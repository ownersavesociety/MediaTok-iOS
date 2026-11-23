import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import LocalizedPeerData
import ItemListUI
import PromptUI
import GiftStoreScreen
import GiftViewScreen
import GGCore
import GGSettingsUI

// More › Fake gifts: the switch, the account's list, "Delete all". One editor for a gift
// (sender — a chat, anonymous or none; caption; date; shown / pinned; delete), reached from the list
// and from the gift's own «…».

enum GGFakeGiftsMenu {
    static func register() {
        GGMenuRegistry.register(GGMenuRow(
            id: "fakeGifts.isEnabled",
            section: .main(of: .moreFakeGifts),
            order: 100,
            title: { GGStrings.FakeGifts.Menu.enable },
            subtitle: { GGStrings.FakeGifts.Menu.enableInfo },
            kind: .toggle(.global(GGFakeGiftsSettings.isEnabled)),
            searchKeywords: { [GGStrings.FakeGifts.Menu.keywords] }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "fakeGifts.list",
            section: .main(of: .moreFakeGifts),
            order: 200,
            title: { GGStrings.FakeGifts.Menu.list },
            subtitle: { GGStrings.FakeGifts.Menu.listInfo },
            icon: .bundle("Chat/Context Menu/Gift"),
            kind: .action({ context in
                context.push(ggMakeFakeGiftsListScreen(context: context.context))
            }),
            isVisible: { _ in GGFakeGiftsSettings.isEnabled.value },
            searchKeywords: { [GGStrings.FakeGifts.Menu.keywords] },
            label: { context in
                let count = GGFakeGiftsStore.shared.records(accountPeerId: context.context.account.peerId).count
                return count == 0 ? nil : "\(count)"
            }
        ))
    }
}

func ggFakeGiftTitle(_ gift: StarGift, number: Int32?) -> String {
    switch gift {
    case let .unique(uniqueGift):
        return "\(uniqueGift.title) #\(uniqueGift.number)"
    case let .generic(generic):
        let title = generic.title ?? GGStrings.FakeGifts.List.giftTitle
        if let number = number {
            return "\(title) #\(number)"
        }
        return title
    }
}

private let ggFakeGiftDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

/// Main thread only (the formatter is shared by the screens).
func ggFakeGiftDateString(_ date: Int32) -> String {
    assert(Thread.isMainThread)
    ggFakeGiftDateFormatter.locale = Locale(identifier: GGLocalization.shared.languageCode)
    return ggFakeGiftDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(date)))
}

func ggMakeFakeGiftsListScreen(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId
    weak var controllerRef: ItemListController?

    let model = combineLatest(queue: .mainQueue(), GGFakeGiftsStore.shared.recordsSignal(accountPeerId: accountPeerId), GGLocalization.shared.languageCodeSignal)
    |> map { records, _ -> GGPEScreenModel in
        var model = GGPEScreenModel(title: GGStrings.FakeGifts.List.title)
        model.sections.append([
            GGPERow(id: "openPortalsMarket", kind: .action(title: "🛍 Маркет и Конструктор NFT (Portals: Коллекции, Модели, Фоны)", destructive: false, enabled: true)),
            GGPERow(id: "addByLink", kind: .action(title: "🔗 Добавить NFT-подарок по ссылке (t.me/nft/...)", destructive: false, enabled: true)),
            GGPERow(id: "addGeneric", kind: .action(title: "🎁 Добавить обычный подарок (с любой подписью)", destructive: false, enabled: true))
        ])
        model.tap["openPortalsMarket"] = {
            ggPresentPortalsNftCatalog(context: context, from: controllerRef, targetPeerId: nil)
        }
        model.tap["addByLink"] = {
            ggPromptAddFakeUniqueGift(context: context, from: controllerRef)
        }
        model.tap["addGeneric"] = {
            ggPresentGenericGiftPicker(context: context, from: controllerRef, targetPeerId: nil)
        }
        var rows: [GGPERow] = [GGPERow(id: "header", kind: .header(GGStrings.FakeGifts.List.header))]
        if records.isEmpty {
            rows.append(GGPERow(id: "empty", kind: .info(GGStrings.FakeGifts.List.empty)))
        }
        for record in records {
            var label = ggFakeGiftDateString(record.date)
            if record.targetPeer != nil {
                label = "Другому · " + label
            }
            if record.pinnedToTop {
                label = GGStrings.FakeGifts.List.pinned + " · " + label
            } else if !record.savedToProfile {
                label = GGStrings.FakeGifts.List.hidden + " · " + label
            }
            let id = "gift\(record.localId)"
            rows.append(GGPERow(id: id, kind: .disclosure(title: ggFakeGiftTitle(record.gift, number: record.number), label: label, icon: nil, enabled: true)))
            let localId = record.localId
            model.tap[id] = {
                controllerRef?.push(ggMakeFakeGiftEditor(context: context, localId: localId))
            }
        }
        rows.append(GGPERow(id: "footer", kind: .footer(GGStrings.FakeGifts.List.footer)))
        model.sections.append(rows)
        if !records.isEmpty {
            model.sections.append([GGPERow(id: "deleteAll", kind: .action(title: GGStrings.FakeGifts.List.deleteAll, destructive: true, enabled: true))])
            model.tap["deleteAll"] = {
                ggPEConfirmDestructive(context: context, from: controllerRef, title: GGStrings.FakeGifts.List.deleteAllTitle, text: GGStrings.FakeGifts.List.deleteAllText, confirm: GGStrings.FakeGifts.List.deleteAllConfirm, action: {
                    GGFakeGiftsStore.shared.removeAll(accountPeerId: accountPeerId)
                })
            }
        }
        return model
    }
    let controller = ggPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

private func ggParseUniqueGiftSlug(_ raw: String) -> String? {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return nil
    }
    if let range = trimmed.range(of: "/nft/", options: .caseInsensitive) {
        trimmed = String(trimmed[range.upperBound...])
    } else if let range = trimmed.range(of: "nft/", options: .caseInsensitive) {
        trimmed = String(trimmed[range.upperBound...])
    }
    if let queryIdx = trimmed.firstIndex(where: { $0 == "?" || $0 == "#" || $0 == "/" }) {
        trimmed = String(trimmed[..<queryIdx])
    }
    trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 128 else {
        return nil
    }
    return trimmed
}

