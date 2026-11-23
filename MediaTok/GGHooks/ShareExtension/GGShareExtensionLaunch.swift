// Compiled into ShareExtensionContext (filegroup //MediaTok/GGHooks:ShareExtensionHookSources):
// launch of MediaTok in the share extension. Accounts opened there go through `Account.init`,
// whose Core point loads their MediaTok settings (GGAccountHooks).

import Foundation
import GGCore
import GGFeaturesShared

private var ggShareExtensionStarted = false

/// MediaTok hook target: on the main thread, before `initializeAccountManagement()` and before any
/// account is opened. The first call starts MediaTok in the process; a later one (iOS may keep the
/// process for the next share) reads the settings files again.
func ggShareExtensionDidStart(appGroupPath: String) {
    assert(Thread.isMainThread)
    if ggShareExtensionStarted {
        GGCore.reloadSettings()
        return
    }
    ggShareExtensionStarted = true
    GGCore.bootstrap(GGCoreEnvironment(appGroupPath: appGroupPath, process: .share))
    GGFeaturesShared.registerForExtension()
    ggShareExtensionRegisterPhotoHandlers()
    GGHookRegistry.freeze()
}
