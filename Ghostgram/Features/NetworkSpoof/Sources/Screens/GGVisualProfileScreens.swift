import Foundation
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import ImageIO
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatListUI
import ContextUI
import AppBundle
import GGCore
import GGHooks

private let ggVisualMaxAvatarDimension: Int = 3840

private final class GGVisualPhotoPickerBox: NSObject, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private var retainedSelf: GGVisualPhotoPickerBox?
    private let completion: (Data, Data?, Int, Int) -> Void

    init(completion: @escaping (Data, Data?, Int, Int) -> Void) {
        self.completion = completion
        super.init()
    }

    func retainCycle() {
        self.retainedSelf = self
    }

    private func finish() {
        self.retainedSelf = nil
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            self.finish()
            return
        }
        let completion = self.completion
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url,
                      let videoData = try? Data(contentsOf: url),
                      !videoData.isEmpty else {
                    DispatchQueue.main.async {
                        self.finish()
                    }
                    return
                }
                let encodedCover = ggVisualExtractVideoCover4k(from: url)
                DispatchQueue.main.async {
                    if let (coverData, width, height) = encodedCover {
                        completion(coverData, videoData, width, height)
                    }
                    self.finish()
                }
            }
            return
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            self.finish()
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            guard let url else {
                DispatchQueue.main.async {
                    self.finish()
                }
                return
            }
            let encoded = ggVisualEncode4kAvatar(from: url)
            DispatchQueue.main.async {
                if let (data, width, height) = encoded {
                    completion(data, nil, width, height)
                }
                self.finish()
            }
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.finish()
    }
}

private func ggVisualExtractVideoCover4k(from url: URL) -> (Data, Int, Int)? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: CGFloat(ggVisualMaxAvatarDimension), height: CGFloat(ggVisualMaxAvatarDimension))
    guard let cgImage = (try? generator.copyCGImage(at: .zero, actualTime: nil))
            ?? (try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)) else {
        return nil
    }
    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
        return nil
    }
    let destOptions: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.94
    ]
    CGImageDestinationAddImage(destination, cgImage, destOptions as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        return nil
    }
    return (mutableData as Data, cgImage.width, cgImage.height)
}

private func ggVisualEncode4kAvatar(from url: URL) -> (Data, Int, Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }
    let thumbOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: ggVisualMaxAvatarDimension
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
        return nil
    }
    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
        return nil
    }
    let destOptions: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.94
    ]
    CGImageDestinationAddImage(destination, cgImage, destOptions as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        return nil
    }
    return (mutableData as Data, cgImage.width, cgImage.height)
}

private func ggPresentVisualPhotoPicker(from controller: ViewController?, completion: @escaping (Data, Data?, Int, Int) -> Void) {
    guard let host = controller?.view.window?.rootViewController ?? controller else {
        return
    }
    var topVC = host
    while let presented = topVC.presentedViewController {
        topVC = presented
    }
    var configuration = PHPickerConfiguration()
    configuration.selectionLimit = 1
    configuration.filter = .any(of: [.images, .videos])
    let picker = PHPickerViewController(configuration: configuration)
    let box = GGVisualPhotoPickerBox(completion: completion)
    box.retainCycle()
    picker.delegate = box
    picker.presentationController?.delegate = box
    topVC.present(picker, animated: true)
}

enum GGVisualProfileSupport {
    static func registerHooks() {
        GGPeerInfoHooks.displayedPhoneNumber.register({ request in
            if let visPhone = GGVisualProfileStore.shared.phone(for: request.peerId.ggKey) {
                return .replaced(visPhone)
            }
            return nil
        }, order: -200)

        GGPeerInfoHooks.menuItems.register({ peerInfo in
            let targetPeer = peerInfo.chatPeer ?? peerInfo.peer
            let peerId = targetPeer.id
            let context = peerInfo.context
            weak let weakController = peerInfo.controller
            return [
                .action(ContextMenuActionItem(
                    text: GGStrings.NetworkSpoof.Visual.menuItem,
                    icon: { theme in
                        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.contextMenu.primaryColor)
                    },
                    action: { _, f in
                        f(.dismissWithoutContent)
                        let editor = ggSpoofMakeVisualEditorController(context: context, peerId: peerId)
                        if let nav = weakController?.navigationController as? NavigationController {
                            nav.pushViewController(editor)
                        } else if let nav = context.sharedContext.mainWindow?.viewController as? NavigationController {
                            nav.pushViewController(editor)
                        }
                    }
                ))
            ]
        })

