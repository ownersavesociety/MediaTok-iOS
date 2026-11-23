import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import AlertUI
import PresentationDataUtils
import LocalizedPeerData
import MTCore

// Screens of «Подмены»: phone number, profile substitution. A typed number stays in the screen until
// «Готово»: nothing is written per keystroke.

func mtSpoofMakePhoneController(context: AccountContext) -> ViewController {
    let account = context.account.id.mt
    weak var weakController: ViewController?
    let draft = ValuePromise<String?>(nil, ignoreRepeated: true)
    let draftValue = Atomic<String?>(value: nil)

    let model = combineLatest(queue: .mainQueue(), MTNetworkSpoofSettings.fakePhoneEnabled.signal(for: account), MTNetworkSpoofSettings.fakePhone.signal(for: account), draft.get(), MTLocalization.shared.languageCodeSignal)
    |> map { enabled, number, draftText, _ -> MTSpoofScreenModel in
        var model = MTSpoofScreenModel(title: MTStrings.NetworkSpoof.Phone.title)
        model.sections.append([
            MTSpoofRow(id: "enabled", kind: .toggle(title: MTStrings.NetworkSpoof.Phone.enable, value: enabled, enabled: !number.isEmpty || enabled)),
            MTSpoofRow(id: "number.header", kind: .header(MTStrings.NetworkSpoof.Phone.numberHeader)),
            MTSpoofRow(id: "number", kind: .numberInput(title: "+", text: draftText ?? number, placeholder: "79991234567")),
            MTSpoofRow(id: "footer", kind: .footer(MTStrings.NetworkSpoof.Phone.footer))
        ])
        model.toggle["enabled"] = { value in
            MTNetworkSpoofSettings.fakePhoneEnabled.set(value, for: account)
        }
        model.text["number"] = { value in
            let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(15))
            let _ = draftValue.swap(digits)
            draft.set(digits)
        }
        if draftText != nil {
            model.rightButton = (MTStrings.NetworkSpoof.done, {
                if let digits = draftValue.swap(nil) {
                    MTNetworkSpoofSettings.fakePhone.set(digits, for: account)
                    if digits.isEmpty {
                        MTNetworkSpoofSettings.fakePhoneEnabled.set(false, for: account)
                    }
                }
                draft.set(nil)
                weakController?.view.endEditing(true)
            })
        }
        return model
    }
    let controller = mtSpoofMakeListController(context: context, model: model)
    weakController = controller
    return controller
}

func mtSpoofMakeProfilesController(context: AccountContext) -> ViewController {
    let account = context.account.id.mt
    weak var weakController: ViewController?
    let push: (ViewController) -> Void = { controller in
        (weakController?.navigationController as? NavigationController)?.pushViewController(controller)
    }

    let redirects = MTNetworkSpoofSettings.profileRedirects.signal(for: account)
    let peers = redirects
    |> mapToSignal { redirects -> Signal<[EnginePeer.Id: EnginePeer], NoError> in
        var ids: [EnginePeer.Id] = []
        for (source, target) in redirects {
            if let key = MTPeerKey(string: source) {
                ids.append(PeerId(mtKey: key))
            }
            ids.append(PeerId(mtKey: target))
        }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { result -> [EnginePeer.Id: EnginePeer] in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in result {
                if let peer {
                    peers[id] = peer
                }
            }
            return peers
        }
    }

    let model = combineLatest(queue: .mainQueue(), MTNetworkSpoofSettings.profileRedirectEnabled.signal(for: account), redirects, peers, MTLocalization.shared.languageCodeSignal)
    |> map { enabled, redirects, peers, _ -> MTSpoofScreenModel in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let name: (EnginePeer.Id) -> String = { id in
            return peers[id]?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? MTStrings.NetworkSpoof.Profiles.unknownPeer
        }
        var model = MTSpoofScreenModel(title: MTStrings.NetworkSpoof.Profiles.title)
        model.sections.append([
            MTSpoofRow(id: "enabled", kind: .toggle(title: MTStrings.NetworkSpoof.Profiles.enable, value: enabled, enabled: true)),
            MTSpoofRow(id: "enabled.footer", kind: .footer(MTStrings.NetworkSpoof.Profiles.footer))
        ])
        model.toggle["enabled"] = { value in
            MTNetworkSpoofSettings.profileRedirectEnabled.set(value, for: account)
        }

        var rows: [MTSpoofRow] = [MTSpoofRow(id: "pairs.header", kind: .header(MTStrings.NetworkSpoof.Profiles.pairsHeader))]
        for source in redirects.keys.sorted() {
            guard let sourceKey = MTPeerKey(string: source), let target = redirects[source] else {
                continue
            }
            let rowId = "pair.\(source)"
            rows.append(MTSpoofRow(id: rowId, kind: .disclosure(title: MTStrings.NetworkSpoof.Profiles.pair(source: name(PeerId(mtKey: sourceKey)), target: name(PeerId(mtKey: target))), label: "")))
            model.tap[rowId] = {
                let alert = textAlertController(context: context, title: nil, text: MTStrings.NetworkSpoof.Profiles.removeConfirm, actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: MTStrings.NetworkSpoof.Profiles.remove, action: {
                        var current = MTNetworkSpoofSettings.profileRedirects.value(for: account)
                        current.removeValue(forKey: source)
                        MTNetworkSpoofSettings.profileRedirects.set(current, for: account)
                    })
                ])
                weakController?.present(alert, in: .window(.root))
            }
        }
        rows.append(MTSpoofRow(id: "pairs.add", kind: .action(title: MTStrings.NetworkSpoof.Profiles.add, destructive: false, enabled: true)))
        model.tap["pairs.add"] = {
            let sourcePicker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSavedMessages, .excludeSecretChats, .doNotSearchMessages], hasContactSelector: false, title: MTStrings.NetworkSpoof.Profiles.pickSource))
            sourcePicker.peerSelected = { [weak sourcePicker] sourcePeer, _ in
                let targetPicker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSavedMessages, .excludeSecretChats, .doNotSearchMessages], hasContactSelector: false, title: MTStrings.NetworkSpoof.Profiles.pickTarget))
                targetPicker.peerSelected = { [weak targetPicker] targetPeer, _ in
                    if targetPeer.id != sourcePeer.id {
                        var current = MTNetworkSpoofSettings.profileRedirects.value(for: account)
                        current[sourcePeer.id.mtKey.stringValue] = targetPeer.id.mtKey
                        MTNetworkSpoofSettings.profileRedirects.set(current, for: account)
                        if !MTNetworkSpoofSettings.profileRedirectEnabled.value(for: account) {
                            MTNetworkSpoofSettings.profileRedirectEnabled.set(true, for: account)
                        }
                    }
                    targetPicker?.dismiss()
                }
                sourcePicker?.dismiss()
                push(targetPicker)
            }
            push(sourcePicker)
        }
        model.sections.append(rows)
        return model
    }
    let controller = mtSpoofMakeListController(context: context, model: model)
    weakController = controller
    return controller
}
