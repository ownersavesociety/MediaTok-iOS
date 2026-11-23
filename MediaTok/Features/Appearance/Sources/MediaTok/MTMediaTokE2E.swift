import Foundation
import UIKit
import Security
import Postbox
import TelegramCore
import AccountContext
import ContextUI
import UndoUI
import MTCore
import MTHooks
import MTSettingsUI

/// Optional per-chat AES-256-GCM End-to-End Encryption for MediaTok iOS.
/// - Keys are stored exclusively in iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
///   with automatic migration from legacy UserDefaults.
/// - Keys are derived via 100,000-iteration PBKDF2-HMAC-SHA256 with random 128-bit salt and
///   chat-bound AAD (`🔒MT2:`), preventing cross-chat replay and GPU brute-force.
/// - Decrypted cache & derived keys are purged automatically when entering the background.
enum MTMediaTokE2E {
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
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokE2E.interceptCommand(request)
        }, order: 20)

        // 2. Transparent outgoing AES-256-GCM encryption (runs LAST after chat text fonts, skips sticker/bot commands)
        MTOutgoingHooks.textStages.register({ outgoing, context in
            MTMediaTokE2E.encryptOutgoing(&outgoing, peerId: context.peerId)
        }, order: 950)

        // 3. Transparent live decryption in chat bubbles (runs FIRST in decoration chain!)
        MTMessageDecorationHooks.decorations.register({ decoration, context in
            MTMediaTokE2E.decryptDecoration(&decoration, message: context.message)
        }, order: 40)

        // 4. 1-tap toggle in Send button long-press menu
        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            return MTMediaTokE2E.sendMenuItems(sendContext)
        }, order: 80)

        // 5. 1-tap toggle in Profile "..." menu
        MTPeerInfoHooks.menuItems.register({ info in
            return MTMediaTokE2E.profileMenuItems(info)
        }, order: 80)

        // 6. Wipe plaintext & PBKDF2 key caches from RAM when app leaves foreground
        MTMediaTokE2E.backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            MTMediaTokE2E.clearCache(redraw: false)
        }
    }

    // MARK: - Keychain Storage & Migration

    private static func peerKey(_ peerId: PeerId) -> String {
        return "\(peerId.namespace._internalGetInt32Value())_\(peerId.id._internalGetInt64Value())"
    }

    private static func readKeysFromKeychain() -> [String: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: MTMediaTokE2E.keychainService,
            kSecAttrAccount as String: MTMediaTokE2E.keychainAccount,
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
            kSecAttrService as String: MTMediaTokE2E.keychainService,
            kSecAttrAccount as String: MTMediaTokE2E.keychainAccount
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
        if let cached = MTMediaTokE2E.cachedKeys {
            return cached
        }
        if let kc = MTMediaTokE2E.readKeysFromKeychain() {
            if UserDefaults.standard.object(forKey: MTMediaTokE2E.legacyDefaultsKey) != nil {
                UserDefaults.standard.removeObject(forKey: MTMediaTokE2E.legacyDefaultsKey)
            }
            MTMediaTokE2E.cachedKeys = kc
            return kc
        }
        if let legacy = UserDefaults.standard.dictionary(forKey: MTMediaTokE2E.legacyDefaultsKey) as? [String: String], !legacy.isEmpty {
            MTMediaTokE2E.writeKeysToKeychain(legacy)
            UserDefaults.standard.removeObject(forKey: MTMediaTokE2E.legacyDefaultsKey)
            MTMediaTokE2E.cachedKeys = legacy
            return legacy
        }
        MTMediaTokE2E.cachedKeys = [:]
        return [:]
    }

    static var allKeys: [String: String] {
        MTMediaTokE2E.lock.lock()
        let keys = MTMediaTokE2E.loadKeysLocked()
        MTMediaTokE2E.lock.unlock()
        return keys
    }

    static var enabledPeers: Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: MTMediaTokE2E.enabledKey) ?? []
        return Set(arr)
    }

    static var activeCount: Int {
        return MTMediaTokE2E.enabledPeers.count
    }

    static func isEnabled(for peerId: PeerId) -> Bool {
        let k = MTMediaTokE2E.peerKey(peerId)
        guard MTMediaTokE2E.enabledPeers.contains(k) else { return false }
        let keys = MTMediaTokE2E.allKeys
        return !(keys[k] ?? "").isEmpty
    }

    static func passphrase(for peerId: PeerId) -> String? {
        let k = MTMediaTokE2E.peerKey(peerId)
        let keys = MTMediaTokE2E.allKeys
        guard let v = keys[k], !v.isEmpty else { return nil }
        return v
    }

    static func enable(for peerId: PeerId, passphrase: String) {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let k = MTMediaTokE2E.peerKey(peerId)

        MTMediaTokE2E.lock.lock()
        var keys = MTMediaTokE2E.loadKeysLocked()
        keys[k] = trimmed
        MTMediaTokE2E.cachedKeys = keys
        MTMediaTokE2E.writeKeysToKeychain(keys)
        MTMediaTokE2E.lock.unlock()

        var enabled = MTMediaTokE2E.enabledPeers
        enabled.insert(k)
        UserDefaults.standard.set(Array(enabled), forKey: MTMediaTokE2E.enabledKey)

        MTMediaTokE2E.clearCache(redraw: true)
    }

    static func disable(for peerId: PeerId) {
        let k = MTMediaTokE2E.peerKey(peerId)
        var enabled = MTMediaTokE2E.enabledPeers
        enabled.remove(k)
        UserDefaults.standard.set(Array(enabled), forKey: MTMediaTokE2E.enabledKey)
        MTMediaTokE2E.clearCache(redraw: true)
    }

    static func removeAll() {
        MTMediaTokE2E.lock.lock()
        MTMediaTokE2E.cachedKeys = [:]
        MTMediaTokE2E.writeKeysToKeychain([:])
        MTMediaTokE2E.lock.unlock()

        UserDefaults.standard.removeObject(forKey: MTMediaTokE2E.legacyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MTMediaTokE2E.enabledKey)
        MTMediaTokE2E.clearCache(redraw: true)
    }

    private static func clearCache(redraw: Bool) {
        MTMediaTokE2E.lock.lock()
        MTMediaTokE2E.decryptCache.removeAll()
        MTMediaTokE2E.lock.unlock()
        MTMediaTokCoreLogic.clearCryptoCache()
        if redraw {
            MTMessageDecorationHooks.redrawAll()
        }
    }

    // MARK: - AES-256-GCM PBKDF2 Crypto

    static func encrypt(_ plaintext: String, passphrase: String, peerId: PeerId) -> String? {
        return MTMediaTokCoreLogic.encryptV2(plaintext, passphrase: passphrase, peerKey: MTMediaTokE2E.peerKey(peerId))
    }

    static func decrypt(_ ciphertext: String, passphrase: String, peerId: PeerId) -> String? {
        return MTMediaTokCoreLogic.decryptAny(ciphertext, passphrase: passphrase, peerKey: MTMediaTokE2E.peerKey(peerId))
    }

    // MARK: - Hooks

    private static func interceptCommand(_ request: MTComposedTextRequest) -> Bool {
        guard let peerId = request.chatLocation.peerId else { return false }
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        guard lower == ".e2e" || lower == ".e2e status" || lower == ".e2e off" || lower.hasPrefix(".e2e on ") || lower.hasPrefix(".e2e ") else {
            return false
        }

        request.replace(ChatTextInputState())
        let statusMsg: String
        if lower == ".e2e off" {
            MTMediaTokE2E.disable(for: peerId)
            statusMsg = "🔓 E2E-шифрование в этом чате выключено"
        } else if lower.hasPrefix(".e2e on ") {
            let pass = String(raw.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            if pass.isEmpty {
                statusMsg = "Укажи ключ: .e2e on <пароль>"
            } else {
                MTMediaTokE2E.enable(for: peerId, passphrase: pass)
                statusMsg = "🔐 E2E AES-256-GCM (PBKDF2) включено! Передай пароль собеседнику лично."
            }
        } else if lower == ".e2e" || lower == ".e2e status" {
            statusMsg = MTMediaTokE2E.isEnabled(for: peerId)
                ? "🔐 E2E в этом чате ВКЛ (выкл: .e2e off)"
                : "🔓 E2E в этом чате ВЫКЛ (вкл: .e2e on <пароль>)"
        } else {
            let pass = String(raw.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            MTMediaTokE2E.enable(for: peerId, passphrase: pass)
            statusMsg = "🔐 E2E AES-256-GCM включено!"
        }
        MTMediaTokE2E.showToast(context: request.context, text: statusMsg)
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

    private static func encryptOutgoing(_ outgoing: inout MTOutgoingText, peerId: PeerId) {
        guard MTMediaTokE2E.isEnabled(for: peerId),
              let pass = MTMediaTokE2E.passphrase(for: peerId),
              !outgoing.text.isEmpty,
              !outgoing.text.hasPrefix(MTMediaTokCoreLogic.prefixV2),
              !outgoing.text.hasPrefix(MTMediaTokCoreLogic.prefixV1),
              !MTMediaTokE2E.shouldSkipEncryptionForCommand(outgoing.text) else {
            return
        }
        if let encrypted = MTMediaTokE2E.encrypt(outgoing.text, passphrase: pass, peerId: peerId) {
            outgoing.text = encrypted
            outgoing.entities = []
        }
    }

    private static func decryptDecoration(_ decoration: inout MTMessageDecoration, message: Message) {
        let text = decoration.textOverride?.text ?? message.text
        guard text.hasPrefix(MTMediaTokCoreLogic.prefixV2) || text.hasPrefix(MTMediaTokCoreLogic.prefixV1) else {
            return
        }
        let cacheKey = "\(message.id.peerId.toInt64()):\(message.id.id):\(text.hashValue)"
        MTMediaTokE2E.lock.lock()
        let cached = MTMediaTokE2E.decryptCache[cacheKey]
        MTMediaTokE2E.lock.unlock()

        if let cached {
            decoration.textOverride = MTMessageTextOverride(text: cached, entities: [])
            return
        }

        let resolved: String
        if let pass = MTMediaTokE2E.passphrase(for: message.id.peerId),
           let plain = MTMediaTokE2E.decrypt(text, passphrase: pass, peerId: message.id.peerId) {
            resolved = "🔓 " + plain
        } else {
            resolved = "🔐 Зашифровано MediaTok E2E (введите ключ в чате: .e2e on <пароль>)"
        }

        MTMediaTokE2E.lock.lock()
        if MTMediaTokE2E.decryptCache.count > 2048 {
            MTMediaTokE2E.decryptCache.removeAll()
        }
        MTMediaTokE2E.decryptCache[cacheKey] = resolved
        MTMediaTokE2E.lock.unlock()

        decoration.textOverride = MTMessageTextOverride(text: resolved, entities: [])
    }

    // MARK: - Menus & UI

    private static func sendMenuItems(_ sendContext: MTSendMenuContext) -> [ContextMenuItem] {
        let peerId = sendContext.peerId
        let isOn = MTMediaTokE2E.isEnabled(for: peerId)
        let title = isOn ? "E2E шифрование: ВКЛ" : "Включить E2E-шифрование"
        let context = sendContext.context
        let dismiss = sendContext.dismiss
        return [.action(ContextMenuActionItem(text: title, icon: { theme in
            return UIImage(systemName: isOn ? "lock.fill" : "lock.open")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            dismiss()
            MTMediaTokE2E.presentConfigAlert(context: context, peerId: peerId)
        }))]
    }

    private static func profileMenuItems(_ info: MTPeerInfoContext) -> [ContextMenuItem] {
        if info.isSettings {
            return []
        }
        let peerId = (info.chatPeer ?? info.peer).id
        let isOn = MTMediaTokE2E.isEnabled(for: peerId)
        let title = isOn ? "E2E шифрование: ВКЛ" : "E2E шифрование чата"
        let context = info.context
        return [.action(ContextMenuActionItem(text: title, icon: { theme in
            return UIImage(systemName: isOn ? "lock.shield.fill" : "lock.shield")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            MTMediaTokE2E.presentConfigAlert(context: context, peerId: peerId)
        }))]
    }

    static func presentConfigAlert(context: AccountContext, peerId: PeerId) {
        let isOn = MTMediaTokE2E.isEnabled(for: peerId)
        let currentPass = MTMediaTokE2E.passphrase(for: peerId) ?? ""
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
                MTMediaTokE2E.showToast(context: context, text: "Пароль не может быть пустым")
                return
            }
            MTMediaTokE2E.enable(for: peerId, passphrase: pass)
            MTMediaTokE2E.showToast(context: context, text: "🔐 E2E AES-256-GCM (PBKDF2) включено!")
        }))
        if isOn {
            alert.addAction(UIAlertAction(title: "Выключить E2E", style: .destructive, handler: { _ in
                MTMediaTokE2E.disable(for: peerId)
                MTMediaTokE2E.showToast(context: context, text: "🔓 E2E выключено для этого чата")
            }))
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTMediaTokE2E.presentAlertOnRoot(alert)
    }

    static func presentManager(context: MTMenuContext) {
        let count = MTMediaTokE2E.activeCount
        let alert = UIAlertController(
            title: "E2E-шифрование чатов (AES-256-GCM)",
            message: "Активно чатов: \(count) (ключи защищены в Keychain + PBKDF2).\n\nВключить E2E для любого чата можно:\n• Долгим нажатием на кнопку «Отправить» в чате\n• Через меню «…» в профиле\n• Командой прямо в чате: .e2e on <пароль> и .e2e off",
            preferredStyle: .alert
        )
        if count > 0 {
            alert.addAction(UIAlertAction(title: "Сбросить все E2E-ключи (\(count))", style: .destructive, handler: { _ in
                MTMediaTokE2E.removeAll()
                context.presentToast("Все E2E-ключи сброшены")
            }))
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        context.presentNative(alert)
    }

    private static func presentAlertOnRoot(_ alert: UIAlertController) {
        MTModalPresenter.presentOnTopmost(alert)
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
