import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import ItemListUI
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

/// Clean Chat Interface Studio: Zero-Bloat 1-Tap Preset (#110), Compact Density (#107),
/// Custom Read Checkmarks (#108), Built-in Guard / Counter Shortcuts (#71/#58), and 4K 60 FPS Video Toggle (#83).
enum MTMediaTokLiquidUI {
    static let liquidPresetKey = "mediatok.liquid_glass.preset.v1"
    static let zeroBloatKey = "mediatok.ui.zero_bloat.v1"
    static let compactModeKey = "mediatok.ui.compact_mode.v1"
    static let checkmarkStyleKey = "mediatok.checkmarks.style.v1"
    static let video4k60Key = "mediatok.video.4k60.v1"
    private static let smearMigrationKey = "mediatok.liquid_glass.cleaned.v2"

    static let checkmarkStyles: [(id: String, title: String)] = [
        ("default", "Стандартные галочки (✓✓)"),
        ("bolt", "Молнии"),
        ("fire", "Огонь"),
        ("diamond", "Кристалл"),
        ("eyes", "Глаза"),
        ("heart", "Сердечки"),
        ("star", "Звёзды"),
        ("minimal", "Минимал-точки (●)")
    ]

    static func register() {
        // Auto-heal broken edge blur/cyan smear from legacy Liquid Glass presets
        if !UserDefaults.standard.bool(forKey: MTMediaTokLiquidUI.smearMigrationKey) {
            UserDefaults.standard.set(true, forKey: MTMediaTokLiquidUI.smearMigrationKey)
            if MTMediaTokLiquidUI.currentLiquidPreset != "off" {
                UserDefaults.standard.set("off", forKey: MTMediaTokLiquidUI.liquidPresetKey)
                DispatchQueue.main.async {
                    MTMediaTokLiquidUI.applyMediaTokGlobalSettings([
                        "appearance.edges.style": MTEdgeStyle.off.rawValue,
                        "appearance.edges.color": ""
                    ])
                    MTThemeHooks.invalidate()
                }
            }
        }
        if UserDefaults.standard.string(forKey: MTMediaTokLiquidUI.checkmarkStyleKey) != nil {
            DispatchQueue.main.async {
                MTThemeHooks.invalidate()
            }
        }
    }

    static var currentLiquidPreset: String {
        return UserDefaults.standard.string(forKey: MTMediaTokLiquidUI.liquidPresetKey) ?? "off"
    }

    static var isZeroBloatEnabled: Bool {
        return UserDefaults.standard.bool(forKey: MTMediaTokLiquidUI.zeroBloatKey)
    }

    static var isCompactModeEnabled: Bool {
        return UserDefaults.standard.bool(forKey: MTMediaTokLiquidUI.compactModeKey)
    }

    static var currentCheckmarkStyle: String {
        return UserDefaults.standard.string(forKey: MTMediaTokLiquidUI.checkmarkStyleKey) ?? "default"
    }

    static var isVideo4k60Enabled: Bool {
        return UserDefaults.standard.bool(forKey: MTMediaTokLiquidUI.video4k60Key)
    }

    static func readMediaTokGlobalBool(_ key: String, fallback: Bool) -> Bool {
        let data = MTSettingsStore.shared.exportData(accounts: [])
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let global = obj["global"] as? [String: Any],
              let val = global[key] as? Bool else {
            return fallback
        }
        return val
    }

    static func applyMediaTokGlobalSettings(_ values: [String: Any]) {
        let root: [String: Any] = [
            "format": "mediatok.settings",
            "version": 1,
            "global": values,
            "appGroup": [:] as [String: Any],
            "accounts": [:] as [String: Any]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: []),
              let diff = try? MTSettingsStore.shared.importPreview(data) else {
            return
        }
        MTSettingsStore.shared.applyImport(diff)
    }

    static func setLiquidPreset(_ presetId: String) {
        UserDefaults.standard.set("off", forKey: MTMediaTokLiquidUI.liquidPresetKey)
        MTMediaTokLiquidUI.applyMediaTokGlobalSettings([
            "appearance.edges.style": MTEdgeStyle.off.rawValue,
            "appearance.edges.color": "",
            "appearance.bubbles.backgroundOpacity": 100.0,
            "appearance.bubbles.outlineOpacity": 0.0
        ])
        MTThemeHooks.invalidate()
    }

