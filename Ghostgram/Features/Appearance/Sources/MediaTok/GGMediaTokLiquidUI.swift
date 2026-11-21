import Foundation
import UIKit
import TelegramPresentationData
import GGCore
import GGHooks
import GGSettingsUI
import GGAppearanceSettings

/// Liquid Glass iOS 27 Studio (#101), Zero-Bloat 1-Tap Preset (#110), Compact Discord Density (#107),
/// Custom Read Checkmarks (#108), Built-in Guard / Counter Shortcuts (#71/#58), and 4K 60 FPS Video Toggle (#83).
enum GGMediaTokLiquidUI {
    static let liquidPresetKey = "mediatok.liquid_glass.preset.v1"
    static let zeroBloatKey = "mediatok.ui.zero_bloat.v1"
    static let compactModeKey = "mediatok.ui.compact_mode.v1"
    static let checkmarkStyleKey = "mediatok.checkmarks.style.v1"
    static let video4k60Key = "mediatok.video.4k60.v1"

    static let liquidPresets: [(id: String, title: String, subtitle: String)] = [
        ("off", "Стандарт (выкл.)", "Обычные края и непрозрачность пузырей Telegram"),
        ("ios27_clear", "iOS 27 Clear Glass 🧊", "Размытие краёв 75%, прозрачные пузыри 78%, стеклянный контур 28%, без разделителей"),
        ("frost_cyber", "Frost Cyber Glass 💎", "Циан-подсветка краёв 65%, прозрачные пузыри 72%, неоновая рамка 42%"),
        ("obsidian_glass", "AMOLED Obsidian Glass 🖤", "AMOLED чёрный + стекло-размытие 80%, прозрачность пузырей 82%, контур 25%")
    ]

    static let checkmarkStyles: [(id: String, title: String)] = [
        ("default", "Стандартные галочки ТГ (✓✓)"),
        ("bolt", "Молнии (⚡)"),
        ("fire", "Огонь (🔥)"),
        ("diamond", "Кристалл (💎)"),
        ("eyes", "Глаза — видно когда прочли (👀)"),
        ("heart", "Сердечки (❤️)"),
        ("star", "Звёзды (⭐)"),
        ("minimal", "Минимал-точки (●)")
    ]

    static func register() {
        // Re-apply theme revision at launch if custom checkmark style or glass preset is active
        if UserDefaults.standard.string(forKey: GGMediaTokLiquidUI.checkmarkStyleKey) != nil {
            DispatchQueue.main.async {
                GGThemeHooks.invalidate()
            }
        }
    }

    static var currentLiquidPreset: String {
        return UserDefaults.standard.string(forKey: GGMediaTokLiquidUI.liquidPresetKey) ?? "off"
    }

    static var isZeroBloatEnabled: Bool {
        return UserDefaults.standard.bool(forKey: GGMediaTokLiquidUI.zeroBloatKey)
    }

    static var isCompactModeEnabled: Bool {
        return UserDefaults.standard.bool(forKey: GGMediaTokLiquidUI.compactModeKey)
    }

    static var currentCheckmarkStyle: String {
        return UserDefaults.standard.string(forKey: GGMediaTokLiquidUI.checkmarkStyleKey) ?? "default"
    }

    static var isVideo4k60Enabled: Bool {
        return UserDefaults.standard.bool(forKey: GGMediaTokLiquidUI.video4k60Key)
    }

    static func readGhostgramGlobalBool(_ key: String, fallback: Bool) -> Bool {
        let data = GGSettingsStore.shared.exportData(accounts: [])
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let global = obj["global"] as? [String: Any],
              let val = global[key] as? Bool else {
            return fallback
        }
        return val
    }

    static func applyGhostgramGlobalSettings(_ values: [String: Any]) {
        let root: [String: Any] = [
            "format": "ghostgram.settings",
            "version": 1,
            "global": values,
            "appGroup": [:] as [String: Any],
            "accounts": [:] as [String: Any]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: []),
              let diff = try? GGSettingsStore.shared.importPreview(data) else {
            return
        }
        GGSettingsStore.shared.applyImport(diff)
    }

