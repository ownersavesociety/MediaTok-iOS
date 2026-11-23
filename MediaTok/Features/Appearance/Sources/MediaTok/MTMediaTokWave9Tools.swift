import Foundation
import UIKit
import CryptoKit
import CFNetwork
import Security
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ItemListUI
import ContextUI
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

/// MediaTok Wave 9 (Roadmap Wave 3 — Network, VPN Slot, Unlimited Accounts, Sync v2 & Security):
/// - #401 + #402 Universal VPN Slot (for user's future custom VPN/subscription) + Split Tunneling domain rules
/// - #422 Unlimited Accounts (999,999 in MTAccountLimit) + Per-Account Proxy Manager (`tg://proxy` / SOCKS5)
/// - #423 One-Click Clone MediaTok Settings & Profile across all connected accounts
/// - #495 + #409 MediaTok Sync v2 (HMAC-SHA256 owner signature + backup custom mirror)
/// - #406 + #415 Telegram DC1–DC5 Speedtest + Live DC & Connection Monitor
/// - #417 DNS-over-HTTPS (DoH) resolver for media hosts (Cloudflare / Google)
/// - #418 Auto-Retry 4K Banners (integrated in MTDiscordProfileStore.downloadLimitedData)
/// - #420 + #421 In-App GitHub Release & SHA-256 Update Verifier
public enum MTMediaTokWave9Tools {
    private static let vpnConfigKey = "mediatok.vpn.custom_uri.v1"
    private static let splitTunnelEnabledKey = "mediatok.vpn.split_tunnel.enabled.v1"
    private static let splitTunnelDomainsKey = "mediatok.vpn.split_tunnel.domains.v1"
    private static let accountProxiesKey = "mediatok.accounts.proxies.v1"
    private static let syncEd25519PrivKey = "mediatok.sync.v2.ed25519_priv.v1"
    private static let syncTofuKeysKey = "mediatok.sync.v2.tofu_pubkeys.v1"
    private static let syncMirrorKey = "mediatok.sync.v2.custom_mirror.v1"
    private static let dohEnabledKey = "mediatok.network.doh.enabled.v1"
    private static let dohProviderKey = "mediatok.network.doh.provider.v1"
    public static let vlessRunningPortDefaultsKey = "mediatok.vless.running_port.v1"
    public static let applyVpnUriNotification = Notification.Name("mediatok.vpn.apply_uri")

    private static let splitProxyLock = NSLock()
    private static var cachedProxyKey: String = ""
    private static var cachedProxySession: URLSession?
    private static let syncCryptoLock = NSLock()

    // MARK: - Keychain Secret Storage (VPN URI & Per-Account Proxies)

    private static let secretKeychainService = "org.mediatok.wave9.secrets"

