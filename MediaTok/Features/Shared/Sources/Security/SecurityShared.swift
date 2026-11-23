import Foundation
import MTCore

/// The part of MTSecurity that the extensions (notification service, share) also link: settings with
/// `.extensions`, NSE handlers, attribute declarations. Owner: MediaTok.
public enum MTSecurityShared {
    /// Called from `MTFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `MTCore.environment?.process` for what only one of them needs.
    public static func register() {
        // Account limit: 100 with and without Premium, app process only.
        MTAccountLimit.register()

        // MediaTok: every setting of the zone, then what the extensions need — which chats are protected
        // (push text, Siri, banners, widget). Migrations only in the app, before the feature modules.
        MTSecuritySharedSettings.declare()
        MTSecuritySettings.declare()
        MTChatProtection.register()
        if MTCore.environment?.process.isApp ?? false {
            MTSecurityMigrations.register()
        }
    }
}
