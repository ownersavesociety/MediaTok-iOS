import Foundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ItemListUI
import PresentationDataUtils
import PromptUI
import MTCore

/// What the library screen shows between rebuilds: thumbnails load once per item, off the main
/// thread.
private final class MTVirtualCameraScreenState {
    var thumbnails: [String: UIImage] = [:]
    var requested = Set<String>()
    let disposables = DisposableSet()

    deinit {
        self.disposables.dispose()
    }
}

/// «Медиатека»: pictures, GIFs and videos that a call can show instead of the camera. Files stay
/// on this device (the list is not exported with the settings); nothing here reaches the network.
func mtMakeVirtualCameraScreen(context: AccountContext) -> ViewController {
    let state = MTVirtualCameraScreenState()
    weak var controllerRef: ViewController?
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshValue = 0
    let bump = {
        refreshValue += 1
        refresh.set(refreshValue)
    }
    let extra: Signal<Void, NoError> = combineLatest(MTVirtualCameraSettings.items.signal, MTVirtualCameraSettings.selected.signal, refresh.get())
    |> deliverOnMainQueue
    |> map { _, _, _ -> Void in
        return Void()
    }

    let loadThumbnails: ([MTVirtualCameraItem]) -> Void = { items in
        for item in items where !state.requested.contains(item.id) {
            state.requested.insert(item.id)
            state.disposables.add((MTVirtualCameraLibrary.thumbnail(item) |> deliverOnMainQueue).start(next: { image in
                guard let image else {
                    return
                }
                state.thumbnails[item.id] = mtVirtualCameraIcon(image)
                bump()
            }))
        }
    }

    let failed = {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controllerRef?.present(textAlertController(context: context, title: MTStrings.CameraMasks.VirtualCamera.addFailedTitle, text: MTStrings.CameraMasks.VirtualCamera.addFailedText, actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]), in: .window(.root))
    }

    let added: (MTVirtualCameraItem?) -> Void = { item in
        guard let item else {
            failed()
            return
        }
        // A first item is chosen at once: the library exists to be used.
        if MTVirtualCameraSettings.selected.value.isEmpty {
            MTVirtualCameraSettings.selected.set(item.id)
        }
    }

    let addFromPhotos = {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        let box = MTVirtualCameraPickerBox()
        box.retain()
        box.onResult = { provider in
            guard let provider else {
                box.releaseHandlers()
                return
            }
            mtImportVirtualCameraItem(provider, title: MTStrings.CameraMasks.VirtualCamera.defaultTitle(index: "\(MTVirtualCameraSettings.items.value.count + 1)"), completion: { item in
                box.releaseHandlers()
                added(item)
            })
        }
        picker.delegate = box
        mtPresentNative(picker, from: controllerRef)
    }

    let addFromFiles = {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.image, UTType.gif, UTType.movie], asCopy: true)
        picker.allowsMultipleSelection = false
        let box = MTVirtualCameraPickerBox()
        box.retain()
        box.onDocument = { url in
            guard let url else {
                box.releaseHandlers()
                return
            }
            let fileTitle = url.deletingPathExtension().lastPathComponent
            let title = fileTitle.isEmpty ? MTStrings.CameraMasks.VirtualCamera.defaultTitle(index: "\(MTVirtualCameraSettings.items.value.count + 1)") : fileTitle
            DispatchQueue.global(qos: .userInitiated).async {
                MTVirtualCameraLibrary.importFile(at: url, title: title, completion: { item in
                    try? FileManager.default.removeItem(at: url)
                    box.releaseHandlers()
                    added(item)
                })
            }
        }
        picker.delegate = box
        mtPresentNative(picker, from: controllerRef)
    }

    let itemActions: (MTVirtualCameraItem) -> Void = { item in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = UIAlertController(title: item.title, message: nil, preferredStyle: .actionSheet)
        if MTVirtualCameraSettings.selected.value != item.id {
            sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.VirtualCamera.choose, style: .default, handler: { _ in
                MTVirtualCameraSettings.selected.set(item.id)
            }))
        }
        sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.VirtualCamera.rename, style: .default, handler: { _ in
            controllerRef?.present(promptController(context: context, text: MTStrings.CameraMasks.VirtualCamera.rename, value: item.title, characterLimit: 64, apply: { value in
                guard let value else {
                    return
                }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    MTVirtualCameraLibrary.rename(id: item.id, title: trimmed)
                }
            }), in: .window(.root))
        }))
        sheet.addAction(UIAlertAction(title: MTStrings.CameraMasks.VirtualCamera.delete, style: .destructive, handler: { _ in
            MTVirtualCameraLibrary.remove(id: item.id)
            state.thumbnails[item.id] = nil
            state.requested.remove(item.id)
        }))
        sheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
        mtPresentNative(sheet, from: controllerRef)
    }

    let controller = mtMakeListScreen(context: context, extra: extra, content: {
        let items = MTVirtualCameraSettings.items.value
        let selected = MTVirtualCameraSettings.selected.value
        loadThumbnails(items)
        var rows: [MTListRow] = []
        if !MTVirtualCameraSettings.enabled.value {
            rows.append(MTListRow(id: "off", section: 0, kind: .footer(MTStrings.CameraMasks.VirtualCamera.disabledHint)))
        }
        rows.append(MTListRow(id: "items.header", section: 1, kind: .header(MTStrings.CameraMasks.VirtualCamera.itemsSection)))
        rows.append(MTListRow(id: "none", section: 1, kind: .checkbox(title: MTStrings.CameraMasks.VirtualCamera.realCamera, subtitle: nil, checked: selected.isEmpty || !items.contains(where: { $0.id == selected }), enabled: true), action: {
            MTVirtualCameraSettings.selected.set("")
        }))
        for item in items {
            let kind: String
            switch item.kind {
            case .image:
                kind = MTStrings.CameraMasks.VirtualCamera.kindImage
            case .gif:
                kind = MTStrings.CameraMasks.VirtualCamera.kindGif
            case .video:
                kind = MTStrings.CameraMasks.VirtualCamera.kindVideo
            }
            let label = item.id == selected ? MTStrings.CameraMasks.VirtualCamera.selected : kind
            rows.append(MTListRow(id: "item." + item.id, section: 1, kind: .disclosure(title: item.title, label: label, icon: state.thumbnails[item.id], enabled: true), action: {
                itemActions(item)
            }))
        }
        rows.append(MTListRow(id: "add.photos", section: 2, kind: .action(title: MTStrings.CameraMasks.VirtualCamera.addFromPhotos, destructive: false, enabled: true), action: addFromPhotos))
        rows.append(MTListRow(id: "add.files", section: 2, kind: .action(title: MTStrings.CameraMasks.VirtualCamera.addFromFiles, destructive: false, enabled: true), action: addFromFiles))
        rows.append(MTListRow(id: "footer", section: 2, kind: .footer(MTStrings.CameraMasks.VirtualCamera.footer)))
        return MTListScreenContent(title: MTStrings.CameraMasks.VirtualCamera.library, rows: rows)
    })
    controllerRef = controller
    return controller
}

