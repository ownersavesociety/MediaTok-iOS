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
import ConfettiEffect
import MTCore
import MTSettingsUI

// More › Fake gifts: the switch, the account's list, "Delete all". One editor for a gift
// (sender — a chat, anonymous or none; caption; date; shown / pinned; delete), reached from the list
// and from the gift's own «…».

enum MTFakeGiftsMenu {
    static func register() {
        MTMenuRegistry.register(MTMenuRow(
            id: "fakeGifts.isEnabled",
            section: .main(of: .moreFakeGifts),
            order: 100,
            title: { MTStrings.FakeGifts.Menu.enable },
            subtitle: { MTStrings.FakeGifts.Menu.enableInfo },
            kind: .toggle(.global(MTFakeGiftsSettings.isEnabled)),
            searchKeywords: { [MTStrings.FakeGifts.Menu.keywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "fakeGifts.globalSync",
            section: .main(of: .moreFakeGifts),
            order: 150,
            title: { "Глобальная синхронизация подарков" },
            subtitle: { "Публиковать и видеть фейковые подарки других пользователей MediaTok через ntfy.sh" },
            kind: .toggle(.global(MTFakeGiftsSettings.globalSyncEnabled)),
            isVisible: { _ in MTFakeGiftsSettings.isEnabled.value },
            searchKeywords: { [MTStrings.FakeGifts.Menu.keywords, "синхронизация", "ntfy"] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "fakeGifts.list",
            section: .main(of: .moreFakeGifts),
            order: 200,
            title: { MTStrings.FakeGifts.Menu.list },
            subtitle: { MTStrings.FakeGifts.Menu.listInfo },
            icon: .bundle("Chat/Context Menu/Gift"),
            kind: .action({ context in
                context.push(mtMakeFakeGiftsListScreen(context: context.context))
            }),
            isVisible: { _ in MTFakeGiftsSettings.isEnabled.value },
            searchKeywords: { [MTStrings.FakeGifts.Menu.keywords] },
            label: { context in
                let count = MTFakeGiftsStore.shared.records(accountPeerId: context.context.account.peerId).count
                return count == 0 ? nil : "\(count)"
            }
        ))
    }
}

func mtFakeGiftTitle(_ gift: StarGift, number: Int32?) -> String {
    switch gift {
    case let .unique(uniqueGift):
        return "\(uniqueGift.title) #\(uniqueGift.number)"
    case let .generic(generic):
        let title = generic.title ?? MTStrings.FakeGifts.List.giftTitle
        if let number = number {
            return "\(title) #\(number)"
        }
        return title
    }
}

private let mtFakeGiftDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

/// Main thread only (the formatter is shared by the screens).
func mtFakeGiftDateString(_ date: Int32) -> String {
    assert(Thread.isMainThread)
    mtFakeGiftDateFormatter.locale = Locale(identifier: MTLocalization.shared.languageCode)
    return mtFakeGiftDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(date)))
}

func mtMakeFakeGiftsListScreen(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId
    weak var controllerRef: ItemListController?

    let model = combineLatest(
        queue: .mainQueue(),
        MTFakeGiftsStore.shared.recordsSignal(accountPeerId: accountPeerId),
        MTVisualProfileStore.shared.revisionSignal,
        MTLocalization.shared.languageCodeSignal
    )
    |> map { records, _, _ -> MTPEScreenModel in
        var model = MTPEScreenModel(title: MTStrings.FakeGifts.List.title)
        var topRows: [MTPERow] = [
            MTPERow(id: "openPortalsMarket", kind: .action(title: "Маркеты NFT и Конструктор (Portals, MRKT, Tonnel)", destructive: false, enabled: true)),
            MTPERow(id: "calcCollectionValue", kind: .action(title: "Оценить коллекцию (CryptoBot: RUB / KZT / UAH / TON / USD)", destructive: false, enabled: true)),
            MTPERow(id: "addByLink", kind: .action(title: "Добавить NFT-подарок по ссылке (t.me/nft/...)", destructive: false, enabled: true)),
            MTPERow(id: "addGeneric", kind: .action(title: "Добавить обычный подарок (с любой подписью)", destructive: false, enabled: true))
        ]
        if let worn = MTVisualProfileStore.shared.wornStarGift(for: accountPeerId.mtKey) {
            topRows.append(MTPERow(id: "unwearNickGift", kind: .action(title: "Снять подарок из статуса ника («\(worn.title)»)", destructive: true, enabled: true)))
            model.tap["unwearNickGift"] = {
                MTVisualProfileStore.shared.setWornStarGift(nil, for: accountPeerId.mtKey)
                mtPEPresentToast(context: context, from: controllerRef, text: "Подарок снят из статуса ника")
            }
        }
        model.sections.append(topRows)
        model.tap["openPortalsMarket"] = {
            mtPresentPortalsNftCatalog(context: context, from: controllerRef, targetPeerId: nil)
        }
        model.tap["calcCollectionValue"] = {
            mtPresentNftCollectionValueCalculator(context: context, records: records, from: controllerRef)
        }
        model.tap["addByLink"] = {
            mtPromptAddFakeUniqueGift(context: context, from: controllerRef)
        }
        model.tap["addGeneric"] = {
            mtPresentGenericGiftPicker(context: context, from: controllerRef, targetPeerId: nil)
        }
        var rows: [MTPERow] = [MTPERow(id: "header", kind: .header(MTStrings.FakeGifts.List.header))]
        if records.isEmpty {
            rows.append(MTPERow(id: "empty", kind: .info(MTStrings.FakeGifts.List.empty)))
        }
        for record in records {
            var label = mtFakeGiftDateString(record.date)
            if record.targetPeer != nil {
                label = "Другому · " + label
            }
            if record.pinnedToTop {
                label = MTStrings.FakeGifts.List.pinned + " · " + label
            } else if !record.savedToProfile {
                label = MTStrings.FakeGifts.List.hidden + " · " + label
            }
            let id = "gift\(record.localId)"
            rows.append(MTPERow(id: id, kind: .disclosure(title: mtFakeGiftTitle(record.gift, number: record.number), label: label, icon: nil, enabled: true)))
            let localId = record.localId
            model.tap[id] = {
                controllerRef?.push(mtMakeFakeGiftEditor(context: context, localId: localId))
            }
        }
        rows.append(MTPERow(id: "footer", kind: .footer(MTStrings.FakeGifts.List.footer)))
        model.sections.append(rows)
        if !records.isEmpty {
            model.sections.append([MTPERow(id: "deleteAll", kind: .action(title: MTStrings.FakeGifts.List.deleteAll, destructive: true, enabled: true))])
            model.tap["deleteAll"] = {
                mtPEConfirmDestructive(context: context, from: controllerRef, title: MTStrings.FakeGifts.List.deleteAllTitle, text: MTStrings.FakeGifts.List.deleteAllText, confirm: MTStrings.FakeGifts.List.deleteAllConfirm, action: {
                    MTFakeGiftsStore.shared.removeAll(accountPeerId: accountPeerId)
                })
            }
        }
        return model
    }
    let controller = mtPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

private func mtParseUniqueGiftSlug(_ raw: String) -> String? {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return nil
    }
    if let range = trimmed.range(of: "/nft/", options: .caseInsensitive) {
        trimmed = String(trimmed[range.upperBound...])
    } else if let range = trimmed.range(of: "nft/", options: .caseInsensitive) {
        trimmed = String(trimmed[range.upperBound...])
    } else if let range = trimmed.range(of: "fragment.com/gift/", options: .caseInsensitive) {
        trimmed = String(trimmed[range.upperBound...])
    } else if let range = trimmed.range(of: "startapp=gift_", options: .caseInsensitive) {
        trimmed = String(trimmed[range.upperBound...])
    }
    if let queryIdx = trimmed.firstIndex(where: { $0 == "?" || $0 == "/" }) {
        trimmed = String(trimmed[..<queryIdx])
    }
    // Support human input like "Plush Pepe #1" or "PlushPepe #1" -> "PlushPepe-1"
    if trimmed.contains("#") {
        let parts = trimmed.split(separator: "#", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count == 2, Int32(parts[1]) != nil {
            let cleanName = parts[0].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            if !cleanName.isEmpty {
                trimmed = "\(cleanName)-\(parts[1])"
            }
        }
    }
    if let hashIdx = trimmed.firstIndex(of: "#") {
        trimmed = String(trimmed[..<hashIdx])
    }
    trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 128 else {
        return nil
    }
    return trimmed
}

func mtPromptAddFakeUniqueGift(context: AccountContext, from controller: ViewController?, targetPeerId: PeerId? = nil) {
    controller?.present(promptController(
        context: context,
        text: targetPeerId == nil ? "Добавить NFT-подарок" : "Подарить NFT (визуально)",
        subtitle: "Вставьте ссылку вида t.me/nft/PlushPepe-1 или короткое имя подарка (slug):",
        value: "",
        placeholder: "t.me/nft/PlushPepe-1",
        characterLimit: 180,
        apply: { value in
            guard let raw = value, let slug = mtParseUniqueGiftSlug(raw) else {
                return
            }
            MTFakeGiftsSettings.isEnabled.set(true)
            MTFakeGiftsStore.shared.ensureAccount(context.account)
            let _ = (context.engine.payments.getUniqueStarGift(slug: slug)
            |> deliverOnMainQueue).start(next: { uniqueGift in
                let date = Int32(Date().timeIntervalSince1970)
                MTFakeGiftsStore.shared.add(
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
                        if let targetPeerId {
                            mtDeliverVisualGiftToChat(
                                context: context,
                                gift: .unique(uniqueGift),
                                targetPeerId: targetPeerId,
                                localId: localId,
                                date: date,
                                from: controller
                            )
                        } else {
                            mtPresentGiftConfetti(context: context, from: controller)
                            mtPEPresentToast(context: context, from: controller, text: "NFT-подарок «\(uniqueGift.title) #\(uniqueGift.number)» добавлен в профиль", actionTitle: MTStrings.FakeGifts.Toast.edit, action: {
                                controller?.push(mtMakeFakeGiftEditor(context: context, localId: localId))
                            })
                        }
                    }
                )
            }, error: { _ in
                mtPEPresentToast(context: context, from: controller, text: "Не удалось найти NFT-подарок «\(slug)». Проверьте ссылку t.me/nft/...")
            })
        }
    ), in: .window(.root))
}

/// Lists Telegram's regular (generic) gifts from the catalog so the user can add any of them locally
/// (to self or another peer) and immediately customize the sender and caption.
func mtPresentGenericGiftPicker(context: AccountContext, from controller: ViewController?, targetPeerId: PeerId?) {
    let _ = context.engine.payments.keepStarGiftsUpdated().start()
    weak var pickerRef: ItemListController?
    let navigationController = (controller?.navigationController as? NavigationController) ?? mtProfileExportTopController(context: context)?.0

    let model = combineLatest(queue: .mainQueue(), context.engine.payments.cachedStarGifts(), MTLocalization.shared.languageCodeSignal)
    |> map { catalog, _ -> MTPEScreenModel in
        var model = MTPEScreenModel(title: targetPeerId == nil ? "Выбрать обычный подарок" : "Подарить обычный подарок")
        var rows: [MTPERow] = [MTPERow(id: "header", kind: .header("Каталог обычных подарков"))]
        let genericGifts: [(StarGift, StarGift.Gift)] = (catalog ?? []).compactMap { gift in
            if case let .generic(generic) = gift {
                return (gift, generic)
            }
            return nil
        }
        if genericGifts.isEmpty {
            rows.append(MTPERow(id: "loading", kind: .info("Загружаем каталог подарков Telegram… Попробуйте открыть через пару секунд.")))
        } else {
            for (gift, generic) in genericGifts {
                let rowId = "generic.\(generic.id)"
                let baseTitle = (generic.title.flatMap { $0.isEmpty ? nil : $0 }) ?? "Подарок #\(generic.id)"
                let limitTag = generic.availability != nil ? " · Лимит" : ""
                let label = "\(generic.price) ⭐️\(limitTag)"
                rows.append(MTPERow(id: rowId, kind: .disclosure(title: baseTitle, label: label, icon: nil, enabled: true)))
                model.tap[rowId] = {
                    MTFakeGiftsSettings.isEnabled.set(true)
                    MTFakeGiftsStore.shared.ensureAccount(context.account)
                    let accountPeerId = context.account.peerId
                    let date = Int32(Date().timeIntervalSince1970)
                    MTFakeGiftsStore.shared.add(
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
                            if let targetPeerId {
                                mtDeliverVisualGiftToChat(
                                    context: context,
                                    gift: gift,
                                    targetPeerId: targetPeerId,
                                    localId: localId,
                                    date: date,
                                    from: pickerRef ?? controller
                                )
                            } else {
                                mtPresentGiftConfetti(context: context, from: pickerRef ?? controller)
                                let editor = mtMakeFakeGiftEditor(context: context, localId: localId)
                                if let nav = pickerRef?.navigationController as? NavigationController {
                                    nav.replaceTopController(editor, animated: true)
                                } else {
                                    navigationController?.pushViewController(editor)
                                }
                            }
                        }
                    )
                }
            }
        }
        model.sections.append(rows)
        return model
    }

