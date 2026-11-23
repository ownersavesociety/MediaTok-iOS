import Foundation
import SwiftSignalKit
import MTCore
import MTFeaturesShared
import MTVoiceDSP

/// The playback equalizer's control side: publishes the gains to the C core (`MTAudioEqualizerSetParameters`)
/// when they change and keeps the preset and the bands consistent. The renderers (MediaPlayer, the video
/// player ChunkMediaPlayerV2 — videos and round videos stay on their upstream player) pick changes up on
/// their next block without resetting their filters, so a change does not click.
enum MTVoiceEqualizer {
    enum Preset: String, CaseIterable {
        case flat
        case bass
        case vocal
        case treble
        case custom

        var gains: [Double]? {
            switch self {
            case .flat:
                return [0.0, 0.0, 0.0, 0.0, 0.0]
            case .bass:
                return [8.0, 5.0, 0.0, -1.0, -2.0]
            case .vocal:
                return [-2.0, 0.0, 6.0, 4.0, -1.0]
            case .treble:
                return [-3.0, -1.0, 0.0, 5.0, 8.0]
            case .custom:
                return nil
            }
        }

        var title: String {
            switch self {
            case .flat:
                return MTStrings.Voice.Eq.presetFlat
            case .bass:
                return MTStrings.Voice.Eq.presetBass
            case .vocal:
                return MTStrings.Voice.Eq.presetVocal
            case .treble:
                return MTStrings.Voice.Eq.presetTreble
            case .custom:
                return MTStrings.Voice.Eq.presetCustom
            }
        }
    }

    private static var disposable: Disposable?
    private static var lastPublished: [Float]?
    private static var lastPreset: String?
    /// The bands of a newly chosen preset are being written. The revision is delivered synchronously
    /// on the main thread, so every band written re-enters `syncPresetAndBands` while the others
    /// still hold the old values: without this the first band «moved by hand» turned the preset
    /// into «Свой» at once.
    private static var isApplyingPreset = false

    static var currentGains: [Double] {
        return MTVoiceSettings.eqBands.map { $0.value }
    }

    /// Main thread, from `register()`: one subscription for the lifetime of the process.
    static func start() {
        if MTVoiceEqualizer.disposable != nil {
            return
        }
        MTVoiceEqualizer.lastPreset = MTVoiceSettings.eqPreset.value
        MTVoiceEqualizer.publish()
        MTVoiceEqualizer.disposable = (MTSettingsStore.shared.revision
        |> deliverOnMainQueue).start(next: { _ in
            if MTVoiceEqualizer.isApplyingPreset {
                // The outer pass publishes once every band is written.
                return
            }
            MTVoiceEqualizer.syncPresetAndBands()
            MTVoiceEqualizer.publish()
        })
    }

    /// A newly chosen preset sets the bands; a band moved by hand turns the preset into «Свой».
    private static func syncPresetAndBands() {
        let preset = MTVoiceSettings.eqPreset.value
        let bands = MTVoiceEqualizer.currentGains
        if preset != MTVoiceEqualizer.lastPreset {
            MTVoiceEqualizer.lastPreset = preset
            if let gains = Preset(rawValue: preset)?.gains, gains != bands {
                MTVoiceEqualizer.isApplyingPreset = true
                for (index, setting) in MTVoiceSettings.eqBands.enumerated() {
                    setting.set(gains[index])
                }
                MTVoiceEqualizer.isApplyingPreset = false
            }
        } else if let gains = Preset(rawValue: preset)?.gains, gains != bands {
            MTVoiceEqualizer.lastPreset = Preset.custom.rawValue
            MTVoiceSettings.eqPreset.set(Preset.custom.rawValue)
        }
    }

    private static func publish() {
        let enabled = MTVoiceSettings.eqEnabled.value
        let gains = MTVoiceEqualizer.currentGains.map { Float($0) }
        let audio = enabled && MTVoiceSettings.eqAudio.value
        let roundVideo = enabled && MTVoiceSettings.eqRoundVideos.value
        let video = enabled && MTVoiceSettings.eqVideos.value
        let snapshot = gains + [audio ? 1.0 : 0.0, roundVideo ? 1.0 : 0.0, video ? 1.0 : 0.0]
        if snapshot == MTVoiceEqualizer.lastPublished {
            return
        }
        MTVoiceEqualizer.lastPublished = snapshot
        gains.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                MTAudioEqualizerSetParameters(base, audio, roundVideo, video)
            }
        }
    }

    /// For the menu preview: the gains that are in effect for a preview (nil = off).
    static func previewGains() -> [Float]? {
        guard MTVoiceSettings.eqEnabled.value else {
            return nil
        }
        let gains = MTVoiceEqualizer.currentGains.map { Float($0) }
        return gains.contains(where: { abs($0) > 0.05 }) ? gains : nil
    }

    static func bandTitle(_ index: Int) -> String {
        let frequency = MTAudioEqualizerBandFrequency(Int32(index))
        if frequency >= 1000.0 {
            let kilohertz = Double(frequency) / 1000.0
            let formatted = kilohertz.truncatingRemainder(dividingBy: 1.0) == 0.0 ? String(Int(kilohertz)) : String(format: "%.1f", kilohertz)
            return MTStrings.Voice.Eq.kilohertz(value: formatted)
        }
        return MTStrings.Voice.Eq.hertz(value: String(Int(frequency)))
    }
}
