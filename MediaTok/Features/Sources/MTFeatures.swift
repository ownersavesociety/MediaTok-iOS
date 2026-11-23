import Foundation
import MTSettingsUI
import MTFeaturesShared
import MTGhostMode
import MTAntiDelete
import MTMessages
import MTAppearance
import MTInterface
import MTVoice
import MTCameraMasks
import MTCallsMedia
import MTSecurity
import MTNetworkSpoof
import MTVless
import MTProfileExport
import MTExtras
import MTRegDate

/// Aggregator of the feature modules, called from `AppDelegate` (see MediaTok spec):
/// `MTCore.bootstrap` → `MTFeatures.registerAll()` → `MTCore.runGlobalMigrations()` →
/// `MTHookRegistry.freeze()`. Only `register()` calls live here; nobody edits it after wave 1.
public enum MTFeatures {
    public static func registerAll() {
        assert(Thread.isMainThread)
        // The menu skeleton first: features add rows to its sections.
        MTSettingsUI.register()
        MTFeaturesShared.registerForApp()
        MTGhostModeModule.register()
        MTAntiDeleteModule.register()
        MTMessagesModule.register()
        MTAppearanceModule.register()
        MTInterfaceModule.register()
        MTVoiceModule.register()
        MTCameraMasksModule.register()
        MTCallsMediaModule.register()
        MTSecurityModule.register()
        MTNetworkSpoofModule.register()
        MTVlessModule.register()
        MTProfileExportModule.register()
        // MediaTok: Swiftgram-parity features.
        MTExtrasModule.register()
        // MediaTok: «Дата регистрации».
        MTRegDateModule.register()
    }
}
