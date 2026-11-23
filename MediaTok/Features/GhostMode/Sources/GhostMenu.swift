import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import AlertUI
import MTCore
import MTSettingsUI
import MTFeaturesShared

extension MTMenuTabID {
    static let ghostActivities = MTMenuTabID("ghostMode.activities")
}

extension MTMenuSectionID {
    static let ghostActivitiesMain = MTMenuSectionID("ghostMode.activities.main")
    static let ghostExceptionTypes = MTMenuSectionID("ghostMode.exceptions.types")
}

/// Rows of the «Приватность» category: preview, the ghost-mode group and its rows, the
/// exceptions and send-delay tabs, «Следы»; plus «Скрыть сообщения заблокированных» in the
/// «Сообщения › Чаты» section where MediaTok spec puts it.
enum MTGhostMenu {
    static func register() {
        MTGhostPreview.register()
        MTGhostMenu.registerGhostSection()
        MTGhostMenu.registerActivitiesTab()
        MTGhostMenu.registerExceptionsTab()
        MTGhostMenu.registerSendDelayTab()
        MTGhostMenu.registerTraces()
        MTGhostMenu.registerChatsSection()
    }

    // MARK: Ghost mode

    private static func registerGhostSection() {
        let section = MTMenuSectionID.privacyGhostMode

        MTMenuRegistry.register(MTMenuRow(
            id: "ghostMode.group",
            section: section,
            order: 100,
            title: { MTStrings.GhostMode.Menu.group },
            subtitle: { MTStrings.GhostMode.Menu.groupInfo },
            kind: .expandableGroup(master: .account(MTGhostSettings.isEnabled), children: [
                MTMenuRow(id: "ghostMode.hideReadReceipts", section: section, order: 100, title: { MTStrings.GhostMode.Menu.hideReadReceipts }, subtitle: { MTStrings.GhostMode.Menu.hideReadReceiptsInfo }, kind: .toggle(.account(MTGhostSettings.hideReadReceipts)), searchKeywords: { [MTStrings.GhostMode.Menu.keywordRead] }),
                MTMenuRow(id: "ghostMode.hideStoryViews", section: section, order: 200, title: { MTStrings.GhostMode.Menu.hideStoryViews }, subtitle: { MTStrings.GhostMode.Menu.hideStoryViewsInfo }, kind: .toggle(.account(MTGhostSettings.hideStoryViews)), searchKeywords: { [MTStrings.GhostMode.Menu.keywordStories] }),
                MTMenuRow(id: "ghostMode.hideOnline", section: section, order: 300, title: { MTStrings.GhostMode.Menu.hideOnline }, subtitle: { MTStrings.GhostMode.Menu.hideOnlineInfo }, kind: .toggle(.account(MTGhostSettings.hideOnline)), searchKeywords: { [MTStrings.GhostMode.Menu.keywordOnline] }),
                MTMenuRow(id: "ghostMode.hideTyping", section: section, order: 400, title: { MTStrings.GhostMode.Menu.hideTyping }, subtitle: { MTStrings.GhostMode.Menu.hideTypingInfo }, kind: .toggle(.account(MTGhostSettings.hideTyping)), searchKeywords: { [MTStrings.GhostMode.Menu.keywordTyping] })
            ]),
            searchKeywords: { [MTStrings.GhostMode.Menu.keywordGhost] }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "ghostMode.readOnAction",
            section: section,
            order: 300,
            title: { MTStrings.GhostMode.Menu.readOnAction },
            subtitle: { MTStrings.GhostMode.Menu.readOnActionInfo },
            kind: .toggle(.account(MTGhostSettings.readOnAction)),
            isEnabled: { context in
                return MTGhostSettings.isEnabled.value(for: context.accountID)
            }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "ghostMode.alwaysOnline",
            section: section,
            order: 400,
            title: { MTStrings.GhostMode.Menu.alwaysOnline },
            subtitle: { MTStrings.GhostMode.Menu.alwaysOnlineInfo },
            kind: .toggle(.account(MTGhostSettings.alwaysOnline)),
            searchKeywords: { [MTStrings.GhostMode.Menu.keywordOnline] },
            // Grey while ghost mode hides "online": the switch must not look active when it is not.
            isEnabled: { context in
                return !MTGhostPolicy.isFunctionOn(.online, account: context.accountID)
            }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "ghostMode.readLocally",
            section: section,
            order: 700,
            title: { MTStrings.GhostMode.Menu.readLocally },
            subtitle: { MTStrings.GhostMode.Menu.readLocallyInfo },
            icon: .bundle("Chat/Context Menu/ReadAll"),
            kind: .action({ context in
                MTGhostMenu.confirm(context, title: MTStrings.GhostMode.Menu.readLocallyConfirmTitle, text: MTStrings.GhostMode.Menu.readLocallyConfirmText, action: MTStrings.GhostMode.Menu.readLocally, perform: {
                    let accountContext = context.context
                    let _ = (MTGhostReadAll.readLocally(context: accountContext)
                    |> deliverOnMainQueue).start(next: { count in
                        context.presentToast(MTStrings.GhostMode.Menu.readLocallyDone(count: count))
                    })
                })
            }),
            searchKeywords: { [MTStrings.GhostMode.Menu.keywordRead] },
            label: { context in
                let count = MTGhostReadLedger.shared.localReadCount(account: context.accountID)
                return count > 0 ? "\(count)" : nil
            }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "ghostMode.readOnServer",
            section: section,
            order: 800,
            title: { MTStrings.GhostMode.Menu.readOnServer },
            subtitle: { MTStrings.GhostMode.Menu.readOnServerInfo },
            icon: .bundle("Chat/Context Menu/MarkAsRead"),
            kind: .action({ context in
                MTGhostMenu.confirm(context, title: MTStrings.GhostMode.Menu.readOnServerConfirmTitle, text: MTStrings.GhostMode.Menu.readOnServerConfirmText, action: MTStrings.GhostMode.Menu.readOnServer, perform: {
                    let accountContext = context.context
                    let _ = (MTGhostReadAll.readOnServer(context: accountContext)
                    |> deliverOnMainQueue).start(next: { count in
                        context.presentToast(MTStrings.GhostMode.Menu.readOnServerDone(count: count))
                    })
                })
            }),
            searchKeywords: { [MTStrings.GhostMode.Menu.keywordRead] },
            label: { context in
                let pending = MTGhostReadLedger.shared.pendingKeys(account: context.accountID)
                let count = pending.kept.count + pending.local.count
                return count > 0 ? "\(count)" : nil
            }
        ))
    }