func ggPromptAddFakeUniqueGift(context: AccountContext, from controller: ViewController?, targetPeerId: PeerId? = nil) {
    controller?.present(promptController(
        context: context,
        text: targetPeerId == nil ? "Добавить NFT-подарок" : "Подарить NFT (визуально)",
        subtitle: "Вставьте ссылку вида t.me/nft/PlushPepe-1 или короткое имя подарка (slug):",
        value: "",
        placeholder: "t.me/nft/PlushPepe-1",
        characterLimit: 180,
        apply: { value in
            guard let raw = value, let slug = ggParseUniqueGiftSlug(raw) else {
                return
            }
            GGFakeGiftsSettings.isEnabled.set(true)
            GGFakeGiftsStore.shared.ensureAccount(context.account)
            let _ = (context.engine.payments.getUniqueStarGift(slug: slug)
            |> deliverOnMainQueue).start(next: { uniqueGift in
                let date = Int32(Date().timeIntervalSince1970)
                GGFakeGiftsStore.shared.add(
                    accountPeerId: context.account.peerId,
                    gift: .unique(uniqueGift),
                    fromPeer: targetPeerId == nil ? nil : context.account.peerId,
                    nameHidden: false,
                    date: date,
                    text: nil,
                    entities: nil,
                    number: uniqueGift.number,
                    targetPeer: targetPeerId,
                    completion: { localId in
                        guard let localId = localId else { return }
                        ggPEPresentToast(context: context, from: controller, text: targetPeerId == nil ? "NFT-подарок «\(uniqueGift.title) #\(uniqueGift.number)» добавлен в профиль" : "NFT-подарок «\(uniqueGift.title) #\(uniqueGift.number)» подарен (виден только у тебя)", actionTitle: GGStrings.FakeGifts.Toast.edit, action: {
                            controller?.push(ggMakeFakeGiftEditor(context: context, localId: localId))
                        })
                    }
                )
            }, error: { _ in
                ggPEPresentToast(context: context, from: controller, text: "Не удалось найти NFT-подарок «\(slug)». Проверьте ссылку t.me/nft/...")
            })
        }
    ), in: .window(.root))
}