    static func setLiquidPreset(_ presetId: String) {
        UserDefaults.standard.set(presetId, forKey: GGMediaTokLiquidUI.liquidPresetKey)
        switch presetId {
        case "ios27_clear":
            GGMediaTokLiquidUI.applyGhostgramGlobalSettings([
                "appearance.edges.style": GGEdgeStyle.blur.rawValue,
                "appearance.edges.intensity": 75.0,
                "appearance.edges.size": 88.0,
                "appearance.edges.color": "",
                "appearance.bubbles.editor": true,
                "appearance.bubbles.backgroundOpacity": 78.0,
                "appearance.bubbles.outlineOpacity": 28.0,
                "appearance.theme.hideSeparators": true
            ])
        case "frost_cyber":
            GGMediaTokLiquidUI.applyGhostgramGlobalSettings([
                "appearance.edges.style": GGEdgeStyle.gradient.rawValue,
                "appearance.edges.intensity": 65.0,
                "appearance.edges.size": 92.0,
                "appearance.edges.color": "00F5FF",
                "appearance.bubbles.editor": true,
                "appearance.bubbles.backgroundOpacity": 72.0,
                "appearance.bubbles.outlineOpacity": 42.0,
                "appearance.theme.hideSeparators": true
            ])
        case "obsidian_glass":
            GGMediaTokLiquidUI.applyGhostgramGlobalSettings([
                "appearance.theme.amoled": true,
                "appearance.edges.style": GGEdgeStyle.blur.rawValue,
                "appearance.edges.intensity": 80.0,
                "appearance.edges.size": 84.0,
                "appearance.edges.color": "",
                "appearance.bubbles.editor": true,
                "appearance.bubbles.backgroundOpacity": 82.0,
                "appearance.bubbles.outlineOpacity": 25.0,
                "appearance.theme.hideSeparators": true
            ])
        default:
            GGMediaTokLiquidUI.applyGhostgramGlobalSettings([
                "appearance.edges.style": GGEdgeStyle.off.rawValue,
                "appearance.edges.color": "",
                "appearance.bubbles.backgroundOpacity": 100.0,
                "appearance.bubbles.outlineOpacity": 0.0
            ])
        }
        GGThemeHooks.invalidate()
    }

    static func setZeroBloatEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: GGMediaTokLiquidUI.zeroBloatKey)
        GGMediaTokLiquidUI.applyGhostgramGlobalSettings([
            "interface.chatList.hideStories": enabled,
            "interface.chatList.hideStoryRings": enabled,
            "interface.chatList.hideProxySponsor": enabled,
            "appearance.profile.hideStarRating": enabled,
            "appearance.messages.hideViewCounts": enabled,
            "appearance.messages.hideChannelComments": enabled,
            "appearance.theme.hideSeparators": enabled
        ])
        GGThemeHooks.invalidate()
    }

    static func setCompactModeEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: GGMediaTokLiquidUI.compactModeKey)
        GGMediaTokLiquidUI.applyGhostgramGlobalSettings([
            "interface.chatList.compact": enabled,
            "interface.chatList.previewLines": enabled ? "1" : "2",
            "interface.chatList.rowScale": enabled ? "85" : "100",
            "interface.chatList.avatarScale": enabled ? "85" : "100",
            "appearance.bubbles.editor": enabled,
            "appearance.bubbles.padding": enabled ? 7.0 : 11.0,
            "appearance.bubbles.hideTails": enabled
        ])
        GGThemeHooks.invalidate()
    }

    static func setCheckmarkStyle(_ styleId: String) {
        UserDefaults.standard.set(styleId, forKey: GGMediaTokLiquidUI.checkmarkStyleKey)
        GGThemeHooks.invalidate()
    }

    static func setVideo4k60Enabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: GGMediaTokLiquidUI.video4k60Key)
    }

    static func presentStudio(context: GGMenuContext) {
        let vc = GGLiquidUIStudioViewController(menuContext: context)
        vc.overrideUserInterfaceStyle = .dark
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        nav.modalPresentationStyle = .pageSheet
        context.presentNative(nav)
    }
}

