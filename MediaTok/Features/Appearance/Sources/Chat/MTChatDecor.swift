import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import MTCore
import MTHooks
import MTAppearanceSettings

/// Decorations of the chat screen, as feature overlays (MTChatScreenHooks.overlays) instead of edits
/// in ChatControllerNode: the animated background and the snowfall above the wallpaper, the blur and
/// gradient bands at the screen edges above the messages. Each overlay follows its settings with one
/// signal, created once per chat screen; nothing here takes part in theme rebuilds.
enum MTChatDecor {
    static func register() {
        MTChatScreenHooks.overlays.register({ screen in
            if screen.isPreview {
                return []
            }
            return [MTChatBackgroundOverlay(), MTChatEdgesOverlay(context: screen.context)]
        }, order: 100)

        MTLifecycleHooks.applicationDidBecomeActive.register({
            MTLoopingVideoView.resumeAll()
        }, order: 100)
    }
}

// MARK: - Settings as values

struct MTBackgroundDecorSettings: Equatable {
    var background: Bool
    var backgroundOpacity: Double
    var backgroundVersion: Int
    var snow: Bool
    var snowInChats: Bool
    var snowStyle: MTSnowStyle
    var snowIntensity: Double

    /// `double` reads the sliders (the stored value, or the menu preview's draft).
    static func current(double: (MTSetting<Double>) -> Double = { $0.value }) -> MTBackgroundDecorSettings {
        return MTBackgroundDecorSettings(
            background: MTAppearanceSettings.chatBackground.value,
            backgroundOpacity: mtClampPercent(double(MTAppearanceSettings.chatBackgroundOpacity)),
            backgroundVersion: MTAppearanceSettings.chatBackgroundVersion.value,
            snow: MTAppearanceSettings.snow.value,
            snowInChats: !MTAppearanceSettings.snowHideInChats.value,
            snowStyle: MTSnowStyle(rawValue: MTAppearanceSettings.snowStyle.value) ?? .snow,
            snowIntensity: mtClampPercent(double(MTAppearanceSettings.snowIntensity))
        )
    }

    /// Distinct values only, re-read on every settings revision (a struct compare, no disk).
    static var signal: Signal<MTBackgroundDecorSettings, NoError> {
        return MTSettingsStore.shared.revision
        |> map { _ -> MTBackgroundDecorSettings in
            return MTBackgroundDecorSettings.current()
        }
        |> distinctUntilChanged
    }
}

/// «Затемнение краёв»: one kind of band (blur or gradient) with one color, height and strength.
struct MTEdgeDecorSettings: Equatable {
    var style: MTEdgeStyle
    var rgb: UInt32?
    var size: Double
    var intensity: Double
    var hideInChatList: Bool

    var isEmpty: Bool {
        return self.style == .off
    }

    /// The chat list shows the gradient only (the blur is drawn in chats).
    var showsInChatList: Bool {
        return self.style == .gradient && !self.hideInChatList
    }

    /// `double` reads the sliders (the stored value, or the menu preview's draft).
    static func current(double: (MTSetting<Double>) -> Double = { $0.value }) -> MTEdgeDecorSettings {
        return MTEdgeDecorSettings(
            style: MTEdgeStyle(rawValue: MTAppearanceSettings.edgeStyle.value) ?? .off,
            rgb: mtAppearanceParseColor(MTAppearanceSettings.edgeColor.value),
            size: min(MTEdgeStyle.sizeRange.upperBound, max(MTEdgeStyle.sizeRange.lowerBound, double(MTAppearanceSettings.edgeSize))),
            intensity: mtClampPercent(double(MTAppearanceSettings.edgeIntensity)),
            hideInChatList: MTAppearanceSettings.edgeHideInChatList.value
        )
    }

    static var signal: Signal<MTEdgeDecorSettings, NoError> {
        return MTSettingsStore.shared.revision
        |> map { _ -> MTEdgeDecorSettings in
            return MTEdgeDecorSettings.current()
        }
        |> distinctUntilChanged
    }

    /// The band for one edge, with the theme's color where the user chose «automatic»: in the
    /// `blur` or the `gradient` slot, by the style.
    func bands(autoColor: UIColor) -> (blur: MTEdgeBandView.Band?, gradient: MTEdgeBandView.Band?) {
        let band = MTEdgeBandView.Band(color: self.rgb.flatMap { UIColor(rgb: $0) } ?? autoColor, size: CGFloat(self.size), intensity: CGFloat(self.intensity))
        switch self.style {
        case .off:
            return (nil, nil)
        case .blur:
            return (band, nil)
        case .gradient:
            return (nil, band)
        }
    }
}

/// 0…100 % → 0…1.
func mtClampPercent(_ value: Double) -> Double {
    return min(1.0, max(0.0, value / 100.0))
}

// MARK: - Above the wallpaper: animated background and snow

