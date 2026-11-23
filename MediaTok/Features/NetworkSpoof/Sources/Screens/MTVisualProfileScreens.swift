import Foundation
import UIKit
import ObjectiveC
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
import MTCore
import MTHooks
import MTSettingsUI

private let mtVisualMaxAvatarDimension: Int = 3840

private final class MTVisualPhotoPickerBox: NSObject, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    static var associatedKey: UInt8 = 0
    private let completion: (Data, Data?, Int, Int) -> Void

    init(completion: @escaping (Data, Data?, Int, Int) -> Void) {
        self.completion = completion
        super.init()
    }

    private func finish(_ picker: PHPickerViewController? = nil) {
        if let picker {
            objc_setAssociatedObject(picker, &MTVisualPhotoPickerBox.associatedKey, nil, .OBJC_ASSOCIATION_ASSIGN)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            self.finish(picker)
            return
        }
        let completion = self.completion
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url,
                      let videoData = try? Data(contentsOf: url),
                      !videoData.isEmpty else {
                    DispatchQueue.main.async {
                        self.finish(picker)
                    }
                    return
                }
                let encodedCover = mtVisualExtractVideoCover4k(from: url)
                DispatchQueue.main.async {
                    if let (coverData, width, height) = encodedCover {
                        completion(coverData, videoData, width, height)
                    }
                    self.finish(picker)
                }
            }
            return
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            self.finish(picker)
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            guard let url else {
                DispatchQueue.main.async {
                    self.finish(picker)
                }
                return
            }
            let encoded = mtVisualEncode4kAvatar(from: url)
            DispatchQueue.main.async {
                if let (data, width, height) = encoded {
                    completion(data, nil, width, height)
                }
                self.finish(picker)
            }
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.finish(presentationController.presentedViewController as? PHPickerViewController)
    }
}

private func mtVisualExtractVideoCover4k(from url: URL) -> (Data, Int, Int)? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: CGFloat(mtVisualMaxAvatarDimension), height: CGFloat(mtVisualMaxAvatarDimension))
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

private func mtVisualEncode4kAvatar(from url: URL) -> (Data, Int, Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }
    let thumbOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: mtVisualMaxAvatarDimension
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

private func mtPresentVisualPhotoPicker(from controller: ViewController?, completion: @escaping (Data, Data?, Int, Int) -> Void) {
    let preferredRoot = controller?.view.window?.rootViewController ?? controller
    guard preferredRoot != nil else {
        return
    }
    var configuration = PHPickerConfiguration()
    configuration.selectionLimit = 1
    configuration.filter = .any(of: [.images, .videos])
    let picker = PHPickerViewController(configuration: configuration)
    let box = MTVisualPhotoPickerBox(completion: completion)
    objc_setAssociatedObject(picker, &MTVisualPhotoPickerBox.associatedKey, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    picker.delegate = box
    picker.presentationController?.delegate = box
    MTModalPresenter.presentOnTopmost(picker, preferredRoot: preferredRoot)
}

enum MTVisualProfileSupport {
    static func registerHooks() {
        MTPeerInfoHooks.displayedPhoneNumber.register({ request in
            if let visPhone = MTVisualProfileStore.shared.phone(for: request.peerId.mtKey) {
                return .replaced(visPhone)
            }
            return nil
        }, order: -200)

        MTPeerInfoHooks.menuItems.register({ peerInfo in
            let targetPeer = peerInfo.chatPeer ?? peerInfo.peer
            let peerId = targetPeer.id
            let context = peerInfo.context
            weak let weakController = peerInfo.controller
            return [
                .action(ContextMenuActionItem(
                    text: MTStrings.NetworkSpoof.Visual.menuItem,
                    icon: { theme in
                        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.contextMenu.primaryColor)
                    },
                    action: { _, f in
                        f(.dismissWithoutContent)
                        let editor = mtSpoofMakeVisualEditorController(context: context, peerId: peerId)
                        if let nav = weakController?.navigationController as? NavigationController {
                            nav.pushViewController(editor)
                        } else if let nav = context.sharedContext.mainWindow?.viewController as? NavigationController {
                            nav.pushViewController(editor)
                        }
                    }
                ))
            ]
        })

        MTChatListHooks.accessoryPeers.register({ _ in
            return MTVisualProfileStore.shared.revisionSignal
            |> map { _ -> Set<EnginePeer.Id> in
                return Set(MTVisualProfileStore.shared.trackedPeerKeys.map { PeerId(mtKey: $0) })
            }
        })
    }
}

