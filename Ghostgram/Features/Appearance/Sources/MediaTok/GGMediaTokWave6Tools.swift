import Foundation
import UIKit
import AVFoundation
import TelegramPresentationData
import TelegramCore
import AccountContext
import Display
import SwiftSignalKit
import GGCore
import GGHooks
import GGSettingsUI
import GGAppearanceSettings
import WebPBinding

/// MediaTok Wave 6 Tools:
/// 1. Unified TikTok/Reels Channel Media Feed (#187)
/// 2. MediaTok Achievements System (#168)
/// 3. Interactive Scratch Messages («Скретч-сообщение — Сотри монеткой») (#163)
/// 4. Call Confirm Guard (#58)
/// 5. Photo Watermark Overlay (#59)
/// 6. Keyboard Layout Auto-Fixer (.fix / .ghbdtn) (#62)
/// 7. Bottom Bar / Tab Bar Editor (#110)
/// 8. Neon Minesweeper (Сапёр) in Offline Mini-Games (#164)
public enum GGMediaTokWave6Tools {
    private static let callConfirmKey = "mediatok.guard.callConfirm.v1"
    private static let watermarkEnabledKey = "mediatok.watermark.enabled.v1"
    private static let watermarkTagKey = "mediatok.watermark.tag.v1"
    private static let unlockedAchievementsKey = "mediatok.achievements.unlocked.v1"
    private static let lastNightOwlCheckKey = "mediatok.achievements.night_owl_check"

