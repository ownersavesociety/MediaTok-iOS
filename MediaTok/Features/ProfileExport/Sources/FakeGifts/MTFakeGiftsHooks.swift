import Foundation
import UIKit
import Display
import AppBundle
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import GiftSetupScreen
import GiftViewScreen
import MTCore
import MTHooks

// Fake gifts on the profile: the own profile's gift list gets the account's fake gifts (filters,
// pinning and hidden ones respected), hide and pin on a fake are handled locally, and
// the "…" menu of any gift's screen offers "Add to my profile" (or "Edit" / "Delete" on a
// fake). The gate comes first: with the feature off nothing is read.

enum MTFakeGiftsHooks {
    static func register() {
        MTAccountHooks.accountWillStart.register({ start in
            MTFakeGiftsStore.shared.accountWillStart(start)
        })
        MTAccountHooks.accountWillBeRemoved.register({ id in
            MTFakeGiftsStore.shared.accountWillBeRemoved(id)
        })

        MTGiftHooks.profileGifts.register({ state, query in
            guard query.collectionId == nil else {
                return
            }
            if query.peerId != query.account.peerId {
                MTFakeGiftsStore.shared.checkGlobalGifts(account: query.account, forPeer: query.peerId)
            }
            var fakes: [ProfileGiftsContext.State.StarGift] = []
            if MTFakeGiftsSettings.isEnabled.value {
                fakes.append(contentsOf: MTFakeGiftsStore.shared.resolvedGifts(accountPeerId: query.account.peerId, forPeer: query.peerId))
                if !fakes.isEmpty {
                    MTFakeGiftsStore.shared.refreshIfNeeded(account: query.account)
                }
            }
            if query.peerId != query.account.peerId {
                fakes.append(contentsOf: MTFakeGiftsStore.shared.remoteGifts(forPeer: query.peerId))
            }
            if fakes.isEmpty {
                return
            }
            mtInsertFakeGifts(&state, fakes: fakes)
        })

        MTGiftHooks.localGiftAction.register({ reference, action, query in
            guard MTFakeGiftsSettings.isEnabled.value, let localId = MTFakeGiftsStore.localId(of: reference, accountPeerId: query.account.peerId) else {
                return false
            }
            switch action {
            case let .setSavedToProfile(saved):
                MTFakeGiftsStore.shared.updateFlags(accountPeerId: query.account.peerId, localId: localId, savedToProfile: saved, pinnedToTop: saved ? nil : false)
            case let .setPinnedToTop(pinned):
                MTFakeGiftsStore.shared.updateFlags(accountPeerId: query.account.peerId, localId: localId, savedToProfile: pinned ? true : nil, pinnedToTop: pinned)
            }
            return true
        })

        // A fake takes no slot of the server's pin limit and never reaches the server's pinned list.
        MTGiftHooks.isLocalGift.register({ reference, account in
            return MTFakeGiftsStore.localId(of: reference, accountPeerId: account.peerId) != nil
        })

        MTGiftViewHooks.menuItems.register({ menuContext in
            return mtFakeGiftMenuItems(menuContext)
        })
        MTGiftViewHooks.isLocalGift.register({ menuContext in
            return MTFakeGiftsStore.localId(of: menuContext.reference, accountPeerId: menuContext.context.account.peerId) != nil
        })

        // 100% Native Telegram GiftSetupScreen interception (any chat Gift button / Attachment -> Gift / Profile -> Gift)
        MTGiftSetupHooks.interceptSend.register({ sendContext in
            let context = sendContext.context
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            var totalStars = sendContext.gift.price
            if sendContext.includeUpgrade, let up = sendContext.gift.upgradeStars {
                totalStars += up
            }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: "Как отправить подарок?"),
                    ActionSheetButtonItem(title: "Отправить визуально (0 ⭐️ — в чат и профиль)", color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        mtSendVisualGiftFromNativeSetup(sendContext)
                    }),
                    ActionSheetButtonItem(title: "Купить за настоящие \(totalStars) ⭐️", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        sendContext.proceedRealPurchase()
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            if let controller = sendContext.controller {
                controller.present(sheet, in: .window(.root))
                return true
            }
            return false
        })

