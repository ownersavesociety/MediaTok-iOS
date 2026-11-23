// Compiled into PeerInfoScreen (filegroup //MediaTok/MTHooks:PeerInfoScreenHookSources):
// maps the public points (MTSettingsTabHooks, MTPeerInfoHooks) to PeerInfoScreen's internal
// item types. No feature logic.

import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import MTCore
import MTHooks

/// Sections MediaTok adds to the Settings tab.
struct MTSettingsTabSections {
    /// Right below «Мой профиль» (shortcuts).
    var afterMyProfile: [(AnyHashable, [PeerInfoScreenItem])] = []
    /// At the end of the tab.
    var bottom: [(AnyHashable, [PeerInfoScreenItem])] = []
}

/// MediaTok hook target: `settingsItems(...)` in PeerInfoSettingsItems.swift, before the sections are
/// assembled: hides Telegram's rows features asked to hide, reorders them, adds MediaTok's rows.
func mtApplySettingsTabHooks(_ items: inout [SettingsSection: [PeerInfoScreenItem]], context: AccountContext, presentationData: PresentationData) -> MTSettingsTabSections {
    var sections = MTSettingsTabSections()
    // Rows with a section of their own come first after «Мой профиль» (the «MediaTok» entry).
    for row in MTSettingsTabHooks.visibleRows(placement: .ownSectionAfterMyProfile, context: context) {
        sections.afterMyProfile.append(("gg.section.\(row.id)" as AnyHashable, [PeerInfoScreenDisclosureItem(id: "gg.\(row.id)", text: row.title(), icon: row.icon(presentationData.theme), action: {
            row.action(context, context.sharedContext.mainWindow?.viewController as? NavigationController)
        })]))
    }
    if !MTSettingsTabHooks.hiddenItem.isEmpty {
        for section in SettingsSection.allCases {
            guard let sectionItems = items[section] else {
                continue
            }
            let sectionName = "\(section)"
            items[section] = sectionItems.filter { item in
                return !MTSettingsTabHooks.isItemHidden(MTSettingsTabItemKey(section: sectionName, itemId: item.id), context: context)
            }
        }
    }
    if !MTSettingsTabHooks.itemOrder.isEmpty {
        for section in SettingsSection.allCases {
            guard let sectionItems = items[section], sectionItems.count > 1 else {
                continue
            }
            var ids = sectionItems.map { $0.id }
            for handler in MTSettingsTabHooks.itemOrder.handlers {
                ids = handler("\(section)", ids, context)
            }
            var byId: [AnyHashable: PeerInfoScreenItem] = [:]
            for item in sectionItems where byId[item.id] == nil {
                byId[item.id] = item
            }
            let reordered = ids.compactMap { byId[$0] }
            if reordered.count == sectionItems.count && Set(ids).count == ids.count {
                items[section] = reordered
            }
        }
    }
    if !MTSettingsTabHooks.dynamicRows.isEmpty {
        let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController
        var dynamicItems: [PeerInfoScreenItem] = []
        for handler in MTSettingsTabHooks.dynamicRows.handlers {
            for row in handler(context, presentationData) {
                dynamicItems.append(PeerInfoScreenDisclosureItem(id: "gg.dynamic.\(row.id)", label: row.label.flatMap { .text($0) } ?? .none, text: row.title, icon: row.icon, action: {
                    row.action(context, navigationController ?? (context.sharedContext.mainWindow?.viewController as? NavigationController))
                }))
            }
        }
        if !dynamicItems.isEmpty {
            sections.afterMyProfile.append(("gg.dynamic" as AnyHashable, dynamicItems))
        }
    }
    if MTSettingsTabHooks.rows.isEmpty {
        return sections
    }
    func makeItem(_ row: MTSettingsTabRow) -> PeerInfoScreenItem {
        return PeerInfoScreenDisclosureItem(id: "gg.\(row.id)", text: row.title(), icon: row.icon(presentationData.theme), action: {
            row.action(context, context.sharedContext.mainWindow?.viewController as? NavigationController)
        })
    }
    let above = MTSettingsTabHooks.visibleRows(placement: .aboveMyProfile, context: context).map(makeItem)
    let below = MTSettingsTabHooks.visibleRows(placement: .belowMyProfile, context: context).map(makeItem)
    if !above.isEmpty || !below.isEmpty {
        items[.myProfile] = above + (items[.myProfile] ?? []) + below
    }
    let bottom = MTSettingsTabHooks.visibleRows(placement: .bottom, context: context).map(makeItem)
    if !bottom.isEmpty {
        sections.bottom.append(("gg.bottom" as AnyHashable, bottom))
    }
    return sections
}

