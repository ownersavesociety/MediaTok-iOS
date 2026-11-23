import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import SwiftSignalKit
import SettingsUI
import PasscodeCore
import MTCore
import MTHooks
import MTSettingsUI
import MTFeaturesShared

/// «Код-пароль» on top of Telegram's own passcode (no second implementation of the screen):
/// - Telegram's screen opens from the menu (and asks Telegram's own passcode, as always);
/// - «Заблокировать сейчас» — the same manual lock as the lock in the «Чаты» header, which stays;
/// - «Блокировать при каждом запуске» — locked on every cold start, decided before the first lock
///   evaluation (`MTPasscodeHooks.locksOnLaunch` in AppLock's init), not in the first «became active»;
/// - «Больше вариантов автоблокировки» — extra values in Telegram's own menu, which keeps «Отключена»
///   and writes once, on selection (the old slider wrote a transaction per tick).
enum MTPasscodeExtras {
    /// Seconds; 0 = «Отключена» stays first.
    private static let extraValues: [Int32] = [2 * 60, 10 * 60, 15 * 60, 30 * 60, 2 * 60 * 60, 8 * 60 * 60, 24 * 60 * 60]

    static func register() {
        MTPasscodeHooks.locksOnLaunch.register({
            return MTSecuritySettings.passcodeLockOnLaunch.value && MTSecuritySettings.passcodeIsSet.value
        })
        MTPasscodeUIHooks.autolockValues.register({ values in
            guard MTSecuritySettings.passcodeMoreAutolockOptions.value else {
                return values
            }
            var result = values.filter { $0 != 0 }
            result.append(contentsOf: MTPasscodeExtras.extraValues)
            return [0] + Set(result).sorted()
        })
        MTPasscodeUIHooks.autolockTitle.register({ timeout in
            if timeout <= 0 {
                return nil
            }
            if timeout % (60 * 60) == 0 {
                return MTStrings.Security.Passcode.autolockHours(count: Int(timeout / (60 * 60)))
            }
            return MTStrings.Security.Passcode.autolockMinutes(count: Int(max(1, timeout / 60)))
        })
    }

    /// Telegram's passcode screen through Telegram's own entry (set-up or passcode check first), as
    /// «Конфиденциальность» opens it.
    static func openTelegramPasscode(_ menuContext: MTMenuContext) {
        let context = menuContext.context
        let navigationController = menuContext.navigationController
        let _ = (passcodeOptionsAccessController(context: context, replaceController: { [weak navigationController] controller in
            navigationController?.replaceTopController(controller, animated: true)
        }, authorizationCompleted: { [weak navigationController] result in
            guard case let .success(session) = result else {
                return
            }
            guard let navigationController else {
                session.invalidate()
                return
            }
            navigationController.replaceTopController(passcodeOptionsController(context: context, settingsSession: session), animated: true)
        })
        |> deliverOnMainQueue).start(next: { controller in
            if let controller {
                menuContext.push(controller)
            }
        })
    }

    /// «Заблокировать сейчас».
    static func lockNow(_ menuContext: MTMenuContext) {
        if !MTAuthEnvironment.shared.state.hasTelegramPasscode {
            menuContext.presentToast(MTStrings.Security.Passcode.lockNeedsPasscode)
            return
        }
        menuContext.context.sharedContext.appLockContext.lock()
    }
}
