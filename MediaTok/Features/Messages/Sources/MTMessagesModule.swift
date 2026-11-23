import Foundation
import MTCore
import MTHooks
import MTFeaturesShared

/// Entry point of the MTMessages feature module: restriction bypasses, the outgoing text
/// pipeline, translation, the message menu and gestures, the «Чаты» and «Уведомления» sections.
public enum MTMessagesModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        // Settings shared with upstream modules and the extensions are declared by
        // MTMessagesShared.register() (called before this one by MTFeaturesShared.registerForApp()).
        let _ = MTOutgoingPipeline.replacementRules

        MTRestrictionHandlers.register()
        MTKeptMediaMenu.register()
        MTMessageDecorations.register()
        MTOutgoingPipeline.register()
        MTOutgoingTransforms.register()
        MTTranslationProviders.register()
        MTTranslateBeforeSending.register()
        MTPhotoTranslation.register()
        MTTranslationMenu.register()
        MTTranslationQuickAction.register()
        MTMessageMenuCustomization.register()
        MTInputAndGestures.register()
        MTAutoQuote.register()
        MTOutgoingLanguageMenu.register()
        MTChatsHandlers.register()
        MTPinnedChats.register()
        MTLocalCreatorMode.register()

        MTMessagesMenu.register()
        MTMessagesMigrations.register()

        // Placeholders of dropped pushes the notification extension did not live to remove
        // (MTEmptyNotifications); one async query, nothing when there are none.
        MTLifecycleHooks.applicationDidBecomeActive.register({
            MTEmptyNotifications.removeDelivered()
        })
    }
}
