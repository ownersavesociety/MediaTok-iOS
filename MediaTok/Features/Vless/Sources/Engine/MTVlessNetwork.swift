import Foundation
import Network
import CFNetwork
import SwiftSignalKit
import MTCore
import MTFeaturesShared

// Network work of the VPN outside the core: downloading a subscription from the user's own panel,
// measuring TCP connect time to servers, and checking that the running tunnel really reaches Telegram.

enum MTVlessFetchError: Error, Equatable {
    case invalidURL
    case network
    case http(Int)
    case tooLarge
    case empty
}

struct MTVlessFetchResult {
    let servers: [MTVlessServer]
    let skipped: Int
    let headers: MTVlessSubscriptionHeaders
}

/// The running core's loopback listener.
struct MTVlessTunnelEndpoint: Equatable {
    let port: Int
    let credentials: MTXrayInboundCredentials

    var route: MTVlessRoute {
        return .socks5(host: "127.0.0.1", port: self.port, username: self.credentials.username, password: self.credentials.password)
    }
}

/// How one subscription request leaves the device.
enum MTVlessRoute: Equatable {
    case direct
    case socks5(host: String, port: Int, username: String?, password: String?)

    /// `URLSession` SOCKS keys (the `kCFNetworkProxiesSOCKS*` names are macOS-only constants; iOS
    /// reads the same strings).
    var proxyDictionary: [AnyHashable: Any]? {
        switch self {
        case .direct:
            return nil
        case let .socks5(host, port, username, password):
            var dictionary: [AnyHashable: Any] = [
                "SOCKSEnable": 1,
                "SOCKSProxy": host,
                "SOCKSPort": port,
                kCFStreamPropertySOCKSVersion as String: kCFStreamSocketSOCKSVersion5 as String
            ]
            if let username, !username.isEmpty {
                dictionary[kCFStreamPropertySOCKSUser as String] = username
            }
            if let password, !password.isEmpty {
                dictionary[kCFStreamPropertySOCKSPassword as String] = password
            }
            return dictionary
        }
    }
}

enum MTVlessSubscriptionFetcher {
    static let maxBytes = 4 << 20

    /// The routes to try, in order:
    /// - the running tunnel (the panel's domain may be blocked), then directly — a refresh is what
    ///   repairs a tunnel whose server is gone;
    /// - otherwise the user's SOCKS5 proxy from Telegram's settings, and nothing else: a request does
    ///   not leave around the proxy the user chose;
    /// - otherwise directly. While Telegram uses an MTProxy or WEB proxy (they can not carry HTTP),
    ///   only a request the user started goes out directly; automatic refreshes wait.
    static func routes(tunnel: MTVlessTunnelEndpoint?, userInitiated: Bool) -> [MTVlessRoute] {
        if let tunnel {
            return [tunnel.route, .direct]
        }
        if let proxy = MTNetwork.shared.proxyProvider?() {
            switch proxy {
            case let .socks5(host, port, username, password):
                let route = MTVlessRoute.socks5(host: host, port: port, username: username, password: password)
                if host == MTNetworkSpoofShared.loopbackHost && port == MTNetworkSpoofSharedSettings.vlessLocalPort.value {
                    // Telegram still points at the VPN's own listener while the core is down.
                    return [route, .direct]
                }
                return [route]
            }
        }
        if !userInitiated, let isDirectAllowed = MTNetwork.shared.isDirectConnectionAllowedProvider, !isDirectAllowed() {
            return []
        }
        return [.direct]
    }

    /// `fetch` over `routes`, moving to the next route only after a network error.
    static func fetch(urlString: String, routes: [MTVlessRoute]) -> Signal<MTVlessFetchResult, MTVlessFetchError> {
        guard let first = routes.first else {
            return .fail(.network)
        }
        let rest = Array(routes.dropFirst())
        return MTVlessSubscriptionFetcher.fetch(urlString: urlString, route: first)
        |> `catch` { error -> Signal<MTVlessFetchResult, MTVlessFetchError> in
            if error == .network && !rest.isEmpty {
                return MTVlessSubscriptionFetcher.fetch(urlString: urlString, routes: rest)
            }
            return .fail(error)
        }
    }

    /// Downloads and parses a subscription over one route. No cookies, no cache, no credential store;
    /// the installation id only when the user switched it on. Never retried with more identity.
    static func fetch(urlString: String, route: MTVlessRoute) -> Signal<MTVlessFetchResult, MTVlessFetchError> {
        return Signal { subscriber in
            let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil else {
                subscriber.putError(.invalidURL)
                return EmptyDisposable
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.urlCredentialStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.timeoutIntervalForRequest = 20.0
            configuration.timeoutIntervalForResource = 40.0
            if let proxyDictionary = route.proxyDictionary {
                configuration.connectionProxyDictionary = proxyDictionary
            }
            let session = URLSession(configuration: configuration)
            var request = URLRequest(url: url)
            request.setValue("MediaTok/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            if MTVlessSettings.sendHwid.value {
                request.setValue(MTVlessSettings.installationId(), forHTTPHeaderField: "x-hwid")
                request.setValue("iOS", forHTTPHeaderField: "x-device-os")
            }
            let task = session.dataTask(with: request, completionHandler: { data, response, error in
                session.finishTasksAndInvalidate()
                if error != nil {
                    subscriber.putError(.network)
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    subscriber.putError(.network)
                    return
                }
                if !(200 ... 299).contains(response.statusCode) {
                    subscriber.putError(.http(response.statusCode))
                    return
                }
                guard let data, !data.isEmpty else {
                    subscriber.putError(.empty)
                    return
                }
                if data.count > MTVlessSubscriptionFetcher.maxBytes {
                    subscriber.putError(.tooLarge)
                    return
                }
                let parsed = MTVlessSubscriptionParser.parse(data)
                if parsed.servers.isEmpty {
                    subscriber.putError(.empty)
                    return
                }
                subscriber.putNext(MTVlessFetchResult(servers: parsed.servers, skipped: parsed.skipped, headers: MTVlessSubscriptionHeaders(headers: response.allHeaderFields)))
                subscriber.putCompletion()
            })
            task.resume()
            return ActionDisposable {
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }
}