private func mtVirtualCameraIcon(_ image: UIImage) -> UIImage {
    let side: CGFloat = 30.0
    let format = UIGraphicsImageRendererFormat()
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
        UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: side, height: side), cornerRadius: 7.0).addClip()
        let size = image.size
        let scale = max(side / max(size.width, 1.0), side / max(size.height, 1.0))
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        image.draw(in: CGRect(x: (side - drawn.width) / 2.0, y: (side - drawn.height) / 2.0, width: drawn.width, height: drawn.height))
    }
}

private final class MTVirtualCameraPickerBox: MTPickerDelegateBox, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    var onResult: ((NSItemProvider?) -> Void)?

    override func releaseHandlers() {
        super.releaseHandlers()
        self.onResult = nil
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        self.onResult?(results.first?.itemProvider)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.onDocument?(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.onDocument?(nil)
    }
}

/// Copies what the photo picker returned into the library: a GIF keeps its frames, a video is
/// copied as a file (never read into memory), a still image keeps its own format.
private func mtImportVirtualCameraItem(_ provider: NSItemProvider, title: String, completion: @escaping (MTVirtualCameraItem?) -> Void) {
    let type: UTType
    if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
        type = .gif
    } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        type = .movie
    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        type = .image
    } else {
        DispatchQueue.main.async {
            completion(nil)
        }
        return
    }
    let _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier, completionHandler: { url, _ in
        // The file is removed when this handler returns, so it is copied here, synchronously.
        guard let url else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        MTVirtualCameraLibrary.importFile(at: url, title: title, completion: completion)
    })
}
