import Foundation
import MTCore
import MTFeaturesShared

/// Keys of legacy format (its Swiftgram layer) that map to MTExtras settings. Runs once.
enum MTExtrasMigrations {
    static func register() {
        MTMigrations.registerGlobal(id: "extras.v1") { legacy in
            // «В историю» in the share sheet: on by default there, our switch hides it.
            if let value = legacy.bool("showRepostToStoryV2") {
                if !value {
                    MTExtrasSettings.hideRepostToStory.set(true)
                }
                legacy.removeLegacyKey("showRepostToStoryV2")
            }
            legacy.removeLegacyKey("showRepostToStory")
            // A hidden key of legacy format (no switch): the system share sheet everywhere.
            if let value = legacy.bool("forceSystemSharing") {
                if value {
                    MTExtrasSettings.systemShareSheet.set(true)
                }
                legacy.removeLegacyKey("forceSystemSharing")
            }
        }
        // «Скрыть поиск в таббаре» removed: nothing in this Telegram puts the
        // search button next to the tab bar, the switch did nothing. Its stored value goes too.
        MTMigrations.registerGlobal(id: "extras.hideTabBarSearch.removed.v1") { _ in
            MTRetiredSettings.remove(keys: ["extras.hideTabBarSearch"])
        }
        // «Данные сообщения (JSON)» in the message menu removed.
        MTMigrations.registerGlobal(id: "extras.messageJson.removed.v1") { legacy in
            MTRetiredSettings.remove(keys: ["extras.messageJson"])
            legacy.removeLegacyKey("contextShowJson")
        }
    }
}
