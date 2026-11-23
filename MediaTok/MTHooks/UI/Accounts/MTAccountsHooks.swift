// Multi-account: a gate before switching accounts (Face ID) and the account preview in Settings.
// Applied in SharedAccountContext. Hiding accounts from the UI («двойное дно») was removed with the
// feature: nothing changes which accounts Telegram sees.

import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import MTCore

public enum MTAccountsHooks {
    /// Gate before switching to another account. Return `true` to take over: run your check,
    /// then call `proceed()` (which switches without asking again).
    public static let switchGate = MTHookPoint<(AccountRecordId, @escaping () -> Void) -> Bool>("accounts.switchGate")

    /// Policy (any `true`): a long press on another account in Settings shows its menu without the
    /// preview of that account's chat list (the preview would show the account before the switch
    /// gate asked anything). Main thread.
    public static let hidesAccountPreview = MTHookPoint<(AccountRecordId) -> Bool>("accounts.hidesAccountPreview")

    /// `false` while the point is empty (upstream).
    public static func hidesPreview(of id: AccountRecordId) -> Bool {
        if MTAccountsHooks.hidesAccountPreview.isEmpty {
            return false
        }
        for handler in MTAccountsHooks.hidesAccountPreview.handlers {
            if handler(id) {
                return true
            }
        }
        return false
    }

    private static var switchBypassId: AccountRecordId?

    /// Main thread. `true` = a gate took over; the call site returns and `proceed` re-enters it.
    public static func interceptSwitch(to id: AccountRecordId, proceed: @escaping () -> Void) -> Bool {
        if MTAccountsHooks.switchGate.isEmpty {
            return false
        }
        if MTAccountsHooks.switchBypassId == id {
            MTAccountsHooks.switchBypassId = nil
            return false
        }
        let continuation: () -> Void = {
            MTAccountsHooks.switchBypassId = id
            proceed()
        }
        for handler in MTAccountsHooks.switchGate.handlers {
            if handler(id, continuation) {
                return true
            }
        }
        return false
    }
}
