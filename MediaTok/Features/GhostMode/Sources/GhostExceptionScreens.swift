import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import ItemListPeerItem
import LocalizedPeerData
import PresentationDataUtils
import AlertUI
import ChatListUI
import MTCore
import MTSettingsUI
import MTFeaturesShared

// «Исключения»: the rows of its «Чаты» and «Папки» segments, one chat's exception and its own
// status list. Each screen / provider follows one signal (presentation data + the account's
// settings + MediaTok's language) and owns its subscriptions; nothing is kept after it closes.

private func mtGhostLanguageAndSettings(_ setting: Signal<[String: MTGhostException], NoError>) -> Signal<[String: MTGhostException], NoError> {
    return combineLatest(setting, MTLocalization.shared.languageCodeSignal)
    |> map { value, _ -> [String: MTGhostException] in
        return value
    }
}

/// One line describing what a chat's exception lets through.
func mtGhostExceptionSummary(_ exception: MTGhostException) -> String {
    if exception.kind == .include {
        return MTStrings.GhostMode.Exceptions.summaryForced
    }
    var parts: [String] = []
    if exception.readMessages {
        parts.append(MTStrings.GhostMode.Exceptions.summaryReads)
    }
    if exception.readStories {
        parts.append(MTStrings.GhostMode.Exceptions.summaryStories)
    }
    if exception.showOnline {
        parts.append(MTStrings.GhostMode.Exceptions.summaryOnline)
    }
    if exception.showTyping {
        parts.append(MTStrings.GhostMode.Exceptions.summaryTyping)
    } else if exception.ownShownActivities != nil {
        parts.append(MTStrings.GhostMode.Exceptions.summaryOwnStatuses)
    }
    if parts.isEmpty {
        return MTStrings.GhostMode.Exceptions.summaryNone
    }
    return parts.joined(separator: " • ")
}

/// Writes the exceptions of an account and recomputes "online" (the chat on screen may have just
/// become an exception: it goes online without leaving and re-entering).
func mtGhostUpdateExceptions(account: MTAccountID, _ f: (inout [String: MTGhostException]) -> Void) {
    var exceptions = MTGhostSettings.exceptions.value(for: account)
    f(&exceptions)
    MTGhostSettings.exceptions.set(exceptions, for: account)
    MTGhostPresence.shared.exceptionsDidChange()
}

// MARK: - «Исключения» › «Чаты» and «Папки» (runtime rows of the segmented tab)

/// The «Чаты» and «Папки» segments of «Исключения»: rows built at runtime from the account's
/// exceptions and the user's folders (`MTMenuRegistry.register(dynamicRowsIn:)`). Each provider runs
/// one signal per opening of the tab and nothing is kept after it closes.
enum MTGhostExceptionRows {
    static let chatsSection = MTMenuSectionID("ghostMode.exceptions.chats")
    static let foldersSection = MTMenuSectionID("ghostMode.exceptions.folders")

