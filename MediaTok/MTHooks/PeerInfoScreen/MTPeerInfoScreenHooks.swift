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
        sections.afterMyProfile.append(("mt.section.\(row.id)" as AnyHashable, [PeerInfoScreenDisclosureItem(id: "mt.\(row.id)", text: row.title(), icon: row.icon(presentationData.theme), action: {
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
                dynamicItems.append(PeerInfoScreenDisclosureItem(id: "mt.dynamic.\(row.id)", label: row.label.flatMap { .text($0) } ?? .none, text: row.title, icon: row.icon, action: {
                    row.action(context, navigationController ?? (context.sharedContext.mainWindow?.viewController as? NavigationController))
                }))
            }
        }
        if !dynamicItems.isEmpty {
            sections.afterMyProfile.append(("mt.dynamic" as AnyHashable, dynamicItems))
        }
    }
    if MTSettingsTabHooks.rows.isEmpty {
        return sections
    }
    func makeItem(_ row: MTSettingsTabRow) -> PeerInfoScreenItem {
        return PeerInfoScreenDisclosureItem(id: "mt.\(row.id)", text: row.title(), icon: row.icon(presentationData.theme), action: {
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
        sections.bottom.append(("mt.bottom" as AnyHashable, bottom))
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
        items.insert(PeerInfoScreenLabeledValueItem(id: "mt.\(row.id)", label: row.label, rightLabel: row.rightLabel, text: row.text, action: itemAction, longTapAction: itemLongTapAction, requestLayout: { animated in
            interaction.requestLayout(animated)
        }), at: insertionIndex)
        insertionIndex += 1
    }
}

/// MediaTok hook target: `infoItems(...)` in PeerInfoProfileItems.swift: dedicated Discord-style «Интеграции» section.
func mtAppendPeerInfoIntegrationSection(_ result: inout [(AnyHashable, [PeerInfoScreenItem])], data: PeerInfoScreenData, context: AccountContext, interaction: PeerInfoInteraction) {
    if MTPeerInfoHooks.integrationCards.isEmpty {
        return
    }
    guard let peerInfoContext = mtPeerInfoContext(data: data, context: context, interaction: interaction) else {
        return
    }
    let cards = MTPeerInfoHooks.integrations(context: peerInfoContext)
    guard !cards.isEmpty else {
        return
    }
    var sectionItems: [PeerInfoScreenItem] = [
        PeerInfoScreenHeaderItem(id: "mt.integrations.header" as AnyHashable, text: "Интеграции")
    ]
    for card in cards {
        sectionItems.append(MTDiscordIntegrationCardItem(id: "mt.integration.\(card.id)" as AnyHashable, card: card))
    }
    result.append(("mt.integrations.section" as AnyHashable, sectionItems))
}

private final class MTDiscordIntegrationCardItem: PeerInfoScreenItem {
    let id: AnyHashable
    let card: MTPeerInfoIntegrationCard

    init(id: AnyHashable, card: MTPeerInfoIntegrationCard) {
        self.id = id
        self.card = card
    }

    func node() -> PeerInfoScreenItemNode {
        return MTDiscordIntegrationCardItemNode()
    }
}

private final class MTDiscordIntegrationCardItemNode: PeerInfoScreenItemNode {
    private let highlightView = UIView()
    private let iconImageView = UIImageView()
    private let usernameLabel = UILabel()
    private let memberSinceLabel = UILabel()
    private let statsLabel = UILabel()
    private let arrowImageView = UIImageView()
    private let bottomSeparatorView = UIView()

    private var currentCard: MTPeerInfoIntegrationCard?
    private var lastRenderedPlatform: String?
    private var lastRenderedDark: Bool?

    override init() {
        super.init()
        self.isUserInteractionEnabled = true
    }

    override func didLoad() {
        super.didLoad()
        self.highlightView.alpha = 0.0
        self.highlightView.isUserInteractionEnabled = false
        self.view.addSubview(self.highlightView)

        self.iconImageView.contentMode = .scaleAspectFit
        self.view.addSubview(self.iconImageView)

        self.usernameLabel.font = UIFont.systemFont(ofSize: 15.5, weight: .semibold)
        self.usernameLabel.lineBreakMode = .byTruncatingTail
        self.view.addSubview(self.usernameLabel)

        self.memberSinceLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .regular)
        self.memberSinceLabel.lineBreakMode = .byTruncatingTail
        self.view.addSubview(self.memberSinceLabel)

        self.statsLabel.lineBreakMode = .byTruncatingTail
        self.view.addSubview(self.statsLabel)

        let arrowConfig = UIImage.SymbolConfiguration(pointSize: 14.0, weight: .medium)
        self.arrowImageView.image = UIImage(systemName: "arrow.up.right", withConfiguration: arrowConfig)
        self.arrowImageView.contentMode = .scaleAspectFit
        self.view.addSubview(self.arrowImageView)

        self.view.addSubview(self.bottomSeparatorView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
        self.view.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.42
        self.view.addGestureRecognizer(longPress)
    }

    @objc private func handleTap() {
        guard let action = self.currentCard?.action else { return }
        self.highlightView.alpha = 1.0
        UIView.animate(withDuration: 0.22) {
            self.highlightView.alpha = 0.0
        }
        action()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let longAction = self.currentCard?.longTapAction else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        longAction()
    }

    override func update(
        context: AccountContext,
        width: CGFloat,
        safeInsets: UIEdgeInsets,
        presentationData: PresentationData,
        item: PeerInfoScreenItem,
        topItem: PeerInfoScreenItem?,
        bottomItem: PeerInfoScreenItem?,
        hasCorners: Bool,
        transition: ContainedViewLayoutTransition
    ) -> CGFloat {
        guard let cardItem = item as? MTDiscordIntegrationCardItem else {
            return 0.0
        }
        let card = cardItem.card
        self.currentCard = card

        let theme = presentationData.theme
        let isDark = theme.overallDarkAppearance
        let primaryColor = theme.list.itemPrimaryTextColor
        let secondaryColor = theme.list.itemSecondaryTextColor

        self.highlightView.backgroundColor = theme.list.itemHighlightedBackgroundColor
        self.usernameLabel.textColor = primaryColor
        self.memberSinceLabel.textColor = secondaryColor
        self.arrowImageView.tintColor = secondaryColor
        self.bottomSeparatorView.backgroundColor = theme.list.itemPlainSeparatorColor

        if self.lastRenderedPlatform != card.platform || self.lastRenderedDark != isDark {
            self.lastRenderedPlatform = card.platform
            self.lastRenderedDark = isDark
            self.iconImageView.image = MTPeerInfoBrandIcons.image(for: card.platform, size: 32.0, isDark: isDark)
        }

        self.usernameLabel.text = card.username

        let hasMemberSince = !(card.memberSinceText ?? "").isEmpty
        self.memberSinceLabel.text = card.memberSinceText
        self.memberSinceLabel.isHidden = !hasMemberSince

        let hasStats = !(card.primaryStatBold ?? "").isEmpty
        if hasStats {
            let attr = NSMutableAttributedString()
            let boldAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: primaryColor
            ]
            let regAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12.5, weight: .regular),
                .foregroundColor: secondaryColor
            ]
            if let pBold = card.primaryStatBold, !pBold.isEmpty {
                attr.append(NSAttributedString(string: pBold, attributes: boldAttrs))
            }
            if let pLabel = card.primaryStatLabel, !pLabel.isEmpty {
                attr.append(NSAttributedString(string: " \(pLabel)", attributes: regAttrs))
            }
            if let sBold = card.secondaryStatBold, !sBold.isEmpty {
                attr.append(NSAttributedString(string: "  ·  ", attributes: regAttrs))
                attr.append(NSAttributedString(string: sBold, attributes: boldAttrs))
                if let sLabel = card.secondaryStatLabel, !sLabel.isEmpty {
                    attr.append(NSAttributedString(string: " \(sLabel)", attributes: regAttrs))
                }
            }
            self.statsLabel.attributedText = attr
            self.statsLabel.isHidden = false
        } else {
            self.statsLabel.attributedText = nil
            self.statsLabel.isHidden = true
        }

        let leftInset = safeInsets.left + 16.0
        let rightInset = safeInsets.right + 16.0
        let iconSize: CGFloat = 34.0
        let arrowSize: CGFloat = 18.0
        let textX = leftInset + iconSize + 12.0
        let textMaxRight = width - rightInset - arrowSize - 10.0
        let textWidth = max(40.0, textMaxRight - textX)

        let topPad: CGFloat = 13.0
        let bottomPad: CGFloat = 13.0
        var y = topPad

        let nameH: CGFloat = 20.0
        self.usernameLabel.frame = CGRect(x: textX, y: y, width: textWidth, height: nameH)
        y += nameH

        if hasMemberSince {
            y += 2.0
            let h: CGFloat = 16.0
            self.memberSinceLabel.frame = CGRect(x: textX, y: y, width: textWidth, height: h)
            y += h
        }

        if hasStats {
            y += 3.0
            let h: CGFloat = 16.0
            self.statsLabel.frame = CGRect(x: textX, y: y, width: textWidth, height: h)
            y += h
        }

        let totalHeight = max(62.0, y + bottomPad)
        self.highlightView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: totalHeight)
        self.iconImageView.frame = CGRect(x: leftInset, y: floor((totalHeight - iconSize) * 0.5), width: iconSize, height: iconSize)
        self.arrowImageView.frame = CGRect(x: width - rightInset - arrowSize, y: floor((totalHeight - arrowSize) * 0.5), width: arrowSize, height: arrowSize)
        self.arrowImageView.isHidden = (card.action == nil)

        let showSep = bottomItem != nil
        self.bottomSeparatorView.isHidden = !showSep
        if showSep {
            let pixel = 1.0 / UIScreen.main.scale
            self.bottomSeparatorView.frame = CGRect(x: textX, y: totalHeight - pixel, width: max(0.0, width - textX - rightInset), height: pixel)
        }

        return totalHeight
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
