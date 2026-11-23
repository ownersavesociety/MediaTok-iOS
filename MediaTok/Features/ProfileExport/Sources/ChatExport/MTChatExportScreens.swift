import Foundation
import UIKit
import Display
import AppBundle
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import LocalizedPeerData
import ContextUI
import ItemListUI
import MTCore
import MTHooks
import MTSettingsUI

// Screens of the export: what to include (the choice is remembered), the progress with "Cancel",
// the result ("Save to Files", "Share ZIP", "Done" — the temporary tree is deleted
// after it was saved), and the list of exports left unfinished. Entry points: «…» of a profile and
// Messages › Chat export.

enum MTChatExportMenu {
    static let infoSection = MTMenuSectionID("messages.export.info")

    static func register() {
        MTMenuRegistry.register(MTMenuRow(
            id: "chatExport.chat",
            section: .main(of: .messagesExport),
            order: 100,
            title: { MTStrings.ChatExport.Menu.chat },
            subtitle: { MTStrings.ChatExport.Menu.chatInfo },
            icon: .bundle("Chat/Context Menu/Message"),
            kind: .action({ context in
                mtChatExportPickChat(context: context.context, push: { controller in
                    context.push(controller)
                })
            }),
            searchKeywords: { [MTStrings.ChatExport.Menu.keywords] }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "chatExport.account",
            section: .main(of: .messagesExport),
            order: 200,
            title: { MTStrings.ChatExport.Menu.account },
            subtitle: { MTStrings.ChatExport.Menu.accountInfo },
            icon: .bundle("Chat/Context Menu/Archive"),
            kind: .action({ context in
                context.push(mtMakeChatExportSetupScreen(context: context.context, mode: .account, title: MTStrings.ChatExport.Setup.accountTitle))
            }),
            searchKeywords: { [MTStrings.ChatExport.Menu.keywords] }
        ))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: MTChatExportMenu.infoSection,
            screen: .tab(.messagesExport),
            order: 300,
            footer: { _ in MTStrings.ChatExport.Menu.footer }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "chatExport.jobs",
            section: MTChatExportMenu.infoSection,
            order: 100,
            title: { MTStrings.ChatExport.Menu.jobs },
            subtitle: { MTStrings.ChatExport.Menu.jobsInfo },
            icon: .bundle("Chat/Context Menu/Download"),
            kind: .action({ context in
                if MTChatExportManager.shared.current != nil {
                    // The screen of the current export offers «Save to Files» and «Share ZIP» once it
                    // is done: the same check as before an export starts.
                    MTChatExportAuth.authenticate(reason: MTStrings.ChatExport.Jobs.authReason, completion: { success in
                        if success {
                            context.push(mtMakeChatExportProgressScreen(context: context.context))
                        }
                    })
                } else {
                    context.push(mtMakeChatExportJobsScreen(context: context.context))
                }
            }),
            searchKeywords: { [MTStrings.ChatExport.Menu.keywords] }
        ))

        MTPeerInfoHooks.menuItems.register({ peerInfo in
            if peerInfo.isSettings {
                return []
            }
            let context = peerInfo.context
            let peer = peerInfo.chatPeer ?? peerInfo.peer
            weak let controller = peerInfo.controller
            return [.action(ContextMenuActionItem(text: MTStrings.ChatExport.Menu.profileItem, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Download"), color: theme.contextMenu.primaryColor)
            }, action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                controller?.push(mtMakeChatExportSetupScreen(context: context, mode: .chat(peer.id.mtKey), title: title))
            }))]
        })
    }
}

private func mtChatExportPickChat(context: AccountContext, push: @escaping (ViewController) -> Void) {
    let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.doNotSearchMessages], hasContactSelector: false, title: MTStrings.ChatExport.Menu.chat))
    picker.peerSelected = { [weak picker] peer, _ in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        let setup = mtMakeChatExportSetupScreen(context: context, mode: .chat(peer.id.mtKey), title: title)
        if let navigationController = picker?.navigationController as? NavigationController {
            navigationController.replaceTopController(setup, animated: true)
        } else {
            push(setup)
        }
    }
    push(picker)
}

