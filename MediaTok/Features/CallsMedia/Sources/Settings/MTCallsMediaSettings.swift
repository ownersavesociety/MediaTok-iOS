import Foundation
import MTCore
import MTFeaturesShared

/// One sound of the call soundboard. The file lives in the soundboard directory (`MTCallSoundLibrary`);
/// only these metadata are in the settings registry.
struct MTCallSoundItem: Codable, Equatable, MTSettingValue {
    var id: String
    var title: String
    var fileName: String
    /// A sound imported by the legacy MediaTok: the file is still in its old `Documents/mtcall/soundboard`.
    var isLegacy: Bool
    var createdAt: Double
}

/// One saved call recording of an account. The file is in that account's recordings directory.
struct MTCallRecordingItem: Codable, Equatable, MTSettingValue {
    enum Kind: String, Codable {
        case audio
        case video
    }

    var id: String
    var fileName: String
    var kind: Kind
    /// Peer of the 1:1 call (canonical key) and its name at the time of the call.
    var peer: MTPeerKey?
    var peerTitle: String
    var startDate: Double
    var duration: Double
    var size: Int64
}

enum MTDownloadBoostMode: String {
    case off
    case medium
    case maximum
}

/// Every setting of the zone. Declared once here; defaults only here.
enum MTCallsMediaSettings {
    // MARK: Calls

    /// `MTCallRecordingMode.rawValue` (one choice since 2026-10-27; replaced «аудиозвонки» / «видеозвонки»).
    static let recordCalls = MTSetting<String>("calls.record", default: MTCallRecordingMode.off.rawValue)
    static let recordOwnVoice = MTSetting<Bool>("calls.recordOwnVoice", default: false)
    static let silentMute = MTSetting<Bool>("calls.silentMute", default: false)
    static let disableRating = MTSetting<Bool>("calls.disableRating", default: false)
    static let statsOverlay = MTSetting<Bool>("calls.statsOverlay", default: false)
    /// Origin of the dragged stats panel, `[x, y]` relative to the screen; empty = default corner.
    static let statsPanelOrigin = MTSetting<[Double]>("calls.statsPanelOrigin", default: [], flags: [.noExport])
    static let soundboard = MTSetting<Bool>("calls.soundboard", default: false)
    /// 0.1…1.0.
    static let soundboardVolume = MTSetting<Double>("calls.soundboardVolume", default: 0.8)
    static let soundboardDuck = MTSetting<Bool>("calls.soundboardDuck", default: false)
    /// Files stay on this device, so the list is not exported.
    static let soundboardItems = MTSetting<[MTCallSoundItem]>("calls.soundboardItems", default: [], flags: [.noExport])
    static let forceTcp = MTSetting<Bool>("calls.forceTcp", default: false)
    /// Recordings of the account (files in the account's directory).
    static let recordings = MTAccountSetting<[MTCallRecordingItem]>("calls.recordings", default: [], flags: [.noExport])

    /// What «Записывать звонки» is set to.
    static var recordingMode: MTCallRecordingMode {
        return MTCallRecordingMode.resolved(MTCallsMediaSettings.recordCalls.value)
    }

    // MARK: Downloads and quality

    static let statusInChatList = MTSetting<Bool>("downloads.statusInChatList", default: false)
    static let statusInChat = MTSetting<Bool>("downloads.statusInChat", default: false)
    static let uploadBoost = MTSetting<Bool>("downloads.uploadBoost", default: false)
    /// `MTDownloadBoostMode` raw value.
    static let downloadBoost = MTSetting<String>("downloads.downloadBoost", default: MTDownloadBoostMode.off.rawValue)
    /// Declared in MTFeaturesShared (App Group): the share extension follows them too.
    static let photoQuality = MTOutgoingPhotoSettings.quality
    static let largePhotos = MTOutgoingPhotoSettings.largePhotos

    // MARK: Gallery

    /// On by default: Swiftgram adds both items always (MediaTok,.
    static let copyPhotoItem = MTSetting<Bool>("gallery.copyPhoto", default: true)
    static let airPlayItem = MTSetting<Bool>("gallery.airPlay", default: true)

    // MARK: Subtitles

    static let subtitles = MTSetting<Bool>("subtitles.enabled", default: false)
    static let subtitlesTranslate = MTSetting<Bool>("subtitles.translate", default: false)
    /// Target language code; "" = the language of the app.
    static let subtitlesLanguage = MTSetting<String>("subtitles.language", default: "")

    static func declare() {
        let _ = MTCallsMediaSettings.recordCalls
        let _ = MTCallsMediaSettings.recordOwnVoice
        let _ = MTCallsMediaSettings.silentMute
        let _ = MTCallsMediaSettings.disableRating
        let _ = MTCallsMediaSettings.statsOverlay
        let _ = MTCallsMediaSettings.statsPanelOrigin
        let _ = MTCallsMediaSettings.soundboard
        let _ = MTCallsMediaSettings.soundboardVolume
        let _ = MTCallsMediaSettings.soundboardDuck
        let _ = MTCallsMediaSettings.soundboardItems
        let _ = MTCallsMediaSettings.forceTcp
        let _ = MTCallsMediaSettings.recordings

        let _ = MTCallsMediaSettings.statusInChatList
        let _ = MTCallsMediaSettings.statusInChat
        let _ = MTCallsMediaSettings.uploadBoost
        let _ = MTCallsMediaSettings.downloadBoost
        let _ = MTCallsMediaSettings.photoQuality
        let _ = MTCallsMediaSettings.largePhotos

        let _ = MTCallsMediaSettings.copyPhotoItem
        let _ = MTCallsMediaSettings.airPlayItem

        let _ = MTCallsMediaSettings.subtitles
        let _ = MTCallsMediaSettings.subtitlesTranslate
        let _ = MTCallsMediaSettings.subtitlesLanguage
    }
}
