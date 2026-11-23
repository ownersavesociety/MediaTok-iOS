import Foundation
import UIKit
import MTCore
import MTSettingsUI
import MTFeaturesShared

/// The «Приватность» preview: a mini chat as the other person sees you. The header is your own
/// avatar with «в сети» / «был(а) недавно»; while ghost mode keeps your read receipt their message
/// stays at one check (no mark by the time — the owner had it removed). It follows the switches of
/// the account the menu is open for.
enum MTGhostPreview {
    static func register() {
        MTMenuRegistry.register(MTMenuRow(
            id: "ghostMode.preview",
            section: .privacyPreview,
            order: 100,
            title: { "" },
            kind: .preview(.miniChat(MTMiniChatConfiguration(scope: "ghostMode", height: 196.0, content: { context in
                let account = context.accountID
                let hidesOnline = MTGhostPolicy.isFunctionOn(.online, account: account)
                let hidesReads = MTGhostPolicy.isFunctionOn(.readReceipts, account: account)
                let status: String
                let statusIsAccent: Bool
                if hidesOnline {
                    status = MTStrings.GhostMode.Preview.recently
                    statusIsAccent = false
                } else {
                    status = MTStrings.GhostMode.Preview.online
                    statusIsAccent = true
                }
                var question = MTPreviewMessage(id: 1, isOutgoing: true, text: MTStrings.GhostMode.Preview.question, ageSeconds: 240)
                if hidesReads {
                    question.isUnread = true
                }
                var messages = [question]
                if !hidesReads {
                    messages.append(MTPreviewMessage(id: 2, isOutgoing: false, text: MTStrings.GhostMode.Preview.answer, ageSeconds: 120))
                }
                return MTMiniChatContent(header: MTMiniChatHeader(peer: .account, status: status, statusIsAccent: statusIsAccent), messages: messages)
            })))
        ))
    }
}
