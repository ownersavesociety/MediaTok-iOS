import Foundation
import MTCore
import MTFeaturesShared
import MTVoiceDSP

/// The voice changer's presets. One parameter set drives the same C graph on all three paths
/// (voice messages, round videos, calls), so a preset sounds the same everywhere.
enum MTVoicePresetID: String, CaseIterable {
    case anonymous
    case female
    case male
    case child
    case robot
    case custom

    var title: String {
        switch self {
        case .anonymous:
            return MTStrings.Voice.Preset.anonymous
        case .female:
            return MTStrings.Voice.Preset.female
        case .male:
            return MTStrings.Voice.Preset.male
        case .child:
            return MTStrings.Voice.Preset.child
        case .robot:
            return MTStrings.Voice.Preset.robot
        case .custom:
            let name = MTVoiceSettings.customName.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? MTStrings.Voice.Preset.custom : name
        }
    }

    var subtitle: String {
        switch self {
        case .anonymous:
            return MTStrings.Voice.Preset.anonymousInfo
        case .female:
            return MTStrings.Voice.Preset.femaleInfo
        case .male:
            return MTStrings.Voice.Preset.maleInfo
        case .child:
            return MTStrings.Voice.Preset.childInfo
        case .robot:
            return MTStrings.Voice.Preset.robotInfo
        case .custom:
            return MTStrings.Voice.Preset.customInfo
        }
    }
}

/// Where a voice is changed. The anonymous mode overrides all three for its account.
enum MTVoiceScope {
    case voiceMessages
    case roundVideos
    case calls
}

enum MTVoicePresets {
    static func params(for preset: MTVoicePresetID) -> MTVoiceParams {
        var p = MTVoiceParams()
        MTVoiceParamsSetIdentity(&p)
        switch preset {
        case .anonymous:
            // Lower and darker, compressed, with breath and a slow random drift of the pitch: the drift is
            // the «hardening» against simply shifting the voice back, now in audible units.
            p.pitchSemitones = -3.5
            p.timbre = -0.35
            p.bassDb = 2.0
            p.trebleDb = -2.0
            p.distortion = 0.18
            p.reverbMix = 0.12
            p.reverbSize = 0.35
            p.jitter = 0.6
            p.breathiness = 0.15
            p.compression = 0.45
        case .female:
            p.pitchSemitones = 5.0
            p.timbre = 0.45
            p.trebleDb = 2.0
            p.reverbMix = 0.04
        case .male:
            p.pitchSemitones = -3.5
            p.timbre = -0.45
            p.bassDb = 3.0
            p.reverbMix = 0.03
        case .child:
            p.pitchSemitones = 7.0
            p.timbre = 0.65
            p.trebleDb = 3.0
            p.reverbMix = 0.05
        case .robot:
            p.ringModHz = 55.0
            p.ringModMix = 0.65
            p.distortion = 0.35
            p.bitcrushBits = 10.0
            p.telephone = 0.3
            p.reverbMix = 0.18
            p.reverbSize = 0.3
            p.echoMix = 0.12
            p.echoDelayMs = 70.0
            p.echoFeedback = 0.25
            p.compression = 0.5
        case .custom:
            p = MTVoicePresets.customParams()
        }
        return p
    }

    static func customParams() -> MTVoiceParams {
        var p = MTVoiceParams()
        MTVoiceParamsSetIdentity(&p)
        p.pitchSemitones = Float(MTVoiceSettings.customPitch.value)
        p.timbre = Float(MTVoiceSettings.customTimbre.value / 100.0)
        p.bassDb = Float(MTVoiceSettings.customBass.value)
        p.midDb = Float(MTVoiceSettings.customMid.value)
        p.trebleDb = Float(MTVoiceSettings.customTreble.value)
        p.gainDb = Float(MTVoiceSettings.customGain.value)
        p.distortion = Float(MTVoiceSettings.customDistortion.value / 100.0)
        p.reverbMix = Float(MTVoiceSettings.customReverb.value / 100.0)
        p.reverbSize = 0.5
        p.echoMix = Float(MTVoiceSettings.customEcho.value / 100.0)
        p.echoDelayMs = 180.0
        p.echoFeedback = 0.3
        p.compression = Float(MTVoiceSettings.customCompression.value / 100.0)
        p.breathiness = Float(MTVoiceSettings.customBreathiness.value / 100.0)
        p.chorus = Float(MTVoiceSettings.customChorus.value / 100.0)
        p.flanger = Float(MTVoiceSettings.customFlanger.value / 100.0)
        p.vibratoRateHz = Float(MTVoiceSettings.customVibratoRate.value)
        p.vibratoDepth = Float(MTVoiceSettings.customVibratoDepth.value / 100.0)
        p.ringModHz = Float(MTVoiceSettings.customRingMod.value)
        p.ringModMix = p.ringModHz > 0.0 ? 0.7 : 0.0
        p.bitcrushBits = Float(MTVoiceSettings.customBitcrush.value)
        p.telephone = MTVoiceSettings.customTelephone.value ? 1.0 : 0.0
        p.wet = Float(MTVoiceSettings.customWet.value / 100.0)
        return p
    }

    /// The selected preset (an unknown stored value falls back to the default, so the master switch
    /// always has something to apply — the old «on, but nothing chosen» state cannot happen).
    static var selectedPreset: MTVoicePresetID {
        return MTVoicePresetID(rawValue: MTVoiceSettings.morphPreset.value) ?? .anonymous
    }

    /// What to apply now on this path for this account, or nil (the sound stays untouched). Reads
    /// snapshots only. The anonymous mode wins over the user's own choice and needs no master switch.
    static func effectiveParams(scope: MTVoiceScope, account: MTAccountID?) -> MTVoiceParams? {
        if let account, let anonymous = MTAnonymousMode.voicePreset(for: account), let preset = MTVoicePresetID(rawValue: anonymous) {
            return MTVoicePresets.nonIdentity(MTVoicePresets.params(for: preset))
        }
        guard MTVoiceSettings.morphEnabled.value else {
            return nil
        }
        switch scope {
        case .voiceMessages:
            guard MTVoiceSettings.morphVoiceMessages.value else {
                return nil
            }
        case .roundVideos:
            guard MTVoiceSettings.morphRoundVideos.value else {
                return nil
            }
        case .calls:
            guard MTVoiceSettings.morphCalls.value else {
                return nil
            }
        }
        return MTVoicePresets.nonIdentity(MTVoicePresets.params(for: MTVoicePresets.selectedPreset))
    }

    static func nonIdentity(_ params: MTVoiceParams) -> MTVoiceParams? {
        var params = params
        return MTVoiceParamsIsIdentity(&params) ? nil : params
    }

    /// Byte image of a parameter set: equal sets need no new chain.
    static func fingerprint(_ params: MTVoiceParams?) -> Data? {
        guard var params else {
            return nil
        }
        return withUnsafeBytes(of: &params) { Data($0) }
    }
}
