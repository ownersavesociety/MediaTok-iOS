import Foundation
import UIKit
import SwiftSignalKit
import Postbox
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import ItemListPeerItem
import LocalizedPeerData
import MTCore
import MTSettingsUI
import MTFeaturesShared

/// «Безопасность»: «Защита чатов», «Код-пароль», «Аккаунты». «Двойное дно» registers nothing (not
/// ported,, so that tab is not shown. The category, and the export / import / reset
/// of the settings, ask the common check while any protection is on — switching a protection off is
/// what an intruder with an unlocked phone would do.
enum MTSecurityMenu {
    static let chatsSection = MTMenuSectionID("security.chatProtection.chats")
    static let folderSection = MTMenuSectionID("security.chatProtection.folder")
    static let folderListSection = MTMenuSectionID("security.chatProtection.folderList")
    static let moreSection = MTMenuSectionID("security.chatProtection.more")
    static let passcodeOptionsSection = MTMenuSectionID("security.passcode.options")
    static let accountSettingsSection = MTMenuSectionID("security.accounts.settings")

    static func register() {
        MTSecurityMenu.registerAccessGate()
        MTSecurityMenu.registerChatProtection()
        MTSecurityMenu.registerPasscode()
        MTSecurityMenu.registerAccounts()
    }

    // MARK: Access

    /// A protection is on: entering «Безопасность» or exporting / importing / resetting needs the check.
    static func isAnyProtectionOn(account: MTAccountID) -> Bool {
        if MTSecuritySharedSettings.chatLockEnabled.value || MTSecuritySettings.accountSwitchAuth.value || MTSecuritySettings.passcodeLockOnLaunch.value {
            return true
        }
        return MTSecuritySettings.secretFolderId.value(for: account) != 0
    }

    private static let guardedActions: Set<String> = ["menu.export", "menu.import", "menu.reset"]

    private static func registerAccessGate() {
        MTMenuAccessGates.gate.register({ request, proceed in
            let isSecurity = request.path.contains(.category(.security)) && !request.unlocked.contains(.category(.security))
            var isGuardedAction = false
            if case let .action(rowId) = request.target {
                isGuardedAction = MTSecurityMenu.guardedActions.contains(rowId)
            }
            guard isSecurity || isGuardedAction else {
                return false
            }
            if !MTSecurityMenu.isAnyProtectionOn(account: request.context.account.id.mt) {
                return false
            }
            MTLocalAuthGate.shared.authenticate(context: request.context, reason: MTStrings.Security.Auth.reasonSettings, completion: { granted in
                if granted {
                    proceed()
                }
            })
            return true
        }, order: 100)
    }

    // MARK: Защита чатов

