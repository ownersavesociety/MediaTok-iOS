import Foundation
import UIKit
import SwiftSignalKit
import Postbox
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import AppBundle
import ChatListUI
import MTCore
import MTHooks
import MTFeaturesShared

/// Where «Пароль на чаты» (and the chats of a locked secret folder) reach into Telegram — through the
/// points, not through eleven edits of the chat screen:
/// - opening a chat (`openChat`) asks first; a peek or a chat screen reached any other way is covered
///   (`lifecycle`) and asks when it appears; reading stops while the cover is up;
/// - the chat list row shows «Чат защищён» instead of the text, no thumbnails, no author line;
/// - the search leaves the chat's messages out (every tab);
/// - pushes, banners, the widget and Siri — `MTChatProtection` in MTFeaturesShared;
/// - the profile's «…» menu protects / unprotects one chat (unprotecting asks first).
enum MTChatLockHandlers {
    static func register() {
        let lock = MTChatLock.shared

        MTChatScreenHooks.openChat.register({ params, proceed in
            return lock.interceptOpen(params, proceed: proceed)
        }, order: -100)
        MTChatScreenHooks.lifecycle.register({ event, screen in
            lock.screenEvent(event, screen: screen)
        })

        // Lists: first, so that no other preview handler shows the text of a protected chat.
        MTChatListHooks.previewText.register({ row in
            guard MTChatLockHandlers.hidesRow(row) else {
                return nil
            }
            let fontSize = row.context.sharedContext.currentPresentationData.with { $0 }.listsFontSize.itemListBaseFontSize
            return NSAttributedString(string: MTStrings.Security.ChatLock.previewText, font: Font.regular(floor(fontSize * 15.0 / 17.0)), textColor: row.theme.chatList.messageTextColor)
        }, order: -1000)
        MTChatListHooks.hidesMediaPreview.register({ row in
            return MTChatLockHandlers.hidesRow(row)
        })
        MTChatListHooks.hidesLastMessageAuthor.register({ row in
            return MTChatLockHandlers.hidesRow(row)
        })
        MTChatListHooks.hidesSearchMessages.register({ context, message in
            return lock.hidesContentInLists(account: context.account.id.mt, peerId: message.id.peerId)
        })
        // Rows of chats whose protection or folder lock changed are laid out again (the set changes
        // rarely: a chat added to / removed from the list, the folder opened / locked).
        MTChatListHooks.accessoryPeers.register({ context in
            return MTChatLockHandlers.relayoutPeers(context: context)
        })

        MTPeerInfoHooks.menuItems.register({ info in
            return MTChatLockHandlers.profileMenuItems(info)
        })
        // A profile opened outside the chat: its shared media stay covered until the check.
        MTProfileMediaLock.register()
    }

    private static func hidesRow(_ row: MTChatListRowContext) -> Bool {
        guard let peer = row.peer else {
            return false
        }
        let lock = MTChatLock.shared
        lock.notePeer(peer)
        return lock.hidesContentInLists(account: row.context.account.id.mt, peerId: peer.id)
    }

    private static func relayoutPeers(context: AccountContext) -> Signal<Set<EnginePeer.Id>, NoError> {
        let account = context.account.id.mt
        return combineLatest(
            MTSecuritySharedSettings.chatLockEnabled.signal,
            MTSecuritySharedSettings.chatLockPeers.signal(for: account),
            MTSecuritySharedSettings.secretFolderPeers.signal(for: account),
            MTSecretFolder.shared.unlockedSignal(account: account)
        )
        |> map { enabled, peers, folderPeers, folderUnlocked -> Set<EnginePeer.Id> in
            var result = Set<EnginePeer.Id>()
            if enabled {
                for key in peers {
                    result.insert(PeerId(mtKey: key))
                }
            }
            if !folderUnlocked {
                for key in folderPeers {
                    result.insert(PeerId(mtKey: key))
                }
            }
            return result
        }
        |> distinctUntilChanged
    }

    // MARK: Profile menu

    private static func profileMenuItems(_ info: MTPeerInfoContext) -> [ContextMenuItem] {
        guard !info.isSettings, MTSecuritySharedSettings.chatLockEnabled.value, !MTSecuritySharedSettings.chatLockAllChats.value else {
            return []
        }
        let peerId = info.chatPeer?.id ?? info.peer.id
        if peerId == info.context.account.peerId || !MTChatProtection.isLockable(peerId) {
            return []
        }
        let context = info.context
        let account = context.account.id.mt
        let key = peerId.mtKey
        let isProtected = MTSecuritySharedSettings.chatLockPeers.value(for: account).contains(key)
        let title = isProtected ? MTStrings.Security.ChatLock.unprotectChat : MTStrings.Security.ChatLock.protectChat
        return [.action(ContextMenuActionItem(text: title, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Lock"), color: theme.contextMenu.primaryColor)
        }, action: { _, f in
            f(.default)
            let apply: () -> Void = {
                var peers = MTSecuritySharedSettings.chatLockPeers.value(for: account)
                if isProtected {
                    peers.remove(key)
                } else {
                    peers.insert(key)
                }
                MTSecuritySharedSettings.chatLockPeers.set(peers, for: account)
            }
            if isProtected {
                // Taking a chat out of the protection is what an intruder would do: ask first.
                MTLocalAuthGate.shared.authenticate(context: context, reason: MTStrings.Security.Auth.reasonSettings, completion: { granted in
                    if granted {
                        apply()
                    }
                })
            } else {
                apply()
            }
        }))]
    }
}
