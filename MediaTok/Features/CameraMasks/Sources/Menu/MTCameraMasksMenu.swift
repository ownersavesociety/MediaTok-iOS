import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import PromptUI
import PresentationDataUtils
import MTCore
import MTSettingsUI
import MTCameraPipeline
import MTFeaturesShared

/// Menu rows of the zone: «Медиа и звонки › Кружки и камера» (masks, round video settings, gallery,
/// photo watermark), the «Маски и камера» section of «Звонки», «Приватность › Анонимный режим».
/// Every row is a binding to a registry setting: writing it rebuilds the screen, nothing else.
enum MTCameraMasksMenu {
    static let tab = MTMenuTabID.mediaCameraVideoMessages

    static let sectionQuality = MTMenuSectionID("media.cameraVideoMessages.quality")
    static let sectionCamera = MTMenuSectionID("media.cameraVideoMessages.camera")
    static let sectionRecording = MTMenuSectionID("media.cameraVideoMessages.recording")
    static let sectionSound = MTMenuSectionID("media.cameraVideoMessages.sound")
    static let sectionWatermark = MTMenuSectionID("media.cameraVideoMessages.watermark")
    static let sectionGallery = MTMenuSectionID("media.cameraVideoMessages.gallery")
    static let sectionPhotoWatermark = MTMenuSectionID("media.cameraVideoMessages.photoWatermark")
    static let sectionReset = MTMenuSectionID("media.cameraVideoMessages.reset")
    static let sectionCalls = MTMenuSectionID("media.calls.cameraMasks")

    static let masksTab = MTMenuTabID("cameraMasks.masks")
    static let studioTab = MTMenuTabID("cameraMasks.studio")
    static let virtualCameraTab = MTMenuTabID("cameraMasks.virtualCamera")

    static func register() {
        MTCameraMasksMenu.registerSections()
        MTCameraMasksMenu.registerPreview()
        MTCameraMasksMenu.registerMasks()
        MTCameraMasksMenu.registerQuality()
        MTCameraMasksMenu.registerCamera()
        MTCameraMasksMenu.registerRecording()
        MTCameraMasksMenu.registerSound()
        MTCameraMasksMenu.registerWatermark()
        MTCameraMasksMenu.registerGallery()
        MTCameraMasksMenu.registerPhotoWatermark()
        MTCameraMasksMenu.registerReset()
        MTCameraMasksMenu.registerCalls()
        MTCameraMasksMenu.registerAnonymousMode()
    }