/// Lists Telegram's regular (generic) gifts from the catalog so the user can add any of them locally
/// (to self or another peer) and immediately customize the sender and caption.
func ggPresentGenericGiftPicker(context: AccountContext, from controller: ViewController?, targetPeerId: PeerId?) {
    let _ = context.engine.payments.keepStarGiftsUpdated().start()
    weak var pickerRef: ItemListController?
    let navigationController = (controller?.navigationController as? NavigationController) ?? ggProfileExportTopController(context: context)?.0

    let model = combineLatest(queue: .mainQueue(), context.engine.payments.cachedStarGifts(), GGLocalization.shared.languageCodeSignal)
    |> map { catalog, _ -> GGPEScreenModel in
        var model = GGPEScreenModel(title: targetPeerId == nil ? "Выбрать обычный подарок" : "Подарить обычный подарок")
        var rows: [GGPERow] = [GGPERow(id: "header", kind: .header("Каталог обычных подарков"))]
        let genericGifts: [(StarGift, StarGift.Gift)] = (catalog ?? []).compactMap { gift in
            if case let .generic(generic) = gift {
                return (gift, generic)
            }
            return nil
        }
        if genericGifts.isEmpty {
            rows.append(GGPERow(id: "loading", kind: .info("Загружаем каталог подарков Telegram… Попробуйте открыть через пару секунд.")))
        } else {
            for (gift, generic) in genericGifts {
                let rowId = "generic.\(generic.id)"
                let baseTitle = (generic.title.flatMap { $0.isEmpty ? nil : $0 }) ?? "Подарок #\(generic.id)"
                let limitTag = generic.availability != nil ? " · Лимит" : ""
                let label = "\(generic.price) ⭐️\(limitTag)"
                rows.append(GGPERow(id: rowId, kind: .disclosure(title: baseTitle, label: label, icon: nil, enabled: true)))
                model.tap[rowId] = {
                    GGFakeGiftsSettings.isEnabled.set(true)
                    GGFakeGiftsStore.shared.ensureAccount(context.account)
                    let accountPeerId = context.account.peerId
                    let date = Int32(Date().timeIntervalSince1970)
                    GGFakeGiftsStore.shared.add(
                        accountPeerId: accountPeerId,
                        gift: gift,
                        fromPeer: targetPeerId == nil ? nil : accountPeerId,
                        nameHidden: false,
                        date: date,
                        text: nil,
                        entities: nil,
                        number: nil,
                        targetPeer: targetPeerId,
                        completion: { localId in
                            guard let localId else {
                                return
                            }
                            let editor = ggMakeFakeGiftEditor(context: context, localId: localId)
                            if let nav = pickerRef?.navigationController as? NavigationController {
                                nav.replaceTopController(editor, animated: true)
                            } else {
                                navigationController?.pushViewController(editor)
                            }
                        }
                    )
                }
            }
        }
        model.sections.append(rows)
        return model
    }

    let picker = ggPEMakeListController(context: context, model: model)
    pickerRef = picker
    if let controller {
        controller.push(picker)
    } else {
        navigationController?.pushViewController(picker)
    }
}