        GGChatListHooks.accessoryPeers.register({ _ in
            return GGVisualProfileStore.shared.revisionSignal
            |> map { _ -> Set<EnginePeer.Id> in
                return Set(GGVisualProfileStore.shared.trackedPeerKeys.map { PeerId(ggKey: $0) })
            }
        })
    }
}

private func ggVisualBadgeTitle(_ mode: GGVisualBadgeMode) -> String {
    switch mode {
    case .default:
        return GGStrings.NetworkSpoof.Visual.badgeDefault
    case .verified:
        return GGStrings.NetworkSpoof.Visual.badgeVerified
    case .premium:
        return GGStrings.NetworkSpoof.Visual.badgePremium
    case .scam:
        return GGStrings.NetworkSpoof.Visual.badgeScam
    case .fake:
        return GGStrings.NetworkSpoof.Visual.badgeFake
    case .hide:
        return GGStrings.NetworkSpoof.Visual.badgeHide
    }
}

func ggSpoofMakeVisualListController(context: AccountContext) -> ViewController {
    weak var weakController: ViewController?
    let push: (ViewController) -> Void = { screen in
        if let nav = weakController?.navigationController as? NavigationController {
            nav.pushViewController(screen)
        } else if let nav = context.sharedContext.mainWindow?.viewController as? NavigationController {
            nav.pushViewController(screen)
        }
    }

    let peersSignal = GGVisualProfileStore.shared.revisionSignal
    |> mapToSignal { _ -> Signal<(EnginePeer?, [EnginePeer.Id: EnginePeer], [(key: GGPeerKey, value: GGVisualPeerOverride)]), NoError> in
        let entries = GGVisualProfileStore.shared.allOverrides()
        var ids = Set<EnginePeer.Id>()
        ids.insert(context.account.peerId)
        for item in entries {
            ids.insert(PeerId(ggKey: item.key))
        }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { mapResult -> (EnginePeer?, [EnginePeer.Id: EnginePeer], [(key: GGPeerKey, value: GGVisualPeerOverride)]) in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in mapResult {
                if let peer {
                    peers[id] = peer
                }
            }
            return (peers[context.account.peerId], peers, entries)
        }
    }

    let model = combineLatest(queue: .mainQueue(), peersSignal, GGLocalization.shared.languageCodeSignal)
    |> map { peersBundle, _ -> GGSpoofScreenModel in
        let (_, peers, _) = peersBundle
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var model = GGSpoofScreenModel(title: GGStrings.NetworkSpoof.Visual.tabTitle)

        model.sections.append([
            GGSpoofRow(id: "self", kind: .disclosure(title: GGStrings.NetworkSpoof.Visual.editSelf, label: "")),
            GGSpoofRow(id: "pick", kind: .action(title: GGStrings.NetworkSpoof.Visual.pickPeer, destructive: false, enabled: true)),
            GGSpoofRow(id: "footer", kind: .footer(GGStrings.NetworkSpoof.Visual.listFooter))
        ])
        model.tap["self"] = {
            push(ggSpoofMakeVisualEditorController(context: context, peerId: context.account.peerId))
        }
        model.tap["pick"] = {
            let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: [.excludeSavedMessages, .excludeSecretChats, .doNotSearchMessages],
                hasContactSelector: false,
                title: GGStrings.NetworkSpoof.Visual.pickPeer
            ))
            picker.peerSelected = { [weak picker] peer, _ in
                picker?.dismiss()
                push(ggSpoofMakeVisualEditorController(context: context, peerId: peer.id))
            }
            push(picker)
        }

        let configured = GGVisualProfileStore.shared.allOverrides()
        if !configured.isEmpty {
            var rows: [GGSpoofRow] = [GGSpoofRow(id: "configured.header", kind: .header(GGStrings.NetworkSpoof.Visual.listHeader))]
            for entry in configured {
                let peerId = PeerId(ggKey: entry.key)
                let origTitle = peers[peerId]?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? GGStrings.NetworkSpoof.Profiles.unknownPeer
                let label = !entry.value.name.isEmpty ? entry.value.name : origTitle
                let rowId = "peer.\(entry.key.stringValue)"
                rows.append(GGSpoofRow(id: rowId, kind: .disclosure(title: origTitle, label: label == origTitle ? "" : label)))
                model.tap[rowId] = {
                    push(ggSpoofMakeVisualEditorController(context: context, peerId: peerId))
                }
            }
            model.sections.append(rows)
        }

        return model
    }

    let controller = ggSpoofMakeListController(context: context, model: model)
    weakController = controller
    return controller
}