    static func setZeroBloatEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: MTMediaTokLiquidUI.zeroBloatKey)
        MTMediaTokLiquidUI.applyMediaTokGlobalSettings([
            "interface.chatList.hideStories": enabled,
            "interface.chatList.hideStoryRings": enabled,
            "interface.chatList.hideProxySponsor": enabled,
            "appearance.profile.hideStarRating": enabled,
            "appearance.messages.hideViewCounts": enabled,
            "appearance.messages.hideChannelComments": enabled,
            "appearance.theme.hideSeparators": enabled
        ])
        MTThemeHooks.invalidate()
    }

    static func setCompactModeEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: MTMediaTokLiquidUI.compactModeKey)
        MTMediaTokLiquidUI.applyMediaTokGlobalSettings([
            "interface.chatList.compact": enabled,
            "interface.chatList.previewLines": enabled ? "1" : "2",
            "interface.chatList.rowScale": enabled ? "85" : "100",
            "interface.chatList.avatarScale": enabled ? "85" : "100",
            "appearance.bubbles.editor": enabled,
            "appearance.bubbles.padding": enabled ? 7.0 : 11.0,
            "appearance.bubbles.hideTails": enabled
        ])
        MTThemeHooks.invalidate()
    }

    static func setCheckmarkStyle(_ styleId: String) {
        UserDefaults.standard.set(styleId, forKey: MTMediaTokLiquidUI.checkmarkStyleKey)
        MTThemeHooks.invalidate()
    }

    static func setVideo4k60Enabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: MTMediaTokLiquidUI.video4k60Key)
    }

    static func presentStudio(context: MTMenuContext) {
        let controller = MTMediaTokLiquidUI.makeStudioController(accountContext: context.context)
        if context.navigationController != nil {
            context.push(controller)
        } else {
            mtPushNativeController(controller, context: context.context)
        }
    }

    static func makeStudioController(accountContext: AccountContext) -> ItemListController {
        let revision = ValuePromise<Int>(0, ignoreRepeated: false)
        var revCount = 0
        let bump: () -> Void = {
            revCount += 1
            revision.set(revCount)
        }

        weak var weakController: ItemListController?
        let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
        |> map { _ -> MTNativeScreenModel in
            var screen = MTNativeScreenModel(title: "Интерфейс и Видео 4K")

            let activeCheckmark = MTMediaTokLiquidUI.currentCheckmarkStyle
            let activeCheckmarkTitle = MTMediaTokLiquidUI.checkmarkStyles.first(where: { $0.id == activeCheckmark })?.title ?? "Стандартные"

            // Section 0: Zero-Bloat / Compact / Counter / Call Confirm
            let zeroBloat = MTMediaTokLiquidUI.isZeroBloatEnabled
            let compact = MTMediaTokLiquidUI.isCompactModeEnabled
            let charCounter = MTMediaTokLiquidUI.readMediaTokGlobalBool("interface.inputBar.characterCounter", fallback: false)
            let confirmCalls = MTMediaTokWave6Tools.isCallConfirmEnabled || MTMediaTokLiquidUI.readMediaTokGlobalBool("ghostMode.confirmCalls", fallback: false)

            screen.sections.append([
                MTNativeRow(id: "ui.header", kind: .header("Чистый интерфейс и плотность")),
                MTNativeRow(id: "ui.zeroBloat", kind: .toggle(title: "Zero-Bloat (убрать всё лишнее)", value: zeroBloat, enabled: true)),
                MTNativeRow(id: "ui.compact", kind: .toggle(title: "Компактный режим чатов", value: compact, enabled: true)),
                MTNativeRow(id: "ui.charCounter", kind: .toggle(title: "Счётчик символов при вводе", value: charCounter, enabled: true)),
                MTNativeRow(id: "ui.confirmCalls", kind: .toggle(title: "Подтверждение звонков", value: confirmCalls, enabled: true)),
                MTNativeRow(id: "ui.footer", kind: .footer("Zero-Bloat скрывает Сторис, кольца, звёздный рейтинг, спонсоров прокси, счётчики просмотров и разделители."))
            ])

            screen.toggle["ui.zeroBloat"] = { isOn in
                MTMediaTokLiquidUI.setZeroBloatEnabled(isOn)
                bump()
                mtPresentNativeToast(context: accountContext, from: weakController, text: isOn ? "Режим Zero-Bloat включён" : "Режим Zero-Bloat выключен")
            }
            screen.toggle["ui.compact"] = { isOn in
                MTMediaTokLiquidUI.setCompactModeEnabled(isOn)
                bump()
                mtPresentNativeToast(context: accountContext, from: weakController, text: isOn ? "Компактный режим включён" : "Компактный режим выключен")
            }
            screen.toggle["ui.charCounter"] = { isOn in
                MTMediaTokLiquidUI.applyMediaTokGlobalSettings(["interface.inputBar.characterCounter": isOn])
                bump()
                mtPresentNativeToast(context: accountContext, from: weakController, text: isOn ? "Счётчик символов включён" : "Счётчик символов выключен")
            }
            screen.toggle["ui.confirmCalls"] = { isOn in
                MTMediaTokWave6Tools.isCallConfirmEnabled = isOn
                MTMediaTokLiquidUI.applyMediaTokGlobalSettings(["ghostMode.confirmCalls": false])
                bump()
                mtPresentNativeToast(context: accountContext, from: weakController, text: isOn ? "Подтверждение звонков включено" : "Подтверждение звонков выключено")
            }

            // Section 1: Read Checkmark Style
            screen.sections.append([
                MTNativeRow(id: "checks.header", kind: .header("Галочки прочтения")),
                MTNativeRow(id: "checks.picker", kind: .disclosure(title: "Стиль галочек", label: activeCheckmarkTitle, icon: nil, enabled: true)),
                MTNativeRow(id: "checks.footer", kind: .footer("Кастомные галочки автоматически окрашиваются в цвет статуса прочтения вашей темы."))
            ])
            screen.tap["checks.picker"] = {
                let buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = MTMediaTokLiquidUI.checkmarkStyles.map { style in
                    return (
                        title: style.title,
                        isDestructive: false,
                        action: {
                            MTMediaTokLiquidUI.setCheckmarkStyle(style.id)
                            bump()
                            mtPresentNativeToast(context: accountContext, from: weakController, text: "Стиль галочек: \(style.title)")
                        }
                    )
                }
                mtPresentNativeActionSheet(context: accountContext, from: weakController, title: "Выберите стиль галочек прочтения", buttons: buttons)
            }

            // Section 2: 4K 60 FPS Video Export & Reset
            let video4k = MTMediaTokLiquidUI.isVideo4k60Enabled
            screen.sections.append([
                MTNativeRow(id: "video.header", kind: .header("Качество видео при отправке")),
                MTNativeRow(id: "video.4k60", kind: .toggle(title: "Видео до 4K 60 FPS", value: video4k, enabled: true)),
                MTNativeRow(id: "video.reset", kind: .action(title: "Сбросить настройки раздела", destructive: true, enabled: true)),
                MTNativeRow(id: "video.footer", kind: .footer("Разблокирует экспорт видео до 3840px и 60 FPS (22 Мбит/с) при выборе максимального качества в редакторе."))
            ])
            screen.toggle["video.4k60"] = { isOn in
                MTMediaTokLiquidUI.setVideo4k60Enabled(isOn)
                bump()
                mtPresentNativeToast(context: accountContext, from: weakController, text: isOn ? "Экспорт видео 4K 60 FPS включён" : "Стандартное сжатие видео")
            }
            screen.tap["video.reset"] = {
                mtPresentNativeAlert(
                    context: accountContext,
                    from: weakController,
                    title: "Сбросить настройки?",
                    text: "Вернуть стандартные галочки, плотность списка чатов и параметры видео?",
                    confirmTitle: "Сбросить",
                    destructive: true,
                    confirmAction: {
                        MTMediaTokLiquidUI.setLiquidPreset("off")
                        MTMediaTokLiquidUI.setZeroBloatEnabled(false)
                        MTMediaTokLiquidUI.setCompactModeEnabled(false)
                        MTMediaTokLiquidUI.setCheckmarkStyle("default")
                        MTMediaTokLiquidUI.setVideo4k60Enabled(false)
                        bump()
                        mtPresentNativeToast(context: accountContext, from: weakController, text: "Настройки сброшены по умолчанию")
                    }
                )
            }

            return screen
        }

        let controller = mtMakeNativeListController(context: accountContext, model: modelSignal)
        weakController = controller
        return controller
    }
}
