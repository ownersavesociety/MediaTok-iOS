// Compiled into IntentsExtensionLib (filegroup //MediaTok/MTHooks:SiriIntentsHookSources):
// launch of MediaTok in the Siri intents extension. «Mark as read» from Siri goes through
// `applyMaxReadIndexInteractively` → `MTPresenceHooks.sendReadReceipt`, whose ghost-mode handler
// lives in MTFeaturesShared; without this launch the point is empty there and Siri reads past
// ghost mode. Accounts opened by the extension go through `Account.init` (MTAccountHooks).

import Foundation
import MTCore
import MTFeaturesShared

private var mtSiriIntentsStarted = false
private let mtSiriIntentsLock = NSLock()

/// MediaTok hook target: before `initializeAccountManagement()` and before any account is opened. The
/// first call starts MediaTok in the process; a later one (iOS keeps the process for the next
/// request) reads the settings files again, so chat protection and ghost mode changed in the app
/// apply at once.
func mtSiriIntentsDidStart(appGroupPath: String) {
    mtSiriIntentsLock.lock()
    defer {
        mtSiriIntentsLock.unlock()
    }
    if mtSiriIntentsStarted {
        MTCore.reloadSettings()
        return
    }
    mtSiriIntentsStarted = true
    MTCore.bootstrap(MTCoreEnvironment(appGroupPath: appGroupPath, process: .intents))
    // Handlers register on the main thread (MTHookPoint contract).
    if Thread.isMainThread {
        MTFeaturesShared.registerForExtension()
    } else {
        DispatchQueue.main.sync {
            MTFeaturesShared.registerForExtension()
        }
    }
    MTHookRegistry.freeze()
}
