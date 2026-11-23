import Foundation
import MTCore

/// Settings of «Безопасность» that the extensions read (notification service, Siri): which chats are
/// protected. The policies are global on purpose (legacy format made them per-account by accident and
/// lost them on an account without a snapshot); the lists are per account, because peer ids and
/// folder ids belong to an account.
public enum MTSecuritySharedSettings {
    /// «Пароль на чаты».
    public static let chatLockEnabled = MTSetting<Bool>("security.chatLock.enabled", default: false, scope: .appGroup, flags: [.extensions])
    /// «Применять к»: every chat instead of the chosen ones.
    public static let chatLockAllChats = MTSetting<Bool>("security.chatLock.allChats", default: false, scope: .appGroup, flags: [.extensions])
    /// «Выбранные чаты» of the account.
    public static let chatLockPeers = MTAccountSetting<Set<MTPeerKey>>("security.chatLock.peers", default: [], flags: [.extensions])
    /// Members of the account's secret folder whose chats are protected while the folder is locked
    /// («Защищать чаты папки»). Kept by the app from a live view of the folder, read by the
    /// notification service; derived data, so never exported.
    public static let secretFolderPeers = MTAccountSetting<Set<MTPeerKey>>("security.secretFolder.peers", default: [], flags: [.extensions, .noExport])
    /// The app's resolved MediaTok language, for the texts the notification service writes (the
    /// extension does not know Telegram's language). Written by the app, never exported.
    public static let extensionLanguage = MTSetting<String>("security.extensionLanguage", default: "", scope: .appGroup, flags: [.extensions, .noExport])

    static func declare() {
        let _ = MTSecuritySharedSettings.chatLockEnabled
        let _ = MTSecuritySharedSettings.chatLockAllChats
        let _ = MTSecuritySharedSettings.chatLockPeers
        let _ = MTSecuritySharedSettings.secretFolderPeers
        let _ = MTSecuritySharedSettings.extensionLanguage
    }
}
