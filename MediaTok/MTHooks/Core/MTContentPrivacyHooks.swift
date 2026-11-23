// Compiled into TelegramCore (filegroup //MediaTok/MTHooks:TelegramCoreHookSources).
// Content of protected chats outside the chat screen (in-app banners, the widget's data, Siri
// reading messages) and the app lock on a cold start. Handlers are registered from
// `GG<Zone>Shared.register()` so that the extensions (Siri) see them too; callers only need
// `import TelegramCore`.

import Foundation
import Postbox
import MTCore

public enum MTContentPrivacyHooks {
    /// Policy (any `true`): the content of this chat must not leave the chat screen — no in-app
    /// banner text, no message in the widget's data, nothing for Siri to read. Asked on the main
    /// thread and in signal maps: answer from settings snapshots.
    public static let hidesContent = MTHookPoint<(AccountRecordId, PeerId) -> Bool>("privacy.hidesContent")

    /// `false` while the point is empty (upstream).
    public static func hidesContent(accountId: AccountRecordId, peerId: PeerId) -> Bool {
        if MTContentPrivacyHooks.hidesContent.isEmpty {
            return false
        }
        for handler in MTContentPrivacyHooks.hidesContent.handlers {
            if handler(accountId, peerId) {
                return true
            }
        }
        return false
    }
}

public enum MTPasscodeHooks {
    /// Policy (any `true`): the app is locked on every cold start, whatever the auto-lock timeout
    /// says. Asked once, from `AppLockContextImpl.init` on the main thread, before the first lock
    /// evaluation; a passcode must be set for it to have any effect (AppLock ignores the lock state
    /// of a non-lockable challenge). Answer from memory.
    public static let locksOnLaunch = MTHookPoint<() -> Bool>("passcode.locksOnLaunch")

    /// `false` while the point is empty (upstream).
    public static func shouldLockOnLaunch() -> Bool {
        if MTPasscodeHooks.locksOnLaunch.isEmpty {
            return false
        }
        for handler in MTPasscodeHooks.locksOnLaunch.handlers {
            if handler() {
                return true
            }
        }
        return false
    }
}
