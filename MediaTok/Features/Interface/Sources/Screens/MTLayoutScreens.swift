import Foundation
import PresentationDataUtils
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import TelegramUIPreferences
import MTCore

// MARK: - Tab bar organizer (tabbar_tweaks)

enum MTTabBarScreens {
    /// Telegram's own title of a tab.
    static func defaultTitle(_ id: String, strings: PresentationStrings) -> String {
        switch id {
        case MTTabBarLayout.contacts:
            return strings.Contacts_Title
        case MTTabBarLayout.calls:
            return strings.Calls_TabTitle
        case MTTabBarLayout.chats:
            return strings.DialogList_Title
        default:
            return strings.Settings_Title
        }
    }

    static func title(_ id: String, strings: PresentationStrings) -> String {
        if let custom = InterfaceSettings.tabTitles.value[id], !custom.isEmpty {
            return custom
        }
        return MTTabBarScreens.defaultTitle(id, strings: strings)
    }

    /// Telegram's own «Calls» tab switch (Recent Calls › Show Calls Tab). The organizer hides
    /// Calls through it, so there is one setting for it, not two.
    static func showsCallsTab(context: AccountContext) -> Signal<Bool, NoError> {
        return context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings])
        |> map { sharedData -> Bool in
            return sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self)?.showTab ?? CallListSettings.defaultSettings.showTab
        }
        |> distinctUntilChanged
    }

    /// One place for the order, the names and the hidden tabs. Applies at once (the tab bar is
    /// re-arranged from the settings snapshot), no restart.
    static func makeOrganizer(context: AccountContext) -> ViewController {
        weak var controllerRef: ViewController?
        let box = MTTabOrganizerBox()
        let update = MTTabBarScreens.showsCallsTab(context: context)
        |> deliverOnMainQueue
        |> map { value -> Void in
            box.showsCallsTab = value
            return Void()
        }
        let actions = MTListActions(select: { id in
            if id == "reset" {
                mtConfirmDestructive(context: context, from: controllerRef, title: MTStrings.Interface.Common.resetTitle, text: MTStrings.Interface.TabBar.resetText, confirm: MTStrings.Interface.Common.reset, action: {
                    InterfaceSettings.tabOrder.reset()
                    InterfaceSettings.tabTitles.reset()
                    InterfaceSettings.hiddenTabs.reset()
                    MTTabBarScreens.setShowsCallsTab(true, context: context)
                })
                return
            }
            MTTabBarScreens.presentTabActions(id: id, context: context, controller: controllerRef, showsCallsTab: box.showsCallsTab)
        }, reorder: { ids in
            InterfaceSettings.tabOrder.set(MTTabBarLayout.normalizedOrder(ids))
        })
        let controller = mtMakeInterfaceList(context: context, title: { MTStrings.Interface.TabBar.organizerTitle }, update: update, sections: { presentationData in
            let order = MTTabBarLayout.normalizedOrder(InterfaceSettings.tabOrder.value)
            var rows: [MTListRow] = [.header(MTStrings.Interface.TabBar.tabsHeader)]
            for id in order {
                let label = MTTabBarScreens.isHidden(id, showsCallsTab: box.showsCallsTab) ? MTStrings.Interface.Common.hiddenLabel : ""
                rows.append(.reorderable(id: id, title: MTTabBarScreens.title(id, strings: presentationData.strings), label: label))
            }
            rows.append(.footer(MTStrings.Interface.TabBar.tabsFooter))
            var sections = [MTListSection(rows)]
            if !InterfaceSettings.tabOrder.isDefault || !InterfaceSettings.tabTitles.isDefault || !InterfaceSettings.hiddenTabs.isDefault || !box.showsCallsTab {
                sections.append(MTListSection([.action(id: "reset", title: MTStrings.Interface.Common.reset, isDestructive: true)]))
            }
            return sections
        }, actions: actions)
        controllerRef = controller
        return controller
    }

    private static func isHidden(_ id: String, showsCallsTab: Bool) -> Bool {
        if id == MTTabBarLayout.calls && !showsCallsTab {
            return true
        }
        return InterfaceSettings.hiddenTabs.value.contains(id)
    }

    private static func setShowsCallsTab(_ value: Bool, context: AccountContext) {
        let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            return settings.withUpdatedShowTab(value)
        }).start()
    }

    private static func presentTabActions(id: String, context: AccountContext, controller: ViewController?, showsCallsTab: Bool) {
        let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
        guard MTTabBarLayout.normalizedOrder(InterfaceSettings.tabOrder.value).contains(id) else {
            return
        }
        var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
        buttons.append((MTStrings.Interface.Common.rename, false, {
            mtPresentTextPrompt(from: controller, title: MTStrings.Interface.TabBar.renameTitle, text: InterfaceSettings.tabTitles.value[id] ?? "", placeholder: MTTabBarScreens.defaultTitle(id, strings: strings), cancel: strings.Common_Cancel, done: strings.Common_Done, completion: { text in
                let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
                var titles = InterfaceSettings.tabTitles.value
                titles[id] = trimmed.isEmpty ? nil : trimmed
                InterfaceSettings.tabTitles.set(titles)
            })
        }))
        if InterfaceSettings.tabTitles.value[id] != nil {
            buttons.append((MTStrings.Interface.Common.restoreName, false, {
                var titles = InterfaceSettings.tabTitles.value
                titles.removeValue(forKey: id)
                InterfaceSettings.tabTitles.set(titles)
            }))
        }
        if MTTabBarLayout.hideableIds.contains(id) {
            let hidden = InterfaceSettings.hiddenTabs.value
            if MTTabBarScreens.isHidden(id, showsCallsTab: showsCallsTab) {
                buttons.append((MTStrings.Interface.Common.show, false, {
                    InterfaceSettings.hiddenTabs.set(hidden.filter { $0 != id })
                    if id == MTTabBarLayout.calls {
                        MTTabBarScreens.setShowsCallsTab(true, context: context)
                    }
                }))
            } else {
                buttons.append((MTStrings.Interface.Common.hide, true, {
                    if id == MTTabBarLayout.calls {
                        MTTabBarScreens.setShowsCallsTab(false, context: context)
                    } else {
                        InterfaceSettings.hiddenTabs.set(hidden + [id])
                    }
                }))
            }
        }
        mtPresentActionSheet(context: context, from: controller, title: MTTabBarScreens.title(id, strings: strings), buttons: buttons)
    }
}

