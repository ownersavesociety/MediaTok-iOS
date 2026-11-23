import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import LocalizedPeerData
import AccountContext
import ContextUI
import AppBundle
import UndoUI
import MTCore
import MTHooks
import MTFeaturesShared

/// Toast at the bottom of the current screen.
func mtGhostToast(context: AccountContext, text: String) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in
        return false
    }), on: .root)
}

private func mtGhostMenuIcon(_ name: String) -> (PresentationTheme) -> UIImage? {
    return { theme in
        return generateTintedImage(image: UIImage(bundleImageName: name), color: theme.contextMenu.primaryColor)
    }
}

/// «Прочитать» in the menus of messages, stories and media, and the ghost-mode items of a profile's
/// «…» menu («Исключения», «Подглядеть онлайн»).
enum MTGhostMenuItems {
    static func register() {
        MTMessageMenuHooks.items.register({ menuContext in
            return MTGhostMenuItems.messageItems(menuContext)
        }, order: 100)
        MTStoryHooks.menuItems.register({ menuContext in
            return MTGhostMenuItems.storyItems(menuContext)
        }, order: 100)
        MTGalleryHooks.menuItems.register({ menuContext in
            return MTGhostMenuItems.galleryItems(menuContext)
        }, order: 100)
        MTPeerInfoHooks.menuItems.register({ peerInfoContext in
            return MTGhostMenuItems.profileItems(peerInfoContext)
        }, order: 100)
    }

    // MARK: Message

