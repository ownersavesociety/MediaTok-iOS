import Foundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import Vision
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import PromptUI
import MTCore
import MTFeaturesShared

// The mask studio: own masks → editor of one mask (live preview, cost, layers) → adding a layer
// (try-on from the catalog of filters) → parameters of a layer. Edits stay in memory and reach the
// preview at once; the disk is written when an edit is finished. No timers: the measured frame
// rate is read when the screen rebuilds.

// MARK: - Home

func mtMakeMaskStudioHome(context: AccountContext) -> ViewController {
    weak var controllerRef: ViewController?
    var entries: [MTMaskStoreEntry] = []
    var storageSize: Int64 = 0
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshValue = 0
    let bump = {
        refreshValue += 1
        refresh.set(refreshValue)
    }
    let extra: Signal<Void, NoError> = combineLatest(MTMaskStore.shared.entries, MTMaskEngine.shared.changes.get(), refresh.get())
    |> deliverOnMainQueue
    |> map { value, _, _ -> Void in
        entries = value
        return Void()
    }

    let openEditor: (String) -> Void = { id in
        if let editor = mtMakeMaskEditor(context: context, maskId: id) {
            controllerRef?.push(editor)
        }
    }

    let create: () -> Void = {
        controllerRef?.present(promptController(context: context, text: MTStrings.CameraMasks.Studio.create, subtitle: MTStrings.CameraMasks.Studio.createText, value: MTStrings.CameraMasks.Studio.defaultName, placeholder: MTStrings.CameraMasks.Studio.namePlaceholder, characterLimit: 64, apply: { value in
            guard let value else {
                return
            }
            MTMaskStore.shared.create(name: value, completion: { result in
                switch result {
                case let .success(id):
                    openEditor(id)
                case let .failure(error):
                    mtPresentStudioError(context: context, controller: controllerRef, error: error)
                }
            })
        }), in: .window(.root))
    }

    let importMask = {
        let box = MTDocumentPickerBox()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data, UTType.json, UTType.plainText], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = box
        box.retain()
        box.onDocument = { url in
            box.releaseHandlers()
            guard let url else {
                return
            }
            MTMaskStore.shared.importPackage(at: url, completion: { result in
                try? FileManager.default.removeItem(at: url)
                switch result {
                case let .success(id):
                    openEditor(id)
                case let .failure(error):
                    mtPresentStudioError(context: context, controller: controllerRef, error: error)
                }
            })
        }
        mtPresentNative(picker, from: controllerRef)
    }

    let entryActions: (MTMaskStoreEntry) -> Void = { entry in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let name = entry.manifest.displayName(languageCode: MTLocalization.shared.languageCode)
        let sheet = UIAlertController(title: name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.open, style: .default, handler: { _ in
            openEditor(entry.id)
        }))
        sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.apply, style: .default, handler: { _ in
            MTMaskEngine.shared.select(.user(entry.id), account: context.account.id.mt)
        }))
        sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.rename, style: .default, handler: { _ in
            controllerRef?.present(promptController(context: context, text: MTStrings.CameraMasks.Studio.rename, value: name, placeholder: MTStrings.CameraMasks.Studio.namePlaceholder, characterLimit: 64, apply: { value in
                if let value {
                    MTMaskStore.shared.rename(id: entry.id, name: value, completion: { _ in })
                }
            }), in: .window(.root))
        }))
        sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.duplicate, style: .default, handler: { _ in
            MTMaskStore.shared.duplicate(id: entry.id, completion: { _ in })
        }))
        sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.share, style: .default, handler: { _ in
            mtShareMask(id: entry.id, controller: controllerRef)
        }))
        sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.delete, style: .destructive, handler: { _ in
            mtConfirmDeleteMask(context: context, controller: controllerRef, id: entry.id, name: name, completion: {
                MTMaskStore.shared.diskSize(completion: { size in
                    storageSize = size
                    bump()
                })
            })
        }))
        sheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
        mtPresentNative(sheet, from: controllerRef)
    }

    let controller = mtMakeListScreen(context: context, extra: extra, content: {
        var rows: [MTListRow] = []
        rows.append(MTListRow(id: "create.header", section: 0, kind: .header(MTStrings.CameraMasks.Studio.sandbox)))
        rows.append(MTListRow(id: "create", section: 0, kind: .action(title: MTStrings.CameraMasks.Studio.create, destructive: false, enabled: true), action: create))
        rows.append(MTListRow(id: "import", section: 0, kind: .action(title: MTStrings.CameraMasks.Studio.importFile, destructive: false, enabled: true), action: importMask))

        rows.append(MTListRow(id: "masks.header", section: 1, kind: .header(MTStrings.CameraMasks.Studio.myMasks)))
        if entries.isEmpty {
            rows.append(MTListRow(id: "masks.empty", section: 1, kind: .footer(MTStrings.CameraMasks.Studio.empty)))
        }
        let current = MTMaskSelection(storage: MTMaskSettings.selection.value)
        for entry in entries {
            let budget = MTMaskBudget.evaluate(entry.manifest.effects)
            let applied = current == .user(entry.id) ? " · " + MTStrings.CameraMasks.Studio.applied : ""
            let label = MTStrings.CameraMasks.Studio.layers(count: entry.manifest.effects.count) + " · " + MTStrings.CameraMasks.Studio.fps(fps: "\(budget.estimatedFps)") + applied
            rows.append(MTListRow(id: "mask." + entry.id, section: 1, kind: .disclosure(title: entry.manifest.displayName(languageCode: MTLocalization.shared.languageCode), label: label, icon: MTMaskStore.shared.thumbnail(id: entry.id).map { mtStudioIcon($0) }, enabled: true), action: {
                entryActions(entry)
            }))
        }
        var footer = MTStrings.CameraMasks.Studio.info
        if storageSize > 0 {
            footer += "\n" + MTStrings.CameraMasks.Studio.storage(size: ByteCountFormatter.string(fromByteCount: storageSize, countStyle: .file))
        }
        rows.append(MTListRow(id: "footer", section: 2, kind: .footer(footer)))
        return MTListScreenContent(title: MTStrings.CameraMasks.Studio.title, rows: rows)
    })
    controllerRef = controller
    MTMaskStore.shared.diskSize(completion: { size in
        storageSize = size
        bump()
    })
    return controller
}