    /// «Выбрать чаты»: Telegram's chat picker over the chats excluded so far.
    static func presentPicker(_ menuContext: MTMenuContext) {
        let context = menuContext.context
        let account = context.account.id.mt
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var selected = Set<EnginePeer.Id>()
        for (key, exception) in MTGhostSettings.exceptions.value(for: account) where exception.kind == .exclude {
            if let peerKey = MTPeerKey(string: key) {
                selected.insert(PeerId(mtKey: peerKey))
            }
        }
        let controller = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
            title: MTStrings.GhostMode.Exceptions.addTitle,
            searchPlaceholder: presentationData.strings.Common_Search,
            selectedChats: selected,
            additionalCategories: nil,
            chatListFilters: nil
        )), alwaysEnabled: true))
        let _ = (controller.result
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak controller] result in
            guard case let .result(peerIds, _) = result else {
                controller?.dismiss()
                return
            }
            var chosen = Set<EnginePeer.Id>()
            for peerId in peerIds {
                if case let .peer(value) = peerId {
                    chosen.insert(value)
                }
            }
            mtGhostUpdateExceptions(account: account) { exceptions in
                for (key, exception) in exceptions where exception.kind == .exclude {
                    if let peerKey = MTPeerKey(string: key), !chosen.contains(PeerId(mtKey: peerKey)) {
                        exceptions.removeValue(forKey: key)
                    }
                }
                for peerId in chosen where exceptions[peerId.mtGhostKey]?.kind != .exclude {
                    exceptions[peerId.mtGhostKey] = MTGhostException()
                }
            }
            controller?.dismiss()
        })
        menuContext.present(controller, arguments: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }

    /// Every chat with its own exception, sorted by name, with what it lets through; swipe to remove.
    static func chatRows(_ providerContext: MTMenuContext) -> Signal<[MTMenuRow], NoError> {
        let context = providerContext.context
        let account = context.account.id.mt
        let revealed = ValuePromise<EnginePeer.Id?>(nil, ignoreRepeated: true)

        let peers: Signal<[EnginePeer.Id: EnginePeer], NoError> = MTGhostSettings.exceptions.signal(for: account)
        |> map { exceptions -> [EnginePeer.Id] in
            return exceptions.keys.compactMap { key -> EnginePeer.Id? in
                return MTPeerKey(string: key).flatMap { PeerId(mtKey: $0) }
            }
        }
        |> distinctUntilChanged
        |> mapToSignal { peerIds -> Signal<[EnginePeer.Id: EnginePeer], NoError> in
            return context.engine.data.subscribe(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
            |> map { map -> [EnginePeer.Id: EnginePeer] in
                var result: [EnginePeer.Id: EnginePeer] = [:]
                for (peerId, peer) in map {
                    if let peer = peer {
                        result[peerId] = peer
                    }
                }
                return result
            }
        }

        return combineLatest(MTGhostSettings.exceptions.signal(for: account), peers, revealed.get(), context.sharedContext.presentationData)
        |> map { exceptions, peers, revealedPeerId, presentationData -> [MTMenuRow] in
            var items: [(EnginePeer, MTGhostException)] = []
            for (key, exception) in exceptions {
                guard let peerKey = MTPeerKey(string: key), let peer = peers[PeerId(mtKey: peerKey)] else {
                    continue
                }
                items.append((peer, exception))
            }
            items.sort(by: { lhs, rhs in
                let lhsTitle = lhs.0.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                let rhsTitle = rhs.0.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            })
            if items.isEmpty {
                return [MTMenuRow(id: "ghostMode.exceptions.chatsEmpty", section: MTGhostExceptionRows.chatsSection, order: 1000, title: { "" }, kind: .custom({ rowContext in
                    return ItemListTextItem(presentationData: rowContext.itemListPresentationData, text: .plain(MTStrings.GhostMode.Exceptions.empty), sectionId: rowContext.sectionId)
                }))]
            }
            var rows: [MTMenuRow] = []
            for (index, item) in items.enumerated() {
                let peer = item.0
                let exception = item.1
                let peerId = peer.id
                let isRevealed = revealedPeerId == peerId
                rows.append(MTMenuRow(id: "ghostMode.exceptions.peer.\(peerId.mtKey.stringValue)", section: MTGhostExceptionRows.chatsSection, order: 1000 + index, title: { "" }, kind: .custom({ rowContext in
                    let presentationData = rowContext.presentationData
                    let remove: (EnginePeer.Id) -> Void = { peerId in
                        mtGhostUpdateExceptions(account: account) { exceptions in
                            exceptions.removeValue(forKey: peerId.mtGhostKey)
                        }
                    }
                    return ItemListPeerItem(presentationData: rowContext.itemListPresentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: rowContext.context, peer: peer, presence: nil, text: .text(mtGhostExceptionSummary(exception), .secondary), label: .none, editing: ItemListPeerItemEditing(editable: true, editing: false, revealed: isRevealed), revealOptions: ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: MTStrings.GhostMode.Exceptions.remove, action: {
                        remove(peerId)
                    })]), switchValue: nil, enabled: true, selectable: true, sectionId: rowContext.sectionId, action: {
                        rowContext.push(mtGhostExceptionController(context: rowContext.context, peerId: peerId))
                    }, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
                        if peerId != nil || fromPeerId != nil {
                            revealed.set(peerId)
                        }
                    }, removePeer: { peerId in
                        remove(peerId)
                    })
                })))
            }
            return rows
        }
    }

    /// The user's folders as switches. Membership is resolved live from the folder definitions (no
    /// stored snapshots of peer ids that go stale); a deleted folder simply stops matching.
    static func folderRows(_ providerContext: MTMenuContext) -> Signal<[MTMenuRow], NoError> {
        let context = providerContext.context
        let account = context.account.id.mt
        let toggle: (Int32, Bool) -> Void = { id, value in
            var folders = MTGhostSettings.exceptFolders.value(for: account)
            if value {
                folders.insert(id)
            } else {
                folders.remove(id)
            }
            MTGhostSettings.exceptFolders.set(folders, for: account)
            MTGhostPresence.shared.exceptionsDidChange()
        }
        // A folder hidden from the app (a locked secret folder) is not listed; an exception already
        // set on it stays in force.
        return combineLatest(MTGhostSettings.exceptFolders.signal(for: account), mtChatListFolders(context.engine.peers.updatedChatListFilters(), context: context))
        |> map { selected, filters -> [MTMenuRow] in
            var rows: [MTMenuRow] = []
            var order = 1000
            for filter in filters {
                guard case let .filter(id, title, _, _) = filter else {
                    continue
                }
                let text = title.text.isEmpty ? "#\(id)" : title.text
                let isOn = selected.contains(id)
                rows.append(MTMenuRow(id: "ghostMode.exceptFolders.\(id)", section: MTGhostExceptionRows.foldersSection, order: order, title: { text }, kind: .custom({ rowContext in
                    return ItemListSwitchItem(presentationData: rowContext.itemListPresentationData, systemStyle: .glass, title: text, value: isOn, sectionId: rowContext.sectionId, style: .blocks, updated: { value in
                        toggle(id, value)
                    })
                })))
                order += 1
            }
            if rows.isEmpty {
                rows.append(MTMenuRow(id: "ghostMode.exceptFolders.empty", section: MTGhostExceptionRows.foldersSection, order: 1000, title: { "" }, kind: .custom({ rowContext in
                    return ItemListTextItem(presentationData: rowContext.itemListPresentationData, text: .plain(MTStrings.GhostMode.Exceptions.foldersEmpty), sectionId: rowContext.sectionId)
                })))
            }
            return rows
        }
    }
}