private final class MTTabOrganizerBox {
    var showsCallsTab = true
}

// MARK: - Settings tab rows (settings_structure: hide and order)

enum MTSettingsTabScreens {
    private static let sectionOrder = ["edit", "myProfile", "wallet", "proxy", "apps", "shortcuts", "advanced", "payment", "extra", "support"]

    /// A section's items in display order: the user's order first, then Telegram's.
    static func items(section: String) -> [MTSettingsTabItem] {
        let ordered = MTSettingsTabLayout.orderedItems(section: section, order: InterfaceSettings.settingsItemsOrder.value)
        var result = ordered
        for item in MTSettingsTabItem.allCases where item.section == section && !result.contains(item) {
            result.append(item)
        }
        return result
    }

    static func makeScreen(context: AccountContext) -> ViewController {
        weak var controllerRef: ViewController?
        let actions = MTListActions(select: { id in
            if id == "reset" {
                mtConfirmDestructive(context: context, from: controllerRef, title: MTStrings.Interface.Common.resetTitle, text: MTStrings.Interface.SettingsTab.resetText, confirm: MTStrings.Interface.Common.reset, action: {
                    InterfaceSettings.hiddenSettingsItems.reset()
                    InterfaceSettings.settingsItemsOrder.reset()
                })
                return
            }
            guard let item = MTSettingsTabItem(rawValue: id) else {
                return
            }
            MTSettingsTabScreens.presentItemActions(item, context: context, controller: controllerRef)
        }, reorder: { ids in
            let items = ids.compactMap(MTSettingsTabItem.init(rawValue:))
            if let section = items.first?.section {
                MTSettingsTabScreens.storeOrder(section: section, items: items)
            }
        })
        let controller = mtMakeInterfaceList(context: context, title: { MTStrings.Interface.SettingsTab.itemsTitle }, sections: { presentationData in
            let hidden = Set(InterfaceSettings.hiddenSettingsItems.value)
            var sections: [MTListSection] = []
            for section in MTSettingsTabScreens.sectionOrder {
                let items = MTSettingsTabScreens.items(section: section)
                if items.isEmpty {
                    continue
                }
                // A row is dragged only among the movable rows of its own block, so a block with one
                // of them has no grip.
                let movable = items.filter { $0.itemId != nil }.count > 1
                var rows: [MTListRow] = []
                for item in items {
                    let title = item.title(strings: presentationData.strings)
                    let label = hidden.contains(item.rawValue) ? MTStrings.Interface.Common.hiddenLabel : ""
                    if movable && item.itemId != nil {
                        rows.append(.reorderable(id: item.rawValue, title: title, label: label))
                    } else {
                        rows.append(.disclosure(id: item.rawValue, title: title, label: label, icon: nil))
                    }
                }
                sections.append(MTListSection(rows))
            }
            if var first = sections.first {
                first.rows.insert(.header(MTStrings.Interface.SettingsTab.itemsHeader), at: 0)
                sections[0] = first
            }
            sections.append(MTListSection([.footer(MTStrings.Interface.SettingsTab.itemsFooter)]))
            if !InterfaceSettings.hiddenSettingsItems.isDefault || !InterfaceSettings.settingsItemsOrder.isDefault {
                sections.append(MTListSection([.action(id: "reset", title: MTStrings.Interface.Common.reset, isDestructive: true)]))
            }
            return sections
        }, actions: actions)
        controllerRef = controller
        return controller
    }

