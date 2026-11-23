import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import ChatListUI
import MTCore
import MTHooks

// Registrations on the points that requests R1 and R2 of this zone add to the frozen MTHooks
// (`MTChatListHooks.accessoryPeers`, `MTGalleryHooks.videoItemDidLoad/videoItemDidLayout`). This directory is the only part of the module that needs them; if
// the requests wait, exclude `Sources/Pending/**` in BUILD and drop the one
// `MTCallsMediaPending.register()` call — the rest of the zone compiles without them (download status
// then shows the line only for rows laid out after a download started; subtitles have no host).

enum MTCallsMediaPending {
    static func register() {
        // R1: chats with a download — their rows re-lay out when it starts or ends, never per percent.
        MTChatListHooks.accessoryPeers.register({ context in
            let service = MTDownloadStatusService.service(for: context)
            return combineLatest(service.activePeers, MTCallsMediaSettings.statusInChatList.signal)
            |> map { peers, enabled -> Set<EnginePeer.Id> in
                return enabled ? peers : Set()
            }
        })

        // R2: the gallery's video items host the subtitles line.
        MTGalleryHooks.videoItemDidLoad.register({ item in
            MTSubtitlesFeature.videoItemDidLoad(context: item.context, message: item.message, file: item.file, itemNode: item.itemNode, status: item.status)
        })
        MTGalleryHooks.videoItemDidLayout.register({ layout in
            MTSubtitlesFeature.videoItemDidLayout(itemNode: layout.itemNode, size: layout.size, bottomInset: layout.bottomInset, transition: layout.transition)
        })
    }
}
