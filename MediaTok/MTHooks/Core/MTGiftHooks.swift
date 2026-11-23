// Compiled into TelegramCore (filegroup //MediaTok/MTHooks:TelegramCoreHookSources).
// Profile gifts: features may add local-only gifts to a profile's list (fake gifts on the
// user's own profile) and handle actions on them without the network.

import Foundation
import Postbox
import SwiftSignalKit
import MTCore

public struct MTProfileGiftsQuery {
    public let account: Account
    public let peerId: PeerId
    public let collectionId: Int32?
}

public enum MTProfileGiftAction {
    case setSavedToProfile(Bool)
    case setPinnedToTop(Bool)
}

public enum MTGiftHooks {
    /// Transformer of the state a profile's gift list publishes (called on every state push).
    public static let profileGifts = MTHookPoint<(inout ProfileGiftsContext.State, MTProfileGiftsQuery) -> Void>("gifts.profileGifts")

    /// Policy: `true` = the feature handled the action for this gift locally; upstream does not
    /// call the network and re-publishes the state.
    public static let localGiftAction = MTHookPoint<(StarGiftReference, MTProfileGiftAction, MTProfileGiftsQuery) -> Bool>("gifts.localGiftAction")

    /// Policy (any `true`): the profile has local-only gifts, so its «Gifts» tab is shown although
    /// the server counts none (own profile, PeerInfoData). Asked on every update of the profile's
    /// data, possibly off the main thread: answer from memory.
    public static let hasLocalGifts = MTHookPoint<(Account, PeerId) -> Bool>("gifts.hasLocalGifts")

    /// Policy (any `true`): the gift is local-only. It takes no slot of the server's pin limit and is
    /// never sent to the server in the pinned list. Main thread or the list's queue: answer from memory.
    public static let isLocalGift = MTHookPoint<(StarGiftReference, Account) -> Bool>("gifts.isLocalGift")

    /// Every live profile gift list (`ProfileGiftsContext`) publishes its state again, through
    /// `profileGifts` — call after local gifts were added, changed or removed. Any thread.
    public static func invalidate() {
        mtProfileGiftsInvalidations.putNext(Void())
    }
}

private let mtProfileGiftsInvalidations = ValuePipe<Void>()

/// MediaTok hook target: PeerInfoData — the own profile's «Gifts» tab without gifts on the server.
public func mtProfileHasLocalGifts(account: Account, peerId: PeerId) -> Bool {
    if MTGiftHooks.hasLocalGifts.isEmpty {
        return false
    }
    for handler in MTGiftHooks.hasLocalGifts.handlers {
        if handler(account, peerId) {
            return true
        }
    }
    return false
}

/// MediaTok hook target: PeerInfoData — the own profile's data is published again when its local-only
/// gifts change (`MTGiftHooks.invalidate()`), so the «Gifts» tab appears with the first one and goes
/// with the last one while the profile is open. Any other profile: `signal` as is.
public func mtRepublishOnLocalGiftsChange<T>(_ signal: Signal<T, NoError>, account: Account, peerId: PeerId) -> Signal<T, NoError> {
    if MTGiftHooks.hasLocalGifts.isEmpty {
        return signal
    }
    let changes: Signal<Void, NoError> = .single(Void()) |> then(mtProfileGiftsInvalidations.signal())
    return combineLatest(signal, changes)
    |> map { value, _ -> T in
        return value
    }
}

/// MediaTok hook target: the pin limit of a profile's gift list (GiftsListView, PeerInfoGiftsPaneNode)
/// — `true` = a local-only gift (no server pin slot).
public func mtIsLocalProfileGift(_ reference: StarGiftReference?, account: Account) -> Bool {
    guard let reference, !MTGiftHooks.isLocalGift.isEmpty else {
        return false
    }
    for handler in MTGiftHooks.isLocalGift.handlers {
        if handler(reference, account) {
            return true
        }
    }
    return false
}

