import Foundation
import MTCore

/// The part of MTVoice that the extensions (notification service, share) also link: settings with
/// `.extensions`, NSE handlers, attribute declarations. Owner: MediaTok.
///
/// The voice settings are declared here rather than in MTVoice because upstream modules below the
/// feature layer read them on their hot paths (TelegramUI: the recorder and the playlist; the bubble
/// nodes: word bubbles). Reading is a snapshot load (MTCore), nothing else.
public enum MTVoiceShared {
    /// Called from `MTFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `MTCore.environment?.process` for what only one of them needs.
    public static func register() {
        MTVoiceSettings.declare()
        MTVoiceMessageAttributes.register()
    }
}

/// Every setting of the «Голос» zone, declared once. User switches are off by default; the «where to
/// apply» switches only act under their master switch, so the master alone gives a working default.
public enum MTVoiceSettings {
    // MARK: Voice changer

    public static let morphEnabled = MTSetting<Bool>("voice.morph.enabled", default: false)
    /// Preset id: anonymous, female, male, child, robot, custom (`MTVoicePresetID`).
    public static let morphPreset = MTSetting<String>("voice.morph.preset", default: "anonymous")
    public static let morphVoiceMessages = MTSetting<Bool>("voice.morph.voiceMessages", default: true)
    public static let morphRoundVideos = MTSetting<Bool>("voice.morph.roundVideos", default: true)
    public static let morphCalls = MTSetting<Bool>("voice.morph.calls", default: false)

    // MARK: «Свой голос» (user units, see MTVoiceParams)

    public static let customName = MTSetting<String>("voice.custom.name", default: "")
    /// Semitones −12…12.
    public static let customPitch = MTSetting<Double>("voice.custom.pitch", default: 0.0)
    /// −100…100 %.
    public static let customTimbre = MTSetting<Double>("voice.custom.timbre", default: 0.0)
    /// dB −12…12.
    public static let customBass = MTSetting<Double>("voice.custom.bass", default: 0.0)
    public static let customMid = MTSetting<Double>("voice.custom.mid", default: 0.0)
    public static let customTreble = MTSetting<Double>("voice.custom.treble", default: 0.0)
    public static let customGain = MTSetting<Double>("voice.custom.gain", default: 0.0)
    /// 0…100 %.
    public static let customDistortion = MTSetting<Double>("voice.custom.distortion", default: 0.0)
    public static let customReverb = MTSetting<Double>("voice.custom.reverb", default: 0.0)
    public static let customEcho = MTSetting<Double>("voice.custom.echo", default: 0.0)
    public static let customCompression = MTSetting<Double>("voice.custom.compression", default: 0.0)
    public static let customBreathiness = MTSetting<Double>("voice.custom.breathiness", default: 0.0)
    public static let customChorus = MTSetting<Double>("voice.custom.chorus", default: 0.0)
    public static let customFlanger = MTSetting<Double>("voice.custom.flanger", default: 0.0)
    public static let customVibratoDepth = MTSetting<Double>("voice.custom.vibratoDepth", default: 0.0)
    public static let customWet = MTSetting<Double>("voice.custom.wet", default: 100.0)
    /// Hz 0…12.
    public static let customVibratoRate = MTSetting<Double>("voice.custom.vibratoRate", default: 5.0)
    /// Hz 0…1000, 0 = off.
    public static let customRingMod = MTSetting<Double>("voice.custom.ringMod", default: 0.0)
    /// Bits 2…16, 16 = off.
    public static let customBitcrush = MTSetting<Double>("voice.custom.bitcrush", default: 16.0)
    public static let customTelephone = MTSetting<Bool>("voice.custom.telephone", default: false)

    // MARK: Fish Audio AI Voice Clone

    public static let fishAudioAutoReplace = MTSetting<Bool>("voice.fishAudio.autoReplace", default: false)
    public static let fishAudioReferenceId = MTSetting<String>("voice.fishAudio.referenceId", default: "")
    public static let fishAudioReferenceTitle = MTSetting<String>("voice.fishAudio.referenceTitle", default: "")
    public static let fishAudioModel = MTSetting<String>("voice.fishAudio.model", default: "s2-pro")

