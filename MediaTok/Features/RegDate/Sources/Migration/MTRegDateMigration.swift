import Foundation
import TelegramCore
import MTCore

/// legacy format keys (SGSimpleSettings, `UserDefaults.standard`):
/// - `showRegDate` (Bool, default true) → `regDate.show`;
/// - `regDateCache` (user id text → JSON of Swiftgram's `RegDate {from, to, validUntil}`): real
///   answers of Swiftgram's server, moved to `regDate.remote` as remote answers (expired ones too —
///   their bounds stay evidence, see `MTRegDate.resolve`).
enum MTRegDateMigration {
    static func register() {
        MTMigrations.registerGlobal(id: "regDate.v1") { legacy in
            if let value = legacy.bool("showRegDate") {
                MTRegDateSettings.show.set(value)
                legacy.removeLegacyKey("showRegDate")
            }
            let answers = MTRegDateStore.legacyRemoteAnswers(legacy.object("regDateCache"))
            if !answers.isEmpty {
                let userNamespace = Namespaces.Peer.CloudUser._internalGetInt32Value()
                var remote = MTRegDateSettings.remote.value
                for (userId, entry) in answers {
                    guard let key = MTPeerKey(namespace: userNamespace, id: userId)?.stringValue else {
                        continue
                    }
                    // An answer this build already has is newer than legacy format.
                    if remote[key] == nil {
                        remote[key] = entry
                    }
                }
                MTRegDateSettings.remote.set(MTRegDateStore.trimmedRemote(remote, now: Int32(clamping: Int(Date().timeIntervalSince1970))))
            }
            if legacy.object("regDateCache") != nil {
                legacy.removeLegacyKey("regDateCache")
            }
        }
    }
}
