import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import PromptUI
import MTCore
import MTSettingsUI
import MTFeaturesShared

/// The profile the hyperlink stage links to. It is resolved when it is set: only a user this
/// account can see is accepted (a mention of an unknown user is dropped by Telegram silently when
/// the message is serialized), so a link never disappears without the user knowing.
enum MTHyperlinkTarget {
    private static var titles: [MTPeerKey: String] = [:]

    static func label(menuContext: MTMenuContext) -> String {
        guard let key = MTMessagesSettings.hyperlinkTarget.value(for: menuContext.accountID) else {
            return MTStrings.Sending.Menu.hyperlinkTargetNone
        }
        if let title = MTHyperlinkTarget.titles[key] {
            return title
        }
        let context = menuContext.context
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: PeerId(mtKey: key)))
        |> deliverOnMainQueue).start(next: { peer in
            if let peer {
                MTHyperlinkTarget.titles[key] = peer.debugDisplayTitle
            }
        })
        return "\(key.id)"
    }

    static func edit(menuContext: MTMenuContext) {
        let context = menuContext.context
        let accountId = menuContext.accountID
        let current = MTMessagesSettings.hyperlinkTarget.value(for: accountId).map { "\($0.id)" }
        let controller = promptController(context: context, text: MTStrings.Sending.Hyperlink.promptTitle, subtitle: MTStrings.Sending.Hyperlink.promptText, value: current, characterLimit: 64, apply: { value in
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                MTMessagesSettings.hyperlinkTarget.set(nil, for: accountId)
                return
            }
            MTHyperlinkTarget.resolve(trimmed, context: context, completion: { peer in
                guard let peer else {
                    menuContext.presentToast(MTStrings.Sending.Hyperlink.notFound)
                    return
                }
                guard case .user = peer else {
                    menuContext.presentToast(MTStrings.Sending.Hyperlink.notUser)
                    return
                }
                MTHyperlinkTarget.titles[peer.id.mtKey] = peer.debugDisplayTitle
                MTMessagesSettings.hyperlinkTarget.set(peer.id.mtKey, for: accountId)
            })
        })
        menuContext.present(controller)
    }

    private static func resolve(_ text: String, context: AccountContext, completion: @escaping (EnginePeer?) -> Void) {
        var value = text
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        if let id = Int64(value), id > 0 {
            let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).start(next: { peer in
                completion(peer)
            })
            return
        }
        let _ = (context.engine.peers.resolvePeerByName(name: value, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(peer) = result else {
                return .complete()
            }
            return .single(peer)
        }
        |> take(1)
        |> deliverOnMainQueue).start(next: { peer in
            completion(peer)
        })
    }
}