    // MARK: Playback equalizer

    public static let eqEnabled = MTSetting<Bool>("voice.eq.enabled", default: false)
    /// flat, bass, vocal, treble, custom.
    public static let eqPreset = MTSetting<String>("voice.eq.preset", default: "flat")
    /// dB −12…12; 60 Hz, 230 Hz, 910 Hz, 3.6 kHz, 14 kHz.
    public static let eqBand0 = MTSetting<Double>("voice.eq.band0", default: 0.0)
    public static let eqBand1 = MTSetting<Double>("voice.eq.band1", default: 0.0)
    public static let eqBand2 = MTSetting<Double>("voice.eq.band2", default: 0.0)
    public static let eqBand3 = MTSetting<Double>("voice.eq.band3", default: 0.0)
    public static let eqBand4 = MTSetting<Double>("voice.eq.band4", default: 0.0)
    public static let eqAudio = MTSetting<Bool>("voice.eq.audio", default: true)
    public static let eqRoundVideos = MTSetting<Bool>("voice.eq.roundVideos", default: true)
    public static let eqVideos = MTSetting<Bool>("voice.eq.videos", default: true)

    public static var eqBands: [MTSetting<Double>] {
        return [MTVoiceSettings.eqBand0, MTVoiceSettings.eqBand1, MTVoiceSettings.eqBand2, MTVoiceSettings.eqBand3, MTVoiceSettings.eqBand4]
    }

    // MARK: Transcription (the engine has no setting:

    public static let wordBubbles = MTSetting<Bool>("voice.wordBubbles", default: false)
    public static let autoTranscribe = MTSetting<Bool>("voice.autoTranscribe.enabled", default: false)
    public static let autoTranscribeRoundVideos = MTSetting<Bool>("voice.autoTranscribe.roundVideos", default: false)
    /// plain, quote, bold, italic, underline, strikethrough, monospace, spoiler.
    public static let autoTranscribeFormat = MTSetting<String>("voice.autoTranscribe.format", default: "quote")
    public static let autoTranscribeTranslate = MTSetting<Bool>("voice.autoTranscribe.translate", default: false)
    /// Language code of the translation; "" = the language of Telegram's interface.
    public static let autoTranscribeLanguage = MTSetting<String>("voice.autoTranscribe.language", default: "")

    // MARK: Playback and recording

    /// Do not play the next unheard voice message / round video after the current one ends.
    public static let disableAutoplay = MTSetting<Bool>("voice.disableAutoplay", default: false)
    /// Record voice messages and round videos with the built-in microphone even with a headset.
    public static let builtInMicrophone = MTSetting<Bool>("voice.builtInMicrophone", default: false)
    /// Mirror of the upstream `MediaInputSettings.pauseMusicOnRecording` (inverted) so the menu row
    /// redraws when Data & Storage changes it. Upstream stays the only source of truth.
    public static let keepMusicMirror = MTSetting<Bool>("voice.keepMusicMirror", default: false, flags: [.noExport])

