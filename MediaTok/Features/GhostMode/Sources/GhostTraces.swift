import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PresentationDataUtils
import AlertUI
import LocalizedPeerData
import MTCore
import MTHooks
import MTFeaturesShared

/// «Следы»: what gives you away besides ghost mode itself.
///
/// - «Скрыть свой номер в Настройках» — the number is decided at every display (Settings header and
///   row, own profile), so the switch applies at once, without a restart, and has one place.
/// - «Подтверждать звонки» — a question before an outgoing call (point `MTCallHooks.outgoingCall`,
///   MediaTok spec).
/// - «Предупреждать перед историей» — before stories open, and only when the view would really be
///   sent (ghost mode does not keep it); the stories wait and nothing is marked as seen until the
///   answer (point `MTStoryHooks.openGate`, MediaTok spec).
enum MTGhostTraces {
    static func register() {
        // Ahead of a replaced (fake) number: hiding wins.
        MTPeerInfoHooks.displayedPhoneNumber.register({ request in
            if request.isAccountPeer && MTGhostSettings.hidePhoneInSettings.value {
                return .hidden
            }
            return nil
        }, order: -100)

        MTCallHooks.outgoingCall.register({ request, proceed in
            if !MTGhostSettings.confirmCalls.value {
                return false
            }
            MTGhostTraces.confirmCall(request, proceed: proceed)
            return true
        }, order: 100)

        MTStoryHooks.openGate.register({ request, completion in
            if !MTGhostSettings.warnBeforeStories.value {
                return false
            }
            if let peerId = request.peerId, MTGhostPolicy.hides(.storyViews, peerId: peerId, account: request.context.account.id.mt) {
                // Ghost mode keeps the view: nothing to warn about.
                return false
            }
            MTGhostTraces.warnBeforeStories(request, completion: completion)
            return true
        }, order: 100)
    }

    private static func confirmCall(_ request: MTOutgoingCallRequest, proceed: @escaping () -> Void) {
        let context = request.context
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: request.peerId))
        |> deliverOnMainQueue).start(next: { peer in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let name = peer?.compactDisplayTitle ?? ""
            let text = request.isVideo ? MTStrings.GhostMode.Call.confirmVideo(name: name) : MTStrings.GhostMode.Call.confirmAudio(name: name)
            context.sharedContext.mainWindow?.present(textAlertController(context: context, title: nil, text: text, actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .defaultAction, title: MTStrings.GhostMode.Call.call, action: {
                    proceed()
                })
            ]), on: .root)
        })
    }

    private static func warnBeforeStories(_ request: MTStoryOpenRequest, completion: @escaping (Bool) -> Void) {
        let context = request.context
        let alert = textAlertController(context: context, title: MTStrings.GhostMode.Stories.warnTitle, text: MTStrings.GhostMode.Stories.warnText, actions: [
            TextAlertAction(type: .genericAction, title: MTStrings.GhostMode.Stories.close, action: {
                completion(false)
            }),
            TextAlertAction(type: .defaultAction, title: MTStrings.GhostMode.Stories.watch, action: {
                completion(true)
            })
        ], dismissOnOutsideTap: false)
        if let controller = request.controller {
            controller.present(alert, in: .window(.root))
        } else {
            context.sharedContext.mainWindow?.present(alert, on: .root)
        }
    }
}
