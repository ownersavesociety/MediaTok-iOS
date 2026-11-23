import Foundation
import Display
import AccountContext
import MTSettingsUI

// MEDIATOK: MediaTok's menu in Telegram's own settings search. The places come from MTSettingsUI
// (`mtSettingsSearchItems`), the same index the MediaTok root screen searches; breadcrumbs start
// at «MediaTok», and opening a result pushes the screen and highlights the row — through the
// menu's access gates (a locked category asks for the code first, possibly pushing later).
func mtSettingsSearchableItems(context: AccountContext) -> [SettingsSearchableItem] {
    return mtSettingsSearchItems(context: context).map { item in
        let open = item.open
        return SettingsSearchableItem(
            id: item.id,
            title: item.title,
            alternate: item.keywords,
            icon: .mediatok,
            breadcrumbs: item.breadcrumbs,
            present: { context, _, present in
                open(context, { controller in
                    present(.push, controller)
                })
            }
        )
    }
}
