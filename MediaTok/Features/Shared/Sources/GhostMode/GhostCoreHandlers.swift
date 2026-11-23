import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import MTCore

/// Handlers of the TelegramCore points: what leaves the device about the user's activity. They run
/// in every process that starts MediaTok (app, notification service, share), on network and
/// Postbox queues, some inside transactions: they read the settings snapshot and memory only.
enum MTGhostCoreHandlers {
    static func register() {
        MTAccountHooks.accountWillStart.register({ context in
            let account = context.id.mt
            MTGhostPeerTraits.shared.accountDidStart(account, postbox: context.postbox)
        })
        MTAccountHooks.accountWillBeRemoved.register({ id in
            let account = id.mt
            MTGhostPeerTraits.shared.accountWillBeRemoved(account)
            MTGhostPresence.shared.accountWillBeRemoved(account)
            MTGhostReadLedger.shared.accountWillBeRemoved(account)
        })

        MTPresenceHooks.onlinePresence.register({ upstream, context in
            return MTGhostPresence.shared.transformOnline(upstream, account: context.accountId.mt)
        })
        MTPresenceHooks.sendTyping.register({ request in
            return MTGhostCoreHandlers.shouldSendTyping(request)
        })
        MTPresenceHooks.sendReadReceipt.register({ request in
            return MTGhostCoreHandlers.shouldSendReadReceipt(request)
        })
        MTPresenceHooks.consumeContent.register({ request in
            return MTGhostCoreHandlers.shouldConsume(request)
        })
        // Inside the transaction that stores (or, for the share extension, Siri and the quick
        // forward, sends) the batch: the chat's peer is known, so a bot is never scheduled.
        MTOutgoingHooks.sendDelay.register({ request in
            return MTGhostCoreHandlers.sendDelay(request)
        }, order: 100)
    }

    private static func account(forAccountPeerId accountPeerId: PeerId?) -> MTAccountID? {
        guard let accountPeerId = accountPeerId, let id = MTAccountHooks.accountId(forAccountPeerId: accountPeerId) else {
            return nil
        }
        return id.mt
    }

    // MARK: «печатает»

    static func shouldSendTyping(_ request: MTTypingRequest) -> Bool? {
        guard let account = MTGhostCoreHandlers.account(forAccountPeerId: request.accountPeerId) else {
            return nil
        }
        MTGhostPeerTraits.shared.learn(request.peer, account: account)
        if !MTGhostPolicy.isEnabled(account) {
            return nil
        }
        let peerId = request.peer.id
        guard let activity = request.activity else {
            // "Stopped typing" only where a start actually went out.
            return MTGhostPresence.shared.takeActivityEnd(for: peerId, account: account) ? nil : false
        }
        if MTGhostPolicy.hides(.typing, peerId: peerId, account: account) {
            let kind = MTGhostActivityKind(activity)
            if !MTGhostPolicy.shownActivities(for: peerId, account: account).contains(kind) {
                return false
            }
        }
        if MTGhostPolicy.hides(.online, peerId: peerId, account: account) {
            // The server relays statuses only from an online account. The first status opens a short
            // online window and is not sent; the next repetition (the activity is re-sent while it
            // lasts) goes out once the account is online. No delayed send racing the presence request.
            let wasOpen = MTGhostPresence.shared.isWindowOpen(account: account)
            MTGhostPresence.shared.openWindow(account: account)
            if !wasOpen {
                return false
            }
        }
        MTGhostPresence.shared.noteActivitySent(to: peerId, account: account)
        return nil
    }

    // MARK: Read receipts