    private static func keychainLoadData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretKeychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func keychainSaveData(_ data: Data?, account: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretKeychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        guard let data, !data.isEmpty else { return }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretKeychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        _ = SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - #401 / #402 VPN Slot & Split Tunneling

    public static var customVpnUri: String {
        get {
            if let data = keychainLoadData(account: vpnConfigKey),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            if let legacy = UserDefaults.standard.string(forKey: vpnConfigKey), !legacy.isEmpty {
                keychainSaveData(Data(legacy.utf8), account: vpnConfigKey)
                UserDefaults.standard.removeObject(forKey: vpnConfigKey)
                return legacy
            }
            return ""
        }
        set {
            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.removeObject(forKey: vpnConfigKey)
            keychainSaveData(clean.isEmpty ? nil : Data(clean.utf8), account: vpnConfigKey)
        }
    }

    public static var isSplitTunnelEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: MTMediaTokWave9Tools.splitTunnelEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: MTMediaTokWave9Tools.splitTunnelEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave9Tools.splitTunnelEnabledKey) }
    }

    public static var splitTunnelDomains: [String] {
        get {
            if let arr = UserDefaults.standard.stringArray(forKey: MTMediaTokWave9Tools.splitTunnelDomainsKey), !arr.isEmpty {
                return arr
            }
            return ["telegram.org", "t.me", "catbox.moe", "files.catbox.moe", "ntfy.sh", "lrclib.net"]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: MTMediaTokWave9Tools.splitTunnelDomainsKey)
        }
    }

    private static func clearCachedProxySessionLocked() {
        if let old = cachedProxySession {
            cachedProxySession = nil
            cachedProxyKey = ""
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5.0) {
                old.finishTasksAndInvalidate()
            }
        }
    }

    /// Returns a URLSession routed via the active local VLESS/Xray SOCKS5 loopback proxy
    /// when Split Tunneling matches the URL host, otherwise `URLSession.shared`.
    public static func urlSession(for url: URL) -> URLSession {
        guard MTMediaTokWave9Tools.isSplitTunnelEnabled,
              let host = url.host?.lowercased() else {
            splitProxyLock.lock()
            clearCachedProxySessionLocked()
            splitProxyLock.unlock()
            return URLSession.shared
        }
        let port = UserDefaults.standard.integer(forKey: MTMediaTokWave9Tools.vlessRunningPortDefaultsKey)
        guard (1024 ... 65535).contains(port) else {
            splitProxyLock.lock()
            clearCachedProxySessionLocked()
            splitProxyLock.unlock()
            return URLSession.shared
        }
        let matches = MTMediaTokWave9Tools.splitTunnelDomains.contains { domain in
            let d = domain.lowercased()
            return host == d || host.hasSuffix(".\(d)")
        }
        guard matches,
              case let .socks5(proxyHost, proxyPort, username, password)? = MTNetwork.shared.proxyProvider?(),
              proxyHost == "127.0.0.1", proxyPort == port,
              let username, !username.isEmpty, let password, !password.isEmpty else {
            return URLSession.shared
        }
        let cacheKey = "\(proxyPort):\(username):\(password)"
        splitProxyLock.lock()
        defer { splitProxyLock.unlock() }
        if let existing = cachedProxySession, cachedProxyKey == cacheKey {
            return existing
        }
        if let old = cachedProxySession {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5.0) {
                old.finishTasksAndInvalidate()
            }
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [
            "SOCKSEnable": 1,
            "SOCKSProxy": proxyHost,
            "SOCKSPort": proxyPort,
            kCFStreamPropertySOCKSVersion as String: kCFStreamSocketSOCKSVersion5 as String,
            kCFStreamPropertySOCKSUser as String: username,
            kCFStreamPropertySOCKSPassword as String: password
        ]
        let session = URLSession(configuration: cfg)
        cachedProxyKey = cacheKey
        cachedProxySession = session
        return session
    }

    // MARK: - #417 DoH (DNS-over-HTTPS)

    public static var isDohEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave9Tools.dohEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave9Tools.dohEnabledKey) }
    }

    /// "cloudflare" or "google"
    public static var dohProvider: String {
        get { return UserDefaults.standard.string(forKey: MTMediaTokWave9Tools.dohProviderKey) ?? "cloudflare" }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave9Tools.dohProviderKey) }
    }

    // MARK: - #495 / #409 MediaTok Sync v2 (Ed25519 Asymmetric Signature + TOFU + Backup Mirror)

    public static var customSyncMirrorBase: String {
        get { return UserDefaults.standard.string(forKey: MTMediaTokWave9Tools.syncMirrorKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: MTMediaTokWave9Tools.syncMirrorKey) }
    }

    public static func customSyncMirrorURL(forTopic topic: String) -> URL? {
        let base = MTMediaTokWave9Tools.customSyncMirrorBase
        guard !base.isEmpty, base.hasPrefix("https://") else { return nil }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: "\(trimmed)/\(topic)")
    }

    private static let syncKeychainService = "org.mediatok.sync.v2"

    private static func readKeychainData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: MTMediaTokWave9Tools.syncKeychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }

    private static func writeKeychainData(_ data: Data, account: String) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: MTMediaTokWave9Tools.syncKeychainService,
            kSecAttrAccount as String: account
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private static func ensureEd25519Key(dialogId: Int64? = nil) -> Curve25519.Signing.PrivateKey {
        MTMediaTokWave9Tools.syncCryptoLock.lock()
        defer { MTMediaTokWave9Tools.syncCryptoLock.unlock() }

        let account: String
        let fallbackDefaultsKey: String
        if let dialogId, dialogId != 0 {
            account = "mediatok.sync.v2.ed25519.\(dialogId)"
            fallbackDefaultsKey = "\(MTMediaTokWave9Tools.syncEd25519PrivKey).\(dialogId)"
        } else {
            account = "mediatok.sync.v2.ed25519.default"
            fallbackDefaultsKey = MTMediaTokWave9Tools.syncEd25519PrivKey
        }

        if let raw = MTMediaTokWave9Tools.readKeychainData(account: account),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            return key
        }

        if let b64 = UserDefaults.standard.string(forKey: fallbackDefaultsKey),
           let raw = Data(base64Encoded: b64),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            if MTMediaTokWave9Tools.writeKeychainData(raw, account: account) {
                UserDefaults.standard.removeObject(forKey: fallbackDefaultsKey)
            }
            return key
        }

        let key = Curve25519.Signing.PrivateKey()
        let raw = key.rawRepresentation
        if !MTMediaTokWave9Tools.writeKeychainData(raw, account: account) {
            UserDefaults.standard.set(raw.base64EncodedString(), forKey: fallbackDefaultsKey)
        }
        return key
    }

    public static func syncOwnerPublicKeyBase64(dialogId: Int64? = nil) -> String {
        return MTMediaTokWave9Tools.ensureEd25519Key(dialogId: dialogId).publicKey.rawRepresentation.base64EncodedString()
    }

    public static func syncOwnerKeyFingerprint(dialogId: Int64? = nil) -> String {
        let pub = MTMediaTokWave9Tools.ensureEd25519Key(dialogId: dialogId).publicKey.rawRepresentation
        let digest = SHA256.hash(data: pub)
        return digest.prefix(6).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    public static func signSyncPayload(_ material: String, dialogId: Int64? = nil) -> String {
        return MTMediaTokWave9Tools.signSyncPayloadData(Data(material.utf8), dialogId: dialogId)
    }

    public static func signSyncPayloadData(_ data: Data, dialogId: Int64? = nil) -> String {
        let key = MTMediaTokWave9Tools.ensureEd25519Key(dialogId: dialogId)
        guard let sig = try? key.signature(for: data) else { return "" }
        return sig.base64EncodedString()
    }

    /// Verifies an incoming Sync v2 Ed25519 signature over canonical `Data` with TOFU pinning per `dialogId`.
    public static func verifySyncSignatureData(dialogId: Int64, material: Data, signatureBase64: String, publicKeyBase64: String) -> Bool {
        guard !signatureBase64.isEmpty, !publicKeyBase64.isEmpty else {
            return false
        }
        MTMediaTokWave9Tools.syncCryptoLock.lock()
        defer { MTMediaTokWave9Tools.syncCryptoLock.unlock() }

        let keyId = "\(dialogId)"
        var pinnedMap = UserDefaults.standard.dictionary(forKey: MTMediaTokWave9Tools.syncTofuKeysKey) as? [String: String] ?? [:]
        if let pinnedPub = pinnedMap[keyId], pinnedPub != publicKeyBase64 {
            return false
        }
        guard let pubData = Data(base64Encoded: publicKeyBase64),
              let sigData = Data(base64Encoded: signatureBase64),
              let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData),
              pubKey.isValidSignature(sigData, for: material) else {
            return false
        }
        if pinnedMap[keyId] == nil {
            pinnedMap[keyId] = publicKeyBase64
            UserDefaults.standard.set(pinnedMap, forKey: MTMediaTokWave9Tools.syncTofuKeysKey)
        }
        return true
    }

    /// Verifies an incoming Sync v2 Ed25519 signature with TOFU (Trust On First Use) pinning per `dialogId`.
    /// Returns `true` for legacy unsigned payloads ONLY if no Ed25519 key was previously pinned for `dialogId`.
    public static func verifySyncSignature(dialogId: Int64, material: String, signatureBase64: String?, publicKeyBase64: String?) -> Bool {
        guard let sigB64 = signatureBase64, !sigB64.isEmpty,
              let pubB64 = publicKeyBase64, !pubB64.isEmpty else {
            MTMediaTokWave9Tools.syncCryptoLock.lock()
            defer { MTMediaTokWave9Tools.syncCryptoLock.unlock() }
            let keyId = "\(dialogId)"
            let pinnedMap = UserDefaults.standard.dictionary(forKey: MTMediaTokWave9Tools.syncTofuKeysKey) as? [String: String] ?? [:]
            // Reject unsigned updates if this peer already published an Ed25519-signed Sync v2 profile (downgrade protection)
            return pinnedMap[keyId] == nil
        }
        return MTMediaTokWave9Tools.verifySyncSignatureData(dialogId: dialogId, material: Data(material.utf8), signatureBase64: sigB64, publicKeyBase64: pubB64)
    }

    // MARK: - Registration

    public static func register() {
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave9Tools.interceptCommands(request)
        }, order: 30)
    }

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let lower = raw.lowercased()

        if lower == ".dc" || lower == ".speedtest" || lower == ".ping" {
            request.replace(ChatTextInputState())
            MTMediaTokWave9Tools.presentDcSpeedtest(context: request.context)
            return true
        }
        if lower == ".vpn" || lower == ".network" {
            request.replace(ChatTextInputState())
            MTMediaTokWave9Tools.presentWave3NetworkHub(context: request.context)
            return true
        }
        if lower == ".update" || lower == ".sha256" {
            request.replace(ChatTextInputState())
            MTMediaTokWave9Tools.checkGitHubReleaseWithSha256(context: request.context)
            return true
        }
        return false
    }

    // MARK: - Wave 3 Network & Security Hub

    public static func presentWave3NetworkHub(context: AccountContext) {
        let controller = mtMakeNativeWave3NetworkHubController(context: context)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #406 / #415 DC1-DC5 Speedtest Launcher

    public static func presentDcSpeedtest(context: AccountContext) {
        DispatchQueue.main.async {
            let controller = mtMakeNativeDcSpeedtestController(context: context)
            mtPushNativeController(controller, context: context)
        }
    }

    // MARK: - #401 / #402 VPN Slot & Split Tunneling UI

    fileprivate static func presentVpnSlotSheet(context: AccountContext) {
        let hasUri = !MTMediaTokWave9Tools.customVpnUri.isEmpty
        let splitState = MTMediaTokWave9Tools.isSplitTunnelEnabled ? "ВКЛ" : "ВЫКЛ"
        let domainsCount = MTMediaTokWave9Tools.splitTunnelDomains.count
        mtPresentNativeActionSheet(
            context: context,
            title: "VPN-слот: \(hasUri ? "Конфиг задан" : "Не задан") · Split Tunneling: \(splitState) (\(domainsCount) доменов)",
            buttons: [
                ("Вставить ссылку/подписку VPN (VLESS/WG/URL)", false, {
                    mtPresentNativePrompt(
                        context: context,
                        title: "VPN-конфиг",
                        subtitle: "Поддерживается vless://, vmess://, ss://, wg:// или https:// подписка:",
                        value: MTMediaTokWave9Tools.customVpnUri,
                        placeholder: "vless://... или https://...",
                        characterLimit: 512,
                        apply: { raw in
                            let val = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            MTMediaTokWave9Tools.customVpnUri = val
                            if !val.isEmpty {
                                NotificationCenter.default.post(name: MTMediaTokWave9Tools.applyVpnUriNotification, object: nil, userInfo: ["uri": val])
                            }
                            mtPresentNativeToast(context: context, text: val.isEmpty ? "VPN-слот очищен" : "VPN-конфиг сохранён")
                        }
                    )
                }),
                (MTMediaTokWave9Tools.isSplitTunnelEnabled ? "Выключить Split Tunneling" : "Включить Split Tunneling", false, {
                    MTMediaTokWave9Tools.isSplitTunnelEnabled.toggle()
                    mtPresentNativeToast(context: context, text: "Split Tunneling: \(MTMediaTokWave9Tools.isSplitTunnelEnabled ? "ВКЛ" : "ВЫКЛ")")
                }),
                ("Редактировать домены Split Tunneling", false, {
                    mtPresentNativePrompt(
                        context: context,
                        title: "Домены Split Tunneling",
                        subtitle: "Укажите домены через запятую:",
                        value: MTMediaTokWave9Tools.splitTunnelDomains.joined(separator: ", "),
                        placeholder: "telegram.org, catbox.moe, ntfy.sh",
                        characterLimit: 512,
                        apply: { raw in
                            let parsed = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                            if !parsed.isEmpty {
                                MTMediaTokWave9Tools.splitTunnelDomains = parsed
                                mtPresentNativeToast(context: context, text: "Сохранено доменов: \(parsed.count)")
                            }
                        }
                    )
                })
            ]
        )
    }

    // MARK: - #422 Per-Account Proxy Manager

    private static func loadAccountProxies() -> [String: String] {
        if let data = keychainLoadData(account: accountProxiesKey),
           let map = (try? JSONDecoder().decode([String: String].self, from: data)) {
            return map
        }
        if let legacy = UserDefaults.standard.dictionary(forKey: accountProxiesKey) as? [String: String], !legacy.isEmpty {
            saveAccountProxies(legacy)
            UserDefaults.standard.removeObject(forKey: accountProxiesKey)
            return legacy
        }
        return [:]
    }

    private static func saveAccountProxies(_ map: [String: String]) {
        UserDefaults.standard.removeObject(forKey: accountProxiesKey)
        if map.isEmpty {
            keychainSaveData(nil, account: accountProxiesKey)
        } else if let data = try? JSONEncoder().encode(map) {
            keychainSaveData(data, account: accountProxiesKey)
        }
    }

    fileprivate static func presentAccountProxyManager(context: AccountContext) {
        let _ = (context.sharedContext.activeAccountsWithInfo
            |> take(1)
            |> deliverOnMainQueue).startStandalone(next: { (_, accounts) in
                let proxies = MTMediaTokWave9Tools.loadAccountProxies()
                let buttons: [(String, Bool, () -> Void)] = accounts.map { acc in
                    let key = "\(acc.account.id.mt.rawValue)"
                    let title = acc.peer.debugDisplayTitle
                    let hasProxy = !(proxies[key]?.isEmpty ?? true)
                    let label = hasProxy ? "\(title) · Прокси задан" : title
                    return (label, false, {
                        mtPresentNativePrompt(
                            context: context,
                            title: "Прокси для \(title)",
                            subtitle: "Вставьте ссылку tg://proxy?server=... или host:port (оставьте пустым для удаления):",
                            value: proxies[key] ?? "",
                            placeholder: "tg://proxy?server=...&port=443&secret=...",
                            characterLimit: 256,
                            apply: { raw in
                                var updated = MTMediaTokWave9Tools.loadAccountProxies()
                                let val = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                if val.isEmpty {
                                    updated.removeValue(forKey: key)
                                } else {
                                    updated[key] = val
                                }
                                MTMediaTokWave9Tools.saveAccountProxies(updated)
                                mtPresentNativeToast(context: context, text: val.isEmpty ? "Прокси удалён" : "Прокси привязан к \(title)")
                            }
                        )
                    })
                }
                mtPresentNativeActionSheet(
                    context: context,
                    title: "Прокси по аккаунтам (подключено: \(accounts.count))",
                    buttons: buttons
                )
            })
    }

    // MARK: - #423 Clone Settings & Profile to All Connected Accounts

    public static func cloneSettingsToAllAccounts(context: AccountContext) {
        let sourcePeerId = context.account.peerId
        let sourceAccountId = context.account.id.mt
        let sourceProfile = MTDiscordProfileStore.shared.profile(for: sourcePeerId)
        let sourceVisual = MTVisualProfileStore.shared.override(for: sourcePeerId.mtKey)
        let exportedSettings = MTSettingsStore.shared.exportData(accounts: [sourceAccountId])
        let _ = (context.sharedContext.activeAccountsWithInfo
            |> take(1)
            |> deliverOnMainQueue).startStandalone(next: { (_, accounts) in
                let others = accounts.filter { $0.account.peerId != sourcePeerId }
                guard !others.isEmpty else {
                    MTMediaTokWave5Tools.showToast(context: context, text: "Подключён только 1 аккаунт — клонировать некуда")
                    return
                }
                let targets: [(peerId: PeerId, accountId: MTAccountID)] = others.map { ($0.account.peerId, $0.account.id.mt) }
                DispatchQueue.global(qos: .userInitiated).async {
                    var clonedCount = 0
                    for target in targets {
                        let dstPeerId = target.peerId
                        let dstAccountId = target.accountId

                        // 1) Clone per-account MTSettingsStore settings
                        if let diff = try? MTSettingsStore.shared.importPreview(exportedSettings, accountMapping: [sourceAccountId: dstAccountId]) {
                            MTSettingsStore.shared.applyImport(diff)
                        }

                        // 2) Clone visual profile override (bio/name/badge/worn gift), preserving destination's own local/remote avatar
                        if var cleanVisual = sourceVisual {
                            let existingDst = MTVisualProfileStore.shared.override(for: dstPeerId.mtKey)
                            cleanVisual.avatarFileName = existingDst?.avatarFileName ?? ""
                            cleanVisual.avatarWidth = existingDst?.avatarWidth ?? 0
                            cleanVisual.avatarHeight = existingDst?.avatarHeight ?? 0
                            cleanVisual.avatarFileId = existingDst?.avatarFileId ?? 0
                            cleanVisual.avatarVideoFileName = existingDst?.avatarVideoFileName ?? ""
                            cleanVisual.avatarVideoFileId = existingDst?.avatarVideoFileId ?? 0
                            cleanVisual.remotePhotoUrl = existingDst?.remotePhotoUrl ?? ""
                            cleanVisual.remoteVideoUrl = existingDst?.remoteVideoUrl ?? ""
                            cleanVisual.remoteUpdatedAt = existingDst?.remoteUpdatedAt ?? 0
                            MTVisualProfileStore.shared.setOverride(cleanVisual, for: dstPeerId.mtKey)
                        }

                        // 3) Deep-copy Discord profile + duplicate media files so accounts never share/delete each other's files
                        if let sourceProfile {
                            var copy = sourceProfile
                            copy.bannerFileName = ""
                            if let bannerUrl = MTDiscordProfileStore.shared.bannerFileURL(for: sourceProfile),
                               let data = try? Data(contentsOf: bannerUrl),
                               let newBanner = MTDiscordProfileStore.shared.saveBannerData(data, for: dstPeerId) {
                                copy.bannerFileName = newBanner
                            }
                            copy.musicFileName = ""
                            if sourceProfile.musicPlaylist.isEmpty,
                               let musicUrl = MTDiscordProfileStore.shared.musicFileURL(for: sourceProfile),
                               let data = try? Data(contentsOf: musicUrl),
                               let newMusic = MTDiscordProfileStore.shared.saveMusicData(data, ext: musicUrl.pathExtension, for: dstPeerId) {
                                copy.musicFileName = newMusic
                            }
                            copy.voiceBioFileName = ""
                            if let vbioUrl = MTDiscordProfileStore.shared.voiceBioFileURL(for: sourceProfile),
                               let data = try? Data(contentsOf: vbioUrl),
                               let newVbio = MTDiscordProfileStore.shared.saveVoiceBioData(data, ext: vbioUrl.pathExtension, for: dstPeerId) {
                                copy.voiceBioFileName = newVbio
                            }
                            var clonedTracks: [MTProfileTrack] = []
                            for track in sourceProfile.musicPlaylist {
                                var tCopy = track
                                tCopy.fileName = ""
                                if let tUrl = MTDiscordProfileStore.shared.trackFileURL(track),
                                   let tData = try? Data(contentsOf: tUrl),
                                   let newTrackFile = MTDiscordProfileStore.shared.saveMusicData(tData, ext: tUrl.pathExtension, for: dstPeerId) {
                                    tCopy.fileName = newTrackFile
                                }
                                clonedTracks.append(tCopy)
                            }
                            copy.musicPlaylist = clonedTracks
                            copy.updatedAt = Int64(Date().timeIntervalSince1970)
                            MTDiscordProfileStore.shared.setProfile(copy, for: dstPeerId, publishGlobally: false)
                            clonedCount += 1
                        }
                    }
                    let finalClonedCount = clonedCount
                    DispatchQueue.main.async {
                        MTMediaTokWave5Tools.showToast(context: context, text: "📋 Настройки, медиа и профиль клонированы на \(targets.count) акк. (профилей: \(finalClonedCount))")
                    }
                }
            })
    }

    // MARK: - #495 / #409 MediaTok Sync v2 UI

    fileprivate static func presentSyncV2Sheet(context: AccountContext) {
        let ownDialogId = context.account.peerId.id._internalGetInt64Value()
        let fp = MTMediaTokWave9Tools.syncOwnerKeyFingerprint(dialogId: ownDialogId)
        let mirror = MTMediaTokWave9Tools.customSyncMirrorBase.isEmpty ? "Только ntfy.sh" : MTMediaTokWave9Tools.customSyncMirrorBase
        mtPresentNativePrompt(
            context: context,
            title: "MediaTok Sync v2 (Ed25519)",
            subtitle: "Ключ владельца: \(fp) · Текущее зеркало: \(mirror). Укажите URL резервного ntfy-сервера (https://...):",
            value: MTMediaTokWave9Tools.customSyncMirrorBase,
            placeholder: "https://ntfy.my-server.com",
            characterLimit: 256,
            apply: { raw in
                let val = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                MTMediaTokWave9Tools.customSyncMirrorBase = val
                mtPresentNativeToast(context: context, text: val.isEmpty ? "Используется только ntfy.sh" : "Резервное зеркало Sync v2 сохранено")
            }
        )
    }

    // MARK: - #417 DoH (DNS-over-HTTPS) UI & Live Test

    fileprivate static func presentDohSheet(context: AccountContext) {
        let st = MTMediaTokWave9Tools.isDohEnabled ? "ВКЛ (\(MTMediaTokWave9Tools.dohProvider))" : "ВЫКЛ"
        mtPresentNativeActionSheet(
            context: context,
            title: "DNS-over-HTTPS (DoH) · Статус: \(st)",
            buttons: [
                (MTMediaTokWave9Tools.isDohEnabled ? "Выключить DoH" : "Включить DoH", false, {
                    MTMediaTokWave9Tools.isDohEnabled.toggle()
                    mtPresentNativeToast(context: context, text: "DoH: \(MTMediaTokWave9Tools.isDohEnabled ? "ВКЛ" : "ВЫКЛ")")
                }),
                ("Провайдер: Cloudflare (1.1.1.1)", false, {
                    MTMediaTokWave9Tools.isDohEnabled = true
                    MTMediaTokWave9Tools.dohProvider = "cloudflare"
                    mtPresentNativeToast(context: context, text: "DoH: Cloudflare 1.1.1.1")
                }),
                ("Провайдер: Google (8.8.8.8)", false, {
                    MTMediaTokWave9Tools.isDohEnabled = true
                    MTMediaTokWave9Tools.dohProvider = "google"
                    mtPresentNativeToast(context: context, text: "DoH: Google 8.8.8.8")
                }),
                ("Проверить резолвинг catbox.moe через DoH", false, {
                    MTMediaTokWave9Tools.testDohResolve(host: "catbox.moe", context: context)
                })
            ]
        )
    }

    private static func testDohResolve(host: String, context: AccountContext) {
        let endpoint = MTMediaTokWave9Tools.dohProvider == "google"
            ? "https://dns.google/resolve?name=\(host)&type=A"
            : "https://cloudflare-dns.com/dns-query?name=\(host)&type=A"
        guard let url = URL(string: endpoint) else { return }
        var req = URLRequest(url: url, timeoutInterval: 8.0)
        req.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let answers = json["Answer"] as? [[String: Any]],
                      let ip = answers.first(where: { ($0["type"] as? Int) == 1 })?["data"] as? String else {
                    mtPresentNativeToast(context: context, text: "DoH: не удалось разрешить \(host)")
                    return
                }
                mtPresentNativeToast(context: context, text: "DoH (\(MTMediaTokWave9Tools.dohProvider)): \(host) → \(ip)")
            }
        }.resume()
    }

    // MARK: - #420 / #421 GitHub Release + SHA-256 Update Verifier

    public static func checkGitHubReleaseWithSha256(context: AccountContext) {
        mtPresentNativeToast(context: context, text: "Проверяю последний релиз MediaTok на GitHub...")
        guard let url = URL(string: "https://api.github.com/repos/ownersavesociety/MediaTok-iOS/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12.0)
        req.setValue("MediaTok-iOS/\(MTMediaTokWave7Tools.currentBuildNumber)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    mtPresentNativeToast(context: context, text: "Не удалось получить релиз GitHub")
                    return
                }
                let assets = (json["assets"] as? [[String: Any]]) ?? []
                let ipa = assets.first(where: { (($0["name"] as? String) ?? "").hasSuffix(".ipa") })
                let sizeBytes = (ipa?["size"] as? Int64) ?? 0
                let sizeMB = String(format: "%.1f МБ", Double(sizeBytes) / 1_048_576.0)
                let downloadUrl = (ipa?["browser_download_url"] as? String) ?? ""
                let body = (json["body"] as? String) ?? ""
                let shaLine: String
                if let range = body.range(of: "[A-Fa-f0-9]{64}", options: .regularExpression) {
                    shaLine = String(body[range]).uppercased()
                } else {
                    shaLine = "Доступен после скачивания"
                }

                let details = "Текущая сборка: b\(MTMediaTokWave7Tools.currentBuildNumber)\nРазмер IPA: \(sizeMB)\nSHA-256: \(shaLine)"
                if !downloadUrl.isEmpty {
                    mtPresentNativeAlert(
                        context: context,
                        title: "Последний релиз: \(tag)",
                        text: details,
                        confirmTitle: "Скопировать ссылку .ipa",
                        destructive: false,
                        confirmAction: {
                            UIPasteboard.general.string = downloadUrl
                            mtPresentNativeToast(context: context, text: "Ссылка на \(tag) скопирована")
                        }
                    )
                } else {
                    mtPresentNativeAlert(context: context, title: "Последний релиз: \(tag)", text: details)
                }
            }
        }.resume()
    }
}