    private static func registerSections() {
        let screen = MTMenuScreenID.tab(MTCameraMasksMenu.tab)
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTCameraMasksMenu.sectionQuality, screen: screen, order: 300, header: { MTStrings.CameraMasks.Round.Section.quality }, footer: { _ in MTStrings.CameraMasks.Round.qualityFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTCameraMasksMenu.sectionCamera, screen: screen, order: 400, header: { MTStrings.CameraMasks.Round.Section.camera }, footer: { _ in MTStrings.CameraMasks.Round.cameraFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTCameraMasksMenu.sectionRecording, screen: screen, order: 500, header: { MTStrings.CameraMasks.Round.Section.recording }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTCameraMasksMenu.sectionSound, screen: screen, order: 600, header: { MTStrings.CameraMasks.Round.Section.sound }, footer: { _ in MTStrings.CameraMasks.Round.soundFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTCameraMasksMenu.sectionWatermark, screen: screen, order: 700, header: { MTStrings.CameraMasks.Round.Section.watermark }, footer: { _ in MTStrings.CameraMasks.Round.watermarkFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTCameraMasksMenu.sectionGallery, screen: screen, order: 800, header: { MTStrings.CameraMasks.Round.Section.gallery }, footer: { _ in MTStrings.CameraMasks.Round.galleryFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTCameraMasksMenu.sectionPhotoWatermark, screen: screen, order: 900, header: { MTStrings.CameraMasks.Photo.section }, footer: { _ in MTStrings.CameraMasks.Photo.footer }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTCameraMasksMenu.sectionReset, screen: screen, order: 1000))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTCameraMasksMenu.sectionCalls, screen: .tab(.mediaCalls), order: 800, header: { MTStrings.CameraMasks.Calls.section }, footer: { _ in MTStrings.CameraMasks.Calls.footer }))
    }

    private static func registerPreview() {
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.preview",
            section: .preview(of: MTCameraMasksMenu.tab),
            order: 100,
            title: { "" },
            kind: .preview(.custom(height: 236.0, make: { _ in
                return MTRoundVideoPreviewView(frame: .zero)
            }))
        ))
    }

    // MARK: Masks

    private static func registerMasks() {
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.masks.enabled",
            section: .main(of: MTCameraMasksMenu.tab),
            order: 100,
            title: { MTStrings.CameraMasks.Masks.enabled },
            subtitle: { MTStrings.CameraMasks.Masks.enabledInfo },
            kind: .toggle(.global(MTMaskSettings.enabled)),
            searchKeywords: { [MTStrings.CameraMasks.Masks.keywords] }
        ))
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: MTCameraMasksMenu.masksTab,
                parent: .tab(MTCameraMasksMenu.tab),
                title: { MTStrings.CameraMasks.Masks.title },
                makeScreen: { context in
                    return mtMakeMaskLibraryScreen(context: context.context, target: .current)
                },
                searchKeywords: { [MTStrings.CameraMasks.Masks.keywords] }
            ),
            linkIn: .main(of: MTCameraMasksMenu.tab),
            order: 200,
            subtitle: { MTStrings.CameraMasks.Masks.chooseInfo },
            icon: .system("theatermasks"),
            label: { context in
                return MTMaskEngine.title(MTMaskSelection(storage: MTMaskSettings.selection.value))
            }
        )
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: MTCameraMasksMenu.studioTab,
                parent: .tab(MTCameraMasksMenu.tab),
                title: { MTStrings.CameraMasks.Studio.title },
                makeScreen: { context in
                    return mtMakeMaskStudioHome(context: context.context)
                },
                searchKeywords: { [MTStrings.CameraMasks.Studio.keywords] }
            ),
            linkIn: .main(of: MTCameraMasksMenu.tab),
            order: 300,
            subtitle: { MTStrings.CameraMasks.Studio.info },
            icon: .system("paintbrush"),
            label: { _ in
                let count = MTMaskStore.shared.currentEntries.count
                return count > 0 ? "\(count)" : nil
            }
        )
    }

    // MARK: Quality

    private static func registerQuality() {
        let section = MTCameraMasksMenu.sectionQuality
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.resolution",
            section: section,
            order: 100,
            title: { MTStrings.CameraMasks.Round.resolution },
            kind: .choice(.global(MTRoundVideoSettings.resolution), options: [
                MTMenuChoiceOption(value: "standard", title: { MTStrings.CameraMasks.Round.asTelegram }),
                MTMenuChoiceOption(value: "400", title: { MTStrings.CameraMasks.Round.side(side: "400") }),
                MTMenuChoiceOption(value: "512", title: { MTStrings.CameraMasks.Round.side(side: "512") }),
                MTMenuChoiceOption(value: "640", title: { MTStrings.CameraMasks.Round.side(side: "640") })
            ]),
            searchKeywords: { [MTStrings.CameraMasks.Round.qualityKeywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.bitrate",
            section: section,
            order: 200,
            title: { MTStrings.CameraMasks.Round.bitrate },
            kind: .slider(.global(MTRoundVideoSettings.bitrate), range: 0.0 ... 4000.0, step: 500.0, format: { value in
                if value < 500.0 {
                    return MTStrings.CameraMasks.Round.asTelegram
                }
                // What is really recorded: above Telegram's size limit the bitrate is lowered
                // (MTRoundVideoConfig.recording), so the slider says so instead of the chosen value.
                if let maximum = MTRoundVideoServerLimits.maximumVideoKbps(audioKbps: MTRoundVideoServerLimits.audioKbps), Double(maximum) < min(4000.0, value) {
                    return MTStrings.CameraMasks.Round.bitrateLimited(value: String(format: "%.1f", Double(maximum) / 1000.0))
                }
                return MTStrings.CameraMasks.Round.bitrateValue(value: String(format: "%.1f", value / 1000.0))
            })
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.codec",
            section: section,
            order: 300,
            title: { MTStrings.CameraMasks.Round.codec },
            kind: .choice(.global(MTRoundVideoSettings.codec), options: [
                MTMenuChoiceOption(value: MTRoundVideoCodec.h264.rawValue, title: { MTStrings.CameraMasks.Round.codecH264 }),
                MTMenuChoiceOption(value: MTRoundVideoCodec.hevc.rawValue, title: { MTStrings.CameraMasks.Round.codecHevc })
            ])
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.frameRate",
            section: section,
            order: 400,
            title: { MTStrings.CameraMasks.Round.frameRate },
            subtitle: { MTStrings.CameraMasks.Round.frameRateInfo },
            kind: .choice(.global(MTRoundVideoSettings.frameRate), options: [
                MTMenuChoiceOption(value: "30", title: { MTStrings.CameraMasks.Round.fps(fps: "30") }),
                MTMenuChoiceOption(value: "60", title: { MTStrings.CameraMasks.Round.fps(fps: "60") })
            ])
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.stabilization",
            section: section,
            order: 500,
            title: { MTStrings.CameraMasks.Round.stabilization },
            kind: .choice(.global(MTRoundVideoSettings.stabilization), options: [
                MTMenuChoiceOption(value: MTRoundVideoStabilization.standard.rawValue, title: { MTStrings.CameraMasks.Round.stabilizationStandard }),
                MTMenuChoiceOption(value: MTRoundVideoStabilization.off.rawValue, title: { MTStrings.CameraMasks.Round.stabilizationOff }),
                MTMenuChoiceOption(value: MTRoundVideoStabilization.cinematic.rawValue, title: { MTStrings.CameraMasks.Round.stabilizationCinematic })
            ])
        ))
    }

    // MARK: Camera

    private static func registerCamera() {
        let section = MTCameraMasksMenu.sectionCamera
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.rearCamera",
            section: section,
            order: 100,
            title: { MTStrings.CameraMasks.Round.rearCamera },
            subtitle: { MTStrings.CameraMasks.Round.rearCameraInfo },
            kind: .toggle(.global(MTRoundVideoSettings.startWithRearCamera))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.startZoom",
            section: section,
            order: 200,
            title: { MTStrings.CameraMasks.Round.startZoom },
            kind: .choice(.global(MTRoundVideoSettings.startZoom), options: [
                MTMenuChoiceOption(value: MTRoundVideoStartZoom.one.rawValue, title: { MTStrings.CameraMasks.Round.zoomOne }),
                MTMenuChoiceOption(value: MTRoundVideoStartZoom.two.rawValue, title: { MTStrings.CameraMasks.Round.zoomTwo }),
                MTMenuChoiceOption(value: MTRoundVideoStartZoom.last.rawValue, title: { MTStrings.CameraMasks.Round.zoomLast })
            ])
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.rememberZoom",
            section: section,
            order: 300,
            title: { MTStrings.CameraMasks.Round.rememberZoom },
            subtitle: { MTStrings.CameraMasks.Round.rememberZoomInfo },
            kind: .toggle(.global(MTRoundVideoSettings.rememberZoom))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.zoomSlider",
            section: section,
            order: 400,
            title: { MTStrings.CameraMasks.Round.zoomSlider },
            subtitle: { MTStrings.CameraMasks.Round.zoomSliderInfo },
            kind: .toggle(.global(MTRoundVideoSettings.zoomSlider))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.rearHalfZoom",
            section: section,
            order: 450,
            title: { MTStrings.CameraMasks.Round.rearHalfZoom },
            subtitle: { MTStrings.CameraMasks.Round.rearHalfZoomInfo },
            kind: .toggle(.global(MTRoundVideoSettings.rearHalfZoom)),
            isVisible: { _ in MTRoundVideoConfig.hasUltraWideCamera }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.flipAnimation",
            section: section,
            order: 500,
            title: { MTStrings.CameraMasks.Round.flipAnimation },
            subtitle: { MTStrings.CameraMasks.Round.flipAnimationInfo },
            kind: .toggle(.global(MTRoundVideoSettings.flipAnimation))
        ))
    }

    // MARK: Recording

    private static func registerRecording() {
        let section = MTCameraMasksMenu.sectionRecording
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.countdown", section: section, order: 100, title: { MTStrings.CameraMasks.Round.countdown }, subtitle: { MTStrings.CameraMasks.Round.countdownInfo }, kind: .toggle(.global(MTRoundVideoSettings.countdown))))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.viewOnce", section: section, order: 200, title: { MTStrings.CameraMasks.Round.viewOnce }, subtitle: { MTStrings.CameraMasks.Round.viewOnceInfo }, kind: .toggle(.global(MTRoundVideoSettings.viewOnceByDefault))))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.sendAsVideo", section: section, order: 300, title: { MTStrings.CameraMasks.Round.sendAsVideo }, subtitle: { MTStrings.CameraMasks.Round.sendAsVideoInfo }, kind: .toggle(.global(MTRoundVideoSettings.sendAsRegularVideo))))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.saveToGallery", section: section, order: 400, title: { MTStrings.CameraMasks.Round.saveToGallery }, subtitle: { MTStrings.CameraMasks.Round.saveToGalleryInfo }, kind: .toggle(.global(MTRoundVideoSettings.saveCopyToGallery))))
    }

    // MARK: Sound

    private static func registerSound() {
        let section = MTCameraMasksMenu.sectionSound
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.microphone",
            section: section,
            order: 100,
            title: { MTStrings.CameraMasks.Round.microphone },
            kind: .choice(.global(MTRoundVideoSettings.microphoneMode), options: [
                MTMenuChoiceOption(value: MTRoundVideoMicrophoneMode.standard.rawValue, title: { MTStrings.CameraMasks.Round.asTelegram }),
                MTMenuChoiceOption(value: MTRoundVideoMicrophoneMode.videoRecording.rawValue, title: { MTStrings.CameraMasks.Round.microphoneVideo }),
                MTMenuChoiceOption(value: MTRoundVideoMicrophoneMode.voiceChat.rawValue, title: { MTStrings.CameraMasks.Round.microphoneVoice })
            ])
        ))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.normalize", section: section, order: 200, title: { MTStrings.CameraMasks.Round.normalize }, subtitle: { MTStrings.CameraMasks.Round.normalizeInfo }, kind: .toggle(.global(MTRoundVideoSettings.normalizeAudio))))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.mute", section: section, order: 300, title: { MTStrings.CameraMasks.Round.mute }, subtitle: { MTStrings.CameraMasks.Round.muteInfo }, kind: .toggle(.global(MTRoundVideoSettings.muteAudio))))
    }

    // MARK: Watermark (round)

    static func fontOptions() -> [MTMenuChoiceOption] {
        return [
            MTMenuChoiceOption(value: MTWatermarkFont.regular.rawValue, title: { MTStrings.CameraMasks.Watermark.fontRegular }),
            MTMenuChoiceOption(value: MTWatermarkFont.bold.rawValue, title: { MTStrings.CameraMasks.Watermark.fontBold }),
            MTMenuChoiceOption(value: MTWatermarkFont.mono.rawValue, title: { MTStrings.CameraMasks.Watermark.fontMono }),
            MTMenuChoiceOption(value: MTWatermarkFont.italic.rawValue, title: { MTStrings.CameraMasks.Watermark.fontItalic })
        ]
    }

    static func colorOptions() -> [MTMenuChoiceOption] {
        return [
            MTMenuChoiceOption(value: MTWatermarkColor.white.rawValue, title: { MTStrings.CameraMasks.Watermark.colorWhite }),
            MTMenuChoiceOption(value: MTWatermarkColor.black.rawValue, title: { MTStrings.CameraMasks.Watermark.colorBlack }),
            MTMenuChoiceOption(value: MTWatermarkColor.red.rawValue, title: { MTStrings.CameraMasks.Watermark.colorRed }),
            MTMenuChoiceOption(value: MTWatermarkColor.yellow.rawValue, title: { MTStrings.CameraMasks.Watermark.colorYellow })
        ]
    }

    /// A row that edits a text setting in a prompt.
    static func textRow(id: String, section: MTMenuSectionID, order: Int, title: @escaping () -> String, prompt: @escaping () -> String, setting: MTSetting<String>, limit: Int, isVisible: ((MTMenuContext) -> Bool)?) -> MTMenuRow {
        return MTMenuRow(
            id: id,
            section: section,
            order: order,
            title: title,
            kind: .action({ context in
                context.present(promptController(context: context.context, text: prompt(), value: setting.value, placeholder: MTStrings.CameraMasks.Watermark.placeholder, characterLimit: limit, apply: { value in
                    if let value {
                        setting.set(value.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }))
            }),
            isVisible: isVisible,
            label: { _ in
                let value = setting.value
                return value.isEmpty ? MTStrings.CameraMasks.Watermark.noText : value
            }
        )
    }

    private static func registerWatermark() {
        let section = MTCameraMasksMenu.sectionWatermark
        let isOn: (MTMenuContext) -> Bool = { _ in
            return MTRoundVideoSettings.watermark.value
        }
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.watermark", section: section, order: 100, title: { MTStrings.CameraMasks.Round.watermark }, kind: .toggle(.global(MTRoundVideoSettings.watermark)), searchKeywords: { [MTStrings.CameraMasks.Watermark.keywords] }))
        MTMenuRegistry.register(MTCameraMasksMenu.textRow(id: "cameraMasks.roundVideo.watermarkText", section: section, order: 200, title: { MTStrings.CameraMasks.Watermark.text }, prompt: { MTStrings.CameraMasks.Watermark.textPrompt }, setting: MTRoundVideoSettings.watermarkText, limit: 48, isVisible: isOn))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.watermarkPosition",
            section: section,
            order: 300,
            title: { MTStrings.CameraMasks.Watermark.position },
            kind: .choice(.global(MTRoundVideoSettings.watermarkPosition), options: [
                MTMenuChoiceOption(value: MTRoundWatermarkPosition.bottom.rawValue, title: { MTStrings.CameraMasks.Watermark.positionBottom }),
                MTMenuChoiceOption(value: MTRoundWatermarkPosition.top.rawValue, title: { MTStrings.CameraMasks.Watermark.positionTop }),
                MTMenuChoiceOption(value: MTRoundWatermarkPosition.center.rawValue, title: { MTStrings.CameraMasks.Watermark.positionCenter })
            ]),
            isVisible: isOn
        ))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.watermarkFont", section: section, order: 400, title: { MTStrings.CameraMasks.Watermark.font }, kind: .choice(.global(MTRoundVideoSettings.watermarkFont), options: MTCameraMasksMenu.fontOptions()), isVisible: isOn))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.watermarkSize", section: section, order: 500, title: { MTStrings.CameraMasks.Watermark.size }, kind: .slider(.global(MTRoundVideoSettings.watermarkSize), range: 2.0 ... 12.0, step: 1.0, format: { value in MTStrings.CameraMasks.Watermark.percent(value: "\(Int(value))") }), isVisible: isOn))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.watermarkOpacity", section: section, order: 600, title: { MTStrings.CameraMasks.Watermark.opacity }, kind: .slider(.global(MTRoundVideoSettings.watermarkOpacity), range: 10.0 ... 100.0, step: 5.0, format: { value in MTStrings.CameraMasks.Watermark.percent(value: "\(Int(value))") }), isVisible: isOn))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.watermarkColor", section: section, order: 700, title: { MTStrings.CameraMasks.Watermark.color }, kind: .choice(.global(MTRoundVideoSettings.watermarkColor), options: MTCameraMasksMenu.colorOptions()), isVisible: isOn))
    }

    // MARK: Gallery (video → round, SG-F5)

    private static func registerGallery() {
        let section = MTCameraMasksMenu.sectionGallery
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.galleryAsRound", section: section, order: 100, title: { MTStrings.CameraMasks.Round.galleryAsRound }, subtitle: { MTStrings.CameraMasks.Round.galleryAsRoundInfo }, kind: .toggle(.global(MTRoundVideoSettings.galleryVideosAsRound))))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.roundVideo.galleryMenuItem", section: section, order: 150, title: { MTStrings.CameraMasks.Round.galleryMenuItem }, subtitle: { MTStrings.CameraMasks.Round.galleryMenuItemInfo }, kind: .toggle(.global(MTRoundVideoSettings.galleryMenuItem)), isVisible: { _ in !MTRoundVideoSettings.galleryVideosAsRound.value }))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.gallery.hideCamera", section: section, order: 200, title: { MTStrings.CameraMasks.Gallery.hideCamera }, subtitle: { MTStrings.CameraMasks.Gallery.hideCameraInfo }, kind: .toggle(.global(MTGalleryCameraSettings.hideCamera))))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.gallery.noLivePreview", section: section, order: 300, title: { MTStrings.CameraMasks.Gallery.noLivePreview }, subtitle: { MTStrings.CameraMasks.Gallery.noLivePreviewInfo }, kind: .toggle(.global(MTGalleryCameraSettings.noLivePreview)), isVisible: { _ in !MTGalleryCameraSettings.hideCamera.value }))
    }

    // MARK: Photo watermark

    private static func registerPhotoWatermark() {
        let section = MTCameraMasksMenu.sectionPhotoWatermark
        let isOn: (MTMenuContext) -> Bool = { _ in
            return MTPhotoWatermarkSettings.enabled.value
        }
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.photoWatermark.preview", section: section, order: 50, title: { "" }, kind: .preview(.custom(height: 190.0, make: { _ in MTPhotoWatermarkPreviewView(frame: .zero) }))))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.photoWatermark.enabled", section: section, order: 100, title: { MTStrings.CameraMasks.Photo.enabled }, subtitle: { MTStrings.CameraMasks.Photo.enabledInfo }, kind: .toggle(.global(MTPhotoWatermarkSettings.enabled)), searchKeywords: { [MTStrings.CameraMasks.Watermark.keywords] }))
        MTMenuRegistry.register(MTCameraMasksMenu.textRow(id: "cameraMasks.photoWatermark.text", section: section, order: 200, title: { MTStrings.CameraMasks.Watermark.text }, prompt: { MTStrings.CameraMasks.Watermark.textPrompt }, setting: MTPhotoWatermarkSettings.text, limit: 40, isVisible: isOn))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.photoWatermark.tiled", section: section, order: 300, title: { MTStrings.CameraMasks.Photo.tiled }, kind: .toggle(.global(MTPhotoWatermarkSettings.tiled)), isVisible: isOn))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.photoWatermark.position",
            section: section,
            order: 400,
            title: { MTStrings.CameraMasks.Watermark.position },
            kind: .choice(.global(MTPhotoWatermarkSettings.position), options: [
                MTMenuChoiceOption(value: MTPhotoWatermarkPosition.bottomRight.rawValue, title: { MTStrings.CameraMasks.Photo.bottomRight }),
                MTMenuChoiceOption(value: MTPhotoWatermarkPosition.bottomLeft.rawValue, title: { MTStrings.CameraMasks.Photo.bottomLeft }),
                MTMenuChoiceOption(value: MTPhotoWatermarkPosition.topRight.rawValue, title: { MTStrings.CameraMasks.Photo.topRight }),
                MTMenuChoiceOption(value: MTPhotoWatermarkPosition.topLeft.rawValue, title: { MTStrings.CameraMasks.Photo.topLeft }),
                MTMenuChoiceOption(value: MTPhotoWatermarkPosition.center.rawValue, title: { MTStrings.CameraMasks.Watermark.positionCenter })
            ]),
            isVisible: { context in isOn(context) && !MTPhotoWatermarkSettings.tiled.value }
        ))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.photoWatermark.font", section: section, order: 500, title: { MTStrings.CameraMasks.Watermark.font }, kind: .choice(.global(MTPhotoWatermarkSettings.font), options: MTCameraMasksMenu.fontOptions()), isVisible: isOn))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.photoWatermark.size", section: section, order: 600, title: { MTStrings.CameraMasks.Watermark.size }, kind: .slider(.global(MTPhotoWatermarkSettings.size), range: 2.0 ... 12.0, step: 1.0, format: { value in MTStrings.CameraMasks.Watermark.percent(value: "\(Int(value))") }), isVisible: isOn))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.photoWatermark.opacity", section: section, order: 700, title: { MTStrings.CameraMasks.Watermark.opacity }, kind: .slider(.global(MTPhotoWatermarkSettings.opacity), range: 10.0 ... 100.0, step: 5.0, format: { value in MTStrings.CameraMasks.Watermark.percent(value: "\(Int(value))") }), isVisible: isOn))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.photoWatermark.color", section: section, order: 800, title: { MTStrings.CameraMasks.Watermark.color }, kind: .choice(.global(MTPhotoWatermarkSettings.color), options: MTCameraMasksMenu.colorOptions()), isVisible: isOn))
    }

    // MARK: Reset

    private static func registerReset() {
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.roundVideo.reset",
            section: MTCameraMasksMenu.sectionReset,
            order: 100,
            title: { MTStrings.CameraMasks.Round.reset },
            kind: .action({ context in
                let presentationData = context.presentationData
                context.present(textAlertController(context: context.context, title: MTStrings.CameraMasks.Round.resetTitle, text: MTStrings.CameraMasks.Round.resetText, actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: MTStrings.CameraMasks.Round.resetConfirm, action: {
                        for setting in MTRoundVideoSettings.resettableKeys {
                            setting.reset()
                        }
                    })
                ]))
            }),
            isEnabled: { _ in
                return MTRoundVideoSettings.resettableKeys.contains(where: { !$0.isDefault() })
            },
            isDestructive: true
        ))
    }

    // MARK: Calls

    private static func registerCalls() {
        let section = MTCameraMasksMenu.sectionCalls
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.calls.masks", section: section, order: 100, title: { MTStrings.CameraMasks.Calls.masks }, subtitle: { MTStrings.CameraMasks.Calls.masksInfo }, kind: .toggle(.global(MTMaskSettings.inCalls)), searchKeywords: { [MTStrings.CameraMasks.Masks.keywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.virtualCamera.enabled", section: section, order: 200, title: { MTStrings.CameraMasks.VirtualCamera.enabled }, subtitle: { MTStrings.CameraMasks.VirtualCamera.enabledInfo }, kind: .toggle(.global(MTVirtualCameraSettings.enabled)), searchKeywords: { [MTStrings.CameraMasks.VirtualCamera.keywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "cameraMasks.virtualCamera.loop", section: section, order: 300, title: { MTStrings.CameraMasks.VirtualCamera.loop }, kind: .toggle(.global(MTVirtualCameraSettings.loop)), isVisible: { _ in MTVirtualCameraSettings.enabled.value }))
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: MTCameraMasksMenu.virtualCameraTab,
                parent: .tab(.mediaCalls),
                title: { MTStrings.CameraMasks.VirtualCamera.library },
                makeScreen: { context in
                    return mtMakeVirtualCameraScreen(context: context.context)
                },
                searchKeywords: { [MTStrings.CameraMasks.VirtualCamera.keywords] }
            ),
            linkIn: MTCameraMasksMenu.sectionCalls,
            order: 400,
            subtitle: { MTStrings.CameraMasks.VirtualCamera.libraryInfo },
            icon: .system("photo.on.rectangle"),
            label: { _ in
                if let item = MTVirtualCameraSettings.selectedItem {
                    return item.title
                }
                return nil
            }
        )
    }

    // MARK: Anonymous mode

    private static func registerAnonymousMode() {
        let tab = MTMenuTabID.privacyAnonymousMode
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.anonymous.active",
            section: .main(of: tab),
            order: 100,
            title: { MTStrings.CameraMasks.Anonymous.toggle },
            subtitle: { MTStrings.CameraMasks.Anonymous.toggleInfo },
            kind: .toggle(.account(MTAnonymousMode.isActive)),
            searchKeywords: { [MTStrings.CameraMasks.Anonymous.keywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.anonymous.mask",
            section: .main(of: tab),
            order: 200,
            title: { MTStrings.CameraMasks.Anonymous.mask },
            kind: .action({ context in
                context.push(mtMakeMaskLibraryScreen(context: context.context, target: .anonymous))
            }),
            label: { _ in
                return MTMaskEngine.title(MTMaskSelection(storage: MTAnonymousMode.mask.value))
            }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "cameraMasks.anonymous.voice",
            section: .main(of: tab),
            order: 300,
            title: { MTStrings.CameraMasks.Anonymous.voice },
            kind: .action({ context in
                let presets = MTAnonymousMode.allVoicePresets()
                context.presentActionSheet(
                    title: MTStrings.CameraMasks.Anonymous.voice,
                    buttons: presets.map { preset in
                        let title = (preset.id == MTAnonymousMode.voice.value ? "✓ " : "") + preset.title()
                        return (title, false, {
                            MTAnonymousMode.voice.set(preset.id)
                        })
                    }
                )
            }),
            isVisible: { _ in
                return !MTAnonymousMode.voicePresets.isEmpty
            },
            label: { _ in
                let value = MTAnonymousMode.voice.value
                return MTAnonymousMode.allVoicePresets().first(where: { $0.id == value })?.title()
            }
        ))
    }
}
