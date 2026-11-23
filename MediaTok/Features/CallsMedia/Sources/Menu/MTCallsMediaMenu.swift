import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import MTCore
import MTSettingsUI

/// The zone's menu: «Медиа и звонки › Звонки / Загрузки и качество» and the «Субтитры к видео»
/// section of «Сообщения › Перевод». Section orders on the skeleton tabs start at 300 (100 and 200
/// are the skeleton's preview and main sections); masks in calls use 800+. «Лента» and the
/// music status were removed by the owner on 2026-10-27 (with their tab «Лента и музыка»).
enum MTCallsMediaMenu {
    static let recordingsTab = MTMenuTabID("calls.recordings")
    static let soundsTab = MTMenuTabID("calls.sounds")

    static func register() {
        MTCallsMediaMenu.registerCalls()
        MTCallsMediaMenu.registerDownloads()
        MTCallsMediaMenu.registerSubtitles()
    }

    private static func toggle(_ id: String, section: MTMenuSectionID, order: Int, setting: MTSetting<Bool>, title: @escaping () -> String, subtitle: (() -> String)? = nil, isVisible: ((MTMenuContext) -> Bool)? = nil, keywords: @escaping () -> [String] = { [] }) -> MTMenuRow {
        return MTMenuRow(id: id, section: section, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)), isVisible: isVisible, searchKeywords: keywords)
    }

    // MARK: Calls

    private static func registerCalls() {
        let screen = MTMenuScreenID.tab(.mediaCalls)
        let recording = MTMenuSectionID("calls.recording")
        let microphone = MTMenuSectionID("calls.microphone")
        let callScreen = MTMenuSectionID("calls.screen")
        let sounds = MTMenuSectionID("calls.soundboard")
        let network = MTMenuSectionID("calls.network")

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: recording, screen: screen, order: 300, header: { MTStrings.Calls.Menu.recordingHeader }, footer: { _ in MTStrings.Calls.Menu.recordingFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: microphone, screen: screen, order: 400, header: { MTStrings.Calls.Menu.microphoneHeader }, footer: { _ in MTStrings.Calls.Menu.silentMuteFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: callScreen, screen: screen, order: 500, header: { MTStrings.Calls.Menu.screenHeader }, footer: { _ in MTStrings.Calls.Menu.screenFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: sounds, screen: screen, order: 600, header: { MTStrings.Calls.Menu.soundboardHeader }, footer: { _ in MTStrings.Calls.Menu.soundboardFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: network, screen: screen, order: 700, header: { MTStrings.Calls.Menu.networkHeader }, footer: { _ in MTStrings.Calls.Menu.forceTcpFooter }))

        let isRecording: (MTMenuContext) -> Bool = { _ in
            return MTCallsMediaSettings.recordingMode.isOn
        }
        // One choice instead of «аудиозвонки» + «видеозвонки» (2026-10-27).
        MTMenuRegistry.register(MTMenuRow(id: "calls.record", section: recording, order: 100, title: { MTStrings.Calls.Menu.record }, subtitle: { MTStrings.Calls.Menu.recordInfo }, kind: .choice(.global(MTCallsMediaSettings.recordCalls), options: [
            MTMenuChoiceOption(value: MTCallRecordingMode.off.rawValue, title: { MTStrings.Calls.Menu.recordOff }),
            MTMenuChoiceOption(value: MTCallRecordingMode.audio.rawValue, title: { MTStrings.Calls.Menu.recordAudioOnly }),
            MTMenuChoiceOption(value: MTCallRecordingMode.audioAndVideo.rawValue, title: { MTStrings.Calls.Menu.recordAudioAndVideo })
        ]), searchKeywords: { [MTStrings.Calls.Menu.keywordRecording] }))
        MTMenuRegistry.register(toggle("calls.recordOwnVoice", section: recording, order: 200, setting: MTCallsMediaSettings.recordOwnVoice, title: { MTStrings.Calls.Menu.recordOwnVoice }, isVisible: isRecording))
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(id: MTCallsMediaMenu.recordingsTab, parent: screen, title: { MTStrings.Calls.Recordings.title }, makeScreen: { context in
            return mtMakeCallRecordingsScreen(menuContext: context)
        }), linkIn: recording, order: 400, subtitle: { MTStrings.Calls.Menu.recordingsInfo }, icon: .bundle("Chat/Context Menu/VoiceChat"), label: { context in
            return MTStrings.Calls.Menu.recordingsCount(count: MTCallsMediaSettings.recordings.value(for: context.accountID).count)
        })

        MTMenuRegistry.register(toggle("calls.silentMute", section: microphone, order: 100, setting: MTCallsMediaSettings.silentMute, title: { MTStrings.Calls.Menu.silentMute }, subtitle: { MTStrings.Calls.Menu.silentMuteInfo }))

        MTMenuRegistry.register(toggle("calls.disableRating", section: callScreen, order: 100, setting: MTCallsMediaSettings.disableRating, title: { MTStrings.Calls.Menu.disableRating }))
        MTMenuRegistry.register(toggle("calls.statsOverlay", section: callScreen, order: 200, setting: MTCallsMediaSettings.statsOverlay, title: { MTStrings.Calls.Menu.statsOverlay }, subtitle: { MTStrings.Calls.Menu.statsOverlayInfo }))

        let soundboardOn: (MTMenuContext) -> Bool = { _ in
            return MTCallsMediaSettings.soundboard.value
        }
        MTMenuRegistry.register(toggle("calls.soundboard", section: sounds, order: 100, setting: MTCallsMediaSettings.soundboard, title: { MTStrings.Calls.Menu.soundboard }, keywords: { [MTStrings.Calls.Menu.keywordSounds] }))
        MTMenuRegistry.register(MTMenuRow(id: "calls.soundboardVolume", section: sounds, order: 200, title: { MTStrings.Calls.Menu.soundboardVolume }, kind: .slider(.global(MTCallsMediaSettings.soundboardVolume), range: 0.1 ... 1.0, step: 0.05, format: { value in
            return "\(Int((value * 100.0).rounded())) %"
        }), isVisible: soundboardOn))
        MTMenuRegistry.register(toggle("calls.soundboardDuck", section: sounds, order: 300, setting: MTCallsMediaSettings.soundboardDuck, title: { MTStrings.Calls.Menu.soundboardDuck }, subtitle: { MTStrings.Calls.Menu.soundboardDuckInfo }, isVisible: soundboardOn))
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(id: MTCallsMediaMenu.soundsTab, parent: screen, title: { MTStrings.Calls.Sounds.title }, makeScreen: { context in
            return mtMakeSoundLibraryScreen(menuContext: context)
        }), linkIn: sounds, order: 400, subtitle: { MTStrings.Calls.Menu.soundsInfo }, icon: .bundle("Chat/Context Menu/AddMusic"), label: { _ in
            return MTStrings.Calls.Menu.soundsCount(count: MTCallsMediaSettings.soundboardItems.value.count)
        })

        MTMenuRegistry.register(toggle("calls.forceTcp", section: network, order: 100, setting: MTCallsMediaSettings.forceTcp, title: { MTStrings.Calls.Menu.forceTcp }))
    }

    // MARK: Downloads and quality

    private static func registerDownloads() {
        let screen = MTMenuScreenID.tab(.mediaDownloads)
        let status = MTMenuSectionID("downloads.status")
        let boost = MTMenuSectionID("downloads.boost")
        let photos = MTMenuSectionID("downloads.photos")
        let gallery = MTMenuSectionID("downloads.gallery")

        MTMenuRegistry.register(MTMenuRow(id: "downloads.preview", section: .preview(of: .mediaDownloads), order: 100, title: { "" }, kind: .preview(.miniChatList(MTMiniChatListConfiguration(scope: "downloads", height: 152.0, rows: { _ in
            var rows = Array(MTPreviewChatListRow.samples().prefix(2))
            if MTCallsMediaSettings.statusInChatList.value, !rows.isEmpty {
                rows[0].text = "⬇︎ " + MTStrings.Downloads.Preview.fileName + " · 42 %"
                rows[0].isTyping = false
            }
            return rows
        })))))

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: status, screen: screen, order: 300, header: { MTStrings.Downloads.Menu.statusHeader }, footer: { _ in MTStrings.Downloads.Menu.statusFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: boost, screen: screen, order: 400, header: { MTStrings.Downloads.Menu.boostHeader }, footer: { _ in MTStrings.Downloads.Menu.boostFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: photos, screen: screen, order: 500, header: { MTStrings.Downloads.Menu.photosHeader }, footer: { _ in MTStrings.Downloads.Menu.photosFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: gallery, screen: screen, order: 600, header: { MTStrings.Downloads.Menu.galleryHeader }, footer: { _ in MTStrings.Downloads.Menu.galleryFooter }))

        MTMenuRegistry.register(toggle("downloads.statusInChatList", section: status, order: 100, setting: MTCallsMediaSettings.statusInChatList, title: { MTStrings.Downloads.Menu.statusInChatList }))
        MTMenuRegistry.register(toggle("downloads.statusInChat", section: status, order: 200, setting: MTCallsMediaSettings.statusInChat, title: { MTStrings.Downloads.Menu.statusInChat }))

        // Both boosts ask once before they switch on: the server may answer with flood waits.
        MTMenuRegistry.register(MTMenuRow(id: "downloads.uploadBoost", section: boost, order: 100, title: { MTStrings.Downloads.Menu.uploadBoost }, kind: .custom({ context in
            return ItemListSwitchItem(presentationData: context.itemListPresentationData, systemStyle: .glass, title: MTStrings.Downloads.Menu.uploadBoost, value: MTCallsMediaSettings.uploadBoost.value, enableInteractiveChanges: false, maximumNumberOfLines: 2, sectionId: context.sectionId, style: .blocks, updated: { value in
                if value {
                    MTCallsMediaMenu.confirmBoost(context: context, apply: {
                        MTCallsMediaSettings.uploadBoost.set(true)
                    })
                } else {
                    MTCallsMediaSettings.uploadBoost.set(false)
                }
            })
        }), searchKeywords: { [MTStrings.Downloads.Menu.keywordSpeed] }))
        MTMenuRegistry.register(MTMenuRow(id: "downloads.downloadBoost", section: boost, order: 200, title: { MTStrings.Downloads.Menu.downloadBoost }, kind: .action({ context in
            MTCallsMediaMenu.chooseDownloadBoost(context: context)
        }), searchKeywords: { [MTStrings.Downloads.Menu.keywordSpeed] }, label: { _ in
            return MTCallsMediaMenu.downloadBoostTitle(MTDownloadBoostMode(rawValue: MTCallsMediaSettings.downloadBoost.value) ?? .off)
        }))

        var qualityOptions = [MTMenuChoiceOption(value: "", title: { MTStrings.Downloads.Menu.photoQualityDefault })]
        for value in ["60", "70", "80", "90", "100"] {
            qualityOptions.append(MTMenuChoiceOption(value: value, title: { value + " %" }))
        }
        MTMenuRegistry.register(MTMenuRow(id: "downloads.photoQuality", section: photos, order: 100, title: { MTStrings.Downloads.Menu.photoQuality }, kind: .choice(.global(MTCallsMediaSettings.photoQuality), options: qualityOptions)))
        MTMenuRegistry.register(toggle("downloads.largePhotos", section: photos, order: 200, setting: MTCallsMediaSettings.largePhotos, title: { MTStrings.Downloads.Menu.largePhotos }, subtitle: { MTStrings.Downloads.Menu.largePhotosInfo }))

        MTMenuRegistry.register(toggle("gallery.copyPhoto", section: gallery, order: 100, setting: MTCallsMediaSettings.copyPhotoItem, title: { MTStrings.Gallery.Menu.copyPhoto }))
        MTMenuRegistry.register(toggle("gallery.airPlay", section: gallery, order: 200, setting: MTCallsMediaSettings.airPlayItem, title: { MTStrings.Gallery.Menu.airPlay }, subtitle: { MTStrings.Gallery.Menu.airPlayInfo }))
    }

    private static func confirmBoost(context: MTMenuContext, apply: @escaping () -> Void) {
        let presentationData = context.presentationData
        context.present(textAlertController(context: context.context, title: MTStrings.Downloads.Boost.warningTitle, text: MTStrings.Downloads.Boost.warningText, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: MTStrings.Downloads.Boost.warningConfirm, action: {
                apply()
            })
        ]))
    }

    private static func downloadBoostTitle(_ mode: MTDownloadBoostMode) -> String {
        switch mode {
        case .off:
            return MTStrings.Downloads.Boost.off
        case .medium:
            return MTStrings.Downloads.Boost.medium
        case .maximum:
            return MTStrings.Downloads.Boost.maximum
        }
    }

    private static func chooseDownloadBoost(context: MTMenuContext) {
        let current = MTDownloadBoostMode(rawValue: MTCallsMediaSettings.downloadBoost.value) ?? .off
        var actions: [(title: String, isDestructive: Bool, action: () -> Void)] = []
        for mode in [MTDownloadBoostMode.off, .medium, .maximum] {
            let title = (mode == current ? "✓ " : "") + MTCallsMediaMenu.downloadBoostTitle(mode)
            actions.append((title, false, {
                if mode == .off || current != .off {
                    MTCallsMediaSettings.downloadBoost.set(mode.rawValue)
                } else {
                    MTCallsMediaMenu.confirmBoost(context: context, apply: {
                        MTCallsMediaSettings.downloadBoost.set(mode.rawValue)
                    })
                }
            }))
        }
        mtPresentMediaActionSheet(context: context.context, title: MTStrings.Downloads.Menu.downloadBoost, actions: actions, present: { context.present($0) })
    }

    // MARK: Subtitles

    private static func registerSubtitles() {
        let section = MTMenuSectionID("subtitles.main")
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: section, screen: .tab(.messagesTranslation), order: 400, header: { MTStrings.Subtitles.Menu.header }, footer: { _ in MTStrings.Subtitles.Menu.footer }))
        MTMenuRegistry.register(toggle("subtitles.enabled", section: section, order: 100, setting: MTCallsMediaSettings.subtitles, title: { MTStrings.Subtitles.Menu.enabled }, subtitle: { MTStrings.Subtitles.Menu.enabledInfo }, keywords: { [MTStrings.Subtitles.Menu.keyword] }))
        MTMenuRegistry.register(toggle("subtitles.translate", section: section, order: 200, setting: MTCallsMediaSettings.subtitlesTranslate, title: { MTStrings.Subtitles.Menu.translate }, isVisible: { _ in MTCallsMediaSettings.subtitles.value }))
        var options = [MTMenuChoiceOption(value: "", title: { MTStrings.Subtitles.Menu.languageAuto })]
        for code in ["en", "ru", "uk", "be", "kk", "de", "fr", "es", "it", "pt", "pl", "tr", "ar", "fa", "he", "hi", "zh", "ja", "ko"] {
            options.append(MTMenuChoiceOption(value: code, title: {
                // Language names come from the system in the language of the interface.
                let interface = Locale(identifier: MTLocalization.shared.languageCode)
                return interface.localizedString(forLanguageCode: code) ?? code
            }))
        }
        MTMenuRegistry.register(MTMenuRow(id: "subtitles.language", section: section, order: 300, title: { MTStrings.Subtitles.Menu.language }, kind: .choice(.global(MTCallsMediaSettings.subtitlesLanguage), options: options), isVisible: { _ in MTCallsMediaSettings.subtitles.value && MTCallsMediaSettings.subtitlesTranslate.value }))
    }
}
