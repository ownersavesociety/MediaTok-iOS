import Foundation
import UIKit
import Display
import AccountContext
import MTCore

/// A third-party component bundled with MediaTok (a library), listed on «О приложении › Сторонние
/// компоненты» with its license. Registered by the feature that ships it. Fonts are not among them:
/// MediaTok uses only the fonts of iOS.
public struct MTMenuLicense {
    /// Unique, "<feature>.<component>".
    public let id: String
    /// Proper names, shown as is in every language («Xray-core»).
    public let name: String
    /// SPDX identifier(s) («MPL-2.0»), shown on the right.
    public let license: String
    /// The license text or the component's source, opened on tap.
    public let url: String
    /// What it is in MediaTok, localized at display time («Ядро «VPN по подписке»»).
    public let note: (() -> String)?
    /// Sparse, step 100.
    public let order: Int
    /// nil = always; e.g. only when the component is in this build.
    public let isVisible: (() -> Bool)?

    public init(id: String, name: String, license: String, url: String, note: (() -> String)? = nil, order: Int, isVisible: (() -> Bool)? = nil) {
        self.id = id
        self.name = name
        self.license = license
        self.url = url
        self.note = note
        self.order = order
        self.isVisible = isVisible
    }
}

extension MTMenuTabID {
    /// «О приложении › Сторонние компоненты» (shown once a feature registered a component).
    public static let moreAboutThirdParty = MTMenuTabID("more.about.thirdParty")
}

extension MTMenuSectionID {
    public static let aboutThirdPartyComponents = MTMenuSectionID("more.about.thirdParty.components")
}

/// The tab and its section; called from `MTSettingsUI.register()` before the features.
func mtRegisterLicensesTab() {
    MTMenuRegistry.register(
        tab: MTMenuTabDescriptor(
            id: .moreAboutThirdParty,
            parent: .tab(.moreAbout),
            title: { MTStrings.Menu.About.thirdParty },
            searchKeywords: { [MTStrings.Menu.About.licenseHeader] }
        ),
        linkIn: .aboutLicense,
        order: 200,
        subtitle: { MTStrings.Menu.About.thirdPartyInfo },
        icon: .bundle("Chat/Context Menu/Info")
    )
    MTMenuRegistry.register(section: MTMenuSectionDescriptor(
        id: .aboutThirdPartyComponents,
        screen: .tab(.moreAboutThirdParty),
        order: 300,
        footer: { _ in MTStrings.Menu.About.thirdPartyFooter }
    ))
}

func mtRegisterLicense(_ license: MTMenuLicense) {
    let url = license.url
    let licenseName = license.license
    var isVisible: ((MTMenuContext) -> Bool)?
    if let visible = license.isVisible {
        isVisible = { _ in
            return visible()
        }
    }
    MTMenuRegistry.register(MTMenuRow(
        id: "menu.license.\(license.id)",
        section: .aboutThirdPartyComponents,
        order: license.order,
        title: { license.name },
        subtitle: license.note,
        kind: .action({ menuContext in
            menuContext.context.sharedContext.applicationBindings.openUrl(url)
        }),
        isVisible: isVisible,
        searchKeywords: { [licenseName] },
        label: { _ in licenseName }
    ))
}