    let picker = mtPEMakeListController(context: context, model: model)
    pickerRef = picker
    if let controller {
        controller.push(picker)
    } else {
        navigationController?.pushViewController(picker)
    }
}

/// The editor works on a draft; "Done" writes it once.
func mtMakeFakeGiftEditor(context: AccountContext, localId: Int64) -> ViewController {
    let accountPeerId = context.account.peerId
    weak var controllerRef: ItemListController?

    guard let initial = MTFakeGiftsStore.shared.records(accountPeerId: accountPeerId).first(where: { $0.localId == localId }) else {
        return mtMakeFakeGiftsListScreen(context: context)
    }
    let draft = ValuePromise<MTFakeGiftRecord>(initial, ignoreRepeated: true)
    let draftValue = Atomic<MTFakeGiftRecord>(value: initial)
    let updateDraft: ((inout MTFakeGiftRecord) -> Void) -> Void = { transform in
        var value = draftValue.with { $0 }
        transform(&value)
        let _ = draftValue.swap(value)
        draft.set(value)
    }

    let sender: Signal<EnginePeer?, NoError> = draft.get()
    |> map { record -> EnginePeer.Id? in
        return record.fromPeer.map(PeerId.init(mtKey:))
    }
    |> distinctUntilChanged
    |> mapToSignal { peerId -> Signal<EnginePeer?, NoError> in
        guard let peerId = peerId else {
            return .single(nil)
        }
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    }

    let model = combineLatest(queue: .mainQueue(), draft.get(), sender, MTLocalization.shared.languageCodeSignal)
    |> map { record, senderPeer, _ -> MTPEScreenModel in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var model = MTPEScreenModel(title: mtFakeGiftTitle(record.gift, number: record.number))

        let senderLabel: String
        if record.nameHidden {
            senderLabel = MTStrings.FakeGifts.Editor.anonymous
        } else if let senderPeer = senderPeer {
            senderLabel = senderPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        } else {
            senderLabel = MTStrings.FakeGifts.Editor.noSender
        }
        model.sections.append([
            MTPERow(id: "senderHeader", kind: .header(MTStrings.FakeGifts.Editor.senderHeader)),
            MTPERow(id: "sender", kind: .peer(title: MTStrings.FakeGifts.Editor.sender, label: senderLabel, peer: record.nameHidden ? nil : senderPeer))
        ])
        model.tap["sender"] = {
            mtPEPresentActionSheet(context: context, from: controllerRef, buttons: [
                (title: MTStrings.FakeGifts.Editor.chooseSender, isDestructive: false, action: {
                    let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasContactSelector: true, title: MTStrings.FakeGifts.Editor.chooseSender))
                    picker.peerSelected = { [weak picker] peer, _ in
                        updateDraft { record in
                            record.fromPeer = peer.id.mtKey
                            record.nameHidden = false
                        }
                        picker?.dismiss()
                    }
                    controllerRef?.push(picker)
                }),
                (title: MTStrings.FakeGifts.Editor.anonymous, isDestructive: false, action: {
                    updateDraft { record in
                        record.nameHidden = true
                    }
                }),
                (title: MTStrings.FakeGifts.Editor.noSender, isDestructive: false, action: {
                    updateDraft { record in
                        record.fromPeer = nil
                        record.nameHidden = false
                    }
                })
            ])
        }

        model.sections.append([
            MTPERow(id: "captionHeader", kind: .header(MTStrings.FakeGifts.Editor.captionHeader)),
            MTPERow(id: "caption", kind: .multilineInput(text: record.text ?? "", placeholder: MTStrings.FakeGifts.Editor.captionPlaceholder))
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
            MTPERow(id: "dateHeader", kind: .header(MTStrings.FakeGifts.Editor.dateHeader)),
            MTPERow(id: "date", kind: .disclosure(title: MTStrings.FakeGifts.Editor.date, label: mtFakeGiftDateString(record.date), icon: nil, enabled: true))
        ])
        model.tap["date"] = {
            let now = Int32(Date().timeIntervalSince1970)
            let day: Int32 = 24 * 60 * 60
            let presets: [(String, Int32)] = [
                (MTStrings.FakeGifts.Editor.dateNow, now),
                (MTStrings.FakeGifts.Editor.dateYesterday, now - day),
                (MTStrings.FakeGifts.Editor.dateWeek, now - 7 * day),
                (MTStrings.FakeGifts.Editor.dateMonth, now - 30 * day),
                (MTStrings.FakeGifts.Editor.dateYear, now - 365 * day)
            ]
            mtPEPresentActionSheet(context: context, from: controllerRef, buttons: presets.map { preset in
                return (title: preset.0, isDestructive: false, action: {
                    updateDraft { record in
                        record.date = preset.1
                    }
                })
            })
        }

        model.sections.append([
            MTPERow(id: "shown", kind: .toggle(title: MTStrings.FakeGifts.Editor.shown, value: record.savedToProfile, enabled: true)),
            MTPERow(id: "pinned", kind: .toggle(title: MTStrings.FakeGifts.Editor.pinned, value: record.pinnedToTop, enabled: true)),
            MTPERow(id: "flagsFooter", kind: .footer(MTStrings.FakeGifts.Editor.flagsFooter))
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

        model.sections.append([MTPERow(id: "delete", kind: .action(title: MTStrings.FakeGifts.Editor.delete, destructive: true, enabled: true))])
        model.tap["delete"] = {
            mtPEConfirmDestructive(context: context, from: controllerRef, title: MTStrings.FakeGifts.Editor.deleteTitle, text: MTStrings.FakeGifts.Editor.deleteText, confirm: MTStrings.FakeGifts.Editor.delete, action: {
                MTFakeGiftsStore.shared.remove(accountPeerId: accountPeerId, localId: localId)
                controllerRef?.dismiss()
            })
        }

        model.rightButton = (title: presentationData.strings.Common_Done, enabled: true, action: {
            let value = draftValue.with { $0 }
            MTFakeGiftsStore.shared.update(accountPeerId: accountPeerId, localId: localId, { record in
                record = value
            })
            controllerRef?.dismiss()
        })
        return model
    }
    let controller = mtPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

// MARK: - Portals Visual NFT Marketplace & Collection Constructor

private func mtFormatAttributeRarity(_ rarity: StarGift.UniqueGift.Attribute.Rarity) -> String {
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

private let mtNftRussianAliases: [(keywords: [String], matchTerms: [String])] = [
    (["пепе", "лягушка", "жаба", "pepe"], ["plush pepe", "kissed frog"]),
    (["кепка", "дуров", "cap", "durov"], ["durov's cap", "durovs cap"]),
    (["снуп", "дог", "snoop"], ["snoop dogg", "snoop cigar", "swag bag", "westside sign", "low rider"]),
    (["часы", "watch", "ролекс"], ["swiss watch"]),
    (["кольцо", "перстень", "ring"], ["signet ring", "diamond ring", "bonded ring"]),
    (["меч", "световой", "джедай", "sword"], ["light sword"]),
    (["череп", "skull"], ["electric skull", "crystal ball"]),
    (["шлем", "helmet", "космонавт"], ["neko helmet", "vintage cigar"]),
    (["кот", "кошка", "котик", "cat"], ["scared cat", "neko helmet"]),
    (["мишка", "медведь", "bear"], ["toy bear"]),
    (["сердце", "heart"], ["trapped heart", "cookie heart", "eternal candle"]),
    (["роза", "цветок", "rose"], ["eternal rose", "sakura flower", "skull flower"]),
    (["персик", "peach"], ["precious peach"]),
    (["духи", "флакон", "парфюм", "perfume"], ["perfume bottle"]),
    (["зелье", "колба", "potion"], ["magic potion", "love potion"]),
    (["сигара", "cigar"], ["vintage cigar", "snoop cigar"]),
    (["шапка", "ушанка", "санта", "hat"], ["santa hat", "winter wreath", "witch hat", "top hat", "jester hat"]),
    (["леденец", "чупа", "конфета", "lol"], ["lol pop", "lollipop", "candy cane"]),
    (["мороженое", "пломбир", "cream"], ["ice cream", "vice cream"]),
    (["лапша", "дошик", "рамен", "ramen"], ["instant ramen"]),
    (["губы", "поцелуй", "lips"], ["sharp tongue", "kissed frog"]),
    (["осколок", "астрал", "кристалл", "shard"], ["astral shard", "ion gem"]),
    (["календарь", "calendar"], ["desk calendar"]),
    (["кролик", "заяц", "bunny"], ["jelly bunny", "easter egg"]),
    (["змея", "snake"], ["lunar snake", "pet snake"]),
    (["торт", "кекс", "cake"], ["homemade cake", "berry box"]),
    (["очки", "визор"], ["hypno lollipop", "cyber"]),
    (["звезда", "star"], ["hanging star", "flying broom"])
]

private func mtNftCollectionMatchesQuery(title: String, query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty {
        return true
    }
    let lowTitle = title.lowercased()
    let compactTitle = lowTitle.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
    let compactQuery = q.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
    if lowTitle.contains(q) || compactTitle.contains(compactQuery) {
        return true
    }
    for alias in mtNftRussianAliases {
        if alias.keywords.contains(where: { $0.contains(q) || q.contains($0) }) {
            if alias.matchTerms.contains(where: { lowTitle.contains($0) }) {
                return true
            }
        }
    }
    return false
}

private func mtOpenExternalNftMarket(context: AccountContext, url: String, from controller: ViewController?) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let nav = (controller?.navigationController as? NavigationController) ?? mtProfileExportTopController(context: context)?.0
    context.sharedContext.openExternalUrl(
        context: context,
        urlContext: .generic,
        url: url,
        forceExternal: false,
        presentationData: presentationData,
        navigationController: nav,
        dismissInput: {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    )
}

func mtPresentPortalsNftCatalog(context: AccountContext, from controller: ViewController?, targetPeerId: PeerId?) {
    let _ = context.engine.payments.keepStarGiftsUpdated().start()
    weak var pickerRef: ItemListController?
    let navigationController = (controller?.navigationController as? NavigationController) ?? mtProfileExportTopController(context: context)?.0
    let openConstructorByDefault = ValuePromise<Bool>(false, ignoreRepeated: true)
    let searchQueryPromise = ValuePromise<String>("", ignoreRepeated: true)

    let model = combineLatest(
        queue: .mainQueue(),
        context.engine.payments.cachedStarGifts(),
        openConstructorByDefault.get(),
        searchQueryPromise.get(),
        MTLocalization.shared.languageCodeSignal
    )
    |> map { catalog, constructorMode, searchQuery, _ -> MTPEScreenModel in
        var model = MTPEScreenModel(title: targetPeerId == nil ? "Маркеты NFT" : "Подарить NFT")

        model.sections.append([
            MTPERow(id: "searchHeader", kind: .header("Поиск коллекции")),
            MTPERow(id: "searchInput", kind: .input(text: searchQuery, placeholder: "Поиск: Plush Pepe, пепе, кепка, снуп, часы..."))
        ])
        model.text["searchInput"] = { value in
            searchQueryPromise.set(value)
        }

        model.sections.append([
            MTPERow(id: "marketsHeader", kind: .header("Маркетплейсы подарков Telegram")),
            MTPERow(id: "marketPortals", kind: .disclosure(title: "Portals Market", label: "@portals", icon: nil, enabled: true)),
            MTPERow(id: "marketMrkt", kind: .disclosure(title: "MRKT Market", label: "@mrkt", icon: nil, enabled: true)),
            MTPERow(id: "marketTonnel", kind: .disclosure(title: "Tonnel Relayer Market", label: "@tonnel_network_bot", icon: nil, enabled: true)),
            MTPERow(id: "marketFragment", kind: .disclosure(title: "Fragment Collectible Gifts", label: "fragment.com", icon: nil, enabled: true)),
            MTPERow(id: "marketsFooter", kind: .footer("Откройте любой маркетплейс выше, чтобы скопировать ссылку на понравившийся NFT (t.me/nft/...), или выберите коллекцию прямо из встроенного 3D-каталога ниже."))
        ])
        model.tap["marketPortals"] = {
            mtOpenExternalNftMarket(context: context, url: "https://t.me/portals/market", from: pickerRef)
        }
        model.tap["marketMrkt"] = {
            mtOpenExternalNftMarket(context: context, url: "https://t.me/mrkt/app", from: pickerRef)
        }
        model.tap["marketTonnel"] = {
            mtOpenExternalNftMarket(context: context, url: "https://t.me/tonnel_network_bot/gifts", from: pickerRef)
        }
        model.tap["marketFragment"] = {
            mtOpenExternalNftMarket(context: context, url: "https://fragment.com/gifts", from: pickerRef)
        }

        model.sections.append([
            MTPERow(id: "modeHeader", kind: .header("Режим выбора NFT")),
            MTPERow(id: "constructorToggle", kind: .toggle(title: "Режим Конструктора (свой Фон + Модель + #Номер)", value: constructorMode, enabled: true)),
            MTPERow(id: "addByLinkRow", kind: .action(title: "Ввести ссылку или название (t.me/nft/PlushPepe-1)", destructive: false, enabled: true)),
            MTPERow(id: "modeFooter", kind: .footer(constructorMode ? "Нажмите на коллекцию ниже, чтобы собрать NFT с любой Моделью, Фоном, Узором и любым #Номером." : "Нажмите на коллекцию ниже, чтобы открыть встроенную 3D-витрину с фильтрами по Модели, Фону, Узору и сортировкой по цене или номеру."))
        ])
        model.toggle["constructorToggle"] = { value in
            openConstructorByDefault.set(value)
        }
        model.tap["addByLinkRow"] = {
            mtPromptAddFakeUniqueGift(context: context, from: pickerRef, targetPeerId: targetPeerId)
        }

        let allGenerics: [StarGift.Gift] = (catalog ?? []).compactMap { gift in
            if case let .generic(generic) = gift {
                return generic
            }
            return nil
        }
        let nftCollections = allGenerics.filter { generic in
            let hasNft: Bool
            if let resale = generic.availability?.resale, resale > 0 {
                hasNft = true
            } else if generic.upgradeStars != nil || generic.availability != nil {
                hasNft = true
            } else {
                hasNft = false
            }
            guard hasNft else { return false }
            let title = (generic.title.flatMap { $0.isEmpty ? nil : $0 }) ?? "Коллекция #\(generic.id)"
            return mtNftCollectionMatchesQuery(title: title, query: searchQuery)
        }.sorted { lhs, rhs in
            let lhsResale = lhs.availability?.resale ?? 0
            let rhsResale = rhs.availability?.resale ?? 0
            if lhsResale != rhsResale {
                return lhsResale > rhsResale
            }
            return (lhs.title ?? "") < (rhs.title ?? "")
        }

        let trimmedQ = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let headerTitle = trimmedQ.isEmpty ? "Коллекции NFT (\(nftCollections.count))" : "Найдено коллекций: \(nftCollections.count)"
        var rows: [MTPERow] = [MTPERow(id: "collectionsHeader", kind: .header(headerTitle))]
        if allGenerics.isEmpty {
            rows.append(MTPERow(id: "loading", kind: .info("Загружаем каталог коллекций NFT из Telegram… Подождите пару секунд.")))
        } else if nftCollections.isEmpty {
            rows.append(MTPERow(id: "noMatch", kind: .info("По запросу «\(trimmedQ)» коллекций не найдено. Попробуйте английское название или вставьте прямую ссылку t.me/nft/... выше.")))
        } else {
            for generic in nftCollections {
                let rowId = "nftcol.\(generic.id)"
                let title = (generic.title.flatMap { $0.isEmpty ? nil : $0 }) ?? "Коллекция #\(generic.id)"
                let resaleCount = generic.availability?.resale ?? 0
                let label: String
                if constructorMode {
                    label = "Конструктор"
                } else if resaleCount > 0 {
                    label = "\(resaleCount) на маркете"
                } else {
                    label = "Конструктор"
                }
                rows.append(MTPERow(id: rowId, kind: .disclosure(title: title, label: label, icon: nil, enabled: true)))
                model.tap[rowId] = {
                    if constructorMode || resaleCount == 0 {
                        let constructorScreen = mtMakeNftCollectionConstructorScreen(context: context, generic: generic, targetPeerId: targetPeerId)
                        pickerRef?.push(constructorScreen)
                    } else {
                        mtOpenPortalsGiftStore(context: context, generic: generic, from: pickerRef, targetPeerId: targetPeerId)
                    }
                }
            }
        }
        model.sections.append(rows)
        return model
    }

    let picker = mtPEMakeListController(context: context, model: model)
    pickerRef = picker
    if let controller {
        controller.push(picker)
    } else {
        navigationController?.pushViewController(picker)
    }
}

func mtOpenPortalsGiftStore(context: AccountContext, generic: StarGift.Gift, from controller: ViewController?, targetPeerId: PeerId?) {
    let effectivePeerId = targetPeerId ?? context.account.peerId
    weak var storeRef: GiftStoreScreen?
    let storeScreen = GiftStoreScreen(
        context: context,
        peerId: effectivePeerId,
        gift: generic,
        completion: { uniqueGift in
            mtPresentUniqueGiftActionSheet(context: context, uniqueGift: uniqueGift, generic: generic, from: storeRef, targetPeerId: targetPeerId)
        }
    )
    storeRef = storeScreen
    storeScreen.parentController = { [weak controller] in
        return controller
    }
    if let controller {
        controller.push(storeScreen)
    } else {
        let navigationController = mtProfileExportTopController(context: context)?.0
        navigationController?.pushViewController(storeScreen)
    }
}

private func mtPresentGiftConfetti(context: AccountContext, from controller: ViewController?) {
    let nav = (controller?.navigationController as? NavigationController) ?? mtProfileExportTopController(context: context)?.0
    if let navView = nav?.view {
        navView.addSubview(ConfettiView(frame: navView.bounds))
    }
}

/// Mirrors Telegram's own GiftSetupScreen / SharedAccountContext delivery flow:
/// opens (or returns to) the peer's ChatController, arms `hintPlayNextOutgoingGift()`
/// so Telegram's native `ChatMessageGiftBubbleContentNode` plays the animated gift card
/// + full-screen confetti burst, and inserts a local `TelegramMediaAction` (`.starGiftUnique`
/// or `.starGift`) into Postbox with `flags: []` so it never uploads to the server.
private func mtDeliverVisualGiftToChat(
    context: AccountContext,
    gift: StarGift,
    targetPeerId: PeerId,
    localId: Int64,
    date: Int32,
    text: String? = nil,
    entities: [MessageTextEntity]? = nil,
    from controller: ViewController?
) {
    let accountPeerId = context.account.peerId
    let action: TelegramMediaAction
    switch gift {
    case let .unique(uniqueGift):
        action = TelegramMediaAction(
            action: .starGiftUnique(
                gift: .unique(uniqueGift),
                isUpgrade: false,
                isTransferred: true,
                savedToProfile: true,
                canExportDate: nil,
                transferStars: nil,
                isRefunded: false,
                isPrepaidUpgrade: false,
                peerId: targetPeerId,
                senderId: accountPeerId,
                savedId: localId,
                resaleAmount: nil,
                canTransferDate: nil,
                canResaleDate: nil,
                dropOriginalDetailsStars: nil,
                assigned: false,
                fromOffer: false,
                canCraftAt: nil,
                isCrafted: false,
                text: text,
                entities: entities,
                nameHidden: false
            )
        )
    case let .generic(genericGift):
        action = TelegramMediaAction(
            action: .starGift(
                gift: .generic(genericGift),
                convertStars: genericGift.convertStars,
                text: text,
                entities: entities,
                nameHidden: false,
                savedToProfile: true,
                converted: false,
                upgraded: false,
                canUpgrade: genericGift.upgradeStars != nil,
                upgradeStars: genericGift.upgradeStars,
                isRefunded: false,
                isPrepaidUpgrade: false,
                upgradeMessageId: nil,
                peerId: targetPeerId,
                senderId: accountPeerId,
                savedId: localId,
                prepaidUpgradeHash: nil,
                giftMessageId: nil,
                upgradeSeparate: false,
                isAuctionAcquired: false,
                toPeerId: targetPeerId,
                number: nil
            )
        )
    }

    let navigationController = (controller?.navigationController as? NavigationController) ?? mtProfileExportTopController(context: context)?.0
    if let navigationController {
        var controllers = navigationController.viewControllers
        if let existingIdx = controllers.lastIndex(where: { vc in
            if let chat = vc as? ChatController, case .peer(id: targetPeerId) = chat.chatLocation {
                return true
            }
            return false
        }) {
            controllers = Array(controllers.prefix(existingIdx + 1))
            if let chatController = controllers.last as? ChatController {
                chatController.hintPlayNextOutgoingGift()
            }
            navigationController.setViewControllers(controllers, animated: true)
        } else {
            let base = controllers.first.map { [$0] } ?? []
            let chatController = context.sharedContext.makeChatController(
                context: context,
                chatLocation: .peer(id: targetPeerId),
                subject: nil,
                botStart: nil,
                mode: .standard(.default),
                params: nil
            )
            chatController.hintPlayNextOutgoingGift()
            navigationController.setViewControllers(base + [chatController], animated: true)
        }

        if targetPeerId.namespace == Namespaces.Peer.CloudChannel {
            navigationController.view.addSubview(ConfettiView(frame: navigationController.view.bounds))
        }
    }

    // Insert the local service message shortly after arming `hintPlayNextOutgoingGift()`
    // so ChatMessageGiftBubbleContentNode plays the gift sticker animation & native confetti on arrival.
    Queue.mainQueue().after(0.18) {
        let randomId = Int64.random(in: Int64.min ... Int64.max)
        let _ = context.account.postbox.transaction { transaction -> Void in
            let topTimestamp = transaction.getTopPeerMessageIndex(peerId: targetPeerId)?.timestamp ?? 0
            let effectiveTimestamp = max(date, topTimestamp + 1)
            let storeMessage = StoreMessage(
                peerId: targetPeerId,
                namespace: Namespaces.Message.Local,
                customStableId: nil,
                globallyUniqueId: randomId,
                groupingKey: nil,
                threadId: nil,
                timestamp: effectiveTimestamp,
                flags: [],
                tags: [],
                globalTags: [],
                localTags: [],
                forwardInfo: nil,
                authorId: accountPeerId,
                text: "",
                attributes: [],
                media: [action]
            )
            let _ = transaction.addMessages([storeMessage], location: .Random)
        }.startStandalone()
    }
}

private func mtSaveChosenUniqueGift(context: AccountContext, uniqueGift: StarGift.UniqueGift, targetPeerId: PeerId?, from controller: ViewController?) {
    MTFakeGiftsSettings.isEnabled.set(true)
    MTFakeGiftsStore.shared.ensureAccount(context.account)
    let accountPeerId = context.account.peerId
    let date = Int32(Date().timeIntervalSince1970)
    MTFakeGiftsStore.shared.add(
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
            if let targetPeerId {
                mtDeliverVisualGiftToChat(
                    context: context,
                    gift: .unique(uniqueGift),
                    targetPeerId: targetPeerId,
                    localId: localId,
                    date: date,
                    from: controller
                )
            } else {
                mtPresentGiftConfetti(context: context, from: controller)
                mtPEPresentToast(
                    context: context,
                    from: controller,
                    text: "NFT «\(uniqueGift.title) #\(uniqueGift.number)» добавлен в ваш профиль",
                    actionTitle: MTStrings.FakeGifts.Toast.edit,
                    action: {
                        controller?.push(mtMakeFakeGiftEditor(context: context, localId: localId))
                    }
                )
            }
        }
    )
}

private func mtPresentUniqueGiftActionSheet(context: AccountContext, uniqueGift: StarGift.UniqueGift, generic: StarGift.Gift, from controller: ViewController?, targetPeerId: PeerId?) {
    var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
    if let targetPeerId {
        buttons.append((
            title: "Подарить «\(uniqueGift.title) #\(uniqueGift.number)» этому пользователю",
            isDestructive: false,
            action: {
                mtSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: targetPeerId, from: controller)
            }
        ))
    }
    buttons.append((
        title: "Добавить «\(uniqueGift.title) #\(uniqueGift.number)» себе в профиль",
        isDestructive: false,
        action: {
            mtSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: nil, from: controller)
        }
    ))
    buttons.append((
        title: "Выбрать кому подарить «\(uniqueGift.title) #\(uniqueGift.number)»…",
        isDestructive: false,
        action: { [weak controller] in
            let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasContactSelector: true, title: "Кому подарить NFT"))
            picker.peerSelected = { [weak picker, weak controller] peer, _ in
                picker?.dismiss()
                mtSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: peer.id, from: controller)
            }
            controller?.push(picker)
        }
    ))
    buttons.append((
        title: "Открыть Конструктор коллекции «\(uniqueGift.title)»",
        isDestructive: false,
        action: {
            controller?.push(mtMakeNftCollectionConstructorScreen(context: context, generic: generic, targetPeerId: targetPeerId))
        }
    ))
    buttons.append((
        title: "Открыть 3D-просмотр NFT",
        isDestructive: false,
        action: {
            let viewScreen = GiftViewScreen(
                context: context,
                subject: .uniqueGift(uniqueGift, targetPeerId ?? context.account.peerId)
            )
            controller?.push(viewScreen)
        }
    ))
    mtPEPresentActionSheet(context: context, from: controller, buttons: buttons)
}