    private static func presentItemActions(_ item: MTSettingsTabItem, context: AccountContext, controller: ViewController?) {
        let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
        var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
        var hidden = InterfaceSettings.hiddenSettingsItems.value
        if let hiddenIndex = hidden.firstIndex(of: item.rawValue) {
            buttons.append((MTStrings.Interface.Common.show, false, {
                hidden.remove(at: hiddenIndex)
                InterfaceSettings.hiddenSettingsItems.set(hidden)
            }))
        } else {
            buttons.append((MTStrings.Interface.Common.hide, true, {
                hidden.append(item.rawValue)
                InterfaceSettings.hiddenSettingsItems.set(hidden)
            }))
        }
        mtPresentActionSheet(context: context, from: controller, title: item.title(strings: strings), buttons: buttons)
    }

    /// Replaces one section's part of the stored order.
    private static func storeOrder(section: String, items: [MTSettingsTabItem]) {
        var order = MTSettingsTabLayout.normalizedOrder(InterfaceSettings.settingsItemsOrder.value).filter { MTSettingsTabItem(rawValue: $0)?.section != section }
        order.append(contentsOf: items.map { $0.rawValue })
        InterfaceSettings.settingsItemsOrder.set(order)
    }
}

// MARK: - Shortcuts (settings_structure: «Добавить в настройки»)

enum MTShortcutScreens {
    static let maxCount = 12

