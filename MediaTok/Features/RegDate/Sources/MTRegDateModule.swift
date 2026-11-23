import Foundation

/// Entry point of MTRegDate, «Дата регистрации»: when an account was
/// created, in the profile of every user and bot. Swiftgram's layers in MediaTok's architecture:
///
/// | Swiftgram | here |
/// |---|---|
/// | `SGRegDateScheme` | `Model/MTRegDateModel.swift` (contract), `Store/MTRegDateStore.swift` |
/// | `SGAPI` regdate | `Remote/MTRegDateAPI.swift` (no address: off), `Remote/MTRegDateRemoteResponse.swift` |
/// | `SGAPIToken`, `SGDeviceToken` | none: no web-app token, no DeviceCheck / App Attest |
/// | `SGRegDate` (cache + request) | `Provider/MTRegDate.swift`, `Evidence/MTRegDateEvidenceCollector.swift` |
/// | the estimate (server side in Swiftgram) | `Estimate/MTRegDateResolver.swift` (by ID, on the device) |
/// | `SGPeerInfoRows` | `Profile/MTRegDateProfileRow.swift` |
public enum MTRegDateModule {
    /// Declares the settings, the menu row, the profile row and the migration. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        MTRegDateSettings.declare()
        MTRegDateMenu.register()
        MTRegDateProfileRow.register()
        MTRegDateMigration.register()
    }
}
