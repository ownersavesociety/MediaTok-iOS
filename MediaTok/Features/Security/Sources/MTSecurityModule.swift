import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatListUI
import MTCore
import MTHooks
import MTFeaturesShared

/// Entry point of the MTSecurity feature module. Owner: MediaTok.
///
/// Settings, migrations and what the extensions need are in MTFeaturesShared
/// (`Sources/Security/`, registered before this module); here — the app: the common check
/// (`MTLocalAuthGate`), the chat lock, the secret folder, the account switch check and the account
/// button, screenshots, the passcode extras and the «Безопасность» menu.
public enum MTSecurityModule {
    private static var listRefreshDisposable: Disposable?

    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        MTSecurityMenu.register()
        MTChatLockHandlers.register()
        MTScreenshotPrivacy.register()
        MTPasscodeExtras.register()
        MTAccountSwitchGuard.shared.register()
        MTAccountHeaderButton.register()

        MTChatListHooks.folders.register({ signal, context in
            return MTSecretFolder.shared.folders(signal, context: context)
        })

        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTAuthEnvironment.shared.start(sharedContext: context.sharedContext)
            MTAccountSwitchGuard.shared.start(context: context)
            MTAccountsList.shared.start(context: context)
            MTSecretFolder.shared.startMembership(context: context)
            MTSecurityModule.observeListPolicies()
        })
        MTLifecycleHooks.applicationDidEnterBackground.register({
            // The folder first: the chat lock covers the folder's open chats by its state.
            MTSecretFolder.shared.lockAll()
            MTChatLock.shared.applicationDidEnterBackground()
        })
        MTLifecycleHooks.applicationDidBecomeActive.register({
            MTAuthEnvironment.shared.refreshDevice()
            MTChatLock.shared.applicationDidBecomeActive()
        })
    }

    /// «Пароль на чаты» and «Защищать все чаты» change what every chat list row shows; the rows of
    /// single chats are laid out again by `MTChatListHooks.accessoryPeers`, the whole lists — by one
    /// re-emission of the PresentationData (only on these two switches, never on a timer).
    private static func observeListPolicies() {
        if MTSecurityModule.listRefreshDisposable != nil {
            return
        }
        var isFirst = true
        MTSecurityModule.listRefreshDisposable = (combineLatest(MTSecuritySharedSettings.chatLockEnabled.signal, MTSecuritySharedSettings.chatLockAllChats.signal)
        |> deliverOnMainQueue).start(next: { _, _ in
            if isFirst {
                isFirst = false
                return
            }
            MTThemeHooks.invalidate()
        })
    }
}
