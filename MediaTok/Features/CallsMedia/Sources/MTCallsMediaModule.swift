import Foundation

/// Entry point of the MTCallsMedia feature module. Owner: MediaTok.
public enum MTCallsMediaModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        MTCallsMediaSettings.declare()
        MTCallsMediaMigrations.register()

        MTTransferTuning.register()
        MTGalleryTweaks.register()
        MTSubtitlesFeature.register()
        MTDownloadStatusViews.register()
        MTCallFeatures.register()
        MTCallsMediaMenu.register()

        // Handlers of the points that requests R1 and R2 add to MTHooks (Sources/Pending).
        MTCallsMediaPending.register()
    }
}
