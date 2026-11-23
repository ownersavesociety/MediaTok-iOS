import Foundation
import PresentationDataUtils
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AppBundle
import MTCore

/// «Наборы иконок»: installed packs (enable, priority, edit, share, delete), import of `.icons`
/// files, a new pack and its editor. Enabling or disabling applies at once.
enum MTIconPackScreens {
    static func makeListScreen(context: AccountContext) -> ViewController {
        weak var controllerRef: ViewController?
        let box = MTIconPackListBox()
        let update = MTIconPackStorage.shared.packs
        |> deliverOnMainQueue
        |> map { packs -> Void in
            box.packs = packs
            return Void()
        }
        let actions = MTListActions(select: { id in
            switch id {
            case "import":
                MTIconPackScreens.importPack(context: context, from: controllerRef)
            case "create":
                MTIconPackScreens.createPack(context: context, from: controllerRef)
            default:
                if let pack = box.packs.first(where: { $0.id == id }) {
                    MTIconPackScreens.presentPackActions(pack, context: context, from: controllerRef)
                }
            }
        })
        let controller = mtMakeInterfaceList(context: context, title: { MTStrings.Interface.IconPacks.title }, update: update, sections: { _ in
            let enabled = InterfaceSettings.iconPacks.value
            var rows: [MTListRow] = [.header(MTStrings.Interface.IconPacks.listHeader)]
            // Enabled packs first, in priority order, then the rest.
            let ordered = enabled.compactMap { id in box.packs.first(where: { $0.id == id }) } + box.packs.filter { !enabled.contains($0.id) }
            for pack in ordered {
                var subtitle = MTStrings.Interface.IconPacks.iconCount(count: pack.coveredAssetCount)
                if !pack.author.isEmpty {
                    subtitle = pack.author + " · " + subtitle
                }
                rows.append(.check(id: pack.id, title: pack.name, subtitle: subtitle, checked: enabled.contains(pack.id)))
            }
            if box.packs.isEmpty {
                rows.append(.footer(MTStrings.Interface.IconPacks.empty))
            } else {
                rows.append(.footer(MTStrings.Interface.IconPacks.listFooter))
            }
            return [
                MTListSection(rows),
                MTListSection([
                    .action(id: "import", title: MTStrings.Interface.IconPacks.importPack, isDestructive: false),
                    .action(id: "create", title: MTStrings.Interface.IconPacks.createPack, isDestructive: false)
                ])
            ]
        }, actions: actions)
        controllerRef = controller
        return controller
    }

