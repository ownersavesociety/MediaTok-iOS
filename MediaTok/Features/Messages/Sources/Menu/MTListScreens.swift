import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import PresentationDataUtils
import PromptUI
import MTCore
import MTSettingsUI
import MTFeaturesShared

// MARK: - Replacement rules

/// One rule set (the old visible and hidden systems are merged). A rule is added or edited with
/// two prompts; the setting is written once per completed edit, never per keystroke.
func mtMakeReplacementRulesScreen(menuContext: MTMenuContext) -> ViewController {
    let context = menuContext.context
    func edit(index: Int?) {
        let rules = MTOutgoingPipeline.replacementRules.value
        let current = index.flatMap { $0 < rules.count ? rules[$0] : nil }
        menuContext.present(promptController(context: context, text: MTStrings.Sending.Rules.sourcePrompt, value: current?.source, characterLimit: 128, apply: { source in
            guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else {
                return
            }
            menuContext.present(promptController(context: context, text: MTStrings.Sending.Rules.replacementPrompt, value: current?.replacement, characterLimit: 512, apply: { replacement in
                guard let replacement else {
                    return
                }
                var updated = MTOutgoingPipeline.replacementRules.value
                let rule = MTTextReplacementRule(source: source, replacement: replacement)
                if let index, index < updated.count {
                    updated[index] = rule
                } else {
                    updated.removeAll(where: { $0.source.lowercased() == source.lowercased() })
                    updated.append(rule)
                }
                MTOutgoingPipeline.replacementRules.set(updated)
            }))
        }))
    }
    return mtMakeEditableListScreen(context: context, content: {
        let items = MTOutgoingPipeline.replacementRules.value.enumerated().map { index, rule in
            return MTEditableListItem(id: "\(index)", title: rule.source + " → " + rule.replacement)
        }
        return MTEditableListContent(title: MTStrings.Sending.Rules.title, addTitle: MTStrings.Sending.Rules.add, emptyText: MTStrings.Sending.Rules.empty, footer: MTStrings.Sending.Rules.footer, items: items)
    }, add: {
        edit(index: nil)
    }, select: { id in
        guard let index = Int(id) else {
            return
        }
        mtPresentActionSheet(context: context, title: nil, actions: [
            (MTStrings.Sending.Rules.edit, false, {
                edit(index: index)
            }),
            (MTStrings.Sending.Rules.delete, true, {
                var updated = MTOutgoingPipeline.replacementRules.value
                if index < updated.count {
                    updated.remove(at: index)
                    MTOutgoingPipeline.replacementRules.set(updated)
                }
            })
        ], present: { menuContext.present($0) })
    })
}

// MARK: - Keyword filter

func mtMakeKeywordsScreen(menuContext: MTMenuContext) -> ViewController {
    let context = menuContext.context
    return mtMakeEditableListScreen(context: context, content: {
        let items = MTMessagesSettings.keywords.value.enumerated().map { index, word in
            return MTEditableListItem(id: "\(index)", title: word)
        }
        return MTEditableListContent(title: MTStrings.Chats.Keywords.title, addTitle: MTStrings.Chats.Keywords.add, emptyText: MTStrings.Chats.Keywords.empty, footer: MTStrings.Chats.Keywords.footer, items: items)
    }, add: {
        menuContext.present(promptController(context: context, text: MTStrings.Chats.Keywords.prompt, value: nil, characterLimit: 128, apply: { value in
            guard let word = value?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else {
                return
            }
            var words = MTMessagesSettings.keywords.value
            if !words.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                words.append(word)
                MTMessagesSettings.keywords.set(words)
            }
        }))
    }, select: { id in
        guard let index = Int(id) else {
            return
        }
        mtPresentActionSheet(context: context, title: nil, actions: [
            (MTStrings.Chats.Keywords.delete, true, {
                var words = MTMessagesSettings.keywords.value
                if index < words.count {
                    words.remove(at: index)
                    MTMessagesSettings.keywords.set(words)
                }
            })
        ], present: { menuContext.present($0) })
    })
}