func ggSpoofMakeVisualEditorController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let peerKey = peerId.ggKey
    weak var weakController: ViewController?

    let initial = GGVisualProfileStore.shared.override(for: peerKey) ?? GGVisualPeerOverride()
    let draftAtomic = Atomic<GGVisualPeerOverride>(value: initial)
    let uiTick = ValuePromise<Int32>(0, ignoreRepeated: false)

    func commitCurrentDraft() {
        let value = draftAtomic.with { $0 }
        GGVisualProfileStore.shared.setOverride(value, for: peerKey)
    }

    let model = combineLatest(queue: .mainQueue(), uiTick.get(), GGVisualProfileStore.shared.revisionSignal, GGLocalization.shared.languageCodeSignal)
    |> map { _, _, _ -> GGSpoofScreenModel in
        let current = draftAtomic.with { $0 }
        let avatarInfo = GGVisualProfileStore.shared.avatarInfo(for: peerKey)
        var model = GGSpoofScreenModel(title: GGStrings.NetworkSpoof.Visual.editorTitle)

        model.sections.append([
            GGSpoofRow(id: "fields.header", kind: .header(GGStrings.NetworkSpoof.Visual.fieldsHeader)),
            GGSpoofRow(id: "field.name", kind: .input(text: current.name, placeholder: GGStrings.NetworkSpoof.Visual.namePlaceholder)),
            GGSpoofRow(id: "field.username", kind: .input(text: current.username, placeholder: GGStrings.NetworkSpoof.Visual.mainUsernamePlaceholder)),
            GGSpoofRow(id: "field.also", kind: .input(text: current.alsoUsernames, placeholder: GGStrings.NetworkSpoof.Visual.alsoUsernamesPlaceholder)),
            GGSpoofRow(id: "field.phone", kind: .input(text: current.phone, placeholder: GGStrings.NetworkSpoof.Visual.phonePlaceholder)),
            GGSpoofRow(id: "field.bio", kind: .multilineInput(text: current.bio, placeholder: GGStrings.NetworkSpoof.Visual.bioPlaceholder))
        ])

        model.text["field.name"] = { val in
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.name = val
                return copy
            }
        }
        model.text["field.username"] = { val in
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.username = val
                return copy
            }
        }
        model.text["field.also"] = { val in
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.alsoUsernames = val
                return copy
            }
        }
        model.text["field.phone"] = { val in
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.phone = val
                return copy
            }
        }
        model.text["field.bio"] = { val in
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.bio = val
                return copy
            }
        }

        var badgeRows: [GGSpoofRow] = [GGSpoofRow(id: "badge.header", kind: .header(GGStrings.NetworkSpoof.Visual.badgeHeader))]
        for mode in GGVisualBadgeMode.allCases {
            let rowId = "badge.\(mode.rawValue)"
            badgeRows.append(GGSpoofRow(id: rowId, kind: .check(title: ggVisualBadgeTitle(mode), label: "", checked: current.badgeMode == mode)))
            model.tap[rowId] = {
                let _ = draftAtomic.modify { cur in
                    var copy = cur
                    copy.badgeMode = mode
                    return copy
                }
                commitCurrentDraft()
                uiTick.set(Int32.random(in: 1 ... Int32.max))
            }
        }
        model.sections.append(badgeRows)

        let avatarLabel: String
        if let info = avatarInfo {
            let videoSuffix = info.videoUrl != nil ? " • 4K Video" : ""
            avatarLabel = "\(GGStrings.NetworkSpoof.Visual.avatarActive) (\(info.width)×\(info.height)\(videoSuffix))"
        } else {
            avatarLabel = GGStrings.NetworkSpoof.Visual.avatarNotSet
        }
        var avatarRows: [GGSpoofRow] = [
            GGSpoofRow(id: "avatar.header", kind: .header(GGStrings.NetworkSpoof.Visual.avatarHeader)),
            GGSpoofRow(id: "avatar.pick", kind: .disclosure(title: GGStrings.NetworkSpoof.Visual.avatarPick, label: avatarLabel))
        ]
        model.tap["avatar.pick"] = {
            commitCurrentDraft()
            ggPresentVisualPhotoPicker(from: weakController) { data, videoData, width, height in
                if let videoData, !videoData.isEmpty {
                    if let saved = GGVisualProfileStore.shared.saveAvatarVideoData(videoData, coverData: data, width: width, height: height, for: peerKey) {
                        let resource = LocalFileMediaResource(fileId: saved.fileId, size: Int64(data.count), isSecretRelated: false)
                        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: false)
                        if saved.videoFileId != 0 {
                            let videoResource = LocalFileMediaResource(fileId: saved.videoFileId, size: Int64(videoData.count), isSecretRelated: false)
                            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(videoResource.id), data: videoData, synchronous: false)
                        }
                        GGVisualProfileStore.shared.publishGlobal4kAvatar(for: peerKey, photoData: data, videoData: videoData)
                        let _ = draftAtomic.modify { cur in
                            var copy = cur
                            copy.avatarFileName = saved.url.lastPathComponent
                            copy.avatarWidth = saved.width
                            copy.avatarHeight = saved.height
                            copy.avatarFileId = saved.fileId
                            copy.avatarVideoFileName = saved.videoUrl?.lastPathComponent ?? ""
                            copy.avatarVideoFileId = saved.videoFileId
                            return copy
                        }
                        uiTick.set(Int32.random(in: 1 ... Int32.max))
                    }
                } else if let saved = GGVisualProfileStore.shared.saveAvatarData(data, width: width, height: height, for: peerKey) {
                    let resource = LocalFileMediaResource(fileId: saved.fileId, size: Int64(data.count), isSecretRelated: false)
                    context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: false)
                    GGVisualProfileStore.shared.publishGlobal4kAvatar(for: peerKey, photoData: data, videoData: nil)
                    let _ = draftAtomic.modify { cur in
                        var copy = cur
                        copy.avatarFileName = saved.url.lastPathComponent
                        copy.avatarWidth = saved.width
                        copy.avatarHeight = saved.height
                        copy.avatarFileId = saved.fileId
                        copy.avatarVideoFileName = ""
                        copy.avatarVideoFileId = 0
                        return copy
                    }
                    uiTick.set(Int32.random(in: 1 ... Int32.max))
                }
            }
        }
        if avatarInfo != nil {
            avatarRows.append(GGSpoofRow(id: "avatar.remove", kind: .action(title: GGStrings.NetworkSpoof.Visual.avatarRemove, destructive: true, enabled: true)))
            model.tap["avatar.remove"] = {
                commitCurrentDraft()
                GGVisualProfileStore.shared.removeAvatar(for: peerKey)
                let _ = draftAtomic.modify { cur in
                    var copy = cur
                    copy.avatarFileName = ""
                    copy.avatarWidth = 0
                    copy.avatarHeight = 0
                    copy.avatarFileId = 0
                    copy.avatarVideoFileName = ""
                    copy.avatarVideoFileId = 0
                    return copy
                }
                uiTick.set(Int32.random(in: 1 ... Int32.max))
            }
        }
        model.sections.append(avatarRows)

        model.sections.append([
            GGSpoofRow(id: "reset", kind: .action(title: GGStrings.NetworkSpoof.Visual.resetAll, destructive: true, enabled: true))
        ])
        model.tap["reset"] = {
            let empty = GGVisualPeerOverride()
            let _ = draftAtomic.swap(empty)
            GGVisualProfileStore.shared.setOverride(empty, for: peerKey)
            uiTick.set(Int32.random(in: 1 ... Int32.max))
        }

        model.rightButton = (GGStrings.NetworkSpoof.done, {
            weakController?.view.endEditing(true)
            commitCurrentDraft()
            _ = (weakController?.navigationController as? NavigationController)?.popViewController(animated: true)
        })

        return model
    }

    let controller = ggSpoofMakeListController(context: context, model: model)
    weakController = controller
    return controller
}
