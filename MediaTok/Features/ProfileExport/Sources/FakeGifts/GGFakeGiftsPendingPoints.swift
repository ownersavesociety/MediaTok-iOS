import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import GGCore

// Handlers for the two points of MediaTok spec R2 (added by MediaTok, MediaTok/GGHooks/Core/GGGiftHooks.swift):
//   - `GGGiftHooks.hasLocalGifts` — the own profile shows its "Gifts" tab when it has only fake
//     gifts (the tab is decided in the frozen PeerInfoData.swift from the server's gift count);
//   - `GGGiftHooks.invalidate()` — an open own profile re-publishes its gift list after a fake gift
//     was added, edited or deleted (otherwise it updates on its next page load).

enum GGFakeGiftsPendingPoints {
    static func register() {
        GGGiftHooks.hasLocalGifts.register({ account, peerId in
            if peerId != account.peerId {
                GGFakeGiftsStore.shared.checkGlobalGifts(account: account, forPeer: peerId)
                if !GGFakeGiftsStore.shared.remoteGifts(forPeer: peerId).isEmpty {
                    return true
                }
            }
            guard GGFakeGiftsSettings.isEnabled.value else {
                return false
            }
            return !GGFakeGiftsStore.shared.resolvedGifts(accountPeerId: account.peerId, forPeer: peerId).isEmpty
        })
    }

    /// The store published a new list for an account.
    static func storeDidChange() {
        GGGiftHooks.invalidate()
    }
}