    private static func messageItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        let context = menuContext.context
        let account = context.account.id.mt
        guard let message = menuContext.messages.max(by: { $0.id.id < $1.id.id }), message.flags.contains(.Incoming) else {
            return []
        }
        let peerId = message.id.peerId
        if peerId.namespace == Namespaces.Peer.SecretChat {
            if message.id.namespace != Namespaces.Message.SecretIncoming {
                return []
            }
        } else if message.id.namespace != Namespaces.Message.Cloud {
            return []
        }
        if !MTGhostPolicy.hides(.readReceipts, peerId: peerId, account: account) {
            return []
        }
        let threadId = menuContext.chatLocation.threadId
        let key = peerId.mtGhostReadKey(threadId: threadId)
        // Known to be read on the server already: nothing to send (no flag threaded through the menu's data).
        if peerId.namespace != Namespaces.Peer.SecretChat, let serverMax = MTGhostReadLedger.shared.serverReadMaxId(account: account, key: key), message.id.id <= serverMax {
            return []
        }
        let item = ContextMenuItem.action(ContextMenuActionItem(text: MTStrings.GhostMode.Action.read, icon: mtGhostMenuIcon("Chat/Context Menu/Read"), action: { _, f in
            f(.default)
            let _ = (MTGhostMenuItems.read(context: context, message: message, threadId: threadId)
            |> deliverOnMainQueue).start(next: { success in
                mtGhostToast(context: context, text: success ? MTStrings.GhostMode.Action.readDone : MTStrings.GhostMode.Action.failed)
            })
        }))
        return [MTMessageMenuEntry(position: .top, item: item)]
    }

    /// Reads the chat on the server up to the message (and the message's "listened" mark), then on the
    /// device. The push the local read schedules finds the server ahead and sends nothing.
    static func read(context: AccountContext, message: Message, threadId: Int64?) -> Signal<Bool, NoError> {
        let account = context.account
        let peerId = message.id.peerId
        var contents: Signal<Bool, NoError> = .single(true)
        if message.attributes.contains(where: { $0 is ConsumableContentMessageAttribute }) {
            contents = MTGhostExplicitReads.readContents(account: account, peerId: peerId, messageIds: [message.id.id])
        }
        return MTGhostExplicitReads.readHistory(account: account, peerId: peerId, threadId: threadId, maxId: message.id.id, maxTimestamp: message.timestamp)
        |> mapToSignal { success -> Signal<Bool, NoError> in
            if !success {
                return .single(false)
            }
            let local: Signal<Never, NoError>
            if threadId == nil {
                local = context.engine.messages.applyMaxReadIndexInteractively(index: message.index) |> ignoreValues
            } else {
                local = .complete()
            }
            return local
            |> mapToSignal { _ -> Signal<Bool, NoError> in
            }
            |> then(contents)
        }
    }

    // MARK: Story

    private static func storyItems(_ menuContext: MTStoryMenuContext) -> [ContextMenuItem] {
        let context = menuContext.context
        let account = context.account.id.mt
        let peerId = menuContext.peer.id
        if peerId == context.account.peerId || !MTGhostPolicy.hides(.storyViews, peerId: peerId, account: account) {
            return []
        }
        let storyId = menuContext.storyItem.id
        let isExpired = menuContext.storyItem.expirationTimestamp <= Int32(Date().timeIntervalSince1970)
        return [.action(ContextMenuActionItem(text: MTStrings.GhostMode.Action.readStory, icon: mtGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
            f(.default)
            let _ = (MTGhostExplicitReads.readStory(account: context.account, peerId: peerId, storyId: storyId, isExpired: isExpired)
            |> deliverOnMainQueue).start(next: { success in
                mtGhostToast(context: context, text: success ? MTStrings.GhostMode.Action.readStoryDone : MTStrings.GhostMode.Action.failed)
            })
        }))]
    }

    // MARK: Gallery (self-destructing media)

    private static func galleryItems(_ menuContext: MTGalleryMenuContext) -> [ContextMenuItem] {
        let context = menuContext.context
        let account = context.account.id.mt
        guard let message = menuContext.message, message.flags.contains(.Incoming), message.mtRawContainsSecretMedia else { // raw: kept media opens in the regular gallery (MTRestrictionHooks.secretMediaDisplay)
            return []
        }
        let peerId = message.id.peerId
        // Secret chats report "opened" through their own layer, which an explicit read here can
        // not reach; ghost mode keeps that report on the device (`.messageContents`).
        if peerId.namespace == Namespaces.Peer.SecretChat || message.id.namespace != Namespaces.Message.Cloud {
            return []
        }
        if !MTGhostPolicy.hides(.readReceipts, peerId: peerId, account: account) {
            return []
        }
        let messageId = message.id
        return [.action(ContextMenuActionItem(text: MTStrings.GhostMode.Action.readMedia, icon: mtGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
            f(.default)
            let _ = (MTGhostExplicitReads.readContents(account: context.account, peerId: peerId, messageIds: [messageId.id])
            |> deliverOnMainQueue).start(next: { success in
                mtGhostToast(context: context, text: success ? MTStrings.GhostMode.Action.readMediaDone : MTStrings.GhostMode.Action.failed)
            })
        }))]
    }

    // MARK: Profile

    private static func profileItems(_ peerInfoContext: MTPeerInfoContext) -> [ContextMenuItem] {
        if peerInfoContext.isSettings {
            return []
        }
        let context = peerInfoContext.context
        let account = context.account.id.mt
        let peer = peerInfoContext.peer
        if peer.id == context.account.peerId {
            return []
        }
        MTGhostPeerTraits.shared.learn(peer, account: account)
        var items: [ContextMenuItem] = []

        let explicit = MTGhostPolicy.explicitException(for: peer.id, account: account)
        let source = MTGhostPolicy.exceptionSource(for: peer.id, account: account)
        if MTGhostPolicy.isEnabled(account) || explicit != nil {
            let key = peer.id.mtGhostKey
            let navigationController = peerInfoContext.controller?.navigationController as? NavigationController
            switch source {
            case .explicit:
                items.append(.action(ContextMenuActionItem(text: MTStrings.GhostMode.Profile.editException, icon: mtGhostMenuIcon("Chat/Context Menu/Settings"), action: { _, f in
                    f(.default)
                    navigationController?.pushViewController(mtGhostExceptionController(context: context, peerId: peer.id))
                })))
                items.append(.action(ContextMenuActionItem(text: MTStrings.GhostMode.Profile.removeException, textColor: .destructive, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor)
                }, action: { _, f in
                    f(.default)
                    mtGhostUpdateExceptions(account: account) { exceptions in
                        exceptions.removeValue(forKey: key)
                    }
                    mtGhostToast(context: context, text: MTStrings.GhostMode.Profile.removed)
                })))
            case .type, .folder:
                // Excepted through its type or a folder: «Убрать» pulls this one chat back into ghost mode.
                items.append(.action(ContextMenuActionItem(text: MTStrings.GhostMode.Profile.removeException, icon: mtGhostMenuIcon("Chat/Context Menu/EyeLocked"), action: { _, f in
                    f(.default)
                    mtGhostUpdateExceptions(account: account) { exceptions in
                        exceptions[key] = .forcedGhost
                    }
                    mtGhostToast(context: context, text: MTStrings.GhostMode.Profile.forced)
                })))
            case .forced:
                items.append(.action(ContextMenuActionItem(text: MTStrings.GhostMode.Profile.restoreException, icon: mtGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
                    f(.default)
                    mtGhostUpdateExceptions(account: account) { exceptions in
                        exceptions.removeValue(forKey: key)
                    }
                    mtGhostToast(context: context, text: MTStrings.GhostMode.Profile.added)
                })))
            case .none:
                items.append(.action(ContextMenuActionItem(text: MTStrings.GhostMode.Profile.addException, icon: mtGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
                    f(.default)
                    mtGhostUpdateExceptions(account: account) { exceptions in
                        exceptions[key] = MTGhostException()
                    }
                    mtGhostToast(context: context, text: MTStrings.GhostMode.Profile.added)
                })))
            }
        }

        if case let .user(user) = peer, user.botInfo == nil, !user.flags.contains(.isSupport), !user.isDeleted {
            items.append(.action(ContextMenuActionItem(text: MTStrings.GhostMode.Profile.peek, icon: mtGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
                f(.default)
                let _ = (MTGhostPeekOnline.peek(context: context, peerId: user.id)
                |> deliverOnMainQueue).start(next: { result in
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    let name = EnginePeer.user(user).compactDisplayTitle
                    switch result {
                    case let .presence(presence):
                        if let presence = presence {
                            let (status, _) = stringAndActivityForUserPresence(strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, presence: presence, relativeTo: Int32(Date().timeIntervalSince1970))
                            mtGhostToast(context: context, text: MTStrings.GhostMode.Profile.peekResult(name: name, status: status))
                        } else {
                            mtGhostToast(context: context, text: MTStrings.GhostMode.Profile.peekHidden(name: name))
                        }
                    case .failed:
                        mtGhostToast(context: context, text: MTStrings.GhostMode.Action.failed)
                    }
                })
            })))
        }
        return items
    }
}