        // 100% Native Collectible Resale NFT interception (GiftOptionsScreen -> Resale -> GiftViewScreen -> GiftMessageScreen)
        MTGiftViewHooks.interceptResaleBuy.register({ buyContext in
            let context = buyContext.context
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: "\(buyContext.uniqueGift.title) #\(buyContext.uniqueGift.number)"),
                    ActionSheetButtonItem(title: "Подарить NFT визуально (0 ⭐️ — в чат и профиль)", color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        mtSendVisualUniqueGiftFromNativeResale(buyContext)
                    }),
                    ActionSheetButtonItem(title: "Купить за настоящие ⭐️ / TON", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        buyContext.proceedRealBuy()
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            let presenter = buyContext.messageController ?? buyContext.controller
            if let presenter {
                presenter.present(sheet, in: .window(.root))
                return true
            }
            return false
        })

        MTFakeGiftsPendingPoints.register()

        // Direct in-chat visual gift/NFT sender from the chat Send-button long-press menu.
        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            let targetPeerId = sendContext.peerId
            let context = sendContext.context
            guard targetPeerId != context.account.peerId, targetPeerId.namespace == Namespaces.Peer.CloudUser else {
                return []
            }
            return [
                .action(ContextMenuActionItem(text: "Подарить NFT / Подарок", icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Gift"), color: theme.contextMenu.primaryColor)
                }, action: { contextController, _ in
                    contextController?.dismiss(completion: nil)
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    let sheet = ActionSheetController(presentationData: presentationData)
                    sheet.setItemGroups([
                        ActionSheetItemGroup(items: [
                            ActionSheetTextItem(title: "Отправить подарок в чат (визуально)"),
                            ActionSheetButtonItem(title: "Каталог NFT (Маркеты и Конструктор)", color: .accent, action: { [weak sheet] in
                                sheet?.dismissAnimated()
                                let top = mtProfileExportTopController(context: context)?.1
                                mtPresentPortalsNftCatalog(context: context, from: top, targetPeerId: targetPeerId)
                            }),
                            ActionSheetButtonItem(title: "Обычные подарки Telegram", color: .accent, action: { [weak sheet] in
                                sheet?.dismissAnimated()
                                let top = mtProfileExportTopController(context: context)?.1
                                mtPresentGenericGiftPicker(context: context, from: top, targetPeerId: targetPeerId)
                            }),
                            ActionSheetButtonItem(title: "NFT по ссылке (t.me/nft/...)", color: .accent, action: { [weak sheet] in
                                sheet?.dismissAnimated()
                                let top = mtProfileExportTopController(context: context)?.1
                                mtPromptAddFakeUniqueGift(context: context, from: top, targetPeerId: targetPeerId)
                            })
                        ]),
                        ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                                sheet?.dismissAnimated()
                            })
                        ])
                    ])
                    sendContext.present(sheet)
                }))
            ]
        }, order: 74)

        // «Подарить визуально» from another person's profile: a collectible by its t.me/nft link.
        MTPeerInfoHooks.menuItems.register({ info in
            if info.isSettings {
                return []
            }
            let peer = info.peer
            let context = info.context
            guard peer.id != context.account.peerId, peer.id.namespace == Namespaces.Peer.CloudUser else {
                return []
            }
            MTFakeGiftsStore.shared.checkGlobalGifts(account: context.account, forPeer: peer.id)
            let targetPeerId = peer.id
            weak let controller = info.controller
            return [
                .action(ContextMenuActionItem(text: "Подарить NFT (Маркеты и Конструктор)", icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Gift"), color: theme.contextMenu.primaryColor)
                }, action: { contextController, _ in
                    contextController?.dismiss(completion: nil)
                    mtPresentPortalsNftCatalog(context: context, from: controller, targetPeerId: targetPeerId)
                })),
                .action(ContextMenuActionItem(text: "Подарить NFT по ссылке (t.me/nft/...)", icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Link"), color: theme.contextMenu.primaryColor)
                }, action: { contextController, _ in
                    contextController?.dismiss(completion: nil)
                    mtPromptAddFakeUniqueGift(context: context, from: controller, targetPeerId: targetPeerId)
                })),
                .action(ContextMenuActionItem(text: "Скопировать все NFT себе в профиль", icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.contextMenu.primaryColor)
                }, action: { contextController, _ in
                    contextController?.dismiss(completion: nil)
                    mtCopyAllPeerNftsToOwnProfile(context: context, peerId: targetPeerId, from: controller)
                })),
                .action(ContextMenuActionItem(text: "Подарить обычный подарок (визуально)", icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Gift"), color: theme.contextMenu.primaryColor)
                }, action: { contextController, _ in
                    contextController?.dismiss(completion: nil)
                    mtPresentGenericGiftPicker(context: context, from: controller, targetPeerId: targetPeerId)
                }))
            ]
        })
    }
}

