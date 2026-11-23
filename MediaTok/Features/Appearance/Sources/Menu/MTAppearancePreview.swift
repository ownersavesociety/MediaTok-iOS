import Foundation
import UIKit
import TelegramPresentationData
import MTCore
import MTSettingsUI
import MTAppearanceSettings

/// The live mini chats of «Сообщения» and «Тема и фон»: while a slider is dragged the
/// bubbles follow it (radii, padding, width, outline, background, name saturation) and the chat
/// layers of the theme tab (animated background, snow, edge bands) follow theirs. Nothing is
/// written before the finger is lifted: the drafts of the screen become a snapshot that the theme
/// transformer and the layout hooks see on the main thread for the duration of the preview's layout
/// (`MTAppearanceSnapshot.withPreview`). The chat's top bar follows «Скрыть в шапке чата».
enum MTAppearancePreview {
    /// Every slider the snapshot is built from (its drafts change the bubbles).
    private static var snapshotSliders: [MTSetting<Double>] {
        return [
            MTAppearanceSettings.bubbleIncomingRadius,
            MTAppearanceSettings.bubbleOutgoingRadius,
            MTAppearanceSettings.bubblePadding,
            MTAppearanceSettings.bubbleWidth,
            MTAppearanceSettings.bubbleBackgroundOpacity,
            MTAppearanceSettings.bubbleOutlineOpacity,
            MTAppearanceSettings.stickerSize,
            MTAppearanceSettings.nameColorSaturation
        ]
    }

    /// The configuration of a mini chat that follows the drafts of its screen.
    static func configuration(scope: String, overlays: Bool, content: @escaping (MTMenuContext) -> MTMiniChatContent) -> MTMiniChatConfiguration {
        var makeOverlays: ((MTMenuContext) -> [MTMiniChatOverlay])?
        if overlays {
            makeOverlays = { _ in
                let layers: [MTMiniChatOverlay] = [MTPreviewBackgroundOverlay(), MTPreviewEdgesOverlay()]
                return layers
            }
        }
        return MTMiniChatConfiguration(scope: scope, height: 196.0, content: content, presentationData: { context in
            // No slider is dragged: the app's own theme (already through the transformer).
            if MTAppearancePreview.drafts(context).isEmpty {
                return context.presentationData
            }
            return MTAppearanceTheme.previewPresentationData(context.presentationData)
        }, draftScope: { context, body in
            let drafts = MTAppearancePreview.drafts(context)
            if drafts.isEmpty {
                body()
            } else {
                MTAppearanceSnapshot.withPreview(MTAppearanceSnapshot.make(overriding: drafts), body)
            }
        }, overlays: makeOverlays)
    }

    /// The values the screen's sliders are being dragged to, of the sliders the snapshot is made of.
    private static func drafts(_ context: MTMenuContext) -> [String: Double] {
        var drafts: [String: Double] = [:]
        for setting in MTAppearancePreview.snapshotSliders {
            if let value = context.draftValue(forKey: setting.key) {
                drafts[setting.key] = value
            }
        }
        return drafts
    }

    /// The sample conversation with the chat's top bar as «Скрыть в шапке чата» sets it.
    static func sampleContent() -> MTMiniChatContent {
        var header = MTMiniChatContent.sampleHeader()
        header.hidesAvatar = MTAppearanceSettings.hideAvatar.value
        header.hidesTitle = MTAppearanceSettings.hideTitlePanel.value
        return MTMiniChatContent.sample(header: header)
    }

    /// A slider's value as the preview shows it: the draft while dragged.
    fileprivate static func reader(_ context: MTMenuContext) -> (MTSetting<Double>) -> Double {
        return { setting in
            return context.draftValue(forKey: setting.key) ?? setting.value
        }
    }
}

/// The animated chat background and the snow, under the bubbles.
private final class MTPreviewBackgroundOverlay: MTMiniChatOverlay {
    let view = UIView()
    let placement: MTMiniChatOverlayPlacement = .belowMessages

    private var videoView: MTLoopingVideoView?
    private var snowView: MTSnowView?

    init() {
        self.view.isUserInteractionEnabled = false
        self.view.clipsToBounds = true
    }

    func update(context: MTMenuContext, size: CGSize, insets: UIEdgeInsets) {
        let settings = MTBackgroundDecorSettings.current(double: MTAppearancePreview.reader(context))
        let bounds = CGRect(origin: CGPoint(), size: size)

        if settings.background, let url = MTAnimatedBackgrounds.fileURL(.chat) {
            let videoView: MTLoopingVideoView
            if let current = self.videoView {
                videoView = current
            } else {
                videoView = MTLoopingVideoView(frame: bounds)
                self.view.insertSubview(videoView, at: 0)
                self.videoView = videoView
            }
            videoView.frame = bounds
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
                snowView = MTSnowView(frame: bounds, kind: .background)
                self.view.addSubview(snowView)
                self.snowView = snowView
            }
            snowView.frame = bounds
            snowView.update(style: settings.snowStyle, intensity: settings.snowIntensity, isPaused: MTSystemState.current)
        } else if let snowView = self.snowView {
            self.snowView = nil
            snowView.removeFromSuperview()
        }
    }
}

/// The blur and gradient bands of the screen edges, above the bubbles: the top one under the
/// preview's top bar, the bottom one at the block's lower edge (the preview has no input panel).
private final class MTPreviewEdgesOverlay: MTMiniChatOverlay {
    let view = UIView()
    let placement: MTMiniChatOverlayPlacement = .aboveMessages

    private let topView = MTEdgeBandView(edge: .top)
    private let bottomView = MTEdgeBandView(edge: .bottom)

    init() {
        self.view.isUserInteractionEnabled = false
        self.view.clipsToBounds = true
        self.view.addSubview(self.topView)
        self.view.addSubview(self.bottomView)
    }

    func update(context: MTMenuContext, size: CGSize, insets: UIEdgeInsets) {
        let settings = MTEdgeDecorSettings.current(double: MTAppearancePreview.reader(context))
        self.view.isHidden = settings.isEmpty
        if settings.isEmpty {
            return
        }
        let theme = context.presentationData.theme
        let width = size.width

        let topBands = settings.bands(autoColor: theme.rootController.navigationBar.opaqueBackgroundColor)
        self.topView.update(width: width, inset: insets.top, blur: topBands.blur, gradient: topBands.gradient)
        self.topView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: self.topView.bandHeight(inset: insets.top, blur: topBands.blur, gradient: topBands.gradient))

        let bottomBands = settings.bands(autoColor: theme.chat.inputPanel.panelBackgroundColor.withAlphaComponent(1.0))
        self.bottomView.update(width: width, inset: 0.0, blur: bottomBands.blur, gradient: bottomBands.gradient)
        let bottomHeight = self.bottomView.bandHeight(inset: 0.0, blur: bottomBands.blur, gradient: bottomBands.gradient)
        self.bottomView.frame = CGRect(x: 0.0, y: size.height - bottomHeight, width: width, height: bottomHeight)
    }
}
