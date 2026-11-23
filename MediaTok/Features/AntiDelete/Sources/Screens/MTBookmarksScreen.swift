import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import LocalizedPeerData
import MTCore
import MTFeaturesShared

/// «Все закладки» (or the bookmarks of one chat): newest first, a tap opens the message, a swipe
/// removes the bookmark. Bookmarks belong to the account (its own Postbox).
func mtMakeBookmarksController(context: AccountContext, peerId: PeerId?) -> ViewController {
    let postbox = context.account.postbox
    weak var weakController: ViewController?

    let _ = MTAntiDeleteOperations.reconcileBookmarks(postbox: postbox, accountId: context.account.id).start()

    let data = MTAntiDeleteIndexStore.bookmarksSignal(postbox: postbox)
    |> mapToSignal { list -> Signal<([MTBookmarkEntry], [EnginePeer.Id: EnginePeer]), NoError> in
        var entries = list.entries
        if let peerId {
            entries = entries.filter { $0.message.peer == peerId.mtKey }
        }
        let ids = Array(Set(entries.map { PeerId(mtKey: $0.message.peer) }))
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { result -> ([MTBookmarkEntry], [EnginePeer.Id: EnginePeer]) in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in result {
                if let peer {
                    peers[id] = peer
                }
            }
            return (entries, peers)
        }
    }

    let model = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, data)
    |> map { presentationData, data -> MTADScreenModel in
        let (entries, peers) = data
        var title = MTStrings.Bookmarks.All.title
        if let peerId, let peer = peers[peerId] {
            title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        }
        var model = MTADScreenModel(title: .text(title), sections: [])
        if entries.isEmpty {
            model.sections.append(MTADSection(id: "empty", rows: [MTADRow(id: "empty", kind: .footer(MTStrings.Bookmarks.All.empty))]))
            return model
        }
        var rows: [MTADRow] = []
        for entry in entries {
            let messageId = MessageId(mtKey: entry.message)
            guard let peer = peers[messageId.peerId] else {
                continue
            }
            let rowId = "bookmark.\(entry.message.stringValue)"
            let date = stringForMediumDate(timestamp: entry.messageDate, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
            rows.append(MTADRow(id: rowId, kind: .peer(peer: peer, text: entry.title, label: date, removeTitle: MTStrings.Bookmarks.All.remove)))
            let threadId = entry.threadId
            model.tap[rowId] = {
                if let navigationController = weakController?.navigationController as? NavigationController {
                    mtOpenMessage(context: context, navigationController: navigationController, messageId: messageId, threadId: threadId)
                }
            }
            model.remove[rowId] = {
                MTAntiDeleteMessageMenu.setBookmark(context: context, messageId: messageId, title: nil)
            }
        }
        rows.append(MTADRow(id: "footer", kind: .footer(MTStrings.Bookmarks.All.footer)))
        model.sections.append(MTADSection(id: "bookmarks", rows: rows))
        return model
    }

    let controller = mtMakeADListController(context: context, model: model)
    weakController = controller
    return controller
}
