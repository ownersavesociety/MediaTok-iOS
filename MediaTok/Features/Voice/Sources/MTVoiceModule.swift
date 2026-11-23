import Foundation
import AccountContext
import TelegramAudio
import MTCore
import MTHooks
import MTFeaturesShared

/// Entry point of the MTVoice feature module. Owner: MediaTok.
public enum MTVoiceModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        // Settings are declared by MTVoiceShared (MTFeaturesShared): upstream modules read them.
        MTVoiceMigrations.register()
        MTVoiceMenu.register()

        // The voice changer: recorder (voice messages), round video audio stage, calls.
        MTVoiceMorphHooks.register()
        // Fish Audio AI voice cloning & character voice replacement.
        MTFishAudioClone.register()
        // «Всегда встроенный микрофон», read by ManagedAudioSession while recording.
        MTAudioSessionHooks.prefersBuiltInMicrophoneForRecording.register({
            return MTVoiceSettings.builtInMicrophone.value
        }, order: 100)
        // Auto-transcription of own voice messages and round videos.
        MTAutoTranscription.register()

        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            let sharedContext = context.sharedContext
            MTVoiceAccounts.shared.start(sharedContext: sharedContext)
            MTVoiceCallEffectController.shared.start(sharedContext: sharedContext)
            MTVoiceKeepMusic.shared.start(sharedContext: sharedContext)
        }, order: 300)

        // Publishes the playback equalizer's parameters (one subscription for the process).
        MTVoiceEqualizer.start()
    }
}