/// The editor works on a draft; "Done" writes it once.
func ggMakeFakeGiftEditor(context: AccountContext, localId: Int64) -> ViewController {
    let accountPeerId = context.account.peerId
    weak var controllerRef: ItemListController?

    guard let initial = GGFakeGiftsStore.shared.records(accountPeerId: accountPeerId).first(where: { $0.localId == localId }) else {
        return ggMakeFakeGiftsListScreen(context: context)
    }
    let draft = ValuePromise<GGFakeGiftRecord>(initial, ignoreRepeated: true)
    let draftValue = Atomic<GGFakeGiftRecord>(value: initial)
    let updateDraft: ((inout GGFakeGiftRecord) -> Void) -> Void = { transform in
        var value = draftValue.with { $0 }
        transform(&value)
        let _ = draftValue.swap(value)
        draft.set(value)
    }

    let sender: Signal<EnginePeer?, NoError> = draft.get()
    |> map { record -> EnginePeer.Id? in
        return record.fromPeer.map(PeerId.init(ggKey:))
    }
    |> distinctUntilChanged
    |> mapToSignal { peerId -> Signal<EnginePeer?, NoError> in
        guard let peerId = peerId else {
            return .single(nil)
        }
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    }

    let model = combineLatest(queue: .mainQueue(), draft.get(), sender, GGLocalization.shared.languageCodeSignal)
    |> map { record, senderPeer, _ -> GGPEScreenModel in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var model = GGPEScreenModel(title: ggFakeGiftTitle(record.gift, number: record.number))

        let senderLabel: String
        if record.nameHidden {
            senderLabel = GGStrings.FakeGifts.Editor.anonymous
        } else if let senderPeer = senderPeer {
            senderLabel = senderPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        } else {
            senderLabel = GGStrings.FakeGifts.Editor.noSender
        }
        model.sections.append([
            GGPERow(id: "senderHeader", kind: .header(GGStrings.FakeGifts.Editor.senderHeader)),
            GGPERow(id: "sender", kind: .peer(title: GGStrings.FakeGifts.Editor.sender, label: senderLabel, peer: record.nameHidden ? nil : senderPeer))
        ])
        model.tap["sender"] = {
            ggPEPresentActionSheet(context: context, from: controllerRef, buttons: [
                (title: GGStrings.FakeGifts.Editor.chooseSender, isDestructive: false, action: {
                    let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasContactSelector: true, title: GGStrings.FakeGifts.Editor.chooseSender))
                    picker.peerSelected = { [weak picker] peer, _ in
                        updateDraft { record in
                            record.fromPeer = peer.id.ggKey
                            record.nameHidden = false
                        }
                        picker?.dismiss()
                    }
                    controllerRef?.push(picker)
                }),
                (title: GGStrings.FakeGifts.Editor.anonymous, isDestructive: false, action: {
                    updateDraft { record in
                        record.nameHidden = true
                    }
                }),
                (title: GGStrings.FakeGifts.Editor.noSender, isDestructive: false, action: {
                    updateDraft { record in
                        record.fromPeer = nil
                        record.nameHidden = false
                    }
                })
            ])
        }

        model.sections.append([
            GGPERow(id: "captionHeader", kind: .header(GGStrings.FakeGifts.Editor.captionHeader)),
            GGPERow(id: "caption", kind: .multilineInput(text: record.text ?? "", placeholder: GGStrings.FakeGifts.Editor.captionPlaceholder))
        ])
        model.text["caption"] = { text in
            updateDraft { record in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if record.text != text {
                    // A typed caption has no entities of its own.
                    record.entities = nil
                }
                record.text = trimmed.isEmpty ? nil : text
            }
        }

        model.sections.append([
            GGPERow(id: "dateHeader", kind: .header(GGStrings.FakeGifts.Editor.dateHeader)),
            GGPERow(id: "date", kind: .disclosure(title: GGStrings.FakeGifts.Editor.date, label: ggFakeGiftDateString(record.date), icon: nil, enabled: true))
        ])
        model.tap["date"] = {
            let now = Int32(Date().timeIntervalSince1970)
            let day: Int32 = 24 * 60 * 60
            let presets: [(String, Int32)] = [
                (GGStrings.FakeGifts.Editor.dateNow, now),
                (GGStrings.FakeGifts.Editor.dateYesterday, now - day),
                (GGStrings.FakeGifts.Editor.dateWeek, now - 7 * day),
                (GGStrings.FakeGifts.Editor.dateMonth, now - 30 * day),
                (GGStrings.FakeGifts.Editor.dateYear, now - 365 * day)
            ]
            ggPEPresentActionSheet(context: context, from: controllerRef, buttons: presets.map { preset in
                return (title: preset.0, isDestructive: false, action: {
                    updateDraft { record in
                        record.date = preset.1
                    }
                })
            })
        }

        model.sections.append([
            GGPERow(id: "shown", kind: .toggle(title: GGStrings.FakeGifts.Editor.shown, value: record.savedToProfile, enabled: true)),
            GGPERow(id: "pinned", kind: .toggle(title: GGStrings.FakeGifts.Editor.pinned, value: record.pinnedToTop, enabled: true)),
            GGPERow(id: "flagsFooter", kind: .footer(GGStrings.FakeGifts.Editor.flagsFooter))
        ])
        model.toggle["shown"] = { value in
            updateDraft { record in
                record.savedToProfile = value
                if !value {
                    record.pinnedToTop = false
                }
            }
        }
        model.toggle["pinned"] = { value in
            updateDraft { record in
                record.pinnedToTop = value
                if value {
                    record.savedToProfile = true
                }
            }
        }

        model.sections.append([GGPERow(id: "delete", kind: .action(title: GGStrings.FakeGifts.Editor.delete, destructive: true, enabled: true))])
        model.tap["delete"] = {
            ggPEConfirmDestructive(context: context, from: controllerRef, title: GGStrings.FakeGifts.Editor.deleteTitle, text: GGStrings.FakeGifts.Editor.deleteText, confirm: GGStrings.FakeGifts.Editor.delete, action: {
                GGFakeGiftsStore.shared.remove(accountPeerId: accountPeerId, localId: localId)
                controllerRef?.dismiss()
            })
        }

        model.rightButton = (title: presentationData.strings.Common_Done, enabled: true, action: {
            let value = draftValue.with { $0 }
            GGFakeGiftsStore.shared.update(accountPeerId: accountPeerId, localId: localId, { record in
                record = value
            })
            controllerRef?.dismiss()
        })
        return model
    }
    let controller = ggPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

// MARK: - Portals Visual NFT Marketplace & Collection Constructor

private func ggFormatAttributeRarity(_ rarity: StarGift.UniqueGift.Attribute.Rarity) -> String {
    switch rarity {
    case let .permille(permille):
        let percent = Double(permille) / 10.0
        return String(format: "%.1f%%", percent)
    case .uncommon:
        return "Uncommon"
    case .rare:
        return "Rare"
    case .epic:
        return "Epic"
    case .legendary:
        return "Legendary"
    }
}

