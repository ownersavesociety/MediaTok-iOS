// The «Settings» tab: MediaTok's rows (the «MediaTok» entry, shortcuts) and hiding of
// Telegram's own rows. Applied by `mtSettingsTabItems` (filegroup PeerInfoScreen/) inside
// `settingsItems(...)` in PeerInfoSettingsItems.swift. Signature fixed by MediaTok spec.

import Foundation
import UIKit
import SwiftSignalKit
import Display
import TelegramPresentationData
import AccountContext
import MTCore

public struct MTSettingsTabRow {
    /// `ownSectionAfterMyProfile`: a section of its own right after «Мой профиль» (before the
    /// dynamic rows), one row per section.
    public enum Placement { case aboveMyProfile, belowMyProfile, ownSectionAfterMyProfile, bottom }
    public let id: String
    public let placement: Placement
    public let order: Int
    public let icon: (PresentationTheme) -> UIImage?        // 30 pt tile like the neighbours
    public let title: () -> String
    public let isVisible: (AccountContext) -> Bool
    public let action: (AccountContext, NavigationController?) -> Void
    public init(id: String, placement: Placement, order: Int,
                icon: @escaping (PresentationTheme) -> UIImage?, title: @escaping () -> String,
                isVisible: @escaping (AccountContext) -> Bool = { _ in true },
                action: @escaping (AccountContext, NavigationController?) -> Void) {
        self.id = id
        self.placement = placement
        self.order = order
        self.icon = icon
        self.title = title
        self.isVisible = isVisible
        self.action = action
    }
}

/// A row of Telegram's own Settings tab: `section` is the case name of PeerInfoScreen's
/// `SettingsSection` ("myProfile", "shortcuts", "advanced", "payment", …), `itemId` the item's id
/// inside it (see the table in MediaTok spec).
public struct MTSettingsTabItemKey: Hashable {
    public let section: String
    public let itemId: AnyHashable

    public init(section: String, itemId: AnyHashable) {
        self.section = section
        self.itemId = itemId
    }
}

public enum MTSettingsTabHooks {
    public static let rows = MTHookPoint<MTSettingsTabRow>("settingsTab.rows")

    /// Policy: `true` hides one of Telegram's own rows («Скрыть в настройках»). Asked for every row
    /// on every rebuild of the tab: answer from a snapshot.
    public static let hiddenItem = MTHookPoint<(MTSettingsTabItemKey, AccountContext) -> Bool>("settingsTab.hiddenItem")

    /// The visible rows of a placement, in `order`.
    public static func visibleRows(placement: MTSettingsTabRow.Placement, context: AccountContext) -> [MTSettingsTabRow] {
        if MTSettingsTabHooks.rows.isEmpty {
            return []
        }
        return MTSettingsTabHooks.rows.handlers.filter { row in
            return row.placement == placement && row.isVisible(context)
        }.sorted(by: { $0.order < $1.order })
    }

    public static func isItemHidden(_ key: MTSettingsTabItemKey, context: AccountContext) -> Bool {
        for handler in MTSettingsTabHooks.hiddenItem.handlers {
            if handler(key, context) {
                return true
            }
        }
        return false
    }
}

/// A per-account row of the Settings tab (shortcuts to chats, mini apps, sites). Built from cached
/// values on every rebuild of the tab; the provider calls `MTSettingsTabHooks.invalidate()` when
/// something visible changed.
public struct MTSettingsTabDynamicRow {
    public let id: String
    public let title: String
    public let label: String?
    /// 30 pt, already rounded / tiled by the provider; nil = no icon yet.
    public let icon: UIImage?
    public let action: (AccountContext, NavigationController?) -> Void

    public init(id: String, title: String, label: String?, icon: UIImage?, action: @escaping (AccountContext, NavigationController?) -> Void) {
        self.id = id
        self.title = title
        self.label = label
        self.icon = icon
        self.action = action
    }
}

extension MTSettingsTabHooks {
    /// Providers (all, in registration order): rows of a section right below «Мой профиль».
    /// Called on the main thread on every rebuild of the tab: answer from caches.
    public static let dynamicRows = MTHookPoint<(AccountContext, PresentationData) -> [MTSettingsTabDynamicRow]>("settingsTab.dynamicRows")

    /// Transformer: the order of Telegram's own rows inside one section (`section` as in
    /// `MTSettingsTabItemKey`), given their ids in Telegram's order. Must return the same ids;
    /// a result that loses or adds ids is ignored.
    public static let itemOrder = MTHookPoint<(String, [AnyHashable], AccountContext) -> [AnyHashable]>("settingsTab.itemOrder")

    /// Re-emits when a feature changed what the tab shows (main thread).
    public static var revision: Signal<Int, NoError> {
        return mtSettingsTabRevisionPromise.get()
    }

    /// Rebuilds the Settings tab (hidden rows, order, dynamic rows changed). Main thread.
    public static func invalidate() {
        assert(Thread.isMainThread)
        mtSettingsTabRevisionValue += 1
        mtSettingsTabRevisionPromise.set(mtSettingsTabRevisionValue)
    }

    /// True when some feature changes the tab beyond static rows (the tab then listens to `revision`).
    public static var changesTab: Bool {
        return !MTSettingsTabHooks.dynamicRows.isEmpty || !MTSettingsTabHooks.itemOrder.isEmpty || !MTSettingsTabHooks.hiddenItem.isEmpty
    }
}

private let mtSettingsTabRevisionPromise = ValuePromise<Int>(0, ignoreRepeated: true)
private var mtSettingsTabRevisionValue = 0
