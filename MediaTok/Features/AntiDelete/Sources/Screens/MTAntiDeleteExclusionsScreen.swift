import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatListUI
import LocalizedPeerData
import MTCore
import MTFeaturesShared

// «Исключения»: kinds of chats (groups, bots, channels), chats picked by hand, folders of THIS
// account. Folder membership is computed by the app (category folders included) and kept in an
// account setting the notification service reads too; it follows folder changes while the
// account runs and is refreshed when the app comes back.

enum MTAntiDeleteFolderSync {
    private static var started: [AccountRecordId: Disposable] = [:]
    private static var activeAccountsDisposable: Disposable?

    /// Recomputes the chats of the excluded folders of one account.
    static func sync(context: AccountContext) -> Signal<Never, NoError> {
        let account = context.account.id.mt
        let folderIds = MTAntiDeleteSettings.excludedFolders.value(for: account)
        if folderIds.isEmpty {
            return Signal { subscriber in
                if !MTAntiDeleteSettings.excludedFolderPeers.value(for: account).isEmpty {
                    MTAntiDeleteSettings.excludedFolderPeers.set([], for: account)
                }
                subscriber.putCompletion()
                return EmptyDisposable
            }
        }
        let accountPeerId = context.account.peerId
        let postbox = context.account.postbox
        return context.engine.peers.currentChatListFilters()
        |> take(1)
        |> mapToSignal { filters -> Signal<Set<MTPeerKey>, NoError> in
            var selected: [ChatListFilterData] = []
            for filter in filters {
                if case let .filter(id, _, _, data) = filter, folderIds.contains(id) {
                    selected.append(data)
                }
            }
            return postbox.transaction { transaction -> Set<MTPeerKey> in
                var result = Set<MTPeerKey>()
                for var data in selected {
                    // Membership must not change on every read or mute.
                    data.excludeRead = false
                    data.excludeMuted = false
                    let predicate = chatListFilterPredicate(filter: data, accountPeerId: accountPeerId)
                    for peer in transaction.getChatListPeers(groupId: .root, filterPredicate: predicate, additionalFilter: nil) {
                        result.insert(peer.id.mtKey)
                    }
                    if !data.excludeArchived {
                        for peer in transaction.getChatListPeers(groupId: Namespaces.PeerGroup.archive, filterPredicate: predicate, additionalFilter: nil) {
                            result.insert(peer.id.mtKey)
                        }
                    }
                    for peerId in data.includePeers.peers + data.includePeers.pinnedPeers {
                        result.insert(peerId.mtKey)
                    }
                }
                return result
            }
        }
        |> deliverOn(MTAntiDeleteAccounts.shared.queue)
        |> map { peers -> Void in
            if MTAntiDeleteSettings.excludedFolderPeers.value(for: account) != peers {
                MTAntiDeleteSettings.excludedFolderPeers.set(peers, for: account)
            }
            return Void()
        }
        |> ignoreValues
    }

    /// Follows the folders and the excluded-folder setting of every running account (main thread).
    static func start(sharedContext: SharedAccountContext) {
        if MTAntiDeleteFolderSync.activeAccountsDisposable != nil {
            return
        }
        MTAntiDeleteFolderSync.activeAccountsDisposable = (sharedContext.activeAccountContexts
        |> deliverOnMainQueue).start(next: { accounts in
            var alive = Set<AccountRecordId>()
            for (id, context, _) in accounts.accounts {
                alive.insert(id)
                if MTAntiDeleteFolderSync.started[id] != nil {
                    continue
                }
                let trigger = combineLatest(context.engine.peers.updatedChatListFilters(), MTAntiDeleteSettings.excludedFolders.signal(for: id.mt))
                // A burst of folder updates becomes one recomputation (the previous wait is dropped).
                MTAntiDeleteFolderSync.started[id] = (trigger
                |> mapToSignal { _ -> Signal<Never, NoError> in
                    return Signal<Void, NoError>.single(Void())
                    |> delay(1.0, queue: MTAntiDeleteAccounts.shared.queue)
                    |> mapToSignal { _ -> Signal<Never, NoError> in
                        return MTAntiDeleteFolderSync.sync(context: context)
                    }
                }).start()
            }
            for (id, disposable) in MTAntiDeleteFolderSync.started where !alive.contains(id) {
                disposable.dispose()
                MTAntiDeleteFolderSync.started.removeValue(forKey: id)
            }
        })
    }

    /// Foreground refresh: chats move between category folders without a folder change.
    static func refreshAll(sharedContext: SharedAccountContext) -> Signal<Never, NoError> {
        return sharedContext.activeAccountContexts
        |> take(1)
        |> mapToSignal { accounts -> Signal<Never, NoError> in
            var signal: Signal<Never, NoError> = .complete()
            for (_, context, _) in accounts.accounts {
                signal = signal |> then(MTAntiDeleteFolderSync.sync(context: context))
            }
            return signal
        }
    }
}

