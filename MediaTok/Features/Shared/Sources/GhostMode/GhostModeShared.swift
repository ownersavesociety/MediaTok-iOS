import Foundation
import MTCore

/// The part of MTGhostMode that the extensions (notification service, share) also link: the
/// settings and the policy that decides what leaves the device (read receipts, story views,
/// "typing", online, send delay). Owner: MediaTok.
public enum MTGhostModeShared {
    /// Called from `MTFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `MTCore.environment?.process` for what only one of them needs.
    public static func register() {
        MTGhostSettings.declare()
        MTGhostCoreHandlers.register()
    }
}
