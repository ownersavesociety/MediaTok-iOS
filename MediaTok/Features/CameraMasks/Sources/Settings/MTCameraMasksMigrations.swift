import Foundation
import MTCore
import MTCameraPipeline
import MTFeaturesShared

/// One-time moves of the old app's settings of this zone. Only values the user really stored are
/// moved (a missing key keeps the new default, which is Telegram's behaviour). Files (own masks,
/// virtual camera media) are moved separately, off the launch thread, by the stores.
enum MTCameraMasksMigrations {
    static func register() {
        MTMigrations.registerGlobal(id: "cameraMasks.roundVideo.v1", MTCameraMasksMigrations.migrateRoundVideo)
        MTMigrations.registerGlobal(id: "cameraMasks.photoWatermark.v1", MTCameraMasksMigrations.migratePhotoWatermark)
        MTMigrations.registerGlobal(id: "cameraMasks.masks.v1", MTCameraMasksMigrations.migrateMasks)
        MTMigrations.registerGlobal(id: "cameraMasks.virtualCamera.v1", MTCameraMasksMigrations.migrateVirtualCamera)
        // Repairs of what builds up to 13.0 (190) carried over (MEDIA-11, MEDIA-13).
        MTMigrations.registerGlobal(id: "cameraMasks.photoWatermark.appGroup.v1", MTCameraMasksMigrations.movePhotoWatermarkToAppGroup)
        MTMigrations.registerGlobal(id: "cameraMasks.roundVideo.halfZoom.v1", MTCameraMasksMigrations.repairStartZoom)
        MTMigrations.registerGlobal(id: "cameraMasks.masks.catalogSelection.v1", MTCameraMasksMigrations.dropUnavailableCatalogMasks)
    }

    // MARK: Helpers

    private static func moveBool(_ legacy: MTLegacyDefaults, _ key: String, _ setting: MTSetting<Bool>) {
        if let value = legacy.bool(key) {
            setting.set(value)
        }
        legacy.removeLegacyKey(key)
    }