    private static func presentPackActions(_ pack: MTIconPack, context: AccountContext, from controller: ViewController?) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var enabled = InterfaceSettings.iconPacks.value
        var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
        if let index = enabled.firstIndex(of: pack.id) {
            buttons.append((MTStrings.Interface.IconPacks.disable, false, {
                enabled.remove(at: index)
                InterfaceSettings.iconPacks.set(enabled)
            }))
            if let moved = mtMoved(enabled, index: index, by: -1) {
                buttons.append((MTStrings.Interface.IconPacks.raisePriority, false, {
                    InterfaceSettings.iconPacks.set(moved)
                }))
            }
            if let moved = mtMoved(enabled, index: index, by: 1) {
                buttons.append((MTStrings.Interface.IconPacks.lowerPriority, false, {
                    InterfaceSettings.iconPacks.set(moved)
                }))
            }
        } else {
            buttons.append((MTStrings.Interface.IconPacks.enable, false, {
                enabled.append(pack.id)
                InterfaceSettings.iconPacks.set(enabled)
            }))
        }
        buttons.append((MTStrings.Interface.IconPacks.edit, false, {
            (controller?.navigationController as? NavigationController)?.pushViewController(MTIconPackScreens.makeEditor(context: context, packId: pack.id))
        }))
        buttons.append((MTStrings.Interface.IconPacks.share, false, {
            let _ = (MTIconPackStorage.shared.export(pack)
            |> deliverOnMainQueue).start(next: { url in
                mtPresentNative(UIActivityViewController(activityItems: [url], applicationActivities: nil), from: controller)
            }, error: { error in
                MTIconPackScreens.showError(error.text, context: context, from: controller)
            })
        }))
        buttons.append((presentationData.strings.Common_Delete, true, {
            mtConfirmDestructive(context: context, from: controller, title: MTStrings.Interface.IconPacks.deleteTitle, text: MTStrings.Interface.IconPacks.deleteText(name: pack.name), confirm: presentationData.strings.Common_Delete, action: {
                InterfaceSettings.iconPacks.set(InterfaceSettings.iconPacks.value.filter { $0 != pack.id })
                let _ = MTIconPackStorage.shared.delete(pack).start()
            })
        }))
        mtPresentActionSheet(context: context, from: controller, title: pack.name, buttons: buttons)
    }

    private static func importPack(context: AccountContext, from controller: ViewController?) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        let delegate = MTBadgeDocumentPickerDelegate(completion: { url in
            MTIconPackScreens.install(archive: url, context: context, from: controller, confirm: false)
        })
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &mtIconPackPickerKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        mtPresentNative(picker, from: controller)
    }

    /// Checks an `.icons` archive, optionally asks (a file tapped in a chat), installs and enables it
    /// as the top pack.
    static func install(archive url: URL, context: AccountContext, from controller: ViewController?, confirm: Bool) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let finish: (MTIconPack) -> Void = { inspected in
            let _ = (MTIconPackStorage.shared.install(inspected)
            |> deliverOnMainQueue).start(next: { pack in
                var enabled = InterfaceSettings.iconPacks.value
                if !enabled.contains(pack.id) {
                    enabled.insert(pack.id, at: 0)
                    InterfaceSettings.iconPacks.set(enabled)
                }
                controller?.present(mtToast(context: context, text: MTStrings.Interface.IconPacks.installed(name: pack.name)), in: .window(.root))
            }, error: { error in
                MTIconPackScreens.showError(error.text, context: context, from: controller)
            })
        }
        let _ = (MTIconPackStorage.shared.inspect(archive: url)
        |> deliverOnMainQueue).start(next: { inspected in
            if !confirm {
                finish(inspected)
                return
            }
            var text = MTStrings.Interface.IconPacks.iconCount(count: inspected.coveredAssetCount)
            if !inspected.author.isEmpty {
                text = inspected.author + " · " + text
            }
            controller?.present(textAlertController(context: context, title: MTStrings.Interface.IconPacks.installTitle(name: inspected.name), text: text, actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                    try? FileManager.default.removeItem(atPath: inspected.directory)
                }),
                TextAlertAction(type: .defaultAction, title: MTStrings.Interface.IconPacks.install, action: {
                    finish(inspected)
                })
            ]), in: .window(.root))
        }, error: { error in
            MTIconPackScreens.showError(error.text, context: context, from: controller)
        })
    }

    private static func createPack(context: AccountContext, from controller: ViewController?) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        mtPresentTextPrompt(context: context, from: controller, title: MTStrings.Interface.IconPacks.namePrompt, text: "", placeholder: MTStrings.Interface.IconPacks.defaultName, cancel: presentationData.strings.Common_Cancel, done: presentationData.strings.Common_Done, completion: { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let _ = (MTIconPackStorage.shared.create(name: trimmed.isEmpty ? MTStrings.Interface.IconPacks.defaultName : trimmed, author: "")
            |> deliverOnMainQueue).start(next: { pack in
                (controller?.navigationController as? NavigationController)?.pushViewController(MTIconPackScreens.makeEditor(context: context, packId: pack.id))
            }, error: { error in
                MTIconPackScreens.showError(error.text, context: context, from: controller)
            })
        })
    }

    private static func showError(_ text: String, context: AccountContext, from controller: ViewController?) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }

    // MARK: Editor

    /// Every iOS asset a pack can replace, by its short name. Pictures are read and decoded off the
    /// main thread, once per file, and kept for the screen's lifetime; the rows get them when ready.
    static func makeEditor(context: AccountContext, packId: String) -> ViewController {
        weak var controllerRef: ViewController?
        let box = MTIconPackEditorBox()
        let assets = MTIconPackMapTable.androidNamesByAsset.keys.filter { asset in
            return MTIconPackScreens.androidName(for: asset) != nil
        }.sorted()
        let update = MTIconPackStorage.shared.packs
        |> deliverOnMainQueue
        |> mapToSignal { packs -> Signal<Void, NoError> in
            let pack = packs.first(where: { $0.id == packId })
            box.pack = pack
            guard let pack else {
                return .single(Void())
            }
            let missing = box.missingPreviews(assets: assets, pack: pack)
            if missing.isEmpty {
                return .single(Void())
            }
            return .single(Void())
            |> then(MTIconPackEditorBox.renderPreviews(missing)
            |> runOn(mtInterfaceQueue)
            |> deliverOnMainQueue
            |> map { previews -> Void in
                box.add(previews)
                return Void()
            })
        }

        let actions = MTListActions(select: { id in
            guard let pack = box.pack else {
                return
            }
            if id == "rename" {
                MTIconPackScreens.renamePack(pack, context: context, from: controllerRef)
                return
            }
            MTIconPackScreens.presentIconActions(asset: id, pack: pack, context: context, from: controllerRef)
        })
        let controller = mtMakeInterfaceList(context: context, title: { box.pack?.name ?? MTStrings.Interface.IconPacks.title }, update: update, sections: { _ in
            guard let pack = box.pack else {
                return []
            }
            var rows: [MTListRow] = [.header(MTStrings.Interface.IconPacks.editorHeader)]
            for asset in assets {
                guard let androidName = MTIconPackScreens.androidName(for: asset) else {
                    continue
                }
                let isCustom = pack.icons[androidName] != nil
                rows.append(.disclosure(id: asset, title: MTIconPackScreens.shortName(asset), label: isCustom ? MTStrings.Interface.IconPacks.customLabel : "", icon: box.image(asset: asset, pack: pack)))
            }
            rows.append(.footer(MTStrings.Interface.IconPacks.editorFooter))
            return [
                MTListSection([.action(id: "rename", title: MTStrings.Interface.IconPacks.renamePack, isDestructive: false)]),
                MTListSection(rows)
            ]
        }, actions: actions)
        controllerRef = controller
        return controller
    }

    /// The Android name a new picture is stored under for an asset (the first one not blacklisted).
    static func androidName(for asset: String) -> String? {
        return MTIconPackMapTable.androidNamesByAsset[asset]?.first(where: { !MTIconPackMapTable.blacklist.contains($0) })
    }

    private static func shortName(_ asset: String) -> String {
        let parts = asset.split(separator: "/")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: " › ")
        }
        return asset
    }

    private static func renamePack(_ pack: MTIconPack, context: AccountContext, from controller: ViewController?) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        mtPresentTextPrompt(context: context, from: controller, title: MTStrings.Interface.IconPacks.namePrompt, text: pack.name, placeholder: MTStrings.Interface.IconPacks.defaultName, cancel: presentationData.strings.Common_Cancel, done: presentationData.strings.Common_Done, completion: { text in
            let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
            if trimmed.isEmpty {
                return
            }
            var updated = pack
            updated.name = trimmed
            let _ = MTIconPackStorage.shared.update(updated).start()
        })
    }

    private static func presentIconActions(asset: String, pack: MTIconPack, context: AccountContext, from controller: ViewController?) {
        guard let androidName = MTIconPackScreens.androidName(for: asset) else {
            return
        }
        // The picture is read and decoded on `mtInterfaceQueue`, only as large as an icon is stored
        // (`load` runs there); nothing from outside is decoded whole or on the main thread.
        let apply: (@escaping () -> UIImage?) -> Void = { load in
            mtInterfaceQueue.async {
                guard let image = load() else {
                    return
                }
                let _ = (MTIconPackStorage.shared.setIcon(image, androidName: androidName, in: pack)
                |> deliverOnMainQueue).start(error: { error in
                    MTIconPackScreens.showError(error.text, context: context, from: controller)
                })
            }
        }
        let maxPixelSize = Int(MTIconPackScreens.iconMaxSide)
        var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
        buttons.append((MTStrings.Interface.IconPacks.fromPhotos, false, {
            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            configuration.selectionLimit = 1
            let picker = PHPickerViewController(configuration: configuration)
            let delegate = MTPhotoThumbnailPickerDelegate(maxPixelSize: maxPixelSize, completion: { image in
                apply({ image })
            })
            picker.delegate = delegate
            objc_setAssociatedObject(picker, &mtIconPackPickerKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            mtPresentNative(picker, from: controller)
        }))
        buttons.append((MTStrings.Interface.IconPacks.fromFiles, false, {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
            let delegate = MTBadgeDocumentPickerDelegate(completion: { url in
                apply({
                    return MTImageDecoding.thumbnail(url: url, maxPixelSize: maxPixelSize, maxSourcePixels: MTImageDecoding.maxPictureSourcePixels)
                })
            })
            picker.delegate = delegate
            objc_setAssociatedObject(picker, &mtIconPackPickerKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            mtPresentNative(picker, from: controller)
        }))
        if UIPasteboard.general.hasImages {
            buttons.append((MTStrings.Interface.IconPacks.paste, false, {
                // The pasteboard's bytes when it has them (decoded as a thumbnail), its image otherwise.
                let data = MTIconPackScreens.pasteboardImageData()
                let image = data == nil ? UIPasteboard.general.image : nil
                apply({
                    if let data {
                        return MTImageDecoding.thumbnail(data: data, maxPixelSize: maxPixelSize, maxSourcePixels: MTImageDecoding.maxPictureSourcePixels)
                    }
                    return image.map(MTIconPackScreens.normalizedIcon)
                })
            }))
        }
        if pack.icons[androidName] != nil {
            buttons.append((MTStrings.Interface.IconPacks.resetIcon, true, {
                let _ = MTIconPackStorage.shared.resetIcon(androidName: androidName, in: pack).start()
            }))
        }
        mtPresentActionSheet(context: context, from: controller, title: MTIconPackScreens.shortName(asset), buttons: buttons)
    }

    /// Icons are stored at most 192 px on the long side (a 3x tab icon is 90 px).
    private static let iconMaxSide: CGFloat = 192.0

    /// The first image the pasteboard holds as bytes. Main thread.
    private static func pasteboardImageData() -> Data? {
        for type in UIPasteboard.general.types {
            if let uti = UTType(type), uti.conforms(to: .image), let data = UIPasteboard.general.data(forPasteboardType: type) {
                return data
            }
        }
        return nil
    }

    /// An image that came without bytes, at most `iconMaxSide` (off the main thread).
    private static func normalizedIcon(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = MTIconPackScreens.iconMaxSide
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        if longest <= maxSide {
            return image
        }
        let factor = maxSide / longest
        let size = CGSize(width: floor(pixelSize.width * factor), height: floor(pixelSize.height * factor))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: CGPoint(), size: size))
        }
    }
}

