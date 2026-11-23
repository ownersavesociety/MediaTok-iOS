import Foundation

/// The part of MTAppearance that the extensions (notification service, share) also link: settings with
/// `.extensions`, NSE handlers, attribute declarations. Owner: MediaTok.
public enum MTAppearanceShared {
    /// Called from `MTFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `MTCore.environment?.process` for what only one of them needs.
    public static func register() {
        // Nothing to do: appearance applies to the app's own screens only. The notification
        // service draws no UI and the share sheet keeps the upstream look, so no appearance setting
        // carries `.extensions`. The settings and the snapshot live in `MTAppearanceSettings`.
    }
}