    static func makeScreen(context: AccountContext) -> ViewController {
        let account = context.account.id.mt
        let peers = Promise<[EnginePeer.Id: EnginePeer]>([:])
        let peerIds: Signal<[EnginePeer.Id], NoError> = InterfaceSettings.settingsShortcuts.signal(for: account)
        |> map { shortcuts -> [EnginePeer.Id] in
            return shortcuts.compactMap { $0.peer.flatMap { EnginePeer.Id(mtKey: $0) } }
        }
        |> distinctUntilChanged
        peers.set(peerIds
        |> mapToSignal { ids -> Signal<[EnginePeer.Id: EnginePeer], NoError> in
            if ids.isEmpty {
                return .single([:])
            }
            return context.engine.data.subscribe(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
            |> map { result -> [EnginePeer.Id: EnginePeer] in
                var mapped: [EnginePeer.Id: EnginePeer] = [:]
                for (id, peer) in result {
                    if let peer {
                        mapped[id] = peer
                    }
                }
                return mapped
            }
        })
        let favicons = Promise<[String: UIImage]>([:])
        favicons.set(InterfaceSettings.settingsShortcuts.signal(for: account)
        |> map { shortcuts -> [String] in
            return shortcuts.compactMap { $0.kind == .site ? $0.url : nil }
        }
        |> distinctUntilChanged
        |> mapToSignal { urls -> Signal<[String: UIImage], NoError> in
            if urls.isEmpty {
                return .single([:])
            }
            return combineLatest(urls.map { url in
                return MTFaviconStore.shared.icon(url: url, size: 29.0) |> map { (url, $0) }
            })
            |> map { pairs -> [String: UIImage] in
                var result: [String: UIImage] = [:]
                for (url, image) in pairs {
                    if let image {
                        result[url] = image
                    }
                }
                return result
            }
        })

        // Resolved peers and favicons are copied into the box on the main queue right before the
        // list is rebuilt from them.
        let box = MTShortcutScreenBox()
        let state = combineLatest(peers.get(), favicons.get())
        |> deliverOnMainQueue
        |> map { peers, icons -> Void in
            box.peers = peers
            box.favicons = icons
            return Void()
        }
        weak var controllerRef: ViewController?

        let actions = MTListActions(select: { id in
            switch id {
            case "add.chat":
                MTShortcutScreens.promptPeer(context: context, controller: controllerRef, kind: .chat)
            case "add.miniApp":
                MTShortcutScreens.promptPeer(context: context, controller: controllerRef, kind: .miniApp)
            case "add.site":
                MTShortcutScreens.promptSite(context: context, controller: controllerRef)
            default:
                MTShortcutScreens.presentShortcutActions(id: id, context: context, controller: controllerRef)
            }
        })
        let controller = mtMakeInterfaceList(context: context, title: { MTStrings.Interface.Shortcuts.title }, update: state, sections: { presentationData in
            let shortcuts = InterfaceSettings.settingsShortcuts.value(for: account)
            var listRows: [MTListRow] = [.header(MTStrings.Interface.Shortcuts.listHeader)]
            for shortcut in shortcuts {
                switch shortcut.kind {
                case .chat, .miniApp:
                    let label = shortcut.kind == .miniApp ? MTStrings.Interface.SettingsTab.miniAppBadge : ""
                    if let key = shortcut.peer, let peer = box.peers[EnginePeer.Id(mtKey: key)] {
                        listRows.append(.peer(id: shortcut.id, peer: peer, title: peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), label: label))
                    } else {
                        listRows.append(.disclosure(id: shortcut.id, title: MTStrings.Interface.Shortcuts.unavailable, label: label, icon: nil))
                    }
                case .site:
                    let url = shortcut.url ?? ""
                    let title = (shortcut.title?.isEmpty == false ? shortcut.title : nil) ?? MTSiteShortcut.displayHost(of: url)
                    let icon = box.favicons[url] ?? MTFaviconStore.monogram(for: MTSiteShortcut.host(of: url) ?? url, size: 29.0)
                    listRows.append(.disclosure(id: shortcut.id, title: title, label: MTStrings.Interface.SettingsTab.siteBadge, icon: icon))
                }
            }
            if shortcuts.isEmpty {
                listRows.append(.footer(MTStrings.Interface.Shortcuts.empty))
            }
            var sections = [MTListSection(listRows)]
            if shortcuts.count < MTShortcutScreens.maxCount {
                sections.append(MTListSection([
                    .action(id: "add.chat", title: MTStrings.Interface.Shortcuts.addChat, isDestructive: false),
                    .action(id: "add.miniApp", title: MTStrings.Interface.Shortcuts.addMiniApp, isDestructive: false),
                    .action(id: "add.site", title: MTStrings.Interface.Shortcuts.addSite, isDestructive: false),
                    .footer(MTStrings.Interface.Shortcuts.footer)
                ]))
            }
            return sections
        }, actions: actions)
        controllerRef = controller
        return controller
    }

    private static func update(context: AccountContext, _ f: (inout [MTSettingsShortcut]) -> Void) {
        let account = context.account.id.mt
        var shortcuts = InterfaceSettings.settingsShortcuts.value(for: account)
        f(&shortcuts)
        InterfaceSettings.settingsShortcuts.set(shortcuts, for: account)
    }