// MARK: - Peers of the account (local creator mode, notification exceptions)

/// Peers for a list screen: loaded once per set of keys, the list rebuilds when they arrive.
private final class MTPeerTitles {
    private(set) var peers: [MTPeerKey: EnginePeer] = [:]
    private let updated = ValuePromise<Int>(0, ignoreRepeated: false)
    private var counter = 0
    private var requested = Set<MTPeerKey>()

    var signal: Signal<Void, NoError> {
        return self.updated.get() |> map { _ in Void() }
    }

    func load(_ keys: [MTPeerKey], context: AccountContext) {
        let missing = keys.filter { !self.requested.contains($0) }
        if missing.isEmpty {
            return
        }
        for key in missing {
            self.requested.insert(key)
        }
        let _ = (context.engine.data.get(EngineDataMap(missing.map { TelegramEngine.EngineData.Item.Peer.Peer(id: PeerId(mtKey: $0)) }))
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self else {
                return
            }
            for (peerId, peer) in result {
                if let peer {
                    self.peers[peerId.mtKey] = peer
                }
            }
            self.counter += 1
            self.updated.set(self.counter)
        })
    }
}

func mtMakeLocalCreatorScreen(menuContext: MTMenuContext) -> ViewController {
    let context = menuContext.context
    let accountId = menuContext.accountID
    let titles = MTPeerTitles()
    return mtMakeEditableListScreen(context: context, extra: titles.signal, content: {
        let keys = MTMessagesSettings.localCreatorChannels.value(for: accountId).sorted()
        titles.load(keys, context: context)
        let items = keys.map { key -> MTEditableListItem in
            let peer = titles.peers[key]
            return MTEditableListItem(id: key.stringValue, title: peer?.debugDisplayTitle ?? key.stringValue, peer: peer)
        }
        return MTEditableListContent(title: MTStrings.Chats.LocalCreator.title, addTitle: nil, emptyText: MTStrings.Chats.LocalCreator.empty, footer: MTStrings.Chats.LocalCreator.footer, items: items)
    }, add: nil, select: { id in
        guard let key = MTPeerKey(string: id) else {
            return
        }
        mtPresentActionSheet(context: context, title: nil, actions: [
            (MTStrings.Chats.LocalCreator.disable, true, {
                MTLocalCreatorMode.setLocalMode(false, peerId: PeerId(mtKey: key), accountId: accountId)
            })
        ], present: { menuContext.present($0) })
    })
}

/// Per-chat exceptions of SG-H1 (legacy format read them in the extension, nothing wrote them).
enum MTNotificationExceptions {
    static func peerKeys(accountId: MTAccountID) -> [MTPeerKey] {
        let pinned = MTMessagesSettings.pinnedNotificationExceptions.value(for: accountId)
        let mentions = MTMessagesSettings.mentionNotificationExceptions.value(for: accountId)
        var keys = Set<MTPeerKey>()
        for key in pinned.keys {
            if let value = MTPeerKey(string: key) {
                keys.insert(value)
            }
        }
        for key in mentions.keys {
            if let value = MTPeerKey(string: key) {
                keys.insert(value)
            }
        }
        return keys.sorted()
    }

    static func modeTitle(_ value: String?) -> String {
        guard let value, let mode = MTNotificationDeliveryMode(rawValue: value) else {
            return MTStrings.Notifications.Exceptions.general
        }
        switch mode {
        case .standard:
            return MTStrings.Notifications.Menu.modeStandard
        case .silent:
            return MTStrings.Notifications.Menu.modeSilent
        case .disabled:
            return MTStrings.Notifications.Menu.modeDisabled
        }
    }

    static func set(_ mode: MTNotificationDeliveryMode?, kind: MTNotificationFilter.Kind, peer: MTPeerKey, accountId: MTAccountID) {
        let setting: MTAccountSetting<[String: String]>
        switch kind {
        case .pinnedMessage:
            setting = MTMessagesSettings.pinnedNotificationExceptions
        case .mentionOrReply:
            setting = MTMessagesSettings.mentionNotificationExceptions
        }
        var values = setting.value(for: accountId)
        values[peer.stringValue] = mode?.rawValue
        setting.set(values, for: accountId)
    }

