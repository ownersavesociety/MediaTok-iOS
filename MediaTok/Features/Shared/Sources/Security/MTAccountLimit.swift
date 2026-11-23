import Foundation
import MTCore
import TelegramCore

/// 2026-10-22: 100, the same in every place that checks it, with and without Premium, no toggle.
/// Upstream: 3, or 4 with Premium. Every check asks `MTLimitHooks.accountLimit` (see
/// MTHooks/MediaTok spec), so code that needs the limit reads `MTLimitHooks.maximumNumberOfAccounts`
/// (with the point empty it answers upstream's) rather than this constant.
public enum MTAccountLimit {
    /// MediaTok #422: unlimited accounts (safe Int32-compatible ceiling, no artificial 3/20/100 cap).
    public static let maximumNumberOfAccounts: Int = 999_999

    /// From `MTSecurityShared.register()`. App only: the extensions never add accounts.
    static func register() {
        guard MTCore.environment?.process.isApp ?? false else {
            return
        }
        MTLimitHooks.accountLimit.register({ _ in
            return MTAccountLimit.maximumNumberOfAccounts
        })
    }
}