func ggPresentPortalsNftCatalog(context: AccountContext, from controller: ViewController?, targetPeerId: PeerId?) {
    let _ = context.engine.payments.keepStarGiftsUpdated().start()
    weak var pickerRef: ItemListController?
    let navigationController = (controller?.navigationController as? NavigationController) ?? ggProfileExportTopController(context: context)?.0
    let openConstructorByDefault = ValuePromise<Bool>(false, ignoreRepeated: true)

    let model = combineLatest(
        queue: .mainQueue(),
        context.engine.payments.cachedStarGifts(),
        openConstructorByDefault.get(),
        GGLocalization.shared.languageCodeSignal
    )
    |> map { catalog, constructorMode, _ -> GGPEScreenModel in
        var model = GGPEScreenModel(title: targetPeerId == nil ? "Маркет NFT (Portals)" : "Подарить NFT (Portals)")

        model.sections.append([
            GGPERow(id: "modeHeader", kind: .header("Режим выбора NFT")),
            GGPERow(id: "constructorToggle", kind: .toggle(title: "🎨 Режим Конструктора (свой Фон + Модель + #Номер)", value: constructorMode, enabled: true)),
            GGPERow(id: "addByLinkRow", kind: .action(title: "🔗 Ввести ссылку вручную (t.me/nft/...)", destructive: false, enabled: true)),
            GGPERow(id: "modeFooter", kind: .footer(constructorMode ? "Нажмите на любую коллекцию ниже, чтобы собрать NFT с любой Моделью, Фоном, Узором и любым #Номером." : "Нажмите на любую коллекцию ниже, чтобы открыть 3D-сетку маркета Portals с фильтрами по Модели, Фону, Узору и сортировкой по цене/номеру."))
        ])
        model.toggle["constructorToggle"] = { value in
            openConstructorByDefault.set(value)
        }
        model.tap["addByLinkRow"] = {
            ggPromptAddFakeUniqueGift(context: context, from: pickerRef, targetPeerId: targetPeerId)
        }

        let allGenerics: [StarGift.Gift] = (catalog ?? []).compactMap { gift in
            if case let .generic(generic) = gift {
                return generic
            }
            return nil
        }
        let nftCollections = allGenerics.filter { generic in
            if let resale = generic.availability?.resale, resale > 0 {
                return true
            }
            if generic.upgradeStars != nil || generic.availability != nil {
                return true
            }
            return false
        }.sorted { lhs, rhs in
            let lhsResale = lhs.availability?.resale ?? 0
            let rhsResale = rhs.availability?.resale ?? 0
            if lhsResale != rhsResale {
                return lhsResale > rhsResale
            }
            return (lhs.title ?? "") < (rhs.title ?? "")
        }

        var rows: [GGPERow] = [GGPERow(id: "collectionsHeader", kind: .header("Коллекции NFT (\(nftCollections.count))"))]
        if nftCollections.isEmpty {
            rows.append(GGPERow(id: "loading", kind: .info("Загружаем каталог коллекций NFT из Telegram… Подождите пару секунд.")))
        } else {
            for generic in nftCollections {
                let rowId = "nftcol.\(generic.id)"
                let title = (generic.title.flatMap { $0.isEmpty ? nil : $0 }) ?? "Коллекция #\(generic.id)"
                let resaleCount = generic.availability?.resale ?? 0
                let label: String
                if constructorMode {
                    label = "🎨 Конструктор"
                } else if resaleCount > 0 {
                    label = "\(resaleCount) на маркете"
                } else {
                    label = "Конструктор"
                }
                rows.append(GGPERow(id: rowId, kind: .disclosure(title: title, label: label, icon: nil, enabled: true)))
                model.tap[rowId] = {
                    if constructorMode || resaleCount == 0 {
                        let constructorScreen = ggMakeNftCollectionConstructorScreen(context: context, generic: generic, targetPeerId: targetPeerId)
                        pickerRef?.push(constructorScreen)
                    } else {
                        ggOpenPortalsGiftStore(context: context, generic: generic, from: pickerRef, targetPeerId: targetPeerId)
                    }
                }
            }
        }
        model.sections.append(rows)
        return model
    }

    let picker = ggPEMakeListController(context: context, model: model)
    pickerRef = picker
    if let controller {
        controller.push(picker)
    } else {
        navigationController?.pushViewController(picker)
    }
}

func ggOpenPortalsGiftStore(context: AccountContext, generic: StarGift.Gift, from controller: ViewController?, targetPeerId: PeerId?) {
    let effectivePeerId = targetPeerId ?? context.account.peerId
    weak var storeRef: GiftStoreScreen?
    let storeScreen = GiftStoreScreen(
        context: context,
        peerId: effectivePeerId,
        gift: generic,
        completion: { uniqueGift in
            ggPresentUniqueGiftActionSheet(context: context, uniqueGift: uniqueGift, generic: generic, from: storeRef, targetPeerId: targetPeerId)
        }
    )
    storeRef = storeScreen
    storeScreen.parentController = { [weak controller] in
        return controller
    }
    if let controller {
        controller.push(storeScreen)
    } else {
        let navigationController = ggProfileExportTopController(context: context)?.0
        navigationController?.pushViewController(storeScreen)
    }
}