    private static func presentShortcutActions(id: String, context: AccountContext, controller: ViewController?) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let shortcuts = InterfaceSettings.settingsShortcuts.value(for: context.account.id.mt)
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else {
            return
        }
        let shortcut = shortcuts[index]
        var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
        buttons.append((MTStrings.Interface.Common.open, false, {
            MTShortcutActions.open(shortcut, context: context, navigationController: controller?.navigationController as? NavigationController)
        }))
        if let moved = mtMoved(shortcuts, index: index, by: -1) {
            buttons.append((MTStrings.Interface.Common.moveUp, false, {
                MTShortcutScreens.update(context: context, { $0 = moved })
            }))
        }
        if let moved = mtMoved(shortcuts, index: index, by: 1) {
            buttons.append((MTStrings.Interface.Common.moveDown, false, {
                MTShortcutScreens.update(context: context, { $0 = moved })
            }))
        }
        if shortcut.kind == .site {
            buttons.append((MTStrings.Interface.Common.rename, false, {
                mtPresentTextPrompt(from: controller, title: MTStrings.Interface.Shortcuts.siteTitlePrompt, text: shortcut.title ?? "", placeholder: MTSiteShortcut.displayHost(of: shortcut.url ?? ""), cancel: presentationData.strings.Common_Cancel, done: presentationData.strings.Common_Done, completion: { text in
                    let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                    MTShortcutScreens.update(context: context, { list in
                        if let i = list.firstIndex(where: { $0.id == id }) {
                            list[i].title = trimmed.isEmpty ? nil : trimmed
                        }
                    })
                })
            }))
        }
        buttons.append((presentationData.strings.Common_Delete, true, {
            MTShortcutScreens.update(context: context, { list in
                list.removeAll(where: { $0.id == id })
            })
        }))
        mtPresentActionSheet(context: context, from: controller, buttons: buttons)
    }

    /// `@username`, `t.me/username` or a numeric ID (as the chat list search by ID reads it).
    private static func promptPeer(context: AccountContext, controller: ViewController?, kind: MTSettingsShortcut.Kind) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let title = kind == .miniApp ? MTStrings.Interface.Shortcuts.miniAppPrompt : MTStrings.Interface.Shortcuts.chatPrompt
        mtPresentTextPrompt(from: controller, title: title, message: MTStrings.Interface.Shortcuts.peerPromptText, text: "", placeholder: "@username", cancel: presentationData.strings.Common_Cancel, done: presentationData.strings.Common_Done, completion: { text in
            var query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in ["https://", "http://", "t.me/", "telegram.me/", "@"] where query.lowercased().hasPrefix(prefix) {
                query = String(query.dropFirst(prefix.count))
            }
            if let slash = query.firstIndex(of: "/") {
                query = String(query[..<slash])
            }
            if query.isEmpty {
                return
            }
            let resolve: Signal<EnginePeer?, NoError>
            let candidates = MTChatListFeature.peerIdCandidates(query)
            if !candidates.isEmpty {
                resolve = context.engine.data.get(EngineDataMap(candidates.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
                |> map { result -> EnginePeer? in
                    for id in candidates {
                        if let peer = result[id] ?? nil {
                            return peer
                        }
                    }
                    return nil
                }
            } else {
                resolve = context.engine.peers.resolvePeerByName(name: query, referrer: nil)
                |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                    guard case let .result(peer) = result else {
                        return .complete()
                    }
                    return .single(peer)
                }
                |> take(1)
            }
            let _ = (resolve |> deliverOnMainQueue).start(next: { peer in
                guard let peer else {
                    controller?.present(textAlertController(context: context, title: nil, text: MTStrings.Interface.Shortcuts.notFound, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                    return
                }
                if kind == .miniApp {
                    guard case let .user(user) = peer, let botInfo = user.botInfo, botInfo.flags.contains(.hasWebApp) else {
                        controller?.present(textAlertController(context: context, title: nil, text: MTStrings.Interface.Shortcuts.notMiniApp, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                        return
                    }
                }
                let key = peer.id.mtKey
                let id = (kind == .miniApp ? "miniApp:" : "chat:") + "\(key)"
                MTShortcutScreens.update(context: context, { list in
                    if !list.contains(where: { $0.id == id }) && list.count < MTShortcutScreens.maxCount {
                        list.append(MTSettingsShortcut(id: id, kind: kind, peer: key, url: nil, title: nil))
                    }
                })
            })
        })
    }

    private static func promptSite(context: AccountContext, controller: ViewController?) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        mtPresentTextPrompt(from: controller, title: MTStrings.Interface.Shortcuts.sitePrompt, text: "", placeholder: "https://", keyboard: .URL, cancel: presentationData.strings.Common_Cancel, done: presentationData.strings.Common_Done, completion: { text in
            guard let url = MTSiteShortcut.normalizedURL(text) else {
                controller?.present(textAlertController(context: context, title: nil, text: MTStrings.Interface.Shortcuts.invalidUrl, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                return
            }
            let id = "site:" + url
            MTShortcutScreens.update(context: context, { list in
                if !list.contains(where: { $0.id == id }) && list.count < MTShortcutScreens.maxCount {
                    list.append(MTSettingsShortcut(id: id, kind: .site, peer: nil, url: url, title: nil))
                }
            })
        })
    }
}

private final class MTShortcutScreenBox {
    var peers: [EnginePeer.Id: EnginePeer] = [:]
    var favicons: [String: UIImage] = [:]
}