private func mtVisualBadgeTitle(_ mode: MTVisualBadgeMode) -> String {
    switch mode {
    case .default:
        return MTStrings.NetworkSpoof.Visual.badgeDefault
    case .verified:
        return MTStrings.NetworkSpoof.Visual.badgeVerified
    case .premium:
        return MTStrings.NetworkSpoof.Visual.badgePremium
    case .scam:
        return MTStrings.NetworkSpoof.Visual.badgeScam
    case .fake:
        return MTStrings.NetworkSpoof.Visual.badgeFake
    case .hide:
        return MTStrings.NetworkSpoof.Visual.badgeHide
    }
}

func mtSpoofMakeVisualListController(context: AccountContext) -> ViewController {
    weak var weakController: ViewController?
    let push: (ViewController) -> Void = { screen in
        if let nav = weakController?.navigationController as? NavigationController {
            nav.pushViewController(screen)
        } else if let nav = context.sharedContext.mainWindow?.viewController as? NavigationController {
            nav.pushViewController(screen)
        }
    }

    let peersSignal = MTVisualProfileStore.shared.revisionSignal
    |> mapToSignal { _ -> Signal<(EnginePeer?, [EnginePeer.Id: EnginePeer], [(key: MTPeerKey, value: MTVisualPeerOverride)]), NoError> in
        let entries = MTVisualProfileStore.shared.allOverrides()
        var ids = Set<EnginePeer.Id>()
        ids.insert(context.account.peerId)
        for item in entries {
            ids.insert(PeerId(mtKey: item.key))
        }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { mapResult -> (EnginePeer?, [EnginePeer.Id: EnginePeer], [(key: MTPeerKey, value: MTVisualPeerOverride)]) in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in mapResult {
                if let peer {
                    peers[id] = peer
                }
            }
            return (peers[context.account.peerId], peers, entries)
        }
    }

    let model = combineLatest(queue: .mainQueue(), peersSignal, MTLocalization.shared.languageCodeSignal)
    |> map { peersBundle, _ -> MTSpoofScreenModel in
        let (_, peers, _) = peersBundle
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var model = MTSpoofScreenModel(title: MTStrings.NetworkSpoof.Visual.tabTitle)

        model.sections.append([
            MTSpoofRow(id: "self", kind: .disclosure(title: MTStrings.NetworkSpoof.Visual.editSelf, label: "")),
            MTSpoofRow(id: "pick", kind: .action(title: MTStrings.NetworkSpoof.Visual.pickPeer, destructive: false, enabled: true)),
            MTSpoofRow(id: "footer", kind: .footer(MTStrings.NetworkSpoof.Visual.listFooter))
        ])
        model.tap["self"] = {
            push(mtSpoofMakeVisualEditorController(context: context, peerId: context.account.peerId))
        }
        model.tap["pick"] = {
            let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: [.excludeSavedMessages, .excludeSecretChats, .doNotSearchMessages],
                hasContactSelector: false,
                title: MTStrings.NetworkSpoof.Visual.pickPeer
            ))
            picker.peerSelected = { [weak picker] peer, _ in
                picker?.dismiss()
                push(mtSpoofMakeVisualEditorController(context: context, peerId: peer.id))
            }
            push(picker)
        }

        let configured = MTVisualProfileStore.shared.allOverrides()
        if !configured.isEmpty {
            var rows: [MTSpoofRow] = [MTSpoofRow(id: "configured.header", kind: .header(MTStrings.NetworkSpoof.Visual.listHeader))]
            for entry in configured {
                let peerId = PeerId(mtKey: entry.key)
                let origTitle = peers[peerId]?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? MTStrings.NetworkSpoof.Profiles.unknownPeer
                let label = !entry.value.name.isEmpty ? entry.value.name : origTitle
                let rowId = "peer.\(entry.key.stringValue)"
                rows.append(MTSpoofRow(id: rowId, kind: .disclosure(title: origTitle, label: label == origTitle ? "" : label)))
                model.tap[rowId] = {
                    push(mtSpoofMakeVisualEditorController(context: context, peerId: peerId))
                }
            }
            model.sections.append(rows)
        }

        return model
    }

    let controller = mtSpoofMakeListController(context: context, model: model)
    weakController = controller
    return controller
}