private func ggSaveChosenUniqueGift(context: AccountContext, uniqueGift: StarGift.UniqueGift, targetPeerId: PeerId?, from controller: ViewController?) {
    GGFakeGiftsSettings.isEnabled.set(true)
    GGFakeGiftsStore.shared.ensureAccount(context.account)
    let accountPeerId = context.account.peerId
    let date = Int32(Date().timeIntervalSince1970)
    GGFakeGiftsStore.shared.add(
        accountPeerId: accountPeerId,
        gift: .unique(uniqueGift),
        fromPeer: targetPeerId == nil ? nil : accountPeerId,
        nameHidden: false,
        date: date,
        text: nil,
        entities: nil,
        number: uniqueGift.number,
        targetPeer: targetPeerId,
        completion: { localId in
            guard let localId else {
                return
            }
            ggPEPresentToast(
                context: context,
                from: controller,
                text: targetPeerId == nil
                    ? "NFT «\(uniqueGift.title) #\(uniqueGift.number)» добавлен в ваш профиль (и синхронизирован)"
                    : "NFT «\(uniqueGift.title) #\(uniqueGift.number)» подарен пользователю (и синхронизирован)",
                actionTitle: GGStrings.FakeGifts.Toast.edit,
                action: {
                    controller?.push(ggMakeFakeGiftEditor(context: context, localId: localId))
                }
            )
        }
    )
}

private func ggPresentUniqueGiftActionSheet(context: AccountContext, uniqueGift: StarGift.UniqueGift, generic: StarGift.Gift, from controller: ViewController?, targetPeerId: PeerId?) {
    var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
    if let targetPeerId {
        buttons.append((
            title: "🎁 Подарить «\(uniqueGift.title) #\(uniqueGift.number)» этому пользователю",
            isDestructive: false,
            action: {
                ggSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: targetPeerId, from: controller)
            }
        ))
    }
    buttons.append((
        title: "✨ Добавить «\(uniqueGift.title) #\(uniqueGift.number)» себе в профиль",
        isDestructive: false,
        action: {
            ggSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: nil, from: controller)
        }
    ))
    buttons.append((
        title: "👤 Выбрать кому подарить «\(uniqueGift.title) #\(uniqueGift.number)»…",
        isDestructive: false,
        action: { [weak controller] in
            let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasContactSelector: true, title: "Кому подарить NFT"))
            picker.peerSelected = { [weak picker, weak controller] peer, _ in
                picker?.dismiss()
                ggSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: peer.id, from: controller)
            }
            controller?.push(picker)
        }
    ))
    buttons.append((
        title: "🎨 Открыть Конструктор коллекции «\(uniqueGift.title)»",
        isDestructive: false,
        action: {
            controller?.push(ggMakeNftCollectionConstructorScreen(context: context, generic: generic, targetPeerId: targetPeerId))
        }
    ))
    buttons.append((
        title: "👁 Открыть 3D-просмотр NFT",
        isDestructive: false,
        action: {
            let viewScreen = GiftViewScreen(
                context: context,
                subject: .uniqueGift(uniqueGift, targetPeerId ?? context.account.peerId)
            )
            controller?.push(viewScreen)
        }
    ))
    ggPEPresentActionSheet(context: context, from: controller, buttons: buttons)
}

private struct GGNftConstructorDraft: Equatable {
    var modelIndex: Int = 0
    var backdropIndex: Int = 0
    var patternIndex: Int = 0
    var number: Int32 = 1
}

