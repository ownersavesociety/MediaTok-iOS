// Compiled into TelegramUI (filegroup //MediaTok/MTHooks:TelegramUIHookSources): launch of
// MediaTok in the app and the call-site helpers of the UI points that need TelegramUI's
// internal types (ChatControllerImpl, ChatControllerNode). No feature logic here.

import Foundation
import UIKit
import ObjectiveC
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import ChatInterfaceState
import ChatPresentationInterfaceState
import SettingsUI
import UIKitRuntimeUtils
import MTCore
import MTHooks
import MTSettingsUI
import MTFeatures

// MARK: - Launch and lifecycle

private var mtApplicationLaunched = false

/// MediaTok hook target: AppDelegate, as soon as the App Group path is known and before the
/// AccountManager and the accounts exist.
func mtApplicationDidLaunch(appGroupPath: String) {
    assert(Thread.isMainThread)
    if mtApplicationLaunched {
        return
    }
    mtApplicationLaunched = true
    MTCore.bootstrap(MTCoreEnvironment(appGroupPath: appGroupPath, process: .app))
    // Screens MTSettingsUI can not link itself (it sits below SettingsUI).
    MTSettingsUIEnvironment.shared.makeTelegramLanguageController = { context in
        return LocalizationListController(context: context)
    }
    // `mediatok://settings` opens the MediaTok menu (features may claim other links).
    MTLifecycleHooks.openURL.register({ url, context, navigationController in
        guard let scheme = url.scheme?.lowercased(), scheme == "mediatok" else {
            return false
        }
        if url.host?.lowercased() == "settings" {
            navigationController.pushViewController(mtMakeSettingsController(context: context))
            return true
        }
        return false
    }, order: 1000)
    // A double tap that edits a message (MTMessageGestureHooks) reaches the chat's input panel.
    MTMessageGestureHooks.editMessage = { chatNode, messageId in
        guard let chatNode = chatNode as? ChatControllerNode, let interfaceInteraction = chatNode.interfaceInteraction else {
            return false
        }
        interfaceInteraction.setupEditMessage(messageId, { _ in })
        return true
    }
    // «В начало чата» of the quick buttons: the first message, not the newest one (performScrollToTop).
    MTChatScreenHooks.scrollToStartOfHistory = { controller in
        (controller as? ChatControllerImpl)?.scrollToStartOfHistory()
    }
    MTFeatures.registerAll()
    MTCore.runGlobalMigrations()
    MTHookRegistry.freeze()
}

func mtApplicationDidBecomeActive() {
    MTForegroundTaskScheduler.shared.applicationDidBecomeActive()
    MTLifecycleHooks.notifyDidBecomeActive()
}

func mtApplicationWillResignActive() {
    MTForegroundTaskScheduler.shared.applicationWillResignActive()
    MTSettingsStore.shared.flush()
    MTLifecycleHooks.notifyWillResignActive()
}

func mtApplicationDidEnterBackground() {
    MTForegroundTaskScheduler.shared.applicationWillResignActive()
    MTSettingsStore.shared.flush()
    MTLifecycleHooks.notifyDidEnterBackground()
}

/// MediaTok hook target: SharedAccountContext, whenever the app's PresentationData strings change.
func mtTelegramLanguageDidChange(_ presentationData: PresentationData) {
    // A custom language pack has its own code; its base language decides then (not English).
    MTLocalization.shared.setTelegramLanguageCode(presentationData.strings.primaryComponent.languageCode, baseCode: presentationData.strings.baseLanguageCode)
}

// MARK: - Chat screen

func mtChatScreen(_ controller: ChatControllerImpl) -> MTChatScreen {
    var isPreview = false
    if case .standard(.previewing) = controller.presentationInterfaceState.mode {
        isPreview = true
    }
    return MTChatScreen(context: controller.context, chatLocation: controller.chatLocation, controller: controller, isPreview: isPreview)
}

private var mtChatOverlaysKey: UInt8 = 0

private final class MTChatOverlaysBox: NSObject {
    let overlays: [MTChatOverlay]

    init(overlays: [MTChatOverlay]) {
        self.overlays = overlays
    }
}

