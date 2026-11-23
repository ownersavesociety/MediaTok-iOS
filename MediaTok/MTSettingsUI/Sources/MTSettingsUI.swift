import Foundation
import UIKit
import Display
import TelegramPresentationData
import AccountContext
import MTCore
import MTHooks

/// Entry point of the module. `MTFeatures.registerAll()` calls `register()` first, before any
/// feature registers its rows.
public enum MTSettingsUI {
    private static var isRegistered = false

    public static func register() {
        assert(Thread.isMainThread)
        if self.isRegistered {
            return
        }
        self.isRegistered = true

        // The «MediaTok» row in Telegram's Settings: a section of its own right after «My Profile»
        //, the standard 30 pt tile.
        MTSettingsTabHooks.rows.register(MTSettingsTabRow(
            id: "mediatok.menu",
            placement: .ownSectionAfterMyProfile,
            order: 0,
            icon: { _ in
                return mtSettingsTileIcon()
            },
            title: {
                return MTStrings.Menu.title
            },
            action: { context, navigationController in
                navigationController?.pushViewController(mtMakeSettingsController(context: context))
            }
        ), order: 0)

        mtRegisterMenuSkeleton()
        mtRegisterBuiltInRows()
        mtRegisterLicensesTab()
    }

    /// Categories and tabs without rows are hidden, so nothing dead is ever reachable. The demo
    /// registration (`Demo/`) turns this on to show the whole skeleton before the features exist.
    public static var showsEmptyScreens: Bool {
        get {
            return MTMenuStorage.shared.showsEmptyTabs
        }
        set {
            MTMenuStorage.shared.showsEmptyTabs = newValue
        }
    }
}

/// Screens that live above this module in the dependency graph. Filled at launch from TelegramUI
///. A `nil` closure hides the row that needs it.
public final class MTSettingsUIEnvironment {
    public static let shared = MTSettingsUIEnvironment()

    /// Telegram's own language screen (`SettingsUI.LocalizationListController`), linked from
    /// «Настройки MediaTok › Язык»: MediaTok's language follows Telegram's by default.
    public var makeTelegramLanguageController: ((AccountContext) -> ViewController)?

    private init() {
    }
}
