import Foundation
import UIKit
import ObjectiveC
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import ChatListHeaderComponent
import MTCore
import MTHooks
import MTAppearanceSettings

/// The chat list's header and footer decorations: the header gradient and snowfall (the old
/// «Градиент хедера/футера» never painted anything — its six settings were read by nobody), the
/// footer gradient. Attached once to the navigation bar view / the container node and kept in sync
/// by one subscription each; the layout hooks only move them.
enum MTChatListDecor {
    private static let themePromise = Promise<PresentationTheme>()
    private static var isTrackingTheme = false

    static func register() {
        MTChatListChromeHooks.containerDidLayout.register({ layout in
            MTChatListDecor.trackTheme(layout.context)
            MTChatListFooterDecor.update(node: layout.node, layout: layout.layout, contentView: layout.contentView)
        }, order: 100)

        MTChatListChromeHooks.navigationBarDidLayout.register({ layout in
            guard let barView = layout.view as? ChatListNavigationBar.View else {
                return
            }
            MTChatListHeaderDecor.update(barView: barView, size: layout.size)
        }, order: 100)
    }

    /// The app's theme, for the «automatic» colors (the same for every account).
    static var theme: Signal<PresentationTheme, NoError> {
        return MTChatListDecor.themePromise.get()
    }

    private static func trackTheme(_ context: AccountContext) {
        if MTChatListDecor.isTrackingTheme {
            return
        }
        MTChatListDecor.isTrackingTheme = true
        MTChatListDecor.themePromise.set(context.sharedContext.presentationData
        |> map { presentationData -> PresentationTheme in
            return presentationData.theme
        })
    }
}

private final class MTChatListHeaderDecor {
    private static var key: UInt8 = 0

    private weak var barView: ChatListNavigationBar.View?
    private let bandView = MTEdgeBandView(edge: .top)
    private let snowView = MTSnowView(frame: CGRect(), kind: .header)
    private var size = CGSize()
    private var state: (MTEdgeDecorSettings, MTBackgroundDecorSettings, Bool, PresentationTheme)?
    private var disposable: Disposable?

    private init(barView: ChatListNavigationBar.View) {
        self.barView = barView
        self.bandView.isHidden = true
        self.snowView.isHidden = true

        self.disposable = (combineLatest(MTEdgeDecorSettings.signal, MTBackgroundDecorSettings.signal, MTSystemState.reducesMotion, MTChatListDecor.theme)
        |> deliverOnMainQueue).start(next: { [weak self] edges, background, reducesMotion, theme in
            guard let self else {
                return
            }
            self.state = (edges, background, reducesMotion, theme)
            self.apply()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    static func update(barView: ChatListNavigationBar.View, size: CGSize) {
        let decor: MTChatListHeaderDecor
        if let current = objc_getAssociatedObject(barView, &MTChatListHeaderDecor.key) as? MTChatListHeaderDecor {
            decor = current
        } else {
            decor = MTChatListHeaderDecor(barView: barView)
            objc_setAssociatedObject(barView, &MTChatListHeaderDecor.key, decor, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        decor.size = size
        decor.apply()
    }

    private func apply() {
        guard let barView = self.barView, let (edges, background, reducesMotion, theme) = self.state, self.size.width > 0.0 else {
            return
        }
        // Behind the search field and the header content, above the bar's own fade.
        let edgeView = barView.edgeEffectBackgroundView
        for view in [self.bandView, self.snowView] where view.superview !== barView {
            if edgeView.superview === barView {
                barView.insertSubview(view, aboveSubview: edgeView)
            } else {
                barView.insertSubview(view, at: 0)
            }
        }

        let showsGradient = edges.showsInChatList
        self.bandView.isHidden = !showsGradient
        if showsGradient {
            let bands = edges.bands(autoColor: theme.rootController.navigationBar.opaqueBackgroundColor)
            self.bandView.update(width: self.size.width, inset: self.size.height, blur: nil, gradient: bands.gradient)
            self.bandView.frame = CGRect(x: 0.0, y: 0.0, width: self.size.width, height: self.bandView.bandHeight(inset: self.size.height, blur: nil, gradient: bands.gradient))
        }

        if background.snow {
            self.snowView.frame = CGRect(origin: CGPoint(), size: self.size)
            self.snowView.update(style: background.snowStyle, intensity: background.snowIntensity, isPaused: reducesMotion)
        } else {
            self.snowView.isHidden = true
        }
    }
}

private final class MTChatListFooterDecor {
    private static var key: UInt8 = 0

    private weak var node: ASDisplayNode?
    /// The list's own view: the band lies right above it, so the chrome over the list (the
    /// «Папки внизу» strip, search) stays above the band.
    private weak var contentView: UIView?
    private let bandView = MTEdgeBandView(edge: .bottom)
    private var layout: ContainerViewLayout?
    private var state: (MTEdgeDecorSettings, PresentationTheme)?
    private var disposable: Disposable?

    private init(node: ASDisplayNode) {
        self.node = node
        self.bandView.isHidden = true
        self.disposable = (combineLatest(MTEdgeDecorSettings.signal, MTChatListDecor.theme)
        |> deliverOnMainQueue).start(next: { [weak self] edges, theme in
            guard let self else {
                return
            }
            self.state = (edges, theme)
            self.apply()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    static func update(node: ASDisplayNode, layout: ContainerViewLayout, contentView: UIView?) {
        let decor: MTChatListFooterDecor
        if let current = objc_getAssociatedObject(node, &MTChatListFooterDecor.key) as? MTChatListFooterDecor {
            decor = current
        } else {
            decor = MTChatListFooterDecor(node: node)
            objc_setAssociatedObject(node, &MTChatListFooterDecor.key, decor, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        decor.layout = layout
        decor.contentView = contentView
        decor.apply()
    }

    private func apply() {
        guard let node = self.node, let layout = self.layout, let (edges, theme) = self.state else {
            return
        }
        let showsGradient = edges.showsInChatList
        self.bandView.isHidden = !showsGradient
        if !showsGradient {
            return
        }
        if let contentView = self.contentView, contentView.superview === node.view {
            let subviews = node.view.subviews
            if let contentIndex = subviews.firstIndex(where: { $0 === contentView }), !(contentIndex + 1 < subviews.count && subviews[contentIndex + 1] === self.bandView) {
                node.view.insertSubview(self.bandView, aboveSubview: contentView)
            }
        } else if self.bandView.superview !== node.view {
            node.view.addSubview(self.bandView)
        } else {
            node.view.bringSubviewToFront(self.bandView)
        }
        let bands = edges.bands(autoColor: theme.rootController.tabBar.backgroundColor.withAlphaComponent(1.0))
        let inset = layout.intrinsicInsets.bottom
        self.bandView.update(width: layout.size.width, inset: inset, blur: nil, gradient: bands.gradient)
        let height = self.bandView.bandHeight(inset: inset, blur: nil, gradient: bands.gradient)
        self.bandView.frame = CGRect(x: 0.0, y: layout.size.height - height, width: layout.size.width, height: height)
    }
}