/// MediaTok hook target: ChatControllerNode.init, after the wallpaper and the history are added.
func mtInstallChatOverlays(_ node: ChatControllerNode, context: AccountContext, chatLocation: ChatLocation, controller: ChatControllerImpl?) {
    if MTChatScreenHooks.overlays.isEmpty {
        return
    }
    var isPreview = false
    if let controller, case .standard(.previewing) = controller.presentationInterfaceState.mode {
        isPreview = true
    }
    let overlays = MTChatScreenHooks.makeOverlays(MTChatScreen(context: context, chatLocation: chatLocation, controller: controller, isPreview: isPreview))
    if overlays.isEmpty {
        return
    }
    for overlay in overlays {
        switch overlay.placement {
        case .aboveWallpaper:
            node.backgroundNode.supernode?.insertSubnode(overlay.node, aboveSubnode: node.backgroundNode)
        case .aboveHistory:
            node.historyNodeContainer.supernode?.insertSubnode(overlay.node, aboveSubnode: node.historyNodeContainer)
        }
    }
    objc_setAssociatedObject(node, &mtChatOverlaysKey, MTChatOverlaysBox(overlays: overlays), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

/// MediaTok hook target: ChatControllerNode.containerLayoutUpdated, next to the wallpaper frame.
func mtLayoutChatOverlays(_ node: ChatControllerNode, bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
    guard let box = objc_getAssociatedObject(node, &mtChatOverlaysKey) as? MTChatOverlaysBox else {
        return
    }
    for overlay in box.overlays {
        transition.updateFrame(node: overlay.node, frame: bounds)
        overlay.updateLayout(bounds: bounds, insets: insets, transition: transition)
    }
}

private var mtChatChromeCaptureKey: UInt8 = 0

/// MediaTok hook target: ChatControllerNode.containerLayoutUpdated, after upstream's own capture
/// protection. Hides the chat's chrome (header, input panel, the panels over it, navigation buttons,
/// overlays above the history) from screenshots and recordings while a feature asks for it
/// (MTChatScreenHooks.hidesChromeFromCapture). The layers are only touched when the answer changes.
func mtUpdateChatChromeCaptureProtection(_ node: ChatControllerNode) {
    if MTChatScreenHooks.hidesChromeFromCapture.isEmpty {
        return
    }
    let hides = MTChatScreenHooks.hidesChromeFromCapture(context: node.context, chatLocation: node.chatLocation)
    let applied = (objc_getAssociatedObject(node, &mtChatChromeCaptureKey) as? NSNumber)?.boolValue ?? false
    if hides == applied {
        return
    }
    objc_setAssociatedObject(node, &mtChatChromeCaptureKey, NSNumber(value: hides), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    var layers: [CALayer] = [node.inputPanelContainerNode.layer, node.inputContextPanelContainer.layer, node.navigateButtons.layer]
    if let navigationBar = node.navigationBar {
        layers.append(navigationBar.layer)
    }
    if let box = objc_getAssociatedObject(node, &mtChatOverlaysKey) as? MTChatOverlaysBox {
        for overlay in box.overlays where overlay.placement == .aboveHistory {
            layers.append(overlay.node.layer)
        }
    }
    for layer in layers {
        setLayerDisableScreenshots(layer, hides)
    }
}

/// MediaTok hook target: ChatControllerNode.shouldAnimateMessageTransition — no send animation while the
/// chrome is hidden from capture (the animation carries the typed text through unprotected layers).
func mtChatChromeHiddenFromCapture(_ node: ChatControllerNode) -> Bool {
    return (objc_getAssociatedObject(node, &mtChatChromeCaptureKey) as? NSNumber)?.boolValue ?? false
}

/// MediaTok hook target: ChatControllerNode.sendCurrentMessage. `true` = a feature took over the send.
func mtInterceptSendCurrentMessage(_ node: ChatControllerNode, proceed: @escaping () -> Void) -> Bool {
    if MTChatScreenHooks.willSendText.isEmpty {
        return false
    }
    guard let textInputPanelNode = node.textInputPanelNode else {
        return false
    }
    return MTChatScreenHooks.interceptSend(owner: node, request: MTComposedTextRequest(
        context: node.context,
        chatLocation: node.chatLocation,
        state: textInputPanelNode.inputTextState,
        replace: { [weak node] state in
            node?.interfaceInteraction?.updateTextInputStateAndMode({ _, mode in
                return (state, mode)
            })
        }
    ), proceed: proceed)
}

/// MediaTok hook target: ChatMessageDisplaySendMessageOptions — features' items at the end of the
/// Send button's menu (MTChatScreenHooks.sendMenuItems).
func mtSendMenuItems(_ selfController: ChatControllerImpl) -> [ContextMenuItem] {
    guard let peerId = selfController.chatLocation.peerId else {
        return []
    }
    return MTChatScreenHooks.sendMenuItems(MTSendMenuContext(
        context: selfController.context,
        peerId: peerId,
        predictedLanguage: selfController.contentData?.state.translationState?.fromLang,
        inputText: selfController.presentationInterfaceState.interfaceState.effectiveInputState.inputText,
        replaceInput: { [weak selfController] text in
            selfController?.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
                return state.updatedInterfaceState { interfaceState in
                    return interfaceState.withUpdatedComposeInputState(ChatTextInputState(inputText: text))
                }
            })
        },
        dismiss: { [weak selfController] in
            selfController?.sendMessageActionsController?.dismiss()
        },
        present: { [weak selfController] controller in
            selfController?.present(controller, in: .window(.root))
        }
    ))
}

/// MediaTok hook target: OpenChatMessage — a downloaded document a feature may open itself
/// (MTChatScreenHooks.openDocument). nil when the file is not downloaded or has no name.
func mtOpenDocumentRequest(_ params: OpenChatMessageParams, file: TelegramMediaFile) -> MTOpenDocumentRequest? {
    guard let fileName = file.fileName, let path = params.context.account.postbox.mediaBox.completedResourcePath(file.resource) else {
        return nil
    }
    return MTOpenDocumentRequest(context: params.context, fileName: fileName, path: path, controller: params.navigationController?.topViewController as? ViewController)
}

// MARK: - Message decoration redraws

private var mtHistoryRedrawKey: UInt8 = 0

private final class MTHistoryRedrawSubscription {
    let disposable: Disposable

    init(disposable: Disposable) {
        self.disposable = disposable
    }

    deinit {
        self.disposable.dispose()
    }
}

/// MediaTok hook target: ChatHistoryListNodeImpl.init. Re-lays out the bubbles a feature asked for
/// with MTMessageDecorationHooks.redraw(messageIds:), and every visible bubble after a settings
/// change (a chat under the settings screen must not keep stale decorations until its history
/// updates). The subscriptions live as long as the node.
func mtObserveMessageDecorationRedraws(_ node: ChatHistoryListNodeImpl) {
    if !MTMessageDecorationHooks.needsRedraws {
        return
    }
    let disposables = DisposableSet()
    disposables.add((MTMessageDecorationHooks.redrawRequests
    |> deliverOnMainQueue).start(next: { [weak node] messageIds in
        guard let node else {
            return
        }
        for messageId in messageIds {
            node.requestMessageUpdate(messageId)
        }
    }))
    // The first value is the current revision (the node was just created): skip it. Bursts of
    // changes (a slider, an import, `redrawAll()`) re-lay out once, 0.3 s after the last one.
    let pendingRedraw = MetaDisposable()
    disposables.add(pendingRedraw)
    let scheduleRedrawOfVisibleMessages: () -> Void = { [weak node] in
        pendingRedraw.set((Signal<Void, NoError>.single(Void())
        |> delay(0.3, queue: Queue.mainQueue())).start(next: { _ in
            guard let node else {
                return
            }
            var messageIds: [EngineMessage.Id] = []
            node.forEachVisibleMessageItemNode { itemNode in
                if let item = itemNode.item {
                    messageIds.append(item.message.id)
                }
            }
            for messageId in messageIds {
                node.requestMessageUpdate(messageId)
            }
        }))
    }
    var isFirstRevision = true
    disposables.add((MTMessageDecorationHooks.settingsRevisions
    |> deliverOnMainQueue).start(next: { _ in
        if isFirstRevision {
            isFirstRevision = false
            return
        }
        scheduleRedrawOfVisibleMessages()
    }))
    disposables.add((MTMessageDecorationHooks.redrawAllRequests
    |> deliverOnMainQueue).start(next: { _ in
        scheduleRedrawOfVisibleMessages()
    }))
    objc_setAssociatedObject(node, &mtHistoryRedrawKey, MTHistoryRedrawSubscription(disposable: disposables), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}