// MARK: - One chat

private final class MTGhostExceptionArguments {
    let update: ((inout MTGhostException) -> Void) -> Void
    let openStatuses: () -> Void
    let chooseReadOnAction: () -> Void
    let remove: () -> Void

    init(update: @escaping ((inout MTGhostException) -> Void) -> Void, openStatuses: @escaping () -> Void, chooseReadOnAction: @escaping () -> Void, remove: @escaping () -> Void) {
        self.update = update
        self.openStatuses = openStatuses
        self.chooseReadOnAction = chooseReadOnAction
        self.remove = remove
    }
}

private enum MTGhostExceptionEntry: ItemListNodeEntry {
    case info(String)
    case readMessages(String, Bool)
    case readStories(String, Bool)
    case showOnline(String, String, Bool)
    case showTyping(String, Bool)
    case statuses(String, String)
    case readOnAction(String, String)
    case footer(String)
    case remove(String)

    var section: ItemListSectionId {
        switch self {
        case .info:
            return 0
        case .readMessages, .readStories, .showOnline, .showTyping, .statuses, .readOnAction, .footer:
            return 1
        case .remove:
            return 2
        }
    }

    var stableId: Int {
        switch self {
        case .info:
            return 0
        case .readMessages:
            return 1
        case .readStories:
            return 2
        case .showOnline:
            return 3
        case .showTyping:
            return 4
        case .statuses:
            return 5
        case .readOnAction:
            return 6
        case .footer:
            return 7
        case .remove:
            return 8
        }
    }

