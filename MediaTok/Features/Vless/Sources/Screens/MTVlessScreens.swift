import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AlertUI
import PresentationDataUtils
import MTCore
import MTFeaturesShared

// Screens of «VPN по подписке»: servers and subscriptions (status, choice, ping), a new
// subscription, a subscription's settings.

enum MTVlessText {
    static func status(_ status: MTVlessStatus) -> String {
        switch status {
        case .off:
            return MTStrings.Vless.Status.off
        case .notBundled:
            return MTStrings.Vless.Status.notBundled
        case .noServer:
            return MTStrings.Vless.Status.noServer
        case .starting:
            return MTStrings.Vless.Status.starting
        case let .running(serverName):
            return MTStrings.Vless.Status.running(server: serverName)
        case let .unreachable(serverName):
            return MTStrings.Vless.Status.unreachable(server: serverName)
        case let .failed(failure):
            switch failure {
            case .loadFailed:
                return MTStrings.Vless.Status.loadFailed
            case .configInvalid:
                return MTStrings.Vless.Status.configInvalid
            case .startFailed:
                return MTStrings.Vless.Status.startFailed
            }
        }
    }

    static func error(_ error: MTVlessFetchError) -> String {
        return MTVlessText.error(code: MTVlessController.errorCode(error))
    }

    static func error(code: String) -> String {
        if code.hasPrefix("http:") {
            return MTStrings.Vless.Error.http(code: String(code.dropFirst("http:".count)))
        }
        switch code {
        case "invalidURL":
            return MTStrings.Vless.Error.invalidURL
        case "tooLarge":
            return MTStrings.Vless.Error.tooLarge
        case "empty":
            return MTStrings.Vless.Error.empty
        default:
            return MTStrings.Vless.Error.network
        }
    }

