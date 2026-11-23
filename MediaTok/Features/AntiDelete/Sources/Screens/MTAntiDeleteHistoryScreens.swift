import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import ItemListUI
import PresentationDataUtils
import LocalizedPeerData
import ChatListUI
import MTCore
import MTFeaturesShared
import MTSettingsUI

// «История»: segments «Удалённые / Изменённые», chats grouped by kind and by folder (category
// folders included), per-chat lists with pages, export / import / clear. Everything reads the
// account's own index (its Postbox) reactively: a capture while the screen is open shows up.

/// A chat folder used as a filter of the history screen.
struct MTADFolderFilter {
    let title: String
    let peerIds: Set<PeerId>
}

private enum MTADChatGroup: Int, CaseIterable {
    case personal
    case groups
    case channels
    case bots
    case secret

    var title: String {
        switch self {
        case .personal:
            return MTStrings.AntiDelete.History.personal
        case .groups:
            return MTStrings.AntiDelete.History.groups
        case .channels:
            return MTStrings.AntiDelete.History.channels
        case .bots:
            return MTStrings.AntiDelete.History.bots
        case .secret:
            return MTStrings.AntiDelete.History.secret
        }
    }

    init(_ peer: EnginePeer) {
        switch peer {
        case let .user(user):
            self = user.botInfo != nil ? .bots : .personal
        case .legacyGroup, .community:
            self = .groups
        case let .channel(channel):
            if case .broadcast = channel.info {
                self = .channels
            } else {
                self = .groups
            }
        case .secretChat:
            self = .secret
        }
    }
}

/// Whether a chat belongs to a folder, without the dynamic rules (read / muted / archived),
/// which would make the grouping change on every read: explicit chats, then the categories.
func mtFolderContains(_ data: ChatListFilterData, peer: EnginePeer, isContact: Bool, accountPeerId: PeerId) -> Bool {
    if data.excludePeers.contains(peer.id) {
        return false
    }
    if data.includePeers.peers.contains(peer.id) || data.includePeers.pinnedPeers.contains(peer.id) {
        return true
    }
    switch peer {
    case let .user(user):
        if user.botInfo != nil {
            return data.categories.contains(.bots)
        }
        if peer.id == accountPeerId {
            return false
        }
        return isContact ? data.categories.contains(.contacts) : data.categories.contains(.nonContacts)
    case .legacyGroup, .community:
        return data.categories.contains(.groups)
    case let .channel(channel):
        if case .broadcast = channel.info {
            return data.categories.contains(.channels)
        }
        return data.categories.contains(.groups)
    case .secretChat:
        return isContact ? data.categories.contains(.contacts) : data.categories.contains(.nonContacts)
    }
}

private func mtAntiDeleteDate(_ timestamp: Int32, presentationData: PresentationData) -> String {
    return stringForMediumDate(timestamp: timestamp, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, withTime: false)
}

// MARK: - Root