    public static var isCallConfirmEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: GGMediaTokWave6Tools.callConfirmKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: GGMediaTokWave6Tools.callConfirmKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave6Tools.callConfirmKey) }
    }

    public static var isWatermarkEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: GGMediaTokWave6Tools.watermarkEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave6Tools.watermarkEnabledKey) }
    }

    public static var customWatermarkTag: String {
        get { return UserDefaults.standard.string(forKey: GGMediaTokWave6Tools.watermarkTagKey) ?? "MediaTok" }
        set { UserDefaults.standard.set(newValue, forKey: GGMediaTokWave6Tools.watermarkTagKey) }
    }

    public static func register() {
        // 1. Call Confirm Guard (Anti-accidental call)
        GGCallHooks.outgoingCall.register({ req, proceed in
            guard GGMediaTokWave6Tools.isCallConfirmEnabled else { return false }
            DispatchQueue.main.async {
                let callType = req.isVideo ? "видеозвонок" : "аудиозвонок"
                let alert = UIAlertController(
                    title: "📞 Подтверждение звонка",
                    message: "Вы действительно хотите совершить \(callType)?",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Позвонить", style: .default, handler: { _ in
                    GGMediaTokWave6Tools.unlockAchievement(.callGuard)
                    proceed()
                }))
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
                GGMediaTokWave6Tools.presentOnRoot(alert)
            }
            return true
        }, order: 100)

        // 2. Chat Commands: .scratch, .fix, .ghbdtn
        GGChatScreenHooks.willSendText.register({ text, context in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // .scratch command
            if let scratch = GGMediaTokCoreLogic.parseScratchCommand(trimmed) {
                DispatchQueue.global(qos: .userInitiated).async {
                    if let webpData = GGMediaTokWave6Tools.generateScratchStickerWebP(scratch: scratch) {
                        DispatchQueue.main.async {
                            let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scratch_\(Int(Date().timeIntervalSince1970)).webp")
                            try? webpData.write(to: tempUrl)
                            context.sendMediaFile(tempUrl)
                            GGMediaTokWave6Tools.unlockAchievement(.mediatokOg)
                        }
                    }
                }
                return nil
            }

            // .fix / .ghbdtn command
            if let fixed = GGMediaTokCoreLogic.parseFixCommand(trimmed) {
                if !fixed.isEmpty {
                    GGMediaTokWave6Tools.unlockAchievement(.mediatokOg)
                    return fixed
                }
            }

            // Achievement check: Night Owl (03:00 - 05:00)
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 3 && hour < 5 {
                GGMediaTokWave6Tools.unlockAchievement(.nightOwl)
            }

            return text
        }, order: 25)

        // 3. Send Menu: Scratch Card & Watermark Photo
        GGChatScreenHooks.sendMenuItems.register({ context in
            return [
                GGSendMenuItem(id: "mediatok.scratch_card", title: "🎟️ Скретч-сообщение (Сотри монеткой)", icon: "sparkles", action: {
                    let alert = UIAlertController(title: "🎟️ Скретч-сообщение", message: "Введите секретный текст или промокод, скрытый под стираемым слоем:", preferredStyle: .alert)
                    alert.addTextField { tf in
                        tf.placeholder = "Секретный текст (например: Люблю тебя)"
                    }
                    alert.addAction(UIAlertAction(title: "Создать и отправить", style: .default, handler: { _ in
                        guard let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                        let scratch = GGMediaTokCoreLogic.ScratchPayload(title: "Секретный билет 🎟️", secret: text, seed: UInt64(Date().timeIntervalSince1970))
                        DispatchQueue.global(qos: .userInitiated).async {
                            if let webpData = GGMediaTokWave6Tools.generateScratchStickerWebP(scratch: scratch) {
                                DispatchQueue.main.async {
                                    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scratch_\(Int(Date().timeIntervalSince1970)).webp")
                                    try? webpData.write(to: tempUrl)
                                    context.sendMediaFile(tempUrl)
                                    GGMediaTokWave6Tools.unlockAchievement(.mediatokOg)
                                }
                            }
                        }
                    }))
                    alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                    GGMediaTokWave6Tools.presentOnRoot(alert)
                }),
                GGSendMenuItem(id: "mediatok.watermark_toggle", title: "💧 Водяной знак на фото: \(GGMediaTokWave6Tools.isWatermarkEnabled ? "ВКЛ" : "ВЫКЛ")", icon: "drop.fill", action: {
                    GGMediaTokWave6Tools.isWatermarkEnabled.toggle()
                    let state = GGMediaTokWave6Tools.isWatermarkEnabled ? "ВКЛ (защита от сливов активна)" : "ВЫКЛ"
                    let toast = UIAlertController(title: "💧 Водяной знак на фото", message: "Статус: \(state)\nТекст: \(GGMediaTokCoreLogic.formatWatermarkText(recipient: "получатель", appTag: GGMediaTokWave6Tools.customWatermarkTag))", preferredStyle: .alert)
                    toast.addAction(UIAlertAction(title: "OK", style: .default))
                    GGMediaTokWave6Tools.presentOnRoot(toast)
                })
            ]
        }, order: 80)
    }

    // MARK: - Achievements System

    public static func getUnlockedAchievements() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: GGMediaTokWave6Tools.unlockedAchievementsKey) ?? [GGMediaTokCoreLogic.AchievementId.mediatokOg.rawValue]
        return Set(array)
    }

    public static func unlockAchievement(_ id: GGMediaTokCoreLogic.AchievementId) {
        var set = getUnlockedAchievements()
        if !set.contains(id.rawValue) {
            set.insert(id.rawValue)
            UserDefaults.standard.set(Array(set), forKey: GGMediaTokWave6Tools.unlockedAchievementsKey)
            if let def = GGMediaTokCoreLogic.allAchievements.first(where: { $0.id == id }) {
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title: "🏆 Новое достижение!",
                        message: "\(def.icon) \(def.title)\n\(def.subtitle) (\(def.rarity))",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "Круто!", style: .default))
                    GGMediaTokWave6Tools.presentOnRoot(alert)
                }
            }
        }
    }

    // MARK: - Watermark Renderer

    public static func applyWatermark(to image: UIImage, recipient: String) -> UIImage {
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))

            let text = GGMediaTokCoreLogic.formatWatermarkText(recipient: recipient, date: Date(), appTag: GGMediaTokWave6Tools.customWatermarkTag)
            let fontSize = max(16.0, size.width * 0.035)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.65),
                .backgroundColor: UIColor.black.withAlphaComponent(0.35)
            ]

            let textSize = (text as NSString).size(withAttributes: attrs)
            let rect = CGRect(
                x: size.width - textSize.width - 24,
                y: size.height - textSize.height - 24,
                width: textSize.width + 12,
                height: textSize.height + 6
            )
            (text as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    // MARK: - Scratch Card WebP Sticker Generator

    public static func generateScratchStickerWebP(scratch: GGMediaTokCoreLogic.ScratchPayload) -> Data? {
        let side: CGFloat = 512
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext

            // Dark neon card background
            cg.setFillColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
            let bgPath = UIBezierPath(roundedRect: CGRect(x: 16, y: 16, width: side - 32, height: side - 32), cornerRadius: 36)
            cg.addPath(bgPath.cgPath)
            cg.fillPath()

            // Glowing border
            cg.setStrokeColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.8)
            cg.setLineWidth(4.0)
            cg.addPath(bgPath.cgPath)
            cg.strokePath()

            // Header text
            let header = "🎟️ МЕДИАТОК СКРЕТЧ-КАРТА"
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
            ]
            (header as NSString).draw(at: CGPoint(x: 44, y: 44), withAttributes: headerAttrs)

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            (scratch.title as NSString).draw(at: CGPoint(x: 44, y: 76), withAttributes: titleAttrs)

            // Metallic silver/gold scratch foil area
            let foilRect = CGRect(x: 40, y: 130, width: side - 80, height: 260)
            let foilPath = UIBezierPath(roundedRect: foilRect, cornerRadius: 20)
            cg.addPath(foilPath.cgPath)
            cg.setFillColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1.0)
            cg.fillPath()

            // Metallic hatching pattern
            cg.setStrokeColor(red: 0.60, green: 0.62, blue: 0.66, alpha: 0.5)
            cg.setLineWidth(2.0)
            for x in stride(from: foilRect.minX - 40, to: foilRect.maxX + 40, by: 16) {
                cg.move(to: CGPoint(x: x, y: foilRect.minY))
                cg.addLine(to: CGPoint(x: x + 40, y: foilRect.maxY))
            }
            cg.strokePath()

            // Foil text prompt
            let prompt = "🪙 СОТРИ МОНЕТКОЙ 🪙"
            let promptAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .black),
                .foregroundColor: UIColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.9)
            ]
            let pSize = (prompt as NSString).size(withAttributes: promptAttrs)
            (prompt as NSString).draw(at: CGPoint(x: foilRect.midX - pSize.width / 2, y: foilRect.midY - pSize.height / 2 - 14), withAttributes: promptAttrs)

            let subPrompt = "Нажми чтобы открыть секрет"
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor(red: 0.35, green: 0.35, blue: 0.4, alpha: 0.9)
            ]
            let subSize = (subPrompt as NSString).size(withAttributes: subAttrs)
            (subPrompt as NSString).draw(at: CGPoint(x: foilRect.midX - subSize.width / 2, y: foilRect.midY + 18), withAttributes: subAttrs)

            // Footer
            let footer = "MediaTok iOS Ghost Edition · 100% Client-Side"
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.lightGray.withAlphaComponent(0.6)
            ]
            (footer as NSString).draw(at: CGPoint(x: 44, y: 440), withAttributes: footerAttrs)
        }

        return WebP.convert(toWebP: img, quality: 90.0)
    }

    public static func presentOnRoot(_ vc: UIViewController) {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first,
              var top = window.rootViewController else {
            return
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
            top = visible
        }
        top.present(vc, animated: true)
    }
}