// MARK: - The profile's list

/// Whether a fake gift is shown under the list's filter.
func mtFakeGiftMatches(_ gift: ProfileGiftsContext.State.StarGift, filter: ProfileGiftsContext.Filters) -> Bool {
    if gift.savedToProfile {
        if !filter.contains(.displayed) {
            return false
        }
    } else if !filter.contains(.hidden) {
        return false
    }
    switch gift.gift {
    case .unique:
        return filter.contains(.unique)
    case let .generic(generic):
        if generic.availability != nil {
            return filter.contains(.limitedUpgradable) || filter.contains(.limitedNonUpgradable)
        }
        return filter.contains(.unlimited)
    }
}

/// Pinned fakes after the real pinned gifts; the others by date among the real ones when the list
/// is sorted by date, after them otherwise.
func mtMergeFakeGifts(_ real: [ProfileGiftsContext.State.StarGift], fakes: [ProfileGiftsContext.State.StarGift], byDate: Bool) -> [ProfileGiftsContext.State.StarGift] {
    if fakes.isEmpty {
        return real
    }
    var pinnedCount = 0
    while pinnedCount < real.count && real[pinnedCount].pinnedToTop {
        pinnedCount += 1
    }
    var result = Array(real.prefix(pinnedCount))
    result.append(contentsOf: fakes.filter { $0.pinnedToTop })
    var rest = Array(real.dropFirst(pinnedCount))
    let others = fakes.filter { !$0.pinnedToTop }
    if byDate {
        for fake in others {
            if let index = rest.firstIndex(where: { $0.date < fake.date }) {
                rest.insert(fake, at: index)
            } else {
                rest.append(fake)
            }
        }
    } else {
        rest.append(contentsOf: others)
    }
    result.append(contentsOf: rest)
    return result
}

func mtInsertFakeGifts(_ state: inout ProfileGiftsContext.State, fakes: [ProfileGiftsContext.State.StarGift]) {
    let shown = fakes.filter { mtFakeGiftMatches($0, filter: state.filter) }
    state.gifts = mtMergeFakeGifts(state.gifts, fakes: fakes, byDate: true)
    state.filteredGifts = mtMergeFakeGifts(state.filteredGifts, fakes: shown, byDate: state.sorting == .date)
    state.count = (state.count ?? 0) + Int32(shown.count)
}

// MARK: - The gift screen's «…»

