import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import PromptUI
import UndoUI
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

    /// Presents Telegram's native `ActionSheetController` instead of UIKit `UIAlertController(.actionSheet)`.
    public func presentActionSheet(
        title: String? = nil,
        onCancel: (() -> Void)? = nil,
        buttons: [(title: String, isDestructive: Bool, action: () -> Void)]
    ) {
        mtPresentMenuActionSheet(context: self.context, from: self.handle.controller, title: title, onCancel: onCancel, buttons: buttons)
    }

    /// Presents Telegram's native `promptController` instead of UIKit `UIAlertController(.alert)` with textField.
    public func presentPrompt(
        title: String,
        subtitle: String? = nil,
        value: String = "",
        placeholder: String = "",
        characterLimit: Int = 512,
        onCancel: (() -> Void)? = nil,
        apply: @escaping (String) -> Void
    ) {
        mtPresentMenuPrompt(context: self.context, from: self.handle.controller, title: title, subtitle: subtitle, value: value, placeholder: placeholder, characterLimit: characterLimit, onCancel: onCancel, apply: apply)
    }
}

private final class MTOverlayContainableRootController: UIViewController {
    var onLayout: (() -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.onLayout?()
    }
}

/// Dedicated lightweight pass-through window (`windowLevel = .normal + 10`) used ONLY when a UIKit modal
/// (`UINavigationController`, `pageSheet`, etc.) is currently presented above Telegram's `Window1`,
/// ensuring native `ContainableController` sheets, prompts, alerts, and toasts render above the modal
/// without touching `presentedViewController`.
final class MTOverlayContainableWindow: UIWindow {
    static var activeWindow: MTOverlayContainableWindow?

    private let accountContext: AccountContext
    let overlayContext = PresentationContext()
    private let hostController = MTOverlayContainableRootController()
    private var keyboardHeight: CGFloat?
    private var kbChangeObserver: NSObjectProtocol?
    private var kbHideObserver: NSObjectProtocol?

    init(windowScene: UIWindowScene, context: AccountContext) {
        self.accountContext = context
        super.init(windowScene: windowScene)
        self.frame = windowScene.coordinateSpace.bounds
        self.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 10.0)
        self.backgroundColor = .clear
        self.isOpaque = false

        self.hostController.view.backgroundColor = .clear
        self.hostController.view.frame = self.bounds
        self.rootViewController = self.hostController

        self.overlayContext.view = self.hostController.view
        self.hostController.onLayout = { [weak self] in
            self?.pushCurrentLayout(transition: .immediate)
        }
        self.overlayContext.controllersUpdated = { [weak self] controllers in
            guard let self else { return }
            if controllers.isEmpty {
                self.tearDown()
            }
        }

        self.kbChangeObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let endVal = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
                return
            }
            let endRect = self.convert(endVal.cgRectValue, from: nil)
            let overlap = max(0.0, self.bounds.maxY - endRect.minY)
            self.keyboardHeight = overlap > 1.0 ? overlap : nil
            self.pushCurrentLayout(transition: .animated(duration: 0.25, curve: .spring))
        }
        self.kbHideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.keyboardHeight = nil
            self.pushCurrentLayout(transition: .animated(duration: 0.25, curve: .easeInOut))
        }

        self.pushCurrentLayout(transition: .immediate)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let obs = self.kbChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = self.kbHideObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func pushCurrentLayout(transition: ContainedViewLayoutTransition) {
        guard let base = (self.accountContext.sharedContext.mainWindow?.viewController as? ViewController)?.currentlyAppliedLayout else {
            return
        }
        let sz = self.bounds.size.width > 0 ? self.bounds.size : base.size
        let safe = self.safeAreaInsets
        let updated = base
            .withUpdatedSize(sz)
            .withUpdatedSafeInsets(safe)
            .withUpdatedInputHeight(self.keyboardHeight)
        self.overlayContext.containerLayoutUpdated(updated, transition: transition)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let containerView = self.hostController.view else {
            return nil
        }
        return self.overlayContext.hitTest(view: containerView, point: point, with: event)
    }

    private func tearDown() {
        self.isHidden = true
        if MTOverlayContainableWindow.activeWindow === self {
            MTOverlayContainableWindow.activeWindow = nil
        }
    }
}

