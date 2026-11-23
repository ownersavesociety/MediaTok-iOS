import Foundation
import UIKit
import ObjectiveC
import AsyncDisplayKit
import Display
import TelegramCore
import AccountContext
import MTCore
import MTHooks
import MTFeaturesShared

/// The shared media of a protected chat in its profile (`MTPeerInfoHooks.paneContainerDidLayout`):
/// a profile opened from the contacts, the search or a mention shows a lock over the media area
/// («Медиа», «Файлы», «Ссылки»…) until the common check passes — the same rule as the chat's own
/// cover. A profile opened from the unlocked chat is not asked again (the chat's grant covers it);
/// a grant given here lives as long as this profile screen.
enum MTProfileMediaLock {
    private static var coverKey: UInt8 = 0

    static func register() {
        MTPeerInfoHooks.paneContainerDidLayout.register({ layout in
            MTProfileMediaLock.update(layout)
        })
    }

    /// Main thread, every layout of the profile: answers from memory, touches views only on change.
    private static func update(_ layout: MTPeerInfoPaneLayout) {
        let container = layout.paneContainer
        let context = layout.context
        let account = context.account.id.mt
        let peerId = layout.peerId
        var locked = false
        if !layout.isSettings && layout.hasPanes && peerId != context.account.peerId {
            locked = MTChatLock.shared.needsUnlock(account: account, peerId: peerId, controller: layout.controller)
        }
        let existing = objc_getAssociatedObject(container, &MTProfileMediaLock.coverKey) as? MTLockCoverView
        if !locked {
            if let existing {
                existing.removeFromSuperview()
                objc_setAssociatedObject(container, &MTProfileMediaLock.coverKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            return
        }
        let cover: MTLockCoverView
        if let existing {
            cover = existing
        } else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            cover = MTLockCoverView(theme: presentationData.theme, title: MTStrings.Security.ChatLock.mediaCoverTitle, unlockTitle: MTStrings.Security.ChatLock.coverUnlock, closeTitle: nil, contentTopInset: 48.0)
            let controller = layout.controller
            cover.unlock = { [weak container, weak controller] in
                MTLocalAuthGate.shared.authenticate(context: context, reason: MTStrings.Security.Auth.reasonChat, completion: { granted in
                    guard granted, let controller else {
                        return
                    }
                    MTChatLock.shared.grant(account: account, peerId: peerId, controller: controller)
                    if let container, let cover = objc_getAssociatedObject(container, &MTProfileMediaLock.coverKey) as? MTLockCoverView {
                        cover.removeFromSuperview()
                        objc_setAssociatedObject(container, &MTProfileMediaLock.coverKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                    }
                    controller.requestLayout(transition: .immediate)
                })
            }
            container.view.addSubview(cover)
            objc_setAssociatedObject(container, &MTProfileMediaLock.coverKey, cover, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        cover.frame = container.bounds
        // Panes are added to the container later (tab switches, loading): stay above them, for
        // touches too.
        container.view.bringSubviewToFront(cover)
    }
}
