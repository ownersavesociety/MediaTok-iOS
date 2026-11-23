import Foundation
import Postbox
import TelegramCore
import MTCore

/// One "what the other side sees you doing" status, one case per `PeerInputActivity` the client
/// actually sends. Raw values are the legacy MediaTok ones (migration of per-chat lists).
public enum MTGhostActivityKind: String, CaseIterable, Codable {
    case typingText
    case recordingVoice
    case recordingInstantVideo
    case uploadingInstantVideo
    case uploadingVideo
    case uploadingPhoto
    case uploadingFile
    case choosingSticker
    case playingGame
    case speakingInGroupCall
    case interactingWithEmoji
    case seeingEmojiInteraction

    public init(_ activity: PeerInputActivity) {
        switch activity {
        case .typingText:
            self = .typingText
        case .recordingVoice:
            self = .recordingVoice
        case .recordingInstantVideo:
            self = .recordingInstantVideo
        case .uploadingInstantVideo:
            self = .uploadingInstantVideo
        case .uploadingVideo:
            self = .uploadingVideo
        case .uploadingPhoto:
            self = .uploadingPhoto
        case .uploadingFile:
            self = .uploadingFile
        case .choosingSticker:
            self = .choosingSticker
        case .playingGame:
            self = .playingGame
        case .speakingInGroupCall:
            self = .speakingInGroupCall
        case .interactingWithEmoji:
            self = .interactingWithEmoji
        case .seeingEmojiInteraction:
            self = .seeingEmojiInteraction
        }
    }
}

/// Per-chat exception from ghost mode. A `true` field means "this part of ghost mode does not apply
/// in this chat" (the chat sees it as from a normal client).
public struct MTGhostException: MTSettingValue {
    public enum Kind: String, Codable {
        /// The chat is an exception: the fields below say what it sees.
        case exclude
        /// The chat is pulled back into ghost mode although its type or folder is an exception.
        case include
    }

    public var kind: Kind
    public var readMessages: Bool
    public var readStories: Bool
    /// Online while this chat is open on screen.
    public var showOnline: Bool
    /// Every activity status is sent in this chat.
    public var showTyping: Bool
    /// Own list of statuses shown in this chat when `showTyping` is off. nil = the global list.
    public var ownShownActivities: [MTGhostActivityKind]?
    /// nil = as in the global «Читать при действиях».
    public var readOnAction: Bool?

    public init(kind: Kind = .exclude, readMessages: Bool = true, readStories: Bool = true, showOnline: Bool = true, showTyping: Bool = true, ownShownActivities: [MTGhostActivityKind]? = nil, readOnAction: Bool? = nil) {
        self.kind = kind
        self.readMessages = readMessages
        self.readStories = readStories
        self.showOnline = showOnline
        self.showTyping = showTyping
        self.ownShownActivities = ownShownActivities
        self.readOnAction = readOnAction
    }

    /// A chat that is excluded completely (type and folder exceptions behave like this).
    public static let fullExclusion = MTGhostException()

    /// Pulled back into ghost mode.
    public static let forcedGhost = MTGhostException(kind: .include, readMessages: false, readStories: false, showOnline: false, showTyping: false)

    private enum CodingKeys: String, CodingKey {
        case kind = "k"
        case readMessages = "rm"
        case readStories = "rs"
        case showOnline = "on"
        case showTyping = "ty"
        case ownShownActivities = "act"
        case readOnAction = "roa"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = (try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? .exclude
        self.readMessages = (try? container.decodeIfPresent(Bool.self, forKey: .readMessages)) ?? true
        self.readStories = (try? container.decodeIfPresent(Bool.self, forKey: .readStories)) ?? true
        self.showOnline = (try? container.decodeIfPresent(Bool.self, forKey: .showOnline)) ?? true
        self.showTyping = (try? container.decodeIfPresent(Bool.self, forKey: .showTyping)) ?? true
        if let raw = try? container.decodeIfPresent([String].self, forKey: .ownShownActivities) {
            self.ownShownActivities = raw.compactMap(MTGhostActivityKind.init(rawValue:))
        } else {
            self.ownShownActivities = nil
        }
        self.readOnAction = try? container.decodeIfPresent(Bool.self, forKey: .readOnAction)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.kind, forKey: .kind)
        try container.encode(self.readMessages, forKey: .readMessages)
        try container.encode(self.readStories, forKey: .readStories)
        try container.encode(self.showOnline, forKey: .showOnline)
        try container.encode(self.showTyping, forKey: .showTyping)
        try container.encodeIfPresent(self.ownShownActivities?.map { $0.rawValue }, forKey: .ownShownActivities)
        try container.encodeIfPresent(self.readOnAction, forKey: .readOnAction)
    }
}

