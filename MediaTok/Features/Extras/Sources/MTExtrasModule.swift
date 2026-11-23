import Foundation
import MTCore
import MTFeaturesShared

/// Entry point of MTExtras: the Swiftgram user features MediaTok did not have yet, written
/// as MediaTok features. Settings and the TelegramCore points are in MTFeaturesShared
/// (`Sources/Extras/`, registered before this module); here — the menu and the app's handlers.
public enum MTExtrasModule {
    /// Declares menu rows and hook handlers. Called once on the main thread from
    /// `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        MTExtrasMenu.register()
        MTExtrasProfileMenu.register()
        MTExtrasSelection.register()
        MTExtrasLinks.register()
        MTExtrasAutolock.register()
        MTExtrasRoutes.register()
        MTExtrasMigrations.register()
    }
}