private func mtStudioIcon(_ image: UIImage) -> UIImage {
    let side: CGFloat = 30.0
    let format = UIGraphicsImageRendererFormat()
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
        UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: side, height: side), cornerRadius: 7.0).addClip()
        image.draw(in: CGRect(x: 0.0, y: 0.0, width: side, height: side))
    }
}

private func mtShareMask(id: String, controller: ViewController?) {
    MTMaskStore.shared.export(id: id, completion: { url in
        guard let url else {
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        mtPresentNative(activity, from: controller)
    })
}

private func mtConfirmDeleteMask(context: AccountContext, controller: ViewController?, id: String, name: String, willDelete: @escaping () -> Void = {}, completion: @escaping () -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    controller?.present(textAlertController(context: context, title: MTStrings.CameraMasks.Studio.deleteTitle, text: name, actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .destructiveAction, title: MTStrings.CameraMasks.Studio.delete, action: {
            willDelete()
            if MTMaskSelection(storage: MTMaskSettings.selection.value) == .user(id) {
                MTMaskSettings.selection.set("")
            }
            if MTMaskSelection(storage: MTAnonymousMode.mask.value) == .user(id) {
                MTAnonymousMode.mask.reset()
            }
            MTMaskStore.shared.delete(id: id, completion: completion)
        })
    ]), in: .window(.root))
}

