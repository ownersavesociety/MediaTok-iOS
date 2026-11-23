// Compiled into TelegramCore (filegroup //MediaTok/MTHooks:TelegramCoreHookSources).
// The account's Stars balance as features show it («Локальные звёзды»: a number shown on this
// device only). TON balances are never touched.

import Foundation
import SwiftSignalKit
import MTCore

public enum MTStarsHooks {
    /// Policy: the Stars balance shown instead of the real one (first non-nil wins; nil = the real
    /// one). Asked on the main queue on every publish of a Stars balance (`StarsContext`) and on
    /// every read of its `currentState`: answer from memory.
    public static let displayedBalance = MTHookPoint<(StarsAmount) -> StarsAmount?>("stars.displayedBalance")

    /// Every live Stars balance publishes its state again through `displayedBalance` — call after
    /// the shown balance changed. Any thread.
    public static func invalidate() {
        mtStarsBalanceInvalidations.putNext(Void())
    }
}

private let mtStarsBalanceInvalidations = ValuePipe<Void>()

/// MediaTok hook target: `StarsContextImpl` (publish) and `StarsContext.currentState` — the state as
/// features show it. A TON state passes as it is.
func mtDisplayedStarsState(_ state: StarsContext.State, ton: Bool) -> StarsContext.State {
    if ton || MTStarsHooks.displayedBalance.isEmpty {
        return state
    }
    for handler in MTStarsHooks.displayedBalance.handlers {
        if let balance = handler(state.balance) {
            var state = state
            state.balance = balance
            return state
        }
    }
    return state
}

/// MediaTok hook target: `StarsContextImpl.init`. `republish` runs on the main queue after
/// `MTStarsHooks.invalidate()`. Nil — nothing subscribed — for TON and while no feature changes
/// the shown balance.
func mtObserveStarsBalanceInvalidation(ton: Bool, _ republish: @escaping () -> Void) -> Disposable? {
    if ton || MTStarsHooks.displayedBalance.isEmpty {
        return nil
    }
    return mtStarsBalanceInvalidations.signal().start(next: { _ in
        Queue.mainQueue().async {
            republish()
        }
    })
}