// MARK: - Interactive Scratch Card View Controller

public final class GGScratchCardViewController: UIViewController {
    private let payload: GGMediaTokCoreLogic.ScratchPayload
    private var scratchView: GGScratchMaskView?
    private let revealedLabel = UILabel()
    private var isRevealed = false

    public init(payload: GGMediaTokCoreLogic.ScratchPayload) {
        self.payload = payload
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.black.withAlphaComponent(0.85)

        let cardContainer = UIView()
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
        cardContainer.layer.cornerRadius = 28
        cardContainer.layer.borderColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.6).cgColor
        cardContainer.layer.borderWidth = 2.0
        cardContainer.clipsToBounds = true
        self.view.addSubview(cardContainer)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = payload.title
        titleLabel.font = .systemFont(ofSize: 22, weight: .heavy)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        cardContainer.addSubview(titleLabel)

        let foilArea = UIView()
        foilArea.translatesAutoresizingMaskIntoConstraints = false
        foilArea.backgroundColor = UIColor(red: 0.12, green: 0.14, blue: 0.20, alpha: 1.0)
        foilArea.layer.cornerRadius = 16
        foilArea.clipsToBounds = true
        cardContainer.addSubview(foilArea)

        revealedLabel.translatesAutoresizingMaskIntoConstraints = false
        revealedLabel.text = payload.secret
        revealedLabel.font = .systemFont(ofSize: 20, weight: .bold)
        revealedLabel.textColor = UIColor(red: 0.20, green: 0.95, blue: 0.6, alpha: 1.0)
        revealedLabel.textAlignment = .center
        revealedLabel.numberOfLines = 0
        foilArea.addSubview(revealedLabel)

