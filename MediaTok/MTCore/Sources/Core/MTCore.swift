import Foundation

/// The process MTCore runs in. Extensions only read settings and never run migrations.
public enum MTProcessKind: String {
    case app
    case notificationService
    case notificationContent
    case share
    case widget
    case intents
    case broadcastUpload
    case other

    public var isApp: Bool {
        return self == .app
    }
}

public struct MTCoreEnvironment {
    /// Path of the App Group container (`group.<base bundle id>`).
    public let appGroupPath: String
    public let process: MTProcessKind
    /// App Group of the previous MediaTok installation, read by migrations. `nil` means
    /// `group.<main bundle id>`: the old app had the same bundle id.
    public let legacyAppGroupIdentifier: String?

    public init(appGroupPath: String, process: MTProcessKind, legacyAppGroupIdentifier: String? = nil) {
        self.appGroupPath = appGroupPath
        self.process = process
        self.legacyAppGroupIdentifier = legacyAppGroupIdentifier
    }

    var mediatokPath: String {
        return (self.appGroupPath as NSString).appendingPathComponent("mediatok")
    }

    var settingsDirectoryPath: String {
        return (self.mediatokPath as NSString).appendingPathComponent("settings")
    }

    var inboxDirectoryPath: String {
        return (self.mediatokPath as NSString).appendingPathComponent("inbox")
    }
}

/// Entry points called once per process from the launch path (see MediaTok spec).
public enum MTCore {
    private static let lock = MTUnfairLock()
    private static var currentEnvironment: MTCoreEnvironment?

    /// The environment passed to `bootstrap`, or nil before it.
    public static var environment: MTCoreEnvironment? {
        return MTCore.lock.withLock {
            return MTCore.currentEnvironment
        }
    }

    /// Loads the settings files of this process. Call first, before any feature registers.
    public static func bootstrap(_ environment: MTCoreEnvironment) {
        let isFirst = MTCore.lock.withLock { () -> Bool in
            if MTCore.currentEnvironment != nil {
                return false
            }
            MTCore.currentEnvironment = environment
            return true
        }
        if !isFirst {
            assertionFailure("MTCore.bootstrap must be called once")
            return
        }
        MTLog.bootstrap(process: environment.process)
        MTSettingsStore.shared.bootstrap(environment)
        // Registers core.language and resolves the language before the first string is read.
        let _ = MTLocalization.shared
    }

    /// Extensions: reads the settings files again (iOS reuses an extension's process for the next
    /// request while the app goes on changing them). Call at the start of every request after the
    /// first; does nothing in the app.
    public static func reloadSettings() {
        MTSettingsStore.shared.reloadFromDisk()
    }

    /// Runs the registered one-time migrations from the legacy MediaTok. App process only, after
    /// all modules have registered (`MTFeatures.registerAll()`).
    public static func runGlobalMigrations() {
        MTMigrations.runPending()
    }
}
