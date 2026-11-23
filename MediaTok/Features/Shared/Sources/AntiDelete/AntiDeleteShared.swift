import Foundation
import Postbox
import TelegramCore
import MTCore

/// The part of MTAntiDelete that the extensions (notification service, share) also link: settings with
/// `.extensions`, NSE handlers, attribute declarations. Owner: MediaTok.
public enum MTAntiDeleteShared {
    /// Called from `MTFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `MTCore.environment?.process` for what only one of them needs.
    public static func register() {
        MTAntiDeleteSettings.declare()

        // Attributes: before any Postbox opens, in every process that decodes messages.
        MTMessageAttributeHooks.declareEncodables.register({
            mtDeclareAntiDeleteAttributes()
        })

        // Capture, the same in the app and in the notification service (which marks the shared
        // Postbox itself and hands the index entries to the app).
        MTUpdateHooks.messagesWillBeDeleted.register({ request in
            return MTAntiDeleteCapture.messagesWillBeDeleted(request)
        })
        MTUpdateHooks.historyWillBeCleared.register({ request in
            return MTAntiDeleteCapture.historyWillBeCleared(request)
        })
        MTUpdateHooks.messageWillBeEdited.register({ request, attributes in
            return MTAntiDeleteCapture.messageWillBeEdited(request, attributes)
        })
        // A message stored again from the server (holes, validation) keeps its local attributes.
        MTMessageAttributeHooks.mergeAttributes.register({ previous, updated in
            MTAntiDeleteCapture.carryOverLocalAttributes(from: previous, into: &updated)
        })

        let isApp = MTCore.environment?.process.isApp ?? true
        if isApp {
            MTAccountHooks.accountWillStart.register({ context in
                MTAntiDeleteAccounts.shared.accountDidStart(context)
                if !context.isSupplementary {
                    MTAntiDeleteLegacyImport.importIfNeeded(accountId: context.id, postbox: context.postbox)
                }
            })
            MTAccountHooks.accountWillBeRemoved.register({ id in
                MTAntiDeleteAccounts.shared.accountWillBeRemoved(id)
            })
        }
    }
}
