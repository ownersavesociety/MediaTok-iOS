// Compiled into TelegramPresentationData (filegroup //MediaTok/MTHooks:TelegramPresentationDataHookSources).
// One chain of PresentationData transformers instead of edits all over the theme code:
// AMOLED, bubbles, separators, checkmarks… are applied to the PresentationData the app
// publishes. Cells keep reading the theme as upstream does; a change of a feature's appearance
// settings calls `MTThemeHooks.invalidate()` once (on slider release), which re-emits the
// PresentationData and re-lays out the screens — no notification fan-out.

import Foundation
import UIKit
import SwiftSignalKit
import MTCore

public struct MTThemeContext {
    /// The PresentationData for the very first frame (`currentPresentationDataAndSettings`).
    public let isInitial: Bool
}

public enum MTThemeHooks {
    /// Transformer chain over every PresentationData the app publishes. Must be fast and must
    /// return the same object when nothing applies. To force a re-layout while only a
    /// feature's own snapshot changed, return a PresentationData with a new theme instance.
    public static let presentationData = MTHookPoint<(PresentationData, MTThemeContext) -> PresentationData>("theme.presentationData")

    /// Re-emits the app's PresentationData through the chain. Call after a feature's appearance
    /// settings changed (never on every slider tick).
    public static func invalidate() {
        let value = mtThemeRevisionCounter.modify { $0 &+ 1 }
        mtThemeRevisionPromise.set(value)
    }

    /// For screens that replace the app's theme with their own (a chat's theme, a gift theme, a
    /// preview of the other appearance): runs that PresentationData through the chain too. A theme
    /// that already came out of the chain is returned unchanged, so calling it on the app's own
    /// PresentationData is harmless.
    public static func transformSubstitutedPresentationData(_ presentationData: PresentationData) -> PresentationData {
        if MTThemeHooks.presentationData.isEmpty || mtIsChainTheme(presentationData.theme) {
            return presentationData
        }
        return mtTransformPresentationData(presentationData, isInitial: false)
    }
}

/// The shape of a message bubble image (`messageBubbleImage`): radii and which neighbours it
/// merges with (`.extracted` draws no tail).
public struct MTBubbleShape {
    public var maxCornerRadius: CGFloat
    public var minCornerRadius: CGFloat
    public var neighbors: MessageBubbleImageNeighbors
    public let incoming: Bool
    /// nil = upstream (the tail follows `neighbors`); `false` = no tail, the corners stay as the
    /// neighbours make them.
    public var drawsTail: Bool?
}

public extension MTThemeHooks {
    /// Transformer of bubble shapes (bubble editor: radii, tails). Images are cached per theme:
    /// after a change call `invalidate()` and return a new theme instance from `presentationData`.
    static let bubbleShape = MTHookPoint<(inout MTBubbleShape) -> Void>("theme.bubbleShape")
}

func mtBubbleShape(maxCornerRadius: CGFloat, minCornerRadius: CGFloat, incoming: Bool, neighbors: MessageBubbleImageNeighbors) -> (CGFloat, CGFloat, MessageBubbleImageNeighbors, Bool?) {
    if MTThemeHooks.bubbleShape.isEmpty {
        return (maxCornerRadius, minCornerRadius, neighbors, nil)
    }
    var shape = MTBubbleShape(maxCornerRadius: maxCornerRadius, minCornerRadius: minCornerRadius, neighbors: neighbors, incoming: incoming, drawsTail: nil)
    for handler in MTThemeHooks.bubbleShape.handlers {
        handler(&shape)
    }
    return (shape.maxCornerRadius, shape.minCornerRadius, shape.neighbors, shape.drawsTail)
}

/// Whether a bubble that has a tail in Telegram (no neighbours below) keeps it. Media bubbles cut
/// their own tail into the image corners (`ImageCorner.Tail`) and ask the same features as the
/// bubble images, so «Без хвостиков» also reaches a photo without a caption.
public func mtBubbleDrawsTail(incoming: Bool) -> Bool {
    if MTThemeHooks.bubbleShape.isEmpty {
        return true
    }
    let (_, _, _, drawsTail) = mtBubbleShape(maxCornerRadius: 16.0, minCornerRadius: 8.0, incoming: incoming, neighbors: .none)
    return drawsTail ?? true
}

private let mtThemeRevisionCounter = Atomic<Int>(value: 0)
private let mtThemeRevisionPromise = ValuePromise<Int>(0, ignoreRepeated: true)

func mtTransformPresentationData(_ presentationData: PresentationData, isInitial: Bool) -> PresentationData {
    if MTThemeHooks.presentationData.isEmpty {
        return presentationData
    }
    let context = MTThemeContext(isInitial: isInitial)
    var result = presentationData
    for handler in MTThemeHooks.presentationData.handlers {
        result = handler(result, context)
    }
    mtNoteChainTheme(result.theme)
    return result
}

// Themes that came out of the chain (held weakly): a screen that substitutes its own theme asks
// the chain only for themes it has not seen, so a theme is never transformed twice.
private final class MTWeakTheme {
    weak var value: PresentationTheme?

    init(_ value: PresentationTheme) {
        self.value = value
    }
}

private let mtChainThemesLock = NSLock()
private var mtChainThemes: [ObjectIdentifier: MTWeakTheme] = [:]

private func mtNoteChainTheme(_ theme: PresentationTheme) {
    mtChainThemesLock.lock()
    if mtChainThemes.count > 64 {
        mtChainThemes = mtChainThemes.filter { $0.value.value != nil }
    }
    mtChainThemes[ObjectIdentifier(theme)] = MTWeakTheme(theme)
    mtChainThemesLock.unlock()
}

private func mtIsChainTheme(_ theme: PresentationTheme) -> Bool {
    mtChainThemesLock.lock()
    defer {
        mtChainThemesLock.unlock()
    }
    return mtChainThemes[ObjectIdentifier(theme)]?.value === theme
}

/// Re-emits `signal`'s latest value on `MTThemeHooks.invalidate()`.
func mtWithThemeRevision<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> {
    if MTThemeHooks.presentationData.isEmpty {
        return signal
    }
    return combineLatest(signal, mtThemeRevisionPromise.get())
    |> map { value, _ -> T in
        return value
    }
}
