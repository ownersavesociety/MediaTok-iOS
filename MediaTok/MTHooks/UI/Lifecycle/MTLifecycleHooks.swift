// App lifecycle for features that must react immediately (chat lock on leaving the app,
// overlays). Background work on return goes through `MTForegroundTaskScheduler` (MTCore), which
// throttles it — do not use `applicationDidBecomeActive` for network or disk work.

import Foundation
import UIKit
import Display
import AccountContext
import MTCore

public enum MTLifecycleHooks {
    /// Observers on the main thread.
    public static let applicationDidBecomeActive = MTHookPoint<() -> Void>("lifecycle.didBecomeActive")
    public static let applicationWillResignActive = MTHookPoint<() -> Void>("lifecycle.willResignActive")
    public static let applicationDidEnterBackground = MTHookPoint<() -> Void>("lifecycle.didEnterBackground")

    /// Observer: an account's root controllers (tab bar) were built — the place to start a
    /// feature's per-account UI machinery. Main thread.
    public static let rootControllersDidLoad = MTHookPoint<(AccountContext, NavigationController) -> Void>("lifecycle.rootControllersDidLoad")

    /// Policy: handle an opened URL (`mediatok://`, `mt://`, or any other) before Telegram does.
    /// `true` = handled. Main thread.
    public static let openURL = MTHookPoint<(URL, AccountContext, NavigationController) -> Bool>("lifecycle.openURL")

    /// Global hardware keyboard shortcuts (`KeyShortcut`) active across `TelegramBaseController` and `TabBarController`.
    public static let keyShortcuts = MTHookPoint<(AccountContext) -> [KeyShortcut]>("lifecycle.keyShortcuts")

    public static func collectKeyShortcuts(context: AccountContext) -> [KeyShortcut] {
        if MTLifecycleHooks.keyShortcuts.isEmpty {
            return []
        }
        var result: [KeyShortcut] = []
        for handler in MTLifecycleHooks.keyShortcuts.handlers {
            result.append(contentsOf: handler(context))
        }
        return result
    }

    public static func handleURL(_ url: URL, context: AccountContext, navigationController: NavigationController) -> Bool {
        for handler in MTLifecycleHooks.openURL.handlers {
            if handler(url, context, navigationController) {
                return true
            }
        }
        return false
    }

    public static func notifyDidBecomeActive() {
        for handler in MTLifecycleHooks.applicationDidBecomeActive.handlers {
            handler()
        }
    }

    public static func notifyWillResignActive() {
        for handler in MTLifecycleHooks.applicationWillResignActive.handlers {
            handler()
        }
    }

    public static func notifyDidEnterBackground() {
        for handler in MTLifecycleHooks.applicationDidEnterBackground.handlers {
            handler()
        }
    }

    public static func notifyRootControllersDidLoad(context: AccountContext, navigationController: NavigationController) {
        for handler in MTLifecycleHooks.rootControllersDidLoad.handlers {
            handler(context, navigationController)
        }
    }
}

/// Order, visibility and extra tabs of the main tab bar. Height, labels and width are MediaTok's
/// own edits in TabBarUI (not a frozen module).
public struct MTRootTabContext {
    public let context: AccountContext
    /// Telegram's controllers, for identification (`===`).
    public let contacts: ViewController
    public let calls: ViewController?
    public let chatList: ViewController
    public let settings: ViewController

    public init(context: AccountContext, contacts: ViewController, calls: ViewController?, chatList: ViewController, settings: ViewController) {
        self.context = context
        self.contacts = contacts
        self.calls = calls
        self.chatList = chatList
        self.settings = settings
    }
}

public enum MTRootHooks {
    /// Transformer of the tab controllers before they are set (reorder, hide, append).
    /// Keep the chat list: the app expects it.
    public static let tabControllers = MTHookPoint<(inout [ViewController], MTRootTabContext) -> Void>("root.tabControllers")

    public static func arrangeTabs(_ controllers: [ViewController], context: MTRootTabContext) -> [ViewController] {
        if MTRootHooks.tabControllers.isEmpty {
            return controllers
        }
        var result = controllers
        for handler in MTRootHooks.tabControllers.handlers {
            handler(&result, context)
        }
        if !result.contains(where: { $0 === context.chatList }) {
            assertionFailure("MTRootHooks.tabControllers removed the chat list")
            return controllers
        }
        return result
    }

    /// The index to select after `arrangeTabs`: where `preferred` ended up, or `fallback`.
    public static func selectedIndex(_ controllers: [ViewController], preferred: ViewController, fallback: Int) -> Int {
        if MTRootHooks.tabControllers.isEmpty {
            return fallback
        }
        return controllers.firstIndex(where: { $0 === preferred }) ?? fallback
    }
}
