import Foundation
import Display
import AccountContext
import MTCore
import MTHooks

/// Shortcut links: `mediatok://contacts` opens contacts, `mediatok://ios_settings` opens iOS Settings.
enum MTExtrasRoutes {
    static func register() {
        MTLifecycleHooks.openURL.register({ url, context, _ in
            guard let scheme = url.scheme?.lowercased(), scheme == "mediatok" else {
                return false
            }
            switch url.host?.lowercased() ?? "" {
            case "contacts":
                guard let rootController = context.sharedContext.mainWindow?.viewController as? TelegramRootControllerInterface else {
                    return false
                }
                rootController.openContacts()
                return true
            case "ios_settings", "iossettings":
                context.sharedContext.applicationBindings.openSettings()
                return true
            default:
                return false
            }
        }, order: 900)
    }
}