        let mask = GGScratchMaskView()
        mask.translatesAutoresizingMaskIntoConstraints = false
        mask.onScratchedPercentage = { [weak self] pct in
            if pct > 0.40, let self = self, !self.isRevealed {
                self.isRevealed = true
                UIView.animate(withDuration: 0.4) {
                    mask.alpha = 0.0
                }
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
            }
        }
        foilArea.addSubview(mask)
        self.scratchView = mask

        let copyBtn = UIButton(type: .system)
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        copyBtn.setTitle("📋 Скопировать секрет", for: .normal)
        copyBtn.setTitleColor(.white, for: .normal)
        copyBtn.backgroundColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.4)
        copyBtn.layer.cornerRadius = 14
        copyBtn.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        cardContainer.addSubview(copyBtn)

        let closeBtn = UIButton(type: .system)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.setTitle("Закрыть", for: .normal)
        closeBtn.setTitleColor(.lightGray, for: .normal)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        cardContainer.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            cardContainer.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            cardContainer.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            cardContainer.widthAnchor.constraint(equalToConstant: 340),
            cardContainer.heightAnchor.constraint(equalToConstant: 440),

            titleLabel.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -16),

            foilArea.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            foilArea.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 20),
            foilArea.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -20),
            foilArea.heightAnchor.constraint(equalToConstant: 220),

            revealedLabel.centerXAnchor.constraint(equalTo: foilArea.centerXAnchor),
            revealedLabel.centerYAnchor.constraint(equalTo: foilArea.centerYAnchor),
            revealedLabel.leadingAnchor.constraint(equalTo: foilArea.leadingAnchor, constant: 16),
            revealedLabel.trailingAnchor.constraint(equalTo: foilArea.trailingAnchor, constant: -16),

            mask.topAnchor.constraint(equalTo: foilArea.topAnchor),
            mask.bottomAnchor.constraint(equalTo: foilArea.bottomAnchor),
            mask.leadingAnchor.constraint(equalTo: foilArea.leadingAnchor),
            mask.trailingAnchor.constraint(equalTo: foilArea.trailingAnchor),

            copyBtn.topAnchor.constraint(equalTo: foilArea.bottomAnchor, constant: 20),
            copyBtn.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 24),
            copyBtn.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -24),
            copyBtn.heightAnchor.constraint(equalToConstant: 44),

            closeBtn.topAnchor.constraint(equalTo: copyBtn.bottomAnchor, constant: 10),
            closeBtn.centerXAnchor.constraint(equalTo: cardContainer.centerXAnchor)
        ])
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = payload.secret
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

private final class GGScratchMaskView: UIView {
    var onScratchedPercentage: ((Double) -> Void)?
    private var scratchedPoints = 0
    private var totalPoints = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1.0)
        self.isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.totalPoints = max(1, Int(self.bounds.width * self.bounds.height / 400.0))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        scratchedPoints += 1
        let pct = min(1.0, Double(scratchedPoints) / Double(totalPoints))
        onScratchedPercentage?(pct)
    }
}

// MARK: - Achievements Showcase View Controller

public final class GGAchievementsViewController: UITableViewController {
    private var unlocked: [GGMediaTokCoreLogic.AchievementDef] = []
    private var locked: [GGMediaTokCoreLogic.AchievementDef] = []
    private var tier: String = ""

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🏆 Достижения MediaTok"
        self.tableView.backgroundColor = .systemGroupedBackground

