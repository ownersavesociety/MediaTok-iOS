import Foundation
import MTCore

/// Every setting of the camera zone that the upstream camera modules read (round videos, the
/// gallery camera tile, watermarks). Declared once here, in a module that depends on MTCore only,
/// so `Camera`, `CameraNeo`, `CameraLegacy`, `MediaEditor` and the picker read the same registry the
/// menu writes. Defaults are Telegram's own behaviour: with every value at its default, all upstream
/// call sites take their original path.
///
/// Recording reads a snapshot (`MTRoundVideoConfig.recording()`) once per camera session, never
/// these values per frame.
public enum MTRoundVideoSettings {
    // MARK: Quality — 0 means «as Telegram does it»

    /// Side of the square in pixels: "standard" (Telegram's), "400", "512", "640".
    public static let resolution = MTSetting<String>("cameraMasks.roundVideo.resolution", default: "standard")
    /// Average video bitrate, kbit/s: 0 (Telegram's) or 500…4000 (a slider, step 500).
    public static let bitrate = MTSetting<Double>("cameraMasks.roundVideo.bitrate", default: 0.0)
    /// `MTRoundVideoCodec.rawValue`.
    public static let codec = MTSetting<String>("cameraMasks.roundVideo.codec", default: "h264")
    /// "30" or "60".
    public static let frameRate = MTSetting<String>("cameraMasks.roundVideo.frameRate", default: "30")
    /// `MTRoundVideoStabilization.rawValue`.
    public static let stabilization = MTSetting<String>("cameraMasks.roundVideo.stabilization", default: "standard")

    // MARK: Camera

    /// SG-F4: start round videos with the rear camera.
    public static let startWithRearCamera = MTSetting<Bool>("cameraMasks.roundVideo.rearCamera", default: false)
    /// `MTRoundVideoStartZoom.rawValue`.
    public static let startZoom = MTSetting<String>("cameraMasks.roundVideo.startZoom", default: "one")
    public static let rememberZoom = MTSetting<Bool>("cameraMasks.roundVideo.rememberZoom", default: false)
    public static let zoomSlider = MTSetting<Bool>("cameraMasks.roundVideo.zoomSlider", default: false)
    /// The back camera opens at 0.5× (the ultra-wide lens), at the start and after a flip
    ///.
    public static let rearHalfZoom = MTSetting<Bool>("cameraMasks.roundVideo.rearHalfZoom", default: false)
    /// The zoom multiplier the user left the camera at (only kept while `rememberZoom` is on).
    public static let lastZoom = MTSetting<Double>("cameraMasks.roundVideo.lastZoom", default: 1.0, flags: [.noExport])
    public static let flipAnimation = MTSetting<Bool>("cameraMasks.roundVideo.flipAnimation", default: false)

    // MARK: Recording

    public static let countdown = MTSetting<Bool>("cameraMasks.roundVideo.countdown", default: false)
    public static let viewOnceByDefault = MTSetting<Bool>("cameraMasks.roundVideo.viewOnce", default: false)
    public static let sendAsRegularVideo = MTSetting<Bool>("cameraMasks.roundVideo.sendAsVideo", default: false)
    public static let saveCopyToGallery = MTSetting<Bool>("cameraMasks.roundVideo.saveToGallery", default: false)

    // MARK: Sound

    /// `MTRoundVideoMicrophoneMode.rawValue`; "default" leaves the audio session as Telegram sets it.
    public static let microphoneMode = MTSetting<String>("cameraMasks.roundVideo.microphone", default: "default")
    public static let normalizeAudio = MTSetting<Bool>("cameraMasks.roundVideo.normalize", default: false)
    public static let muteAudio = MTSetting<Bool>("cameraMasks.roundVideo.mute", default: false)

    // MARK: Watermark over the circle

    public static let watermark = MTSetting<Bool>("cameraMasks.roundVideo.watermark", default: false)
    public static let watermarkText = MTSetting<String>("cameraMasks.roundVideo.watermarkText", default: "")
    /// `MTRoundWatermarkPosition.rawValue`.
    public static let watermarkPosition = MTSetting<String>("cameraMasks.roundVideo.watermarkPosition", default: "bottom")
    /// `MTWatermarkFont.rawValue`.
    public static let watermarkFont = MTSetting<String>("cameraMasks.roundVideo.watermarkFont", default: "bold")
    /// % of the side, 2…12.
    public static let watermarkSize = MTSetting<Double>("cameraMasks.roundVideo.watermarkSize", default: 6.0)
    /// %, 10…100.
    public static let watermarkOpacity = MTSetting<Double>("cameraMasks.roundVideo.watermarkOpacity", default: 55.0)
    /// `MTWatermarkColor.rawValue`.
    public static let watermarkColor = MTSetting<String>("cameraMasks.roundVideo.watermarkColor", default: "white")