private func mtChatExportSizeLabel(_ value: String) -> String {
    if value == "0" {
        return MTStrings.ChatExport.Setup.sizeUnlimited
    }
    return MTStrings.ChatExport.Setup.sizeMegabytes(size: value)
}

private func mtChatExportErrorText(_ code: String?) -> String {
    switch code {
    case "noSpace":
        return MTStrings.ChatExport.Progress.errorNoSpace
    case "chatNotFound":
        return MTStrings.ChatExport.Progress.errorChatNotFound
    default:
        return MTStrings.ChatExport.Progress.errorWrite
    }
}

// MARK: - Setup

func mtMakeChatExportSetupScreen(context: AccountContext, mode: MTChatExportMode, title: String) -> ViewController {
    weak var controllerRef: ItemListController?

    let model = combineLatest(queue: .mainQueue(), MTSettingsStore.shared.revision, MTLocalization.shared.languageCodeSignal)
    |> map { _, _ -> MTPEScreenModel in
        var model = MTPEScreenModel(title: MTStrings.ChatExport.Setup.title)
        let options = MTChatExportSettings.currentOptions()

        model.sections.append([
            MTPERow(id: "target", kind: .header(MTStrings.ChatExport.Setup.target)),
            MTPERow(id: "targetName", kind: .info(title))
        ])

        let toggles: [(String, String, MTSetting<Bool>)] = [
            ("photos", MTStrings.ChatExport.Setup.photos, MTChatExportSettings.photos),
            ("videos", MTStrings.ChatExport.Setup.videos, MTChatExportSettings.videos),
            ("voice", MTStrings.ChatExport.Setup.voiceMessages, MTChatExportSettings.voiceMessages),
            ("round", MTStrings.ChatExport.Setup.videoMessages, MTChatExportSettings.videoMessages),
            ("stickers", MTStrings.ChatExport.Setup.stickers, MTChatExportSettings.stickers),
            ("gifs", MTStrings.ChatExport.Setup.gifs, MTChatExportSettings.gifs),
            ("files", MTStrings.ChatExport.Setup.files, MTChatExportSettings.files)
        ]
        var mediaRows: [MTPERow] = [MTPERow(id: "mediaHeader", kind: .header(MTStrings.ChatExport.Setup.mediaHeader))]
        for (id, label, setting) in toggles {
            mediaRows.append(MTPERow(id: id, kind: .check(title: label, subtitle: nil, checked: setting.value)))
            model.tap[id] = {
                setting.set(!setting.value)
            }
        }
        if options.includesMedia {
            mediaRows.append(MTPERow(id: "size", kind: .disclosure(title: MTStrings.ChatExport.Setup.sizeLimit, label: mtChatExportSizeLabel(MTChatExportSettings.sizeLimit.value), icon: nil, enabled: true)))
            model.tap["size"] = {
                mtPEPresentActionSheet(context: context, from: controllerRef, buttons: MTChatExportSettings.sizeLimitValues.map { value in
                    return (title: mtChatExportSizeLabel(value), isDestructive: false, action: {
                        MTChatExportSettings.sizeLimit.set(value)
                    })
                })
            }
        }
        mediaRows.append(MTPERow(id: "mediaFooter", kind: .footer(MTStrings.ChatExport.Setup.mediaFooter)))
        model.sections.append(mediaRows)

        let format = MTChatExportSettings.format.value
        model.sections.append([
            MTPERow(id: "formatHeader", kind: .header(MTStrings.ChatExport.Setup.formatHeader)),
            MTPERow(id: "formatHTML", kind: .check(title: MTStrings.ChatExport.Setup.formatHtml, subtitle: nil, checked: format == "html")),
            MTPERow(id: "formatJSON", kind: .check(title: MTStrings.ChatExport.Setup.formatJson, subtitle: nil, checked: format == "json")),
            MTPERow(id: "formatBoth", kind: .check(title: MTStrings.ChatExport.Setup.formatBoth, subtitle: nil, checked: format != "html" && format != "json"))
        ])
        model.tap["formatHTML"] = {
            MTChatExportSettings.format.set("html")
        }
        model.tap["formatJSON"] = {
            MTChatExportSettings.format.set("json")
        }
        model.tap["formatBoth"] = {
            MTChatExportSettings.format.set("both")
        }

        var startFooter = MTStrings.ChatExport.Setup.startFooter
        if case .account = mode {
            startFooter = MTStrings.ChatExport.Setup.accountFooter
        }
        if let free = MTChatExportJob.freeSpace() {
            startFooter += "\n" + MTStrings.ChatExport.Setup.freeSpace(size: MTChatExportFormat.fileSize(free))
        }
        model.sections.append([
            MTPERow(id: "start", kind: .action(title: MTStrings.ChatExport.Setup.start, destructive: false, enabled: true)),
            MTPERow(id: "startFooter", kind: .footer(startFooter))
        ])
        model.tap["start"] = {
            guard let controller = controllerRef else {
                return
            }
            if MTChatExportManager.shared.isBusy {
                mtPEPresentToast(context: context, from: controller, text: MTStrings.ChatExport.Setup.alreadyRunning)
                return
            }
            if let free = MTChatExportJob.freeSpace(), free < MTChatExportJob.minimumFreeSpace {
                mtPEPresentToast(context: context, from: controller, text: MTStrings.ChatExport.Progress.errorNoSpace)
                return
            }
            MTChatExportAuth.authenticate(reason: MTStrings.ChatExport.Setup.authReason, completion: { success in
                guard success, let controller = controllerRef else {
                    return
                }
                if MTChatExportManager.shared.start(context: context, mode: mode, title: title) {
                    if let navigationController = controller.navigationController as? NavigationController {
                        navigationController.replaceTopController(mtMakeChatExportProgressScreen(context: context), animated: true)
                    }
                } else {
                    mtPEPresentToast(context: context, from: controller, text: MTStrings.ChatExport.Setup.alreadyRunning)
                }
            })
        }
        return model
    }
    let controller = mtPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}

