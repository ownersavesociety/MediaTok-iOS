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
import ChatListUI
import MTCore
import MTHooks
import MTFeaturesShared

/// The profile's «…» menu (`MTPeerInfoHooks.menuItems`): «Удалённые сообщения», «Изменённые
/// сообщения», «Закладки», and excluding this chat from anti-delete. The counts come from the
/// account's summaries in memory, the namespace from the index (secret chats included).
enum MTAntiDeletePeerMenu {
    private static func icon(_ name: String) -> (PresentationTheme) -> UIImage? {
        return { theme in
            return generateTintedImage(image: UIImage(bundleImageName: name), color: theme.contextMenu.primaryColor)
        }
    }

    static func items(_ peerInfo: MTPeerInfoContext) -> [ContextMenuItem] {
        if peerInfo.isSettings {
            return []
        }
        let context = peerInfo.context
        let chatPeerId = (peerInfo.chatPeer ?? peerInfo.peer).id
        let accountId = context.account.id
        var result: [ContextMenuItem] = []

        let push: (ViewController) -> Void = { [weak controller = peerInfo.controller] screen in
            if let navigationController = controller?.navigationController as? NavigationController {
                navigationController.pushViewController(screen)
            } else {
                MTAntiDeleteMessageMenu.rootNavigationController(context)?.pushViewController(screen)
            }
        }

        let deletedCount = MTAntiDeleteAccounts.shared.count(account: accountId, kind: .deleted, peerId: chatPeerId)
        if deletedCount > 0 {
            result.append(.action(ContextMenuActionItem(text: MTStrings.AntiDelete.PeerMenu.deleted(count: deletedCount), icon: MTAntiDeletePeerMenu.icon("Chat/Context Menu/Delete"), action: { _, f in
                f(.dismissWithoutContent)
                push(mtMakeAntiDeleteChatHistoryController(context: context, kind: .deleted, peerId: chatPeerId))
            })))
        }
        let editedCount = MTAntiDeleteAccounts.shared.count(account: accountId, kind: .edited, peerId: chatPeerId)
        if editedCount > 0 {
            result.append(.action(ContextMenuActionItem(text: MTStrings.AntiDelete.PeerMenu.edited(count: editedCount), icon: MTAntiDeletePeerMenu.icon("Chat/Context Menu/Edit"), action: { _, f in
                f(.dismissWithoutContent)
                push(mtMakeAntiDeleteChatHistoryController(context: context, kind: .edited, peerId: chatPeerId))
            })))
        }
        if MTBookmarkSettings.enabled.value && MTAntiDeleteAccounts.shared.hasBookmarks(account: accountId, peerId: chatPeerId) {
            result.append(.action(ContextMenuActionItem(text: MTStrings.Bookmarks.PeerMenu.title, icon: MTAntiDeletePeerMenu.icon("Chat/Context Menu/ReadingList"), action: { _, f in
                f(.dismissWithoutContent)
                push(mtMakeBookmarksController(context: context, peerId: chatPeerId))
            })))
        }

        let capturing = MTAntiDeleteSettings.enabled.value || MTAntiDeleteSettings.keepOwn.value || MTAntiDeleteSettings.keepSelfDestructing.value || MTAntiDeleteSettings.editHistory.value
        if capturing && chatPeerId != context.account.peerId {
            let key = chatPeerId.mtKey
            let excluded = MTAntiDeleteSettings.excludedPeers.value(for: accountId.mt).contains(key)
            result.append(.action(ContextMenuActionItem(text: excluded ? MTStrings.AntiDelete.PeerMenu.include : MTStrings.AntiDelete.PeerMenu.exclude, icon: MTAntiDeletePeerMenu.icon("Chat/Context Menu/Ban"), action: { _, f in
                f(.dismissWithoutContent)
                var peers = MTAntiDeleteSettings.excludedPeers.value(for: accountId.mt)
                if peers.contains(key) {
                    peers.remove(key)
                } else {
                    peers.insert(key)
                }
                MTAntiDeleteSettings.excludedPeers.set(peers, for: accountId.mt)
            })))
        }
        return result
    }
}

/// `MTChatListHooks.previewText`: the row shows the local edit of the last message, like the bubble.
enum MTAntiDeleteChatList {
    static func previewText(_ row: MTChatListRowContext) -> NSAttributedString? {
        guard let message = row.messages.first?._asMessage() else {
            return nil
        }
        var localEdit: MTLocalEditMessageAttribute?
        for attribute in message.attributes {
            if let attribute = attribute as? MTLocalEditMessageAttribute, attribute.isActive {
                localEdit = attribute
            }
        }
        guard let localEdit else {
            return nil
        }
        let presentationData = row.context.sharedContext.currentPresentationData.with { $0 }
        let font = Font.regular(floor(presentationData.listsFontSize.itemListBaseFontSize * 15.0 / 17.0))
        return NSAttributedString(string: localEdit.text.replacingOccurrences(of: "\n", with: " "), font: font, textColor: row.theme.chatList.messageTextColor)
    }
}