func ggMakeNftCollectionConstructorScreen(context: AccountContext, generic: StarGift.Gift, targetPeerId: PeerId?) -> ViewController {
    weak var controllerRef: ItemListController?
    let collectionTitle = (generic.title.flatMap { $0.isEmpty ? nil : $0 }) ?? "NFT #\(generic.id)"

    let draftPromise = ValuePromise<GGNftConstructorDraft>(GGNftConstructorDraft(), ignoreRepeated: true)
    let draftAtomic = Atomic<GGNftConstructorDraft>(value: GGNftConstructorDraft())
    let updateDraft: ((inout GGNftConstructorDraft) -> Void) -> Void = { transform in
        var value = draftAtomic.with { $0 }
        transform(&value)
        let _ = draftAtomic.swap(value)
        draftPromise.set(value)
    }

    let attributesSignal: Signal<[StarGift.UniqueGift.Attribute]?, NoError> = context.engine.payments.getStarGiftUpgradeAttributes(giftId: generic.id)
    |> mapToSignal { attrs -> Signal<[StarGift.UniqueGift.Attribute]?, NoError> in
        if let attrs, !attrs.isEmpty {
            return .single(attrs)
        }
        return context.engine.payments.starGiftUpgradePreview(giftId: generic.id)
        |> map { preview in
            return preview?.attributes
        }
    }

    let model = combineLatest(
        queue: .mainQueue(),
        attributesSignal,
        draftPromise.get()
    )
    |> map { attributes, draft -> GGPEScreenModel in
        var screen = GGPEScreenModel(title: "🎨 \(collectionTitle)")

        let allAttributes = attributes ?? []
        var models: [(String, TelegramMediaFile, StarGift.UniqueGift.Attribute.Rarity, Bool, StarGift.UniqueGift.Attribute)] = []
        var backdrops: [(String, Int32, Int32, Int32, Int32, Int32, StarGift.UniqueGift.Attribute.Rarity, StarGift.UniqueGift.Attribute)] = []
        var patterns: [(String, TelegramMediaFile, StarGift.UniqueGift.Attribute.Rarity, StarGift.UniqueGift.Attribute)] = []

        for attr in allAttributes {
            switch attr {
            case let .model(name, file, rarity, crafted):
                models.append((name, file, rarity, crafted, attr))
            case let .backdrop(name, id, innerColor, outerColor, patternColor, textColor, rarity):
                backdrops.append((name, id, innerColor, outerColor, patternColor, textColor, rarity, attr))
            case let .pattern(name, file, rarity):
                patterns.append((name, file, rarity, attr))
            case .originalInfo:
                break
            }
        }

        if allAttributes.isEmpty {
            screen.sections.append([
                GGPERow(id: "loading", kind: .info("Загружаем все 3D-модели, фоны и узоры коллекции «\(collectionTitle)» с серверов Telegram…"))
            ])
            return screen
        }

        let safeModelIdx = models.isEmpty ? 0 : min(max(0, draft.modelIndex), models.count - 1)
        let safeBackdropIdx = backdrops.isEmpty ? 0 : min(max(0, draft.backdropIndex), backdrops.count - 1)
        let safePatternIdx = patterns.isEmpty ? 0 : min(max(0, draft.patternIndex), patterns.count - 1)

        let selectedModelLabel = models.isEmpty ? "—" : "\(models[safeModelIdx].0) (\(ggFormatAttributeRarity(models[safeModelIdx].2)))"
        let selectedBackdropLabel = backdrops.isEmpty ? "—" : "\(backdrops[safeBackdropIdx].0) (\(ggFormatAttributeRarity(backdrops[safeBackdropIdx].6)))"
        let selectedPatternLabel = patterns.isEmpty ? "—" : "\(patterns[safePatternIdx].0) (\(ggFormatAttributeRarity(patterns[safePatternIdx].2)))"

        screen.sections.append([
            GGPERow(id: "attrHeader", kind: .header("Параметры NFT (\(collectionTitle) #\(draft.number))")),
            GGPERow(id: "pickModel", kind: .disclosure(title: "Модель (\(models.count))", label: selectedModelLabel, icon: nil, enabled: !models.isEmpty)),
            GGPERow(id: "pickBackdrop", kind: .disclosure(title: "Фон / Backdrop (\(backdrops.count))", label: selectedBackdropLabel, icon: nil, enabled: !backdrops.isEmpty)),
            GGPERow(id: "pickPattern", kind: .disclosure(title: "Узор / Symbol (\(patterns.count))", label: selectedPatternLabel, icon: nil, enabled: !patterns.isEmpty)),
            GGPERow(id: "pickNumber", kind: .disclosure(title: "Номер NFT", label: "#\(draft.number)", icon: nil, enabled: true)),
            GGPERow(id: "randomize", kind: .action(title: "🎲 Случайная комбинация (Модель + Фон + Узор)", destructive: false, enabled: true))
        ])

        screen.tap["pickModel"] = {
            let buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = models.enumerated().map { idx, item in
                let prefix = idx == safeModelIdx ? "✓ " : ""
                return (
                    title: "\(prefix)\(item.0) · \(ggFormatAttributeRarity(item.2))",
                    isDestructive: false,
                    action: {
                        updateDraft { $0.modelIndex = idx }
                    }
                )
            }
            ggPEPresentActionSheet(context: context, from: controllerRef, buttons: buttons)
        }

        screen.tap["pickBackdrop"] = {
            let buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = backdrops.enumerated().map { idx, item in
                let prefix = idx == safeBackdropIdx ? "✓ " : ""
                return (
                    title: "\(prefix)\(item.0) · \(ggFormatAttributeRarity(item.6))",
                    isDestructive: false,
                    action: {
                        updateDraft { $0.backdropIndex = idx }
                    }
                )
            }
            ggPEPresentActionSheet(context: context, from: controllerRef, buttons: buttons)
        }

        screen.tap["pickPattern"] = {
            let buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = patterns.enumerated().map { idx, item in
                let prefix = idx == safePatternIdx ? "✓ " : ""
                return (
                    title: "\(prefix)\(item.0) · \(ggFormatAttributeRarity(item.2))",
                    isDestructive: false,
                    action: {
                        updateDraft { $0.patternIndex = idx }
                    }
                )
            }
            ggPEPresentActionSheet(context: context, from: controllerRef, buttons: buttons)
        }

        screen.tap["pickNumber"] = {
            let presets: [Int32] = [1, 7, 13, 77, 100, 666, 777, 888, 999, 1337, 7777]
            var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = [
                (title: "⌨️ Ввести любой свой номер (#)...", isDestructive: false, action: {
                    controllerRef?.present(promptController(
                        context: context,
                        text: "Номер NFT",
                        subtitle: "Введите любой номер для «\(collectionTitle)» (например 1 или 777):",
                        value: "\(draft.number)",
                        placeholder: "1",
                        characterLimit: 9,
                        apply: { value in
                            if let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: ""),
                               let parsed = Int32(raw), parsed > 0 {
                                updateDraft { $0.number = parsed }
                            }
                        }
                    ), in: .window(.root))
                })
            ]
            for num in presets {
                buttons.append((
                    title: draft.number == num ? "✓ #\(num)" : "#\(num)",
                    isDestructive: false,
                    action: {
                        updateDraft { $0.number = num }
                    }
                ))
            }
            ggPEPresentActionSheet(context: context, from: controllerRef, buttons: buttons)
        }

        screen.tap["randomize"] = {
            updateDraft { d in
                if !models.isEmpty { d.modelIndex = Int.random(in: 0 ..< models.count) }
                if !backdrops.isEmpty { d.backdropIndex = Int.random(in: 0 ..< backdrops.count) }
                if !patterns.isEmpty { d.patternIndex = Int.random(in: 0 ..< patterns.count) }
            }
        }

        let buildUniqueGift: () -> StarGift.UniqueGift? = {
            var chosenAttrs: [StarGift.UniqueGift.Attribute] = []
            if !models.isEmpty {
                chosenAttrs.append(models[safeModelIdx].4)
            }
            if !patterns.isEmpty {
                chosenAttrs.append(patterns[safePatternIdx].3)
            }
            if !backdrops.isEmpty {
                chosenAttrs.append(backdrops[safeBackdropIdx].7)
            }
            guard !chosenAttrs.isEmpty else {
                return nil
            }
            let syntheticSlug = "mtcustom_\(generic.id)_\(draft.number)"
            let syntheticId = Int64.random(in: 1_000_000_000 ... 9_000_000_000)
            let totalIssued = generic.availability?.total ?? 10000
            return StarGift.UniqueGift(
                id: syntheticId,
                giftId: generic.id,
                title: collectionTitle,
                number: draft.number,
                slug: syntheticSlug,
                owner: .peerId(targetPeerId ?? context.account.peerId),
                attributes: chosenAttrs,
                availability: StarGift.UniqueGift.Availability(issued: max(draft.number, 1), total: max(totalIssued, draft.number)),
                giftAddress: nil,
                resellAmounts: nil,
                resellForTonOnly: false,
                releasedBy: generic.releasedBy,
                valueAmount: nil,
                valueCurrency: nil,
                valueUsdAmount: nil,
                flags: [],
                themePeerId: nil,
                peerColor: nil,
                hostPeerId: nil,
                minOfferStars: nil,
                craftChancePermille: nil
            )
        }

        var actionRows: [GGPERow] = []
        if let targetPeerId {
            let _ = targetPeerId
            actionRows.append(GGPERow(id: "giftToTarget", kind: .action(title: "🎁 Создать и подарить этому пользователю", destructive: false, enabled: true)))
        }
        actionRows.append(GGPERow(id: "addToSelf", kind: .action(title: "✨ Создать и добавить себе в профиль", destructive: false, enabled: true)))
        actionRows.append(GGPERow(id: "giftToOther", kind: .action(title: "👤 Создать и выбрать кому подарить…", destructive: false, enabled: true)))
        actionRows.append(GGPERow(id: "preview3D", kind: .action(title: "👁 Предпросмотр 3D-модели NFT", destructive: false, enabled: true)))
        screen.sections.append(actionRows)

        screen.tap["giftToTarget"] = {
            guard let targetPeerId, let uniqueGift = buildUniqueGift() else { return }
            ggSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: targetPeerId, from: controllerRef)
        }
        screen.tap["addToSelf"] = {
            guard let uniqueGift = buildUniqueGift() else { return }
            ggSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: nil, from: controllerRef)
        }
        screen.tap["giftToOther"] = {
            guard let uniqueGift = buildUniqueGift() else { return }
            let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasContactSelector: true, title: "Кому подарить NFT"))
            picker.peerSelected = { [weak picker] peer, _ in
                picker?.dismiss()
                ggSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: peer.id, from: controllerRef)
            }
            controllerRef?.push(picker)
        }
        screen.tap["preview3D"] = {
            guard let uniqueGift = buildUniqueGift() else { return }
            let viewScreen = GiftViewScreen(
                context: context,
                subject: .uniqueGift(uniqueGift, targetPeerId ?? context.account.peerId)
            )
            controllerRef?.push(viewScreen)
        }

        return screen
    }

    let controller = ggPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}
