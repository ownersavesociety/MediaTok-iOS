// The chat list screen's chrome: its container node after layout (search field, folder panel,
// Android-style buttons) and the navigation bar component after layout (gradient, snow, folder
// tabs placement). Here, not in ChatListUI, because ChatListNavigationBar lives in
// ChatListHeaderComponent, below ChatListUI. Row-level points: `MTChatListHooks` (ChatListUI).

import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import MTCore

public struct MTChatListContainerLayout {
    public let context: AccountContext
    /// ChatListControllerNode.
    public let node: ASDisplayNode
    public let layout: ContainerViewLayout
    public let navigationBarHeight: CGFloat
    public let transition: ContainedViewLayoutTransition
    /// Height MediaTok's own bottom chrome takes above `layout.intrinsicInsets.bottom` (the
    /// «Папки внизу» strip with its gaps); 0 = none. Floating buttons go above it.
    public let bottomAccessoryHeight: CGFloat
    /// The list itself (the container of the chat list pages), a subview of `node.view`. Decorations
    /// of the list's content belong right above it — under the folder strip, search and the rest.
    public let contentView: UIView?
}

public struct MTChatListNavigationBarLayout {
    /// ChatListNavigationBar.View.
    public let view: UIView
    public let size: CGSize
    public let isAnimated: Bool
}

public enum MTChatListChromeHooks {
    /// Observer after the chat list container's layout (main thread).
    public static let containerDidLayout = MTHookPoint<(MTChatListContainerLayout) -> Void>("chatListChrome.containerDidLayout")

    /// Observer after the chat list navigation bar's layout (main thread, scroll path).
    public static let navigationBarDidLayout = MTHookPoint<(MTChatListNavigationBarLayout) -> Void>("chatListChrome.navigationBarDidLayout")

    /// Policy: `false` turns off "swipe right to record a story" on the chat list.
    public static let storyCameraSwipe = MTHookPoint<(AccountContext) -> Bool?>("chatListChrome.storyCameraSwipe")

    public static func notifyContainerDidLayout(context: AccountContext, node: ASDisplayNode, layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition, bottomAccessoryHeight: CGFloat = 0.0, contentView: UIView? = nil) {
        if MTChatListChromeHooks.containerDidLayout.isEmpty {
            return
        }
        let value = MTChatListContainerLayout(context: context, node: node, layout: layout, navigationBarHeight: navigationBarHeight, transition: transition, bottomAccessoryHeight: bottomAccessoryHeight, contentView: contentView)
        for handler in MTChatListChromeHooks.containerDidLayout.handlers {
            handler(value)
        }
    }

    public static func notifyNavigationBarDidLayout(view: UIView, size: CGSize, isAnimated: Bool) {
        if MTChatListChromeHooks.navigationBarDidLayout.isEmpty {
            return
        }
        let value = MTChatListNavigationBarLayout(view: view, size: size, isAnimated: isAnimated)
        for handler in MTChatListChromeHooks.navigationBarDidLayout.handlers {
            handler(value)
        }
    }

    public static func allowsStoryCameraSwipe(context: AccountContext) -> Bool {
        for handler in MTChatListChromeHooks.storyCameraSwipe.handlers {
            if let value = handler(context) {
                return value
            }
        }
        return true
    }
}