final class MTChatBackgroundOverlay: MTChatOverlay {
    let node: ASDisplayNode
    let placement: MTChatOverlayPlacement = .aboveWallpaper

    private var videoView: MTLoopingVideoView?
    private var snowView: MTSnowView?
    private var settings: MTBackgroundDecorSettings?
    private var reducesMotion = false
    private var bounds = CGRect()
    private var disposable: Disposable?

    init() {
        self.node = ASDisplayNode()
        self.node.isUserInteractionEnabled = false

        self.disposable = (combineLatest(MTBackgroundDecorSettings.signal, MTSystemState.reducesMotion)
        |> deliverOnMainQueue).start(next: { [weak self] settings, reducesMotion in
            guard let self else {
                return
            }
            self.settings = settings
            self.reducesMotion = reducesMotion
            self.apply()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    func updateLayout(bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        self.bounds = bounds
        self.videoView?.frame = bounds
        self.snowView?.frame = bounds
    }

    private func apply() {
        guard let settings = self.settings else {
            return
        }
        if settings.background, let url = MTAnimatedBackgrounds.fileURL(.chat) {
            let videoView: MTLoopingVideoView
            if let current = self.videoView {
                videoView = current
            } else {
                videoView = MTLoopingVideoView(frame: self.bounds)
                self.node.view.insertSubview(videoView, at: 0)
                self.videoView = videoView
            }
            videoView.alpha = CGFloat(settings.backgroundOpacity)
            videoView.setVideo(url: url, version: settings.backgroundVersion)
        } else if let videoView = self.videoView {
            self.videoView = nil
            videoView.setVideo(url: nil, version: 0)
            videoView.removeFromSuperview()
        }

        if settings.snow && settings.snowInChats {
            let snowView: MTSnowView
            if let current = self.snowView {
                snowView = current
            } else {
                snowView = MTSnowView(frame: self.bounds, kind: .background)
                self.node.view.addSubview(snowView)
                self.snowView = snowView
            }
            snowView.update(style: settings.snowStyle, intensity: settings.snowIntensity, isPaused: self.reducesMotion)
        } else if let snowView = self.snowView {
            self.snowView = nil
            snowView.removeFromSuperview()
        }
    }
}

// MARK: - Above the messages: blur and gradient at the edges

final class MTChatEdgesOverlay: MTChatOverlay {
    let node: ASDisplayNode
    let placement: MTChatOverlayPlacement = .aboveHistory

    private let topView = MTEdgeBandView(edge: .top)
    private let bottomView = MTEdgeBandView(edge: .bottom)
    private var settings: MTEdgeDecorSettings?
    private var theme: PresentationTheme?
    private var layout: (bounds: CGRect, insets: UIEdgeInsets)?
    private var disposable: Disposable?

    init(context: AccountContext) {
        self.node = ASDisplayNode()
        self.node.isUserInteractionEnabled = false
        self.node.view.addSubview(self.topView)
        self.node.view.addSubview(self.bottomView)

        self.disposable = (combineLatest(MTEdgeDecorSettings.signal, context.sharedContext.presentationData)
        |> deliverOnMainQueue).start(next: { [weak self] settings, presentationData in
            guard let self else {
                return
            }
            self.settings = settings
            self.theme = presentationData.theme
            self.apply()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    func updateLayout(bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        self.layout = (bounds, insets)
        self.apply()
    }

    private func apply() {
        guard let settings = self.settings, let theme = self.theme, let layout = self.layout else {
            return
        }
        self.node.isHidden = settings.isEmpty
        if settings.isEmpty {
            return
        }
        let width = layout.bounds.width
        let topBands = settings.bands(autoColor: theme.rootController.navigationBar.opaqueBackgroundColor)
        self.topView.update(width: width, inset: layout.insets.top, blur: topBands.blur, gradient: topBands.gradient)
        self.topView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: self.topView.bandHeight(inset: layout.insets.top, blur: topBands.blur, gradient: topBands.gradient))

        // The overlay's bottom inset includes the input panels (MTChatScreenHooks.overlays).
        let bottomInset = layout.insets.bottom
        let bottomBands = settings.bands(autoColor: theme.chat.inputPanel.panelBackgroundColor.withAlphaComponent(1.0))
        self.bottomView.update(width: width, inset: bottomInset, blur: bottomBands.blur, gradient: bottomBands.gradient)
        let bottomHeight = self.bottomView.bandHeight(inset: bottomInset, blur: bottomBands.blur, gradient: bottomBands.gradient)
        self.bottomView.frame = CGRect(x: 0.0, y: layout.bounds.height - bottomHeight, width: width, height: bottomHeight)
    }
}

extension MTEdgeBandView {
    func bandHeight(inset: CGFloat, blur: Band?, gradient: Band?) -> CGFloat {
        return max(1.0, inset + max(blur?.size ?? 0.0, gradient?.size ?? 0.0))
    }
}