private func mtPresentStudioError(context: AccountContext, controller: ViewController?, error: MTMaskStoreError) {
    let text: String
    switch error {
    case .emptyName:
        text = MTStrings.CameraMasks.Studio.Error.emptyName
    case .package:
        text = MTStrings.CameraMasks.Studio.Error.package
    case let .version(version):
        text = MTStrings.CameraMasks.Studio.Error.version(version: "\(version)")
    case .read:
        text = MTStrings.CameraMasks.Studio.Error.read
    case .asset:
        text = MTStrings.CameraMasks.Studio.Error.asset
    case .notFound:
        text = MTStrings.CameraMasks.Studio.Error.notFound
    case .write:
        text = MTStrings.CameraMasks.Studio.Error.write
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    controller?.present(textAlertController(context: context, title: MTStrings.CameraMasks.Studio.Error.title, text: text, actions: [
        TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
    ]), in: .window(.root))
}

// MARK: - Editor

func mtMakeMaskEditor(context: AccountContext, maskId: String) -> ViewController? {
    guard let session = MTMaskStudioSession(maskId: maskId) else {
        return nil
    }
    weak var controllerRef: ViewController?
    let extra: Signal<Void, NoError> = combineLatest(session.changes.get(), MTMaskEngine.shared.changes.get())
    |> deliverOnMainQueue
    |> map { _, _ -> Void in
        return Void()
    }
    let languageCode = { MTLocalization.shared.languageCode }

    let layerActions: (Int) -> Void = { index in
        let manifest = session.manifest
        guard index < manifest.effects.count else {
            return
        }
        let effect = manifest.effects[index]
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = UIAlertController(title: MTMaskStudioNames.layerTitle(effect), message: nil, preferredStyle: .actionSheet)
        if effect.type == .filter {
            sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.configure, style: .default, handler: { _ in
                controllerRef?.push(mtMakeLayerParams(context: context, session: session, index: index))
            }))
        }
        sheet.addAction(UIAlertAction(title: effect.isEnabled ? MTStrings.CameraMasks.Studio.turnOff : MTStrings.CameraMasks.Studio.turnOn, style: .default, handler: { _ in
            session.update(persist: true) { manifest in
                manifest.effects[index].enabled = !effect.isEnabled
            }
        }))
        if index > 0 {
            sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.moveDown, style: .default, handler: { _ in
                session.update(persist: true) { manifest in
                    manifest.effects.swapAt(index, index - 1)
                }
            }))
        }
        if index + 1 < manifest.effects.count {
            sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.moveUp, style: .default, handler: { _ in
                session.update(persist: true) { manifest in
                    manifest.effects.swapAt(index, index + 1)
                }
            }))
        }
        sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.removeLayer, style: .destructive, handler: { _ in
            session.update(persist: true) { manifest in
                manifest.effects.remove(at: index)
            }
        }))
        sheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
        mtPresentNative(sheet, from: controllerRef)
    }

    let addFaceSwap = {
        let effect = MTFilterCatalog.descriptor("face.swapImage")?.makeEffect() ?? MTMaskEffect.filter("face.swapImage")
        guard MTMaskBudget.canAppend(effect, to: session.manifest.effects) else {
            mtStudioAlert(context: context, controller: controllerRef, title: MTStrings.CameraMasks.Filter.Face.swapImage, text: MTStrings.CameraMasks.Studio.tooHeavy)
            return
        }
        mtPickPhoto(controller: controllerRef, completion: { image in
            guard let image else {
                return
            }
            mtCropFace(image, completion: { cropped in
                guard let cropped else {
                    mtStudioAlert(context: context, controller: controllerRef, title: MTStrings.CameraMasks.Studio.noFaceTitle, text: MTStrings.CameraMasks.Studio.noFaceText)
                    return
                }
                MTMaskStore.shared.importImage(cropped, maskId: session.maskId, completion: { name in
                    guard let name else {
                        return
                    }
                    var layer = effect
                    layer.asset = name
                    session.update(persist: true) { manifest in
                        manifest.effects.append(layer)
                    }
                    controllerRef?.push(mtMakeLayerParams(context: context, session: session, index: session.manifest.effects.count - 1))
                })
            })
        })
    }

    let controller = mtMakeListScreen(context: context, extra: extra, content: {
        let manifest = session.manifest
        let budget = MTMaskBudget.evaluate(manifest.effects)
        var rows: [MTListRow] = []
        rows.append(MTListRow(id: "preview", section: 0, kind: .view(height: 340.0, key: "preview", make: {
            return session.makePreviewView()
        }, update: { _ in })))
        rows.append(MTListRow(id: "preview.hint", section: 0, kind: .footer(MTStrings.CameraMasks.Studio.previewHint)))

        rows.append(MTListRow(id: "load.header", section: 1, kind: .header(MTStrings.CameraMasks.Studio.loadSection)))
        let summary: String
        if budget.violations.contains(.overBudget) {
            summary = MTStrings.CameraMasks.Studio.budgetOver
        } else if budget.isWarning {
            summary = MTStrings.CameraMasks.Studio.budgetWarning
        } else {
            summary = MTStrings.CameraMasks.Studio.budgetOk
        }
        rows.append(MTListRow(id: "load.estimate", section: 1, kind: .disclosure(title: MTStrings.CameraMasks.Studio.estimate, label: summary + " · " + MTStrings.CameraMasks.Studio.fps(fps: "\(budget.estimatedFps)"), icon: nil, enabled: false)))
        if let fps = session.measuredFps {
            let simplified = session.isSimplified ? " · " + MTStrings.CameraMasks.Studio.simplified : ""
            rows.append(MTListRow(id: "load.measured", section: 1, kind: .disclosure(title: MTStrings.CameraMasks.Studio.measured, label: MTStrings.CameraMasks.Studio.fps(fps: "\(fps)") + simplified, icon: nil, enabled: false)))
        }
        for (index, violation) in budget.violations.enumerated() {
            rows.append(MTListRow(id: "load.violation.\(index)", section: 1, kind: .footer(MTMaskStudioNames.violation(violation))))
        }

        rows.append(MTListRow(id: "layers.header", section: 2, kind: .header(MTStrings.CameraMasks.Studio.layersSection)))
        if manifest.effects.isEmpty {
            rows.append(MTListRow(id: "layers.empty", section: 2, kind: .footer(MTStrings.CameraMasks.Studio.layersEmpty)))
        }
        for (index, effect) in manifest.effects.enumerated() {
            rows.append(MTListRow(id: "layer.\(index)", section: 2, kind: .disclosure(title: MTMaskStudioNames.layerTitle(effect), label: MTMaskStudioNames.layerSubtitle(effect), icon: nil, enabled: true), action: {
                layerActions(index)
            }))
        }
        let canAdd = manifest.effects.count < MTMaskBudget.maximumEffects
        rows.append(MTListRow(id: "layers.add", section: 2, kind: .action(title: MTStrings.CameraMasks.Studio.addLayer, destructive: false, enabled: true), action: {
            if !canAdd {
                mtStudioAlert(context: context, controller: controllerRef, title: MTStrings.CameraMasks.Studio.limitTitle, text: MTStrings.CameraMasks.Studio.limitText(count: MTMaskBudget.maximumEffects))
                return
            }
            controllerRef?.push(mtMakeFilterPicker(context: context, session: session))
        }))
        rows.append(MTListRow(id: "layers.faceSwap", section: 2, kind: .action(title: MTStrings.CameraMasks.Studio.faceSwap, destructive: false, enabled: canAdd), action: addFaceSwap))

        rows.append(MTListRow(id: "mask.header", section: 3, kind: .header(MTStrings.CameraMasks.Studio.maskSection)))
        let name = manifest.displayName(languageCode: languageCode())
        rows.append(MTListRow(id: "mask.name", section: 3, kind: .disclosure(title: MTStrings.CameraMasks.Studio.name, label: name, icon: nil, enabled: true), action: {
            controllerRef?.present(promptController(context: context, text: MTStrings.CameraMasks.Studio.rename, value: name, placeholder: MTStrings.CameraMasks.Studio.namePlaceholder, characterLimit: 64, apply: { value in
                guard let value else {
                    return
                }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return
                }
                session.update(persist: true) { manifest in
                    manifest.name[languageCode()] = trimmed
                    manifest.name["en"] = trimmed
                }
            }), in: .window(.root))
        }))
        rows.append(MTListRow(id: "mask.snapshot", section: 3, kind: .action(title: MTStrings.CameraMasks.Studio.snapshot, destructive: false, enabled: true), action: {
            if !session.hasRunningPreview {
                mtStudioAlert(context: context, controller: controllerRef, title: MTStrings.CameraMasks.Studio.snapshot, text: MTStrings.CameraMasks.Studio.snapshotNeedsCamera)
                return
            }
            session.setThumbnailFromCamera()
        }))
        let isApplied = MTMaskSelection(storage: MTMaskSettings.selection.value) == .user(maskId)
        rows.append(MTListRow(id: "mask.apply", section: 3, kind: .disclosure(title: MTStrings.CameraMasks.Studio.apply, label: isApplied ? MTStrings.CameraMasks.Studio.applied : "", icon: nil, enabled: true), action: {
            session.flush()
            MTMaskEngine.shared.select(.user(maskId), account: context.account.id.mt)
            mtStudioAlert(context: context, controller: controllerRef, title: MTStrings.CameraMasks.Studio.appliedTitle, text: MTStrings.CameraMasks.Studio.appliedText)
        }))
        rows.append(MTListRow(id: "mask.share", section: 3, kind: .action(title: MTStrings.CameraMasks.Studio.share, destructive: false, enabled: true), action: {
            session.flush()
            mtShareMask(id: maskId, controller: controllerRef)
        }))
        rows.append(MTListRow(id: "mask.duplicate", section: 3, kind: .action(title: MTStrings.CameraMasks.Studio.duplicate, destructive: false, enabled: true), action: {
            session.flush()
            MTMaskStore.shared.duplicate(id: maskId, completion: { newId in
                if let newId, let editor = mtMakeMaskEditor(context: context, maskId: newId) {
                    controllerRef?.push(editor)
                }
            })
        }))
        rows.append(MTListRow(id: "mask.delete", section: 3, kind: .action(title: MTStrings.CameraMasks.Studio.deleteMask, destructive: true, enabled: true), action: {
            mtConfirmDeleteMask(context: context, controller: controllerRef, id: maskId, name: name, willDelete: {
                session.markDeleted()
            }, completion: {
                let _ = (controllerRef?.navigationController as? NavigationController)?.popViewController(animated: true)
            })
        }))
        rows.append(MTListRow(id: "footer", section: 4, kind: .footer(MTStrings.CameraMasks.Studio.editorFooter)))
        return MTListScreenContent(title: name, rows: rows)
    })
    controller.didAppear = { _ in
        // A mask without a picture gets the first masked frame of the preview as one.
        if MTMaskStore.shared.thumbnail(id: maskId) == nil {
            session.setThumbnailFromCamera()
        }
    }
    controller.didDisappear = { _ in
        session.flush()
    }
    controllerRef = controller
    return controller
}