private var mtIconPackPickerKey: UInt8 = 0

private final class MTIconPackListBox {
    var packs: [MTIconPack] = []
}

private final class MTIconPackEditorBox {
    /// What a row's preview is made from: a file of the pack or Telegram's own asset.
    struct PreviewSource {
        let key: String
        let asset: String
        /// The pack and the Android name of its file; nil = Telegram's asset.
        let packFile: (pack: MTIconPack, androidName: String)?
    }

    private static let previewSide: CGFloat = 24.0

    var pack: MTIconPack?
    private var images: [String: UIImage] = [:]

    private static func key(asset: String, pack: MTIconPack) -> String {
        if let androidName = MTIconPackScreens.androidName(for: asset), let fileName = pack.icons[androidName] {
            return "pack|" + fileName
        }
        return "stock|" + asset
    }

    /// 24 pt preview of an asset: the pack's picture if it has one, else Telegram's glyph. Only what
    /// was already made (main thread, no disk); nil until `renderPreviews` delivered it.
    func image(asset: String, pack: MTIconPack) -> UIImage? {
        return self.images[MTIconPackEditorBox.key(asset: asset, pack: pack)]
    }

    /// Rows whose preview is not made yet. Main thread.
    func missingPreviews(assets: [String], pack: MTIconPack) -> [PreviewSource] {
        var result: [PreviewSource] = []
        var seen = Set<String>()
        for asset in assets {
            let key = MTIconPackEditorBox.key(asset: asset, pack: pack)
            if self.images[key] != nil || seen.contains(key) {
                continue
            }
            seen.insert(key)
            var packFile: (pack: MTIconPack, androidName: String)?
            if key.hasPrefix("pack|"), let androidName = MTIconPackScreens.androidName(for: asset) {
                packFile = (pack, androidName)
            }
            result.append(PreviewSource(key: key, asset: asset, packFile: packFile))
        }
        return result
    }

