import Foundation
import Postbox
import TelegramCore
import MTCore

/// Which chats are protected — configuration only (the app's unlock state is MTSecurity's). One
/// answer for every place that must not show a protected chat's content: the chat list preview and
/// the search (app), the push text (notification service), in-app banners, the widget and Siri.
public enum MTChatProtection {
    /// The chat is protected by «Пароль на чаты» or belongs to the locked-away secret folder.
    /// Snapshot reads only: layout paths, signal maps, the extensions.
    public static func isProtected(account: MTAccountID, peerId: PeerId) -> Bool {
        let key = peerId.mtKey
        if MTSecuritySharedSettings.chatLockEnabled.value {
            if MTSecuritySharedSettings.chatLockAllChats.value {
                return MTChatProtection.isLockable(peerId)
            }
            if MTSecuritySharedSettings.chatLockPeers.value(for: account).contains(key) {
                return true
            }
        }
        return MTSecuritySharedSettings.secretFolderPeers.value(for: account).contains(key)
    }

    /// «Все чаты» means every chat except Telegram's service notifications (777000): login codes must
    /// stay readable in their pushes.
    public static func isLockable(_ peerId: PeerId) -> Bool {
        if peerId.namespace == Namespaces.Peer.CloudUser && peerId.id._internalGetInt64Value() == 777000 {
            return false
        }
        return true
    }

    /// Notification service, Siri, in-app banners, widget (MTContentPrivacyHooks.hidesContent) and the
    /// push text (MTNotificationServiceHooks.content).
    static func register() {
        MTContentPrivacyHooks.hidesContent.register({ accountId, peerId in
            return MTChatProtection.isProtected(account: accountId.mt, peerId: peerId)
        })
        MTNotificationServiceHooks.content.register({ content, context in
            guard let accountId = context.accountId, let peerId = context.peerId, !content.isHidden else {
                return
            }
            if !MTChatProtection.isProtected(account: accountId.mt, peerId: peerId) {
                return
            }
            MTChatProtection.adoptAppLanguage()
            content.body = MTStrings.Security.Notifications.hiddenText
            content.hidesAttachments = true
        }, order: 10000)
    }

    /// The extension does not learn Telegram's language from a PresentationData; the app leaves it in
    /// `extensionLanguage` (the user's manual MediaTok language still wins inside MTLocalization).
    private static func adoptAppLanguage() {
        if MTCore.environment?.process.isApp ?? true {
            return
        }
        let code = MTSecuritySharedSettings.extensionLanguage.value
        if !code.isEmpty {
            MTLocalization.shared.setTelegramLanguageCode(code)
        }
    }
}