/// Whether a screen that just disappeared was closed (popped) rather than covered by a pushed one.
/// Telegram's navigation keeps a weak reference to the stack after a pop, so the reference itself
/// says nothing; the stack does.
private func mtWasClosed(_ controller: ViewController?) -> Bool {
    guard let controller else {
        return true
    }
    guard let navigationController = controller.navigationController as? NavigationController else {
        return true
    }
    return !navigationController.viewControllers.contains(where: { $0 === controller })
}

private func mtStudioAlert(context: AccountContext, controller: ViewController?, title: String, text: String) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    controller?.present(textAlertController(context: context, title: title, text: text, actions: [
        TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
    ]), in: .window(.root))
}

// MARK: - Filter picker

private func mtMakeFilterPicker(context: AccountContext, session: MTMaskStudioSession) -> ViewController {
    weak var controllerRef: ViewController?
    var chosenId: String?
    var committed = false
    let extra: Signal<Void, NoError> = session.changes.get() |> map { _ -> Void in return Void() }

    let controller = mtMakeListScreen(context: context, extra: extra, content: {
        var rows: [MTListRow] = []
        rows.append(MTListRow(id: "preview", section: 0, kind: .view(height: 260.0, key: "preview", make: {
            return session.makePreviewView()
        }, update: { _ in })))
        rows.append(MTListRow(id: "hint", section: 0, kind: .footer(MTStrings.CameraMasks.Studio.pickerHint)))
        var existing = session.manifest.effects
        if let index = session.provisionalIndex, index < existing.count {
            existing.remove(at: index)
        }
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        for (sectionIndex, category) in MTFilterCategory.allCases.enumerated() {
            let section = sectionIndex + 1
            rows.append(MTListRow(id: "category." + category.rawValue, section: section, kind: .header(MTMaskStudioNames.category(category))))
            for descriptor in MTFilterCatalog.descriptors(in: category) where descriptor.minimumOS <= osMajor {
                let effect = descriptor.makeEffect()
                let fits = MTMaskBudget.canAppend(effect, to: existing)
                rows.append(MTListRow(id: "filter." + descriptor.id, section: section, kind: .checkbox(title: MTMaskStudioNames.filterTitle(descriptor.id), subtitle: MTMaskStudioNames.filterSubtitle(descriptor), checked: chosenId == descriptor.id, enabled: true), action: {
                    if !fits {
                        mtStudioAlert(context: context, controller: controllerRef, title: MTMaskStudioNames.filterTitle(descriptor.id), text: MTStrings.CameraMasks.Studio.tooHeavy)
                        return
                    }
                    chosenId = descriptor.id
                    committed = false
                    session.tryOn(effect)
                }))
            }
        }
        return MTListScreenContent(title: MTStrings.CameraMasks.Studio.addLayer, rows: rows, rightButton: (MTStrings.CameraMasks.Studio.add, chosenId != nil, {
            guard let index = session.commitProvisional() else {
                return
            }
            committed = true
            chosenId = nil
            controllerRef?.push(mtMakeLayerParams(context: context, session: session, index: index))
        }))
    })
    controller.didDisappear = { [weak controller] _ in
        if !committed && mtWasClosed(controller) {
            session.discardProvisional()
        }
    }
    controllerRef = controller
    return controller
}