        let unlockedSet = GGMediaTokWave6Tools.getUnlockedAchievements()
        let eval = GGMediaTokCoreLogic.evaluateAchievements(unlockedIds: unlockedSet)
        self.unlocked = eval.unlocked
        self.locked = eval.locked
        self.tier = eval.tier

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Поделиться",
            style: .plain,
            target: self,
            action: #selector(shareAchievements)
        )
    }

    @objc private func shareAchievements() {
        let text = "🏆 Мои достижения в MediaTok iOS Ghost Edition:\nРанг: \(tier) (\(unlocked.count)/12)\n" + unlocked.map { "\($0.icon) \($0.title)" }.joined(separator: "\n")
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        self.present(vc, animated: true)
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return unlocked.count
        case 2: return locked.count
        default: return 0
        }
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "ТЕКУЩИЙ РАНГ"
        case 1: return "РАЗБЛОКИРОВАННЫЕ (\(unlocked.count))"
        case 2: return "ЗАБЛОКИРОВАННЫЕ (\(locked.count))"
        default: return nil
        }
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        switch indexPath.section {
        case 0:
            cell.textLabel?.text = "Ранг: \(tier)"
            cell.textLabel?.font = .systemFont(ofSize: 18, weight: .bold)
            cell.detailTextLabel?.text = "Открыто \(unlocked.count) из 12 наград MediaTok"
            cell.imageView?.image = UIImage(systemName: "crown.fill")
            cell.imageView?.tintColor = .systemYellow
        case 1:
            let def = unlocked[indexPath.row]
            cell.textLabel?.text = "\(def.icon) \(def.title) · \(def.rarity)"
            cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            cell.detailTextLabel?.text = def.subtitle
            cell.accessoryType = .checkmark
        case 2:
            let def = locked[indexPath.row]
            cell.textLabel?.text = "🔒 \(def.title) (\(def.rarity))"
            cell.textLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.text = def.subtitle
            cell.detailTextLabel?.textColor = .tertiaryLabel
        default:
            break
        }
        return cell
    }
}

// MARK: - Bottom Bar Studio View Controller

public final class GGBottomBarStudioViewController: UITableViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "📱 Редактор нижнего бара"
        self.tableView.backgroundColor = .systemGroupedBackground
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? GGMediaTokCoreLogic.BottomTabPreset.allCases.count : 2
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "ГОТОВЫЕ ПРЕСЕТЫ (1 ТАП)" : "КАСТОМИЗАЦИЯ"
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.section == 0 {
            let preset = GGMediaTokCoreLogic.BottomTabPreset.allCases[indexPath.row]
            cell.textLabel?.text = preset.title
            cell.detailTextLabel?.text = preset.hiddenTabs.isEmpty ? "Все вкладки включены" : "Скрывает: \(preset.hiddenTabs.joined(separator: ", "))"
            cell.accessoryType = .disclosureIndicator
        } else {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Парящий бар (+8pt над краем экрана)"
                let sw = UISwitch()
                sw.isOn = UserDefaults.standard.bool(forKey: "mediatok.tabbar.lifted")
                sw.addTarget(self, action: #selector(toggleLifted(_:)), for: .valueChanged)
                cell.accessoryView = sw
            } else {
                cell.textLabel?.text = "Широкий бар без разделителей"
                let sw = UISwitch()
                sw.isOn = UserDefaults.standard.bool(forKey: "mediatok.tabbar.wide")
                sw.addTarget(self, action: #selector(toggleWide(_:)), for: .valueChanged)
                cell.accessoryView = sw
            }
        }
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let preset = GGMediaTokCoreLogic.BottomTabPreset.allCases[indexPath.row]
            GGMediaTokLiquidUI.applyGhostgramGlobalSettings([
                "interface.tabBar.hidden": preset.hiddenTabs,
                "interface.tabBar.wide": preset.isWide
            ])
            GGThemeHooks.invalidate()
            let alert = UIAlertController(title: "Пресет применен!", message: "Выбран: \(preset.title)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    @objc private func toggleLifted(_ sw: UISwitch) {
        UserDefaults.standard.set(sw.isOn, forKey: "mediatok.tabbar.lifted")
        GGMediaTokLiquidUI.applyGhostgramGlobalSettings([
            "interface.tabBar.bottomOffset": sw.isOn ? 8.0 : 0.0
        ])
        GGThemeHooks.invalidate()
    }

    @objc private func toggleWide(_ sw: UISwitch) {
        UserDefaults.standard.set(sw.isOn, forKey: "mediatok.tabbar.wide")
        GGMediaTokLiquidUI.applyGhostgramGlobalSettings([
            "interface.tabBar.wide": sw.isOn
        ])
        GGThemeHooks.invalidate()
    }
}

// MARK: - Neon Minesweeper (Сапёр) View Controller