    static func <(lhs: MTGhostExceptionEntry, rhs: MTGhostExceptionEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MTGhostExceptionArguments
        switch self {
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .readMessages(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.readMessages = value }
            })
        case let .readStories(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.readStories = value }
            })
        case let .showOnline(title, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: text, value: value, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.showOnline = value }
            })
        case let .showTyping(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.showTyping = value }
            })
        case let .statuses(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.openStatuses()
            })
        case let .readOnAction(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.chooseReadOnAction()
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .remove(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.remove()
            })
        }
    }
}

/// The exception of one chat (from the list or from the profile's «…»).
func mtGhostExceptionController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let account = context.account.id.mt
    let key = peerId.mtGhostKey
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?

    let arguments = MTGhostExceptionArguments(update: { f in
        mtGhostUpdateExceptions(account: account) { exceptions in
            var exception = exceptions[key] ?? MTGhostException()
            f(&exception)
            exceptions[key] = exception
        }
    }, openStatuses: {
        pushImpl?(mtGhostExceptionStatusesController(context: context, peerId: peerId))
    }, chooseReadOnAction: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let set: (Bool?) -> Void = { value in
            mtGhostUpdateExceptions(account: account) { exceptions in
                var exception = exceptions[key] ?? MTGhostException()
                exception.readOnAction = value
                exceptions[key] = exception
            }
        }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: MTStrings.GhostMode.Exception.readOnActionGlobal, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                set(nil)
            }),
            ActionSheetButtonItem(title: MTStrings.GhostMode.Exception.readOnActionOn, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                set(true)
            }),
            ActionSheetButtonItem(title: MTStrings.GhostMode.Exception.readOnActionOff, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                set(false)
            })
        ]), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentImpl?(actionSheet)
    }, remove: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentImpl?(textAlertController(context: context, title: MTStrings.GhostMode.Exception.removeConfirmTitle, text: MTStrings.GhostMode.Exception.removeConfirmText, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: MTStrings.GhostMode.Exception.remove, action: {
                mtGhostUpdateExceptions(account: account) { exceptions in
                    exceptions.removeValue(forKey: key)
                }
                dismissImpl?()
            })
        ]))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, mtGhostLanguageAndSettings(MTGhostSettings.exceptions.signal(for: account)), context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)))
    |> map { presentationData, exceptions, peer -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let exception = exceptions[key] ?? MTGhostException()
        var entries: [MTGhostExceptionEntry] = []
        let title = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? MTStrings.GhostMode.Exception.title
        if exception.kind == .include {
            entries.append(.info(MTStrings.GhostMode.Exception.forcedInfo))
        } else {
            entries.append(.info(MTStrings.GhostMode.Exception.info))
            entries.append(.readMessages(MTStrings.GhostMode.Exception.readMessages, exception.readMessages))
            entries.append(.readStories(MTStrings.GhostMode.Exception.readStories, exception.readStories))
            entries.append(.showOnline(MTStrings.GhostMode.Exception.showOnline, MTStrings.GhostMode.Exception.showOnlineInfo, exception.showOnline))
            entries.append(.showTyping(MTStrings.GhostMode.Exception.showTyping, exception.showTyping))
            if !exception.showTyping {
                let label = exception.ownShownActivities == nil ? MTStrings.GhostMode.Exception.statusesGlobal : MTStrings.GhostMode.Exception.statusesOwn
                entries.append(.statuses(MTStrings.GhostMode.Exception.statuses, label))
            }
            if !exception.readMessages {
                let label: String
                switch exception.readOnAction {
                case .none:
                    label = MTStrings.GhostMode.Exception.readOnActionGlobal
                case .some(true):
                    label = MTStrings.GhostMode.Exception.readOnActionOn
                case .some(false):
                    label = MTStrings.GhostMode.Exception.readOnActionOff
                }
                entries.append(.readOnAction(MTStrings.GhostMode.Exception.readOnAction, label))
            }
            entries.append(.footer(MTStrings.GhostMode.Exception.footer))
        }
        if exceptions[key] != nil {
            entries.append(.remove(exception.kind == .include ? MTStrings.GhostMode.Exception.restore : MTStrings.GhostMode.Exception.remove))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root), with: nil)
    }
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}

