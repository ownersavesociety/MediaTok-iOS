import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import MTCore

/// What a row, a preview or an action sees. A value type built on every rebuild of a screen;
/// it never outlives the screen (the handle inside is weak to the controller).
public struct MTMenuContext {
    public let context: AccountContext
    public let presentationData: PresentationData
    public let accountID: MTAccountID
    /// The account's own peer, once loaded (for «своя аватарка» in previews).
    public let accountPeer: EnginePeer?
    /// Section of the row being built (valid inside `.custom` builders).
    public internal(set) var sectionId: ItemListSectionId
    /// Scope of the preview being built (valid inside preview modifiers).
    public internal(set) var previewScope: String?
    let drafts: [String: Double]
    let handle: MTMenuScreenHandle

    init(context: AccountContext, presentationData: PresentationData, accountPeer: EnginePeer?, drafts: [String: Double], handle: MTMenuScreenHandle) {
        self.context = context
        self.presentationData = presentationData
        self.accountID = context.account.id.mt
        self.accountPeer = accountPeer
        self.sectionId = 0
        self.previewScope = nil
        self.drafts = drafts
        self.handle = handle
    }

    public var itemListPresentationData: ItemListPresentationData {
        return ItemListPresentationData(self.presentationData)
    }

    public var navigationController: NavigationController? {
        return self.handle.navigationController
    }

    /// The value a slider of this screen is being dragged to, or nil. Previews read it so they
    /// follow the finger while the setting itself is written only on release.
    public func draftValue(forKey key: String) -> Double? {
        return self.drafts[key]
    }

    /// Draft if a slider is being dragged, otherwise the stored value.
    public func displayValue(_ binding: MTMenuBinding<Double>) -> Double {
        if let draft = self.drafts[binding.key] {
            return draft
        }
        return binding.value(in: self)
    }

    public func push(_ controller: ViewController) {
        self.handle.push(controller)
    }

    public func present(_ controller: ViewController) {
        self.handle.present(controller, arguments: nil)
    }

    /// With presentation arguments, e.g. `.modalSheet` for a chat picker.
    public func present(_ controller: ViewController, arguments: ViewControllerPresentationArguments?) {
        self.handle.present(controller, arguments: arguments)
    }

    /// For plain UIKit controllers (document picker, activity sheet).
    public func presentNative(_ controller: UIViewController) {
        self.handle.presentNative(controller)
    }

    public func open(tab: MTMenuTabID) {
        self.handle.open(screen: .tab(tab), focusRowId: nil)
    }

    /// Opens a t.me link inside the app without resetting the navigation stack.
    public func openTelegramLink(_ url: String) {
        self.handle.openTelegramLink(url)
    }

    public func presentToast(_ text: String) {
        self.handle.presentToast(text)
    }
}

/// Owned by one screen; weakly references its controller. Also the single place that knows how to
/// open other menu screens (see `MTMenuScreen.swift`).
final class MTMenuScreenHandle {
    let context: AccountContext
    weak var controller: ViewController?

    init(context: AccountContext) {
        self.context = context
    }

    var navigationController: NavigationController? {
        return self.controller?.navigationController as? NavigationController
    }

    func push(_ controller: ViewController) {
        self.navigationController?.pushViewController(controller)
    }

    func present(_ controller: ViewController, arguments: ViewControllerPresentationArguments? = nil) {
        self.controller?.present(controller, in: .window(.root), with: arguments)
    }

    func presentNative(_ controller: UIViewController) {
        MTModalPresenter.presentOnTopmost(controller, preferredRoot: self.controller?.view.window?.rootViewController)
    }

    /// Every move to another menu screen goes through the access gates (`MTMenuAccessGates`).
    func open(screen: MTMenuScreenID, focusRowId: String?) {
        let context = self.context
        mtMenuWithAccess(.screen(screen), path: mtMenuScreenPathIds(screen), context: context, perform: { [weak self] in
            guard let self, let controller = mtMakeMenuScreen(context: context, screen: screen, focusRowId: focusRowId) else {
                return nil
            }
            self.push(controller)
            return controller
        })
    }

    func openTelegramLink(_ url: String) {
        guard let navigationController = self.navigationController else {
            return
        }
        mtOpenTelegramLink(context: self.context, url: url, navigationController: navigationController, present: { [weak self] controller in
            self?.present(controller)
        })
    }

