import Foundation
import MTCore

extension MTRegDateStoredEntry: MTSettingValue {}
extension MTRegDateRemoteEntry: MTSettingValue {}

/// Settings and caches of «Дата регистрации».
enum MTRegDateSettings {
    /// The row in profiles. On by default, like Swiftgram's `showRegDate`.
    static let show = MTSetting<Bool>("regDate.show", default: true)

    /// What this account found on the device, by user (`MTPeerKey.stringValue`): Telegram's month and
    /// the earliest trace. Account scope: it was learned through this account's data and leaves with
    /// it. A cache — not exported; bounded by `MTRegDateStore.evidenceLimit`.
    static let evidence = MTAccountSetting<[String: MTRegDateStoredEntry]>("regDate.evidence", default: [:], flags: [.noExport])

    /// Answers of a remote service by user (`MTPeerKey.stringValue`), and legacy format
    /// `regDateCache`. Global: an answer depends on the ID only. Not exported; bounded by
    /// `MTRegDateStore.remoteLimit`.
    static let remote = MTSetting<[String: MTRegDateRemoteEntry]>("regDate.remote", default: [:], flags: [.noExport])

    static func declare() {
        let _ = MTRegDateSettings.show
        let _ = MTRegDateSettings.evidence
        let _ = MTRegDateSettings.remote
    }
}