func mtMakeAntiDeleteExclusionsController(context: AccountContext) -> ViewController {
    let account = context.account.id.mt
    weak var weakController: ViewController?

    let peers = MTAntiDeleteSettings.excludedPeers.signal(for: account)
    |> mapToSignal { keys -> Signal<[EnginePeer], NoError> in
        let ids = keys.sorted().map { PeerId(mtKey: $0) }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { result -> [EnginePeer] in
            return ids.compactMap { id in
                return result[id] ?? nil
            }
        }
    }

    // A folder hidden from the app (a locked secret folder) is not listed; an exclusion already set
    // on it stays in force (the folder sync reads every folder).
    let model = combineLatest(queue: .mainQueue(), MTSettingsStore.shared.revision, peers, mtChatListFolders(context.engine.peers.updatedChatListFilters(), context: context))
    |> map { _, peers, filters -> MTADScreenModel in
        var model = MTADScreenModel(title: .text(MTStrings.AntiDelete.Exclusions.title), sections: [])

        let kinds: [(id: String, title: String, setting: MTSetting<Bool>)] = [
            ("groups", MTStrings.AntiDelete.Exclusions.groups, MTAntiDeleteSettings.excludeGroups),
            ("bots", MTStrings.AntiDelete.Exclusions.bots, MTAntiDeleteSettings.excludeBots),
            ("channels", MTStrings.AntiDelete.Exclusions.channels, MTAntiDeleteSettings.excludeChannels)
        ]
        var kindRows: [MTADRow] = [MTADRow(id: "kinds.header", kind: .header(MTStrings.AntiDelete.Exclusions.kindsHeader))]
        for item in kinds {
            kindRows.append(MTADRow(id: "kind.\(item.id)", kind: .toggle(title: item.title, value: item.setting.value)))
            let setting = item.setting
            model.toggle["kind.\(item.id)"] = { value in
                setting.set(value)
            }
        }
        kindRows.append(MTADRow(id: "kind.edits", kind: .toggle(title: MTStrings.AntiDelete.Exclusions.editsInExclusions, value: MTAntiDeleteSettings.editsInExclusions.value)))
        model.toggle["kind.edits"] = { value in
            MTAntiDeleteSettings.editsInExclusions.set(value)
        }
        kindRows.append(MTADRow(id: "kinds.footer", kind: .footer(MTStrings.AntiDelete.Exclusions.kindsFooter)))
        model.sections.append(MTADSection(id: "kinds", rows: kindRows))

        var chatRows: [MTADRow] = [MTADRow(id: "chats.header", kind: .header(MTStrings.AntiDelete.Exclusions.chatsHeader))]
        chatRows.append(MTADRow(id: "chats.add", kind: .action(title: MTStrings.AntiDelete.Exclusions.addChat, destructive: false)))
        model.tap["chats.add"] = {
            let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSavedMessages, .doNotSearchMessages], hasContactSelector: false, title: MTStrings.AntiDelete.Exclusions.addChat))
            controller.peerSelected = { [weak controller] peer, _ in
                var current = MTAntiDeleteSettings.excludedPeers.value(for: account)
                current.insert(peer.id.mtKey)
                MTAntiDeleteSettings.excludedPeers.set(current, for: account)
                controller?.dismiss()
            }
            (weakController?.navigationController as? NavigationController)?.pushViewController(controller)
        }
        for peer in peers {
            let rowId = "chat.\(peer.id.mtKey.stringValue)"
            chatRows.append(MTADRow(id: rowId, kind: .peer(peer: peer, text: "", label: "", removeTitle: MTStrings.AntiDelete.Exclusions.remove)))
            let key = peer.id.mtKey
            model.remove[rowId] = {
                var current = MTAntiDeleteSettings.excludedPeers.value(for: account)
                current.remove(key)
                MTAntiDeleteSettings.excludedPeers.set(current, for: account)
            }
        }
        chatRows.append(MTADRow(id: "chats.footer", kind: .footer(MTStrings.AntiDelete.Exclusions.chatsFooter)))
        model.sections.append(MTADSection(id: "chats", rows: chatRows))

        var folderRows: [MTADRow] = [MTADRow(id: "folders.header", kind: .header(MTStrings.AntiDelete.Exclusions.foldersHeader))]
        let excludedFolders = MTAntiDeleteSettings.excludedFolders.value(for: account)
        var hasFolders = false
        for filter in filters {
            guard case let .filter(id, title, emoticon, _) = filter else {
                continue
            }
            hasFolders = true
            let rowId = "folder.\(id)"
            folderRows.append(MTADRow(id: rowId, kind: .toggle(title: (emoticon.map { $0 + " " } ?? "") + title.text, value: excludedFolders.contains(id))))
            model.toggle[rowId] = { value in
                var current = MTAntiDeleteSettings.excludedFolders.value(for: account)
                if value {
                    current.insert(id)
                } else {
                    current.remove(id)
                }
                MTAntiDeleteSettings.excludedFolders.set(current, for: account)
                let _ = MTAntiDeleteFolderSync.sync(context: context).start()
            }
        }
        folderRows.append(MTADRow(id: "folders.footer", kind: .footer(hasFolders ? MTStrings.AntiDelete.Exclusions.foldersFooter : MTStrings.AntiDelete.Exclusions.foldersEmpty)))
        model.sections.append(MTADSection(id: "folders", rows: folderRows))
        return model
    }

    let controller = mtMakeADListController(context: context, model: model)
    weakController = controller
    return controller
}
