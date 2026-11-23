import Foundation

/// Light aggregator linked into the app and into the extensions (notification service, share).
/// Each zone owns its `Sources/<Zone>/<Zone>Shared.swift`; nobody edits this file after wave 1.
public enum MTFeaturesShared {
    /// App process: called by `MTFeatures.registerAll()` before the feature modules register.
    public static func registerForApp() {
        MTFeaturesShared.registerZones()
    }

    /// Extension processes: called instead of `MTFeatures.registerAll()`, after `MTCore.bootstrap`
    /// and before `MTHookRegistry.freeze()`.
    public static func registerForExtension() {
        MTFeaturesShared.registerZones()
    }

    private static func registerZones() {
        MTGhostModeShared.register()
        MTAntiDeleteShared.register()
        MTMessagesShared.register()
        MTAppearanceShared.register()
        MTInterfaceShared.register()
        MTVoiceShared.register()
        MTCameraMasksShared.register()
        MTCallsMediaShared.register()
        MTSecurityShared.register()
        MTNetworkSpoofShared.register()
        MTProfileExportShared.register()
        // MediaTok: Swiftgram-parity features (settings, NSE flag, TelegramCore points).
        MTExtrasShared.register()
    }
}