/// A read the server has not been told about: the chat (or forum topic) was read on the device up to
/// `maxId` while ghost mode kept the receipt. `date` lets old entries expire.
public struct MTGhostKeptRead: MTSettingValue {
    public var maxId: Int32
    /// Secret chats are read by date (`messages.readEncryptedHistory`), not by id.
    public var maxTimestamp: Int32
    public var date: Int32

    public init(maxId: Int32, maxTimestamp: Int32, date: Int32) {
        self.maxId = maxId
        self.maxTimestamp = maxTimestamp
        self.date = date
    }

    private enum CodingKeys: String, CodingKey {
        case maxId = "m"
        case maxTimestamp = "t"
        case date = "d"
    }
}

/// Undo record of «Подглядеть онлайн»: what was changed in the "Last seen" privacy rule, written
/// before the change and removed after the rule is restored (survives a killed process).
public struct MTGhostPeekRestore: MTSettingValue {
    public var peer: MTPeerKey
    /// The peer was added to the "always share" list by peek.
    public var addedToAllowed: Bool
    /// The peer was taken out of the "never share" list by peek.
    public var removedFromDisallowed: Bool
    public var date: Int32

    public init(peer: MTPeerKey, addedToAllowed: Bool, removedFromDisallowed: Bool, date: Int32) {
        self.peer = peer
        self.addedToAllowed = addedToAllowed
        self.removedFromDisallowed = removedFromDisallowed
        self.date = date
    }
}

/// Every setting of the ghost-mode zone, declared once. Account scope: ghost mode, exceptions,
/// send delay and "always online" belong to an account; the traces are global.
public enum MTGhostSettings {
    // MARK: Ghost mode (read by the policy, also in the extensions)

    public static let isEnabled = MTAccountSetting<Bool>("ghostMode.isEnabled", default: false, flags: [.extensions])
    public static let hideReadReceipts = MTAccountSetting<Bool>("ghostMode.hideReadReceipts", default: false, flags: [.extensions])
    public static let hideStoryViews = MTAccountSetting<Bool>("ghostMode.hideStoryViews", default: false, flags: [.extensions])
    public static let hideOnline = MTAccountSetting<Bool>("ghostMode.hideOnline", default: false, flags: [.extensions])
    public static let hideTyping = MTAccountSetting<Bool>("ghostMode.hideTyping", default: false, flags: [.extensions])
    public static let readOnAction = MTAccountSetting<Bool>("ghostMode.readOnAction", default: false, flags: [.extensions])

    /// Statuses still sent while «Не отправлять «печатает»» is on. One switch per status.
    public static let shownActivities: [MTGhostActivityKind: MTAccountSetting<Bool>] = {
        var result: [MTGhostActivityKind: MTAccountSetting<Bool>] = [:]
        for kind in MTGhostActivityKind.allCases {
            result[kind] = MTAccountSetting<Bool>("ghostMode.activityShown.\(kind.rawValue)", default: false, flags: [.extensions])
        }
        return result
    }()

    // MARK: Exceptions

    /// `MTPeerKey.stringValue` → exception.
    public static let exceptions = MTAccountSetting<[String: MTGhostException]>("ghostMode.exceptions", default: [:], flags: [.extensions])
    public static let exceptAllChannels = MTAccountSetting<Bool>("ghostMode.exceptAllChannels", default: false, flags: [.extensions])
    public static let exceptAllGroups = MTAccountSetting<Bool>("ghostMode.exceptAllGroups", default: false, flags: [.extensions])
    public static let exceptFolders = MTAccountSetting<Set<Int32>>("ghostMode.exceptFolders", default: [], flags: [.extensions])

    // MARK: Service state (not exported, not reset)

