import Foundation
import UIKit
import CryptoKit
import Postbox
import TelegramCore
import AccountContext
import ContextUI
import UndoUI
import GGCore
import GGHooks
import GGSettingsUI

/// Optional per-chat AES-256-GCM End-to-End Encryption for MediaTok iOS.
/// - Toggleable per chat via Send button long-press menu, profile "..." menu, Settings, or inline `.e2e on <key>` / `.e2e off`.
/// - Encrypts outgoing messages transparently into `🔒MT1:<url-safe-base64>` (so Telegram servers & non-E2E clients only see ciphertext).
/// - Decrypts incoming & outgoing `🔒MT1:` bubbles transparently in-memory via `GGMessageDecorationHooks.decorations` (NO upstream edits!).
enum GGMediaTokE2E {
    private static let prefix = "🔒MT1:"
    private static let defaultsKey = "mediatok.e2e.keys.v1"
    private static let enabledKey = "mediatok.e2e.enabled.v1"
    private static let lock = NSLock()
    private static var decryptCache: [String: String] = [:]

    static func register() {
        // 1. Inline `.e2e on <pass>` / `.e2e off` / `.e2e status` interceptor (never leaks passphrase to chat!)
        GGChatScreenHooks.willSendText.register({ request, _ in
            return GGMediaTokE2E.interceptCommand(request)
        }, order: 20)

        // 2. Transparent outgoing AES-256-GCM encryption (runs LAST after chat text fonts!)
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
    }

    // MARK: - Storage

    private static func peerKey(_ peerId: PeerId) -> String {
        return "\(peerId.namespace._internalGetInt32Value())_\(peerId.id._internalGetInt64Value())"
    }

    static var allKeys: [String: String] {
        return (UserDefaults.standard.dictionary(forKey: GGMediaTokE2E.defaultsKey) as? [String: String]) ?? [:]
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
        return GGMediaTokE2E.enabledPeers.contains(k) && !(GGMediaTokE2E.allKeys[k] ?? "").isEmpty
    }

    static func passphrase(for peerId: PeerId) -> String? {
        let k = GGMediaTokE2E.peerKey(peerId)
        guard let v = GGMediaTokE2E.allKeys[k], !v.isEmpty else { return nil }
        return v
    }

    static func enable(for peerId: PeerId, passphrase: String) {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let k = GGMediaTokE2E.peerKey(peerId)
        var keys = GGMediaTokE2E.allKeys
        keys[k] = trimmed
        UserDefaults.standard.set(keys, forKey: GGMediaTokE2E.defaultsKey)

        var enabled = GGMediaTokE2E.enabledPeers
        enabled.insert(k)
        UserDefaults.standard.set(Array(enabled), forKey: GGMediaTokE2E.enabledKey)

        GGMediaTokE2E.clearCache()
    }

    static func disable(for peerId: PeerId) {
        let k = GGMediaTokE2E.peerKey(peerId)
        var enabled = GGMediaTokE2E.enabledPeers
        enabled.remove(k)
        UserDefaults.standard.set(Array(enabled), forKey: GGMediaTokE2E.enabledKey)
        GGMediaTokE2E.clearCache()
    }

    static func removeAll() {
        UserDefaults.standard.removeObject(forKey: GGMediaTokE2E.defaultsKey)
        UserDefaults.standard.removeObject(forKey: GGMediaTokE2E.enabledKey)
        GGMediaTokE2E.clearCache()
    }

    private static func clearCache() {
        GGMediaTokE2E.lock.lock()
        GGMediaTokE2E.decryptCache.removeAll()
        GGMediaTokE2E.lock.unlock()
        GGMessageDecorationHooks.redrawAll()
    }

    // MARK: - AES-256-GCM CryptoKit

    private static func deriveKey(passphrase: String) -> SymmetricKey {
        let material = Data("MediaTokE2E:v1:\(passphrase)".utf8)
        let hash = SHA256.hash(data: material)
        return SymmetricKey(data: hash)
    }

    static func encrypt(_ plaintext: String, passphrase: String) -> String? {
        let key = GGMediaTokE2E.deriveKey(passphrase: passphrase)
        let plainData = Data(plaintext.utf8)
        guard let sealed = try? AES.GCM.seal(plainData, using: key),
              let combined = sealed.combined else {
            return nil
        }
        let b64 = combined.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return GGMediaTokE2E.prefix + b64
    }

    static func decrypt(_ ciphertext: String, passphrase: String) -> String? {
        guard ciphertext.hasPrefix(GGMediaTokE2E.prefix) else { return nil }
        var b64 = String(ciphertext.dropFirst(GGMediaTokE2E.prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 {
            b64.append(String(repeating: "=", count: 4 - rem))
        }
        guard let raw = Data(base64Encoded: b64),
              let box = try? AES.GCM.SealedBox(combined: raw) else {
            return nil
        }
        let key = GGMediaTokE2E.deriveKey(passphrase: passphrase)
        guard let plain = try? AES.GCM.open(box, using: key),
              let str = String(data: plain, encoding: .utf8) else {
            return nil
        }
        return str
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
                statusMsg = "🔐 E2E AES-256-GCM включено! Передай пароль собеседнику лично."
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

    private static func encryptOutgoing(_ outgoing: inout GGOutgoingText, peerId: PeerId) {
        guard GGMediaTokE2E.isEnabled(for: peerId),
              let pass = GGMediaTokE2E.passphrase(for: peerId),
              !outgoing.text.isEmpty,
              !outgoing.text.hasPrefix(GGMediaTokE2E.prefix) else {
            return
        }
        if let encrypted = GGMediaTokE2E.encrypt(outgoing.text, passphrase: pass) {
            outgoing.text = encrypted
            outgoing.entities = []
        }
    }

    private static func decryptDecoration(_ decoration: inout GGMessageDecoration, message: Message) {
        let text = decoration.textOverride?.text ?? message.text
        guard text.hasPrefix(GGMediaTokE2E.prefix) else {
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
           let plain = GGMediaTokE2E.decrypt(text, passphrase: pass) {
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
            message: "AES-256-GCM шифрование сообщений прямо в обычном чате. Задайте общий пароль с собеседником — сервер Telegram увидит только шифротекст.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Общий секретный ключ (пароль)"
            tf.text = currentPass
            tf.isSecureTextEntry = false
        }
        alert.addAction(UIAlertAction(title: "Включить / Сохранить", style: .default, handler: { [weak alert] _ in
            let pass = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pass.isEmpty {
                GGMediaTokE2E.showToast(context: context, text: "Пароль не может быть пустым")
                return
            }
            GGMediaTokE2E.enable(for: peerId, passphrase: pass)
            GGMediaTokE2E.showToast(context: context, text: "🔐 E2E AES-256-GCM включено для этого чата!")
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
            message: "Активно чатов: \(count).\n\nВключить E2E для любого чата можно:\n• Долгим нажатием на кнопку «Отправить» в чате\n• Через меню «…» в профиле\n• Командой прямо в чате: .e2e on <пароль> и .e2e off",
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
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let root = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
                return
            }
            var presenter = root
            while let next = presenter.presentedViewController {
                presenter = next
            }
            presenter.present(alert, animated: true)
        }
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
