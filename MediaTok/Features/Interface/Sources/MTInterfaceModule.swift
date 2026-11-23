import Foundation

/// Entry point of the MTInterface feature module. Owner: MediaTok.
public enum MTInterfaceModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        InterfaceSettings.declare()
        InterfaceMigrations.register()
        // Hot paths read this snapshot; it follows every settings change from here on.
        InterfaceSnapshots.shared.start()

        MTChatListFeature.register()
        MTFoldersFeature.register()
        MTTabBarFeature.register()
        MTSettingsTabLayout.register()
        MTInputFeature.register()
        MTInputBarEditor.register()
        MTQuickButtonsFeature.register()
        MTCustomReactions.register()
        MTIconPackResolver.shared.register()
        MTIconPackStorage.shared.migrateLegacyPacksIfNeeded()
        MTIslandBadge.shared.register()
        // Handlers of points that MediaTok spec/R9 add to MTHooks (Sources/Pending).
        MTInterfacePending.register()

        InterfaceMenu.register()
    }
}