    func add(_ previews: [String: UIImage]) {
        for (key, image) in previews {
            self.images[key] = image
        }
    }

    /// Reads and draws the previews (run it on `mtInterfaceQueue`): a pack's file decoded only as a
    /// 24 pt thumbnail, never whole.
    static func renderPreviews(_ sources: [PreviewSource]) -> Signal<[String: UIImage], NoError> {
        return Signal { subscriber in
            let side = MTIconPackEditorBox.previewSide
            let maxPixelSize = Int(ceil(side * 3.0))
            var result: [String: UIImage] = [:]
            for source in sources {
                let image: UIImage?
                if let packFile = source.packFile {
                    image = packFile.pack.fileURL(androidName: packFile.androidName).flatMap { url in
                        return MTImageDecoding.thumbnail(url: url, maxPixelSize: maxPixelSize, maxSourcePixels: MTImageDecoding.maxIconSourcePixels)
                    }
                } else {
                    image = UIImage(named: source.asset, in: getAppBundle(), compatibleWith: nil)
                }
                guard let image else {
                    continue
                }
                let preview = generateImage(CGSize(width: side, height: side), rotatedContext: { size, context in
                    context.clear(CGRect(origin: CGPoint(), size: size))
                    let scale = min(size.width / max(1.0, image.size.width), size.height / max(1.0, image.size.height))
                    let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    UIGraphicsPushContext(context)
                    image.draw(in: CGRect(origin: CGPoint(x: (size.width - drawSize.width) * 0.5, y: (size.height - drawSize.height) * 0.5), size: drawSize))
                    UIGraphicsPopContext()
                })
                if let preview {
                    result[source.key] = preview
                }
            }
            subscriber.putNext(result)
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}