    static func bytes(_ value: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func date(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: MTLocalization.shared.languageCode)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    static func interval(_ interval: MTVlessUpdateInterval) -> String {
        switch interval {
        case .provider:
            return MTStrings.Vless.Subscription.Interval.provider
        case .hours6:
            return MTStrings.Vless.Subscription.Interval.hours6
        case .hours12:
            return MTStrings.Vless.Subscription.Interval.hours12
        case .hours24:
            return MTStrings.Vless.Subscription.Interval.hours24
        case .manual:
            return MTStrings.Vless.Subscription.Interval.manual
        }
    }

    /// Usage, expiry, last refresh or its error — one info block under a subscription's header.
    static func subscriptionInfo(_ subscription: MTVlessSubscription) -> String {
        var lines: [String] = [MTStrings.Vless.Subscription.servers(count: subscription.servers.count)]
        if let usage = subscription.usage {
            let used = usage.upload + usage.download
            if usage.total > 0 {
                lines.append(MTStrings.Vless.Servers.usage(used: MTVlessText.bytes(used), total: MTVlessText.bytes(usage.total)))
            } else {
                lines.append(MTStrings.Vless.Servers.usageUnlimited(used: MTVlessText.bytes(used)))
            }
            if usage.expire > 0 {
                lines.append(MTStrings.Vless.Servers.expires(date: MTVlessText.date(Double(usage.expire))))
            }
        }
        if subscription.url == nil {
            lines.append(MTStrings.Vless.Servers.manual)
        } else if let error = subscription.lastError {
            lines.append(MTStrings.Vless.Error.lastRefresh(reason: MTVlessText.error(code: error)))
        } else if subscription.updatedAt > 0 {
            lines.append(MTStrings.Vless.Servers.updated(date: MTVlessText.date(subscription.updatedAt)))
        }
        return lines.joined(separator: "\n")
    }
}

func mtVlessMakeServersController(context: AccountContext) -> ViewController {
    MTVlessController.shared.attach(context: context)
    weak var weakController: ViewController?
    let push: (ViewController) -> Void = { controller in
        (weakController?.navigationController as? NavigationController)?.pushViewController(controller)
    }

    let model = combineLatest(queue: .mainQueue(),
        MTVlessStore.shared.subscriptionsSignal,
        MTVlessController.shared.status,
        MTVlessController.shared.pingResults,
        MTVlessController.shared.traffic(),
        MTSettingsStore.shared.revision,
        MTLocalization.shared.languageCodeSignal
    )
    |> map { subscriptions, status, pings, traffic, _, _ -> MTVlessScreenModel in
        var model = MTVlessScreenModel(title: MTStrings.Vless.Servers.title)
        let selectedId = MTVlessSettings.selectedServer.value

        var statusRows: [MTVlessRow] = [MTVlessRow(id: "status.header", kind: .header(MTStrings.Vless.Status.title))]
        // The same switch as in the menu: this screen is also reached from Telegram's proxy screen.
        let enabled = MTVlessSettings.enabled.value
        let canSwitch = enabled || (MTXrayCore.isBundled && !selectedId.isEmpty)
        statusRows.append(MTVlessRow(id: "status.enabled", kind: .toggle(title: MTStrings.Vless.Menu.enable, value: enabled, enabled: canSwitch)))
        model.toggle["status.enabled"] = { value in
            MTVlessSettings.enabled.set(value)
        }
        var statusText = MTVlessText.status(status)
        if let traffic {
            statusText += "\n" + MTStrings.Vless.Status.traffic(up: MTVlessText.bytes(traffic.uplink), down: MTVlessText.bytes(traffic.downlink))
        }
        if !selectedId.isEmpty && MTVlessStore.shared.server(id: selectedId) == nil, case let .running(serverName) = status {
            statusText += "\n" + MTStrings.Vless.Servers.removed(server: serverName)
        }
        statusRows.append(MTVlessRow(id: "status.text", kind: .info(statusText)))
        model.sections.append(statusRows)

        var actions: [MTVlessRow] = [MTVlessRow(id: "action.add", kind: .action(title: MTStrings.Vless.Servers.add, destructive: false, enabled: true))]
        model.tap["action.add"] = {
            push(mtVlessMakeAddController(context: context))
        }
        if !subscriptions.isEmpty {
            actions.append(MTVlessRow(id: "action.ping", kind: .action(title: MTStrings.Vless.Servers.ping, destructive: false, enabled: true)))
            model.tap["action.ping"] = {
                MTVlessController.shared.pingAll()
            }
            if subscriptions.contains(where: { $0.url != nil }) {
                actions.append(MTVlessRow(id: "action.refresh", kind: .action(title: MTStrings.Vless.Servers.refreshAll, destructive: false, enabled: true)))
                model.tap["action.refresh"] = {
                    for subscription in MTVlessStore.shared.subscriptions where subscription.url != nil {
                        let _ = MTVlessController.shared.refresh(subscriptionId: subscription.id).start()
                    }
                }
            }
        } else {
            actions.append(MTVlessRow(id: "action.empty", kind: .footer(MTStrings.Vless.Servers.empty)))
        }
        model.sections.append(actions)

        for subscription in subscriptions {
            var rows: [MTVlessRow] = [MTVlessRow(id: "sub.\(subscription.id).header", kind: .header(subscription.name.isEmpty ? MTStrings.Vless.Subscription.title : subscription.name))]
            for server in subscription.servers {
                let rowId = "server.\(subscription.id).\(server.id)"
                var label = ""
                if let ping = pings[server.id] {
                    label = ping >= 0 ? MTStrings.Vless.Servers.pingMs(ms: String(ping)) : MTStrings.Vless.Servers.pingFailed
                }
                rows.append(MTVlessRow(id: rowId, kind: .check(title: server.name, label: label, checked: server.id == selectedId)))
                let serverId = server.id
                model.tap[rowId] = {
                    MTVlessSettings.selectedServer.set(serverId)
                }
            }
            let settingsId = "sub.\(subscription.id).settings"
            rows.append(MTVlessRow(id: settingsId, kind: .disclosure(title: MTStrings.Vless.Servers.settings, label: "")))
            let subscriptionId = subscription.id
            model.tap[settingsId] = {
                push(mtVlessMakeSubscriptionController(context: context, subscriptionId: subscriptionId))
            }
            rows.append(MTVlessRow(id: "sub.\(subscription.id).info", kind: .footer(MTVlessText.subscriptionInfo(subscription))))
            model.sections.append(rows)
        }
        return model
    }
    let controller = mtVlessMakeListController(context: context, model: model)
    weakController = controller
    return controller
}

func mtVlessMakeAddController(context: AccountContext) -> ViewController {
    weak var weakController: ViewController?
    struct State: Equatable {
        var link = ""
        var name = ""
        var loading = false
        var error: String?
    }
    let state = ValuePromise(State(), ignoreRepeated: true)
    let stateValue = Atomic(value: State())
    let update: ((inout State) -> Void) -> Void = { f in
        state.set(stateValue.modify { current in
            var current = current
            f(&current)
            return current
        })
    }
    let addDisposable = MetaDisposable()

    let model = combineLatest(queue: .mainQueue(), state.get(), MTLocalization.shared.languageCodeSignal)
    |> map { state, _ -> MTVlessScreenModel in
        var model = MTVlessScreenModel(title: MTStrings.Vless.Add.title)
        model.sections.append([
            MTVlessRow(id: "link.header", kind: .header(MTStrings.Vless.Add.linkHeader)),
            MTVlessRow(id: "link", kind: .multilineInput(text: state.link, placeholder: MTStrings.Vless.Add.linkPlaceholder)),
            MTVlessRow(id: "link.footer", kind: .footer(MTStrings.Vless.Add.linkFooter))
        ])
        model.sections.append([
            MTVlessRow(id: "name.header", kind: .header(MTStrings.Vless.Add.nameHeader)),
            MTVlessRow(id: "name", kind: .input(text: state.name, placeholder: MTStrings.Vless.Add.namePlaceholder))
        ])
        var actionRows: [MTVlessRow] = [MTVlessRow(id: "add", kind: .action(title: state.loading ? MTStrings.Vless.Add.adding : MTStrings.Vless.Add.add, destructive: false, enabled: !state.loading && !state.link.isEmpty))]
        if let error = state.error {
            actionRows.append(MTVlessRow(id: "error", kind: .footer(MTStrings.Vless.Add.failed(reason: error))))
        }
        model.sections.append(actionRows)
        model.text["link"] = { value in
            update { $0.link = value }
        }
        model.text["name"] = { value in
            update { $0.name = value }
        }
        model.tap["add"] = {
            let current = stateValue.with { $0 }
            if current.loading || current.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
            update {
                $0.loading = true
                $0.error = nil
            }
            addDisposable.set((MTVlessController.shared.addSubscription(input: current.link, name: current.name)
            |> deliverOnMainQueue).start(next: { subscription in
                if MTVlessSettings.selectedServer.value.isEmpty, let first = subscription.servers.first {
                    MTVlessSettings.selectedServer.set(first.id)
                }
                weakController?.dismiss()
            }, error: { error in
                update {
                    $0.loading = false
                    $0.error = MTVlessText.error(error)
                }
            }))
        }
        return model
    }
    let controller = mtVlessMakeListController(context: context, model: model)
    controller.navigationPresentation = .modal
    weakController = controller
    return controller
}

func mtVlessMakeSubscriptionController(context: AccountContext, subscriptionId: String) -> ViewController {
    weak var weakController: ViewController?
    // Text edits stay in the screen until «Готово»: no write per keystroke.
    let draftName = Atomic<String?>(value: nil)
    let draftURL = Atomic<String?>(value: nil)
    let refreshDisposable = MetaDisposable()

    let model = combineLatest(queue: .mainQueue(), MTVlessStore.shared.subscriptionsSignal, MTLocalization.shared.languageCodeSignal)
    |> map { subscriptions, _ -> MTVlessScreenModel in
        var model = MTVlessScreenModel(title: MTStrings.Vless.Subscription.title)
        guard let subscription = subscriptions.first(where: { $0.id == subscriptionId }) else {
            return model
        }
        model.sections.append([
            MTVlessRow(id: "name.header", kind: .header(MTStrings.Vless.Subscription.nameHeader)),
            MTVlessRow(id: "name", kind: .input(text: draftName.with { $0 } ?? subscription.name, placeholder: MTStrings.Vless.Add.namePlaceholder))
        ])
        model.text["name"] = { value in
            let _ = draftName.swap(value)
        }
        if let url = subscription.url {
            model.sections.append([
                MTVlessRow(id: "url.header", kind: .header(MTStrings.Vless.Subscription.urlHeader)),
                MTVlessRow(id: "url", kind: .multilineInput(text: draftURL.with { $0 } ?? url, placeholder: MTStrings.Vless.Add.linkPlaceholder))
            ])
            model.text["url"] = { value in
                let _ = draftURL.swap(value)
            }
            var intervalRows: [MTVlessRow] = [MTVlessRow(id: "interval.header", kind: .header(MTStrings.Vless.Subscription.intervalHeader))]
            for interval in MTVlessUpdateInterval.allCases {
                let rowId = "interval.\(interval.rawValue)"
                intervalRows.append(MTVlessRow(id: rowId, kind: .check(title: MTVlessText.interval(interval), label: "", checked: subscription.updateInterval == interval)))
                model.tap[rowId] = {
                    MTVlessController.shared.updateSubscription(id: subscriptionId, { $0.updateInterval = interval })
                }
            }
            intervalRows.append(MTVlessRow(id: "interval.footer", kind: .footer(MTStrings.Vless.Subscription.intervalFooter)))
            model.sections.append(intervalRows)
            model.sections.append([MTVlessRow(id: "refresh", kind: .action(title: MTStrings.Vless.Subscription.refresh, destructive: false, enabled: true))])
            model.tap["refresh"] = {
                refreshDisposable.set(MTVlessController.shared.refresh(subscriptionId: subscriptionId).start())
            }
        }
        model.sections.append([
            MTVlessRow(id: "delete", kind: .action(title: MTStrings.Vless.Subscription.delete, destructive: true, enabled: true)),
            MTVlessRow(id: "info", kind: .footer(MTVlessText.subscriptionInfo(subscription)))
        ])
        let name = subscription.name
        model.tap["delete"] = {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(context: context, title: nil, text: MTStrings.Vless.Subscription.deleteConfirm(name: name), actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: MTStrings.Vless.Subscription.delete, action: {
                    MTVlessController.shared.removeSubscription(id: subscriptionId)
                    let _ = weakController?.navigationController?.popViewController(animated: true)
                })
            ])
            weakController?.present(alert, in: .window(.root))
        }
        model.rightButton = (MTStrings.Vless.Subscription.save, {
            let name = draftName.swap(nil)
            let url = draftURL.swap(nil)
            var urlChanged = false
            MTVlessController.shared.updateSubscription(id: subscriptionId, { subscription in
                if let name {
                    subscription.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let url, subscription.url != nil {
                    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && trimmed != subscription.url {
                        subscription.url = trimmed
                        subscription.lastError = nil
                        urlChanged = true
                    }
                }
            })
            if urlChanged {
                refreshDisposable.set(MTVlessController.shared.refresh(subscriptionId: subscriptionId).start())
            }
            let _ = weakController?.navigationController?.popViewController(animated: true)
        })
        return model
    }
    let controller = mtVlessMakeListController(context: context, model: model)
    weakController = controller
    return controller
}