private func mtFakeGiftMenuItems(_ menuContext: MTGiftViewMenuContext) -> [ContextMenuItem] {
    let context = menuContext.context
    let accountPeerId = context.account.peerId
    weak let controller = menuContext.controller

    if let localId = MTFakeGiftsStore.localId(of: menuContext.reference, accountPeerId: accountPeerId) {
        var localItems: [ContextMenuItem] = [
            .action(ContextMenuActionItem(text: MTStrings.FakeGifts.Menu.edit, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.contextMenu.primaryColor)
            }, action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                mtOpenFakeGiftEditor(context: context, localId: localId, from: controller)
            }))
        ]
        if case .generic = menuContext.gift {
            localItems.append(.action(ContextMenuActionItem(text: "Улучшить в NFT (визуально)", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Gift"), color: theme.contextMenu.primaryColor)
            }, action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                mtPromptUpgradeLocalGiftToNft(context: context, localId: localId, from: controller)
            })))
        }
        localItems.append(.action(ContextMenuActionItem(text: MTStrings.FakeGifts.Menu.delete, textColor: .destructive, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            MTFakeGiftsStore.shared.remove(accountPeerId: accountPeerId, localId: localId)
            controller?.dismiss(animated: true)
        })))
        return localItems
    }

    let gift = menuContext.gift
    let fromPeerId = menuContext.nameHidden ? nil : menuContext.fromPeerId
    let nameHidden = menuContext.nameHidden
    let text = menuContext.text
    let entities = menuContext.entities
    let number = menuContext.number
    return [
        .action(ContextMenuActionItem(text: MTStrings.FakeGifts.Menu.add, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Gift"), color: theme.contextMenu.primaryColor)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            MTFakeGiftsSettings.isEnabled.set(true)
            MTFakeGiftsStore.shared.ensureAccount(context.account)
            let date = Int32(Date().timeIntervalSince1970)
            MTFakeGiftsStore.shared.add(accountPeerId: accountPeerId, gift: gift, fromPeer: fromPeerId == accountPeerId ? nil : fromPeerId, nameHidden: nameHidden, date: date, text: text, entities: entities, number: number, completion: { localId in
                guard let localId = localId else {
                    return
                }
                mtPEPresentToast(context: context, from: controller, text: MTStrings.FakeGifts.Toast.added, actionTitle: MTStrings.FakeGifts.Toast.edit, action: {
                    mtOpenFakeGiftEditor(context: context, localId: localId, from: controller)
                })
            })
        })),
        .action(ContextMenuActionItem(text: "Подарить визуально другому…", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Gift"), color: theme.contextMenu.primaryColor)
        }, action: { contextController, _ in
            contextController?.dismiss(completion: nil)
            mtGiveFakeGiftToPeer(context: context, gift: gift, text: text, entities: entities, number: number, from: controller)
        }))
    ]
}

/// Picks a person and shows a copy of the gift on their profile (only on this device), then opens the
/// editor so the sender and the caption can be changed.
private func mtGiveFakeGiftToPeer(context: AccountContext, gift: StarGift, text: String?, entities: [MessageTextEntity]?, number: Int32?, from controller: ViewController?) {
    let _ = entities
    let navigationController = (controller?.navigationController as? NavigationController) ?? mtProfileExportTopController(context: context)?.0
    controller?.dismiss(animated: true)
    let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasContactSelector: true, title: "Кому подарить (визуально)"))
    picker.peerSelected = { [weak picker, weak navigationController] peer, _ in
        picker?.dismiss()
        Queue.mainQueue().after(0.25) {
            let top = navigationController?.viewControllers.last as? ViewController
            mtPromptGiftComposerAndSend(
                context: context,
                gift: gift,
                targetPeerId: peer.id,
                number: number,
                initialText: text,
                from: top
            )
        }
    }
    Queue.mainQueue().after(0.35) {
        navigationController?.pushViewController(picker)
    }
}

/// Closes the gift screen (a sheet over the stack) and opens the editor on the account's stack.
private func mtOpenFakeGiftEditor(context: AccountContext, localId: Int64, from controller: ViewController?) {
    let navigationController = (controller?.navigationController as? NavigationController) ?? mtProfileExportTopController(context: context)?.0
    controller?.dismiss(animated: true)
    navigationController?.pushViewController(mtMakeFakeGiftEditor(context: context, localId: localId))
}
