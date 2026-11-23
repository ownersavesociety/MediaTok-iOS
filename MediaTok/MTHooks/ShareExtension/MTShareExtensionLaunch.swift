// Compiled into ShareExtensionContext (filegroup //MediaTok/MTHooks:ShareExtensionHookSources):
// launch of MediaTok in the share extension. Accounts opened there go through `Account.init`,
// whose Core point loads their MediaTok settings (MTAccountHooks).

import Foundation
import MTCore
import MTFeaturesShared

private var mtShareExtensionStarted = false

/// MediaTok hook target: on the main thread, before `initializeAccountManagement()` and before any
/// account is opened. The first call starts MediaTok in the process; a later one (iOS may keep the
/// process for the next share) reads the settings files again.
func mtShareExtensionDidStart(appGroupPath: String) {
    assert(Thread.isMainThread)
    if mtShareExtensionStarted {
        MTCore.reloadSettings()
        return
    }
    mtShareExtensionStarted = true
    MTCore.bootstrap(MTCoreEnvironment(appGroupPath: appGroupPath, process: .share))
    MTFeaturesShared.registerForExtension()
    mtShareExtensionRegisterPhotoHandlers()
    MTHookRegistry.freeze()
}