public final class GGMinesweeperViewController: UIViewController {
    private var game = GGMediaTokCoreLogic.MinesweeperGame()
    private var cellButtons: [UIButton] = []
    private let statusLabel = UILabel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "💣 Neon Minesweeper"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1.0)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Мины: 10 · Первый клик безопасен"
        statusLabel.textColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.textAlignment = .center
        self.view.addSubview(statusLabel)

        let gridContainer = UIView()
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1.0)
        gridContainer.layer.cornerRadius = 16
        gridContainer.clipsToBounds = true
        self.view.addSubview(gridContainer)

        let cellSize: CGFloat = 36
        for r in 0..<8 {
            for c in 0..<8 {
                let idx = r * 8 + c
                let btn = UIButton(type: .system)
                btn.frame = CGRect(x: CGFloat(c) * (cellSize + 2) + 6, y: CGFloat(r) * (cellSize + 2) + 6, width: cellSize, height: cellSize)
                btn.backgroundColor = UIColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1.0)
                btn.layer.cornerRadius = 6
                btn.tag = idx
                btn.addTarget(self, action: #selector(cellTapped(_:)), for: .touchUpInside)

                let lp = UILongPressGestureRecognizer(target: self, action: #selector(cellLongPressed(_:)))
                lp.minimumPressDuration = 0.35
                btn.addGestureRecognizer(lp)

                gridContainer.addSubview(btn)
                cellButtons.append(btn)
            }
        }

        let resetBtn = UIButton(type: .system)
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        resetBtn.setTitle("Новая игра", for: .normal)
        resetBtn.setTitleColor(.white, for: .normal)
        resetBtn.backgroundColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.3)
        resetBtn.layer.cornerRadius = 12
        resetBtn.addTarget(self, action: #selector(resetGame), for: .touchUpInside)
        self.view.addSubview(resetBtn)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),

            gridContainer.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            gridContainer.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            gridContainer.widthAnchor.constraint(equalToConstant: 8 * (cellSize + 2) + 12),
            gridContainer.heightAnchor.constraint(equalToConstant: 8 * (cellSize + 2) + 12),

            resetBtn.topAnchor.constraint(equalTo: gridContainer.bottomAnchor, constant: 24),
            resetBtn.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            resetBtn.widthAnchor.constraint(equalToConstant: 180),
            resetBtn.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func cellTapped(_ btn: UIButton) {
        let idx = btn.tag
        game.reveal(at: idx)
        updateGridUI()
        if game.isWon {
            statusLabel.text = "🏆 ПОБЕДА! Все мины обезврежены!"
            statusLabel.textColor = .systemGreen
            GGMediaTokWave6Tools.unlockAchievement(.gamer)
        } else if game.isGameOver {
            statusLabel.text = "💥 БУМ! Вы наступили на мину!"
            statusLabel.textColor = .systemRed
        }
    }

    @objc private func cellLongPressed(_ lp: UILongPressGestureRecognizer) {
        guard lp.state == .began, let btn = lp.view as? UIButton else { return }
        let idx = btn.tag
        game.toggleFlag(at: idx)
        updateGridUI()
    }

    @objc private func resetGame() {
        game = GGMediaTokCoreLogic.MinesweeperGame()
        statusLabel.text = "Мины: 10 · Первый клик безопасен"
        statusLabel.textColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
        updateGridUI()
    }

    private func updateGridUI() {
        for i in 0..<64 {
            let cell = game.grid[i]
            let btn = cellButtons[i]
            if cell.isRevealed {
                if cell.isMine {
                    btn.setTitle("💣", for: .normal)
                    btn.backgroundColor = UIColor.systemRed.withAlphaComponent(0.6)
                } else {
                    btn.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
                    if cell.adjacentMines > 0 {
                        btn.setTitle("\(cell.adjacentMines)", for: .normal)
                        btn.setTitleColor(colorForAdjacent(cell.adjacentMines), for: .normal)
                    } else {
                        btn.setTitle("", for: .normal)
                    }
                }
            } else if cell.isFlagged {
                btn.setTitle("🚩", for: .normal)
                btn.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.4)
            } else {
                btn.setTitle("", for: .normal)
                btn.backgroundColor = UIColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1.0)
            }
        }
    }

    private func colorForAdjacent(_ n: Int) -> UIColor {
        switch n {
        case 1: return UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
        case 2: return UIColor.systemGreen
        case 3: return UIColor.systemOrange
        case 4: return UIColor.systemPurple
        default: return UIColor.systemRed
        }
    }
}
