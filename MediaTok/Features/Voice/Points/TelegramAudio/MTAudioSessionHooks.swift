import Foundation
import AVFoundation
import MTCore

// Compiled into TelegramAudio (filegroup //MediaTok/Features/Voice:TelegramAudioPoints), owner MediaTok.

public enum MTAudioSessionHooks {
    /// Policy (any `true`): record voice messages and round videos with the built-in microphone even
    /// when a headset (wired, AirPods, Bluetooth) is connected. Calls are not affected.
    public static let prefersBuiltInMicrophoneForRecording = MTHookPoint<() -> Bool>("audioSession.builtInMicrophoneForRecording")

    static func prefersBuiltInMicrophone() -> Bool {
        if MTAudioSessionHooks.prefersBuiltInMicrophoneForRecording.isEmpty {
            return false
        }
        for handler in MTAudioSessionHooks.prefersBuiltInMicrophoneForRecording.handlers {
            if handler() {
                return true
            }
        }
        return false
    }
}

/// `ManagedAudioSessionImpl.setupOutputMode`, after the upstream input choice, for recording sessions
/// with a headset connected. Moving the output off Bluetooth is what lets the built-in microphone take
/// over (a Bluetooth headset keeps its own microphone while it holds the route).
func mtApplyBuiltInMicrophoneIfNeeded(isRecording: Bool, isHeadsetConnected: Bool) {
    guard isRecording, isHeadsetConnected, MTAudioSessionHooks.prefersBuiltInMicrophone() else {
        return
    }
    let session = AVAudioSession.sharedInstance()
    guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
        return
    }
    let _ = try? session.overrideOutputAudioPort(.speaker)
    let _ = try? session.setPreferredInput(builtIn)
}