func mtMakeAntiDeleteHistoryController(context: AccountContext, kind initialKind: MTAntiDeleteLogKind, folder: MTADFolderFilter? = nil) -> ViewController {
    let postbox = context.account.postbox
    let accountId = context.account.id
    let segment = ValuePromise<Int>(initialKind == .deleted ? 0 : 1, ignoreRepeated: true)
    weak var weakController: ViewController?

    // Dangling entries (chats the user deleted, messages removed by hand) leave the index on open.
    if folder == nil {
        let _ = (postbox.transaction { transaction -> [(MTAntiDeleteLogKind, PeerId)] in
            var result: [(MTAntiDeleteLogKind, PeerId)] = []
            for kind in MTAntiDeleteLogKind.allCases {
                for peer in MTAntiDeleteIndexStore.readSummary(transaction, kind: kind).peers.keys {
                    result.append((kind, PeerId(mtKey: peer)))
                }
            }
            return result
        }
        |> mapToSignal { items -> Signal<Never, NoError> in
            var signal: Signal<Never, NoError> = .complete()
            for (kind, peerId) in items {
                signal = signal |> then(MTAntiDeleteOperations.reconcile(postbox: postbox, accountId: accountId, kind: kind, peerId: peerId))
            }
            return signal
        }).start()
    }

    let summaries = combineLatest(MTAntiDeleteIndexStore.summarySignal(postbox: postbox, kind: .deleted), MTAntiDeleteIndexStore.summarySignal(postbox: postbox, kind: .edited))
    let data = summaries
    |> mapToSignal { deleted, edited -> Signal<(MTAntiDeleteSummary, MTAntiDeleteSummary, [EnginePeer.Id: EnginePeer], [ChatListFilter], Set<PeerId>), NoError> in
        var ids = Set<PeerId>()
        for key in deleted.peers.keys {
            ids.insert(PeerId(mtKey: key))
        }
        for key in edited.peers.keys {
            ids.insert(PeerId(mtKey: key))
        }
        let peers = context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { result -> [EnginePeer.Id: EnginePeer] in
            var values: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in result {
                if let peer {
                    values[id] = peer
                }
            }
            return values
        }
        let contacts = postbox.transaction { transaction -> Set<PeerId> in
            return transaction.getContactPeerIds()
        }
        // A folder hidden from the app (a locked secret folder) gets no row of its own here.
        return combineLatest(peers, mtChatListFolders(context.engine.peers.currentChatListFilters(), context: context) |> take(1), contacts)
        |> map { peers, filters, contacts in
            return (deleted, edited, peers, filters, contacts)
        }
    }

    let model = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, segment.get(), data)
    |> map { presentationData, segmentIndex, data -> MTADScreenModel in
        let (deletedSummary, editedSummary, peers, filters, contacts) = data
        let kind: MTAntiDeleteLogKind = segmentIndex == 0 ? .deleted : .edited
        let summary = kind == .deleted ? deletedSummary : editedSummary
        let titles = [MTStrings.AntiDelete.History.deleted, MTStrings.AntiDelete.History.edited]
        var model = MTADScreenModel(title: folder == nil ? .sectionControl(titles, segmentIndex) : .text(folder?.title ?? ""), sections: [])

        var items: [(peer: EnginePeer, summary: MTAntiDeletePeerSummary)] = []
        for (key, value) in summary.sortedPeers {
            let peerId = PeerId(mtKey: key)
            guard let peer = peers[peerId] else {
                continue
            }
            if let folder, !folder.peerIds.contains(peerId) {
                continue
            }
            items.append((peer, value))
        }
        let total = items.reduce(0, { $0 + Int($1.summary.count) })
        if total == 0 {
            model.sections.append(MTADSection(id: "empty", rows: [MTADRow(id: "empty", kind: .footer(kind == .deleted ? MTStrings.AntiDelete.History.emptyDeleted : MTStrings.AntiDelete.History.emptyEdited))]))
        } else {
            model.sections.append(MTADSection(id: "summary", rows: [MTADRow(id: "summary", kind: .footer(kind == .deleted ? MTStrings.AntiDelete.History.totalDeleted(count: total) : MTStrings.AntiDelete.History.totalEdited(count: total)))]))
        }

        for group in MTADChatGroup.allCases {
            let groupItems = items.filter { MTADChatGroup($0.peer) == group }
            if groupItems.isEmpty {
                continue
            }
            var rows: [MTADRow] = [MTADRow(id: "header.\(group.rawValue)", kind: .header(group.title))]
            for item in groupItems {
                let id = "peer.\(item.peer.id.mtKey.stringValue)"
                let count = Int(item.summary.count)
                let text = kind == .deleted ? MTStrings.AntiDelete.History.deletedCount(count: count) : MTStrings.AntiDelete.History.editedCount(count: count)
                rows.append(MTADRow(id: id, kind: .peer(peer: item.peer, text: text, label: mtAntiDeleteDate(item.summary.lastTime, presentationData: presentationData), removeTitle: MTStrings.AntiDelete.History.clear)))
                let peerId = item.peer.id
                model.tap[id] = {
                    (weakController?.navigationController as? NavigationController)?.pushViewController(mtMakeAntiDeleteChatHistoryController(context: context, kind: kind, peerId: peerId))
                }
                model.remove[id] = {
                    mtConfirmClear(context: context, controller: weakController, kind: kind, peerIds: [peerId])
                }
            }
            model.sections.append(MTADSection(id: "group.\(group.rawValue)", rows: rows))
        }

        if folder == nil && !items.isEmpty {
            var rows: [MTADRow] = []
            for filter in filters {
                guard case let .filter(id, title, emoticon, filterData) = filter else {
                    continue
                }
                let members = items.filter { item in
                    var isContact = contacts.contains(item.peer.id)
                    if case let .secretChat(secretChat) = item.peer {
                        isContact = contacts.contains(secretChat.regularPeerId)
                    }
                    return mtFolderContains(filterData, peer: item.peer, isContact: isContact, accountPeerId: context.account.peerId)
                }
                if members.isEmpty {
                    continue
                }
                let rowId = "folder.\(id)"
                let folderTitle = (emoticon.map { $0 + " " } ?? "") + title.text
                let count = members.reduce(0, { $0 + Int($1.summary.count) })
                rows.append(MTADRow(id: rowId, kind: .disclosure(title: folderTitle, label: "\(count)", icon: "Chat/Context Menu/Folder")))
                let peerIds = Set(members.map(\.peer.id))
                model.tap[rowId] = {
                    (weakController?.navigationController as? NavigationController)?.pushViewController(mtMakeAntiDeleteHistoryController(context: context, kind: kind, folder: MTADFolderFilter(title: folderTitle, peerIds: peerIds)))
                }
            }
            if !rows.isEmpty {
                rows.insert(MTADRow(id: "header.folders", kind: .header(MTStrings.AntiDelete.History.folders)), at: 0)
                model.sections.append(MTADSection(id: "folders", rows: rows))
            }
        }

        if folder == nil {
            var actions: [MTADRow] = []
            if total > 0 {
                actions.append(MTADRow(id: "export", kind: .action(title: MTStrings.AntiDelete.History.exportAction, destructive: false)))
                model.tap["export"] = {
                    mtExportHistory(context: context, controller: weakController)
                }
            }
            actions.append(MTADRow(id: "import", kind: .action(title: MTStrings.AntiDelete.History.importAction, destructive: false)))
            model.tap["import"] = {
                mtImportHistory(context: context, controller: weakController)
            }
            if total > 0 {
                actions.append(MTADRow(id: "clear", kind: .action(title: kind == .deleted ? MTStrings.AntiDelete.History.clearDeleted : MTStrings.AntiDelete.History.clearEdited, destructive: true)))
                model.tap["clear"] = {
                    mtConfirmClear(context: context, controller: weakController, kind: kind, peerIds: nil)
                }
            }
            actions.append(MTADRow(id: "actions.footer", kind: .footer(MTStrings.AntiDelete.History.exportFooter)))
            model.sections.append(MTADSection(id: "actions", rows: actions))
        }
        return model
    }

    let controller = mtMakeADListController(context: context, model: model, onSegment: { index in
        segment.set(index)
    })
    weakController = controller
    return controller
}