// MARK: - Native Wave 3 Network & Security Hub Controller

private func mtMakeNativeWave3NetworkHubController(context: AccountContext) -> ViewController {
    let modelSignal: Signal<MTNativeScreenModel, NoError> = .single(0)
    |> map { _ in
        var model = MTNativeScreenModel(title: "Сеть, VPN и Синхронизация")
        let dcId = context.account.network.datacenterId
        let ownDialogId = context.account.peerId.id._internalGetInt64Value()
        let vpnLabel = MTMediaTokWave9Tools.customVpnUri.isEmpty ? "Свободен" : "Задан"
        let dohLabel = MTMediaTokWave9Tools.isDohEnabled ? MTMediaTokWave9Tools.dohProvider : "Выкл"

        model.sections.append([
            .init(id: "n_hdr", kind: .header("Сеть и прокси (DC\(dcId))")),
            .init(id: "dc_speed", kind: .disclosure(title: "Спидтест DC1–DC5 и пинг CDN", label: "Открыть", icon: .system("antenna.radiowaves.left.and.right"), enabled: true)),
            .init(id: "vpn_slot", kind: .disclosure(title: "VPN-слот и Split Tunneling", label: vpnLabel, icon: .system("shield.lefthalf.filled"), enabled: true)),
            .init(id: "acc_proxy", kind: .disclosure(title: "Прокси по аккаунтам", label: "Настроить", icon: .system("person.2"), enabled: true)),
            .init(id: "doh_cfg", kind: .disclosure(title: "DNS-over-HTTPS (DoH) для медиа", label: dohLabel, icon: .system("lock.icloud"), enabled: true))
        ])

        model.tap["dc_speed"] = { MTMediaTokWave9Tools.presentDcSpeedtest(context: context) }
        model.tap["vpn_slot"] = { MTMediaTokWave9Tools.presentVpnSlotSheet(context: context) }
        model.tap["acc_proxy"] = { MTMediaTokWave9Tools.presentAccountProxyManager(context: context) }
        model.tap["doh_cfg"] = { MTMediaTokWave9Tools.presentDohSheet(context: context) }

        model.sections.append([
            .init(id: "s_hdr", kind: .header("Аккаунты и обновления")),
            .init(id: "clone_all", kind: .action(title: "Клонировать настройки и профиль на все аккаунты", destructive: false, enabled: true)),
            .init(id: "sync_v2", kind: .disclosure(title: "MediaTok Sync v2 (Ed25519)", label: MTMediaTokWave9Tools.syncOwnerKeyFingerprint(dialogId: ownDialogId), icon: .system("key"), enabled: true)),
            .init(id: "chk_rel", kind: .disclosure(title: "Проверить последний релиз GitHub", label: "SHA-256", icon: .system("checkmark.seal"), enabled: true))
        ])

        model.tap["clone_all"] = { MTMediaTokWave9Tools.cloneSettingsToAllAccounts(context: context) }
        model.tap["sync_v2"] = { MTMediaTokWave9Tools.presentSyncV2Sheet(context: context) }
        model.tap["chk_rel"] = { MTMediaTokWave9Tools.checkGitHubReleaseWithSha256(context: context) }

        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #406 / #415 Native Telegram ItemListController DC1–DC5 Speedtest

private struct MTDcPingTarget: Equatable {
    let id: String
    let title: String
    let region: String
    let url: String
    var ms: Int?
    var failed: Bool = false
}

private func mtMakeNativeDcSpeedtestController(context: AccountContext) -> ItemListController {
    let initialTargets: [MTDcPingTarget] = [
        MTDcPingTarget(id: "dc1", title: "DC1 (Pluto)", region: "Майами, США", url: "https://pluto.web.telegram.org/apiw1"),
        MTDcPingTarget(id: "dc2", title: "DC2 (Venus)", region: "Амстердам, ЕС", url: "https://venus.web.telegram.org/apiw1"),
        MTDcPingTarget(id: "dc3", title: "DC3 (Aurora)", region: "Майами, США", url: "https://aurora.web.telegram.org/apiw1"),
        MTDcPingTarget(id: "dc4", title: "DC4 (Vesta)", region: "Амстердам, ЕС", url: "https://vesta.web.telegram.org/apiw1"),
        MTDcPingTarget(id: "dc5", title: "DC5 (Flora)", region: "Сингапур, Азия", url: "https://flora.web.telegram.org/apiw1"),
        MTDcPingTarget(id: "catbox", title: "Catbox 4K CDN", region: "Баннеры и медиа", url: "https://catbox.moe/"),
        MTDcPingTarget(id: "ntfy", title: "MediaTok Sync (ntfy)", region: "Глобальный синк", url: "https://ntfy.sh/v1/health")
    ]
    let targetsAtomic = Atomic<[MTDcPingTarget]>(value: initialTargets)
    let statePromise = ValuePromise<[MTDcPingTarget]>(initialTargets, ignoreRepeated: true)
    weak var controllerRef: ItemListController?

    let runTests: () -> Void = {
        let reset = targetsAtomic.modify { cur in
            cur.map { t in var c = t; c.ms = nil; c.failed = false; return c }
        }
        statePromise.set(reset)
        for idx in 0 ..< reset.count {
            guard let url = URL(string: reset[idx].url) else { continue }
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 6.0)
            req.httpMethod = "HEAD"
            let started = Date()
            URLSession.shared.dataTask(with: req) { _, response, error in
                let elapsed = max(1, Int(Date().timeIntervalSince(started) * 1000.0))
                let ok = (response != nil && error == nil)
                DispatchQueue.main.async {
                    let updated = targetsAtomic.modify { cur in
                        var next = cur
                        if idx < next.count {
                            next[idx].ms = ok ? elapsed : nil
                            next[idx].failed = !ok
                        }
                        return next
                    }
                    statePromise.set(updated)
                }
            }.resume()
        }
    }

    let dcId = context.account.network.datacenterId
    let model = statePromise.get()
    |> map { targets -> MTNativeScreenModel in
        var screen = MTNativeScreenModel(title: "Спидтест DC1–DC5")
        screen.rightButton = (title: "Повторить", enabled: true, action: { runTests() })

        var rows: [MTNativeRow] = [
            MTNativeRow(id: "h_dc", kind: .header("Активный сервер аккаунта: DC\(dcId)"))
        ]
        for t in targets {
            let label: String
            if t.failed {
                label = "Недоступен"
            } else if let ms = t.ms {
                label = "\(ms) мс"
            } else {
                label = "Замер..."
            }
            rows.append(MTNativeRow(
                id: t.id,
                kind: .disclosure(title: "\(t.title) · \(t.region)", label: label, icon: nil, enabled: true)
            ))
        }
        screen.sections.append(rows)

        screen.sections.append([
            MTNativeRow(id: "h_actions", kind: .header("Подключение Telegram")),
            MTNativeRow(id: "nativeProxy", kind: .action(title: "Нативные прокси Telegram (MTProto / SOCKS5)", destructive: false, enabled: true)),
            MTNativeRow(id: "reconnect", kind: .action(title: "Force Reconnect (переподключить сеть)", destructive: false, enabled: true))
        ])

        screen.tap["nativeProxy"] = {
            let proxyVC = context.sharedContext.makeProxySettingsController(context: context)
            mtPushNativeController(proxyVC, context: context, from: controllerRef)
        }
        screen.tap["reconnect"] = {
            MTMediaTokWave7Tools.forceReconnect(context: context)
        }
        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: model)
    controllerRef = controller
    runTests()
    return controller
}