private struct MTNftConstructorDraft: Equatable {
    var modelIndex: Int = 0
    var backdropIndex: Int = 0
    var patternIndex: Int = 0
    var number: Int32 = 1
}

func mtMakeNftCollectionConstructorScreen(context: AccountContext, generic: StarGift.Gift, targetPeerId: PeerId?) -> ViewController {
    weak var controllerRef: ItemListController?
    let collectionTitle = (generic.title.flatMap { $0.isEmpty ? nil : $0 }) ?? "NFT #\(generic.id)"

    let draftPromise = ValuePromise<MTNftConstructorDraft>(MTNftConstructorDraft(), ignoreRepeated: true)
    let draftAtomic = Atomic<MTNftConstructorDraft>(value: MTNftConstructorDraft())
    let updateDraft: ((inout MTNftConstructorDraft) -> Void) -> Void = { transform in
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
    |> map { attributes, draft -> MTPEScreenModel in
        var screen = MTPEScreenModel(title: collectionTitle)

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
                MTPERow(id: "loading", kind: .info("Загружаем все 3D-модели, фоны и узоры коллекции «\(collectionTitle)» с серверов Telegram…"))
            ])
            return screen
        }

        let safeModelIdx = models.isEmpty ? 0 : min(max(0, draft.modelIndex), models.count - 1)
        let safeBackdropIdx = backdrops.isEmpty ? 0 : min(max(0, draft.backdropIndex), backdrops.count - 1)
        let safePatternIdx = patterns.isEmpty ? 0 : min(max(0, draft.patternIndex), patterns.count - 1)

        let selectedModelLabel = models.isEmpty ? "—" : "\(models[safeModelIdx].0) (\(mtFormatAttributeRarity(models[safeModelIdx].2)))"
        let selectedBackdropLabel = backdrops.isEmpty ? "—" : "\(backdrops[safeBackdropIdx].0) (\(mtFormatAttributeRarity(backdrops[safeBackdropIdx].6)))"
        let selectedPatternLabel = patterns.isEmpty ? "—" : "\(patterns[safePatternIdx].0) (\(mtFormatAttributeRarity(patterns[safePatternIdx].2)))"

        screen.sections.append([
            MTPERow(id: "attrHeader", kind: .header("Параметры NFT (\(collectionTitle) #\(draft.number))")),
            MTPERow(id: "pickModel", kind: .disclosure(title: "Модель (\(models.count))", label: selectedModelLabel, icon: nil, enabled: !models.isEmpty)),
            MTPERow(id: "pickBackdrop", kind: .disclosure(title: "Фон / Backdrop (\(backdrops.count))", label: selectedBackdropLabel, icon: nil, enabled: !backdrops.isEmpty)),
            MTPERow(id: "pickPattern", kind: .disclosure(title: "Узор / Symbol (\(patterns.count))", label: selectedPatternLabel, icon: nil, enabled: !patterns.isEmpty)),
            MTPERow(id: "pickNumber", kind: .disclosure(title: "Номер NFT", label: "#\(draft.number)", icon: nil, enabled: true)),
            MTPERow(id: "randomize", kind: .action(title: "Случайная комбинация (Модель + Фон + Узор)", destructive: false, enabled: true))
        ])

        screen.tap["pickModel"] = {
            let buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = models.enumerated().map { idx, item in
                let prefix = idx == safeModelIdx ? "✓ " : ""
                return (
                    title: "\(prefix)\(item.0) · \(mtFormatAttributeRarity(item.2))",
                    isDestructive: false,
                    action: {
                        updateDraft { $0.modelIndex = idx }
                    }
                )
            }
            mtPEPresentActionSheet(context: context, from: controllerRef, buttons: buttons)
        }

        screen.tap["pickBackdrop"] = {
            let buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = backdrops.enumerated().map { idx, item in
                let prefix = idx == safeBackdropIdx ? "✓ " : ""
                return (
                    title: "\(prefix)\(item.0) · \(mtFormatAttributeRarity(item.6))",
                    isDestructive: false,
                    action: {
                        updateDraft { $0.backdropIndex = idx }
                    }
                )
            }
            mtPEPresentActionSheet(context: context, from: controllerRef, buttons: buttons)
        }

        screen.tap["pickPattern"] = {
            let buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = patterns.enumerated().map { idx, item in
                let prefix = idx == safePatternIdx ? "✓ " : ""
                return (
                    title: "\(prefix)\(item.0) · \(mtFormatAttributeRarity(item.2))",
                    isDestructive: false,
                    action: {
                        updateDraft { $0.patternIndex = idx }
                    }
                )
            }
            mtPEPresentActionSheet(context: context, from: controllerRef, buttons: buttons)
        }

        screen.tap["pickNumber"] = {
            let presets: [Int32] = [1, 7, 13, 77, 100, 666, 777, 888, 999, 1337, 7777]
            var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = [
                (title: "Ввести любой свой номер (#)...", isDestructive: false, action: {
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
            mtPEPresentActionSheet(context: context, from: controllerRef, buttons: buttons)
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

        var actionRows: [MTPERow] = []
        if let targetPeerId {
            let _ = targetPeerId
            actionRows.append(MTPERow(id: "giftToTarget", kind: .action(title: "Создать и подарить этому пользователю", destructive: false, enabled: true)))
        }
        actionRows.append(MTPERow(id: "addToSelf", kind: .action(title: "Создать и добавить себе в профиль", destructive: false, enabled: true)))
        actionRows.append(MTPERow(id: "giftToOther", kind: .action(title: "Создать и выбрать кому подарить…", destructive: false, enabled: true)))
        actionRows.append(MTPERow(id: "preview3D", kind: .action(title: "Предпросмотр 3D-модели NFT", destructive: false, enabled: true)))
        screen.sections.append(actionRows)

        screen.tap["giftToTarget"] = {
            guard let targetPeerId, let uniqueGift = buildUniqueGift() else { return }
            mtSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: targetPeerId, from: controllerRef)
        }
        screen.tap["addToSelf"] = {
            guard let uniqueGift = buildUniqueGift() else { return }
            mtSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: nil, from: controllerRef)
        }
        screen.tap["giftToOther"] = {
            guard let uniqueGift = buildUniqueGift() else { return }
            let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasContactSelector: true, title: "Кому подарить NFT"))
            picker.peerSelected = { [weak picker] peer, _ in
                picker?.dismiss()
                mtSaveChosenUniqueGift(context: context, uniqueGift: uniqueGift, targetPeerId: peer.id, from: controllerRef)
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

    let controller = mtPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

// MARK: - Copy All NFTs from Any User Profile (#68)

private final class MTCopyAllGiftsSession {
    let giftsContext: ProfileGiftsContext
    let disposable = MetaDisposable()
    var isFinished = false
    var requestedPages = 0

    init(giftsContext: ProfileGiftsContext) {
        self.giftsContext = giftsContext
    }

    deinit {
        self.disposable.dispose()
    }
}

private var mtActiveCopyAllSession: MTCopyAllGiftsSession?

func mtCopyAllPeerNftsToOwnProfile(context: AccountContext, peerId: PeerId, from controller: ViewController?) {
    mtPEPresentToast(context: context, from: controller, text: "Загружаем коллекцию подарков…")
    let giftsContext = ProfileGiftsContext(account: context.account, peerId: peerId, limit: 100)
    let session = MTCopyAllGiftsSession(giftsContext: giftsContext)
    mtActiveCopyAllSession = session

    session.disposable.set((giftsContext.state
    |> deliverOnMainQueue).start(next: { [weak controller, weak session] state in
        guard let session, !session.isFinished else { return }
        guard case let .ready(canLoadMore, _) = state.dataState else {
            return
        }
        if canLoadMore && state.gifts.count < 500 && session.requestedPages < 15 {
            session.requestedPages += 1
            session.giftsContext.loadMore()
            return
        }
        session.isFinished = true
        session.disposable.set(nil)
        if mtActiveCopyAllSession === session {
            mtActiveCopyAllSession = nil
        }

        let ownPeerId = context.account.peerId
        MTFakeGiftsStore.shared.ensureAccount(context.account)
        if !MTFakeGiftsSettings.isEnabled.value {
            MTFakeGiftsSettings.isEnabled.set(true)
        }
        let cappedGifts = Array(state.gifts.prefix(500))
        let uniqueOnly = cappedGifts.filter {
            if case .unique = $0.gift { return true }
            return false
        }
        let source = uniqueOnly.isEmpty ? cappedGifts : uniqueOnly
        guard !source.isEmpty else {
            mtPEPresentToast(context: context, from: controller, text: "У этого пользователя нет открытых подарков")
            return
        }
        let batch: [MTFakeGiftBatchInput] = source.map { item in
            let giftNum: Int32?
            if case let .unique(unique) = item.gift {
                giftNum = unique.number
            } else {
                giftNum = nil
            }
            return MTFakeGiftBatchInput(
                gift: item.gift,
                fromPeer: item.fromPeer?.id,
                nameHidden: item.nameHidden,
                date: item.date,
                text: item.text,
                entities: item.entities,
                number: giftNum
            )
        }
        MTFakeGiftsStore.shared.addBatch(accountPeerId: ownPeerId, items: batch, targetPeer: nil) { addedCount in
            mtPEPresentToast(context: context, from: controller, text: "Скопировано \(addedCount) подарков в ваш профиль")
        }
    }))
}

// MARK: - Live CryptoBot NFT Collection Value Calculator (#80)

private func mtEstimatedFloorTon(for gift: StarGift) -> Double {
    switch gift {
    case let .unique(unique):
        let slugLower = unique.slug.lowercased()
        if slugLower.contains("plushpepe") || slugLower.contains("durov") {
            return 1450.0
        } else if slugLower.contains("heartlocket") || slugLower.contains("preciouspeach") || slugLower.contains("astralshard") || slugLower.contains("astrals") {
            return 320.0
        } else if slugLower.contains("perfume") || slugLower.contains("lootbag") || slugLower.contains("iongem") || slugLower.contains("magicpotion") {
            return 85.0
        } else if slugLower.contains("swisswatch") || slugLower.contains("signetring") || slugLower.contains("eternalrose") || slugLower.contains("vintagecigar") {
            return 38.0
        } else if unique.number <= 10 {
            return 120.0
        } else if unique.number <= 100 {
            return 45.0
        } else {
            return 14.0
        }
    case let .generic(generic):
        return max(0.25, Double(generic.price) * 0.003)
    }
}

func mtPresentNftCollectionValueCalculator(context: AccountContext, records: [MTFakeGiftRecord], from controller: ViewController?) {
    let ownRecords = records.filter { $0.targetPeer == nil }
    guard !ownRecords.isEmpty else {
        mtPEPresentToast(context: context, from: controller, text: "В вашей коллекции пока нет подарков")
        return
    }
    let totalTon = ownRecords.reduce(0.0) { $0 + mtEstimatedFloorTon(for: $1.gift) }
    let nftCount = ownRecords.filter {
        if case .unique = $0.gift { return true }
        return false
    }.count

    mtPEPresentToast(context: context, from: controller, text: "Получаем живой курс TON (CryptoBot)…")

    let showReport: (Double, Double, Double, Double, String) -> Void = { [weak controller] usdRate, rubRate, kztRate, uahRate, sourceName in
        let tonStr = String(format: "%.2f TON", totalTon)
        let usdStr = String(format: "$%.2f", totalTon * usdRate)
        let rubStr = String(format: "%.0f ₽", totalTon * rubRate)
        let kztStr = String(format: "%.0f ₸", totalTon * kztRate)
        let uahStr = String(format: "%.0f ₴", totalTon * uahRate)
        let body = """
Оценка флора (локальная база + курс \(sourceName)):
Подарков в профиле: \(ownRecords.count) (NFT: \(nftCount))
Курс: 1 TON = $\(String(format: "%.2f", usdRate)) (\(sourceName))

TON:  \(tonStr)
USD:  \(usdStr)
RUB:  \(rubStr)
KZT:  \(kztStr)
UAH:  \(uahStr)
"""
        let alert = UIAlertController(title: "Оценка коллекции NFT", message: body, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Скопировать отчёт", style: .default) { _ in
            UIPasteboard.general.string = body
            mtPEPresentToast(context: context, from: controller, text: "Отчёт скопирован в буфер обмена")
        })
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        MTModalPresenter.presentOnTopmost(alert, preferredRoot: controller?.viewIfLoaded?.window?.rootViewController)
    }

    let fetchCoinGeckoFallback: () -> Void = {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=the-open-network&vs_currencies=usd,rub,kzt,uah") else {
            DispatchQueue.main.async { showReport(5.2, 495.0, 2650.0, 215.0, "офлайн-оценка") }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 8.0)
        req.setValue("MediaTok/13.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ton = json["the-open-network"] as? [String: Any],
               let usd = ton["usd"] as? Double, usd > 0 {
                let rub = (ton["rub"] as? Double) ?? (usd * 95.0)
                let kzt = (ton["kzt"] as? Double) ?? (usd * 510.0)
                let uah = (ton["uah"] as? Double) ?? (usd * 41.5)
                DispatchQueue.main.async { showReport(usd, rub, kzt, uah, "CoinGecko") }
            } else {
                DispatchQueue.main.async { showReport(5.2, 495.0, 2650.0, 215.0, "офлайн-оценка") }
            }
        }.resume()
    }

    guard let cryptoBotUrl = URL(string: "https://pay.crypt.bot/api/getExchangeRates") else {
        fetchCoinGeckoFallback()
        return
    }
    var req = URLRequest(url: cryptoBotUrl, timeoutInterval: 6.0)
    req.setValue("MediaTok/13.1", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: req) { data, _, _ in
        if let data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? [[String: Any]] {
            var usd: Double?
            var rub: Double?
            var kzt: Double?
            var uah: Double?
            for item in result {
                guard (item["source"] as? String) == "TON",
                      let target = item["target"] as? String,
                      let rateStr = item["rate"] as? String,
                      let rate = Double(rateStr), rate > 0 else { continue }
                switch target {
                case "USD": usd = rate
                case "RUB": rub = rate
                case "KZT": kzt = rate
                case "UAH": uah = rate
                default: break
                }
            }
            if let usd {
                DispatchQueue.main.async {
                    showReport(usd, rub ?? usd * 95.0, kzt ?? usd * 510.0, uah ?? usd * 41.5, "CryptoBot")
                }
                return
            }
        }
        fetchCoinGeckoFallback()
    }.resume()
}
