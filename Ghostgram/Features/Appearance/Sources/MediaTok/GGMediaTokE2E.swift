import Foundation
import UIKit
import Security
import Postbox
import TelegramCore
import AccountContext
import ContextUI
import UndoUI
import GGCore
import GGHooks
import GGSettingsUI

/// Optional per-chat AES-256-GCM End-to-End Encryption for MediaTok iOS.
/// - Keys are stored exclusively in iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
///   with automatic migration from legacy UserDefaults.
/// - Keys are derived via 100,000-iteration PBKDF2-HMAC-SHA256 with random 128-bit salt and
///   chat-bound AAD (`🔒MT2:`), preventing cross-chat replay and GPU brute-force.
/// - Decrypted cache & derived keys are purged automatically when entering the background.
enum GGMediaTokE2E {
    private static let legacyDefaultsKey = "mediatok.e2e.keys.v1"
    private static let enabledKey = "mediatok.e2e.enabled.v1"
    private static let keychainService = "org.mediatok.e2e.keys.v2"
    private static let keychainAccount = "chat_keys"

    private static let lock = NSLock()
    private static var cachedKeys: [String: String]?
    private static var decryptCache: [String: String] = [:]
    private static var backgroundObserver: NSObjectProtocol?

    static func register() {
        // 1. Inline `.e2e on <pass>` / `.e2e off` / `.e2e status` interceptor (never leaks passphrase to chat!)
        GGChatScreenHooks.willSendText.register({ request, _ in
            return GGMediaTokE2E.interceptCommand(request)
        }, order: 20)

        // 2. Transparent outgoing AES-256-GCM encryption (runs LAST after chat text fonts, skips sticker/bot commands)
        GGOutgoingHooks.textStages.register({ outgoing, context in
            GGMediaTokE2E.encryptOutgoing(&outgoing, peerId: context.peerId)
        }, order: 950)

        // 3. Transparent live decryption in chat bubbles (runs FIRST in decoration chain!)
        GGMessageDecorationHooks.decorations.register({ decoration, context in
            GGMediaTokE2E.decryptDecoration(&decoration, message: context.message)
        }, order: 40)

        // 4. 1-tap toggle in Send button long-press menu
        GGChatScreenHooks.sendMenuItems.register({ sendContext in
            return GGMediaTokE2E.sendMenuItems(sendContext)
        }, order: 80)

        // 5. 1-tap toggle in Profile "..." menu
        GGPeerInfoHooks.menuItems.register({ info in
            return GGMediaTokE2E.profileMenuItems(info)
        }, order: 80)

        // 6. Wipe plaintext & PBKDF2 key caches from RAM when app leaves foreground
        GGMediaTokE2E.backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            GGMediaTokE2E.clearCache(redraw: false)
        }
    }

    // MARK: - Keychain Storage & Migration

    private static func peerKey(_ peerId: PeerId) -> String {
        return "\(peerId.namespace._internalGetInt32Value())_\(peerId.id._internalGetInt64Value())"
    }

    private static func readKeysFromKeychain() -> [String: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: GGMediaTokE2E.keychainService,
            kSecAttrAccount as String: GGMediaTokE2E.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return decoded
    }

    private static func writeKeysToKeychain(_ dict: [String: String]) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: GGMediaTokE2E.keychainService,
            kSecAttrAccount as String: GGMediaTokE2E.keychainAccount
        ]
        if dict.isEmpty {
            _ = SecItemDelete(baseQuery as CFDictionary)
            return
        }
        guard let data = try? JSONEncoder().encode(dict) else { return }
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            _ = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func loadKeysLocked() -> [String: String] {
        if let cached = GGMediaTokE2E.cachedKeys {
            return cached
        }
        if let kc = GGMediaTokE2E.readKeysFromKeychain() {
            if UserDefaults.standard.object(forKey: GGMediaTokE2E.legacyDefaultsKey) != nil {
                UserDefaults.standard.removeObject(forKey: GGMediaTokE2E.legacyDefaultsKey)
            }
            GGMediaTokE2E.cachedKeys = kc
            return kc
        }
        if let legacy = UserDefaults.standard.dictionary(forKey: GGMediaTokE2E.legacyDefaultsKey) as? [String: String], !legacy.isEmpty {
            GGMediaTokE2E.writeKeysToKeychain(legacy)
            UserDefaults.standard.removeObject(forKey: GGMediaTokE2E.legacyDefaultsKey)
            GGMediaTokE2E.cachedKeys = legacy
            return legacy
        }
        GGMediaTokE2E.cachedKeys = [:]
        return [:]
    }

    static var allKeys: [String: String] {
        GGMediaTokE2E.lock.lock()
        let keys = GGMediaTokE2E.loadKeysLocked()
        GGMediaTokE2E.lock.unlock()
        return keys
    }

    static var enabledPeers: Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: GGMediaTokE2E.enabledKey) ?? []
        return Set(arr)
    }

    static var activeCount: Int {
        return GGMediaTokE2E.enabledPeers.count
    }

    static func isEnabled(for peerId: PeerId) -> Bool {
        let k = GGMediaTokE2E.peerKey(peerId)
        guard GGMediaTokE2E.enabledPeers.contains(k) else { return false }
        let keys = GGMediaTokE2E.allKeys
        return !(keys[k] ?? "").isEmpty
    }

    static func passphrase(for peerId: PeerId) -> String? {
        let k = GGMediaTokE2E.peerKey(peerId)
        let keys = GGMediaTokE2E.allKeys
        guard let v = keys[k], !v.isEmpty else { return nil }
        return v
    }

    static func enable(for peerId: PeerId, passphrase: String) {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let k = GGMediaTokE2E.peerKey(peerId)

        GGMediaTokE2E.lock.lock()
        var keys = GGMediaTokE2E.loadKeysLocked()
        keys[k] = trimmed
        GGMediaTokE2E.cachedKeys = keys
        GGMediaTokE2E.writeKeysToKeychain(keys)
        GGMediaTokE2E.lock.unlock()

        var enabled = GGMediaTokE2E.enabledPeers
        enabled.insert(k)
        UserDefaults.standard.set(Array(enabled), forKey: GGMediaTokE2E.enabledKey)

        GGMediaTokE2E.clearCache(redraw: true)
    }

    static func disable(for peerId: PeerId) {
        let k = GGMediaTokE2E.peerKey(peerId)
        var enabled = GGMediaTokE2E.enabledPeers
        enabled.remove(k)
        UserDefaults.standard.set(Array(enabled), forKey: GGMediaTokE2E.enabledKey)
        GGMediaTokE2E.clearCache(redraw: true)
    }

    static func removeAll() {
        GGMediaTokE2E.lock.lock()
        GGMediaTokE2E.cachedKeys = [:]
        GGMediaTokE2E.writeKeysToKeychain([:])
        GGMediaTokE2E.lock.unlock()

        UserDefaults.standard.removeObject(forKey: GGMediaTokE2E.legacyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: GGMediaTokE2E.enabledKey)
        GGMediaTokE2E.clearCache(redraw: true)
    }

    private static func clearCache(redraw: Bool) {
        GGMediaTokE2E.lock.lock()
        GGMediaTokE2E.decryptCache.removeAll()
        GGMediaTokE2E.lock.unlock()
        GGMediaTokCoreLogic.clearCryptoCache()
        if redraw {
            GGMessageDecorationHooks.redrawAll()
        }
    }

    // MARK: - AES-256-GCM PBKDF2 Crypto

    static func encrypt(_ plaintext: String, passphrase: String, peerId: PeerId) -> String? {
        return GGMediaTokCoreLogic.encryptV2(plaintext, passphrase: passphrase, peerKey: GGMediaTokE2E.peerKey(peerId))
    }

    static func decrypt(_ ciphertext: String, passphrase: String, peerId: PeerId) -> String? {
        return GGMediaTokCoreLogic.decryptAny(ciphertext, passphrase: passphrase, peerKey: GGMediaTokE2E.peerKey(peerId))
    }

    // MARK: - Hooks

    private static func interceptCommand(_ request: GGComposedTextRequest) -> Bool {
        guard let peerId = request.chatLocation.peerId else { return false }
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        guard lower == ".e2e" || lower == ".e2e status" || lower == ".e2e off" || lower.hasPrefix(".e2e on ") || lower.hasPrefix(".e2e ") else {
            return false
        }

        request.replace(ChatTextInputState())
        let statusMsg: String
        if lower == ".e2e off" {
            GGMediaTokE2E.disable(for: peerId)
            statusMsg = "🔓 E2E-шифрование в этом чате выключено"
        } else if lower.hasPrefix(".e2e on ") {
            let pass = String(raw.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            if pass.isEmpty {
                statusMsg = "Укажи ключ: .e2e on <пароль>"
            } else {
                GGMediaTokE2E.enable(for: peerId, passphrase: pass)
                statusMsg = "🔐 E2E AES-256-GCM (PBKDF2) включено! Передай пароль собеседнику лично."
            }
        } else if lower == ".e2e" || lower == ".e2e status" {
            statusMsg = GGMediaTokE2E.isEnabled(for: peerId)
                ? "🔐 E2E в этом чате ВКЛ (выкл: .e2e off)"
                : "🔓 E2E в этом чате ВЫКЛ (вкл: .e2e on <пароль>)"
        } else {
            let pass = String(raw.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            GGMediaTokE2E.enable(for: peerId, passphrase: pass)
            statusMsg = "🔐 E2E AES-256-GCM включено!"
        }
        GGMediaTokE2E.showToast(context: request.context, text: statusMsg)
        return true
    }

    private static func shouldSkipEncryptionForCommand(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("/") {
            return true
        }
        let prefixes = [
            ".color ", ".col ", ".q ", ".stats ", ".card ", ".e2e", ".afk",
            ".c ", ".c! ", ".clip", ".streak",
            ".scratch ", ".qr ", ".fix", ".ghbdtn", ".wheel ", ".poll ",
            ".split ", ".capsule ", ".mood ", ".wish ", ".sn", ".wiki ",
            ".def ", ".unshort ", ".ai ", ".note"
        ]
        for p in prefixes {
            if lower.hasPrefix(p) {
                return true
            }
        }
        return lower == ".stats"
    }

    private static func encryptOutgoing(_ outgoing: inout GGOutgoingText, peerId: PeerId) {
        guard GGMediaTokE2E.isEnabled(for: peerId),
              let pass = GGMediaTokE2E.passphrase(for: peerId),
              !outgoing.text.isEmpty,
              !outgoing.text.hasPrefix(GGMediaTokCoreLogic.prefixV2),
              !outgoing.text.hasPrefix(GGMediaTokCoreLogic.prefixV1),
              !GGMediaTokE2E.shouldSkipEncryptionForCommand(outgoing.text) else {
            return
        }
        if let encrypted = GGMediaTokE2E.encrypt(outgoing.text, passphrase: pass, peerId: peerId) {
            outgoing.text = encrypted
            outgoing.entities = []
        }
    }

    private static func decryptDecoration(_ decoration: inout GGMessageDecoration, message: Message) {
        let text = decoration.textOverride?.text ?? message.text
        guard text.hasPrefix(GGMediaTokCoreLogic.prefixV2) || text.hasPrefix(GGMediaTokCoreLogic.prefixV1) else {
            return
        }
        let cacheKey = "\(message.id.peerId.toInt64()):\(message.id.id):\(text.hashValue)"
        GGMediaTokE2E.lock.lock()
        let cached = GGMediaTokE2E.decryptCache[cacheKey]
        GGMediaTokE2E.lock.unlock()

        if let cached {
            decoration.textOverride = GGMessageTextOverride(text: cached, entities: [])
            return
        }

        let resolved: String
        if let pass = GGMediaTokE2E.passphrase(for: message.id.peerId),
           let plain = GGMediaTokE2E.decrypt(text, passphrase: pass, peerId: message.id.peerId) {
            resolved = "🔓 " + plain
        } else {
            resolved = "🔐 Зашифровано MediaTok E2E (введите ключ в чате: .e2e on <пароль>)"
        }

        GGMediaTokE2E.lock.lock()
        if GGMediaTokE2E.decryptCache.count > 2048 {
            GGMediaTokE2E.decryptCache.removeAll()
        }
        GGMediaTokE2E.decryptCache[cacheKey] = resolved
        GGMediaTokE2E.lock.unlock()

        decoration.textOverride = GGMessageTextOverride(text: resolved, entities: [])
    }

    // MARK: - Menus & UI

    private static func sendMenuItems(_ sendContext: GGSendMenuContext) -> [ContextMenuItem] {
        let peerId = sendContext.peerId
        let isOn = GGMediaTokE2E.isEnabled(for: peerId)
        let title = isOn ? "E2E шифрование: ВКЛ" : "Включить E2E-шифрование"
        let context = sendContext.context
        let dismiss = sendContext.dismiss
        return [.action(ContextMenuActionItem(text: title, icon: { theme in
            return UIImage(systemName: isOn ? "lock.fill" : "lock.open")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            dismiss()
            GGMediaTokE2E.presentConfigAlert(context: context, peerId: peerId)
        }))]
    }

    private static func profileMenuItems(_ info: GGPeerInfoContext) -> [ContextMenuItem] {
        if info.isSettings {
            return []
        }
        let peerId = (info.chatPeer ?? info.peer).id
        let isOn = GGMediaTokE2E.isEnabled(for: peerId)
        let title = isOn ? "E2E шифрование: ВКЛ" : "E2E шифрование чата"
        let context = info.context
        return [.action(ContextMenuActionItem(text: title, icon: { theme in
            return UIImage(systemName: isOn ? "lock.shield.fill" : "lock.shield")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            GGMediaTokE2E.presentConfigAlert(context: context, peerId: peerId)
        }))]
    }

    static func presentConfigAlert(context: AccountContext, peerId: PeerId) {
        let isOn = GGMediaTokE2E.isEnabled(for: peerId)
        let currentPass = GGMediaTokE2E.passphrase(for: peerId) ?? ""
        let alert = UIAlertController(
            title: isOn ? "🔐 E2E-шифрование (ВКЛ)" : "🔓 Включить E2E-шифрование",
            message: "AES-256-GCM + PBKDF2 шифрование сообщений в Keychain iOS. Задайте общий пароль с собеседником — сервер Telegram увидит только шифротекст.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Общий секретный ключ (пароль)"
            tf.text = currentPass
            tf.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Включить / Сохранить", style: .default, handler: { [weak alert] _ in
            let pass = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pass.isEmpty {
                GGMediaTokE2E.showToast(context: context, text: "Пароль не может быть пустым")
                return
            }
            GGMediaTokE2E.enable(for: peerId, passphrase: pass)
            GGMediaTokE2E.showToast(context: context, text: "🔐 E2E AES-256-GCM (PBKDF2) включено!")
        }))
        if isOn {
            alert.addAction(UIAlertAction(title: "Выключить E2E", style: .destructive, handler: { _ in
                GGMediaTokE2E.disable(for: peerId)
                GGMediaTokE2E.showToast(context: context, text: "🔓 E2E выключено для этого чата")
            }))
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        GGMediaTokE2E.presentAlertOnRoot(alert)
    }

    static func presentManager(context: GGMenuContext) {
        let count = GGMediaTokE2E.activeCount
        let alert = UIAlertController(
            title: "E2E-шифрование чатов (AES-256-GCM)",
            message: "Активно чатов: \(count) (ключи защищены в Keychain + PBKDF2).\n\nВключить E2E для любого чата можно:\n• Долгим нажатием на кнопку «Отправить» в чате\n• Через меню «…» в профиле\n• Командой прямо в чате: .e2e on <пароль> и .e2e off",
            preferredStyle: .alert
        )
        if count > 0 {
            alert.addAction(UIAlertAction(title: "Сбросить все E2E-ключи (\(count))", style: .destructive, handler: { _ in
                GGMediaTokE2E.removeAll()
                context.presentToast("Все E2E-ключи сброшены")
            }))
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        context.presentNative(alert)
    }

    private static func presentAlertOnRoot(_ alert: UIAlertController) {
        GGModalPresenter.presentOnTopmost(alert)
    }

    private static func showToast(context: AccountContext, text: String) {
        DispatchQueue.main.async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let overlay = UndoOverlayController(
                presentationData: presentationData,
                content: .info(title: nil, text: text, timeout: nil, customUndoText: nil),
                elevatedLayout: false,
                action: { _ in return false }
            )
            context.sharedContext.mainWindow?.present(overlay, on: .root)
        }
    }
}