// MARK: - Layer parameters

private let mtPalette: [(hex: String, title: () -> String)] = [
    ("#FFFFFF", { MTStrings.CameraMasks.Palette.white }), ("#000000", { MTStrings.CameraMasks.Palette.black }),
    ("#8A8A8A", { MTStrings.CameraMasks.Palette.grey }), ("#FF3B30", { MTStrings.CameraMasks.Palette.red }),
    ("#FF8800", { MTStrings.CameraMasks.Palette.orange }), ("#FFD60A", { MTStrings.CameraMasks.Palette.yellow }),
    ("#34C759", { MTStrings.CameraMasks.Palette.green }), ("#00C7BE", { MTStrings.CameraMasks.Palette.teal }),
    ("#0A84FF", { MTStrings.CameraMasks.Palette.blue }), ("#5E5CE6", { MTStrings.CameraMasks.Palette.indigo }),
    ("#BF5AF2", { MTStrings.CameraMasks.Palette.purple }), ("#FF2D55", { MTStrings.CameraMasks.Palette.pink }),
    ("#C8304A", { MTStrings.CameraMasks.Palette.lipstick }), ("#FFDD88", { MTStrings.CameraMasks.Palette.warmLight }),
    ("#001133", { MTStrings.CameraMasks.Palette.deepBlue }), ("#0A0033", { MTStrings.CameraMasks.Palette.night })
]

