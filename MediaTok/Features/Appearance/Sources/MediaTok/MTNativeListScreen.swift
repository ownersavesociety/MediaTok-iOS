import Foundation
import UIKit
import Display
import AppBundle
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import AlertUI
import PromptUI
import UndoUI
import MTSettingsUI

// MARK: - 100% Native Telegram ItemListController + ActionSheet + Prompt + UndoToast Infrastructure

public struct MTNativeIcon: Equatable {
    public let image: UIImage

    public init(_ image: UIImage) {
        self.image = image
    }

    public static func bundle(_ name: String) -> MTNativeIcon? {
        guard let img = UIImage(bundleImageName: name) else { return nil }
        return MTNativeIcon(img)
    }

    public static func system(_ name: String) -> MTNativeIcon? {
        guard let img = UIImage(systemName: name) else { return nil }
        return MTNativeIcon(img)
    }

    public static func ==(lhs: MTNativeIcon, rhs: MTNativeIcon) -> Bool {
        return lhs.image === rhs.image
    }
}

public struct MTNativeRow: Equatable {
    public enum Kind: Equatable {
        case header(String)
        case footer(String)
        case info(String)
        case action(title: String, destructive: Bool, enabled: Bool)
        case disclosure(title: String, label: String, icon: MTNativeIcon?, enabled: Bool)
        case peer(title: String, label: String, peer: EnginePeer?)
        case toggle(title: String, value: Bool, enabled: Bool)
        case check(title: String, subtitle: String?, checked: Bool)
        case input(text: String, placeholder: String)
        case multilineInput(text: String, placeholder: String)
    }

    public let id: String
    public let kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

public struct MTNativeScreenModel {
    public var title: String
    public var sections: [[MTNativeRow]] = []
    public var tap: [String: () -> Void] = [:]
    public var text: [String: (String) -> Void] = [:]
    public var toggle: [String: (Bool) -> Void] = [:]
    public var rightButton: (title: String, enabled: Bool, action: () -> Void)?

    public init(title: String) {
        self.title = title
    }
}

public final class MTNativeListHandlers {
    public var tap: [String: () -> Void] = [:]
    public var text: [String: (String) -> Void] = [:]
    public var toggle: [String: (Bool) -> Void] = [:]
    public init() {}
}

private struct MTNativeListEntry: ItemListNodeEntry {
    let row: MTNativeRow
    let sectionIndex: Int
    let rowIndex: Int
    let context: AccountContext

    var section: ItemListSectionId {
        return ItemListSectionId(self.sectionIndex)
    }

    var stableId: String {
        return self.row.id
    }

    static func ==(lhs: MTNativeListEntry, rhs: MTNativeListEntry) -> Bool {
        return lhs.row == rhs.row && lhs.sectionIndex == rhs.sectionIndex && lhs.rowIndex == rhs.rowIndex
    }

    static func <(lhs: MTNativeListEntry, rhs: MTNativeListEntry) -> Bool {
        if lhs.sectionIndex != rhs.sectionIndex {
            return lhs.sectionIndex < rhs.sectionIndex
        }
        return lhs.rowIndex < rhs.rowIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let handlers = arguments as! MTNativeListHandlers
        let id = self.row.id
        switch self.row.kind {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text.uppercased(), sectionId: self.section)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .info(text):
            return ItemListMultilineTextItem(presentationData: presentationData, text: text, enabledEntityTypes: [], sectionId: self.section, style: .blocks)
        case let .action(title, destructive, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: destructive ? .destructive : (enabled ? .generic : .disabled), alignment: .natural, sectionId: self.section, style: .blocks, action: {
                handlers.tap[id]?()
            })
        case let .disclosure(title, label, icon, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon?.image, title: title, enabled: enabled, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: {
                handlers.tap[id]?()
            })
        case let .peer(title, label, peer):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, context: peer == nil ? nil : self.context, iconPeer: peer, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: {
                handlers.tap[id]?()
            })
        case let .toggle(title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                handlers.toggle[id]?(value)
            })
        case let .check(title, subtitle, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, subtitle: subtitle, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                handlers.tap[id]?()
            })
        case let .input(text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), returnKeyType: .done, clearType: .always, sectionId: self.section, textUpdated: { value in
                handlers.text[id]?(value)
            }, action: {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
        case let .multilineInput(text, placeholder):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: self.section, style: .blocks, textUpdated: { value in
                handlers.text[id]?(value)
            })
        }
    }
}

