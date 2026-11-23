import Foundation
import GGCore
import TelegramCore

/// How many accounts can be signed in at once — the one place that says it. Owner decision
/// 2026-10-22: 100, the same in every place that checks it, with and without Premium, no toggle.
/// Upstream: 3, or 4 with Premium. Every check asks `GGLimitHooks.accountLimit` (see
/// GGHooks/MediaTok spec), so code that needs the limit reads `GGLimitHooks.maximumNumberOfAccounts`
/// (with the point empty it answers upstream's) rather than this constant.
public enum GGAccountLimit {
    /// MediaTok #422: unlimited accounts (safe Int32-compatible ceiling, no artificial 3/20/100 cap).
    public static let maximumNumberOfAccounts: Int = 999_999

    /// From `GGSecurityShared.register()`. App only: the extensions never add accounts.
    static func register() {
        guard GGCore.environment?.process.isApp ?? false else {
            return
        }
        GGLimitHooks.accountLimit.register({ _ in
            return GGAccountLimit.maximumNumberOfAccounts
        })
    }
}
