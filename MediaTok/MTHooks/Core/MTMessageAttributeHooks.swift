// Compiled into TelegramCore (filegroup //MediaTok/MTHooks:TelegramCoreHookSources).
// Features declare their own Postbox-coded types (message attributes: deleted, versions,
// local edit, bookmark, previous reactions…) in the same place TelegramCore declares its own,
// before any Postbox opens — in the app and in every extension.

import Foundation
import Postbox
import MTCore

public enum MTMessageAttributeHooks {
    /// Observer, called once per process from TelegramCore's `declaredEncodables`
    /// (`initializeAccountManagement()`), on the thread that initializes account management.
    /// Handlers call `declareEncodable(MyAttribute.self, f: { MyAttribute(decoder: $0) })`.
    /// Register from `GG<Zone>Shared.register()` so extensions decode the attributes too.
    public static let declareEncodables = MTHookPoint<() -> Void>("attributes.declareEncodables")

    /// Transformer: when the server stores a message again over an existing one (holes, history
    /// validation, `storeMessages`), Postbox merges the stored version's local attributes into the
    /// new one (`SeedConfiguration.mergeMessageAttributes`). Handlers copy their own local
    /// attributes from `previous` into `updated` (deleted, versions, local edit, bookmark…).
    /// Called inside the Postbox transaction for every such message: one cheap pass, no I/O.
    public static let mergeAttributes = MTHookPoint<([MessageAttribute], inout [MessageAttribute]) -> Void>("attributes.merge")
}

func mtDeclareFeatureEncodables() {
    for handler in MTMessageAttributeHooks.declareEncodables.handlers {
        handler()
    }
}

/// MediaTok hook target: `telegramPostboxSeedConfiguration.mergeMessageAttributes`.
func mtMergeFeatureAttributes(_ previous: [MessageAttribute], _ updated: inout [MessageAttribute]) {
    if MTMessageAttributeHooks.mergeAttributes.isEmpty || previous.isEmpty {
        return
    }
    for handler in MTMessageAttributeHooks.mergeAttributes.handlers {
        handler(previous, &updated)
    }
}
