import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import MTCore

// MediaTok's own rows: «Настройки MediaTok» (language, export / import with a diff / reset) and
// «О приложении» (version, links, license). Data operations are MTCore's; this is the UI.

private let mtSourceCodeUrl = "https://github.com/ownersavesociety/MediaTok-iOS"
private let mtImportMaximumFileSize = 4 * 1024 * 1024

func mtRegisterBuiltInRows() {
    // Language: "" follows Telegram, otherwise one of the languages that have MediaTok strings.
    MTMenuRegistry.register(MTMenuRow(
        id: "menu.language",
        section: .mediatokSettingsLanguage,
        order: 100,
        title: { MTStrings.Menu.Settings.language },
        icon: .bundle("Chat/Context Menu/Translate"),
        kind: .choice(.global(MTLocalization.languageOverride), options: mtLanguageOptions())
    ))
    MTMenuRegistry.register(MTMenuRow(
        id: "menu.telegramLanguage",
        section: .mediatokSettingsLanguage,
        order: 200,
        title: { MTStrings.Menu.Settings.telegramLanguage },
        icon: .bundle("Chat/Context Menu/Globe"),
        kind: .action({ menuContext in
            if let controller = MTSettingsUIEnvironment.shared.makeTelegramLanguageController?(menuContext.context) {
                menuContext.push(controller)
            }
        }),
        isVisible: { _ in
            return MTSettingsUIEnvironment.shared.makeTelegramLanguageController != nil
        }
    ))

    MTMenuRegistry.register(MTMenuRow(
        id: "menu.export",
        section: .mediatokSettingsData,
        order: 100,
        title: { MTStrings.Menu.Settings.exportSettings },
        subtitle: { MTStrings.Menu.Settings.exportInfo },
        icon: .bundle("Chat/Context Menu/Share"),
        kind: .action({ menuContext in
            mtExportSettings(menuContext: menuContext)
        })
    ))
    MTMenuRegistry.register(MTMenuRow(
        id: "menu.import",
        section: .mediatokSettingsData,
        order: 200,
        title: { MTStrings.Menu.Settings.importSettings },
        subtitle: { MTStrings.Menu.Settings.importInfo },
        icon: .bundle("Chat/Context Menu/Download"),
        kind: .action({ menuContext in
            mtPickSettingsFile(menuContext: menuContext)
        })
    ))
    MTMenuRegistry.register(MTMenuRow(
        id: "menu.reset",
        section: .mediatokSettingsData,
        order: 300,
        title: { MTStrings.Menu.Settings.reset },
        kind: .action({ menuContext in
            mtConfirmResetAll(menuContext: menuContext)
        }),
        isDestructive: true
    ))

    MTMenuRegistry.register(MTMenuRow(
        id: "menu.about.version",
        section: .aboutInfo,
        order: 100,
        title: { MTStrings.Menu.About.version },
        icon: .ghost,
        kind: .action({ menuContext in
            UIPasteboard.general.string = mtAppVersionString()
            menuContext.presentToast(MTStrings.Menu.About.versionCopied)
        }),
        label: { _ in
            return mtAppVersionString()
        }
    ))
    for (index, link) in mtMenuLinks.enumerated() {
        let id = link.id
        let url = link.url
        let username = link.username
        MTMenuRegistry.register(MTMenuRow(
            id: "menu.about.\(id)",
            section: .aboutLinks,
            order: (index + 1) * 100,
            title: {
                return mtMenuLinkTitle(id)
            },
            icon: link.icon,
            kind: .action({ menuContext in
                menuContext.openTelegramLink(url)
            }),
            label: { _ in
                return username
            }
        ))
    }
    MTMenuRegistry.register(MTMenuRow(
        id: "menu.about.source",
        section: .aboutLicense,
        order: 100,
        title: { MTStrings.Menu.About.sourceCode },
        icon: .bundle("Chat/Context Menu/Browser"),
        kind: .action({ menuContext in
            menuContext.context.sharedContext.applicationBindings.openUrl(mtSourceCodeUrl)
        })
    ))
}