private func mtConfirmClear(context: AccountContext, controller: ViewController?, kind: MTAntiDeleteLogKind, peerIds: [PeerId]?) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let text: String
    switch kind {
    case .deleted:
        text = MTStrings.AntiDelete.History.clearDeletedText
    case .edited:
        text = MTStrings.AntiDelete.History.clearEditedText
    }
    controller?.present(textAlertController(context: context, title: MTStrings.AntiDelete.History.clearTitle, text: text, actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .destructiveAction, title: MTStrings.AntiDelete.History.clear, action: {
            let _ = MTAntiDeleteOperations.clear(postbox: context.account.postbox, accountId: context.account.id, kind: kind, peerIds: peerIds).start()
        })
    ]), in: .window(.root))
}

// MARK: - Export / import

private func mtExportHistory(context: AccountContext, controller: ViewController?) {
    let _ = (MTAntiDeleteOperations.export(postbox: context.account.postbox, accountId: context.account.id)
    |> deliverOn(MTAntiDeleteAccounts.shared.queue)
    |> map { data -> URL? in
        guard let data else {
            return nil
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mediatok-history-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }
    |> deliverOnMainQueue).start(next: { [weak controller] url in
        guard let url else {
            controller?.present(textAlertController(context: context, title: nil, text: MTStrings.AntiDelete.History.exportFailed, actions: [TextAlertAction(type: .defaultAction, title: context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK, action: {})]), in: .window(.root))
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            // The file is plain text: it does not stay in the temporary folder.
            MTAntiDeleteAccounts.shared.queue.justDispatch {
                let _ = try? FileManager.default.removeItem(at: url)
            }
        }
        MTModalPresenter.presentOnTopmost(activity, preferredRoot: controller?.view.window?.rootViewController)
    })
}

/// Keeps the document picker's delegate alive while the picker is shown.
private final class MTADDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void
    private var keepAlive: MTADDocumentPickerDelegate?

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        super.init()
        self.keepAlive = self
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
        self.keepAlive = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion(nil)
        self.keepAlive = nil
    }
}