    func presentToast(_ text: String) {
        mtPresentToast(context: self.context, text: text, present: { [weak self] controller in
            self?.present(controller)
        })
    }
}

/// Safe UIKit modal/sheet presentation helper: skips dismissing view controllers,
/// retries briefly during transition animations, and guarantees iPad/sheet popover anchors.
public enum MTModalPresenter {
    public static func activeRootViewController(preferredRoot: UIViewController? = nil) -> UIViewController? {
        if let preferredRoot, preferredRoot.viewIfLoaded?.window != nil {
            return preferredRoot
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow && $0.rootViewController != nil })?.rootViewController
            ?? windows.first(where: { $0.rootViewController != nil })?.rootViewController
    }

    public static func configurePopover(
        _ controller: UIViewController,
        hostView: UIView,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil
    ) {
        guard let popover = controller.popoverPresentationController else { return }
        if let sourceView, sourceView.window != nil, !sourceView.bounds.isEmpty {
            popover.sourceView = sourceView
            popover.sourceRect = sourceRect ?? sourceView.bounds
        } else {
            popover.sourceView = hostView
            popover.sourceRect = CGRect(x: hostView.bounds.midX, y: hostView.bounds.midY, width: 0.0, height: 0.0)
            popover.permittedArrowDirections = []
        }
    }

    private static func dismissActiveKeyboardIfNeeded(for controller: UIViewController) {
        if let alert = controller as? UIAlertController, !(alert.textFields ?? []).isEmpty {
            return
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    public static func presentOnTopmost(
        _ controller: UIViewController,
        preferredRoot: UIViewController? = nil,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        attempt: Int = 0
    ) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.presentOnTopmost(
                    controller,
                    preferredRoot: preferredRoot,
                    sourceView: sourceView,
                    sourceRect: sourceRect,
                    attempt: attempt
                )
            }
            return
        }
        guard controller.presentingViewController == nil,
              let root = self.activeRootViewController(preferredRoot: preferredRoot) else {
            return
        }
        var presenter = root
        while let presented = presenter.presentedViewController {
            if presented.isBeingDismissed {
                if attempt < 8 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        self.presentOnTopmost(
                            controller,
                            preferredRoot: preferredRoot,
                            sourceView: sourceView,
                            sourceRect: sourceRect,
                            attempt: attempt + 1
                        )
                    }
                }
                return
            }
            presenter = presented
        }
        if presenter.isBeingDismissed {
            if attempt < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    self.presentOnTopmost(
                        controller,
                        preferredRoot: preferredRoot,
                        sourceView: sourceView,
                        sourceRect: sourceRect,
                        attempt: attempt + 1
                    )
                }
            }
            return
        }
        self.dismissActiveKeyboardIfNeeded(for: controller)
        self.configurePopover(controller, hostView: presenter.view, sourceView: sourceView, sourceRect: sourceRect)
        presenter.present(controller, animated: true)
    }

    public static func presentWhenReady(
        _ controller: UIViewController,
        from host: UIViewController,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        attempt: Int = 0
    ) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak host] in
                guard let host else { return }
                self.presentWhenReady(
                    controller,
                    from: host,
                    sourceView: sourceView,
                    sourceRect: sourceRect,
                    attempt: attempt
                )
            }
            return
        }
        guard !host.isBeingDismissed,
              !host.isMovingFromParent,
              controller.presentingViewController == nil else {
            return
        }
        if let existing = host.presentedViewController {
            if existing.isBeingDismissed && attempt < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak host] in
                    guard let host else { return }
                    self.presentWhenReady(
                        controller,
                        from: host,
                        sourceView: sourceView,
                        sourceRect: sourceRect,
                        attempt: attempt + 1
                    )
                }
            }
            return
        }
        if host.viewIfLoaded?.window == nil {
            if attempt < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak host] in
                    guard let host else { return }
                    self.presentWhenReady(
                        controller,
                        from: host,
                        sourceView: sourceView,
                        sourceRect: sourceRect,
                        attempt: attempt + 1
                    )
                }
            }
            return
        }
        self.dismissActiveKeyboardIfNeeded(for: controller)
        self.configurePopover(controller, hostView: host.view, sourceView: sourceView, sourceRect: sourceRect)
        host.present(controller, animated: true)
    }
}