/// MediaTok's languages. Names are resolved at display time,
/// so registering the row at launch does not parse every string table.
private let mtMenuLanguageCodes = ["en", "ru", "uk", "ar"]

private func mtLanguageOptions() -> [MTMenuChoiceOption] {
    var options: [MTMenuChoiceOption] = [MTMenuChoiceOption(value: "", title: { MTStrings.Core.Language.followTelegram })]
    for code in mtMenuLanguageCodes {
        options.append(MTMenuChoiceOption(value: code, title: {
            return MTLocalization.shared.availableLanguages.first(where: { $0.code == code })?.nativeName ?? code
        }))
    }
    return options
}

// MARK: - Export

/// The export goes to a temporary file that is removed when the share sheet closes; the file is
/// written off the main thread.
private func mtExportSettings(menuContext: MTMenuContext) {
    let store = MTSettingsStore.shared
    let data = store.exportData(accounts: store.registeredAccounts)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let fileName = "mediatok-settings-\(formatter.string(from: Date())).json"

    Queue.concurrentDefaultQueue().async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mediatok-export", isDirectory: true)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        let written = (try? data.write(to: url, options: .atomic)) != nil
        Queue.mainQueue().async {
            guard written else {
                menuContext.presentToast(MTStrings.Menu.Settings.exportFailed)
                return
            }
            let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activityController.completionWithItemsHandler = { _, _, _, _ in
                Queue.concurrentDefaultQueue().async {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
            menuContext.presentNative(activityController)
        }
    }
}

// MARK: - Import

/// `UIDocumentPickerViewController` holds its delegate weakly; this one keeps itself alive until a callback.
private final class MTDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void
    private var lifetime: MTDocumentPickerDelegate?

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        super.init()
        self.lifetime = self
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
        self.lifetime = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion(nil)
        self.lifetime = nil
    }
}

private func mtPickSettingsFile(menuContext: MTMenuContext) {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json, UTType.data], asCopy: true)
    picker.allowsMultipleSelection = false
    let delegate = MTDocumentPickerDelegate(completion: { url in
        guard let url else {
            return
        }
        // The picked copy lives in our tmp/Inbox: read it off the main thread and delete it right away.
        Queue.concurrentDefaultQueue().async {
            var data: Data?
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            if size > 0 && size <= mtImportMaximumFileSize {
                data = try? Data(contentsOf: url)
            }
            try? FileManager.default.removeItem(at: url)
            Queue.mainQueue().async {
                mtPreviewImport(data: data, menuContext: menuContext)
            }
        }
    })
    picker.delegate = delegate
    menuContext.presentNative(picker)
}

private func mtPreviewImport(data: Data?, menuContext: MTMenuContext) {
    guard let data else {
        menuContext.presentToast(MTSettingsImportError.invalidFormat.localizedText)
        return
    }
    let diff: MTSettingsImportDiff
    do {
        diff = try MTSettingsStore.shared.importPreview(data)
    } catch let error as MTSettingsImportError {
        menuContext.presentToast(error.localizedText)
        return
    } catch {
        menuContext.presentToast(MTSettingsImportError.invalidFormat.localizedText)
        return
    }
    if diff.isEmpty {
        menuContext.presentToast(MTStrings.Menu.Settings.importNoChanges)
        return
    }
    menuContext.push(mtMakeImportDiffController(diff: diff, menuContext: menuContext))
}

/// Compact JSON of a value → what a person reads.
private func mtImportValueText(_ json: String) -> String {
    switch json {
    case "true":
        return MTStrings.Menu.Settings.valueOn
    case "false":
        return MTStrings.Menu.Settings.valueOff
    case "null", "":
        return "—"
    default:
        break
    }
    var text = json
    if text.count >= 2 && text.hasPrefix("\"") && text.hasSuffix("\"") {
        text = String(text.dropFirst().dropLast())
    }
    if text.count > 48 {
        text = String(text.prefix(47)) + "…"
    }
    return text
}

