import Foundation
import SwiftSignalKit

/// Where a non-account setting is stored.
/// - `global`: `<appGroup>/mediatok/settings/global.json`, read by the app only.
/// - `appGroup`: `<appGroup>/mediatok/settings/shared.json`, small, read by the app and the
///   extensions (declare such settings in MTFeaturesShared with `.extensions`).
/// Account-scoped settings are `MTAccountSetting`.
public enum MTSettingScope: Equatable {
    case global
    case appGroup
}

public struct MTSettingFlags: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Secrets, hashes, tokens and internal state: never exported, imported or reset by
    /// "Reset all". The owning feature manages them.
    public static let noExport = MTSettingFlags(rawValue: 1 << 0)
    /// Read by the notification service / share extensions. Requires `.appGroup` scope or an
    /// account setting, and a declaration in MTFeaturesShared (linked into the extensions).
    public static let extensions = MTSettingFlags(rawValue: 1 << 1)
    /// The menu shows the localized "Restart required" footer after a change.
    public static let requiresRestart = MTSettingFlags(rawValue: 1 << 2)
}

/// What the store needs from any setting, without knowing its value type.
protocol MTAnySettingDescriptor: AnyObject {
    var key: String { get }
    var storageKind: MTSettingStorageKind { get }
    var flags: MTSettingFlags { get }

    /// Applies a stored JSON fragment (`nil`: absent, read the default). True when the value changed.
    func applyStored(_ fragment: Data?, account: MTAccountID?) -> Bool
    /// The value to write, or nil when it equals the default (the key is then dropped from the file).
    func storageFragment(account: MTAccountID?) -> Data?
    /// The current value, always encoded (export, diff display).
    func currentFragment(account: MTAccountID?) -> Data?
    /// Decodes an imported fragment; nil when it does not fit the type.
    func importCandidate(_ fragment: Data, account: MTAccountID?) -> MTSettingImportCandidate?
    /// Writes through the normal path (signals, persistence).
    func applyImported(_ fragment: Data, account: MTAccountID?)
    func resetValue(account: MTAccountID?)
    func dropAccount(_ account: MTAccountID)
    #if DEBUG
    var debugWasRead: Bool { get }
    #endif
}

enum MTSettingStorageKind: Equatable {
    case global
    case appGroup
    case account
}

struct MTSettingImportCandidate {
    let isChange: Bool
    let oldText: String
    let newText: String
    let canonicalFragment: Data
}

/// A global or App Group setting.
///
/// Declare it once, as a `static let` in the feature's enum, and touch every declaration from the
/// module's `register()` so the registry knows it before export, search and migrations:
///
///     enum GhostModeSettings {
///         static let hideReadReceipts = MTSetting<Bool>("ghostMode.hideReadReceipts", default: false)
///     }
///
/// `value` is the hot path: an uncontended lock and a copy of the value.
public final class MTSetting<Value: MTSettingValue> {
    public let key: String
    public let defaultValue: Value
    public let scope: MTSettingScope
    public let flags: MTSettingFlags

    let cell: MTValueCell<Value>

    public init(_ key: String, default defaultValue: Value, scope: MTSettingScope = .global, flags: MTSettingFlags = []) {
        self.key = key
        self.defaultValue = defaultValue
        self.scope = scope
        self.flags = flags
        self.cell = MTValueCell(defaultValue)

        assert(MTSettingsStore.isValidKey(key), "Setting key must be <feature>.<key> in camelCase: \(key)")
        assert(!flags.contains(.extensions) || scope == .appGroup, "\(key): .extensions needs scope .appGroup")
        MTSettingsStore.shared.register(self)
    }

    /// Current value. Safe on any thread; the hot path.
    public var value: Value {
        #if DEBUG
        if MTSettingsStore.debugIsExtensionProcess && !self.flags.contains(.extensions) {
            MTSettingsStore.shared.debugNoteExtensionRead(key: self.key)
        }
        return self.cell.currentMarkingRead
        #else
        return self.cell.current
        #endif
    }

    public func set(_ value: Value) {
        guard MTSettingsStore.shared.canWrite(key: self.key) else {
            return
        }
        if self.cell.update(value) {
            MTSettingsStore.shared.didChange(self, account: nil)
        }
    }

    public func reset() {
        self.set(self.defaultValue)
    }

    public var isDefault: Bool {
        return self.cell.current == self.defaultValue
    }

    /// The current value first, then every distinct change. Delivered on the writer's thread.
    public var signal: Signal<Value, NoError> {
        return self.cell.signal()
    }
}

extension MTSetting: MTAnySettingDescriptor {
    var storageKind: MTSettingStorageKind {
        switch self.scope {
        case .global:
            return .global
        case .appGroup:
            return .appGroup
        }
    }

    func applyStored(_ fragment: Data?, account: MTAccountID?) -> Bool {
        return self.cell.update(MTSettingDecoding.value(fragment, default: self.defaultValue, key: self.key))
    }

    func storageFragment(account: MTAccountID?) -> Data? {
        let current = self.cell.current
        if current == self.defaultValue {
            return nil
        }
        return MTSettingCodec.encode(current)
    }

    func currentFragment(account: MTAccountID?) -> Data? {
        return MTSettingCodec.encode(self.cell.current)
    }

    func importCandidate(_ fragment: Data, account: MTAccountID?) -> MTSettingImportCandidate? {
        return MTSettingDecoding.importCandidate(fragment, current: self.cell.current)
    }

