import Foundation
import UIKit
import Display
import AccountContext
import MTCore
import MTHooks

// Registrations on the Settings tab points (dynamic rows, order) and on
// `MTChatScreenHooks.openDocument`.

enum MTInterfacePending {
    static func register() {
        MTSettingsTabPending.register()

        // Open `.icons` packs or `.mtbadge` packages directly from chats.
        MTChatScreenHooks.openDocument.register({ request in
            let name = request.fileName.lowercased()
            let url = URL(fileURLWithPath: request.path)
            if name.hasSuffix("." + MTIconPackStorage.fileExtension) {
                MTIconPackScreens.install(archive: url, context: request.context, from: request.controller, confirm: true)
                return true
            }
            if name.hasSuffix(".mtbadge") {
                MTBadgeGallery.importFile(url, context: request.context, from: request.controller)
                return true
            }
            return false
        })
    }
}
