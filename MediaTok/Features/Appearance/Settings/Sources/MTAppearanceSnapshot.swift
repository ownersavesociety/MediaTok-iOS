import Foundation
import Darwin
import os
import SwiftSignalKit
import MTCore

/// Bubble geometry and paint of the bubble editor (nil in the snapshot while the editor is off).
public struct MTBubbleAppearance: Equatable {
    public var incomingRadius: Double
    public var outgoingRadius: Double
    public var padding: Double
    /// 0.4…1, share of the upstream maximum width.
    public var widthFraction: Double
    /// 0…1.
    public var backgroundAlpha: Double
    /// 0…1.
    public var outlineAlpha: Double
}

/// Everything about MediaTok's appearance that changes the theme or the layout of messages and
/// chrome, as one immutable value. Built once per settings change; the hot paths (cells, layout) read
/// `MTAppearanceSnapshot.current` — one lock-protected load, no disk, no JSON.
///
/// Decorations that do not need a relayout (animated backgrounds, snow, screen-edge blur) are not
/// part of it: they follow their own settings' signals, so they never rebuild the theme.
public struct MTAppearanceSnapshot: Equatable {
    // Theme
    public var amoled = false
    public var amoledKeyboard = false
    public var hideSeparators = false
    /// 0…1; 1 = the server's colors.
    public var nameColorSaturation: Double = 1.0
    public var readCheckRGB: UInt32?
    public var unreadCheckRGB: UInt32?
    public var checkColorsInChatList = false
    public var bubbles: MTBubbleAppearance?
    public var hideTails = false

    // Messages
    public var wideChannelPosts = false
    public var secondsInTime = false
    public var hideReactionsInChats = false
    public var hideReactionsInChannels = false
    public var hideEdited = false
    public var hideTime = false
    public var hideIncomingFormatting = false
    public var hideOutgoingFormatting = false
    public var hideChannelComments = false
    public var hideViewCounts = false
    public var colorSwatches = false
    public var authorOnlineIndicator = false
    public var exactLastSeen = false
    public var tripleTapDelete: MTTripleTapDelete = .off
    public var noSelectionBlur = false
    /// 0.5…2.
    public var stickerScale: Double = 1.0
    public var stickerHideTime = false

    // Chat top bar
    public var hideBackButton = false
    public var hideTitlePanel = false
    public var hideAvatar = false
    public var hidePinnedMessages = false

    public init() {
    }

    /// All upstream: the theme transformer returns the PresentationData untouched.
    public var isDefault: Bool {
        return self == MTAppearanceSnapshot()
    }

    /// The parts that change the theme's colors or images (the rest only needs a relayout).
    public var changesThemeColors: Bool {
        if self.amoled || self.amoledKeyboard || self.hideSeparators {
            return true
        }
        if self.readCheckRGB != nil || self.unreadCheckRGB != nil {
            return true
        }
        if self.bubbles != nil {
            return true
        }
        return false
    }

    /// The current snapshot. Any thread; the hot path. Inside `withPreview` on the main thread —
    /// the preview's snapshot.
    public static var current: MTAppearanceSnapshot {
        if pthread_main_np() != 0, let preview = MTAppearanceSnapshotStore.mainThreadPreview {
            return preview
        }
        return MTAppearanceSnapshotStore.shared.current()
    }

    /// Runs `body` with `current` answering `snapshot` on the main thread only (other threads keep
    /// the real one): the menu's live preview lays its bubbles out with the values a slider is
    /// being dragged to, while the settings are written only on release. Main thread, synchronous.
    public static func withPreview(_ snapshot: MTAppearanceSnapshot, _ body: () -> Void) {
        assert(pthread_main_np() != 0)
        let previous = MTAppearanceSnapshotStore.mainThreadPreview
        MTAppearanceSnapshotStore.mainThreadPreview = snapshot
        body()
        MTAppearanceSnapshotStore.mainThreadPreview = previous
    }

    /// The snapshot as the settings would make it with these slider values (setting key → value):
    /// what a live preview shows while a slider is dragged.
    public static func make(overriding values: [String: Double]) -> MTAppearanceSnapshot {
        if values.isEmpty {
            return MTAppearanceSnapshot.current
        }
        return MTAppearanceSnapshot.make(double: { setting in
            return values[setting.key] ?? setting.value
        })
    }

    /// The current snapshot first, then every distinct one. Delivered on the writer's thread.
    public static var signal: Signal<MTAppearanceSnapshot, NoError> {
        return MTAppearanceSnapshotStore.shared.signal()
    }