private func mtMakeLayerParams(context: AccountContext, session: MTMaskStudioSession, index: Int) -> ViewController {
    weak var controllerRef: ViewController?
    let extra: Signal<Void, NoError> = session.changes.get() |> map { _ -> Void in return Void() }

    /// Changes one parameter. Ticks update the preview only; `persist` writes the mask.
    let setParam: (String, MTMaskParamValue, Bool) -> Void = { id, value, persist in
        session.update(persist: persist) { manifest in
            guard index < manifest.effects.count else {
                return
            }
            var params = manifest.effects[index].params ?? [:]
            params[id] = value
            manifest.effects[index].params = params
            if id == "anchor", let anchor = value.text.flatMap(MTMaskAnchor.init(rawValue:)) {
                manifest.effects[index].anchor = anchor
            }
        }
    }

    let controller = mtMakeListScreen(context: context, extra: extra, content: {
        let manifest = session.manifest
        var rows: [MTListRow] = []
        guard index < manifest.effects.count else {
            rows.append(MTListRow(id: "gone", section: 0, kind: .footer(MTStrings.CameraMasks.Studio.layerGone)))
            return MTListScreenContent(title: MTStrings.CameraMasks.Studio.paramsTitle, rows: rows)
        }
        let effect = manifest.effects[index]
        let theme = context.sharedContext.currentPresentationData.with { $0 }.theme
        rows.append(MTListRow(id: "preview", section: 0, kind: .view(height: 300.0, key: "preview", make: {
            return session.makePreviewView()
        }, update: { _ in })))

        guard let filterId = effect.filterId, let descriptor = MTFilterCatalog.descriptor(filterId) else {
            rows.append(MTListRow(id: "unknown", section: 1, kind: .footer(MTStrings.CameraMasks.Studio.unknownFilter)))
            rows.append(MTListRow(id: "remove", section: 1, kind: .action(title: MTStrings.CameraMasks.Studio.removeLayer, destructive: true, enabled: true), action: {
                session.update(persist: true) { manifest in
                    manifest.effects.remove(at: index)
                }
                let _ = (controllerRef?.navigationController as? NavigationController)?.popViewController(animated: true)
            }))
            return MTListScreenContent(title: MTStrings.CameraMasks.Studio.paramsTitle, rows: rows)
        }

        rows.append(MTListRow(id: "params.header", section: 1, kind: .header(MTStrings.CameraMasks.Studio.paramsSection)))
        let value: (MTFilterParam) -> MTMaskParamValue = { param in
            if let current = effect.params?[param.id], current != .unknown {
                return current
            }
            return param.defaultValue
        }
        func sliderRow(_ rowId: String, title: String, current: Double, range: ClosedRange<Double>, step: Double, apply: @escaping (Double, Bool) -> Void) -> MTListRow {
            return MTListRow(id: rowId, section: 1, kind: .view(height: MTSliderBlockView.height, key: "\(rowId)|\(current)|\(title)", make: {
                return MTSliderBlockView(frame: .zero)
            }, update: { view in
                guard let slider = view as? MTSliderBlockView else {
                    return
                }
                slider.step = step
                slider.format = { value in
                    return step >= 1.0 ? "\(Int(value))" : String(format: "%.2f", value)
                }
                slider.configure(title: title, value: current, range: range, theme: theme)
                slider.changed = { value in
                    apply(value, false)
                }
                slider.committed = { value in
                    apply(value, true)
                }
            }))
        }
        for param in descriptor.params {
            let title = MTMaskStudioNames.paramTitle(param.id)
            switch param.kind {
            case let .slider(min, max, step):
                rows.append(sliderRow("param." + param.id, title: title, current: value(param).number ?? min, range: min ... max, step: step, apply: { number, persist in
                    setParam(param.id, .number(number), persist)
                }))
            case .toggle:
                rows.append(MTListRow(id: "param." + param.id, section: 1, kind: .toggle(title: title, value: value(param).bool ?? false, enabled: true), toggled: { newValue in
                    setParam(param.id, .bool(newValue), true)
                }))
            case .color:
                let hex = value(param).text ?? "#FFFFFF"
                rows.append(MTListRow(id: "param." + param.id, section: 1, kind: .disclosure(title: title, label: hex.uppercased(), icon: mtColorSwatch(hex), enabled: true), action: {
                    mtPickColor(context: context, controller: controllerRef, title: title, current: hex, apply: { newHex in
                        setParam(param.id, .color(newHex), true)
                    })
                }))
            case .point:
                let point = value(param).point ?? CGPoint(x: 0.5, y: 0.5)
                rows.append(sliderRow("param." + param.id + ".x", title: title + " · X", current: Double(point.x), range: 0.0 ... 1.0, step: 0.01, apply: { x, persist in
                    let current = session.manifest.effects[index].params?[param.id]?.point ?? point
                    setParam(param.id, .point(CGPoint(x: x, y: Double(current.y))), persist)
                }))
                rows.append(sliderRow("param." + param.id + ".y", title: title + " · Y", current: Double(point.y), range: 0.0 ... 1.0, step: 0.01, apply: { y, persist in
                    let current = session.manifest.effects[index].params?[param.id]?.point ?? point
                    setParam(param.id, .point(CGPoint(x: Double(current.x), y: y)), persist)
                }))
            case .anchor, .blendMode:
                let options: [(value: String, title: String)] = param.kind == .anchor ? MTMaskAnchor.allCases.map { (value: $0.rawValue, title: MTMaskStudioNames.anchor($0)) } : MTMaskBlendMode.allCases.map { (value: $0.rawValue, title: MTMaskStudioNames.blendMode($0)) }
                let current = value(param).text ?? ""
                rows.append(MTListRow(id: "param." + param.id, section: 1, kind: .disclosure(title: title, label: options.first(where: { $0.value == current })?.title ?? current, icon: nil, enabled: true), action: {
                    let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
                    for option in options {
                        sheet.addAction(UIAlertAction(title: (option.value == current ? "✓ " : "") + option.title, style: .default, handler: { _ in
                            setParam(param.id, .text(option.value), true)
                        }))
                    }
                    sheet.addAction(UIAlertAction(title: context.sharedContext.currentPresentationData.with({ $0 }).strings.Common_Cancel, style: .cancel))
                    mtPresentNative(sheet, from: controllerRef)
                }))
            case .image:
                let hasImage = effect.asset != nil
                rows.append(MTListRow(id: "param.image", section: 1, kind: .disclosure(title: title, label: hasImage ? MTStrings.CameraMasks.Studio.imageChosen : MTStrings.CameraMasks.Studio.imageNone, icon: nil, enabled: true), action: {
                    mtPickPhoto(controller: controllerRef, completion: { image in
                        guard let image else {
                            return
                        }
                        let store: (UIImage) -> Void = { picked in
                            MTMaskStore.shared.importImage(picked, maskId: session.maskId, completion: { name in
                                guard let name else {
                                    return
                                }
                                session.update(persist: true) { manifest in
                                    manifest.effects[index].asset = name
                                }
                            })
                        }
                        if descriptor.id == "face.swapImage" {
                            mtCropFace(image, completion: { cropped in
                                if let cropped {
                                    store(cropped)
                                } else {
                                    mtStudioAlert(context: context, controller: controllerRef, title: MTStrings.CameraMasks.Studio.noFaceTitle, text: MTStrings.CameraMasks.Studio.noFaceText)
                                }
                            })
                        } else {
                            store(image)
                        }
                    })
                }))
                if hasImage {
                    rows.append(MTListRow(id: "param.image.clear", section: 1, kind: .action(title: MTStrings.CameraMasks.Studio.imageClear, destructive: true, enabled: true), action: {
                        session.update(persist: true) { manifest in
                            manifest.effects[index].asset = nil
                        }
                    }))
                } else {
                    rows.append(MTListRow(id: "param.image.hint", section: 1, kind: .footer(MTStrings.CameraMasks.Studio.imageNeeded)))
                }
            case .emoji:
                let current = value(param).text ?? "🙂"
                rows.append(MTListRow(id: "param." + param.id, section: 1, kind: .disclosure(title: title, label: current, icon: nil, enabled: true), action: {
                    controllerRef?.present(promptController(context: context, text: MTStrings.CameraMasks.Studio.emojiPrompt, value: current, characterLimit: 8, apply: { text in
                        guard let text else {
                            return
                        }
                        let glyph = String(text.trimmingCharacters(in: .whitespaces).prefix(2))
                        setParam(param.id, .text(glyph.isEmpty ? "🙂" : glyph), true)
                    }), in: .window(.root))
                }))
            case .curve5, .curveRGB:
                let count = param.kind == .curve5 ? 5 : 15
                var values = value(param).numbers ?? []
                if values.count != count {
                    values = (0 ..< count).map { Double($0 % 5) / 4.0 }
                }
                for i in 0 ..< count {
                    let channel: String
                    if param.kind == .curveRGB {
                        channel = [MTStrings.CameraMasks.Studio.curveRed, MTStrings.CameraMasks.Studio.curveGreen, MTStrings.CameraMasks.Studio.curveBlue][i / 5] + " · "
                    } else {
                        channel = title + " · "
                    }
                    rows.append(sliderRow("param.\(param.id).\(i)", title: channel + MTStrings.CameraMasks.Studio.curvePoint(index: "\(i % 5 + 1)"), current: values[i], range: 0.0 ... 1.0, step: 0.01, apply: { number, persist in
                        var updated = session.manifest.effects[index].params?[param.id]?.numbers ?? values
                        if updated.count != count {
                            updated = values
                        }
                        updated[i] = number
                        setParam(param.id, .numbers(updated), persist)
                    }))
                }
            }
        }
        if descriptor.param("opacity") == nil {
            rows.append(sliderRow("layer.opacity", title: MTStrings.CameraMasks.Studio.layerOpacity, current: effect.opacity ?? 1.0, range: 0.0 ... 1.0, step: 0.01, apply: { number, persist in
                session.update(persist: persist) { manifest in
                    manifest.effects[index].opacity = number >= 0.999 ? nil : number
                }
            }))
        }

        rows.append(MTListRow(id: "layer.header", section: 2, kind: .header(MTStrings.CameraMasks.Studio.layerSection)))
        rows.append(MTListRow(id: "layer.enabled", section: 2, kind: .toggle(title: MTStrings.CameraMasks.Studio.layerEnabled, value: effect.isEnabled, enabled: true), toggled: { value in
            session.update(persist: true) { manifest in
                manifest.effects[index].enabled = value ? nil : false
            }
        }))
        rows.append(MTListRow(id: "layer.reset", section: 2, kind: .action(title: MTStrings.CameraMasks.Studio.resetLayer, destructive: false, enabled: true), action: {
            session.update(persist: true) { manifest in
                var fresh = descriptor.makeEffect()
                fresh.asset = manifest.effects[index].asset
                fresh.anchor = manifest.effects[index].anchor
                manifest.effects[index] = fresh
            }
        }))
        rows.append(MTListRow(id: "layer.remove", section: 2, kind: .action(title: MTStrings.CameraMasks.Studio.removeLayer, destructive: true, enabled: true), action: {
            session.update(persist: true) { manifest in
                manifest.effects.remove(at: index)
            }
            let _ = (controllerRef?.navigationController as? NavigationController)?.popViewController(animated: true)
        }))
        rows.append(MTListRow(id: "layer.footer", section: 2, kind: .footer(MTStrings.CameraMasks.Studio.layerCost(units: "\(MTMaskBudget.cost(of: effect))") + MTMaskStudioNames.needsSuffix(MTFilterCatalog.visionNeeds(of: effect)))))
        return MTListScreenContent(title: MTMaskStudioNames.filterTitle(descriptor.id), rows: rows)
    })
    controller.didDisappear = { _ in
        session.flush()
    }
    controllerRef = controller
    return controller
}

