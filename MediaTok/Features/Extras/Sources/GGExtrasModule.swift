import Foundation
import GGCore
import GGFeaturesShared

/// Entry point of GGExtras: the Swiftgram user features MediaTok did not have yet, written
/// as MediaTok features. Settings and the TelegramCore points are in GGFeaturesShared
/// (`Sources/Extras/`, registered before this module); here — the menu and the app's handlers.
public enum GGExtrasModule {
    /// Declares menu rows and hook handlers. Called once on the main thread from
    /// `GGFeatures.registerAll()`, before `GGHookRegistry.freeze()`.
    public static func register() {
        GGExtrasMenu.register()
        GGExtrasProfileMenu.register()
        GGExtrasSelection.register()
        GGExtrasLinks.register()
        GGExtrasAutolock.register()
        GGExtrasRoutes.register()
        GGExtrasMigrations.register()
    }
}
