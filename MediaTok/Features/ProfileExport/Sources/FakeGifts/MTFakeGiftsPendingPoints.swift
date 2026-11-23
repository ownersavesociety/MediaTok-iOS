import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import MTCore

// Handlers for the two points of MediaTok spec R2 (added by MediaTok, MediaTok/MTHooks/Core/MTGiftHooks.swift):
//   - `MTGiftHooks.hasLocalGifts` — the own profile shows its "Gifts" tab when it has only fake
//     gifts (the tab is decided in the frozen PeerInfoData.swift from the server's gift count);
//   - `MTGiftHooks.invalidate()` — an open own profile re-publishes its gift list after a fake gift
//     was added, edited or deleted (otherwise it updates on its next page load).

enum MTFakeGiftsPendingPoints {
    static func register() {
        MTGiftHooks.hasLocalGifts.register({ account, peerId in
            if peerId != account.peerId {
                MTFakeGiftsStore.shared.checkGlobalGifts(account: account, forPeer: peerId)
                if !MTFakeGiftsStore.shared.remoteGifts(forPeer: peerId).isEmpty {
                    return true
                }
            }
            guard MTFakeGiftsSettings.isEnabled.value else {
                return false
            }
            return !MTFakeGiftsStore.shared.resolvedGifts(accountPeerId: account.peerId, forPeer: peerId).isEmpty
        })
    }

    /// The store published a new list for an account.
    static func storeDidChange() {
        MTGiftHooks.invalidate()
    }
}