private func mtImportHistory(context: AccountContext, controller: ViewController?) {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
    let delegate = MTADDocumentPickerDelegate(completion: { [weak controller] url in
        guard let url else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let showText: (String) -> Void = { text in
            controller?.present(textAlertController(context: context, title: MTStrings.AntiDelete.History.importTitle, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
        }
        let read = Signal<Data?, NoError> { subscriber in
            let data = try? Data(contentsOf: url)
            let _ = try? FileManager.default.removeItem(at: url)
            subscriber.putNext(data)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(MTAntiDeleteAccounts.shared.queue)
        let _ = (read
        |> mapToSignal { data -> Signal<String, NoError> in
            guard let data else {
                return .single(MTStrings.AntiDelete.History.importInvalid)
            }
            switch MTAntiDeleteExportFile.decode(data) {
            case .failure(.invalidFormat):
                return .single(MTStrings.AntiDelete.History.importInvalid)
            case let .failure(.unsupportedVersion(version)):
                return .single(MTStrings.AntiDelete.History.importNewer(version: "\(version)"))
            case let .success(file):
                return MTAntiDeleteOperations.importFile(postbox: context.account.postbox, accountId: context.account.id, file: file)
                |> map { result -> String in
                    return MTStrings.AntiDelete.History.importDone(added: "\(result.added)", skipped: "\(result.skipped)")
                }
            }
        }
        |> deliverOnMainQueue).start(next: { text in
            showText(text)
        })
    })
    picker.delegate = delegate
    MTModalPresenter.presentOnTopmost(picker, preferredRoot: controller?.view.window?.rootViewController)
}

// MARK: - One chat

func mtMakeAntiDeleteChatHistoryController(context: AccountContext, kind: MTAntiDeleteLogKind, peerId: PeerId) -> ViewController {
    let postbox = context.account.postbox
    let accountId = context.account.id
    let pageSize = 50
    let limit = ValuePromise<Int>(pageSize, ignoreRepeated: true)
    weak var weakController: ViewController?

    let _ = MTAntiDeleteOperations.reconcile(postbox: postbox, accountId: accountId, kind: kind, peerId: peerId).start()

    struct Item {
        let entry: MTAntiDeleteLogEntry
        let message: Message?
        let archived: MTAntiDeleteArchivedContent?
    }

    let chatPeer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    let page = combineLatest(MTAntiDeleteIndexStore.logSignal(postbox: postbox, kind: kind, peerId: peerId), limit.get())
    |> mapToSignal { log, limit -> Signal<(Int, [Item]), NoError> in
        let entries = log.newestFirst(offset: 0, limit: limit)
        return postbox.transaction { transaction -> (Int, [Item]) in
            var items: [Item] = []
            for entry in entries {
                let id = MessageId(peerId: peerId, namespace: entry.namespace, id: entry.id)
                if entry.isArchiveOnly {
                    items.append(Item(entry: entry, message: nil, archived: MTAntiDeleteIndexStore.readArchived(transaction, id: id)))
                } else if let message = transaction.getMessage(id) {
                    items.append(Item(entry: entry, message: message, archived: nil))
                }
            }
            return (log.count, items)
        }
    }

    let model = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, chatPeer, page, limit.get())
    |> map { presentationData, chatPeer, page, currentLimit -> MTADScreenModel in
        let (total, items) = page
        let title = chatPeer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? MTStrings.AntiDelete.History.unknownChat
        var model = MTADScreenModel(title: .text(title), sections: [])
        guard let chatPeer else {
            return model
        }
        if items.isEmpty {
            model.sections.append(MTADSection(id: "empty", rows: [MTADRow(id: "empty", kind: .footer(MTStrings.AntiDelete.History.emptyChat))]))
            return model
        }
        var rows: [MTADRow] = [MTADRow(id: "header", kind: .header(kind == .deleted ? MTStrings.AntiDelete.History.deletedCount(count: total) : MTStrings.AntiDelete.History.editedCount(count: total)))]
        for item in items {
            let rowId = "message.\(item.entry.namespace).\(item.entry.id)"
            var rowPeer = chatPeer
            var text = ""
            if let message = item.message {
                if let author = message.author {
                    rowPeer = EnginePeer(author)
                }
                text = message.mtEffectiveText.text
                if text.isEmpty, let token = mtAntiDeleteMediaToken(message.media) {
                    text = mtAntiDeleteMediaTitle(token)
                }
            } else if let archived = item.archived {
                text = archived.text
                if text.isEmpty, let media = archived.mediaDescription {
                    text = mtAntiDeleteMediaTitle(media)
                }
                if let author = archived.authorName, !author.isEmpty {
                    text = author + ": " + text
                }
            }
            text = text.replacingOccurrences(of: "\n", with: " ")
            if text.count > 80 {
                text = String(text.prefix(80)) + "…"
            }
            if kind == .edited {
                text = "✎\(item.entry.count) · " + text
            }
            rows.append(MTADRow(id: rowId, kind: .peer(peer: rowPeer, text: text, label: mtAntiDeleteDate(item.entry.time, presentationData: presentationData), removeTitle: nil)))
            let messageId = MessageId(peerId: peerId, namespace: item.entry.namespace, id: item.entry.id)
            let entry = item.entry
            model.tap[rowId] = {
                mtPresentEntryActions(context: context, controller: weakController, kind: kind, messageId: messageId, entry: entry)
            }
        }
        if total > currentLimit {
            rows.append(MTADRow(id: "more", kind: .action(title: MTStrings.AntiDelete.History.showMore, destructive: false)))
            model.tap["more"] = {
                limit.set(currentLimit + pageSize)
            }
        }
        model.sections.append(MTADSection(id: "messages", rows: rows))
        model.sections.append(MTADSection(id: "actions", rows: [MTADRow(id: "clear", kind: .action(title: kind == .deleted ? MTStrings.AntiDelete.History.clearDeleted : MTStrings.AntiDelete.History.clearEdited, destructive: true))]))
        model.tap["clear"] = {
            mtConfirmClear(context: context, controller: weakController, kind: kind, peerIds: [peerId])
        }
        return model
    }

    let controller = mtMakeADListController(context: context, model: model)
    weakController = controller
    return controller
}

private func mtPresentEntryActions(context: AccountContext, controller: ViewController?, kind: MTAntiDeleteLogKind, messageId: MessageId, entry: MTAntiDeleteLogEntry) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = []
    if !entry.isArchiveOnly {
        items.append(ActionSheetButtonItem(title: MTStrings.AntiDelete.History.openInChat, color: .accent, action: { [weak actionSheet, weak controller] in
            actionSheet?.dismissAnimated()
            if let navigationController = controller?.navigationController as? NavigationController {
                mtOpenMessage(context: context, navigationController: navigationController, messageId: messageId, threadId: entry.threadId)
            }
        }))
    }
    switch kind {
    case .deleted:
        items.append(ActionSheetButtonItem(title: entry.isArchiveOnly ? MTStrings.AntiDelete.History.removeEntry : MTStrings.AntiDelete.History.deleteForMe, color: .destructive, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            let _ = MTAntiDeleteOperations.deleteKept(postbox: context.account.postbox, accountId: context.account.id, messageIds: [messageId]).start()
        }))
    case .edited:
        items.append(ActionSheetButtonItem(title: MTStrings.AntiDelete.History.versions, color: .accent, action: { [weak actionSheet, weak controller] in
            actionSheet?.dismissAnimated()
            (controller?.navigationController as? NavigationController)?.pushViewController(mtMakeEditVersionsController(context: context, messageId: messageId))
        }))
        items.append(ActionSheetButtonItem(title: MTStrings.AntiDelete.History.clearVersions, color: .destructive, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            let _ = MTAntiDeleteOperations.removeEditHistory(postbox: context.account.postbox, accountId: context.account.id, messageIds: [messageId]).start()
        }))
    }
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])
    ])
    controller?.present(actionSheet, in: .window(.root))
}

/// Opens a chat on a message; a forum topic opens inside its topic.
func mtOpenMessage(context: AccountContext, navigationController: NavigationController, messageId: MessageId, threadId: Int64?) {
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: messageId.peerId))
    |> deliverOnMainQueue).start(next: { peer in
        guard let peer else {
            return
        }
        if let threadId, peer._asPeer().isForum {
            let _ = context.sharedContext.navigateToForumThread(context: context, peerId: peer.id, threadId: threadId, messageId: messageId, navigationController: navigationController, activateInput: nil, scrollToEndIfExists: false, keepStack: .always, animated: true).start()
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always, useExisting: true))
    })
}
