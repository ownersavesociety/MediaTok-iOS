import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PromptUI
import MTCore
import MTSettingsUI
import MTFeaturesShared

/// «Медиа и звонки › Голос». Section orders on the skeleton tab start at 300 (100 = preview, 200 = main).
enum MTVoiceMenu {
    static let customTab = MTMenuTabID("voice.custom")
    static let bandsTab = MTMenuTabID("voice.eqBands")

    static let morphSection = MTMenuSectionID("voice.morph")
    static let eqSection = MTMenuSectionID("voice.eq")
    static let transcriptionSection = MTMenuSectionID("voice.transcription")
    static let playbackSection = MTMenuSectionID("voice.playback")

    static func register() {
        MTVoiceMenu.registerPreview()
        MTVoiceMenu.registerMorph()
        MTVoiceMenu.registerCustomVoice()
        MTVoiceMenu.registerEqualizer()
        MTVoiceMenu.registerTranscription()
        MTVoiceMenu.registerPlayback()
    }

    private static func toggle(_ id: String, section: MTMenuSectionID, order: Int, setting: MTSetting<Bool>, title: @escaping () -> String, subtitle: (() -> String)? = nil, isVisible: ((MTMenuContext) -> Bool)? = nil, keywords: @escaping () -> [String] = { [] }) -> MTMenuRow {
        return MTMenuRow(id: id, section: section, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)), isVisible: isVisible, searchKeywords: keywords)
    }

    private static func slider(_ id: String, section: MTMenuSectionID, order: Int, setting: MTSetting<Double>, range: ClosedRange<Double>, step: Double, title: @escaping () -> String, format: @escaping (Double) -> String) -> MTMenuRow {
        return MTMenuRow(id: id, section: section, order: order, title: title, kind: .slider(.global(setting), range: range, step: step, format: format))
    }

    static func signed(_ value: Double, decimals: Bool = false) -> String {
        let rounded = decimals ? (value * 10.0).rounded() / 10.0 : value.rounded()
        let text: String
        if decimals && rounded.truncatingRemainder(dividingBy: 1.0) != 0.0 {
            text = String(format: "%.1f", abs(rounded))
        } else {
            text = String(Int(abs(rounded)))
        }
        if rounded > 0.0 {
            return "+" + text
        } else if rounded < 0.0 {
            return "−" + text
        }
        return text
    }

    static func percent(_ value: Double) -> String {
        return MTStrings.Voice.Unit.percent(value: String(Int(value.rounded())))
    }

    // MARK: Preview

    private static func registerPreview() {
        MTMenuRegistry.register(MTMenuRow(id: "voice.preview", section: .preview(of: .mediaVoice), order: 100, title: { "" }, kind: .preview(.custom(height: 138.0, make: { _ in
            return MTVoicePreviewView(frame: .zero)
        }))))
    }

    // MARK: Voice changer

    private static func registerMorph() {
        let screen = MTMenuScreenID.tab(.mediaVoice)
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTVoiceMenu.morphSection, screen: screen, order: 300, header: { MTStrings.Voice.Menu.morphHeader }, footer: { _ in
            return MTStrings.Voice.Menu.morphFooter
        }))
        let morphOn: (MTMenuContext) -> Bool = { _ in
            return MTVoiceSettings.morphEnabled.value
        }
        MTMenuRegistry.register(MTMenuRow(
            id: "voice.fishAudio.studio",
            section: MTVoiceMenu.morphSection,
            order: 50,
            title: { "AI Клон голоса (Fish Audio)" },
            subtitle: { "Клонирование по ГС / войслайну аниме-персонажа и авто-озвучка" },
            icon: .system("waveform.badge.person.crop"),
            kind: .action({ context in
                MTFishAudioClone.presentStudio(context: context.context, from: context.navigationController)
            }),
            searchKeywords: { ["fish audio", "клон", "голос", "аниме", "elevenlabs", "войслайн", "tts"] },
            label: { _ in
                let title = MTVoiceSettings.fishAudioReferenceTitle.value
                if MTVoiceRecordingHooks.isFishAudioCloneActive {
                    return title.isEmpty ? "Вкл." : title
                }
                return title.isEmpty ? nil : title
            }
        ))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.morph.enabled", section: MTVoiceMenu.morphSection, order: 100, setting: MTVoiceSettings.morphEnabled, title: { MTStrings.Voice.Menu.morph }, subtitle: { MTStrings.Voice.Menu.morphInfo }, keywords: { [MTStrings.Voice.Menu.keywordMorph, MTStrings.Voice.Menu.keywordAnonymous] }))
        let presetOptions = MTVoicePresetID.allCases.map { preset in
            return MTMenuChoiceOption(value: preset.rawValue, title: { preset.title })
        }
        MTMenuRegistry.register(MTMenuRow(id: "voice.morph.preset", section: MTVoiceMenu.morphSection, order: 200, title: { MTStrings.Voice.Menu.preset }, subtitle: { MTVoicePresets.selectedPreset.subtitle }, kind: .choice(.global(MTVoiceSettings.morphPreset), options: presetOptions), searchKeywords: { [MTStrings.Voice.Menu.keywordMorph] }))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.morph.voiceMessages", section: MTVoiceMenu.morphSection, order: 300, setting: MTVoiceSettings.morphVoiceMessages, title: { MTStrings.Voice.Menu.morphVoiceMessages }, subtitle: { MTStrings.Voice.Menu.morphVoiceMessagesInfo }, isVisible: morphOn))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.morph.roundVideos", section: MTVoiceMenu.morphSection, order: 400, setting: MTVoiceSettings.morphRoundVideos, title: { MTStrings.Voice.Menu.morphRoundVideos }, isVisible: morphOn))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.morph.calls", section: MTVoiceMenu.morphSection, order: 500, setting: MTVoiceSettings.morphCalls, title: { MTStrings.Voice.Menu.morphCalls }, subtitle: { MTStrings.Voice.Menu.morphCallsInfo }, isVisible: morphOn))
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(id: MTVoiceMenu.customTab, parent: screen, title: { MTStrings.Voice.Custom.title }, topView: MTMenuTopView(content: .emoji("🎛"), text: { MTStrings.Voice.Custom.info }), searchKeywords: { [MTStrings.Voice.Menu.keywordMorph] }), linkIn: MTVoiceMenu.morphSection, order: 600, subtitle: { MTStrings.Voice.Menu.customInfo }, icon: .system("slider.horizontal.3"), label: { _ in
            return MTVoicePresets.selectedPreset == .custom ? MTStrings.Voice.Menu.selected : nil
        })

        // The anonymous mode offers the same presets; its choice overrides, nothing is rewritten.
        MTAnonymousMode.voicePresets.register({
            return MTVoicePresetID.allCases.map { preset in
                return MTAnonymousVoicePreset(id: preset.rawValue, title: { preset.title })
            }
        }, order: 100)
    }

    private static func registerCustomVoice() {
        let screen = MTMenuScreenID.tab(MTVoiceMenu.customTab)
        let pitch = MTMenuSectionID("voice.custom.pitch")
        let tone = MTMenuSectionID("voice.custom.tone")
        let effects = MTMenuSectionID("voice.custom.effects")
        let modulation = MTMenuSectionID("voice.custom.modulation")
        let mix = MTMenuSectionID("voice.custom.mix")
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .main(of: MTVoiceMenu.customTab), screen: screen, order: 200))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: pitch, screen: screen, order: 300, header: { MTStrings.Voice.Custom.pitchHeader }, footer: { _ in MTStrings.Voice.Custom.pitchFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: tone, screen: screen, order: 400, header: { MTStrings.Voice.Custom.toneHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: effects, screen: screen, order: 500, header: { MTStrings.Voice.Custom.effectsHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: modulation, screen: screen, order: 600, header: { MTStrings.Voice.Custom.modulationHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: mix, screen: screen, order: 700, header: { MTStrings.Voice.Custom.mixHeader }, footer: { _ in MTStrings.Voice.Custom.mixFooter }))

        MTMenuRegistry.register(MTMenuRow(
            id: "voice.custom.fishAudioClone",
            section: .main(of: MTVoiceMenu.customTab),
            order: 50,
            title: { "Клонировать по ГС / войслайну (Fish Audio AI)" },
            subtitle: { "Загрузи голосовое или фразу аниме-персонажа для копирования голоса" },
            icon: .system("waveform.badge.person.crop"),
            kind: .action({ context in
                MTFishAudioClone.presentStudio(context: context.context, from: context.navigationController)
            }),
            searchKeywords: { ["fish audio", "клон", "голос", "аниме"] },
            label: { _ in
                let title = MTVoiceSettings.fishAudioReferenceTitle.value
                return title.isEmpty ? nil : title
            }
        ))
        MTMenuRegistry.register(MTMenuRow(id: "voice.custom.name", section: .main(of: MTVoiceMenu.customTab), order: 100, title: { MTStrings.Voice.Custom.name }, kind: .action({ context in
            context.present(promptController(context: context.context, text: MTStrings.Voice.Custom.namePrompt, value: MTVoiceSettings.customName.value, characterLimit: 32, apply: { value in
                if let value {
                    MTVoiceSettings.customName.set(value.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }))
        }), label: { _ in
            let name = MTVoiceSettings.customName.value
            return name.isEmpty ? nil : name
        }))
        MTMenuRegistry.register(MTMenuRow(id: "voice.custom.use", section: .main(of: MTVoiceMenu.customTab), order: 200, title: { MTStrings.Voice.Custom.use }, kind: .action({ _ in
            MTVoiceSettings.morphPreset.set(MTVoicePresetID.custom.rawValue)
        }), isVisible: { _ in
            return MTVoicePresets.selectedPreset != .custom
        }))

        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.pitch", section: pitch, order: 100, setting: MTVoiceSettings.customPitch, range: -12.0 ... 12.0, step: 0.5, title: { MTStrings.Voice.Custom.pitch }, format: { value in
            return MTStrings.Voice.Unit.semitones(value: MTVoiceMenu.signed(value, decimals: true))
        }))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.timbre", section: pitch, order: 200, setting: MTVoiceSettings.customTimbre, range: -100.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.timbre }, format: { value in
            return MTStrings.Voice.Unit.percent(value: MTVoiceMenu.signed(value))
        }))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.vibratoDepth", section: pitch, order: 300, setting: MTVoiceSettings.customVibratoDepth, range: 0.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.vibratoDepth }, format: MTVoiceMenu.percent))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.vibratoRate", section: pitch, order: 400, setting: MTVoiceSettings.customVibratoRate, range: 0.0 ... 12.0, step: 0.5, title: { MTStrings.Voice.Custom.vibratoRate }, format: { value in
            return MTStrings.Voice.Eq.hertz(value: MTVoiceMenu.signed(value, decimals: true))
        }))

        let decibels: (Double) -> String = { value in
            return MTStrings.Voice.Unit.decibels(value: MTVoiceMenu.signed(value))
        }
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.bass", section: tone, order: 100, setting: MTVoiceSettings.customBass, range: -12.0 ... 12.0, step: 1.0, title: { MTStrings.Voice.Custom.bass }, format: decibels))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.mid", section: tone, order: 200, setting: MTVoiceSettings.customMid, range: -12.0 ... 12.0, step: 1.0, title: { MTStrings.Voice.Custom.mid }, format: decibels))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.treble", section: tone, order: 300, setting: MTVoiceSettings.customTreble, range: -12.0 ... 12.0, step: 1.0, title: { MTStrings.Voice.Custom.treble }, format: decibels))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.custom.telephone", section: tone, order: 400, setting: MTVoiceSettings.customTelephone, title: { MTStrings.Voice.Custom.telephone }))

        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.distortion", section: effects, order: 100, setting: MTVoiceSettings.customDistortion, range: 0.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.distortion }, format: MTVoiceMenu.percent))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.reverb", section: effects, order: 200, setting: MTVoiceSettings.customReverb, range: 0.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.reverb }, format: MTVoiceMenu.percent))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.echo", section: effects, order: 300, setting: MTVoiceSettings.customEcho, range: 0.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.echo }, format: MTVoiceMenu.percent))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.breathiness", section: effects, order: 400, setting: MTVoiceSettings.customBreathiness, range: 0.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.breathiness }, format: MTVoiceMenu.percent))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.compression", section: effects, order: 500, setting: MTVoiceSettings.customCompression, range: 0.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.compression }, format: MTVoiceMenu.percent))

        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.chorus", section: modulation, order: 100, setting: MTVoiceSettings.customChorus, range: 0.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.chorus }, format: MTVoiceMenu.percent))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.flanger", section: modulation, order: 200, setting: MTVoiceSettings.customFlanger, range: 0.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.flanger }, format: MTVoiceMenu.percent))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.ringMod", section: modulation, order: 300, setting: MTVoiceSettings.customRingMod, range: 0.0 ... 1000.0, step: 10.0, title: { MTStrings.Voice.Custom.ringMod }, format: { value in
            return value < 1.0 ? MTStrings.Voice.Unit.off : MTStrings.Voice.Eq.hertz(value: String(Int(value.rounded())))
        }))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.bitcrush", section: modulation, order: 400, setting: MTVoiceSettings.customBitcrush, range: 2.0 ... 16.0, step: 1.0, title: { MTStrings.Voice.Custom.bitcrush }, format: { value in
            return value >= 15.5 ? MTStrings.Voice.Unit.off : MTStrings.Voice.Unit.bits(value: String(Int(value.rounded())))
        }))

        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.gain", section: mix, order: 100, setting: MTVoiceSettings.customGain, range: -12.0 ... 12.0, step: 1.0, title: { MTStrings.Voice.Custom.gain }, format: decibels))
        MTMenuRegistry.register(MTVoiceMenu.slider("voice.custom.wet", section: mix, order: 200, setting: MTVoiceSettings.customWet, range: 0.0 ... 100.0, step: 5.0, title: { MTStrings.Voice.Custom.wet }, format: MTVoiceMenu.percent))
        MTMenuRegistry.register(MTMenuRow(id: "voice.custom.reset", section: mix, order: 300, title: { MTStrings.Voice.Custom.reset }, kind: .action({ _ in
            MTVoiceMenu.resetCustomVoice()
        }), isDestructive: true))
    }

    private static func resetCustomVoice() {
        MTVoiceSettings.customPitch.reset()
        MTVoiceSettings.customTimbre.reset()
        MTVoiceSettings.customBass.reset()
        MTVoiceSettings.customMid.reset()
        MTVoiceSettings.customTreble.reset()
        MTVoiceSettings.customGain.reset()
        MTVoiceSettings.customDistortion.reset()
        MTVoiceSettings.customReverb.reset()
        MTVoiceSettings.customEcho.reset()
        MTVoiceSettings.customCompression.reset()
        MTVoiceSettings.customBreathiness.reset()
        MTVoiceSettings.customChorus.reset()
        MTVoiceSettings.customFlanger.reset()
        MTVoiceSettings.customVibratoDepth.reset()
        MTVoiceSettings.customVibratoRate.reset()
        MTVoiceSettings.customRingMod.reset()
        MTVoiceSettings.customBitcrush.reset()
        MTVoiceSettings.customTelephone.reset()
        MTVoiceSettings.customWet.reset()
    }

    // MARK: Equalizer

    private static func registerEqualizer() {
        let screen = MTMenuScreenID.tab(.mediaVoice)
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTVoiceMenu.eqSection, screen: screen, order: 400, header: { MTStrings.Voice.Eq.header }, footer: { _ in MTStrings.Voice.Eq.footer }))
        let eqOn: (MTMenuContext) -> Bool = { _ in
            return MTVoiceSettings.eqEnabled.value
        }
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.eq.enabled", section: MTVoiceMenu.eqSection, order: 100, setting: MTVoiceSettings.eqEnabled, title: { MTStrings.Voice.Eq.enabled }, keywords: { [MTStrings.Voice.Eq.keyword] }))
        let presetOptions = MTVoiceEqualizer.Preset.allCases.map { preset in
            return MTMenuChoiceOption(value: preset.rawValue, title: { preset.title })
        }
        MTMenuRegistry.register(MTMenuRow(id: "voice.eq.preset", section: MTVoiceMenu.eqSection, order: 200, title: { MTStrings.Voice.Eq.preset }, kind: .choice(.global(MTVoiceSettings.eqPreset), options: presetOptions), isVisible: eqOn, searchKeywords: { [MTStrings.Voice.Eq.keyword] }))
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(id: MTVoiceMenu.bandsTab, parent: screen, title: { MTStrings.Voice.Eq.bandsTitle }, topView: MTMenuTopView(content: .emoji("🎚"), text: { MTStrings.Voice.Eq.bandsInfo }), searchKeywords: { [MTStrings.Voice.Eq.keyword] }), linkIn: MTVoiceMenu.eqSection, order: 300, subtitle: { MTStrings.Voice.Eq.bandsSubtitle }, icon: .system("slider.vertical.3"), label: { _ in
            return MTVoiceSettings.eqEnabled.value ? MTVoiceEqualizer.Preset(rawValue: MTVoiceSettings.eqPreset.value)?.title : nil
        })
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.eq.audio", section: MTVoiceMenu.eqSection, order: 400, setting: MTVoiceSettings.eqAudio, title: { MTStrings.Voice.Eq.audio }, isVisible: eqOn))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.eq.roundVideos", section: MTVoiceMenu.eqSection, order: 500, setting: MTVoiceSettings.eqRoundVideos, title: { MTStrings.Voice.Eq.roundVideos }, isVisible: eqOn))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.eq.videos", section: MTVoiceMenu.eqSection, order: 600, setting: MTVoiceSettings.eqVideos, title: { MTStrings.Voice.Eq.videos }, isVisible: eqOn))

        let decibels: (Double) -> String = { value in
            return MTStrings.Voice.Unit.decibels(value: MTVoiceMenu.signed(value))
        }
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .main(of: MTVoiceMenu.bandsTab), screen: .tab(MTVoiceMenu.bandsTab), order: 200, footer: { _ in MTStrings.Voice.Eq.bandsFooter }))
        for (index, setting) in MTVoiceSettings.eqBands.enumerated() {
            MTMenuRegistry.register(MTVoiceMenu.slider("voice.eq.band\(index)", section: .main(of: MTVoiceMenu.bandsTab), order: 100 + index * 100, setting: setting, range: -12.0 ... 12.0, step: 1.0, title: { MTVoiceEqualizer.bandTitle(index) }, format: decibels))
        }
    }

    // MARK: Transcription

    private static func registerTranscription() {
        let screen = MTMenuScreenID.tab(.mediaVoice)
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTVoiceMenu.transcriptionSection, screen: screen, order: 500, header: { MTStrings.Voice.Transcription.header }, footer: { context in
            return context.context.isPremium ? MTStrings.Voice.Transcription.footerPremium : MTStrings.Voice.Transcription.footerApple
        }))
        let autoOn: (MTMenuContext) -> Bool = { _ in
            return MTVoiceSettings.autoTranscribe.value
        }
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.wordBubbles", section: MTVoiceMenu.transcriptionSection, order: 100, setting: MTVoiceSettings.wordBubbles, title: { MTStrings.Voice.Transcription.wordBubbles }, subtitle: { MTStrings.Voice.Transcription.wordBubblesInfo }, keywords: { [MTStrings.Voice.Transcription.keyword] }))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.autoTranscribe.enabled", section: MTVoiceMenu.transcriptionSection, order: 200, setting: MTVoiceSettings.autoTranscribe, title: { MTStrings.Voice.AutoTranscribe.enabled }, subtitle: { MTStrings.Voice.AutoTranscribe.enabledInfo }, keywords: { [MTStrings.Voice.Transcription.keyword] }))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.autoTranscribe.roundVideos", section: MTVoiceMenu.transcriptionSection, order: 300, setting: MTVoiceSettings.autoTranscribeRoundVideos, title: { MTStrings.Voice.AutoTranscribe.roundVideos }, isVisible: autoOn))
        let formatOptions = MTTranscriptionFormat.allCases.map { format in
            return MTMenuChoiceOption(value: format.rawValue, title: { format.title })
        }
        MTMenuRegistry.register(MTMenuRow(id: "voice.autoTranscribe.format", section: MTVoiceMenu.transcriptionSection, order: 400, title: { MTStrings.Voice.AutoTranscribe.format }, subtitle: { MTStrings.Voice.AutoTranscribe.formatExample(format: (MTTranscriptionFormat(rawValue: MTVoiceSettings.autoTranscribeFormat.value) ?? .quote).title) }, kind: .choice(.global(MTVoiceSettings.autoTranscribeFormat), options: formatOptions), isVisible: autoOn))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.autoTranscribe.translate", section: MTVoiceMenu.transcriptionSection, order: 500, setting: MTVoiceSettings.autoTranscribeTranslate, title: { MTStrings.Voice.AutoTranscribe.translate }, isVisible: autoOn))
        var languageOptions = [MTMenuChoiceOption(value: "", title: { MTStrings.Voice.AutoTranscribe.languageTelegram })]
        for code in MTVoiceMenu.translationLanguages {
            languageOptions.append(MTMenuChoiceOption(value: code, title: { MTVoiceMenu.languageName(code) }))
        }
        MTMenuRegistry.register(MTMenuRow(id: "voice.autoTranscribe.language", section: MTVoiceMenu.transcriptionSection, order: 600, title: { MTStrings.Voice.AutoTranscribe.language }, kind: .choice(.global(MTVoiceSettings.autoTranscribeLanguage), options: languageOptions), isVisible: { _ in
            return MTVoiceSettings.autoTranscribe.value && MTVoiceSettings.autoTranscribeTranslate.value
        }))
    }

    /// Language codes of the translation target (names come from the system, in MediaTok's language).
    static let translationLanguages = ["en", "ru", "uk", "be", "kk", "uz", "de", "fr", "es", "it", "pt", "pl", "tr", "ar", "fa", "he", "hi", "id", "ja", "ko", "zh"]

    static func languageName(_ code: String) -> String {
        let locale = Locale(identifier: MTLocalization.shared.languageCode)
        guard let name = locale.localizedString(forLanguageCode: code) else {
            return code
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: Playback and recording

    private static func registerPlayback() {
        let screen = MTMenuScreenID.tab(.mediaVoice)
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTVoiceMenu.playbackSection, screen: screen, order: 600, header: { MTStrings.Voice.Playback.header }, footer: { _ in MTStrings.Voice.Playback.footer }))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.disableAutoplay", section: MTVoiceMenu.playbackSection, order: 100, setting: MTVoiceSettings.disableAutoplay, title: { MTStrings.Voice.Playback.disableAutoplay }, subtitle: { MTStrings.Voice.Playback.disableAutoplayInfo }))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.builtInMicrophone", section: MTVoiceMenu.playbackSection, order: 200, setting: MTVoiceSettings.builtInMicrophone, title: { MTStrings.Voice.Playback.builtInMicrophone }, subtitle: { MTStrings.Voice.Playback.builtInMicrophoneInfo }, keywords: { [MTStrings.Voice.Playback.keywordMicrophone] }))
        MTMenuRegistry.register(MTVoiceMenu.toggle("voice.keepMusic", section: MTVoiceMenu.playbackSection, order: 300, setting: MTVoiceSettings.keepMusicMirror, title: { MTStrings.Voice.Playback.keepMusic }, subtitle: { MTStrings.Voice.Playback.keepMusicInfo }))
    }
}
