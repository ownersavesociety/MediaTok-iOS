import Foundation
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import LocalizedPeerData
import MTCore
import MTSettingsUI
import MTFeaturesShared

/// «Настройки по аккаунтам» on top of MTCore's scopes. Which settings follow the account is decided
/// once, where each setting is declared (ghost mode, exceptions, delayed sending, chat lists of
/// «Безопасность» … are per account; everything else is shared) — there is no mode that copies the
/// whole key-value store around on every switch any more. What the user can do here is take another account's
/// own settings into this one, in one write, through the same export → preview → apply path as
/// «Настройки MediaTok» (secrets are never part of it).
///
/// Folder-bound settings are left out: folder ids belong to an account, and the same id in another
/// account is some other folder (legacy format secret-folder bug).
enum MTAccountSettingsCopy {
    /// Account-scoped keys of `source` written into `target`. Returns how many values changed.
    static func copy(from source: MTAccountID, to target: MTAccountID) -> Int {
        let data = MTSettingsStore.shared.exportData(accounts: [source])
        guard var object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return 0
        }
        object["global"] = [String: Any]()
        object["appGroup"] = [String: Any]()
        if var accounts = object["accounts"] as? [String: Any], var values = accounts[source.stringValue] as? [String: Any] {
            for key in Array(values.keys) where MTAccountSettingsCopy.isAccountBound(key) {
                values.removeValue(forKey: key)
            }
            accounts[source.stringValue] = values
            object["accounts"] = accounts
        }
        guard let filtered = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return 0
        }
        guard let diff = try? MTSettingsStore.shared.importPreview(filtered, accountMapping: [source: target]), !diff.isEmpty else {
            return 0
        }
        MTSettingsStore.shared.applyImport(diff)
        return diff.changes.count
    }

    private static func isAccountBound(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return lowercased.contains("folder")
    }

    /// The menu action: pick the account to copy from, confirm, copy.
    static func present(_ menuContext: MTMenuContext) {
        let context = menuContext.context
        let target = context.account.id.mt
        let _ = (context.sharedContext.activeAccountsWithInfo
        |> take(1)
        |> deliverOnMainQueue).start(next: { _, accounts in
            let others = accounts.filter { $0.account.id != context.account.id }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            if others.isEmpty {
                menuContext.presentToast(MTStrings.Security.AccountSettings.noOtherAccounts)
                return
            }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = [ActionSheetTextItem(title: MTStrings.Security.AccountSettings.copyPickerTitle)]
            for info in others {
                let name = info.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                let source = info.account.id.mt
                items.append(ActionSheetButtonItem(title: name, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    let alert = textAlertController(context: context, title: MTStrings.Security.AccountSettings.copyConfirmTitle, text: MTStrings.Security.AccountSettings.copyConfirmText(name: name), actions: [
                        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .defaultAction, title: MTStrings.Security.AccountSettings.copyConfirmAction, action: {
                            let changed = MTAccountSettingsCopy.copy(from: source, to: target)
                            menuContext.presentToast(MTStrings.Security.AccountSettings.copied(count: changed))
                        })
                    ])
                    menuContext.present(alert)
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })])
            ])
            menuContext.present(actionSheet)
        })
    }
}
