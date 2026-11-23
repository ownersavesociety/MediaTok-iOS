import Foundation
import SwiftSignalKit
import MTCore

/// The remote source of registration dates, Swiftgram's `SGAPI.getSGAPIRegDate` in MediaTok's
/// architecture: one `GET`, through `MTNetwork` (ephemeral session, the user's SOCKS5 proxy, nothing
/// sent while an MTProxy / WEB proxy is on), 10 s like Swiftgram.
///
/// **Off:** there is no address. Swiftgram's server and its `@SwiftgramBot` token are not used
///, so with `baseURL == nil` no request is ever made.
/// A server the owner gives later is set here; the contract is `MTRegDateRemoteResponse`. Such a
/// server learns the ID of every profile opened, which the explanation then says.
enum MTRegDateAPI {
    /// The server's base address (`https://…`); nil = the source is off.
    static let baseURL: URL? = nil
    /// DeviceCheck / App Attest are not done now, so there are none.
    static let credentials = MTRegDateAPICredentials.none
    static let requestTimeout: Double = 10.0
    static let maxResponseBytes = 4096

    static var isEnabled: Bool {
        return MTRegDateAPI.baseURL != nil
    }

    /// The answer for `userId`, nil on any failure. Without an address: nil at once, no network.
    static func fetch(userId: Int64, now: Int32) -> Signal<MTRegDateRemoteEntry?, NoError> {
        guard let baseURL = MTRegDateAPI.baseURL, userId > 0 else {
            return .single(nil)
        }
        // `MTNetwork` sends no custom headers yet (MediaTok spec): a server that needs
        // credentials is not asked rather than asked without them.
        if !MTRegDateAPI.credentials.headers.isEmpty {
            return .single(nil)
        }
        let request = MTNetworkRequest(url: MTRegDateRemoteResponse.url(base: baseURL, userId: userId), maxBytes: MTRegDateAPI.maxResponseBytes)
        return MTNetwork.shared.fetch(request)
        |> map { response -> MTRegDateRemoteEntry? in
            guard let data = response.data else {
                return nil
            }
            return MTRegDateRemoteResponse.parse(data, now: now, fetched: now)
        }
        |> `catch` { _ -> Signal<MTRegDateRemoteEntry?, NoError> in
            return .single(nil)
        }
        |> timeout(MTRegDateAPI.requestTimeout, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
    }
}