// MARK: - Progress and result

private final class MTChatExportPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completed: () -> Void

    init(completed: @escaping () -> Void) {
        self.completed = completed
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completed()
    }
}

/// Keeps the document picker's delegate alive as long as the screen.
private final class MTChatExportDelegateHolder {
    var delegate: MTChatExportPickerDelegate?
}

private func mtPEPresentNative(_ controller: UIViewController, from presenter: ViewController?) {
    MTModalPresenter.presentOnTopmost(controller, preferredRoot: presenter?.view.window?.rootViewController)
}

func mtMakeChatExportProgressScreen(context: AccountContext) -> ViewController {
    weak var controllerRef: ItemListController?
    let pickerDelegate = MTChatExportDelegateHolder()
    let archiving = ValuePromise<Float?>(nil, ignoreRepeated: true)
    let archiveDisposable = MetaDisposable()

    let model = combineLatest(queue: .mainQueue(), MTChatExportManager.shared.progress, archiving.get(), MTLocalization.shared.languageCodeSignal)
    |> map { progress, archiveProgress, _ -> MTPEScreenModel in
        var model = MTPEScreenModel(title: MTStrings.ChatExport.Progress.title)
        guard let progress = progress, let job = MTChatExportManager.shared.current else {
            model.sections.append([MTPERow(id: "none", kind: .info(MTStrings.ChatExport.Progress.none))])
            return model
        }
        let jobId = progress.jobId

        var status: String
        switch progress.stage {
        case .planning:
            status = MTStrings.ChatExport.Progress.planning
        case .sections:
            status = MTStrings.ChatExport.Progress.sections
        case .chats:
            status = MTStrings.ChatExport.Progress.chat(index: "\(min(progress.chatIndex + 1, progress.chatCount))", count: progress.chatCount, name: progress.chatName ?? "")
        case .finished:
            status = MTStrings.ChatExport.Progress.finished
        case .failed:
            status = MTStrings.ChatExport.Progress.failed(reason: mtChatExportErrorText(progress.errorCode))
        }
        let stats = MTStrings.ChatExport.Progress.stats(messages: "\(progress.messages)", files: "\(progress.files)", size: MTChatExportFormat.fileSize(progress.bytes))
        model.sections.append([
            MTPERow(id: "header", kind: .header(progress.title)),
            MTPERow(id: "status", kind: .info(status + "\n" + stats))
        ])

        switch progress.stage {
        case .finished:
            var rows: [MTPERow] = [
                MTPERow(id: "saveFiles", kind: .action(title: MTStrings.ChatExport.Progress.saveToFiles, destructive: false, enabled: archiveProgress == nil)),
                MTPERow(id: "shareZip", kind: .action(title: archiveProgress.map { MTStrings.ChatExport.Progress.archiving(percent: "\(Int($0 * 100.0))") } ?? MTStrings.ChatExport.Progress.shareZip, destructive: false, enabled: archiveProgress == nil)),
                MTPERow(id: "done", kind: .action(title: MTStrings.ChatExport.Progress.done, destructive: true, enabled: true))
            ]
            rows.append(MTPERow(id: "doneFooter", kind: .footer(MTStrings.ChatExport.Progress.doneFooter)))
            model.sections.append(rows)
            let finish = {
                archiveDisposable.set(nil)
                MTChatExportManager.shared.discard(jobId: jobId)
                controllerRef?.dismiss()
            }
            model.tap["saveFiles"] = {
                let picker = UIDocumentPickerViewController(forExporting: [job.resultURL], asCopy: true)
                let delegate = MTChatExportPickerDelegate(completed: finish)
                pickerDelegate.delegate = delegate
                picker.delegate = delegate
                mtPEPresentNative(picker, from: controllerRef)
            }
            model.tap["shareZip"] = {
                archiving.set(0.0)
                archiveDisposable.set((MTChatExportManager.shared.archive(folder: job.resultURL)
                |> deliverOnMainQueue).start(next: { value, url in
                    archiving.set(url == nil && value < 1.0 ? value : nil)
                    if let url = url {
                        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        activity.completionWithItemsHandler = { _, completed, _, _ in
                            if completed {
                                finish()
                            }
                        }
                        mtPEPresentNative(activity, from: controllerRef)
                    } else if value >= 1.0, let controller = controllerRef {
                        mtPEPresentToast(context: context, from: controller, text: MTStrings.ChatExport.Progress.zipFailed)
                    }
                }))
            }
            model.tap["done"] = finish
        case .failed:
            model.sections.append([
                MTPERow(id: "retry", kind: .action(title: MTStrings.ChatExport.Progress.retry, destructive: false, enabled: true)),
                MTPERow(id: "delete", kind: .action(title: MTStrings.ChatExport.Progress.delete, destructive: true, enabled: true))
            ])
            model.tap["retry"] = {
                if let free = MTChatExportJob.freeSpace(), free < MTChatExportJob.minimumFreeSpace, let controller = controllerRef {
                    mtPEPresentToast(context: context, from: controller, text: MTStrings.ChatExport.Progress.errorNoSpace)
                    return
                }
                MTChatExportManager.shared.retry()
            }
            model.tap["delete"] = {
                MTChatExportManager.shared.discard(jobId: jobId)
                controllerRef?.dismiss()
            }
        case .planning, .sections, .chats:
            model.sections.append([
                MTPERow(id: "cancel", kind: .action(title: MTStrings.ChatExport.Progress.cancel, destructive: true, enabled: true)),
                MTPERow(id: "cancelFooter", kind: .footer(MTStrings.ChatExport.Progress.runningFooter))
            ])
            model.tap["cancel"] = {
                mtPEConfirmDestructive(context: context, from: controllerRef, title: MTStrings.ChatExport.Progress.cancelTitle, text: MTStrings.ChatExport.Progress.cancelText, confirm: MTStrings.ChatExport.Progress.cancel, action: {
                    MTChatExportManager.shared.cancel()
                    controllerRef?.dismiss()
                })
            }
        }
        return model
    }
    let controller = mtPEMakeListController(context: context, model: model)
    controllerRef = controller

    // The screen does not lock while it shows a running export.
    let idleDisposable = MetaDisposable()
    controller.didAppear = { _ in
        idleDisposable.set((MTChatExportManager.shared.progress
        |> deliverOnMainQueue).start(next: { progress in
            UIApplication.shared.isIdleTimerDisabled = progress?.isRunning == true
        }))
    }
    controller.didDisappear = { _ in
        idleDisposable.set(nil)
        UIApplication.shared.isIdleTimerDisabled = false
    }
    return controller
}

