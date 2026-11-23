// Compiled into IntentsExtensionLib (filegroup //MediaTok/GGHooks:SiriIntentsHookSources):
// launch of MediaTok in the Siri intents extension. «Mark as read» from Siri goes through
// `applyMaxReadIndexInteractively` → `GGPresenceHooks.sendReadReceipt`, whose ghost-mode handler
// lives in GGFeaturesShared; without this launch the point is empty there and Siri reads past
// ghost mode. Accounts opened by the extension go through `Account.init` (GGAccountHooks).

import Foundation
import GGCore
import GGFeaturesShared

private var ggSiriIntentsStarted = false
private let ggSiriIntentsLock = NSLock()

/// MediaTok hook target: before `initializeAccountManagement()` and before any account is opened. The
/// first call starts MediaTok in the process; a later one (iOS keeps the process for the next
/// request) reads the settings files again, so chat protection and ghost mode changed in the app
/// apply at once.
func ggSiriIntentsDidStart(appGroupPath: String) {
    ggSiriIntentsLock.lock()
    defer {
        ggSiriIntentsLock.unlock()
    }
    if ggSiriIntentsStarted {
        GGCore.reloadSettings()
        return
    }
    ggSiriIntentsStarted = true
    GGCore.bootstrap(GGCoreEnvironment(appGroupPath: appGroupPath, process: .intents))
    // Handlers register on the main thread (GGHookPoint contract).
    if Thread.isMainThread {
        GGFeaturesShared.registerForExtension()
    } else {
        DispatchQueue.main.sync {
            GGFeaturesShared.registerForExtension()
        }
    }
    GGHookRegistry.freeze()
}