    /// Reads kept on the device: `<peer>` or `<peer>#<thread>` → entry.
    public static let keptReads = MTAccountSetting<[String: MTGhostKeptRead]>("ghostMode.keptReads", default: [:], flags: [.extensions, .noExport])
    /// What the server is known to have read: same keys → max id.
    public static let serverReads = MTAccountSetting<[String: Int32]>("ghostMode.serverReads", default: [:], flags: [.extensions, .noExport])
    /// «Прочитать локально»: chat → max id read on the device only. A later read past it goes out normally.
    public static let localReads = MTAccountSetting<[String: Int32]>("ghostMode.localReads", default: [:], flags: [.extensions, .noExport])
    /// Old exception ids without a namespace, resolved against the account's database later.
    public static let legacyUnresolvedPeers = MTAccountSetting<[Int64]>("ghostMode.legacyUnresolvedPeers", default: [], flags: [.noExport])
    public static let peekRestore = MTAccountSetting<MTGhostPeekRestore?>("ghostMode.peekRestore", default: nil, flags: [.noExport])

    // MARK: Other functions of the zone

    public static let alwaysOnline = MTAccountSetting<Bool>("alwaysOnline.isEnabled", default: false)
    public static let hideBlockedMessages = MTAccountSetting<Bool>("ghostMode.hideBlockedMessages", default: false)

    public static let sendDelayEnabled = MTAccountSetting<Bool>("sendDelay.isEnabled", default: false, flags: [.extensions])
    /// One delay for every message (since 2026-10-27; replaced the text and media delays), seconds,
    /// `MTSendDelaySeconds.range`.
    public static let sendDelaySeconds = MTAccountSetting<Double>("sendDelay.seconds", default: MTSendDelaySeconds.defaultValue, flags: [.extensions])

    // MARK: Traces (global)

    /// On by default, as Swiftgram's `confirmCalls` (MediaTok,.
    public static let confirmCalls = MTSetting<Bool>("ghostMode.confirmCalls", default: true)
    public static let warnBeforeStories = MTSetting<Bool>("ghostMode.warnBeforeStories", default: false)
    /// On by default, as Swiftgram's `hidePhoneInSettings`.
    public static let hidePhoneInSettings = MTSetting<Bool>("ghostMode.hidePhoneInSettings", default: true)

    /// Touches every declaration so the registry knows them before export, search and migrations.
    static func declare() {
        let _ = MTGhostSettings.isEnabled
        let _ = MTGhostSettings.hideReadReceipts
        let _ = MTGhostSettings.hideStoryViews
        let _ = MTGhostSettings.hideOnline
        let _ = MTGhostSettings.hideTyping
        let _ = MTGhostSettings.readOnAction
        let _ = MTGhostSettings.shownActivities
        let _ = MTGhostSettings.exceptions
        let _ = MTGhostSettings.exceptAllChannels
        let _ = MTGhostSettings.exceptAllGroups
        let _ = MTGhostSettings.exceptFolders
        let _ = MTGhostSettings.keptReads
        let _ = MTGhostSettings.serverReads
        let _ = MTGhostSettings.localReads
        let _ = MTGhostSettings.legacyUnresolvedPeers
        let _ = MTGhostSettings.peekRestore
        let _ = MTGhostSettings.alwaysOnline
        let _ = MTGhostSettings.hideBlockedMessages
        let _ = MTGhostSettings.sendDelayEnabled
        let _ = MTGhostSettings.sendDelaySeconds
        let _ = MTGhostSettings.confirmCalls
        let _ = MTGhostSettings.warnBeforeStories
        let _ = MTGhostSettings.hidePhoneInSettings
    }

    /// The setting of one status switch (always present: the table holds every case).
    public static func shownActivity(_ kind: MTGhostActivityKind) -> MTAccountSetting<Bool> {
        return MTGhostSettings.shownActivities[kind]!
    }
}

public extension PeerId {
    /// Key of a chat in the ghost-mode tables.
    var mtGhostKey: String {
        return self.mtKey.stringValue
    }

    /// Key of a forum topic / monoforum thread in the read tables.
    func mtGhostReadKey(threadId: Int64?) -> String {
        if let threadId = threadId {
            return "\(self.mtKey.stringValue)#\(threadId)"
        }
        return self.mtKey.stringValue
    }
}
