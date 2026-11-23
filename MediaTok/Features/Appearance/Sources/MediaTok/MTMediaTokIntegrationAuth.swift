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

// MARK: - Real 1-Tap Sign-In Engine (Steam OpenID 2.0 + Direct Account Web Sign-In + Optional OAuth 2.0 PKCE)

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

    var directLoginURL: URL? {
        switch self {
        case .steam:
            return URL(string: "https://steamcommunity.com/openid/login")
        case .spotify:
            return URL(string: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fwww.spotify.com%2Faccount%2Foverview%2F")
        case .discord:
            return URL(string: "https://discord.com/login?redirect_to=%2Fchannels%2F%40me")
        case .youtube:
            return URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2Faccount")
        case .roblox:
            return URL(string: "https://www.roblox.com/login")
        case .twitch:
            return URL(string: "https://www.twitch.tv/login")
        case .github:
            return URL(string: "https://github.com/login?return_to=https%3A%2F%2Fgithub.com%2Fsettings%2Fprofile")
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
        if !cid.isEmpty {
            self.launchPkceOAuth(platform: platform, clientId: cid, completion: completion)
            return
        }

        // Direct 1-tap sign-in into the user's own account (zero Client ID prompts)
        let vc = MTWebAccountSignInController(platform: platform) { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        presenter.present(nav, animated: true)
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

// MARK: - Direct Account Sign-In Sheet (Discord, Spotify, YouTube, GitHub, Roblox, Twitch — Zero Client ID Prompts)

private final class MTWebAccountSignInController: UIViewController, WKNavigationDelegate {
    private let platform: MTIntegrationPlatform
    private let completion: (Result<String, Error>) -> Void
    private var didComplete = false
    private let webView: WKWebView
    private var pollTimer: Timer?

    init(platform: MTIntegrationPlatform, completion: @escaping (Result<String, Error>) -> Void) {
        self.platform = platform
        self.completion = completion
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        self.pollTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.platform.title
        self.view.backgroundColor = .systemBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Отмена",
            style: .plain,
            target: self,
            action: #selector(self.cancelTapped)
        )
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Привязать",
            style: .done,
            target: self,
            action: #selector(self.bindTapped)
        )

        // Standard Mobile Safari UA so Google/YouTube, Discord, and Spotify allow normal web sign-in
        self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        self.webView.navigationDelegate = self
        self.webView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.webView)
        NSLayoutConstraint.activate([
            self.webView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.webView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.webView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.webView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        if let url = self.platform.directLoginURL {
            self.webView.load(URLRequest(url: url))
        }

        self.pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.attemptExtractPublicIdentity(manualTrigger: false)
        }
    }

    @objc private func cancelTapped() {
        self.finish(.failure(NSError(domain: "MediaTok.AccountSignIn", code: -10, userInfo: [NSLocalizedDescriptionKey: "Вход отменён"])))
    }

    @objc private func bindTapped() {
        self.attemptExtractPublicIdentity(manualTrigger: true)
    }

    private func finish(_ result: Result<String, Error>) {
        guard !self.didComplete else { return }
        self.didComplete = true
        self.pollTimer?.invalidate()
        self.pollTimer = nil
        self.dismiss(animated: true) {
            self.completion(result)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.attemptExtractPublicIdentity(manualTrigger: false)
    }

    private func attemptExtractPublicIdentity(manualTrigger: Bool) {
        guard !self.didComplete else { return }
        let currentURL = self.webView.url?.absoluteString ?? ""
        let lowerURL = currentURL.lowercased()

        // Skip while clearly on a login/auth form unless user manually tapped Bind on a profile URL
        if !manualTrigger {
            if lowerURL.contains("/login") || lowerURL.contains("servicelogin") || lowerURL.contains("accounts.google.com") || lowerURL.contains("accounts.spotify.com") {
                return
            }
        }

        let js: String
        switch self.platform {
        case .spotify:
            js = """
            (function() {
                try {
                    var uLink = document.querySelector('a[href*="/user/"]');
                    if (uLink && uLink.href) {
                        var m = uLink.href.match(/open\\.spotify\\.com\\/user\\/([^/?#]+)/i);
                        var name = (uLink.getAttribute('aria-label') || uLink.textContent || '').trim();
                        if (m && m[1]) {
                            var cleanUrl = 'https://open.spotify.com/user/' + m[1];
                            return (name ? name : m[1]) + '|' + cleanUrl;
                        }
                    }
                    var nextEl = document.getElementById('__NEXT_DATA__');
                    if (nextEl) {
                        var raw = nextEl.textContent || '';
                        var um = raw.match(/"username"\\s*:\\s*"([^"]+)"/);
                        if (um && um[1]) {
                            return um[1] + '|https://open.spotify.com/user/' + encodeURIComponent(um[1]);
                        }
                    }
                    var bodyTxt = document.body ? document.body.innerText : '';
                    var lines = bodyTxt.split('\\n').map(function(s){ return s.trim(); }).filter(Boolean);
                    for (var i = 0; i < lines.length - 1; i++) {
                        if ((lines[i] === 'Username' || lines[i] === 'Имя пользователя') && lines[i+1].length >= 2 && lines[i+1].length <= 64) {
                            var id = lines[i+1];
                            return id + '|https://open.spotify.com/user/' + encodeURIComponent(id);
                        }
                    }
                } catch (e) {}
                return '';
            })();
            """
        case .discord:
            js = """
            (function() {
                try {
                    if (location.pathname.indexOf('/login') !== -1 || location.pathname.indexOf('/register') !== -1) return '';
                    var panels = document.querySelectorAll('[class*="nameTag"], [class*="panelTitleContainer"], section[aria-label] [class*="lineClamp"]');
                    for (var i = 0; i < panels.length; i++) {
                        var t = (panels[i].innerText || '').split('\\n').map(function(s){ return s.trim(); }).filter(Boolean);
                        for (var j = 0; j < t.length; j++) {
                            if (/^[a-z0-9_.]{2,32}$/i.test(t[j]) && t[j].toLowerCase() !== 'online' && t[j].toLowerCase() !== 'idle' && t[j].toLowerCase() !== 'dnd') {
                                return t[j];
                            }
                        }
                    }
                    var avatarBtn = document.querySelector('[aria-label][class*="avatarWrapper"]');
                    if (avatarBtn) {
                        var lbl = (avatarBtn.getAttribute('aria-label') || '').split(',')[0].trim();
                        if (lbl.length >= 2 && lbl.length <= 32) return lbl;
                    }
                } catch (e) {}
                return '';
            })();
            """
        case .youtube:
            js = """
            (function() {
                try {
                    if (location.hostname.indexOf('youtube.com') === -1) return '';
                    var hMatch = location.pathname.match(/^\\/@([A-Za-z0-9_.-]{2,60})/);
                    if (hMatch && hMatch[1]) return '@' + hMatch[1];
                    var cMatch = location.pathname.match(/^\\/channel\\/(UC[A-Za-z0-9_-]{16,40})/);
                    if (cMatch && cMatch[1]) return 'https://www.youtube.com/channel/' + cMatch[1];
                    var links = document.querySelectorAll('a[href*="/@"], a[href*="/channel/UC"]');
                    for (var i = 0; i < links.length; i++) {
                        var href = links[i].getAttribute('href') || '';
                        var m1 = href.match(/\\/@([A-Za-z0-9_.-]{2,60})/);
                        if (m1 && m1[1]) return '@' + m1[1];
                        var m2 = href.match(/\\/channel\\/(UC[A-Za-z0-9_-]{16,40})/);
                        if (m2 && m2[1]) return 'https://www.youtube.com/channel/' + m2[1];
                    }
                    var html = document.documentElement ? document.documentElement.innerHTML : '';
                    var ch = html.match(/"canonicalBaseUrl"\\s*:\\s*"\\/@([A-Za-z0-9_.-]{2,60})"/);
                    if (ch && ch[1]) return '@' + ch[1];
                } catch (e) {}
                return '';
            })();
            """
        case .github:
            js = """
            (function() {
                var meta = document.querySelector('meta[name="user-login"]');
                if (meta && meta.content) return meta.content.trim();
                return '';
            })();
            """
        case .roblox:
            js = """
            (function() {
                var meta = document.querySelector('meta[name="user-data"]');
                if (meta) {
                    var uid = meta.getAttribute('data-userid') || '';
                    if (/^[0-9]+$/.test(uid)) return 'https://www.roblox.com/users/' + uid + '/profile';
                }
                var m = location.pathname.match(/\\/users\\/([0-9]+)/);
                if (m && m[1]) return 'https://www.roblox.com/users/' + m[1] + '/profile';
                return '';
            })();
            """
        case .twitch:
            js = """
            (function() {
                try {
                    var c = document.cookie.match(/twilight-user=([^;]+)/);
                    if (c && c[1]) {
                        var dec = JSON.parse(decodeURIComponent(c[1]));
                        if (dec && dec.login) return String(dec.login);
                    }
                    var m = location.pathname.match(/^\\/([a-zA-Z0-9_]{3,25})\\/?$/);
                    if (m && m[1] && ['login', 'signup', 'directory', 'settings', 'downloads', 'wallet', 'Following'].indexOf(m[1]) === -1) {
                        return m[1];
                    }
                } catch (e) {}
                return '';
            })();
            """
        case .steam:
            js = "''"
        }

        self.webView.evaluateJavaScript(js) { [weak self] raw, _ in
            guard let self, !self.didComplete else { return }
            let found = (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !found.isEmpty {
                self.finish(.success(found))
            } else if manualTrigger {
                // On manual tap, if user navigated to youtube/spotify/discord, guide them to finish login first
                if self.platform == .youtube && !lowerURL.contains("youtube.com/feed/you") && !lowerURL.contains("youtube.com/account") {
                    if let u = URL(string: "https://m.youtube.com/feed/you") {
                        self.webView.load(URLRequest(url: u))
                    }
                } else if self.platform == .spotify && !lowerURL.contains("spotify.com/account") {
                    if let u = URL(string: "https://www.spotify.com/account/overview/") {
                        self.webView.load(URLRequest(url: u))
                    }
                }
            }
        }
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
        self.title = "Steam"
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