/// The pinned gifts that count against the server's limit (local-only gifts do not).
public func mtServerPinnedCount(_ references: [StarGiftReference], account: Account) -> Int {
    if MTGiftHooks.isLocalGift.isEmpty {
        return references.count
    }
    return references.filter { !mtIsLocalProfileGift($0, account: account) }.count
}

/// The first gifts of a list as the pinned order takes them: up to `maxCount` that count against the
/// server's limit, local-only gifts among them without taking a slot (upstream: `prefix(maxCount)`).
public func mtPinnedPrefix(_ gifts: [ProfileGiftsContext.State.StarGift], maxCount: Int, account: Account) -> [ProfileGiftsContext.State.StarGift] {
    if MTGiftHooks.isLocalGift.isEmpty {
        return Array(gifts.prefix(maxCount))
    }
    var result: [ProfileGiftsContext.State.StarGift] = []
    var serverCount = 0
    for gift in gifts {
        if mtIsLocalProfileGift(gift.reference, account: account) {
            result.append(gift)
            continue
        }
        if serverCount >= maxCount {
            break
        }
        serverCount += 1
        result.append(gift)
    }
    return result
}

/// MediaTok hook target: `ProfileGiftsContextImpl.updatePinnedToTopStarGifts` — the new pinned list's
/// local-only gifts are pinned / unpinned by the feature (`localGiftAction`), and only the others
/// go on to the server. `currentlyPinned` = the published state's pinned gifts (local ones included).
func mtSplitLocalPinnedGifts(_ references: [StarGiftReference], currentlyPinned: [StarGiftReference], account: Account, peerId: PeerId, collectionId: Int32?) -> [StarGiftReference] {
    if MTGiftHooks.isLocalGift.isEmpty || MTGiftHooks.localGiftAction.isEmpty {
        return references
    }
    var server: [StarGiftReference] = []
    let wasPinned = Set(currentlyPinned)
    for reference in references {
        if mtIsLocalProfileGift(reference, account: account) {
            if !wasPinned.contains(reference) {
                let _ = mtHandleLocalGiftAction(reference, action: .setPinnedToTop(true), account: account, peerId: peerId, collectionId: collectionId)
            }
        } else {
            server.append(reference)
        }
    }
    let kept = Set(references)
    for reference in currentlyPinned where !kept.contains(reference) && mtIsLocalProfileGift(reference, account: account) {
        let _ = mtHandleLocalGiftAction(reference, action: .setPinnedToTop(false), account: account, peerId: peerId, collectionId: collectionId)
    }
    return server
}

/// MediaTok hook target: `ProfileGiftsContextImpl.init`. `republish` runs on the context's queue after
/// `MTGiftHooks.invalidate()`. Nil — nothing subscribed — while no feature transforms profile gifts.
func mtObserveProfileGiftsInvalidation(queue: Queue, _ republish: @escaping () -> Void) -> Disposable? {
    if MTGiftHooks.profileGifts.isEmpty {
        return nil
    }
    return mtProfileGiftsInvalidations.signal().start(next: { _ in
        queue.async {
            republish()
        }
    })
}

func mtTransformProfileGifts(_ state: inout ProfileGiftsContext.State, account: Account, peerId: PeerId, collectionId: Int32?) {
    if MTGiftHooks.profileGifts.isEmpty {
        return
    }
    let query = MTProfileGiftsQuery(account: account, peerId: peerId, collectionId: collectionId)
    for handler in MTGiftHooks.profileGifts.handlers {
        handler(&state, query)
    }
}

func mtHandleLocalGiftAction(_ reference: StarGiftReference, action: MTProfileGiftAction, account: Account, peerId: PeerId, collectionId: Int32?) -> Bool {
    if MTGiftHooks.localGiftAction.isEmpty {
        return false
    }
    let query = MTProfileGiftsQuery(account: account, peerId: peerId, collectionId: collectionId)
    for handler in MTGiftHooks.localGiftAction.handlers {
        if handler(reference, action, query) {
            return true
        }
    }
    return false
}