    func applyImported(_ fragment: Data, account: MTAccountID?) {
        guard let value = MTSettingCodec.decode(Value.self, from: fragment) else {
            return
        }
        self.set(value)
    }

    func resetValue(account: MTAccountID?) {
        self.reset()
    }

    func dropAccount(_ account: MTAccountID) {
    }

    #if DEBUG
    var debugWasRead: Bool {
        return self.cell.debugWasRead
    }
    #endif
}

/// A setting with one value per Telegram account, stored in the account's own directory
/// (`<account.basePath>/mediatok/settings.json`), so it leaves together with the account.
/// Exceptions, archives, bookmarks and per-account substitutions belong here.
public final class MTAccountSetting<Value: MTSettingValue> {
    public let key: String
    public let defaultValue: Value
    public let flags: MTSettingFlags

    let cell: MTAccountValueCell<Value>

    public init(_ key: String, default defaultValue: Value, flags: MTSettingFlags = []) {
        self.key = key
        self.defaultValue = defaultValue
        self.flags = flags
        self.cell = MTAccountValueCell(defaultValue: defaultValue)

        assert(MTSettingsStore.isValidKey(key), "Setting key must be <feature>.<key> in camelCase: \(key)")
        MTSettingsStore.shared.register(self)
    }

    /// Value for an account; the default for accounts that are not registered. The hot path.
    public func value(for account: MTAccountID) -> Value {
        #if DEBUG
        if MTSettingsStore.debugIsExtensionProcess && !self.flags.contains(.extensions) {
            MTSettingsStore.shared.debugNoteExtensionRead(key: self.key)
        }
        return self.cell.currentMarkingRead(for: account)
        #else
        return self.cell.current(for: account)
        #endif
    }

    public func set(_ value: Value, for account: MTAccountID) {
        guard MTSettingsStore.shared.canWrite(key: self.key) else {
            return
        }
        guard MTSettingsStore.shared.isAccountRegistered(account) else {
            MTLog.warning("settings", "\(self.key): write for an account that is not registered")
            return
        }
        if self.cell.update(value, for: account) {
            MTSettingsStore.shared.didChange(self, account: account)
        }
    }

    public func reset(for account: MTAccountID) {
        self.set(self.defaultValue, for: account)
    }

    public func isDefault(for account: MTAccountID) -> Bool {
        return self.cell.current(for: account) == self.defaultValue
    }

    /// The account's current value first, then every distinct change.
    public func signal(for account: MTAccountID) -> Signal<Value, NoError> {
        return self.cell.signal(for: account)
    }
}

extension MTAccountSetting: MTAnySettingDescriptor {
    var storageKind: MTSettingStorageKind {
        return .account
    }

    func applyStored(_ fragment: Data?, account: MTAccountID?) -> Bool {
        guard let account = account else {
            return false
        }
        let value = MTSettingDecoding.value(fragment, default: self.defaultValue, key: self.key)
        return self.cell.update(value, for: account)
    }

    func storageFragment(account: MTAccountID?) -> Data? {
        guard let account = account else {
            return nil
        }
        let current = self.cell.current(for: account)
        if current == self.defaultValue {
            return nil
        }
        return MTSettingCodec.encode(current)
    }

    func currentFragment(account: MTAccountID?) -> Data? {
        guard let account = account else {
            return nil
        }
        return MTSettingCodec.encode(self.cell.current(for: account))
    }

    func importCandidate(_ fragment: Data, account: MTAccountID?) -> MTSettingImportCandidate? {
        guard let account = account else {
            return nil
        }
        return MTSettingDecoding.importCandidate(fragment, current: self.cell.current(for: account))
    }

    func applyImported(_ fragment: Data, account: MTAccountID?) {
        guard let account = account, let value = MTSettingCodec.decode(Value.self, from: fragment) else {
            return
        }
        self.set(value, for: account)
    }

    func resetValue(account: MTAccountID?) {
        guard let account = account else {
            return
        }
        self.reset(for: account)
    }

    func dropAccount(_ account: MTAccountID) {
        self.cell.update(nil, for: account)
    }

    #if DEBUG
    var debugWasRead: Bool {
        return self.cell.debugWasRead
    }
    #endif
}

enum MTSettingDecoding {
    static func value<Value: MTSettingValue>(_ fragment: Data?, default defaultValue: Value, key: String) -> Value {
        guard let fragment = fragment else {
            return defaultValue
        }
        if let value = MTSettingCodec.decode(Value.self, from: fragment) {
            return value
        }
        // A stored value of another type (the declaration changed): read the default. The stored
        // fragment stays in the file until the setting is written again.
        MTLog.warning("settings", "\(key): stored value does not match the declared type")
        return defaultValue
    }

    static func importCandidate<Value: MTSettingValue>(_ fragment: Data, current: Value) -> MTSettingImportCandidate? {
        guard let newValue = MTSettingCodec.decode(Value.self, from: fragment) else {
            return nil
        }
        guard let canonical = MTSettingCodec.encode(newValue) else {
            return nil
        }
        return MTSettingImportCandidate(
            isChange: newValue != current,
            oldText: MTSettingCodec.text(MTSettingCodec.encode(current)),
            newText: MTSettingCodec.text(canonical),
            canonicalFragment: canonical
        )
    }
}
