import Foundation
import UIKit
import WebKit
import AuthenticationServices
import CryptoKit
import MTHooks

// MARK: - Authentic Brand Vector Icons (Delegates to Official SVG Paths in MTPeerInfoBrandIcons)

internal enum MTIntegrationBrandIcon {
    static func image(for platform: String, size: CGFloat = 28.0, isDark: Bool = true) -> UIImage {
        return MTPeerInfoBrandIcons.image(for: platform, size: size, isDark: isDark)
    }
}

// MARK: - Real Sign-In Engine (Steam OpenID 2.0 + OAuth 2.0 PKCE)

internal enum MTIntegrationPlatform: String, CaseIterable {
    case steam
    case spotify
    case discord
    case youtube
    case roblox
    case twitch
    case github

    var title: String {
        switch self {
        case .steam: return "Steam"
        case .spotify: return "Spotify"
        case .discord: return "Discord"
        case .youtube: return "YouTube"
        case .roblox: return "Roblox"
        case .twitch: return "Twitch"
        case .github: return "GitHub"
        }
    }

    var redirectUri: String {
        return "mediatok://oauth/\(self.rawValue)"
    }

    var authorizeEndpoint: String {
        switch self {
        case .steam: return "https://steamcommunity.com/openid/login"
        case .spotify: return "https://accounts.spotify.com/authorize"
        case .discord: return "https://discord.com/oauth2/authorize"
        case .youtube: return "https://accounts.google.com/o/oauth2/v2/auth"
        case .roblox: return "https://apis.roblox.com/oauth/v1/authorize"
        case .twitch: return "https://id.twitch.tv/oauth2/authorize"
        case .github: return "https://github.com/login/oauth/authorize"
        }
    }

    var tokenEndpoint: String {
        switch self {
        case .steam: return ""
        case .spotify: return "https://accounts.spotify.com/api/token"
        case .discord: return "https://discord.com/api/oauth2/token"
        case .youtube: return "https://oauth2.googleapis.com/token"
        case .roblox: return "https://apis.roblox.com/oauth/v1/token"
        case .twitch: return "https://id.twitch.tv/oauth2/token"
        case .github: return "https://github.com/login/oauth/access_token"
        }
    }

    var scope: String {
        switch self {
        case .steam: return ""
        case .spotify: return "user-read-private user-read-currently-playing"
        case .discord: return "identify"
        case .youtube: return "https://www.googleapis.com/auth/youtube.readonly"
        case .roblox: return "openid profile"
        case .twitch: return "user:read:email"
        case .github: return "read:user"
        }
    }
}