/// MediaTok hook target: the end of `settingsItems(...)`: MediaTok's sections go to their places.
func mtInsertSettingsTabSections(_ result: inout [(AnyHashable, [PeerInfoScreenItem])], _ sections: MTSettingsTabSections) {
    if !sections.afterMyProfile.isEmpty {
        var index = 0
        for (offset, entry) in result.enumerated() {
            if let section = entry.0.base as? SettingsSection, section.rawValue <= SettingsSection.myProfile.rawValue {
                index = offset + 1
            }
        }
        result.insert(contentsOf: sections.afterMyProfile, at: index)
    }
    result.append(contentsOf: sections.bottom)
}

/// MediaTok hook target: PeerInfoScreen — the Settings tab is rebuilt when a feature changed what it
/// shows (`MTSettingsTabHooks.invalidate()`), not only when Telegram's data changes.
func mtSettingsTabRefreshing<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> {
    if !MTSettingsTabHooks.changesTab {
        return signal
    }
    return combineLatest(signal, MTSettingsTabHooks.revision)
    |> map { value, _ -> T in
        return value
    }
}

/// The group the profile was opened from (a member's profile opened from a group message).
func mtPeerInfoSourceChatPeerId(_ interaction: PeerInfoInteraction) -> EnginePeer.Id? {
    return mtPeerInfoSourceMessageId(interaction)?.peerId
}

/// The message the profile was opened from (a tap on its author), if any.
func mtPeerInfoSourceMessageId(_ interaction: PeerInfoInteraction) -> EngineMessage.Id? {
    return (interaction.getController() as? PeerInfoScreenImpl)?.controllerNode.sourceMessageId
}

/// The point context of a profile's info items; nil before the peer is known.
func mtPeerInfoContext(data: PeerInfoScreenData, context: AccountContext, interaction: PeerInfoInteraction) -> MTPeerInfoContext? {
    guard let peer = data.peer else {
        return nil
    }
    let sourceMessageId = mtPeerInfoSourceMessageId(interaction)
    return MTPeerInfoContext(context: context, peer: peer, chatPeer: data.chatPeer, isSettings: false, controller: interaction.getController(), sourceChatPeerId: sourceMessageId?.peerId, sourceMessageId: sourceMessageId, cachedData: data.cachedData)
}

/// MediaTok hook target: `infoItems(...)` in PeerInfoProfileItems.swift — Telegram's items features hide.
func mtPeerInfoHidesItem(_ kind: MTPeerInfoItemKind, data: PeerInfoScreenData, context: AccountContext, interaction: PeerInfoInteraction) -> Bool {
    return MTPeerInfoHooks.hidesItem(kind, context: mtPeerInfoContext(data: data, context: context, interaction: interaction))
}

/// MediaTok hook target: `infoItems(...)` in PeerInfoProfileItems.swift: feature rows (ID, DC, dates).
func mtAppendPeerInfoRows(_ items: inout [PeerInfoScreenItem], data: PeerInfoScreenData, context: AccountContext, interaction: PeerInfoInteraction) {
    if MTPeerInfoHooks.infoRows.isEmpty {
        return
    }
    guard let peerInfoContext = mtPeerInfoContext(data: data, context: context, interaction: interaction) else {
        return
    }
    let rows = MTPeerInfoHooks.rows(context: peerInfoContext)
    // A comment closes its card (a bot's «Открывая это мини-приложение…» under «Открыть приложение»):
    // rows after it got the card's background drawn over the comment. They go in front of it.
    var insertionIndex = items.count
    while insertionIndex > 0 && items[insertionIndex - 1] is PeerInfoScreenCommentItem {
        insertionIndex -= 1
    }
    for row in rows {
        var itemAction: ((ASDisplayNode, Promise<Bool>?) -> Void)?
        if let action = row.action {
            itemAction = { _, _ in
                action()
            }
        }
        var itemLongTapAction: ((ASDisplayNode) -> Void)?
        if let longTapAction = row.longTapAction {
            itemLongTapAction = { _ in
                longTapAction()
            }
        }
        items.insert(PeerInfoScreenLabeledValueItem(id: "gg.\(row.id)", label: row.label, rightLabel: row.rightLabel, text: row.text, action: itemAction, longTapAction: itemLongTapAction, requestLayout: { animated in
            interaction.requestLayout(animated)
        }), at: insertionIndex)
        insertionIndex += 1
    }
}

/// MediaTok hook target: `PeerInfoScreenNode`, right after `paneContainerNode.update(...)` — the shared
/// media area as features see it (MTPeerInfoHooks.paneContainerDidLayout). Without handlers: nothing.
func mtPeerInfoPaneContainerDidLayout(_ node: PeerInfoScreenNode) {
    if MTPeerInfoHooks.paneContainerDidLayout.isEmpty {
        return
    }
    let hasPanes = !node.state.isEditing && !(node.data?.availablePanes ?? []).isEmpty
    let layout = MTPeerInfoPaneLayout(context: node.context, peerId: node.peerId, isSettings: node.isSettings, hasPanes: hasPanes, paneContainer: node.paneContainerNode, controller: node.controller)
    for handler in MTPeerInfoHooks.paneContainerDidLayout.handlers {
        handler(layout)
    }
}
