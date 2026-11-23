import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ItemListUI
import MTCore
import MTSettingsUI

// The nick badge screen: the account's own badge, what a badge costs (from the server, only while
// this screen is open), and the way to the bot. Opened from the menu and from a bulletin's "More".

func mtMakeNickBadgeScreen(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId
    weak var controllerRef: ItemListController?

    let configSignal: Signal<MTNickBadgeServerConfig?, NoError> = MTNickBadgeSettings.isEnabled.signal
    |> distinctUntilChanged
    |> mapToSignal { _ -> Signal<MTNickBadgeServerConfig?, NoError> in
        return MTNickBadgeService.shared.serverConfig()
    }
    let changes: Signal<Void, NoError> = .single(Void()) |> then(MTNickBadgeService.shared.changes)

    let model = combineLatest(queue: .mainQueue(), MTNickBadgeSettings.isEnabled.signal, configSignal, changes, MTLocalization.shared.languageCodeSignal)
    |> map { isEnabled, config, _, _ -> MTPEScreenModel in
        var model = MTPEScreenModel(title: MTStrings.NickBadge.Screen.title)

        let badge = isEnabled ? MTNickBadgeService.shared.badge(for: accountPeerId) : nil
        let status: String
        if !isEnabled {
            status = MTStrings.NickBadge.Status.off
        } else if let badge = badge {
            status = badge.kind == .team ? MTStrings.NickBadge.Status.team : MTStrings.NickBadge.Status.active
        } else {
            status = MTStrings.NickBadge.Status.none
        }
        let icon = badge.flatMap { MTNickBadgeArt.image(for: $0, height: 28.0) } ?? MTNickBadgeArt.sampleImage(height: 28.0)
        var statusSection: [MTPERow] = [
            MTPERow(id: "statusHeader", kind: .header(MTStrings.NickBadge.Screen.statusHeader)),
            MTPERow(id: "status", kind: .disclosure(title: MTStrings.NickBadge.Screen.status, label: status, icon: MTPEImage(image: icon), enabled: true))
        ]
        if !isEnabled {
            statusSection.append(MTPERow(id: "statusFooter", kind: .footer(MTStrings.NickBadge.Screen.offFooter)))
        }
        model.tap["status"] = {
            if badge != nil {
                mtPresentNickBadgeBulletin(context: context, peerId: accountPeerId)
            }
        }
        model.sections.append(statusSection)

        var getSection: [MTPERow] = [MTPERow(id: "getHeader", kind: .header(MTStrings.NickBadge.Screen.getHeader))]
        if let config = config {
            if let price = config.standard {
                getSection.append(MTPERow(id: "planStandard", kind: .disclosure(title: MTStrings.NickBadge.Screen.planStandard, label: mtNickBadgePriceLabel(price), icon: nil, enabled: true)))
            }
            if let price = config.custom {
                getSection.append(MTPERow(id: "planCustom", kind: .disclosure(title: MTStrings.NickBadge.Screen.planCustom, label: mtNickBadgePriceLabel(price), icon: nil, enabled: true)))
            }
        } else {
            getSection.append(MTPERow(id: "pricesLoading", kind: .disclosure(title: MTStrings.NickBadge.Screen.pricesLoading, label: "", icon: nil, enabled: false)))
        }
        getSection.append(MTPERow(id: "openBot", kind: .action(title: MTStrings.NickBadge.Screen.openBot, destructive: false, enabled: true)))
        let bot = config?.bot ?? MTNickBadgeService.shared.botUsername
        getSection.append(MTPERow(id: "info", kind: .footer(MTStrings.NickBadge.Screen.info(bot: bot))))
        let openBot = {
            guard let navigationController = controllerRef?.navigationController as? NavigationController else {
                return
            }
            MTNickBadgeService.shared.noteWentToBot()
            mtProfileExportOpenTelegramLink(context: context, url: "https://t.me/" + bot, navigationController: navigationController)
        }
        model.tap["planStandard"] = openBot
        model.tap["planCustom"] = openBot
        model.tap["openBot"] = openBot
        model.sections.append(getSection)
        return model
    }

    let controller = mtPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

/// «590 ₽ · 250 ⭐️», «$5 · 250 ⭐️» — whatever the server knows.
func mtNickBadgePriceLabel(_ price: MTNickBadgeServerConfig.Price) -> String {
    var parts: [String] = []
    if let local = price.local {
        parts.append(local)
    } else if let usd = price.usd {
        parts.append(MTStrings.NickBadge.Screen.priceUsd(amount: usd))
    }
    if let stars = price.stars {
        parts.append(MTStrings.NickBadge.Screen.priceStars(amount: "\(stars)"))
    }
    return parts.joined(separator: " · ")
}

// MARK: - Menu (More › Nick badge)

enum MTNickBadgeMenu {
    static func register() {
        MTMenuRegistry.register(MTMenuRow(
            id: "nickBadge.isEnabled",
            section: .main(of: .moreNickBadge),
            order: 100,
            title: { MTStrings.NickBadge.Menu.show },
            subtitle: { MTStrings.NickBadge.Menu.showInfo },
            kind: .toggle(.global(MTNickBadgeSettings.isEnabled)),
            searchKeywords: { [MTStrings.NickBadge.Menu.keywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "nickBadge.screen",
            section: .main(of: .moreNickBadge),
            order: 200,
            title: { MTStrings.NickBadge.Menu.screen },
            subtitle: { MTStrings.NickBadge.Menu.screenInfo },
            icon: .bundle("Chat/Context Menu/Tag"),
            kind: .action({ context in
                context.push(mtMakeNickBadgeScreen(context: context.context))
            }),
            searchKeywords: { [MTStrings.NickBadge.Menu.keywords] }
        ))
    }
}