internal final class MTIntegrationAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = MTIntegrationAuthCoordinator()

    private static let clientIdsKey = "mediatok.oauth.client_ids.v1"
    private var activeSession: ASWebAuthenticationSession?
    private weak var anchorWindow: UIWindow?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let w = self.anchorWindow { return w }
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let w = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            return w
        }
        return ASPresentationAnchor()
    }

    static func clientId(for platform: MTIntegrationPlatform) -> String {
        let dict = (UserDefaults.standard.dictionary(forKey: clientIdsKey) as? [String: String]) ?? [:]
        return (dict[platform.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func setClientId(_ id: String, for platform: MTIntegrationPlatform) {
        var dict = (UserDefaults.standard.dictionary(forKey: clientIdsKey) as? [String: String]) ?? [:]
        dict[platform.rawValue] = id.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(dict, forKey: clientIdsKey)
    }

    func signIn(
        platform: MTIntegrationPlatform,
        from presenter: UIViewController,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        self.anchorWindow = presenter.view.window

        if platform == .steam {
            let vc = MTSteamOpenIdWebViewController { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .pageSheet
            presenter.present(nav, animated: true)
            return
        }

        let cid = Self.clientId(for: platform)
        if cid.isEmpty {
            UIPasteboard.general.string = platform.redirectUri
            let alert = UIAlertController(
                title: "Вход через \(platform.title)",
                message: "Для OAuth 2.0 PKCE нужен публичный Client ID из \(platform.title) Developer Portal.\n\nRedirect URI уже скопирован:\n\(platform.redirectUri)",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.placeholder = "Вставьте Client ID для \(platform.title)"
                tf.autocapitalizationType = .none
                tf.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Войти", style: .default) { [weak self, weak alert] _ in
                let entered = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !entered.isEmpty else { return }
                Self.setClientId(entered, for: platform)
                self?.launchPkceOAuth(platform: platform, clientId: entered, completion: completion)
            })
            presenter.present(alert, animated: true)
            return
        }

        self.launchPkceOAuth(platform: platform, clientId: cid, completion: completion)
    }

    private func launchPkceOAuth(
        platform: MTIntegrationPlatform,
        clientId: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString

        var comps = URLComponents(string: platform.authorizeEndpoint)
        comps?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: platform.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: platform.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authUrl = comps?.url else {
            completion(.failure(NSError(domain: "MediaTok.OAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Некорректный URL авторизации"])))
            return
        }

        let session = ASWebAuthenticationSession(url: authUrl, callbackURLScheme: "mediatok") { [weak self] callbackUrl, error in
            self?.activeSession = nil
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let callbackUrl,
                  let cbComps = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false),
                  let returnedState = cbComps.queryItems?.first(where: { $0.name == "state" })?.value,
                  returnedState == state,
                  let code = cbComps.queryItems?.first(where: { $0.name == "code" })?.value,
                  !code.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MediaTok.OAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Авторизация не подтверждена"])))
                }
                return
            }
            self?.exchangeCodeForProfile(platform: platform, clientId: clientId, code: code, verifier: verifier, completion: completion)
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.activeSession = session
        session.start()
    }

    private func exchangeCodeForProfile(
        platform: MTIntegrationPlatform,
        clientId: String,
        code: String,
        verifier: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let tokenUrl = URL(string: platform.tokenEndpoint) else { return }
        var req = URLRequest(url: tokenUrl, timeoutInterval: 15.0)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        var bodyComps = URLComponents()
        bodyComps.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: platform.redirectUri),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        req.httpBody = bodyComps.percentEncodedQuery?.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err {
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            guard let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  !accessToken.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MediaTok.OAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить токен от \(platform.title)"])))
                }
                return
            }
            Self.fetchVerifiedIdentity(platform: platform, clientId: clientId, accessToken: accessToken, completion: completion)
        }.resume()
    }

    private static func fetchVerifiedIdentity(
        platform: MTIntegrationPlatform,
        clientId: String,
        accessToken: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let endpoint: String
        switch platform {
        case .spotify: endpoint = "https://api.spotify.com/v1/me"
        case .discord: endpoint = "https://discord.com/api/users/@me"
        case .youtube: endpoint = "https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true"
        case .roblox: endpoint = "https://apis.roblox.com/oauth/v1/userinfo"
        case .twitch: endpoint = "https://api.twitch.tv/helix/users"
        case .github: endpoint = "https://api.github.com/user"
        case .steam: return
        }
        guard let url = URL(string: endpoint) else { return }
        var req = URLRequest(url: url, timeoutInterval: 12.0)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("MediaTok/OAuth", forHTTPHeaderField: "User-Agent")
        if platform == .twitch {
            req.setValue(clientId, forHTTPHeaderField: "Client-Id")
        }

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err {
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            guard let data, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MediaTok.OAuth", code: -4, userInfo: [NSLocalizedDescriptionKey: "Пустой ответ профиля \(platform.title)"])))
                }
                return
            }

            var resolvedValue: String?
            switch platform {
            case .spotify:
                let display = (obj["display_name"] as? String) ?? (obj["id"] as? String) ?? ""
                let ext = (obj["external_urls"] as? [String: Any])?["spotify"] as? String ?? ""
                if !ext.isEmpty && !display.isEmpty {
                    resolvedValue = "\(display)|\(ext)"
                } else if !display.isEmpty {
                    resolvedValue = display
                }
            case .discord:
                resolvedValue = (obj["username"] as? String) ?? (obj["global_name"] as? String)
            case .youtube:
                if let items = obj["items"] as? [[String: Any]], let first = items.first {
                    let snippet = first["snippet"] as? [String: Any]
                    if let custom = snippet?["customUrl"] as? String, !custom.isEmpty {
                        resolvedValue = custom
                    } else if let cid = first["id"] as? String, !cid.isEmpty {
                        resolvedValue = "https://www.youtube.com/channel/\(cid)"
                    }
                }
            case .roblox:
                if let sub = obj["sub"] as? String, !sub.isEmpty {
                    resolvedValue = "https://www.roblox.com/users/\(sub)/profile"
                } else if let pref = obj["preferred_username"] as? String, !pref.isEmpty {
                    resolvedValue = pref
                }
            case .twitch:
                if let arr = obj["data"] as? [[String: Any]], let first = arr.first {
                    resolvedValue = first["login"] as? String
                }
            case .github:
                resolvedValue = obj["login"] as? String
            case .steam:
                break
            }

            DispatchQueue.main.async {
                if let val = resolvedValue, !val.isEmpty {
                    completion(.success(val))
                } else {
                    completion(.failure(NSError(domain: "MediaTok.OAuth", code: -5, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать профиль \(platform.title)"])))
                }
            }
        }.resume()
    }

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Real Steam OpenID 2.0 Sign-In Sheet (Zero API Keys, Cryptographic check_authentication)

private final class MTSteamOpenIdWebViewController: UIViewController, WKNavigationDelegate {
    private let completion: (Result<String, Error>) -> Void
    private var didComplete = false
    private let webView = WKWebView(frame: .zero)
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Вход через Steam"
        self.view.backgroundColor = .systemBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Отмена", style: .plain, target: self, action: #selector(self.cancelTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.spinner)

        self.webView.navigationDelegate = self
        self.webView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.webView)
        NSLayoutConstraint.activate([
            self.webView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.webView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.webView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.webView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        var comps = URLComponents(string: "https://steamcommunity.com/openid/login")
        comps?.queryItems = [
            URLQueryItem(name: "openid.ns", value: "http://specs.openid.net/auth/2.0"),
            URLQueryItem(name: "openid.mode", value: "checkid_setup"),
            URLQueryItem(name: "openid.return_to", value: "https://mediatok.local/steam-openid"),
            URLQueryItem(name: "openid.realm", value: "https://mediatok.local/"),
            URLQueryItem(name: "openid.identity", value: "http://specs.openid.net/auth/2.0/identifier_select"),
            URLQueryItem(name: "openid.claimed_id", value: "http://specs.openid.net/auth/2.0/identifier_select")
        ]
        if let url = comps?.url {
            self.spinner.startAnimating()
            self.webView.load(URLRequest(url: url))
        }
    }

    @objc private func cancelTapped() {
        self.finish(.failure(NSError(domain: "MediaTok.SteamOpenID", code: -10, userInfo: [NSLocalizedDescriptionKey: "Вход отменён"])))
    }

    private func finish(_ result: Result<String, Error>) {
        guard !self.didComplete else { return }
        self.didComplete = true
        self.dismiss(animated: true) {
            self.completion(result)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.spinner.stopAnimating()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.host == "mediatok.local" && url.path == "/steam-openid" {
            decisionHandler(.cancel)
            self.verifySteamOpenIdCallback(url)
            return
        }
        decisionHandler(.allow)
    }

    private func verifySteamOpenIdCallback(_ callbackUrl: URL) {
        self.spinner.startAnimating()
        guard let comps = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false),
              let items = comps.queryItems,
              let claimedId = items.first(where: { $0.name == "openid.claimed_id" })?.value,
              let steamId64 = claimedId.split(separator: "/").last.map(String.init),
              !steamId64.isEmpty,
              steamId64.allSatisfy({ $0.isNumber }) else {
            self.finish(.failure(NSError(domain: "MediaTok.SteamOpenID", code: -11, userInfo: [NSLocalizedDescriptionKey: "Steam не вернул идентификатор аккаунта"])))
            return
        }

        // Verify cryptographic OpenID signature directly with Steam
        var verifyItems = items.filter { $0.name != "openid.mode" }
        verifyItems.append(URLQueryItem(name: "openid.mode", value: "check_authentication"))
        var bodyComps = URLComponents()
        bodyComps.queryItems = verifyItems

        guard let verifyUrl = URL(string: "https://steamcommunity.com/openid/login") else { return }
        var req = URLRequest(url: verifyUrl, timeoutInterval: 12.0)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyComps.percentEncodedQuery?.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                guard let self else { return }
                self.spinner.stopAnimating()
                if let err {
                    self.finish(.failure(err))
                    return
                }
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if body.contains("is_valid:true") {
                    self.finish(.success("https://steamcommunity.com/profiles/\(steamId64)"))
                } else {
                    self.finish(.failure(NSError(domain: "MediaTok.SteamOpenID", code: -12, userInfo: [NSLocalizedDescriptionKey: "Подпись Steam не прошла проверку"])))
                }
            }
        }.resume()
    }
}