private final class GGLiquidUIStudioViewController: UITableViewController {
    private let menuContext: GGMenuContext
    private weak var activeToastView: UIView?

    init(menuContext: GGMenuContext) {
        self.menuContext = menuContext
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
        self.title = "🧊 Интерфейс и Видео 4K"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closeTapped))
    }

    private func showInlineToast(_ text: String) {
        let hostView: UIView = self.navigationController?.view ?? self.view
        self.activeToastView?.removeFromSuperview()

        let pill = UIView()
        pill.isUserInteractionEnabled = false
        pill.backgroundColor = UIColor(red: 0.08, green: 0.11, blue: 0.18, alpha: 0.96)
        pill.layer.cornerRadius = 14.0
        pill.layer.borderWidth = 1.0
        pill.layer.borderColor = UIColor(red: 0.0, green: 0.96, blue: 1.0, alpha: 0.75).cgColor
        pill.layer.shadowColor = UIColor.black.cgColor
        pill.layer.shadowOpacity = 0.4
        pill.layer.shadowRadius = 8.0
        pill.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13.5, weight: .semibold)
        label.textColor = .white
        label.numberOfLines = 2
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        pill.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(pill)

        NSLayoutConstraint.activate([
            pill.bottomAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.bottomAnchor, constant: -14.0),
            pill.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: hostView.leadingAnchor, constant: 20.0),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: hostView.trailingAnchor, constant: -20.0),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 10.0),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -10.0),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16.0),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16.0)
        ])

        self.activeToastView = pill
        pill.alpha = 0.0
        UIView.animate(withDuration: 0.2) {
            pill.alpha = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak pill] in
            guard let pill else { return }
            UIView.animate(withDuration: 0.2, animations: {
                pill.alpha = 0.0
            }, completion: { _ in
                pill.removeFromSuperview()
            })
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "🧊 Liquid Glass для iOS 27"
        case 1: return "⚡ Zero-Bloat / Компактность / Счётчик / Звонки"
        case 2: return "✔️ Стиль галочек прочтения"
        default: return "🎬 Качество видео при отправке"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 1:
            return "Подсказка: Нижнюю панель вкладок можно детально настроить в «Интерфейс → Нижняя панель», а водяной знак на фото с прозрачностью — в «Камера и медиа → Водяной знак»."
        case 3:
            return "Разблокирует экспорт видео до 4K (3840px) и 60 FPS при выборе максимального качества в редакторе."
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return GGMediaTokLiquidUI.liquidPresets.count
        case 1: return 4
        case 2: return GGMediaTokLiquidUI.checkmarkStyles.count
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "uiRow") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "uiRow")
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch indexPath.section {
        case 0:
            let item = GGMediaTokLiquidUI.liquidPresets[indexPath.row]
            cell.textLabel?.text = item.title
            cell.detailTextLabel?.text = item.subtitle
            cell.detailTextLabel?.numberOfLines = 2
            cell.accessoryType = (GGMediaTokLiquidUI.currentLiquidPreset == item.id) ? .checkmark : .none
        case 1:
            cell.selectionStyle = .none
            let sw = UISwitch()
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "🧹 Zero-Bloat (убрать всё лишнее)"
                cell.detailTextLabel?.text = "Скрывает Сторис, звёзды, спонсоров, счётчики и разделители"
                sw.isOn = GGMediaTokLiquidUI.isZeroBloatEnabled
                sw.addTarget(self, action: #selector(self.zeroBloatToggled(_:)), for: .valueChanged)
            case 1:
                cell.textLabel?.text = "💬 Компактный режим (как Discord)"
                cell.detailTextLabel?.text = "Больше чатов и сообщений на экране (уменьшенные отступы)"
                sw.isOn = GGMediaTokLiquidUI.isCompactModeEnabled
                sw.addTarget(self, action: #selector(self.compactToggled(_:)), for: .valueChanged)
            case 2:
                cell.textLabel?.text = "🔢 Счётчик символов при вводе"
                cell.detailTextLabel?.text = "Живой счётчик символов в поле ввода и меню отправки"
                sw.isOn = GGMediaTokLiquidUI.readGhostgramGlobalBool("interface.inputBar.characterCounter", fallback: false)
                sw.addTarget(self, action: #selector(self.charCounterToggled(_:)), for: .valueChanged)
            default:
                cell.textLabel?.text = "📞 Подтверждение звонков"
                cell.detailTextLabel?.text = "Защита от случайного нажатия кнопки звонка"
                sw.isOn = GGMediaTokWave6Tools.isCallConfirmEnabled
                sw.addTarget(self, action: #selector(self.confirmCallsToggled(_:)), for: .valueChanged)
            }
            cell.accessoryView = sw
        case 2:
            let item = GGMediaTokLiquidUI.checkmarkStyles[indexPath.row]
            cell.textLabel?.text = item.title
            cell.detailTextLabel?.text = (item.id == "default") ? "Цвета меняются выше в разделе «Галочки»" : "Автоматически красится под ваш цвет прочтения"
            cell.accessoryType = (GGMediaTokLiquidUI.currentCheckmarkStyle == item.id) ? .checkmark : .none
        default:
            cell.selectionStyle = .none
            let sw = UISwitch()
            cell.textLabel?.text = "🎬 Разблокировать видео до 4K 60 FPS"
            cell.detailTextLabel?.text = "До 3840px · 22 Мбит/с · 60 кадров/с без даунскейла"
            sw.isOn = GGMediaTokLiquidUI.isVideo4k60Enabled
            sw.addTarget(self, action: #selector(self.video4kToggled(_:)), for: .valueChanged)
            cell.accessoryView = sw
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let item = GGMediaTokLiquidUI.liquidPresets[indexPath.row]
            GGMediaTokLiquidUI.setLiquidPreset(item.id)
            tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
            self.showInlineToast("🧊 Пресет применён: \(item.title)")
        } else if indexPath.section == 2 {
            let item = GGMediaTokLiquidUI.checkmarkStyles[indexPath.row]
            GGMediaTokLiquidUI.setCheckmarkStyle(item.id)
            tableView.reloadSections(IndexSet(integer: 2), with: .automatic)
            self.showInlineToast("✔️ Стиль галочек: \(item.title)")
        }
    }

    @objc private func zeroBloatToggled(_ sender: UISwitch) {
        GGMediaTokLiquidUI.setZeroBloatEnabled(sender.isOn)
        self.showInlineToast(sender.isOn ? "🧹 Zero-Bloat ВКЛ!" : "Zero-Bloat ВЫКЛ")
    }

    @objc private func compactToggled(_ sender: UISwitch) {
        GGMediaTokLiquidUI.setCompactModeEnabled(sender.isOn)
        self.showInlineToast(sender.isOn ? "💬 Компактный режим ВКЛ!" : "Компактный режим ВЫКЛ")
    }

    @objc private func charCounterToggled(_ sender: UISwitch) {
        GGMediaTokLiquidUI.applyGhostgramGlobalSettings(["interface.inputBar.characterCounter": sender.isOn])
        self.showInlineToast(sender.isOn ? "🔢 Счётчик символов ВКЛ!" : "Счётчик символов ВЫКЛ")
    }

    @objc private func confirmCallsToggled(_ sender: UISwitch) {
        GGMediaTokWave6Tools.isCallConfirmEnabled = sender.isOn
        GGMediaTokLiquidUI.applyGhostgramGlobalSettings(["ghostMode.confirmCalls": false])
        self.showInlineToast(sender.isOn ? "📞 Подтверждение звонков ВКЛ!" : "Подтверждение звонков ВЫКЛ")
    }

    @objc private func video4kToggled(_ sender: UISwitch) {
        GGMediaTokLiquidUI.setVideo4k60Enabled(sender.isOn)
        self.showInlineToast(sender.isOn ? "🎬 Экспорт 4K 60 FPS ВКЛ!" : "Стандартное сжатие видео ТГ")
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}
