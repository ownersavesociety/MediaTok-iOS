import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import MTCore
import MTSettingsUI
import MTFeaturesShared

// Menu rows of «Сообщения › Удалённые и изменённые», the «Сообщения» preview and the bookmark rows
// in «Меню и жесты». One place per setting; titles are computed at display time.

extension MTMenuTabID {
    static let antiDeleteHistory = MTMenuTabID("antiDelete.history")
    static let antiDeleteExclusions = MTMenuTabID("antiDelete.exclusions")
    static let bookmarksAll = MTMenuTabID("bookmarks.all")
}

extension MTMenuSectionID {
    static let antiDeleteEdits = MTMenuSectionID("antiDelete.edits")
    static let antiDeleteStorage = MTMenuSectionID("antiDelete.storage")
}

enum MTAntiDeleteMenu {
    private static var capturesAnything: Bool {
        return MTAntiDeleteSettings.enabled.value || MTAntiDeleteSettings.keepOwn.value || MTAntiDeleteSettings.keepSelfDestructing.value
    }

    private static func percent(_ value: Double) -> String {
        return MTStrings.AntiDelete.Menu.percent(value: "\(Int(value.rounded()))")
    }

    static func register() {
        let main = MTMenuSectionID.main(of: .messagesAntiDelete)

        // MARK: Previews

        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.categoryPreview",
            section: .messagesPreview,
            order: 100,
            title: { "" },
            kind: .preview(.miniChat(MTMiniChatConfiguration(scope: "antiDelete", height: 300.0, content: { context in
                return MTAntiDeleteMenu.previewContent(context)
            })))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.preview",
            section: .preview(of: .messagesAntiDelete),
            order: 100,
            title: { "" },
            kind: .preview(.miniChat(MTMiniChatConfiguration(scope: "antiDelete", height: 300.0, content: { context in
                return MTAntiDeleteMenu.previewContent(context)
            })))
        ))

        // MARK: Deleted messages

        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.enabled",
            section: main,
            order: 100,
            title: { MTStrings.AntiDelete.Menu.enabled },
            subtitle: { MTStrings.AntiDelete.Menu.enabledInfo },
            kind: .toggle(.global(MTAntiDeleteSettings.enabled)),
            searchKeywords: { [MTStrings.AntiDelete.Menu.keywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.keepOwn",
            section: main,
            order: 200,
            title: { MTStrings.AntiDelete.Menu.keepOwn },
            subtitle: { MTStrings.AntiDelete.Menu.keepOwnInfo },
            kind: .toggle(.global(MTAntiDeleteSettings.keepOwn))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.keepSelfDestructing",
            section: main,
            order: 300,
            title: { MTStrings.AntiDelete.Menu.keepSelfDestructing },
            subtitle: { MTStrings.AntiDelete.Menu.keepSelfDestructingInfo },
            kind: .toggle(.global(MTAntiDeleteSettings.keepSelfDestructing))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.secretChats",
            section: main,
            order: 400,
            title: { MTStrings.AntiDelete.Menu.secretChats },
            subtitle: { MTStrings.AntiDelete.Menu.secretChatsInfo },
            kind: .toggle(.global(MTAntiDeleteSettings.secretChats)),
            isVisible: { _ in MTAntiDeleteMenu.capturesAnything || MTAntiDeleteSettings.editHistory.value }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.keepMedia",
            section: main,
            order: 500,
            title: { MTStrings.AntiDelete.Menu.keepMedia },
            subtitle: { MTStrings.AntiDelete.Menu.keepMediaInfo },
            kind: .toggle(.global(MTAntiDeleteSettings.keepMedia)),
            isVisible: { _ in MTAntiDeleteMenu.capturesAnything }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.transparency",
            section: main,
            order: 600,
            title: { MTStrings.AntiDelete.Menu.transparency },
            kind: .slider(.global(MTAntiDeleteSettings.transparency), range: MTAntiDeleteSettings.transparencyRange, step: 5.0, format: { value in
                return MTAntiDeleteMenu.percent(value)
            })
        ))
        // A reply to a deleted message needs no setting: it always goes as AyuGram's pseudo-reply
        // (an ordinary message with the quote on top) — the preview and «Сохранять удалённые» say so.

        // MARK: Edits and local edits — one section

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .antiDeleteEdits, screen: .tab(.messagesAntiDelete), order: 300, header: { MTStrings.AntiDelete.Menu.editsHeader }, footer: { _ in MTStrings.AntiDelete.Menu.editsFooter }))
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.editHistory",
            section: .antiDeleteEdits,
            order: 100,
            title: { MTStrings.AntiDelete.Menu.editHistory },
            subtitle: { MTStrings.AntiDelete.Menu.editHistoryInfo },
            kind: .toggle(.global(MTAntiDeleteSettings.editHistory)),
            searchKeywords: { [MTStrings.AntiDelete.Menu.editKeywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.editHistoryInline",
            section: .antiDeleteEdits,
            order: 200,
            title: { MTStrings.AntiDelete.Menu.editHistoryInline },
            subtitle: { MTStrings.AntiDelete.Menu.editHistoryInlineInfo },
            kind: .toggle(.global(MTAntiDeleteSettings.editHistoryInline)),
            isVisible: { _ in MTAntiDeleteSettings.editHistory.value }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.versionsTransparency",
            section: .antiDeleteEdits,
            order: 300,
            title: { MTStrings.AntiDelete.Menu.versionsTransparency },
            kind: .slider(.global(MTAntiDeleteSettings.versionsTransparency), range: MTAntiDeleteSettings.transparencyRange, step: 5.0, format: { value in
                return MTAntiDeleteMenu.percent(value)
            }),
            isVisible: { _ in MTAntiDeleteSettings.editHistory.value && MTAntiDeleteSettings.editHistoryInline.value }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.localEdit",
            section: .antiDeleteEdits,
            order: 500,
            title: { MTStrings.AntiDelete.Menu.localEdit },
            subtitle: { MTStrings.AntiDelete.Menu.localEditInfo },
            kind: .toggle(.global(MTAntiDeleteSettings.localEdit))
        ))

        // MARK: Storage

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: .antiDeleteStorage, screen: .tab(.messagesAntiDelete), order: 600, header: { MTStrings.AntiDelete.Menu.storageHeader }, footer: { _ in MTStrings.AntiDelete.Menu.autoClearFooter }))
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: .antiDeleteHistory,
                parent: .tab(.messagesAntiDelete),
                title: { MTStrings.AntiDelete.History.title },
                makeScreen: { context in
                    return mtMakeAntiDeleteHistoryController(context: context.context, kind: .deleted)
                },
                searchKeywords: { [MTStrings.AntiDelete.Menu.historyKeywords] }
            ),
            linkIn: .antiDeleteStorage,
            order: 100,
            subtitle: { MTStrings.AntiDelete.Menu.historyInfo },
            icon: .bundle("Chat/Context Menu/Time"),
            label: { context in
                let deleted = MTAntiDeleteAccounts.shared.summary(account: context.context.account.id, kind: .deleted).totalCount
                let edited = MTAntiDeleteAccounts.shared.summary(account: context.context.account.id, kind: .edited).totalCount
                if deleted + edited == 0 {
                    return nil
                }
                return "\(deleted + edited)"
            }
        )
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: .antiDeleteExclusions,
                parent: .tab(.messagesAntiDelete),
                title: { MTStrings.AntiDelete.Exclusions.title },
                makeScreen: { context in
                    return mtMakeAntiDeleteExclusionsController(context: context.context)
                },
                searchKeywords: { [MTStrings.AntiDelete.Menu.exclusionsKeywords] }
            ),
            linkIn: .antiDeleteStorage,
            order: 200,
            subtitle: { MTStrings.AntiDelete.Menu.exclusionsInfo },
            icon: .bundle("Chat/Context Menu/Ban"),
            label: { context in
                let account = context.accountID
                var count = MTAntiDeleteSettings.excludedPeers.value(for: account).count + MTAntiDeleteSettings.excludedFolders.value(for: account).count
                for setting in [MTAntiDeleteSettings.excludeGroups, MTAntiDeleteSettings.excludeBots, MTAntiDeleteSettings.excludeChannels] where setting.value {
                    count += 1
                }
                return count == 0 ? nil : "\(count)"
            }
        )
        MTMenuRegistry.register(MTMenuRow(
            id: "antiDelete.autoClear",
            section: .antiDeleteStorage,
            order: 300,
            title: { MTStrings.AntiDelete.Menu.autoClear },
            icon: .bundle("Chat/Context Menu/Timer"),
            kind: .choice(.global(MTAntiDeleteSettings.autoClear), options: MTAntiDeleteRetention.allCases.map { retention in
                return MTMenuChoiceOption(value: retention.rawValue, title: { MTAntiDeleteMenu.retentionTitle(retention) })
            })
        ))

        // MARK: Bookmarks («Меню и жесты»)

        let gestures = MTMenuSectionID.main(of: .messagesMenuGestures)
        MTMenuRegistry.register(MTMenuRow(
            id: "bookmarks.enabled",
            section: gestures,
            order: 800,
            title: { MTStrings.Bookmarks.Menu.enabled },
            subtitle: { MTStrings.Bookmarks.Menu.enabledInfo },
            icon: .bundle("Chat/Context Menu/Tag"),
            kind: .toggle(.global(MTBookmarkSettings.enabled)),
            searchKeywords: { [MTStrings.Bookmarks.Menu.keywords] }
        ))
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: .bookmarksAll,
                parent: .tab(.messagesMenuGestures),
                title: { MTStrings.Bookmarks.All.title },
                makeScreen: { context in
                    return mtMakeBookmarksController(context: context.context, peerId: nil)
                },
                searchKeywords: { [MTStrings.Bookmarks.Menu.keywords] }
            ),
            linkIn: gestures,
            order: 900,
            subtitle: { MTStrings.Bookmarks.Menu.allInfo },
            icon: .bundle("Chat/Context Menu/ReadingList")
        )
    }

    static func retentionTitle(_ retention: MTAntiDeleteRetention) -> String {
        switch retention {
        case .never:
            return MTStrings.AntiDelete.AutoClear.never
        case .day:
            return MTStrings.AntiDelete.AutoClear.day
        case .week:
            return MTStrings.AntiDelete.AutoClear.week
        case .month:
            return MTStrings.AntiDelete.AutoClear.month
        case .quarter:
            return MTStrings.AntiDelete.AutoClear.quarter
        case .year:
            return MTStrings.AntiDelete.AutoClear.year
        }
    }

    /// The «Сообщения» preview, as the chat shows it with the current switches: while deleted
    /// messages are kept, a deleted one with the current transparency and a reply to it exactly as
    /// it is sent — AyuGram's pseudo-reply, the quote on top (no author line: a one-to-one chat with
    /// that author); with them off neither exists, as in Telegram. The edited message carries the
    /// history mark only while the history is kept.
    static func previewContent(_ context: MTMenuContext) -> MTMiniChatContent {
        let keepsDeleted = MTAntiDeleteSettings.enabled.value
        let deletedText = MTStrings.AntiDelete.Preview.deletedText
        let transparency = context.displayValue(.global(MTAntiDeleteSettings.transparency))
        var messages: [MTPreviewMessage] = []
        messages.append(MTPreviewMessage(id: 1, isOutgoing: false, text: MTStrings.AntiDelete.Preview.firstText, ageSeconds: 900))
        if keepsDeleted {
            messages.append(MTPreviewMessage(id: 2, isOutgoing: false, text: deletedText, alpha: MTAntiDeleteSettings.alpha(forTransparency: transparency), mark: MTPreviewMark(statusText: MTAntiDeleteDecorations.deletedMark), ageSeconds: 840))
        }
        let historyMark: MTPreviewMark? = MTAntiDeleteSettings.editHistory.value ? MTPreviewMark(statusText: MTAntiDeleteDecorations.historyMark(versionCount: 1)) : nil
        messages.append(MTPreviewMessage(id: 3, isOutgoing: false, text: MTStrings.AntiDelete.Preview.editedText, isEdited: true, mark: historyMark, ageSeconds: 600))
        if keepsDeleted {
            messages.append(MTPreviewMessage(id: 4, isOutgoing: true, text: MTStrings.AntiDelete.Preview.replyText, quote: deletedText, ageSeconds: 300))
        }
        return MTMiniChatContent(header: MTMiniChatContent.sampleHeader(), messages: messages)
    }
}
