import Foundation
import UIKit
import SwiftSignalKit
import Postbox
import Display
import TelegramCore
import AccountContext
import ChatListUI
import MTCore
import MTHooks
import MTSettingsUI
import MTFeaturesShared

/// «Секретная папка»: one folder of the account that does not exist for the app while it is locked —
/// no tab, no page to swipe into, no entry in the «Chats» tab's folder menu or in the forward picker
/// (every one of them reads `chatListFilterItems`, filtered through `MTChatListHooks.folders`).
/// «Открыть секретную папку» asks the common check (biometrics with a fallback to the passcode) and
/// takes the user into the folder; going to the background locks it again and the tab disappears.
/// The folder id is per account (folder ids are an account's own).
final class MTSecretFolder {
    static let shared = MTSecretFolder()

    private let unlocked = Atomic<Set<MTAccountID>>(value: Set())
    private let unlockedPromise = ValuePromise<Set<MTAccountID>>(Set(), ignoreRepeated: true)
    private var membershipDisposables: [MTAccountID: Disposable] = [:]

    /// Any thread (row layout reads it).
    func isUnlocked(account: MTAccountID) -> Bool {
        return self.unlocked.with { $0.contains(account) }
    }

    func unlockedSignal(account: MTAccountID) -> Signal<Bool, NoError> {
        return self.unlockedPromise.get()
        |> map { $0.contains(account) }
        |> distinctUntilChanged
    }

    private func update(_ f: (Set<MTAccountID>) -> Set<MTAccountID>) {
        let value = self.unlocked.modify(f)
        self.unlockedPromise.set(value)
    }

    func unlock(account: MTAccountID) {
        self.update { current in
            var current = current
            current.insert(account)
            return current
        }
    }

    func lockAll() {
        self.update { _ in Set() }
    }

    // MARK: Folders

    /// `MTChatListHooks.folders`: the locked secret folder is left out.
    func folders(_ signal: Signal<[ChatListFilter], NoError>, context: AccountContext) -> Signal<[ChatListFilter], NoError> {
        let account = context.account.id.mt
        return combineLatest(signal, MTSecuritySettings.secretFolderId.signal(for: account), self.unlockedSignal(account: account))
        |> map { filters, folderId, isUnlocked -> [ChatListFilter] in
            if folderId == 0 || isUnlocked {
                return filters
            }
            return filters.filter { filter in
                if case let .filter(id, _, _, _) = filter {
                    return id != folderId
                }
                return true
            }
        }
    }

    // MARK: Opening

    /// «Открыть секретную папку»: the check, then the chat list on the folder's tab.
    func open(_ menuContext: MTMenuContext) {
        let context = menuContext.context
        let account = context.account.id.mt
        let folderId = MTSecuritySettings.secretFolderId.value(for: account)
        if folderId == 0 {
            return
        }
        let navigationController = menuContext.navigationController
        MTLocalAuthGate.shared.authenticate(context: context, reason: MTStrings.Security.Auth.reasonFolder, completion: { [weak self, weak navigationController] granted in
            guard let self, granted else {
                return
            }
            let _ = (context.engine.peers.updatedChatListFilters()
            |> take(1)
            |> deliverOnMainQueue).start(next: { filters in
                let exists = filters.contains(where: { filter in
                    if case let .filter(id, _, _, _) = filter {
                        return id == folderId
                    }
                    return false
                })
                if !exists {
                    // The folder was deleted in Telegram: forget it rather than open nothing.
                    MTSecuritySettings.secretFolderId.set(0, for: account)
                    menuContext.presentToast(MTStrings.Security.Folder.deleted)
                    return
                }
                self.unlockAndShow(account: account, folderId: folderId, navigationController: navigationController)
            })
        })
    }