private func mtColorSwatch(_ hex: String) -> UIImage? {
    guard let rgba = mtParseHexColor(hex) else {
        return nil
    }
    let format = UIGraphicsImageRendererFormat()
    return UIGraphicsImageRenderer(size: CGSize(width: 22.0, height: 22.0), format: format).image { _ in
        UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1.0).setFill()
        UIBezierPath(ovalIn: CGRect(x: 1.0, y: 1.0, width: 20.0, height: 20.0)).fill()
        UIColor(white: 0.5, alpha: 0.5).setStroke()
        UIBezierPath(ovalIn: CGRect(x: 1.0, y: 1.0, width: 20.0, height: 20.0)).stroke()
    }
}

private func mtPickColor(context: AccountContext, controller: ViewController?, title: String, current: String, apply: @escaping (String) -> Void) {
    let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
    for entry in mtPalette {
        sheet.addAction(UIAlertAction(title: (entry.hex.uppercased() == current.uppercased() ? "✓ " : "") + entry.title(), style: .default, handler: { _ in
            apply(entry.hex)
        }))
    }
    sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.Studio.customColor, style: .default, handler: { _ in
        controller?.present(promptController(context: context, text: MTStrings.CameraMasks.Studio.customColor, subtitle: MTStrings.CameraMasks.Studio.customColorText, value: current, characterLimit: 9, apply: { value in
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard mtParseHexColor(trimmed) != nil else {
                mtStudioAlert(context: context, controller: controller, title: MTStrings.CameraMasks.Studio.badColorTitle, text: MTStrings.CameraMasks.Studio.badColorText)
                return
            }
            apply(trimmed.hasPrefix("#") ? trimmed : "#" + trimmed)
        }), in: .window(.root))
    }))
    sheet.addAction(UIAlertAction(title: context.sharedContext.currentPresentationData.with({ $0 }).strings.Common_Cancel, style: .cancel))
    mtPresentNative(sheet, from: controller)
}