    // MARK: Gallery

    /// Every video picked from the gallery goes out as a round video.
    public static let galleryVideosAsRound = MTSetting<Bool>("cameraMasks.roundVideo.galleryAsRound", default: false)
    /// «Send as a round video» in the attachment picker's «…» menu (for the chosen videos only).
    public static let galleryMenuItem = MTSetting<Bool>("cameraMasks.roundVideo.galleryMenuItem", default: false)

    /// Settings the «reset the round video settings» row resets (the watermark and the gallery keys
    /// have their own rows and are reset with it as well).
    public static var resettableKeys: [MTRoundVideoAnySetting] {
        return [
            MTRoundVideoAnySetting(MTRoundVideoSettings.resolution),
            MTRoundVideoAnySetting(MTRoundVideoSettings.bitrate),
            MTRoundVideoAnySetting(MTRoundVideoSettings.codec),
            MTRoundVideoAnySetting(MTRoundVideoSettings.frameRate),
            MTRoundVideoAnySetting(MTRoundVideoSettings.stabilization),
            MTRoundVideoAnySetting(MTRoundVideoSettings.startWithRearCamera),
            MTRoundVideoAnySetting(MTRoundVideoSettings.startZoom),
            MTRoundVideoAnySetting(MTRoundVideoSettings.rememberZoom),
            MTRoundVideoAnySetting(MTRoundVideoSettings.zoomSlider),
            MTRoundVideoAnySetting(MTRoundVideoSettings.rearHalfZoom),
            MTRoundVideoAnySetting(MTRoundVideoSettings.lastZoom),
            MTRoundVideoAnySetting(MTRoundVideoSettings.flipAnimation),
            MTRoundVideoAnySetting(MTRoundVideoSettings.countdown),
            MTRoundVideoAnySetting(MTRoundVideoSettings.viewOnceByDefault),
            MTRoundVideoAnySetting(MTRoundVideoSettings.sendAsRegularVideo),
            MTRoundVideoAnySetting(MTRoundVideoSettings.saveCopyToGallery),
            MTRoundVideoAnySetting(MTRoundVideoSettings.microphoneMode),
            MTRoundVideoAnySetting(MTRoundVideoSettings.normalizeAudio),
            MTRoundVideoAnySetting(MTRoundVideoSettings.muteAudio),
            MTRoundVideoAnySetting(MTRoundVideoSettings.watermark),
            MTRoundVideoAnySetting(MTRoundVideoSettings.watermarkText),
            MTRoundVideoAnySetting(MTRoundVideoSettings.watermarkPosition),
            MTRoundVideoAnySetting(MTRoundVideoSettings.watermarkFont),
            MTRoundVideoAnySetting(MTRoundVideoSettings.watermarkSize),
            MTRoundVideoAnySetting(MTRoundVideoSettings.watermarkOpacity),
            MTRoundVideoAnySetting(MTRoundVideoSettings.watermarkColor),
            MTRoundVideoAnySetting(MTRoundVideoSettings.galleryVideosAsRound),
            MTRoundVideoAnySetting(MTRoundVideoSettings.galleryMenuItem)
        ]
    }

    static func declare() {
        let _ = MTRoundVideoSettings.resettableKeys
    }
}

/// A type-erased setting for the reset row.
public struct MTRoundVideoAnySetting {
    public let key: String
    public let isDefault: () -> Bool
    public let reset: () -> Void

    init<Value>(_ setting: MTSetting<Value>) {
        self.key = setting.key
        self.isDefault = {
            return setting.isDefault
        }
        self.reset = {
            setting.reset()
        }
    }
}

/// SG-F5: the camera tile in the attachment gallery.
public enum MTGalleryCameraSettings {
    /// No camera tile at all (the picker never starts the camera).
    public static let hideCamera = MTSetting<Bool>("cameraMasks.gallery.hideCamera", default: false)
    /// The tile stays but shows no live feed until it is tapped.
    public static let noLivePreview = MTSetting<Bool>("cameraMasks.gallery.noLivePreview", default: false)

