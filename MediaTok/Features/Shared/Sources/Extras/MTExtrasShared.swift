import Foundation
import TelegramCore
import MTCore

/// The part of MTExtras (Swiftgram-parity features, MediaTok) that the extensions also link: the
/// settings (the notification service reads `hideAccountInNotifications`) and the handlers of the
/// points compiled into TelegramCore.
public enum MTExtrasShared {
    /// Called from `MTFeaturesShared.registerForApp()` and `.registerForExtension()`.
    public static func register() {
        MTExtrasSettings.declare()

        MTExtrasCoreHooks.restrictionText.register({ text, reason, platform in
            if !MTExtrasSettings.restrictionReasonCode.value || reason.isEmpty {
                return text
            }
            return text + "\n" + reason + "-" + platform
        })

        if MTCore.environment?.process.isApp ?? false {
            MTExtrasCoreHooks.searchesPartialWords.register({
                return MTExtrasSettings.searchPartialWords.value
            })
        }
    }
}
