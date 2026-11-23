import Foundation
import MTCore
import MTHooks
import MTFeaturesShared

/// «Через 5 секунд» in Telegram's auto-lock menu (MTPasscodeUIHooks, the points MediaTok's extra values
/// use). The app lock renews its «last active» mark every 2.5 s while 5 s is the chosen timeout
/// (`MTExtrasPolicy.appLockActivityRenewInterval(autolockTimeout:)`), so a short leave is measured fairly.
enum MTExtrasAutolock {
    static let fiveSeconds: Int32 = 5

    static func register() {
        MTPasscodeUIHooks.autolockValues.register({ values in
            if !MTExtrasSettings.autolockFiveSeconds.value {
                return values
            }
            var result = values.filter { $0 != 0 }
            result.append(MTExtrasAutolock.fiveSeconds)
            return [0] + Set(result).sorted()
        }, order: -100)
        // Before MediaTok's titles: they count whole minutes and would call 5 s «1 minute».
        MTPasscodeUIHooks.autolockTitle.register({ timeout in
            if timeout > 0 && timeout < 60 {
                return MTStrings.Extras.Autolock.seconds(count: Int(timeout))
            }
            return nil
        }, order: -100)
    }
}