    static func declare() {
        let _ = MTGalleryCameraSettings.hideCamera
        let _ = MTGalleryCameraSettings.noLivePreview
    }
}

/// «Водяной знак на фото». Read once per photo as a snapshot (`MTPhotoWatermarkConfig.current()`).
/// App Group settings: photos sent from other apps through the share extension get the mark too.
/// (Until 13.0 (190) they were global, under `cameraMasks.photoWatermark.*`; moved by the migration
/// `cameraMasks.photoWatermark.appGroup.v1`.)
public enum MTPhotoWatermarkSettings {
    public static let enabled = MTSetting<Bool>("cameraMasks.outgoingWatermark.enabled", default: false, scope: .appGroup, flags: [.extensions])
    public static let text = MTSetting<String>("cameraMasks.outgoingWatermark.text", default: "", scope: .appGroup, flags: [.extensions])
    /// `MTPhotoWatermarkPosition.rawValue`.
    public static let position = MTSetting<String>("cameraMasks.outgoingWatermark.position", default: "bottomRight", scope: .appGroup, flags: [.extensions])
    /// `MTWatermarkFont.rawValue`.
    public static let font = MTSetting<String>("cameraMasks.outgoingWatermark.font", default: "bold", scope: .appGroup, flags: [.extensions])
    /// % of the short side, 2…12.
    public static let size = MTSetting<Double>("cameraMasks.outgoingWatermark.size", default: 4.0, scope: .appGroup, flags: [.extensions])
    /// %, 10…100.
    public static let opacity = MTSetting<Double>("cameraMasks.outgoingWatermark.opacity", default: 55.0, scope: .appGroup, flags: [.extensions])
    /// `MTWatermarkColor.rawValue`.
    public static let color = MTSetting<String>("cameraMasks.outgoingWatermark.color", default: "white", scope: .appGroup, flags: [.extensions])
    public static let tiled = MTSetting<Bool>("cameraMasks.outgoingWatermark.tiled", default: false, scope: .appGroup, flags: [.extensions])

    /// Also from the share extension's launch: the extension reads these.
    public static func declare() {
        let _ = MTPhotoWatermarkSettings.enabled
        let _ = MTPhotoWatermarkSettings.text
        let _ = MTPhotoWatermarkSettings.position
        let _ = MTPhotoWatermarkSettings.font
        let _ = MTPhotoWatermarkSettings.size
        let _ = MTPhotoWatermarkSettings.opacity
        let _ = MTPhotoWatermarkSettings.color
        let _ = MTPhotoWatermarkSettings.tiled
    }
}

public enum MTRoundVideoCodec: String, CaseIterable {
    case h264
    case hevc
}

public enum MTRoundVideoStabilization: String, CaseIterable {
    case standard
    case off
    case cinematic
}

/// 0.5× is not a start zoom: it is «0,5× на задней камере» (`MTRoundVideoSettings.rearHalfZoom`).
public enum MTRoundVideoStartZoom: String, CaseIterable {
    case one
    case two
    case last

    /// Fixed multiplier of the camera's neutral (1×) zoom; `last` is resolved by the config.
    public var multiplier: Double? {
        switch self {
        case .one:
            return 1.0
        case .two:
            return 2.0
        case .last:
            return nil
        }
    }
}

public enum MTRoundVideoMicrophoneMode: String, CaseIterable {
    /// The audio session as Telegram configures it.
    case standard = "default"
    /// `AVAudioSession.Mode.videoRecording`: no voice processing.
    case videoRecording
    /// `AVAudioSession.Mode.voiceChat`: the system's noise and echo cancellation.
    case voiceChat
}

public enum MTWatermarkFont: String, CaseIterable {
    case regular
    case bold
    case mono
    case italic
}

public enum MTWatermarkColor: String, CaseIterable {
    case white
    case black
    case red
    case yellow
}

/// Positions inside the circle: only horizontally centred ones, corners would be cut by the mask.
public enum MTRoundWatermarkPosition: String, CaseIterable {
    case bottom
    case top
    case center
}

public enum MTPhotoWatermarkPosition: String, CaseIterable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft
    case center
}

public enum MTCameraPipelineSettings {
    /// Touches every declaration of this module (called from `MTCameraMasksModule.register()`).
    public static func declare() {
        MTRoundVideoSettings.declare()
        MTGalleryCameraSettings.declare()
        MTPhotoWatermarkSettings.declare()
    }
}