    static func declare() {
        let _ = MTVoiceSettings.morphEnabled
        let _ = MTVoiceSettings.morphPreset
        let _ = MTVoiceSettings.morphVoiceMessages
        let _ = MTVoiceSettings.morphRoundVideos
        let _ = MTVoiceSettings.morphCalls
        let _ = MTVoiceSettings.customName
        let _ = MTVoiceSettings.customPitch
        let _ = MTVoiceSettings.customTimbre
        let _ = MTVoiceSettings.customBass
        let _ = MTVoiceSettings.customMid
        let _ = MTVoiceSettings.customTreble
        let _ = MTVoiceSettings.customGain
        let _ = MTVoiceSettings.customDistortion
        let _ = MTVoiceSettings.customReverb
        let _ = MTVoiceSettings.customEcho
        let _ = MTVoiceSettings.customCompression
        let _ = MTVoiceSettings.customBreathiness
        let _ = MTVoiceSettings.customChorus
        let _ = MTVoiceSettings.customFlanger
        let _ = MTVoiceSettings.customVibratoDepth
        let _ = MTVoiceSettings.customWet
        let _ = MTVoiceSettings.customVibratoRate
        let _ = MTVoiceSettings.customRingMod
        let _ = MTVoiceSettings.customBitcrush
        let _ = MTVoiceSettings.customTelephone
        let _ = MTVoiceSettings.fishAudioAutoReplace
        let _ = MTVoiceSettings.fishAudioReferenceId
        let _ = MTVoiceSettings.fishAudioReferenceTitle
        let _ = MTVoiceSettings.fishAudioModel
        let _ = MTVoiceSettings.eqEnabled
        let _ = MTVoiceSettings.eqPreset
        let _ = MTVoiceSettings.eqBand0
        let _ = MTVoiceSettings.eqBand1
        let _ = MTVoiceSettings.eqBand2
        let _ = MTVoiceSettings.eqBand3
        let _ = MTVoiceSettings.eqBand4
        let _ = MTVoiceSettings.eqAudio
        let _ = MTVoiceSettings.eqRoundVideos
        let _ = MTVoiceSettings.eqVideos
        let _ = MTVoiceSettings.wordBubbles
        let _ = MTVoiceSettings.autoTranscribe
        let _ = MTVoiceSettings.autoTranscribeRoundVideos
        let _ = MTVoiceSettings.autoTranscribeFormat
        let _ = MTVoiceSettings.autoTranscribeTranslate
        let _ = MTVoiceSettings.autoTranscribeLanguage
        let _ = MTVoiceSettings.disableAutoplay
        let _ = MTVoiceSettings.builtInMicrophone
        let _ = MTVoiceSettings.keepMusicMirror
    }
}

/// An effect the voice recorder runs over every captured block before the waveform and the encoder
/// see it, so the real voice is never written anywhere. Created once per recording (recorder queue).
public protocol MTVoiceRecordingEffect: AnyObject {
    /// Mono Int16 samples, processed in place; the length never changes. Recorder queue.
    func process(_ samples: UnsafeMutablePointer<Int16>, count: Int, sampleRate: Int)
}

public enum MTVoiceRecordingHooks {
    /// Provider (first non-nil wins), asked when a voice message recording starts. MTVoice.
    public static let effect = MTHookPoint<() -> MTVoiceRecordingEffect?>("voice.recordingEffect")

    /// `ManagedAudioRecorderContext.init`. Without handlers: nil, upstream behaviour.
    public static func makeEffect() -> MTVoiceRecordingEffect? {
        if MTVoiceRecordingHooks.effect.isEmpty {
            return nil
        }
        for handler in MTVoiceRecordingHooks.effect.handlers {
            if let effect = handler() {
                return effect
            }
        }
        return nil
    }

    /// `SharedMediaPlayer.setActionAtEnd`: stop after a voice message / round video instead of
    /// playing the next unheard one.
    public static var disablesNextVoiceAutoplay: Bool {
        return MTVoiceSettings.disableAutoplay.value
    }

    public struct FishAudioVoiceResult {
        public let oggData: Data
        public let duration: Double
        public let waveform: Data

        public init(oggData: Data, duration: Double, waveform: Data) {
            self.oggData = oggData
            self.duration = duration
            self.waveform = waveform
        }
    }

    public static var isFishAudioCloneActive: Bool {
        return MTVoiceSettings.fishAudioAutoReplace.value
            && !MTVoiceSettings.fishAudioReferenceId.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static let transformRecordedVoice = MTHookPoint<(Data, String, @escaping (Result<FishAudioVoiceResult, Error>) -> Void) -> Bool>("voice.fishAudioTransform")

    public static func runFishAudioTransform(oggData: Data, interfaceLanguage: String, completion: @escaping (Result<FishAudioVoiceResult, Error>) -> Void) -> Bool {
        for handler in MTVoiceRecordingHooks.transformRecordedVoice.handlers {
            if handler(oggData, interfaceLanguage, completion) {
                return true
            }
        }
        return false
    }
}