    static func confirm(_ context: MTMenuContext, title: String, text: String, action: String, perform: @escaping () -> Void) {
        let presentationData = context.presentationData
        let alert = textAlertController(context: context.context, title: title, text: text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: action, action: perform)
        ])
        context.present(alert)
    }

    // MARK: Activity statuses

    static func activityTitle(_ kind: MTGhostActivityKind) -> String {
        switch kind {
        case .typingText:
            return MTStrings.GhostMode.Activity.typingText
        case .recordingVoice:
            return MTStrings.GhostMode.Activity.recordingVoice
        case .recordingInstantVideo:
            return MTStrings.GhostMode.Activity.recordingInstantVideo
        case .uploadingInstantVideo:
            return MTStrings.GhostMode.Activity.uploadingInstantVideo
        case .uploadingVideo:
            return MTStrings.GhostMode.Activity.uploadingVideo
        case .uploadingPhoto:
            return MTStrings.GhostMode.Activity.uploadingPhoto
        case .uploadingFile:
            return MTStrings.GhostMode.Activity.uploadingFile
        case .choosingSticker:
            return MTStrings.GhostMode.Activity.choosingSticker
        case .playingGame:
            return MTStrings.GhostMode.Activity.playingGame
        case .speakingInGroupCall:
            return MTStrings.GhostMode.Activity.speakingInGroupCall
        case .interactingWithEmoji:
            return MTStrings.GhostMode.Activity.interactingWithEmoji
        case .seeingEmojiInteraction:
            return MTStrings.GhostMode.Activity.seeingEmojiInteraction
        }
    }

    private static func registerActivitiesTab() {
        // Shown only while «Не отправлять «печатает»» is on: an empty tab has no link (no dead screen).
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: .ghostActivities,
                parent: .category(.privacy),
                title: { MTStrings.GhostMode.Menu.activities },
                topView: MTMenuTopView(content: .emoji("✍️"), text: { MTStrings.GhostMode.Menu.activitiesInfo }),
                searchKeywords: { [MTStrings.GhostMode.Menu.keywordTyping] }
            ),
            linkIn: .privacyGhostMode,
            order: 200,
            subtitle: { MTStrings.GhostMode.Menu.activitiesInfo },
            icon: .bundle("Chat/Context Menu/Edit"),
            label: { context in
                let account = context.accountID
                var shown = 0
                for kind in MTGhostActivityKind.allCases where MTGhostSettings.shownActivity(kind).value(for: account) {
                    shown += 1
                }
                return MTStrings.GhostMode.Menu.activitiesShown(shown: "\(shown)", total: "\(MTGhostActivityKind.allCases.count)")
            }
        )
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: .ghostActivitiesMain,
            screen: .tab(.ghostActivities),
            order: 200,
            header: { MTStrings.GhostMode.Menu.activitiesHeader },
            footer: { _ in MTStrings.GhostMode.Menu.activitiesFooter },
            isVisible: { context in
                return MTGhostSettings.hideTyping.value(for: context.accountID)
            }
        ))
        var order = 100
        for kind in MTGhostActivityKind.allCases {
            MTMenuRegistry.register(MTMenuRow(
                id: "ghostMode.activityShown.\(kind.rawValue)",
                section: .ghostActivitiesMain,
                order: order,
                title: { MTGhostMenu.activityTitle(kind) },
                kind: .toggle(.account(MTGhostSettings.shownActivity(kind)))
            ))
            order += 100
        }
    }

    // MARK: Exceptions

    /// MediaTok spec: «Чаты / Папки / Типы» as a segment in the navbar of the skeleton's tab. Chats and
    /// folders are runtime rows of their sections (MTGhostExceptionRows); the types are settings.
    private static func registerExceptionsTab() {
        let tab = MTMenuTabID.privacyGhostExceptions
        MTMenuRegistry.register(segments: [
            MTMenuSegment(id: "chats", title: { MTStrings.GhostMode.Exceptions.chats }),
            MTMenuSegment(id: "folders", title: { MTStrings.GhostMode.Exceptions.folders }),
            MTMenuSegment(id: "types", title: { MTStrings.GhostMode.Exceptions.typesSegment })
        ], for: tab)

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: MTGhostExceptionRows.chatsSection,
            screen: .tab(tab),
            order: 300,
            segment: "chats",
            footer: { _ in MTStrings.GhostMode.Exceptions.chatsInfo }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "ghostMode.exceptions.add",
            section: MTGhostExceptionRows.chatsSection,
            order: 100,
            title: { MTStrings.GhostMode.Exceptions.add },
            icon: .bundle("Chat/Context Menu/AddUser"),
            kind: .action({ context in
                MTGhostExceptionRows.presentPicker(context)
            }),
            searchKeywords: { [MTStrings.GhostMode.Exceptions.chatsInfo] },
            label: { context in
                let count = MTGhostSettings.exceptions.value(for: context.accountID).count
                return count > 0 ? "\(count)" : nil
            }
        ))
        MTMenuRegistry.register(dynamicRowsIn: MTGhostExceptionRows.chatsSection, { context in
            return MTGhostExceptionRows.chatRows(context)
        })

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: MTGhostExceptionRows.foldersSection,
            screen: .tab(tab),
            order: 400,
            segment: "folders",
            header: { MTStrings.GhostMode.Exceptions.foldersInfo },
            footer: { _ in MTStrings.GhostMode.Exceptions.foldersFooter }
        ))
        MTMenuRegistry.register(dynamicRowsIn: MTGhostExceptionRows.foldersSection, { context in
            return MTGhostExceptionRows.folderRows(context)
        })

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: .ghostExceptionTypes,
            screen: .tab(tab),
            order: 500,
            segment: "types",
            header: { MTStrings.GhostMode.Exceptions.typesHeader },
            footer: { _ in MTStrings.GhostMode.Exceptions.typesFooter }
        ))
        MTMenuRegistry.register(MTMenuRow(id: "ghostMode.exceptAllChannels", section: .ghostExceptionTypes, order: 100, title: { MTStrings.GhostMode.Exceptions.allChannels }, kind: .toggle(.account(MTGhostSettings.exceptAllChannels))))
        MTMenuRegistry.register(MTMenuRow(id: "ghostMode.exceptAllGroups", section: .ghostExceptionTypes, order: 200, title: { MTStrings.GhostMode.Exceptions.allGroups }, kind: .toggle(.account(MTGhostSettings.exceptAllGroups))))
    }

    // MARK: Send delay

    private static func registerSendDelayTab() {
        let main = MTMenuSectionID.main(of: .privacySendDelay)
        MTMenuRegistry.register(MTMenuRow(
            id: "sendDelay.isEnabled",
            section: main,
            order: 100,
            title: { MTStrings.GhostMode.SendDelay.toggle },
            subtitle: { MTStrings.GhostMode.SendDelay.toggleInfo },
            kind: .toggle(.account(MTGhostSettings.sendDelayEnabled))
        ))
        // One delay for text and media since 2026-10-27 (were two sliders).
        MTMenuRegistry.register(MTMenuRow(
            id: "sendDelay.seconds",
            section: main,
            order: 200,
            title: { MTStrings.GhostMode.SendDelay.delay },
            kind: .slider(.account(MTGhostSettings.sendDelaySeconds), range: MTSendDelaySeconds.range, step: 1.0, format: { value in
                return MTStrings.GhostMode.SendDelay.seconds(count: Int(value))
            }),
            isVisible: { context in
                return MTGhostSettings.sendDelayEnabled.value(for: context.accountID)
            }
        ))
    }

    // MARK: Traces

    private static func registerTraces() {
        MTMenuRegistry.register(MTMenuRow(id: "ghostMode.confirmCalls", section: .privacyTraces, order: 100, title: { MTStrings.GhostMode.Traces.confirmCalls }, subtitle: { MTStrings.GhostMode.Traces.confirmCallsInfo }, kind: .toggle(.global(MTGhostSettings.confirmCalls))))
        MTMenuRegistry.register(MTMenuRow(id: "ghostMode.warnBeforeStories", section: .privacyTraces, order: 200, title: { MTStrings.GhostMode.Traces.warnBeforeStories }, subtitle: { MTStrings.GhostMode.Traces.warnBeforeStoriesInfo }, kind: .toggle(.global(MTGhostSettings.warnBeforeStories))))
        MTMenuRegistry.register(MTMenuRow(id: "ghostMode.hidePhoneInSettings", section: .privacyTraces, order: 300, title: { MTStrings.GhostMode.Traces.hidePhone }, subtitle: { MTStrings.GhostMode.Traces.hidePhoneInfo }, kind: .toggle(.global(MTGhostSettings.hidePhoneInSettings))))
    }

    // MARK: Messages › Chats

    private static func registerChatsSection() {
        MTMenuRegistry.register(MTMenuRow(
            id: "ghostMode.hideBlockedMessages",
            section: .messagesChats,
            order: 450,
            title: { MTStrings.GhostMode.Blocked.toggle },
            subtitle: { MTStrings.GhostMode.Blocked.toggleInfo },
            kind: .toggle(.account(MTGhostSettings.hideBlockedMessages))
        ))
    }
}