// MARK: - Unfinished exports

func mtMakeChatExportJobsScreen(context: AccountContext) -> ViewController {
    weak var controllerRef: ItemListController?
    let format = MTChatExportFormat(languageCode: MTLocalization.shared.languageCode)

    let model = combineLatest(queue: .mainQueue(), MTChatExportManager.shared.storedJobs(accountId: context.account.id.int64), MTLocalization.shared.languageCodeSignal)
    |> map { journals, _ -> MTPEScreenModel in
        var model = MTPEScreenModel(title: MTStrings.ChatExport.Jobs.title)
        var rows: [MTPERow] = [MTPERow(id: "header", kind: .header(MTStrings.ChatExport.Jobs.header))]
        if journals.isEmpty {
            rows.append(MTPERow(id: "empty", kind: .info(MTStrings.ChatExport.Jobs.empty)))
        }
        for journal in journals {
            let id = "job" + journal.id
            let state: String
            switch journal.stage {
            case .finished:
                state = MTStrings.ChatExport.Jobs.finished
            case .failed:
                state = mtChatExportErrorText(journal.errorCode)
            case .planning, .sections, .chats:
                state = MTStrings.ChatExport.Jobs.paused(index: "\(journal.chatIndex)", count: journal.chats.count)
            }
            rows.append(MTPERow(id: id, kind: .disclosure(title: journal.title, label: format.full(journal.createdAt) + " · " + state, icon: nil, enabled: true)))
            model.tap[id] = {
                var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
                if journal.stage != .finished {
                    buttons.append((title: MTStrings.ChatExport.Jobs.resume, isDestructive: false, action: {
                        MTChatExportAuth.authenticate(reason: MTStrings.ChatExport.Setup.authReason, completion: { success in
                            guard success, let controller = controllerRef else {
                                return
                            }
                            if MTChatExportManager.shared.resume(context: context, journal: journal) {
                                controller.push(mtMakeChatExportProgressScreen(context: context))
                            } else {
                                mtPEPresentToast(context: context, from: controller, text: MTStrings.ChatExport.Setup.alreadyRunning)
                            }
                        })
                    }))
                } else {
                    buttons.append((title: MTStrings.ChatExport.Jobs.open, isDestructive: false, action: {
                        // A finished export can be saved or shared from its screen: Face ID first, as
                        // before it was made.
                        MTChatExportAuth.authenticate(reason: MTStrings.ChatExport.Jobs.authReason, completion: { success in
                            guard success, let controller = controllerRef else {
                                return
                            }
                            if MTChatExportManager.shared.resume(context: context, journal: journal) {
                                controller.push(mtMakeChatExportProgressScreen(context: context))
                            }
                        })
                    }))
                }
                buttons.append((title: MTStrings.ChatExport.Jobs.delete, isDestructive: true, action: {
                    MTChatExportManager.shared.discard(jobId: journal.id)
                }))
                mtPEPresentActionSheet(context: context, from: controllerRef, title: journal.title, buttons: buttons)
            }
        }
        rows.append(MTPERow(id: "footer", kind: .footer(MTStrings.ChatExport.Jobs.footer)))
        model.sections.append(rows)
        return model
    }
    let controller = mtPEMakeListController(context: context, model: model)
    controllerRef = controller
    return controller
}