    private static func moveText(_ legacy: MTLegacyDefaults, _ key: String, _ setting: MTSetting<String>, limit: Int) {
        if let value = legacy.string(key) {
            setting.set(String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit)))
        }
        legacy.removeLegacyKey(key)
    }

    private static func moveNumber(_ legacy: MTLegacyDefaults, _ key: String, _ setting: MTSetting<Double>, range: ClosedRange<Double>) {
        if let value = legacy.double(key) {
            setting.set(min(range.upperBound, max(range.lowerBound, value.rounded())))
        }
        legacy.removeLegacyKey(key)
    }

    /// An old integer code → the new string value; unknown codes keep the default.
    private static func moveCode(_ legacy: MTLegacyDefaults, _ key: String, _ setting: MTSetting<String>, _ map: [Int: String]) {
        if let code = legacy.int(key), let value = map[code] {
            setting.set(value)
        }
        legacy.removeLegacyKey(key)
    }

    private static let fontCodes: [Int: String] = [0: MTWatermarkFont.regular.rawValue, 1: MTWatermarkFont.bold.rawValue, 2: MTWatermarkFont.mono.rawValue, 3: MTWatermarkFont.italic.rawValue]
    private static let colorCodes: [Int: String] = [0: MTWatermarkColor.white.rawValue, 1: MTWatermarkColor.black.rawValue, 2: MTWatermarkColor.red.rawValue, 3: MTWatermarkColor.yellow.rawValue]

    // MARK: Round videos (`RoundVideo.*`, two `MiscSettings.*` keys)

    private static func migrateRoundVideo(_ legacy: MTLegacyDefaults) {
        // 400 is Telegram's own side; 720 was offered but is above what the server takes as a
        // round video, so it becomes the largest side that still is one.
        if let side = legacy.int("RoundVideo.resolution") {
            switch side {
            case 512:
                MTRoundVideoSettings.resolution.set("512")
            case 640, 720:
                MTRoundVideoSettings.resolution.set("640")
            default:
                break
            }
        }
        legacy.removeLegacyKey("RoundVideo.resolution")
        // 1000 kbit/s was the old default and is Telegram's own rate: it stays «standard».
        if let kbps = legacy.int("RoundVideo.bitrateKbps"), kbps != 1000 {
            MTRoundVideoSettings.bitrate.set(min(4000.0, max(500.0, (Double(kbps) / 500.0).rounded() * 500.0)))
        }
        legacy.removeLegacyKey("RoundVideo.bitrateKbps")
        MTCameraMasksMigrations.moveCode(legacy, "RoundVideo.fps", MTRoundVideoSettings.frameRate, [60: "60"])
        MTCameraMasksMigrations.moveCode(legacy, "RoundVideo.codec", MTRoundVideoSettings.codec, [1: MTRoundVideoCodec.hevc.rawValue])
        MTCameraMasksMigrations.moveCode(legacy, "RoundVideo.stabilization", MTRoundVideoSettings.stabilization, [0: MTRoundVideoStabilization.off.rawValue, 2: MTRoundVideoStabilization.cinematic.rawValue])
        // Code 0 (start at 0.5×) is «0,5× на задней камере» here: 0.5× exists only on the back camera.
        if legacy.int("RoundVideo.startZoom") == 0 {
            MTRoundVideoSettings.rearHalfZoom.set(true)
        }
        MTCameraMasksMigrations.moveCode(legacy, "RoundVideo.startZoom", MTRoundVideoSettings.startZoom, [2: MTRoundVideoStartZoom.two.rawValue, 3: MTRoundVideoStartZoom.last.rawValue])
        MTCameraMasksMigrations.moveBool(legacy, "RoundVideo.rememberZoom", MTRoundVideoSettings.rememberZoom)
        MTCameraMasksMigrations.moveBool(legacy, "RoundVideo.zoomSlider", MTRoundVideoSettings.zoomSlider)
        if let zoom = legacy.double("RoundVideo.lastZoomFactor") {
            MTRoundVideoSettings.lastZoom.set(min(MTRoundVideoConfig.maximumZoom, max(0.5, zoom)))
        }
        legacy.removeLegacyKey("RoundVideo.lastZoomFactor")
        MTCameraMasksMigrations.moveBool(legacy, "RoundVideo.sendAsRegularVideo", MTRoundVideoSettings.sendAsRegularVideo)
        MTCameraMasksMigrations.moveBool(legacy, "RoundVideo.countdownEnabled", MTRoundVideoSettings.countdown)
        MTCameraMasksMigrations.moveBool(legacy, "RoundVideo.viewOnceByDefault", MTRoundVideoSettings.viewOnceByDefault)
        MTCameraMasksMigrations.moveBool(legacy, "RoundVideo.saveCopyToGallery", MTRoundVideoSettings.saveCopyToGallery)
        // Code 0 («video recording») was the old default; the new default leaves the session as
        // Telegram sets it, so only the explicit «conversation» choice is carried over.
        MTCameraMasksMigrations.moveCode(legacy, "RoundVideo.micMode", MTRoundVideoSettings.microphoneMode, [1: MTRoundVideoMicrophoneMode.voiceChat.rawValue])
        MTCameraMasksMigrations.moveBool(legacy, "RoundVideo.normalizeAudio", MTRoundVideoSettings.normalizeAudio)
        MTCameraMasksMigrations.moveBool(legacy, "RoundVideo.muteAudio", MTRoundVideoSettings.muteAudio)
        MTCameraMasksMigrations.moveBool(legacy, "RoundVideo.watermarkEnabled", MTRoundVideoSettings.watermark)
        MTCameraMasksMigrations.moveText(legacy, "RoundVideo.watermarkText", MTRoundVideoSettings.watermarkText, limit: 48)
        MTCameraMasksMigrations.moveCode(legacy, "RoundVideo.watermarkPosition", MTRoundVideoSettings.watermarkPosition, [0: MTRoundWatermarkPosition.bottom.rawValue, 1: MTRoundWatermarkPosition.top.rawValue, 2: MTRoundWatermarkPosition.center.rawValue])
        MTCameraMasksMigrations.moveCode(legacy, "RoundVideo.watermarkFontStyle", MTRoundVideoSettings.watermarkFont, MTCameraMasksMigrations.fontCodes)
        MTCameraMasksMigrations.moveNumber(legacy, "RoundVideo.watermarkSize", MTRoundVideoSettings.watermarkSize, range: 2.0 ... 12.0)
        MTCameraMasksMigrations.moveNumber(legacy, "RoundVideo.watermarkOpacity", MTRoundVideoSettings.watermarkOpacity, range: 10.0 ... 100.0)
        MTCameraMasksMigrations.moveCode(legacy, "RoundVideo.watermarkColor", MTRoundVideoSettings.watermarkColor, MTCameraMasksMigrations.colorCodes)

        MTCameraMasksMigrations.moveBool(legacy, "MiscSettings.autoSendVideosAsRoundVideo", MTRoundVideoSettings.galleryVideosAsRound)
        // The one-shot «send the next video as a round video» flag is replaced by per-asset marks.
        legacy.removeLegacyKey("MiscSettings.sendNextAsRoundVideo")
        MTCameraMasksMigrations.moveBool(legacy, "MiscSettings.roundVideoFlipAnimation", MTRoundVideoSettings.flipAnimation)

        // SG-F4, round videos from the rear camera.
        MTCameraMasksMigrations.moveBool(legacy, "startTelescopeWithRearCam", MTRoundVideoSettings.startWithRearCamera)
        // SG-F5, the camera tile of the attachment gallery.
        MTCameraMasksMigrations.moveBool(legacy, "disableGalleryCamera", MTGalleryCameraSettings.hideCamera)
        MTCameraMasksMigrations.moveBool(legacy, "disableGalleryCameraPreview", MTGalleryCameraSettings.noLivePreview)
    }

    // MARK: Photo watermark (`MiscSettings.photoWatermark*`)

    private static func migratePhotoWatermark(_ legacy: MTLegacyDefaults) {
        MTCameraMasksMigrations.moveBool(legacy, "MiscSettings.photoWatermarkEnabled", MTPhotoWatermarkSettings.enabled)
        MTCameraMasksMigrations.moveText(legacy, "MiscSettings.photoWatermarkText", MTPhotoWatermarkSettings.text, limit: 40)
        MTCameraMasksMigrations.moveCode(legacy, "MiscSettings.photoWatermarkPosition", MTPhotoWatermarkSettings.position, [
            0: MTPhotoWatermarkPosition.bottomRight.rawValue,
            1: MTPhotoWatermarkPosition.topLeft.rawValue,
            2: MTPhotoWatermarkPosition.topRight.rawValue,
            3: MTPhotoWatermarkPosition.center.rawValue,
            4: MTPhotoWatermarkPosition.bottomLeft.rawValue
        ])
        MTCameraMasksMigrations.moveCode(legacy, "MiscSettings.photoWatermarkFontStyle", MTPhotoWatermarkSettings.font, MTCameraMasksMigrations.fontCodes)
        MTCameraMasksMigrations.moveNumber(legacy, "MiscSettings.photoWatermarkSize", MTPhotoWatermarkSettings.size, range: 2.0 ... 12.0)
        MTCameraMasksMigrations.moveNumber(legacy, "MiscSettings.photoWatermarkOpacity", MTPhotoWatermarkSettings.opacity, range: 10.0 ... 100.0)
        MTCameraMasksMigrations.moveCode(legacy, "MiscSettings.photoWatermarkColor", MTPhotoWatermarkSettings.color, MTCameraMasksMigrations.colorCodes)
        MTCameraMasksMigrations.moveBool(legacy, "MiscSettings.photoWatermarkTiled", MTPhotoWatermarkSettings.tiled)
    }

    // MARK: Masks and the anonymous mode

    /// A catalog mask can be used only while the catalog can be downloaded; the old app's copies of
    /// catalog masks are not carried over (`MTMaskStore.migrateLegacyMasks` drops them).
    private static func isUsable(_ selection: MTMaskSelection) -> Bool {
        switch selection {
        case .none:
            return false
        case .catalog:
            return MTMaskCatalog.isAvailable
        case .builtIn, .user:
            return true
        }
    }

    private static func migrateMasks(_ legacy: MTLegacyDefaults) {
        // A chosen mask applied to every round video in the old app: the new switch is turned on
        // only for users who had one this build can show (a catalog mask can not be prepared while
        // the catalog is off: the switch would be on and nothing would happen).
        if let stored = legacy.string("selectedVideoMaskSelection"), let selection = MTMaskSelection.fromLegacy(stored), MTCameraMasksMigrations.isUsable(selection) {
            MTMaskSettings.selection.set(selection.storage)
            MTMaskSettings.enabled.set(true)
        }
        legacy.removeLegacyKey("selectedVideoMaskSelection")
        if let megabytes = legacy.int("maskCacheDiskLimitMB") {
            let options = [50, 100, 200, 400, 800, 1024]
            let nearest = options.min(by: { abs($0 - megabytes) < abs($1 - megabytes) }) ?? 200
            MTMaskSettings.cacheLimit.set("\(nearest)")
        }
        legacy.removeLegacyKey("maskCacheDiskLimitMB")
        // «Apply automatically» never did anything (no reader in the old app): dropped.
        legacy.removeLegacyKey("videoMaskAutoApply")
        MTCameraMasksMigrations.moveBool(legacy, "videoMaskCallsEnabled", MTMaskSettings.inCalls)

        if let id = legacy.string("anonymousModeMaskId") {
            // An unusable one keeps the default anonymous mask, so the face is always covered.
            let selection = MTMaskSelection.fromLegacyMaskId(id)
            if MTCameraMasksMigrations.isUsable(selection) {
                MTAnonymousMode.mask.set(selection.storage)
            }
        }
        legacy.removeLegacyKey("anonymousModeMaskId")
        MTCameraMasksMigrations.moveText(legacy, "anonymousModeVoicePreset", MTAnonymousMode.voice, limit: 64)
        // The old mode was one switch for every account plus a snapshot of the voice changer it
        // restored on exit. The new mode is per account and never touches the user's own preset,
        // so the old state is not carried over: the mode starts off.
        for key in ["GG.anonymous.video.active", "GG.anonymous.voice.savedPresetId", "GG.anonymous.voice.savedEnabled", "GG.anonymous.voice.didSaveState"] {
            legacy.removeLegacyKey(key)
        }
        // The old catalog cache lived in UserDefaults; the new one is a file in Caches.
        legacy.removeLegacyKey("GG.masks.catalog.json")
        legacy.removeLegacyKey("GG.masks.catalog.fetchedAt")
    }

    // MARK: Repairs

    /// The photo watermark moved from global.json to the App Group file the share extension reads
    /// (MEDIA-12), under new keys: the values stored under the old ones are carried over.
    private static func movePhotoWatermarkToAppGroup(_ legacy: MTLegacyDefaults) {
        let prefix = "cameraMasks.photoWatermark."
        if let value = MTRetiredSettings.value(prefix + "enabled", as: Bool.self) {
            MTPhotoWatermarkSettings.enabled.set(value)
        }
        if let value = MTRetiredSettings.value(prefix + "text", as: String.self) {
            MTPhotoWatermarkSettings.text.set(value)
        }
        if let value = MTRetiredSettings.value(prefix + "position", as: String.self) {
            MTPhotoWatermarkSettings.position.set(value)
        }
        if let value = MTRetiredSettings.value(prefix + "font", as: String.self) {
            MTPhotoWatermarkSettings.font.set(value)
        }
        if let value = MTRetiredSettings.value(prefix + "size", as: Double.self) {
            MTPhotoWatermarkSettings.size.set(value)
        }
        if let value = MTRetiredSettings.value(prefix + "opacity", as: Double.self) {
            MTPhotoWatermarkSettings.opacity.set(value)
        }
        if let value = MTRetiredSettings.value(prefix + "color", as: String.self) {
            MTPhotoWatermarkSettings.color.set(value)
        }
        if let value = MTRetiredSettings.value(prefix + "tiled", as: Bool.self) {
            MTPhotoWatermarkSettings.tiled.set(value)
        }
        MTRetiredSettings.remove(prefixes: [prefix])
    }

    /// Builds up to 190 carried the old 0.5× start over as a start zoom no menu row offers; it is
    /// «0,5× на задней камере» now. A remembered zoom above the slider's end is cut to it.
    private static func repairStartZoom(_ legacy: MTLegacyDefaults) {
        if MTRoundVideoSettings.startZoom.value == "half" {
            MTRoundVideoSettings.startZoom.reset()
            MTRoundVideoSettings.rearHalfZoom.set(true)
        }
        if MTRoundVideoSettings.lastZoom.value > MTRoundVideoConfig.maximumZoom {
            MTRoundVideoSettings.lastZoom.set(MTRoundVideoConfig.maximumZoom)
        }
    }

    /// Builds up to 190 carried a catalog mask over and switched masks on, although the catalog is
    /// off and the old copies are gone: the choice is dropped (and masks switched off with it), the
    /// anonymous mask goes back to its default.
    private static func dropUnavailableCatalogMasks(_ legacy: MTLegacyDefaults) {
        if MTMaskCatalog.isAvailable {
            return
        }
        if case .catalog = MTMaskSelection(storage: MTMaskSettings.selection.value) {
            MTMaskSettings.selection.reset()
            MTMaskSettings.enabled.set(false)
        }
        if case .catalog = MTMaskSelection(storage: MTAnonymousMode.mask.value) {
            MTAnonymousMode.mask.reset()
        }
    }

    // MARK: Virtual camera (`mtCallVirtualCamera*`)

    private struct LegacyCallMediaItem: Decodable {
        let id: String
        let title: String
        let fileName: String
        let kind: String
        let createdAt: Double
    }

    private static func migrateVirtualCamera(_ legacy: MTLegacyDefaults) {
        if let raw = legacy.string("mtCallVirtualCameraItems"), let data = raw.data(using: .utf8), let items = try? JSONDecoder().decode([LegacyCallMediaItem].self, from: data) {
            // Audio items belong to the soundboard (calls zone), not to the camera.
            let converted: [MTVirtualCameraItem] = items.compactMap { item in
                guard let kind = MTVirtualCameraItem.Kind(rawValue: item.kind) else {
                    return nil
                }
                return MTVirtualCameraItem(id: item.id, title: item.title, fileName: item.fileName, kind: kind, createdAt: item.createdAt)
            }
            if !converted.isEmpty {
                MTVirtualCameraSettings.items.set(converted)
            }
        }
        legacy.removeLegacyKey("mtCallVirtualCameraItems")
        MTCameraMasksMigrations.moveBool(legacy, "mtCallVirtualCameraEnabled", MTVirtualCameraSettings.enabled)
        if let selected = legacy.string("mtCallVirtualCameraSelectedId"), MTVirtualCameraSettings.items.value.contains(where: { $0.id == selected }) {
            MTVirtualCameraSettings.selected.set(selected)
        }
        legacy.removeLegacyKey("mtCallVirtualCameraSelectedId")
        MTCameraMasksMigrations.moveBool(legacy, "mtCallVirtualCameraLoop", MTVirtualCameraSettings.loop)
    }
}
