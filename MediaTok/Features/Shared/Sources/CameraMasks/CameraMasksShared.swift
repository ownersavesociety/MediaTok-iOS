import Foundation
import SwiftSignalKit
import MTCore

/// The part of MTCameraMasks other zones read: the anonymous mode (a mask and a voice in one tap).
/// The voice changer asks `MTAnonymousMode.voicePreset(for:)` and, while it answers, uses
/// that preset instead of the user's own; it registers its presets for the menu in
/// `MTAnonymousMode.voicePresets`. Owner: MediaTok.
public enum MTCameraMasksShared {
    /// Called from `MTFeaturesShared.registerForApp()` and `.registerForExtension()`.
    public static func register() {
        MTAnonymousMode.declare()
    }
}

/// A voice preset the anonymous mode can use (registered by the voice changer).
public struct MTAnonymousVoicePreset {
    public let id: String
    public let title: () -> String

    public init(id: String, title: @escaping () -> String) {
        self.id = id
        self.title = title
    }
}

/// «Анонимный режим»: a temporary override over the user's own choices, per account. While it is on,
/// round videos and calls of that account use the anonymous mask, and the voice changer uses the
/// anonymous preset. Nothing is snapshotted or restored: turning it off simply removes the override,
/// so it can never restore a preset of another account. Picking a mask by hand turns it off for that
/// account (the manual choice wins), so the two never disagree.
public enum MTAnonymousMode {
    public static let isActive = MTAccountSetting<Bool>("cameraMasks.anonymous.active", default: false)
    /// `MTMaskSelection` storage ("builtin:<id>", "catalog:<id>", "user:<id>").
    public static let mask = MTSetting<String>("cameraMasks.anonymous.mask", default: "builtin:pixelate")
    /// Id of a preset from `voicePresets`.
    public static let voice = MTSetting<String>("cameraMasks.anonymous.voice", default: "robot")

    /// The voice changer's presets for the menu. Empty: the voice row is hidden.
    public static let voicePresets = MTHookPoint<() -> [MTAnonymousVoicePreset]>("cameraMasks.anonymousVoicePresets")

    static func declare() {
        let _ = MTAnonymousMode.isActive
        let _ = MTAnonymousMode.mask
        let _ = MTAnonymousMode.voice
    }

    /// The preset the voice changer must use for this account now, or nil (the user's own settings).
    public static func voicePreset(for account: MTAccountID) -> String? {
        guard MTAnonymousMode.isActive.value(for: account) else {
            return nil
        }
        let value = MTAnonymousMode.voice.value
        return value.isEmpty ? nil : value
    }

    /// The anonymous mask storage for this account now, or nil.
    public static func maskOverride(for account: MTAccountID) -> String? {
        guard MTAnonymousMode.isActive.value(for: account) else {
            return nil
        }
        return MTAnonymousMode.mask.value
    }

    public static func allVoicePresets() -> [MTAnonymousVoicePreset] {
        var result: [MTAnonymousVoicePreset] = []
        for handler in MTAnonymousMode.voicePresets.handlers {
            result.append(contentsOf: handler())
        }
        return result
    }
}
