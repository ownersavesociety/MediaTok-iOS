import Foundation
import MTCore
import MTSettingsUI

/// The switch in «Оформление › Профиль и Настройки › Профиль», next to the ID and the dates.
enum MTRegDateMenu {
    /// The section MTAppearance declares («Профиль»); rows of other features join it by id.
    static let profileSection = MTMenuSectionID("appearance.profileSettings.profile")

    static func register() {
        // After «Показывать даты» (order 300).
        MTMenuRegistry.register(MTMenuRow(id: "regDate.show", section: MTRegDateMenu.profileSection, order: 350, title: { MTStrings.RegDate.Menu.title }, subtitle: { MTStrings.RegDate.Menu.subtitle }, kind: .toggle(.global(MTRegDateSettings.show)), searchKeywords: { [MTStrings.RegDate.Menu.keywords] }))
    }
}