    private func unlockAndShow(account: MTAccountID, folderId: Int32, navigationController: NavigationController?) {
        self.unlock(account: account)
        guard let navigationController else {
            return
        }
        navigationController.popToRoot(animated: true)
        guard let tabBarController = navigationController.viewControllers.first as? TabBarController else {
            return
        }
        for (index, controller) in tabBarController.controllers.enumerated() {
            if let chatListController = controller as? ChatListController {
                tabBarController.selectedIndex = index
                chatListController.navigateToFolder(folderId: folderId, completion: {})
                break
            }
        }
    }

    // MARK: Members (for «Защищать чаты папки»)

    /// Keeps `MTSecuritySharedSettings.secretFolderPeers` equal to the folder's chats while the option is
    /// on (empty otherwise): the notification service and the lists read that snapshot. One live view
    /// of the folder per account, only while the option is on; the setting is written only on change.
    ///
    /// Membership ignores the folder's «exclude read / muted» flags (a chat must not lose its
    /// protection because it was just read) and has no size cap: the live view only says «something
    /// changed», the members come from a full pass over the chat list (root and, unless the folder
    /// excludes it, the archive), at most once in two seconds.
    func startMembership(context: AccountContext) {
        let account = context.account.id.mt
        self.membershipDisposables[account]?.dispose()
        let accountPeerId = context.account.peerId
        let postbox = context.account.postbox
        let viewTracker: AccountViewTracker = context.account.viewTracker
        let members: Signal<Set<MTPeerKey>, NoError> = combineLatest(
            MTSecuritySettings.secretFolderId.signal(for: account),
            MTSecuritySettings.secretFolderProtectChats.signal(for: account),
            context.engine.peers.updatedChatListFilters()
        )
        |> mapToSignal { folderId, protectChats, filters -> Signal<Set<MTPeerKey>, NoError> in
            guard protectChats, folderId != 0 else {
                return .single(Set())
            }
            var folderData: ChatListFilterData?
            for filter in filters {
                if case let .filter(id, _, _, data) = filter, id == folderId {
                    folderData = data
                }
            }
            guard var data = folderData else {
                return .single(Set())
            }
            data.excludeRead = false
            data.excludeMuted = false
            var explicit = Set<MTPeerKey>()
            for peerId in data.includePeers.peers {
                explicit.insert(peerId.mtKey)
            }
            for peerId in data.includePeers.pinnedPeers {
                explicit.insert(peerId.mtKey)
            }
            let predicate = chatListFilterPredicate(filter: data, accountPeerId: accountPeerId)
            var groups: [PeerGroupId] = [.root]
            if !data.excludeArchived {
                groups.append(Namespaces.PeerGroup.archive)
            }
            return viewTracker.tailChatListView(groupId: .root, filterPredicate: predicate, count: 100)
            |> mapToThrottled { _ -> Signal<Set<MTPeerKey>, NoError> in
                return postbox.transaction { transaction -> Set<MTPeerKey> in
                    var result = explicit
                    for groupId in groups {
                        for peer in transaction.getChatListPeers(groupId: groupId, filterPredicate: predicate, additionalFilter: nil) {
                            result.insert(peer.id.mtKey)
                        }
                    }
                    return result
                }
                |> then(Signal<Set<MTPeerKey>, NoError>.complete() |> delay(2.0, queue: Queue.concurrentDefaultQueue()))
            }
        }
        |> distinctUntilChanged
        self.membershipDisposables[account] = (members
        |> deliverOnMainQueue).start(next: { members in
            if MTSecuritySharedSettings.secretFolderPeers.value(for: account) != members {
                MTSecuritySharedSettings.secretFolderPeers.set(members, for: account)
            }
        })
    }

    /// The account's folders for the picker: id and title.
    static func folderChoices(context: AccountContext) -> Signal<[(Int32, String)], NoError> {
        return context.engine.peers.updatedChatListFilters()
        |> map { filters -> [(Int32, String)] in
            var result: [(Int32, String)] = []
            for filter in filters {
                if case let .filter(id, title, _, _) = filter {
                    result.append((id, title.text.isEmpty ? "#\(id)" : title.text))
                }
            }
            return result
        }
    }
}