    static func chooseMode(kind: MTNotificationFilter.Kind, peer: MTPeerKey, accountId: MTAccountID, menuContext: MTMenuContext) {
        let title = kind == .pinnedMessage ? MTStrings.Notifications.Menu.pinned : MTStrings.Notifications.Menu.mentions
        mtPresentActionSheet(context: menuContext.context, title: title, actions: [
            (MTStrings.Notifications.Exceptions.general, false, {
                MTNotificationExceptions.set(nil, kind: kind, peer: peer, accountId: accountId)
            }),
            (MTStrings.Notifications.Menu.modeStandard, false, {
                MTNotificationExceptions.set(.standard, kind: kind, peer: peer, accountId: accountId)
            }),
            (MTStrings.Notifications.Menu.modeSilent, false, {
                MTNotificationExceptions.set(.silent, kind: kind, peer: peer, accountId: accountId)
            }),
            (MTStrings.Notifications.Menu.modeDisabled, false, {
                MTNotificationExceptions.set(.disabled, kind: kind, peer: peer, accountId: accountId)
            })
        ], present: { menuContext.present($0) })
    }
}

func mtMakeNotificationExceptionsScreen(menuContext: MTMenuContext) -> ViewController {
    let context = menuContext.context
    let accountId = menuContext.accountID
    let titles = MTPeerTitles()
    let edit: (MTPeerKey) -> Void = { key in
        mtPresentActionSheet(context: context, title: nil, actions: [
            (MTStrings.Notifications.Menu.pinned, false, {
                MTNotificationExceptions.chooseMode(kind: .pinnedMessage, peer: key, accountId: accountId, menuContext: menuContext)
            }),
            (MTStrings.Notifications.Menu.mentions, false, {
                MTNotificationExceptions.chooseMode(kind: .mentionOrReply, peer: key, accountId: accountId, menuContext: menuContext)
            }),
            (MTStrings.Notifications.Exceptions.remove, true, {
                MTNotificationExceptions.set(nil, kind: .pinnedMessage, peer: key, accountId: accountId)
                MTNotificationExceptions.set(nil, kind: .mentionOrReply, peer: key, accountId: accountId)
            })
        ], present: { menuContext.present($0) })
    }
    return mtMakeEditableListScreen(context: context, extra: titles.signal, content: {
        let keys = MTNotificationExceptions.peerKeys(accountId: accountId)
        titles.load(keys, context: context)
        let pinned = MTMessagesSettings.pinnedNotificationExceptions.value(for: accountId)
        let mentions = MTMessagesSettings.mentionNotificationExceptions.value(for: accountId)
        let items = keys.map { key -> MTEditableListItem in
            let peer = titles.peers[key]
            let label = MTStrings.Notifications.Exceptions.pinnedValue(mode: MTNotificationExceptions.modeTitle(pinned[key.stringValue])) + " · " + MTStrings.Notifications.Exceptions.mentionsValue(mode: MTNotificationExceptions.modeTitle(mentions[key.stringValue]))
            return MTEditableListItem(id: key.stringValue, title: peer?.debugDisplayTitle ?? key.stringValue, label: label, peer: peer)
        }
        return MTEditableListContent(title: MTStrings.Notifications.Exceptions.title, addTitle: MTStrings.Notifications.Exceptions.add, emptyText: MTStrings.Notifications.Exceptions.empty, footer: MTStrings.Notifications.Menu.footer, items: items)
    }, add: {
        guard let navigationController = menuContext.navigationController else {
            return
        }
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasFilters: true, hasContactSelector: false))
        controller.peerSelected = { [weak controller] peer, _ in
            controller?.dismiss()
            edit(peer.id.mtKey)
        }
        navigationController.pushViewController(controller)
    }, select: { id in
        if let key = MTPeerKey(string: id) {
            edit(key)
        }
    })
}