    /// `double` reads the sliders (the stored value, or a preview's draft).
    static func make(double: (MTSetting<Double>) -> Double = { $0.value }) -> MTAppearanceSnapshot {
        var result = MTAppearanceSnapshot()

        result.amoled = MTAppearanceSettings.amoled.value
        result.amoledKeyboard = MTAppearanceSettings.amoledKeyboard.value
        result.hideSeparators = MTAppearanceSettings.hideSeparators.value
        result.nameColorSaturation = mtClamp(double(MTAppearanceSettings.nameColorSaturation) / 100.0, 0.0, 1.0)

        let readRGB = mtAppearanceParseColor(MTAppearanceSettings.readCheckColor.value)
        result.readCheckRGB = readRGB
        if MTAppearanceSettings.unreadCheckSameAsRead.value, let readRGB {
            result.unreadCheckRGB = readRGB
        } else {
            result.unreadCheckRGB = mtAppearanceParseColor(MTAppearanceSettings.unreadCheckColor.value)
        }
        result.checkColorsInChatList = readRGB != nil && MTAppearanceSettings.checkColorsInChatList.value

        if MTAppearanceSettings.bubbleEditor.value {
            result.bubbles = MTBubbleAppearance(
                incomingRadius: mtClamp(double(MTAppearanceSettings.bubbleIncomingRadius), 0.0, 26.0),
                outgoingRadius: mtClamp(double(MTAppearanceSettings.bubbleOutgoingRadius), 0.0, 26.0),
                padding: mtClamp(double(MTAppearanceSettings.bubblePadding), 0.0, 24.0),
                widthFraction: mtClamp(double(MTAppearanceSettings.bubbleWidth) / 100.0, 0.4, 1.0),
                backgroundAlpha: mtClamp(double(MTAppearanceSettings.bubbleBackgroundOpacity) / 100.0, 0.0, 1.0),
                outlineAlpha: mtClamp(double(MTAppearanceSettings.bubbleOutlineOpacity) / 100.0, 0.0, 1.0)
            )
        }
        result.hideTails = MTAppearanceSettings.bubbleHideTails.value

        result.wideChannelPosts = MTAppearanceSettings.wideChannelPosts.value
        result.secondsInTime = MTAppearanceSettings.secondsInTime.value
        let hiddenReactions = MTHiddenReactions(rawValue: MTAppearanceSettings.hideReactions.value) ?? .off
        result.hideReactionsInChats = hiddenReactions.inChats
        result.hideReactionsInChannels = hiddenReactions.inChannels
        result.hideEdited = MTAppearanceSettings.hideEdited.value
        result.hideTime = MTAppearanceSettings.hideTime.value
        let hiddenFormatting = MTHiddenFormatting(rawValue: MTAppearanceSettings.hideFormatting.value) ?? .off
        result.hideIncomingFormatting = hiddenFormatting.inIncoming
        result.hideOutgoingFormatting = hiddenFormatting.inOutgoing
        result.hideChannelComments = MTAppearanceSettings.hideChannelComments.value
        result.hideViewCounts = MTAppearanceSettings.hideViewCounts.value
        result.colorSwatches = MTAppearanceSettings.colorSwatches.value
        result.authorOnlineIndicator = MTAppearanceSettings.authorOnlineIndicator.value
        result.exactLastSeen = MTAppearanceSettings.exactLastSeen.value
        result.tripleTapDelete = MTTripleTapDelete(rawValue: MTAppearanceSettings.tripleTapDelete.value) ?? .off
        result.noSelectionBlur = MTAppearanceSettings.noSelectionBlur.value
        result.stickerScale = mtClamp(double(MTAppearanceSettings.stickerSize) / 100.0, 0.5, 2.0)
        result.stickerHideTime = MTAppearanceSettings.stickerHideTime.value

        result.hideBackButton = MTAppearanceSettings.hideBackButton.value
        result.hideTitlePanel = MTAppearanceSettings.hideTitlePanel.value
        result.hideAvatar = MTAppearanceSettings.hideAvatar.value
        result.hidePinnedMessages = MTAppearanceSettings.hidePinnedMessages.value

        return result
    }
}

@inline(__always)
func mtClamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    if value.isNaN {
        return lower
    }
    return min(upper, max(lower, value))
}

/// Holds the snapshot. Rebuilt from `MTSettingsStore.shared.revision`, which moves on every write
/// (one rebuild ≈ 60 lock-protected copies, i.e. microseconds, only on writes); subscribers see only
/// distinct snapshots, so a write to an unrelated setting changes nothing downstream.
final class MTAppearanceSnapshotStore {
    static let shared = MTAppearanceSnapshotStore()

    /// The menu preview's snapshot (`MTAppearanceSnapshot.withPreview`). Written and read on the
    /// main thread only (`current` checks the thread first), so other threads never see it.
    static var mainThreadPreview: MTAppearanceSnapshot?

    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var value: MTAppearanceSnapshot?
    private var isObserving = false
    private let promise = ValuePromise<MTAppearanceSnapshot>(ignoreRepeated: true)
    private var disposable: Disposable?

    private init() {
        self.lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())
    }

    func current() -> MTAppearanceSnapshot {
        os_unfair_lock_lock(self.lock)
        if let value = self.value {
            os_unfair_lock_unlock(self.lock)
            return value
        }
        let startObserving = !self.isObserving
        self.isObserving = true
        os_unfair_lock_unlock(self.lock)

        if startObserving {
            self.startObserving()
        }
        return self.storeIfNeeded(MTAppearanceSnapshot.make())
    }

    func signal() -> Signal<MTAppearanceSnapshot, NoError> {
        let _ = self.current()
        return self.promise.get()
    }

    private func startObserving() {
        // The revision signal delivers its current value synchronously: done outside the lock.
        let disposable = (MTSettingsStore.shared.revision
        |> distinctUntilChanged).start(next: { [weak self] _ in
            guard let self else {
                return
            }
            let updated = MTAppearanceSnapshot.make()
            os_unfair_lock_lock(self.lock)
            let changed = self.value != updated
            self.value = updated
            os_unfair_lock_unlock(self.lock)
            if changed {
                self.promise.set(updated)
            }
        })
        os_unfair_lock_lock(self.lock)
        self.disposable = disposable
        os_unfair_lock_unlock(self.lock)
    }

    private func storeIfNeeded(_ snapshot: MTAppearanceSnapshot) -> MTAppearanceSnapshot {
        os_unfair_lock_lock(self.lock)
        if let value = self.value {
            os_unfair_lock_unlock(self.lock)
            return value
        }
        self.value = snapshot
        os_unfair_lock_unlock(self.lock)
        self.promise.set(snapshot)
        return snapshot
    }
}