/// Central z-order-safe presenter for Telegram `ContainableController`s (`ActionSheetController`,
/// `PromptController`, `AlertScreen`, `UndoOverlayController`). Automatically elevates presentation above
/// any active UIKit modal (`UINavigationController`, `pageSheet`, etc.) when one is on screen.
public func mtPresentContainableOverlay(
    _ controller: ViewController,
    context: AccountContext,
    from sourceController: ViewController? = nil,
    isToast: Bool = false
) {
    let run = {
        let appRoot = MTModalPresenter.activeRootViewController()
        let hasActiveUIKitModal = (appRoot?.presentedViewController != nil && appRoot?.presentedViewController?.isBeingDismissed == false)
        if hasActiveUIKitModal,
           (context.sharedContext.mainWindow?.viewController as? ViewController)?.currentlyAppliedLayout != nil,
           let windowScene = appRoot?.viewIfLoaded?.window?.windowScene
               ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let win: MTOverlayContainableWindow
            if let existing = MTOverlayContainableWindow.activeWindow, existing.windowScene === windowScene {
                win = existing
            } else {
                win = MTOverlayContainableWindow(windowScene: windowScene, context: context)
                MTOverlayContainableWindow.activeWindow = win
            }
            win.isHidden = false
            if !isToast {
                win.makeKey()
            }
            win.pushCurrentLayout(transition: .immediate)
            win.overlayContext.present(controller, on: .root, blockInteraction: false, completion: {})
            return
        }

        let target = sourceController ?? (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController
        if let target {
            target.present(controller, in: isToast ? .current : .window(.root))
        } else {
            context.sharedContext.mainWindow?.present(controller, on: .root)
        }
    }
    if Thread.isMainThread {
        run()
    } else {
        DispatchQueue.main.async(execute: run)
    }
}

public func mtPresentMenuActionSheet(
    context: AccountContext,
    from controller: ViewController? = nil,
    title: String? = nil,
    onCancel: (() -> Void)? = nil,
    buttons: [(title: String, isDestructive: Bool, action: () -> Void)]
) {
    DispatchQueue.main.async {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        var didSelectAction = false
        var didCancel = false
        let fireCancelOnce = {
            guard !didSelectAction, !didCancel else { return }
            didCancel = true
            onCancel?()
        }
        sheet.dismissed = { cancelled in
            if cancelled {
                fireCancelOnce()
            }
        }
        var items: [ActionSheetItem] = []
        if let title, !title.isEmpty {
            items.append(ActionSheetTextItem(title: title, parseMarkdown: false))
        }
        for b in buttons {
            items.append(ActionSheetButtonItem(
                title: b.title,
                color: b.isDestructive ? .destructive : .accent,
                action: { [weak sheet] in
                    didSelectAction = true
                    sheet?.dismissAnimated()
                    b.action()
                }
            ))
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(
                    title: presentationData.strings.Common_Cancel,
                    color: .accent,
                    font: .bold,
                    action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        fireCancelOnce()
                    }
                )
            ])
        ])
        mtPresentContainableOverlay(sheet, context: context, from: controller)
    }
}

public func mtPresentMenuPrompt(
    context: AccountContext,
    from controller: ViewController? = nil,
    title: String,
    subtitle: String? = nil,
    value: String = "",
    placeholder: String = "",
    characterLimit: Int = 512,
    onCancel: (() -> Void)? = nil,
    apply: @escaping (String) -> Void
) {
    DispatchQueue.main.async {
        var didFinish = false
        let fireCancelOnce = {
            guard !didFinish else { return }
            didFinish = true
            onCancel?()
        }
        let prompt = promptController(
            context: context,
            text: title,
            subtitle: subtitle,
            value: value,
            placeholder: placeholder,
            characterLimit: characterLimit,
            apply: { result in
                if let result {
                    guard !didFinish else { return }
                    didFinish = true
                    apply(result)
                } else {
                    fireCancelOnce()
                }
            },
            dismissed: {
                fireCancelOnce()
            }
        )
        mtPresentContainableOverlay(prompt, context: context, from: controller)
    }
}

public func mtPresentMenuAlert(
    context: AccountContext,
    from controller: ViewController? = nil,
    title: String?,
    text: String,
    confirmTitle: String? = nil,
    destructive: Bool = false,
    confirmAction: (() -> Void)? = nil
) {
    DispatchQueue.main.async {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var actions: [TextAlertAction] = []
        if let confirmTitle, let confirmAction {
            actions.append(TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}))
            actions.append(TextAlertAction(type: destructive ? .destructiveAction : .defaultAction, title: confirmTitle, action: confirmAction))
        } else {
            actions.append(TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {}))
        }
        let alert = textAlertController(context: context, title: title, text: text, actions: actions)
        mtPresentContainableOverlay(alert, context: context, from: controller)
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
        if let preferredRoot,
           let win = preferredRoot.viewIfLoaded?.window,
           !(win is MTOverlayContainableWindow) {
            return preferredRoot
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }.filter { !($0 is MTOverlayContainableWindow) }
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
        let _ = controller
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
