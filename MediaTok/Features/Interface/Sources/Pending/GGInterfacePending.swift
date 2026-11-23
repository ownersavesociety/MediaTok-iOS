import Foundation
import UIKit
import Display
import AccountContext
import GGCore
import GGHooks

// Registrations on the Settings tab points (dynamic rows, order) and on
// `GGChatScreenHooks.openDocument`.

enum GGInterfacePending {
    static func register() {
        GGSettingsTabPending.register()

        // Open `.icons` packs or `.mtbadge` packages directly from chats.
        GGChatScreenHooks.openDocument.register({ request in
            let name = request.fileName.lowercased()
            let url = URL(fileURLWithPath: request.path)
            if name.hasSuffix("." + GGIconPackStorage.fileExtension) {
                GGIconPackScreens.install(archive: url, context: request.context, from: request.controller, confirm: true)
                return true
            }
            if name.hasSuffix(".mtbadge") {
                GGBadgeGallery.importFile(url, context: request.context, from: request.controller)
                return true
            }
            return false
        })
    }
}