/// Creates a 100% native Telegram `ItemListController` driven by a reactive `MTNativeScreenModel` signal.
public func mtMakeNativeListController(
    context: AccountContext,
    model: Signal<MTNativeScreenModel, NoError>,
    modalCloseButton: Bool = false
) -> ItemListController {
    let handlers = MTNativeListHandlers()
    weak var controllerBox: ItemListController?
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, model)
    |> map { presentationData, model -> (ItemListControllerState, (ItemListNodeState, MTNativeListHandlers)) in
        handlers.tap = model.tap
        handlers.text = model.text
        handlers.toggle = model.toggle
        var entries: [MTNativeListEntry] = []
        for (sectionIndex, rows) in model.sections.enumerated() {
            for (rowIndex, row) in rows.enumerated() {
                entries.append(MTNativeListEntry(row: row, sectionIndex: sectionIndex, rowIndex: rowIndex, context: context))
            }
        }
        var leftButton: ItemListNavigationButton?
        if modalCloseButton {
            leftButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Close), style: .regular, enabled: true, action: {
                controllerBox?.dismiss()
            })
        }
        var rightButton: ItemListNavigationButton?
        if let button = model.rightButton {
            rightButton = ItemListNavigationButton(content: .text(button.title), style: .bold, enabled: button.enabled, action: button.action)
        }
        let itemListPresentationData = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: itemListPresentationData,
            title: .text(model.title),
            leftNavigationButton: leftButton,
            rightNavigationButton: rightButton,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: itemListPresentationData,
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, handlers))
    }
    let controller = ItemListController(context: context, state: signal)
    controllerBox = controller
    return controller
}

/// Pushes a native Telegram `ViewController` onto the active `NavigationController` stack (or presents on root if none).
public func mtPushNativeController(_ controller: ViewController, context: AccountContext, from sourceController: ViewController? = nil) {
    DispatchQueue.main.async {
        if let sourceController {
            if let nav = sourceController.navigationController as? NavigationController {
                nav.pushViewController(controller)
                return
            }
            sourceController.push(controller)
            return
        }
        if let nav = context.sharedContext.mainWindow?.viewController as? NavigationController {
            nav.pushViewController(controller)
        } else {
            context.sharedContext.mainWindow?.present(controller, on: .root)
        }
    }
}

/// Presents a native Telegram `ActionSheetController` with Cancel.
public func mtPresentNativeActionSheet(
    context: AccountContext,
    from controller: ViewController? = nil,
    title: String? = nil,
    onCancel: (() -> Void)? = nil,
    buttons: [(title: String, isDestructive: Bool, action: () -> Void)]
) {
    mtPresentMenuActionSheet(context: context, from: controller, title: title, onCancel: onCancel, buttons: buttons)
}

/// Presents Telegram's native `promptController` text input dialog.
public func mtPresentNativePrompt(
    context: AccountContext,
    from controller: ViewController? = nil,
    title: String,
    subtitle: String? = nil,
    value: String = "",
    placeholder: String = "",
    characterLimit: Int = 512,
    onCancel: (() -> Void)? = nil,
    apply: @escaping (String) -> Void
) {
    mtPresentMenuPrompt(context: context, from: controller, title: title, subtitle: subtitle, value: value, placeholder: placeholder, characterLimit: characterLimit, onCancel: onCancel, apply: apply)
}

/// Presents Telegram's native `textAlertController`.
public func mtPresentNativeAlert(
    context: AccountContext,
    from controller: ViewController? = nil,
    title: String?,
    text: String,
    confirmTitle: String? = nil,
    destructive: Bool = false,
    confirmAction: (() -> Void)? = nil
) {
    mtPresentMenuAlert(context: context, from: controller, title: title, text: text, confirmTitle: confirmTitle, destructive: destructive, confirmAction: confirmAction)
}

/// Presents Telegram's native `UndoOverlayController` toast.
public func mtPresentNativeToast(
    context: AccountContext,
    from controller: ViewController? = nil,
    text: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
) {
    DispatchQueue.main.async {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let undo = UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: text, timeout: nil, customUndoText: actionTitle),
            elevatedLayout: false,
            action: { res in
                if case .undo = res {
                    action?()
                }
                return true
            }
        )
        mtPresentContainableOverlay(undo, context: context, from: controller, isToast: true)
    }
}
