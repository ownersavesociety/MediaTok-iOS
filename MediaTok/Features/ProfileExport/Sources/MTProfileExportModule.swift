import Foundation
import SwiftSignalKit
import MTCore

/// Entry point of the MTProfileExport feature module: the MediaTok nick badge, fake gifts,
/// chat export.
public enum MTProfileExportModule {
    private static var fakeGiftsDisposable: Disposable?

    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        MTNickBadgeSettings.declare()
        MTFakeGiftsSettings.declare()
        MTLocalStars.declare()
        MTChatExportSettings.declare()
        MTFakeGiftsLegacy.registerMigrations()

        // Nick badge disabled for MediaTok builds.
        MTNickBadgeSettings.isEnabled.set(false)

        // Fake gifts: the profile's list, the gift screen's menu, the store per account.
        MTFakeGiftsHooks.register()
        MTFakeGiftsMenu.register()
        MTProfileExportModule.fakeGiftsDisposable = (MTFakeGiftsSettings.isEnabled.signal
        |> distinctUntilChanged).start(next: { enabled in
            MTFakeGiftsStore.shared.setEnabled(enabled)
        })
        // Local stars: the Stars balance shown on this device (same tab, own section).
        MTLocalStars.register()

        // Chat export: entry points; temporary trees of old jobs are removed off the main thread.
        MTChatExportMenu.register()
        MTChatExportManager.shared.removeStaleJobs()
    }
}
