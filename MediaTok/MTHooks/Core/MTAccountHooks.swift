// Compiled into TelegramCore (filegroup //MediaTok/MTHooks:TelegramCoreHookSources).
// Account lifecycle points. Called from Account.swift / AccountManager.swift.

import Foundation
import Postbox
import SwiftSignalKit
import MTCore

/// What a feature learns when an account starts in this process (app or extension).
public struct MTAccountStartContext {
    public let id: AccountRecordId
    public let peerId: PeerId
    public let basePath: String
    /// True for accounts started only to finish a logout or for a short extension task.
    public let isSupplementary: Bool
    public let postbox: Postbox
    public let network: Network
}

public enum MTAccountHooks {
    /// Observer. An account's state machinery is about to start; its MediaTok settings
    /// (`MTAccountSetting`) are already loaded. Runs on the thread that creates the account.
    public static let accountWillStart = MTHookPoint<(MTAccountStartContext) -> Void>("account.willStart")

    /// Observer. The account is being removed (logged out); its directory is deleted afterwards.
    public static let accountWillBeRemoved = MTHookPoint<(AccountRecordId) -> Void>("account.willBeRemoved")

    /// The record id of the account whose own peer is `accountPeerId`, once it started in this
    /// process. Lets handlers that only get an account peer id (Core points) reach
    /// account-scoped settings: `MTAccountSetting.value(for: id.mt)`.
    public static func accountId(forAccountPeerId accountPeerId: PeerId) -> AccountRecordId? {
        return mtAccountIdsByPeerId.with { $0[accountPeerId] }
    }
}

private let mtAccountIdsByPeerId = Atomic<[PeerId: AccountRecordId]>(value: [:])

/// MediaTok hook target: first statement of `Account.init`, before the account's managers start.
func mtAccountWillStart(id: AccountRecordId, basePath: String, peerId: PeerId, supplementary: Bool, postbox: Postbox, network: Network) {
    // MTCore bridge: loads <basePath>/mediatok/settings.json and runs account migrations.
    mtCoreAccountDidLoad(id: id, basePath: basePath)
    // Then the migrations of old data keyed by the account's peer: before the handlers below, which
    // may already read what they moved (fake gifts).
    mtCoreAccountPeerDidLoad(id: id, peerId: peerId)
    let _ = mtAccountIdsByPeerId.modify { current in
        var current = current
        current[peerId] = id
        return current
    }
    if MTAccountHooks.accountWillStart.isEmpty {
        return
    }
    let context = MTAccountStartContext(id: id, peerId: peerId, basePath: basePath, isSupplementary: supplementary, postbox: postbox, network: network)
    for handler in MTAccountHooks.accountWillStart.handlers {
        handler(context)
    }
}

/// MediaTok hook target: `standaloneStateManager` (notification service) — no `Account` object
/// exists there, so the account's settings are loaded here, before its network starts.
func mtStandaloneAccountWillStart(id: AccountRecordId, basePath: String, peerId: PeerId) {
    mtCoreAccountDidLoad(id: id, basePath: basePath)
    mtCoreAccountPeerDidLoad(id: id, peerId: peerId)
    let _ = mtAccountIdsByPeerId.modify { current in
        var current = current
        current[peerId] = id
        return current
    }
}

/// MediaTok hook target: an account record is about to be removed for good (logout).
func mtAccountWillBeRemoved(id: AccountRecordId) {
    for handler in MTAccountHooks.accountWillBeRemoved.handlers {
        handler(id)
    }
    let _ = mtAccountIdsByPeerId.modify { current in
        return current.filter { $0.value != id }
    }
    mtCoreAccountWillBeRemoved(id: id)
}

/// The account peer id stored in the account's own Postbox state, for points that are called
/// without one (autoremove timers, interactive deletions without a state manager).
func mtAccountPeerId(transaction: Transaction) -> PeerId? {
    return (transaction.getState() as? AuthorizedAccountState)?.peerId
}