    private static func registerChatProtection() {
        let tab = MTMenuTabID.securityChatProtection
        let main = MTMenuSectionID.main(of: tab)
        let enabled: (MTMenuContext) -> Bool = { _ in MTSecuritySharedSettings.chatLockEnabled.value }

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: MTSecurityMenu.chatsSection,
            screen: .tab(tab),
            order: 250,
            footer: { _ in MTStrings.Security.ChatLock.footer },
            isVisible: enabled
        ))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTSecurityMenu.folderSection, screen: .tab(tab), order: 300, header: { MTStrings.Security.Folder.header }, footer: { _ in MTStrings.Security.Folder.footer }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTSecurityMenu.folderListSection, screen: .tab(tab), order: 350, header: { MTStrings.Security.Folder.chooseHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTSecurityMenu.moreSection, screen: .tab(tab), order: 400, footer: { _ in MTStrings.Security.Screenshot.footer }))

        MTMenuRegistry.register(MTMenuRow(
            id: "security.chatLock.enabled",
            section: main,
            order: 100,
            title: { MTStrings.Security.ChatLock.toggle },
            subtitle: { MTStrings.Security.ChatLock.toggleInfo },
            kind: .toggle(.global(MTSecuritySharedSettings.chatLockEnabled)),
            searchKeywords: { [MTStrings.Security.ChatLock.keywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.chatLock.allChats",
            section: main,
            order: 200,
            title: { MTStrings.Security.ChatLock.allChats },
            subtitle: { MTStrings.Security.ChatLock.allChatsInfo },
            kind: .toggle(.global(MTSecuritySharedSettings.chatLockAllChats)),
            isVisible: enabled
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.chatLock.autolock",
            section: main,
            order: 300,
            title: { MTStrings.Security.ChatLock.autolock },
            subtitle: { MTStrings.Security.ChatLock.autolockInfo },
            kind: .toggle(.global(MTSecuritySettings.chatLockAutolock)),
            isVisible: enabled
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.chatLock.autolockTimeout",
            section: main,
            order: 400,
            title: { MTStrings.Security.ChatLock.timeout },
            kind: .choice(.global(MTSecuritySettings.chatLockAutolockTimeout), options: [
                MTMenuChoiceOption(value: "0", title: { MTStrings.Security.ChatLock.timeoutImmediately }),
                MTMenuChoiceOption(value: "15", title: { MTStrings.Security.ChatLock.timeoutSeconds(count: 15) }),
                MTMenuChoiceOption(value: "30", title: { MTStrings.Security.ChatLock.timeoutSeconds(count: 30) }),
                MTMenuChoiceOption(value: "60", title: { MTStrings.Security.ChatLock.timeoutMinutes(count: 1) }),
                MTMenuChoiceOption(value: "300", title: { MTStrings.Security.ChatLock.timeoutMinutes(count: 5) })
            ]),
            isVisible: { _ in MTSecuritySharedSettings.chatLockEnabled.value && MTSecuritySettings.chatLockAutolock.value }
        ))

        // The chosen chats of the account.
        MTMenuRegistry.register(MTMenuRow(
            id: "security.chatLock.choose",
            section: MTSecurityMenu.chatsSection,
            order: 100,
            title: { MTStrings.Security.ChatLock.choose },
            icon: .bundle("Chat/Context Menu/AddUser"),
            kind: .action({ context in
                MTSecurityMenu.presentChatPicker(context)
            }),
            isVisible: { _ in !MTSecuritySharedSettings.chatLockAllChats.value },
            label: { context in
                let count = MTSecuritySharedSettings.chatLockPeers.value(for: context.accountID).count
                return count > 0 ? "\(count)" : nil
            }
        ))
        MTMenuRegistry.register(dynamicRowsIn: MTSecurityMenu.chatsSection, { context in
            return MTSecurityMenu.chatRows(context)
        })

        // Secret folder.
        MTMenuRegistry.register(MTMenuRow(
            id: "security.secretFolder.open",
            section: MTSecurityMenu.folderSection,
            order: 100,
            title: { MTStrings.Security.Folder.open },
            icon: .bundle("Chat/Context Menu/Lock"),
            kind: .action({ context in
                MTSecretFolder.shared.open(context)
            }),
            isVisible: { context in MTSecuritySettings.secretFolderId.value(for: context.accountID) != 0 },
            searchKeywords: { [MTStrings.Security.Folder.keywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.secretFolder.protectChats",
            section: MTSecurityMenu.folderSection,
            order: 200,
            title: { MTStrings.Security.Folder.protectChats },
            subtitle: { MTStrings.Security.Folder.protectChatsInfo },
            kind: .toggle(.account(MTSecuritySettings.secretFolderProtectChats)),
            isVisible: { context in MTSecuritySettings.secretFolderId.value(for: context.accountID) != 0 }
        ))
        MTMenuRegistry.register(dynamicRowsIn: MTSecurityMenu.folderListSection, { context in
            return MTSecurityMenu.folderRows(context)
        })

        // Accounts and screenshots.
        MTMenuRegistry.register(MTMenuRow(
            id: "security.accountSwitchAuth",
            section: MTSecurityMenu.moreSection,
            order: 100,
            title: { MTStrings.Security.Accounts.switchAuth },
            subtitle: { MTStrings.Security.Accounts.switchAuthInfo },
            kind: .toggle(.global(MTSecuritySettings.accountSwitchAuth))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.screenshotPrivacy",
            section: MTSecurityMenu.moreSection,
            order: 200,
            title: { MTStrings.Security.Screenshot.toggle },
            subtitle: { MTStrings.Security.Screenshot.toggleInfo },
            kind: .toggle(.global(MTSecuritySettings.screenshotPrivacy)),
            searchKeywords: { [MTStrings.Security.Screenshot.keywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.screenshotPrivacyChatList",
            section: MTSecurityMenu.moreSection,
            order: 300,
            title: { MTStrings.Security.Screenshot.chatList },
            kind: .toggle(.global(MTSecuritySettings.screenshotPrivacyChatList)),
            isVisible: { _ in MTSecuritySettings.screenshotPrivacy.value }
        ))
    }

    /// «Выбрать чаты»: Telegram's chat picker over the chats protected so far.
    private static func presentChatPicker(_ menuContext: MTMenuContext) {
        let context = menuContext.context
        let account = context.account.id.mt
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var selected = Set<EnginePeer.Id>()
        for key in MTSecuritySharedSettings.chatLockPeers.value(for: account) {
            selected.insert(PeerId(mtKey: key))
        }
        let controller = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
            title: MTStrings.Security.ChatLock.choose,
            searchPlaceholder: presentationData.strings.Common_Search,
            selectedChats: selected,
            additionalCategories: nil,
            chatListFilters: nil
        )), alwaysEnabled: true))
        let _ = (controller.result
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak controller] result in
            guard case let .result(peerIds, _) = result else {
                controller?.dismiss()
                return
            }
            var keys = Set<MTPeerKey>()
            for peerId in peerIds {
                if case let .peer(value) = peerId {
                    keys.insert(value.mtKey)
                }
            }
            MTSecuritySharedSettings.chatLockPeers.set(keys, for: account)
            controller?.dismiss()
        })
        menuContext.present(controller, arguments: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }

    /// The protected chats of the account, sorted by name; swipe to remove.
    private static func chatRows(_ providerContext: MTMenuContext) -> Signal<[MTMenuRow], NoError> {
        let context = providerContext.context
        let account = context.account.id.mt
        let revealed = ValuePromise<EnginePeer.Id?>(nil, ignoreRepeated: true)
        let peers: Signal<[EnginePeer], NoError> = MTSecuritySharedSettings.chatLockPeers.signal(for: account)
        |> map { keys -> [EnginePeer.Id] in
            return keys.map { PeerId(mtKey: $0) }
        }
        |> mapToSignal { peerIds -> Signal<[EnginePeer], NoError> in
            return context.engine.data.subscribe(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
            |> map { map -> [EnginePeer] in
                return map.values.compactMap { $0 }
            }
        }
        return combineLatest(peers, revealed.get(), context.sharedContext.presentationData, MTSecuritySharedSettings.chatLockAllChats.signal)
        |> map { peers, revealedPeerId, presentationData, allChats -> [MTMenuRow] in
            if allChats {
                return []
            }
            let sorted = peers.sorted(by: { lhs, rhs in
                let lhsTitle = lhs.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                let rhsTitle = rhs.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            })
            var rows: [MTMenuRow] = []
            for (index, peer) in sorted.enumerated() {
                let peerId = peer.id
                let isRevealed = revealedPeerId == peerId
                rows.append(MTMenuRow(id: "security.chatLock.peer.\(peerId.mtKey.stringValue)", section: MTSecurityMenu.chatsSection, order: 1000 + index, title: { "" }, kind: .custom({ rowContext in
                    let presentationData = rowContext.presentationData
                    let remove: (EnginePeer.Id) -> Void = { peerId in
                        var keys = MTSecuritySharedSettings.chatLockPeers.value(for: account)
                        keys.remove(peerId.mtKey)
                        MTSecuritySharedSettings.chatLockPeers.set(keys, for: account)
                    }
                    return ItemListPeerItem(presentationData: rowContext.itemListPresentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: rowContext.context, peer: peer, presence: nil, text: .none, label: .none, editing: ItemListPeerItemEditing(editable: true, editing: false, revealed: isRevealed), revealOptions: ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: MTStrings.Security.ChatLock.remove, action: {
                        remove(peerId)
                    })]), switchValue: nil, enabled: true, selectable: false, sectionId: rowContext.sectionId, action: nil, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
                        if peerId != nil || fromPeerId != nil {
                            revealed.set(peerId)
                        }
                    }, removePeer: { peerId in
                        remove(peerId)
                    })
                })))
            }
            return rows
        }
    }

    /// The account's folders as a single choice («Нет» first).
    private static func folderRows(_ providerContext: MTMenuContext) -> Signal<[MTMenuRow], NoError> {
        let context = providerContext.context
        let account = context.account.id.mt
        return combineLatest(MTSecretFolder.folderChoices(context: context), MTSecuritySettings.secretFolderId.signal(for: account))
        |> map { folders, selectedId -> [MTMenuRow] in
            var choices: [(Int32, String?)] = [(0, nil)]
            for (id, title) in folders {
                choices.append((id, title))
            }
            var rows: [MTMenuRow] = []
            for (index, choice) in choices.enumerated() {
                let id = choice.0
                let title = choice.1
                let checked = id == selectedId
                rows.append(MTMenuRow(id: "security.secretFolder.choice.\(id)", section: MTSecurityMenu.folderListSection, order: 1000 + index, title: { title ?? MTStrings.Security.Folder.none }, kind: .custom({ rowContext in
                    return ItemListCheckboxItem(presentationData: rowContext.itemListPresentationData, systemStyle: .glass, title: title ?? MTStrings.Security.Folder.none, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: rowContext.sectionId, action: {
                        if MTSecuritySettings.secretFolderId.value(for: account) != id {
                            MTSecuritySettings.secretFolderId.set(id, for: account)
                            // A newly chosen folder starts locked.
                            MTSecretFolder.shared.lockAll()
                        }
                    })
                })))
            }
            if folders.isEmpty {
                rows.append(MTMenuRow(id: "security.secretFolder.empty", section: MTSecurityMenu.folderListSection, order: 5000, title: { "" }, kind: .custom({ rowContext in
                    return ItemListTextItem(presentationData: rowContext.itemListPresentationData, text: .plain(MTStrings.Security.Folder.noFolders), sectionId: rowContext.sectionId)
                })))
            }
            return rows
        }
    }

    // MARK: Код-пароль

    private static func registerPasscode() {
        let tab = MTMenuTabID.securityPasscode
        let main = MTMenuSectionID.main(of: tab)
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTSecurityMenu.passcodeOptionsSection, screen: .tab(tab), order: 300, footer: { _ in MTStrings.Security.Passcode.footer }))

        MTMenuRegistry.register(MTMenuRow(
            id: "security.passcode.open",
            section: main,
            order: 100,
            title: { MTStrings.Security.Passcode.open },
            icon: .bundle("Chat/Context Menu/Lock"),
            kind: .action({ context in
                MTPasscodeExtras.openTelegramPasscode(context)
            }),
            searchKeywords: { [MTStrings.Security.Passcode.keywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.passcode.lockNow",
            section: main,
            order: 200,
            title: { MTStrings.Security.Passcode.lockNow },
            subtitle: { MTStrings.Security.Passcode.lockNowInfo },
            kind: .action({ context in
                MTPasscodeExtras.lockNow(context)
            })
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.passcode.lockOnLaunch",
            section: MTSecurityMenu.passcodeOptionsSection,
            order: 100,
            title: { MTStrings.Security.Passcode.lockOnLaunch },
            subtitle: { MTStrings.Security.Passcode.lockOnLaunchInfo },
            kind: .toggle(.global(MTSecuritySettings.passcodeLockOnLaunch))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.passcode.moreAutolockOptions",
            section: MTSecurityMenu.passcodeOptionsSection,
            order: 200,
            title: { MTStrings.Security.Passcode.moreAutolock },
            subtitle: { MTStrings.Security.Passcode.moreAutolockInfo },
            kind: .toggle(.global(MTSecuritySettings.passcodeMoreAutolockOptions))
        ))
    }

    // MARK: Аккаунты

    private static func registerAccounts() {
        let tab = MTMenuTabID.securityAccounts
        let main = MTMenuSectionID.main(of: tab)
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTSecurityMenu.accountSettingsSection, screen: .tab(tab), order: 300, header: { MTStrings.Security.AccountSettings.header }, footer: { _ in MTStrings.Security.AccountSettings.footer }))

        MTMenuRegistry.register(MTMenuRow(
            id: "security.accounts.headerButton",
            section: main,
            order: 100,
            title: { MTStrings.Security.Accounts.headerButton },
            subtitle: { MTStrings.Security.Accounts.headerButtonInfo },
            kind: .toggle(.global(MTSecuritySettings.accountsHeaderButton))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "security.accounts.copySettings",
            section: MTSecurityMenu.accountSettingsSection,
            order: 100,
            title: { MTStrings.Security.AccountSettings.copy },
            icon: .bundle("Chat/Context Menu/Copy"),
            kind: .action({ context in
                MTAccountSettingsCopy.present(context)
            }),
            searchKeywords: { [MTStrings.Security.AccountSettings.keywords] }
        ))
    }
}
