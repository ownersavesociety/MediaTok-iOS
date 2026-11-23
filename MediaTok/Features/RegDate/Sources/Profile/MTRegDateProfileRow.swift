import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import UndoUI
import MTCore
import MTHooks

/// «Дата регистрации» in the info section of every user's and bot's profile, the own profile too
/// (that is where the ID row is; the Settings tab has no info rows). The value follows `precision` and
/// `source`, the account's age is on the right, a long press copies it; a tap does nothing, like the
/// ID row. Off (`regDate.show`): no row, no work, no request.
enum MTRegDateProfileRow {
    static func register() {
        // After the ID / data center / dates of MTProfileDecor (order 100).
        MTPeerInfoHooks.infoRows.register({ info in
            return MTRegDateProfileRow.rows(info)
        }, order: 110)
    }

    /// Asked on every layout of the profile: memory and snapshots only (MTRegDate).
    private static func rows(_ info: MTPeerInfoContext) -> [MTPeerInfoRow] {
        // A secret chat's profile describes the user too.
        guard case let .user(user) = info.peer else {
            return []
        }
        let context = info.context
        if let customDate = MTVisualProfileStore.shared.customRegDate(for: user.id.mtKey) {
            let ageText = MTRegDateProfileRow.computeAge(from: customDate)
            return [MTPeerInfoRow(id: "regDate.profile", label: MTStrings.RegDate.Profile.label, text: customDate, rightLabel: ageText, longTapAction: { [weak controller = info.controller] in
                MTRegDateProfileRow.copy(customDate, context: context, controller: controller)
            })]
        }
        if !MTRegDateSettings.show.value {
            return []
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        guard let row = MTRegDate.shared.row(context: context, peerId: user.id, cachedData: info.cachedData, sourceMessageId: info.sourceMessageId, sourceChatPeerId: info.sourceChatPeerId, controller: info.controller, strings: presentationData.strings) else {
            return []
        }
        let copyText = row.texts.copy
        return [MTPeerInfoRow(id: "regDate.profile", label: MTStrings.RegDate.Profile.label, text: row.texts.value, rightLabel: row.texts.age, longTapAction: { [weak controller = info.controller] in
            MTRegDateProfileRow.copy(copyText, context: context, controller: controller)
        })]
    }

    private static func computeAge(from customDate: String) -> String? {
        let formats = ["dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm", "dd.MM.yyyy", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        var parsed: Date?
        for fmt in formats {
            df.dateFormat = fmt
            if let d = df.date(from: customDate) {
                parsed = d
                break
            }
        }
        guard let date = parsed else {
            return nil
        }
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date, to: Date())
        let y = max(0, comps.year ?? 0)
        let m = max(0, comps.month ?? 0)
        let d = max(0, comps.day ?? 0)
        if y > 0 {
            return m > 0 ? "\(y) г. \(m) мес." : "\(y) г."
        } else if m > 0 {
            return "\(m) мес."
        } else {
            return "\(d) д."
        }
    }

    private static func copy(_ text: String, context: AccountContext, controller: ViewController?) {
        UIPasteboard.general.string = text
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .copy(text: MTStrings.RegDate.Profile.copied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in
            return false
        }), in: .current)
    }
}