private enum MTImportDiffEntry: ItemListNodeEntry {
    case changesHeader(String)
    case change(index: Int, title: String, detail: String, scope: String?)
    case notes(String)
    case apply(String)

    var section: ItemListSectionId {
        switch self {
        case .changesHeader, .change, .notes:
            return 0
        case .apply:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .changesHeader:
            return 0
        case let .change(index, _, _, _):
            return 1 + index
        case .notes:
            return Int.max - 1
        case .apply:
            return Int.max
        }
    }

    static func <(lhs: MTImportDiffEntry, rhs: MTImportDiffEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let apply = arguments as! () -> Void
        switch self {
        case let .changesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text.uppercased(), sectionId: self.section)
        case let .change(_, title, detail, scope):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: scope ?? "", labelStyle: .text, additionalDetailLabel: detail, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .notes(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .apply(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: {
                apply()
            })
        }
    }
}

private func mtMakeImportDiffController(diff: MTSettingsImportDiff, menuContext: MTMenuContext) -> ViewController {
    let context = menuContext.context
    var dismissImpl: (() -> Void)?
    let apply: () -> Void = {
        MTSettingsStore.shared.applyImport(diff)
        dismissImpl?()
        menuContext.presentToast(MTStrings.Menu.Settings.importDone)
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, MTLocalization.shared.languageCodeSignal)
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, () -> Void)) in
        let storage = MTMenuStorage.shared
        var entries: [MTImportDiffEntry] = [.changesHeader(MTStrings.Menu.Settings.importChanges(count: diff.changes.count))]
        for (index, change) in diff.changes.enumerated() {
            var title = change.key
            if let row = storage.row(forSettingKey: change.key) {
                title = row.title()
                // A child of «Скрыть в сообщениях» is «Время» on its own: name its group too.
                if let groupId = storage.groupByChildId[row.id], let group = storage.rowsById[groupId] {
                    title = group.title() + " › " + title
                }
            }
            let scope: String?
            switch change.scope {
            case .account:
                scope = MTStrings.Menu.Settings.scopeAccount
            case .global, .appGroup:
                scope = nil
            }
            entries.append(.change(index: index, title: title, detail: "\(mtImportValueText(change.oldValue)) → \(mtImportValueText(change.newValue))", scope: scope))
        }
        var notes: [String] = []
        if !diff.skippedKeys.isEmpty {
            notes.append(MTStrings.Menu.Settings.importSkipped(count: diff.skippedKeys.count))
        }
        if !diff.unknownKeys.isEmpty {
            notes.append(MTStrings.Menu.Settings.importUnknown(count: diff.unknownKeys.count))
        }
        if !diff.unmatchedAccounts.isEmpty {
            notes.append(MTStrings.Menu.Settings.importUnmatchedAccounts(count: diff.unmatchedAccounts.count))
        }
        if !notes.isEmpty {
            entries.append(.notes(notes.joined(separator: "\n")))
        }
        entries.append(.apply(MTStrings.Menu.Settings.importApply))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(MTStrings.Menu.Settings.importTitle), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, apply))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        if let navigationController = controller?.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        }
    }
    return controller
}

// MARK: - Reset

private func mtConfirmResetAll(menuContext: MTMenuContext) {
    let presentationData = menuContext.presentationData
    menuContext.present(textAlertController(context: menuContext.context, title: MTStrings.Menu.Settings.resetTitle, text: MTStrings.Menu.Settings.resetText, actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .destructiveAction, title: MTStrings.Menu.Settings.resetConfirm, action: {
            let store = MTSettingsStore.shared
            store.resetAll(accounts: store.registeredAccounts)
            menuContext.presentToast(MTStrings.Menu.Settings.resetDone)
        })
    ]))
}