// MARK: - Own statuses of one chat

private final class MTGhostStatusesArguments {
    let setOwn: (Bool) -> Void
    let toggle: (MTGhostActivityKind, Bool) -> Void

    init(setOwn: @escaping (Bool) -> Void, toggle: @escaping (MTGhostActivityKind, Bool) -> Void) {
        self.setOwn = setOwn
        self.toggle = toggle
    }
}

private enum MTGhostStatusesEntry: ItemListNodeEntry {
    case own(String, String, Bool)
    case kind(Int, MTGhostActivityKind, String, Bool, Bool)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .own:
            return 0
        case .kind, .footer:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .own:
            return 0
        case let .kind(index, _, _, _, _):
            return 10 + index
        case .footer:
            return 1000
        }
    }

    static func <(lhs: MTGhostStatusesEntry, rhs: MTGhostStatusesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MTGhostStatusesArguments
        switch self {
        case let .own(title, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: text, value: value, maximumNumberOfLines: 3, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setOwn(value)
            })
        case let .kind(_, kind, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(kind, value)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// Statuses a chat still sees while ghost mode hides «печатает» in it: the global list, or its own.
func mtGhostExceptionStatusesController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let account = context.account.id.mt
    let key = peerId.mtGhostKey
    let update: ((inout MTGhostException) -> Void) -> Void = { f in
        mtGhostUpdateExceptions(account: account) { exceptions in
            var exception = exceptions[key] ?? MTGhostException()
            f(&exception)
            exceptions[key] = exception
        }
    }
    let globalList: () -> [MTGhostActivityKind] = {
        return MTGhostActivityKind.allCases.filter { MTGhostSettings.shownActivity($0).value(for: account) }
    }
    let arguments = MTGhostStatusesArguments(setOwn: { value in
        update { exception in
            // Turning the own list on starts from the global one, so nothing changes until edited.
            exception.ownShownActivities = value ? globalList() : nil
        }
    }, toggle: { kind, value in
        update { exception in
            var list = exception.ownShownActivities ?? globalList()
            list.removeAll(where: { $0 == kind })
            if value {
                list.append(kind)
            }
            exception.ownShownActivities = list
        }
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, mtGhostLanguageAndSettings(MTGhostSettings.exceptions.signal(for: account)), MTSettingsStore.shared.revision)
    |> map { presentationData, exceptions, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let exception = exceptions[key] ?? MTGhostException()
        let own = exception.ownShownActivities
        let shown = Set(own ?? globalList())
        var entries: [MTGhostStatusesEntry] = [.own(MTStrings.GhostMode.Exception.ownList, MTStrings.GhostMode.Exception.ownListInfo, own != nil)]
        for (index, kind) in MTGhostActivityKind.allCases.enumerated() {
            entries.append(.kind(index, kind, MTGhostMenu.activityTitle(kind), shown.contains(kind), own != nil))
        }
        entries.append(.footer(MTStrings.GhostMode.Menu.activitiesFooter))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(MTStrings.GhostMode.Menu.activities), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}