func mtSpoofMakeVisualEditorController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let peerKey = peerId.mtKey
    weak var weakController: ViewController?

    let initial = MTVisualProfileStore.shared.override(for: peerKey) ?? MTVisualPeerOverride()
    let draftAtomic = Atomic<MTVisualPeerOverride>(value: initial)
    let uiTick = ValuePromise<Int32>(0, ignoreRepeated: false)

    func commitCurrentDraft() {
        let value = draftAtomic.with { $0 }
        MTVisualProfileStore.shared.setOverride(value, for: peerKey)
    }

    let model = combineLatest(queue: .mainQueue(), uiTick.get(), MTVisualProfileStore.shared.revisionSignal, MTLocalization.shared.languageCodeSignal)
    |> map { _, _, _ -> MTSpoofScreenModel in
        let current = draftAtomic.with { $0 }
        let avatarInfo = MTVisualProfileStore.shared.avatarInfo(for: peerKey)
        var model = MTSpoofScreenModel(title: MTStrings.NetworkSpoof.Visual.editorTitle)

        model.sections.append([
            MTSpoofRow(id: "fields.header", kind: .header(MTStrings.NetworkSpoof.Visual.fieldsHeader)),
            MTSpoofRow(id: "field.name", kind: .input(text: current.name, placeholder: MTStrings.NetworkSpoof.Visual.namePlaceholder)),
            MTSpoofRow(id: "field.username", kind: .input(text: current.username, placeholder: MTStrings.NetworkSpoof.Visual.mainUsernamePlaceholder)),
            MTSpoofRow(id: "field.also", kind: .input(text: current.alsoUsernames, placeholder: MTStrings.NetworkSpoof.Visual.alsoUsernamesPlaceholder)),
            MTSpoofRow(id: "field.phone", kind: .input(text: current.phone, placeholder: MTStrings.NetworkSpoof.Visual.phonePlaceholder)),
            MTSpoofRow(id: "field.alsoPhones", kind: .multilineInput(text: current.alsoPhones, placeholder: MTStrings.NetworkSpoof.Visual.alsoPhonesPlaceholder)),
            MTSpoofRow(id: "field.bio", kind: .multilineInput(text: current.bio, placeholder: MTStrings.NetworkSpoof.Visual.bioPlaceholder))
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
        model.text["field.alsoPhones"] = { val in
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.alsoPhones = val
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

        var badgeRows: [MTSpoofRow] = [MTSpoofRow(id: "badge.header", kind: .header(MTStrings.NetworkSpoof.Visual.badgeHeader))]
        for mode in MTVisualBadgeMode.allCases {
            let rowId = "badge.\(mode.rawValue)"
            badgeRows.append(MTSpoofRow(id: rowId, kind: .check(title: mtVisualBadgeTitle(mode), label: "", checked: current.simultaneousBadgeMask == 0 && current.badgeMode == mode)))
            model.tap[rowId] = {
                let _ = draftAtomic.modify { cur in
                    var copy = cur
                    copy.badgeMode = mode
                    copy.simultaneousBadgeMask = 0
                    return copy
                }
                commitCurrentDraft()
                uiTick.set(Int32.random(in: 1 ... Int32.max))
            }
        }
        model.sections.append(badgeRows)

        let multiBadges: [(bit: Int, id: String, title: String)] = [
            (1, "multibadge.verified", "Verified + остальные (одновременно)"),
            (2, "multibadge.premium", "Premium + остальные (одновременно)"),
            (4, "multibadge.scam", "SCAM (совместно)"),
            (8, "multibadge.fake", "FAKE (совместно)")
        ]
        var multiBadgeRows: [MTSpoofRow] = [MTSpoofRow(id: "multibadge.header", kind: .header("НЕСКОЛЬКО БЕЙДЖЕЙ ОДНОВРЕМЕННО"))]
        for mb in multiBadges {
            let isOn = (current.simultaneousBadgeMask & mb.bit) != 0
            multiBadgeRows.append(MTSpoofRow(id: mb.id, kind: .check(title: mb.title, label: "", checked: isOn)))
            model.tap[mb.id] = {
                let _ = draftAtomic.modify { cur in
                    var copy = cur
                    copy.simultaneousBadgeMask ^= mb.bit
                    return copy
                }
                commitCurrentDraft()
                uiTick.set(Int32.random(in: 1 ... Int32.max))
            }
        }
        model.sections.append(multiBadgeRows)

        let levelStr = current.visualStarLevel > 0 ? "\(current.visualStarLevel)" : ""
        let starsStr = current.visualStarsCount > 0 ? "\(current.visualStarsCount)" : ""
        let dcStr = current.customDataCenter > 0 ? "\(current.customDataCenter)" : ""
        model.sections.append([
            MTSpoofRow(id: "meta.header", kind: .header("УРОВЕНЬ, ID, DC И ДАТА РЕГИСТРАЦИИ")),
            MTSpoofRow(id: "field.starLevel", kind: .input(text: levelStr, placeholder: "Уровень профиля (Level, напр. 99)")),
            MTSpoofRow(id: "field.starsCount", kind: .input(text: starsStr, placeholder: "Звёзды в уровне (напр. 250000)")),
            MTSpoofRow(id: "field.regDate", kind: .input(text: current.customRegDate, placeholder: "Дата регистрации (ДД.ММ.ГГГГ ЧЧ:ММ:СС)")),
            MTSpoofRow(id: "field.customId", kind: .input(text: current.customAccountId, placeholder: "Кастомный ID аккаунта (напр. 777777)")),
            MTSpoofRow(id: "field.customDc", kind: .input(text: dcStr, placeholder: "Дата-центр DC (1–5)"))
        ])
        model.text["field.starLevel"] = { val in
            let parsed = Int32(val.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.visualStarLevel = max(0, min(999, parsed))
                return copy
            }
        }
        model.text["field.starsCount"] = { val in
            let parsed = Int64(val.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.visualStarsCount = max(0, parsed)
                return copy
            }
        }
        model.text["field.regDate"] = { val in
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.customRegDate = val
                return copy
            }
        }
        model.text["field.customId"] = { val in
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.customAccountId = val
                return copy
            }
        }
        model.text["field.customDc"] = { val in
            let parsed = Int(val.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let _ = draftAtomic.modify { cur in
                var copy = cur
                copy.customDataCenter = (1...5).contains(parsed) ? parsed : 0
                return copy
            }
        }

        let avatarLabel: String
        if let info = avatarInfo {
            let videoSuffix = info.videoUrl != nil ? " • 4K Video" : ""
            avatarLabel = "\(MTStrings.NetworkSpoof.Visual.avatarActive) (\(info.width)×\(info.height)\(videoSuffix))"
        } else {
            avatarLabel = MTStrings.NetworkSpoof.Visual.avatarNotSet
        }
        var avatarRows: [MTSpoofRow] = [
            MTSpoofRow(id: "avatar.header", kind: .header(MTStrings.NetworkSpoof.Visual.avatarHeader)),
            MTSpoofRow(id: "avatar.pick", kind: .disclosure(title: MTStrings.NetworkSpoof.Visual.avatarPick, label: avatarLabel))
        ]
        model.tap["avatar.pick"] = {
            commitCurrentDraft()
            mtPresentVisualPhotoPicker(from: weakController) { data, videoData, width, height in
                if let videoData, !videoData.isEmpty {
                    if let saved = MTVisualProfileStore.shared.saveAvatarVideoData(videoData, coverData: data, width: width, height: height, for: peerKey) {
                        let resource = LocalFileMediaResource(fileId: saved.fileId, size: Int64(data.count), isSecretRelated: false)
                        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: false)
                        if saved.videoFileId != 0 {
                            let videoResource = LocalFileMediaResource(fileId: saved.videoFileId, size: Int64(videoData.count), isSecretRelated: false)
                            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(videoResource.id), data: videoData, synchronous: false)
                        }
                        if peerId == context.account.peerId {
                            MTVisualProfileStore.shared.publishGlobal4kAvatar(for: peerKey, photoData: data, videoData: videoData)
                        }
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
                } else if let saved = MTVisualProfileStore.shared.saveAvatarData(data, width: width, height: height, for: peerKey) {
                    let resource = LocalFileMediaResource(fileId: saved.fileId, size: Int64(data.count), isSecretRelated: false)
                    context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: false)
                    if peerId == context.account.peerId {
                        MTVisualProfileStore.shared.publishGlobal4kAvatar(for: peerKey, photoData: data, videoData: nil)
                    }
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
            avatarRows.append(MTSpoofRow(id: "avatar.remove", kind: .action(title: MTStrings.NetworkSpoof.Visual.avatarRemove, destructive: true, enabled: true)))
            model.tap["avatar.remove"] = {
                commitCurrentDraft()
                MTVisualProfileStore.shared.removeAvatar(for: peerKey)
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
            MTSpoofRow(id: "reset", kind: .action(title: MTStrings.NetworkSpoof.Visual.resetAll, destructive: true, enabled: true))
        ])
        model.tap["reset"] = {
            let empty = MTVisualPeerOverride()
            let _ = draftAtomic.swap(empty)
            MTVisualProfileStore.shared.setOverride(empty, for: peerKey)
            uiTick.set(Int32.random(in: 1 ... Int32.max))
        }

        model.rightButton = (MTStrings.NetworkSpoof.done, {
            weakController?.view.endEditing(true)
            commitCurrentDraft()
            _ = (weakController?.navigationController as? NavigationController)?.popViewController(animated: true)
        })

        return model
    }

    let controller = mtSpoofMakeListController(context: context, model: model)
    weakController = controller
    controller.willDisappear = { _ in
        commitCurrentDraft()
    }
    return controller
}
