import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import MTCore
import MTHooks
import MTSettingsUI

/// Entry point of the MTNetworkSpoof feature module («Приватность › Подмены»). Owner: MediaTok.
public enum MTNetworkSpoofModule {
    static let phoneTab = MTMenuTabID("networkSpoof.phone")
    static let profilesTab = MTMenuTabID("networkSpoof.profiles")

    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        MTNetworkSpoofSettings.declare()

        // Own number, on this device only. Hiding the number wins over replacing it.
        MTPeerInfoHooks.displayedPhoneNumber.register({ request in
            guard request.isAccountPeer else {
                return nil
            }
            let account = request.context.account.id.mt
            guard MTNetworkSpoofSettings.fakePhoneEnabled.value(for: account) else {
                return nil
            }
            let number = MTNetworkSpoofSettings.fakePhone.value(for: account)
            if number.isEmpty {
                return nil
            }
            return .replaced(number)
        }, order: 100)

        // Profile substitution: the whole target peer (namespace included) is opened, so the
        // profile's chat location, shared media and actions all belong to the target.
        MTPeerInfoHooks.redirectPeer.register({ context, peerId in
            if peerId == context.account.peerId {
                return nil
            }
            let account = context.account.id.mt
            guard MTNetworkSpoofSettings.profileRedirectEnabled.value(for: account) else {
                return nil
            }
            guard let target = MTNetworkSpoofSettings.profileRedirects.value(for: account)[peerId.mtKey.stringValue] else {
                return nil
            }
            let targetId = PeerId(mtKey: target)
            return targetId == peerId ? nil : targetId
        }, order: 0)

        MTNetworkSpoofModule.registerMenu()
        MTVisualProfileSupport.registerHooks()
        MTNetworkSpoofMigrations.register()
    }

    private static let visualTab = MTMenuTabID("networkSpoof.visual")

    private static func registerMenu() {
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: MTNetworkSpoofModule.visualTab,
                parent: .tab(.privacySpoofing),
                title: { MTStrings.NetworkSpoof.Visual.tabTitle },
                makeScreen: { context in
                    return mtSpoofMakeVisualListController(context: context.context)
                },
                searchKeywords: { [MTStrings.NetworkSpoof.Visual.tabKeywords] }
            ),
            linkIn: .main(of: .privacySpoofing),
            order: 100,
            subtitle: { MTStrings.NetworkSpoof.Visual.tabInfo },
            icon: .bundle("Chat/Context Menu/Edit"),
            label: { _ in
                let count = MTVisualProfileStore.shared.allOverrides().count
                return count > 0 ? "\(count)" : MTStrings.NetworkSpoof.Menu.off
            }
        )
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: MTNetworkSpoofModule.phoneTab,
                parent: .tab(.privacySpoofing),
                title: { MTStrings.NetworkSpoof.Phone.title },
                makeScreen: { context in
                    return mtSpoofMakePhoneController(context: context.context)
                },
                searchKeywords: { [MTStrings.NetworkSpoof.Phone.keywords] }
            ),
            linkIn: .main(of: .privacySpoofing),
            order: 200,
            subtitle: { MTStrings.NetworkSpoof.Phone.info },
            icon: .bundle("Chat/Context Menu/Call"),
            label: { context in
                return MTNetworkSpoofSettings.fakePhoneEnabled.value(for: context.accountID) ? MTStrings.NetworkSpoof.Menu.on : MTStrings.NetworkSpoof.Menu.off
            }
        )
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: MTNetworkSpoofModule.profilesTab,
                parent: .tab(.privacySpoofing),
                title: { MTStrings.NetworkSpoof.Profiles.title },
                makeScreen: { context in
                    return mtSpoofMakeProfilesController(context: context.context)
                },
                searchKeywords: { [MTStrings.NetworkSpoof.Profiles.keywords] }
            ),
            linkIn: .main(of: .privacySpoofing),
            order: 300,
            subtitle: { MTStrings.NetworkSpoof.Profiles.info },
            icon: .bundle("Chat/Context Menu/User"),
            label: { context in
                return MTNetworkSpoofSettings.profileRedirectEnabled.value(for: context.accountID) ? MTStrings.NetworkSpoof.Menu.on : MTStrings.NetworkSpoof.Menu.off
            }
        )
    }
}