// MARK: - Pickers

private final class MTPhotoPickerBox: MTPickerDelegateBox, PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            self.onImage?(nil)
            self.releaseHandlers()
            return
        }
        provider.loadObject(ofClass: UIImage.self, completionHandler: { object, _ in
            DispatchQueue.main.async {
                self.onImage?(object as? UIImage)
                self.releaseHandlers()
            }
        })
    }
}

private final class MTDocumentPickerBox: MTPickerDelegateBox, UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.onDocument?(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.onDocument?(nil)
    }
}

private func mtPickPhoto(controller: ViewController?, completion: @escaping (UIImage?) -> Void) {
    var configuration = PHPickerConfiguration()
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    let box = MTPhotoPickerBox()
    box.onImage = completion
    box.retain()
    picker.delegate = box
    mtPresentNative(picker, from: controller)
}

/// The largest face of a photo, cropped square with room around it (the face swap's source).
private func mtCropFace(_ image: UIImage, completion: @escaping (UIImage?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let normalized = MTMaskStore.downscaled(image, maxSide: 2048.0)
        guard let cgImage = normalized.cgImage else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        guard let face = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let box = face.boundingBox
        let side = min(max(box.width * width, box.height * height) * 1.8, min(width, height))
        let center = CGPoint(x: box.midX * width, y: (1.0 - box.midY) * height)
        var rect = CGRect(x: center.x - side / 2.0, y: center.y - side / 2.0, width: side, height: side)
        rect.origin.x = max(0.0, min(width - side, rect.origin.x))
        rect.origin.y = max(0.0, min(height - side, rect.origin.y))
        let cropped = cgImage.cropping(to: rect.integral).map { UIImage(cgImage: $0) }
        DispatchQueue.main.async {
            completion(cropped)
        }
    }
}
