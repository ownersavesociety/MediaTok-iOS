import Foundation
import Display
import SwiftSignalKit
import AccountContext
import MTCore
import MTHooks
import MTSettingsUI
import MTFeaturesShared

/// Entry point of the MTVless feature module («Ещё › VPN по подписке»). Owner: MediaTok.
public enum MTVlessModule {
    static let serversTab = MTMenuTabID("vless.servers")
    static let mainSection = MTMenuSectionID("vless.main")
    static let optionsSection = MTMenuSectionID("vless.options")

    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        MTVlessSettings.declare()
        let _ = MTVlessLegacy.loopbackPort

        MTVlessModule.registerMenu()

        // «О приложении › Сторонние компоненты» (MediaTok spec R5): the core is Xray-core
        // (MPL-2.0) with its Go dependencies (BSD / MIT / Apache-2.0); listed only in builds that
        // carry the core.
        MTMenuRegistry.register(license: MTMenuLicense(
            id: "vless.xrayCore",
            name: "Xray-core",
            license: "MPL-2.0",
            url: "https://github.com/XTLS/Xray-core",
            note: { MTStrings.Vless.License.note },
            order: 100,
            isVisible: {
                return MTXrayCore.isBundled
            }
        ))

        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTVlessController.shared.attach(context: context)
        }, order: 0)

        // Telegram's proxy screen links here: with the VPN on, Telegram's proxy is the core's loopback
        // entry, which that screen does not list.
        MTVpnEntryPoint.makeScreen = { context in
            guard let context = context as? AccountContext else {
                return nil
            }
            return mtVlessMakeServersController(context: context)
        }
        MTVpnEntryPoint.stateText = {
            if !MTXrayCore.isBundled {
                return MTStrings.Vless.ProxyEntry.notBundled
            }
            return MTVlessSettings.enabled.value ? MTStrings.Vless.ProxyEntry.on : MTStrings.Vless.ProxyEntry.off
        }

        MTVlessLegacy.registerMigration()

        // Starts the core in the background if the VPN was on (nothing is loaded otherwise).
        MTVlessController.shared.setup()

        // Bridge from MediaTok Wave 3 custom VPN slot into MTVlessController
        let _ = NotificationCenter.default.addObserver(forName: Notification.Name("mediatok.vpn.apply_uri"), object: nil, queue: .main) { note in
            guard let uri = note.userInfo?["uri"] as? String, !uri.isEmpty else { return }
            let _ = (MTVlessController.shared.addSubscription(input: uri, name: "MediaTok VPN")
            |> deliverOnMainQueue).start(next: { sub in
                for existing in MTVlessStore.shared.subscriptions where existing.name == "MediaTok VPN" && existing.id != sub.id {
                    MTVlessController.shared.removeSubscription(id: existing.id)
                }
                if let first = sub.servers.first {
                    MTVlessSettings.selectedServer.set(first.id)
                    if MTXrayCore.isBundled {
                        MTVlessSettings.enabled.set(true)
                    }
                }
            }, error: { err in
                MTLog.warning("vless", "mediatok.vpn.apply_uri failed: \(MTVlessController.errorCode(err))")
            })
        }
    }

    private static func registerMenu() {
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: MTVlessModule.mainSection,
            screen: .tab(.moreVpn),
            order: 300,
            footer: { _ in
                return MTXrayCore.isBundled ? nil : MTStrings.Vless.Status.notBundled
            }
        ))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: MTVlessModule.optionsSection,
            screen: .tab(.moreVpn),
            order: 400,
            footer: { _ in MTStrings.Vless.Menu.footer }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "vless.enabled",
            section: MTVlessModule.mainSection,
            order: 100,
            title: { MTStrings.Vless.Menu.enable },
            subtitle: { MTStrings.Vless.Menu.enableInfo },
            kind: .toggle(.global(MTVlessSettings.enabled)),
            searchKeywords: { [MTStrings.Vless.Menu.keywords] },
            isEnabled: { _ in
                // Switching on needs the core in this build and a chosen server; switching off is
                // always possible.
                if MTVlessSettings.enabled.value {
                    return true
                }
                return MTXrayCore.isBundled && !MTVlessSettings.selectedServer.value.isEmpty
            }
        ))

        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: MTVlessModule.serversTab,
                parent: .tab(.moreVpn),
                title: { MTStrings.Vless.Menu.servers },
                makeScreen: { context in
                    return mtVlessMakeServersController(context: context.context)
                },
                searchKeywords: { [MTStrings.Vless.Menu.keywords] }
            ),
            linkIn: MTVlessModule.mainSection,
            order: 200,
            subtitle: { MTStrings.Vless.Menu.serversInfo },
            icon: .bundle("Chat/Context Menu/Globe"),
            label: { _ in
                let id = MTVlessSettings.selectedServer.value
                if id.isEmpty {
                    return MTStrings.Vless.Menu.noServer
                }
                return MTVlessStore.shared.server(id: id)?.1.name
            }
        )

        MTMenuRegistry.register(MTMenuRow(
            id: "vless.proxyBypassOnVpn",
            section: MTVlessModule.optionsSection,
            order: 100,
            title: { MTStrings.Vless.Menu.bypass },
            subtitle: { MTStrings.Vless.Menu.bypassInfo },
            kind: .toggle(.global(MTNetworkSpoofSharedSettings.proxyBypassOnVpn))
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "vless.sendHwid",
            section: MTVlessModule.optionsSection,
            order: 200,
            title: { MTStrings.Vless.Menu.hwid },
            subtitle: { MTStrings.Vless.Menu.hwidInfo },
            kind: .toggle(.global(MTVlessSettings.sendHwid))
        ))
    }
}
