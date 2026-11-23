import Foundation
import UIKit
import Display
import TelegramPresentationData
import AccountContext
import GGCore
import GGHooks

/// Entry point of the module. `GGFeatures.registerAll()` calls `register()` first, before any
/// feature registers its rows.
public enum GGSettingsUI {
    private static var isRegistered = false

    public static func register() {
        assert(Thread.isMainThread)
        if self.isRegistered {
            return
        }
        self.isRegistered = true

        // The «MediaTok» row in Telegram's Settings: a section of its own right after «My Profile»
        //, the standard 30 pt tile.
        GGSettingsTabHooks.rows.register(GGSettingsTabRow(
            id: "mediatok.menu",
            placement: .ownSectionAfterMyProfile,
            order: 0,
            icon: { _ in
                return ggSettingsTileIcon()
            },
            title: {
                return GGStrings.Menu.title
            },
            action: { context, navigationController in
                navigationController?.pushViewController(ggMakeSettingsController(context: context))
            }
        ), order: 0)

        ggRegisterMenuSkeleton()
        ggRegisterBuiltInRows()
        ggRegisterLicensesTab()
    }

    /// Categories and tabs without rows are hidden, so nothing dead is ever reachable. The demo
    /// registration (`Demo/`) turns this on to show the whole skeleton before the features exist.
    public static var showsEmptyScreens: Bool {
        get {
            return GGMenuStorage.shared.showsEmptyTabs
        }
        set {
            GGMenuStorage.shared.showsEmptyTabs = newValue
        }
    }
}

/// Screens that live above this module in the dependency graph. Filled at launch from TelegramUI
///. A `nil` closure hides the row that needs it.
public final class GGSettingsUIEnvironment {
    public static let shared = GGSettingsUIEnvironment()

    /// Telegram's own language screen (`SettingsUI.LocalizationListController`), linked from
    /// «Настройки MediaTok › Язык»: MediaTok's language follows Telegram's by default.
    public var makeTelegramLanguageController: ((AccountContext) -> ViewController)?

    private init() {
    }
}
