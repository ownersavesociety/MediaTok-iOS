import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PromptUI
import MTCore
import MTSettingsUI

// More › Fake gifts › Stars: «Локальные звёзды» — the Stars balance this device shows instead of the
// real one (`MTStarsHooks.displayedBalance` in TelegramCore; TON is not touched). Only the number on
// screen changes: what Stars pay for is still checked by the server against the real balance.
// Restored 2026-11-01 at the owner's word: legacy format had it in «Кастомизация › Сообщения»
// (`GG.fontCustomization.localStarsBalance`), the client had lost it.

enum MTLocalStars {
    /// nil = the real balance.
    static let balance = MTSetting<Int64?>("fakeGifts.localStars", default: nil)

    static let section = MTMenuSectionID("more.fakeGifts.stars")

    private static var settingDisposable: Disposable?

    static func declare() {
        let _ = MTLocalStars.balance
    }

    /// Main thread, before `MTHookRegistry.freeze()`.
    static func register() {
        MTStarsHooks.displayedBalance.register({ _ in
            return MTLocalStars.balance.value.map { StarsAmount(value: $0, nanos: 0) }
        })
        // A balance already on screen follows the change at once.
        MTLocalStars.settingDisposable = (MTLocalStars.balance.signal
        |> distinctUntilChanged).start(next: { _ in
            MTStarsHooks.invalidate()
        })

        MTMigrations.registerGlobal(id: "fakeGifts.localStars.v1") { legacy in
            let key = "GG.fontCustomization.localStarsBalance"
            if let number = legacy.object(key) as? NSNumber {
                MTLocalStars.balance.set(max(0, number.int64Value))
            }
            legacy.removeLegacyKey(key)
        }

        MTLocalStars.registerMenu()
    }

    private static func registerMenu() {
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: MTLocalStars.section,
            screen: .tab(.moreFakeGifts),
            order: 300,
            header: { MTStrings.FakeGifts.Stars.header },
            footer: { _ in MTStrings.FakeGifts.Stars.footer }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "fakeGifts.localStars",
            section: MTLocalStars.section,
            order: 100,
            title: { MTStrings.FakeGifts.Stars.title },
            subtitle: { MTStrings.FakeGifts.Stars.info },
            icon: .bundle("Chat/Context Menu/Stars"),
            kind: .action({ context in
                MTLocalStars.edit(menuContext: context)
            }),
            searchKeywords: { [MTStrings.FakeGifts.Stars.keywords] },
            label: { context in
                guard let value = MTLocalStars.balance.value else {
                    return nil
                }
                return MTLocalStars.formatted(value, groupingSeparator: context.presentationData.dateTimeFormat.groupingSeparator)
            }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "fakeGifts.localStars.reset",
            section: MTLocalStars.section,
            order: 200,
            title: { MTStrings.FakeGifts.Stars.reset },
            kind: .action({ _ in
                MTLocalStars.balance.set(nil)
            }),
            isVisible: { _ in MTLocalStars.balance.value != nil },
            isDestructive: true
        ))
    }

    private static func edit(menuContext: MTMenuContext) {
        let current = MTLocalStars.balance.value.map { "\($0)" }
        menuContext.present(promptController(context: menuContext.context, text: MTStrings.FakeGifts.Stars.title, subtitle: MTStrings.FakeGifts.Stars.promptText, value: current, placeholder: MTStrings.FakeGifts.Stars.placeholder, characterLimit: 32, apply: { value in
            guard let value else {
                return
            }
            MTLocalStars.balance.set(MTLocalStars.parse(value))
        }))
    }

    /// The digits of `text` as a balance, at most `Int64.max`; nil when there are none (the real
    /// balance again).
    static func parse(_ text: String) -> Int64? {
        var result: Int64?
        for scalar in text.unicodeScalars {
            guard scalar.value >= 48 && scalar.value <= 57 else {
                continue
            }
            let digit = Int64(scalar.value - 48)
            let value = result ?? 0
            if value > (Int64.max - digit) / 10 {
                return Int64.max
            }
            result = value * 10 + digit
        }
        return result
    }

    static func formatted(_ value: Int64, groupingSeparator: String) -> String {
        let digits = String(value)
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 {
                result += groupingSeparator
            }
            result.append(character)
        }
        return result
    }
}