    static func shouldSendReadReceipt(_ request: MTReadReceiptRequest) -> Bool? {
        guard let account = MTGhostCoreHandlers.account(forAccountPeerId: request.accountPeerId) else {
            return nil
        }
        let ledger = MTGhostReadLedger.shared
        let peerId = request.peerId
        switch request.kind {
        case let .history(maxId):
            let key = peerId.mtGhostKey
            if let maxId = maxId, let localMax = ledger.localReadMaxId(account: account, key: key) {
                if maxId <= localMax {
                    // «Прочитать локально»: stays on the device even without ghost mode.
                    ledger.noteKept(account: account, key: key, maxId: maxId, maxTimestamp: 0)
                    return false
                }
                ledger.dropLocalRead(account: account, key: key)
            }
            if !MTGhostPolicy.hides(.readReceipts, peerId: peerId, account: account) {
                // Only worth remembering while ghost mode is on or a kept read is now superseded.
                if MTGhostPolicy.isEnabled(account) || ledger.keptRead(account: account, key: key) != nil {
                    if let maxId = maxId {
                        ledger.noteServerRead(account: account, key: key, maxId: maxId)
                    } else {
                        ledger.noteServerReadSecret(account: account, key: key)
                    }
                }
                return nil
            }
            if let maxId = maxId {
                if let serverMax = ledger.serverReadMaxId(account: account, key: key), maxId <= serverMax {
                    // Already read on the server (an explicit «Прочитать»): nothing new to tell.
                    return false
                }
                ledger.noteKept(account: account, key: key, maxId: maxId, maxTimestamp: 0)
            } else {
                // Secret chats are read by date; the date of the newest read message is not known
                // here, the explicit read takes it from the chat when needed.
                ledger.noteKept(account: account, key: key, maxId: 0, maxTimestamp: Int32(Date().timeIntervalSince1970))
            }
            return false
        case .historyValidation:
            // A validation would replace a local-only read with the server's unread state (and with
            // the server behind, it looped forever). Keep the local state of such chats — only of
            // those: every other chat is checked against the server as usual, ghost mode or not
            // (the check is how unread counters get right after a gap in the history). Reads ghost
            // mode keeps are in the ledger (persisted), so they are covered by the first test.
            if ledger.hasKeptRead(account: account, peerId: peerId) {
                return false
            }
            if ledger.localReadMaxId(account: account, key: peerId.mtGhostKey) != nil {
                return false
            }
            return nil
        case let .thread(threadId, maxId):
            let key = peerId.mtGhostReadKey(threadId: threadId)
            if let localMax = ledger.localReadMaxId(account: account, key: key) {
                if maxId <= localMax {
                    ledger.noteKept(account: account, key: key, maxId: maxId, maxTimestamp: 0)
                    return false
                }
                ledger.dropLocalRead(account: account, key: key)
            }
            if !MTGhostPolicy.hides(.readReceipts, peerId: peerId, account: account) {
                if MTGhostPolicy.isEnabled(account) || ledger.keptRead(account: account, key: key) != nil {
                    ledger.noteServerRead(account: account, key: key, maxId: maxId)
                }
                return nil
            }
            if let serverMax = ledger.serverReadMaxId(account: account, key: key), maxId <= serverMax {
                return false
            }
            ledger.noteKept(account: account, key: key, maxId: maxId, maxTimestamp: 0)
            return false
        case .stories, .storyView:
            return MTGhostPolicy.hides(.storyViews, peerId: peerId, account: account) ? false : nil
        case .messageContents:
            return MTGhostPolicy.hides(.readReceipts, peerId: peerId, account: account) ? false : nil
        }
    }

    // MARK: Listened / opened

    /// Content is consumed on the device as usual in every chat; only the network part is kept:
    /// cloud chats through `synchronizeConsumeMessageContents`, secret chats through their own
    /// `readMessagesContent` operation — both ask `sendReadReceipt` with `.messageContents`.
    /// Here the secret chat's peer is only learned for the exception lists.
    static func shouldConsume(_ request: MTContentConsumptionRequest) -> Bool? {
        let peerId = request.message.id.peerId
        guard peerId.namespace == Namespaces.Peer.SecretChat else {
            return nil
        }
        guard let account = MTGhostCoreHandlers.account(forAccountPeerId: request.accountPeerId) else {
            return nil
        }
        if let peer = request.message.peers[peerId] {
            MTGhostPeerTraits.shared.learn(peer, account: account)
        }
        return nil
    }

    // MARK: Send delay

    static func sendDelay(_ request: MTOutgoingDelayRequest) -> Int32? {
        guard let account = MTGhostCoreHandlers.account(forAccountPeerId: request.accountPeerId) else {
            return nil
        }
        if !MTGhostSettings.sendDelayEnabled.value(for: account) {
            return nil
        }
        if let peer = request.peer {
            MTGhostPeerTraits.shared.learn(peer, account: account)
        }
        if MTSendDelayPolicy.mustSendImmediately(request.attributes) {
            return nil
        }
        // One delay for text and media since 2026-10-27.
        return MTSendDelayPolicy.scheduleTime(account: account, accountPeerId: request.accountPeerId, peerId: request.peerId, peer: request.peer, serverTime: request.serverTime)
    }
}
