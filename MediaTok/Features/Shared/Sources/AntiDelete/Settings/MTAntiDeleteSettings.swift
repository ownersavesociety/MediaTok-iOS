import Foundation
import MTCore

/// Every setting of anti-delete, edit history, local edits and bookmarks, declared once.
/// What the notification service reads (capture) is `.appGroup` + `.extensions`, or an account
/// setting with `.extensions`; the rest is app-only.
public enum MTAntiDeleteSettings {
    // MARK: Capture (read by the notification service too)

    /// Keep messages other people (or the server) deleted.
    public static let enabled = MTSetting<Bool>("antiDelete.enabled", default: false, scope: .appGroup, flags: [.extensions])
    /// Keep one's own outgoing messages deleted «for everyone» (here or on another device).
    public static let keepOwn = MTSetting<Bool>("antiDelete.keepOwn", default: false, scope: .appGroup, flags: [.extensions])
    /// Keep incoming self-destructing messages (timers, view-once) when the timer fires.
    public static let keepSelfDestructing = MTSetting<Bool>("antiDelete.keepSelfDestructing", default: false, scope: .appGroup, flags: [.extensions])
    /// Apply all of the above to secret chats as well.
    public static let secretChats = MTSetting<Bool>("antiDelete.secretChats", default: false, scope: .appGroup, flags: [.extensions])
    /// Keep previous versions of edited messages.
    public static let editHistory = MTSetting<Bool>("antiDelete.editHistory", default: false, scope: .appGroup, flags: [.extensions])
    public static let excludeGroups = MTSetting<Bool>("antiDelete.excludeGroups", default: false, scope: .appGroup, flags: [.extensions])
    public static let excludeBots = MTSetting<Bool>("antiDelete.excludeBots", default: false, scope: .appGroup, flags: [.extensions])
    public static let excludeChannels = MTSetting<Bool>("antiDelete.excludeChannels", default: false, scope: .appGroup, flags: [.extensions])
    /// Excluded chats still keep previous versions of edited messages.
    public static let editsInExclusions = MTSetting<Bool>("antiDelete.editsInExclusions", default: false, scope: .appGroup, flags: [.extensions])

    /// Chats excluded by hand (the whole PeerId; a secret chat follows its user).
    public static let excludedPeers = MTAccountSetting<Set<MTPeerKey>>("antiDelete.excludedPeers", default: [], flags: [.extensions])
    /// Folders whose chats are excluded (folder ids of this account).
    public static let excludedFolders = MTAccountSetting<Set<Int32>>("antiDelete.excludedFolders", default: [])
    /// The chats of `excludedFolders`, kept up to date by the app while the account runs
    /// (folders change, chats move). Derived data: not exported, recomputed after a reset.
    public static let excludedFolderPeers = MTAccountSetting<Set<MTPeerKey>>("antiDelete.excludedFolderPeers", default: [], flags: [.extensions, .noExport])

    // MARK: App only

    /// Keep a copy of the media of deleted messages (not for secret chats).
    public static let keepMedia = MTSetting<Bool>("antiDelete.keepMedia", default: false)
    /// Transparency of deleted messages, percent 0…80.
    public static let transparency = MTSetting<Double>("antiDelete.transparency", default: 45.0)
    /// Previous versions are shown under the text (otherwise only in «История правок»).
    public static let editHistoryInline = MTSetting<Bool>("antiDelete.editHistoryInline", default: false)
    /// Transparency of the previous versions shown under the text, percent 0…80.
    public static let versionsTransparency = MTSetting<Double>("antiDelete.versionsTransparency", default: 45.0)
    /// «Изменить локально» in the message menu.
    public static let localEdit = MTSetting<Bool>("antiDelete.localEdit", default: false)
    /// `MTAntiDeleteRetention` raw value.
    public static let autoClear = MTSetting<String>("antiDelete.autoClear", default: MTAntiDeleteRetention.never.rawValue)

    /// The old client's archive was imported into this account.
    public static let legacyImportDone = MTAccountSetting<Bool>("antiDelete.legacyImportDone", default: false, flags: [.noExport])

    public static let transparencyRange: ClosedRange<Double> = 0.0 ... 80.0

    static func declare() {
        let _ = MTAntiDeleteSettings.enabled
        let _ = MTAntiDeleteSettings.keepOwn
        let _ = MTAntiDeleteSettings.keepSelfDestructing
        let _ = MTAntiDeleteSettings.secretChats
        let _ = MTAntiDeleteSettings.editHistory
        let _ = MTAntiDeleteSettings.excludeGroups
        let _ = MTAntiDeleteSettings.excludeBots
        let _ = MTAntiDeleteSettings.excludeChannels
        let _ = MTAntiDeleteSettings.editsInExclusions
        let _ = MTAntiDeleteSettings.excludedPeers
        let _ = MTAntiDeleteSettings.excludedFolders
        let _ = MTAntiDeleteSettings.excludedFolderPeers
        let _ = MTAntiDeleteSettings.keepMedia
        let _ = MTAntiDeleteSettings.transparency
        let _ = MTAntiDeleteSettings.editHistoryInline
        let _ = MTAntiDeleteSettings.versionsTransparency
        let _ = MTAntiDeleteSettings.localEdit
        let _ = MTAntiDeleteSettings.autoClear
        let _ = MTAntiDeleteSettings.legacyImportDone
        let _ = MTBookmarkSettings.enabled
    }

    /// Alpha of a deleted message from the transparency percent (clamped like the slider).
    public static func alpha(forTransparency value: Double) -> CGFloat {
        let clamped = min(MTAntiDeleteSettings.transparencyRange.upperBound, max(MTAntiDeleteSettings.transparencyRange.lowerBound, value))
        return CGFloat(1.0 - clamped / 100.0)
    }
}

public enum MTBookmarkSettings {
    /// «Закладка» in the message menu, the marker on the bubble and the row under the chat search.
    public static let enabled = MTSetting<Bool>("bookmarks.enabled", default: false)
}
