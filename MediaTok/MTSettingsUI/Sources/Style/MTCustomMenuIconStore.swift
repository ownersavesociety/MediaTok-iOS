import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ComponentFlow
import EmojiStatusComponent
import MTCore

/// User-selected custom icon for any MediaTok Settings category or row.
public enum MTCustomMenuIconChoice: Equatable {
    case systemDefault
    case premiumEmoji(fileId: Int64)
    case sfSymbol(String)
    case imageFile(String)

    var serialized: String? {
        switch self {
        case .systemDefault:
            return nil
        case let .premiumEmoji(fileId):
            return "emoji:\(fileId)"
        case let .sfSymbol(name):
            return "sf:\(name)"
        case let .imageFile(name):
            return "img:\(name)"
        }
    }

    init(serialized: String?) {
        guard let raw = serialized, !raw.isEmpty else {
            self = .systemDefault
            return
        }
        if raw.hasPrefix("emoji:"), let id = Int64(raw.dropFirst(6)), id != 0 {
            self = .premiumEmoji(fileId: id)
        } else if raw.hasPrefix("sf:") {
            let name = String(raw.dropFirst(3))
            self = name.isEmpty ? .systemDefault : .sfSymbol(name)
        } else if raw.hasPrefix("img:") {
            let file = String(raw.dropFirst(4))
            self = file.isEmpty ? .systemDefault : .imageFile(file)
        } else {
            self = .systemDefault
        }
    }
}

/// Persistent store for user-customized section & row icons (Telegram Premium Emoji, SF Symbols, or gallery images).
public final class MTCustomMenuIconStore: @unchecked Sendable {
    public static let shared = MTCustomMenuIconStore()

    private static let defaultsKey = "mediatok.menu.custom_icons.v1"
    private let lock = NSLock()
    private var entries: [String: String] = [:]
    private var imageCache: [String: UIImage] = [:]
    private let revisionPromise = ValuePromise<Int>(0, ignoreRepeated: false)
    private var revisionCounter: Int = 0

    public var revision: Signal<Int, NoError> {
        return self.revisionPromise.get()
    }

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] {
            self.entries = saved
        }
    }

    public func choice(for key: String) -> MTCustomMenuIconChoice {
        self.lock.lock()
        let raw = self.entries[key]
        self.lock.unlock()
        return MTCustomMenuIconChoice(serialized: raw)
    }

    public func setChoice(_ choice: MTCustomMenuIconChoice, for key: String) {
        self.lock.lock()
        if let serialized = choice.serialized {
            self.entries[key] = serialized
        } else {
            self.entries.removeValue(forKey: key)
        }
        let snapshot = self.entries
        self.imageCache.removeAll()
        self.revisionCounter += 1
        let nextRev = self.revisionCounter
        self.lock.unlock()

        UserDefaults.standard.set(snapshot, forKey: Self.defaultsKey)
        self.revisionPromise.set(nextRev)
    }

    public func resetAll() {
        self.lock.lock()
        self.entries.removeAll()
        self.imageCache.removeAll()
        self.revisionCounter += 1
        let nextRev = self.revisionCounter
        self.lock.unlock()

        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        if let dir = Self.iconsDirectory() {
            try? FileManager.default.removeItem(at: dir)
        }
        self.revisionPromise.set(nextRev)
    }

    public var customCount: Int {
        self.lock.lock()
        let count = self.entries.count
        self.lock.unlock()
        return count
    }

    public func saveCustomImage(_ image: UIImage, for key: String) -> String? {
        guard let dir = Self.iconsDirectory() else {
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeKey = key.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        let fileName = "\(safeKey)_\(Int(Date().timeIntervalSince1970)).png"
        let targetURL = dir.appendingPathComponent(fileName)

        let side: CGFloat = 72.0
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let bounds = CGRect(x: 0.0, y: 0.0, width: side, height: side)
            UIBezierPath(roundedRect: bounds, cornerRadius: 16.0).addClip()
            let srcSize = image.size
            let scale = max(side / max(1.0, srcSize.width), side / max(1.0, srcSize.height))
            let drawW = srcSize.width * scale
            let drawH = srcSize.height * scale
            image.draw(in: CGRect(x: (side - drawW) / 2.0, y: (side - drawH) / 2.0, width: drawW, height: drawH))
        }
        guard let pngData = rendered.pngData() else {
            return nil
        }
        do {
            try pngData.write(to: targetURL, options: .atomic)
            self.setChoice(.imageFile(fileName), for: key)
            return fileName
        } catch {
            return nil
        }
    }

    public func resolvedImage(for choice: MTCustomMenuIconChoice, theme: PresentationTheme) -> UIImage? {
        switch choice {
        case .systemDefault, .premiumEmoji:
            return nil
        case let .sfSymbol(name):
            return mtMenuIcon(.system(name), theme: theme)
        case let .imageFile(fileName):
            self.lock.lock()
            if let cached = self.imageCache[fileName] {
                self.lock.unlock()
                return cached
            }
            self.lock.unlock()
            guard let dir = Self.iconsDirectory() else {
                return nil
            }
            let url = dir.appendingPathComponent(fileName)
            guard let raw = UIImage(contentsOfFile: url.path) else {
                return nil
            }
            let targetSize = CGSize(width: 24.0, height: 24.0)
            let resized = UIGraphicsImageRenderer(size: targetSize).image { _ in
                let rect = CGRect(origin: .zero, size: targetSize)
                UIBezierPath(roundedRect: rect, cornerRadius: 6.0).addClip()
                raw.draw(in: rect)
            }.withRenderingMode(.alwaysOriginal)
            self.lock.lock()
            self.imageCache[fileName] = resized
            self.lock.unlock()
            return resized
        }
    }

    public func emojiComponent(for fileId: Int64, context: AccountContext, theme: PresentationTheme) -> AnyComponent<Empty> {
        return AnyComponent(EmojiStatusComponent(
            context: context,
            animationCache: context.animationCache,
            animationRenderer: context.animationRenderer,
            content: .animation(
                content: .customEmoji(fileId: fileId),
                size: CGSize(width: 24.0, height: 24.0),
                placeholderColor: theme.list.mediaPlaceholderColor,
                themeColor: theme.list.itemAccentColor,
                loopMode: .forever
            ),
            isVisibleForAnimations: context.sharedContext.energyUsageSettings.loopEmoji,
            action: nil
        ))
    }

    private static func iconsDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("mediatok/menu_icons", isDirectory: true)
    }
}

/// Opens the native MediaTok Section & Premium Emoji Icon Customizer.
public func mtPresentMenuIconStudio(context: MTMenuContext) {
    let vc = MTMenuIconStudioViewController(accountContext: context.context, presentationData: context.presentationData)
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .pageSheet
    context.presentNative(nav)
}

// MARK: - Studio Targets

private struct MTIconTarget {
    let key: String
    let title: String
    let subtitle: String
    let defaultIcon: MTMenuIcon
}

private func mtBuildIconTargets() -> [MTIconTarget] {
    var list: [MTIconTarget] = []
    for cat in MTMenuCategory.allCases {
        list.append(MTIconTarget(
            key: "category.\(cat.rawValue)",
            title: cat.title,
            subtitle: "Главный раздел",
            defaultIcon: cat.icon
        ))
    }
    let rootRows = MTMenuStorage.shared.rows(in: MTMenuSectionID("root.mediatokStudio"))
    for row in rootRows {
        let rowIcon = row.icon ?? .system("square.grid.2x2")
        list.append(MTIconTarget(
            key: row.id,
            title: row.title(),
            subtitle: "Эксклюзивы MediaTok",
            defaultIcon: rowIcon
        ))
    }
    for cat in MTMenuCategory.allCases {
        for section in MTMenuStorage.shared.sections(for: .category(cat)) {
            for row in MTMenuStorage.shared.rows(in: section.id) {
                guard case .tab = row.kind else { continue }
                list.append(MTIconTarget(
                    key: row.id,
                    title: row.title(),
                    subtitle: cat.title,
                    defaultIcon: row.icon ?? cat.icon
                ))
            }
        }
    }
    return list
}

private let mtCuratedSfSymbols: [(symbol: String, title: String)] = [
    ("sparkles", "Искры"),
    ("crown.fill", "Корона"),
    ("star.fill", "Звезда"),
    ("flame.fill", "Огонь"),
    ("eye.slash.fill", "Скрытый"),
    ("shield.lefthalf.filled", "Щит"),
    ("lock.fill", "Замок"),
    ("key.fill", "Ключ"),
    ("wand.and.stars", "Магия"),
    ("paintbrush.fill", "Кисть"),
    ("cube.transparent", "Стекло"),
    ("square.grid.2x2.fill", "Сетка"),
    ("magnifyingglass", "Поиск"),
    ("message.fill", "Чат"),
    ("bubble.left.and.bubble.right.fill", "Диалоги"),
    ("waveform", "Волна"),
    ("music.note", "Музыка"),
    ("play.rectangle.fill", "Видео"),
    ("camera.fill", "Камера"),
    ("phone.fill", "Звонок"),
    ("globe", "Сеть"),
    ("antenna.radiowaves.left.and.right", "Сигнал"),
    ("paperplane.fill", "Отправка"),
    ("gift.fill", "Подарок"),
    ("heart.fill", "Сердце"),
    ("moon.stars.fill", "Ночь"),
    ("sun.max.fill", "Свет"),
    ("cpu", "Процессор"),
    ("terminal.fill", "Терминал"),
    ("gearshape.fill", "Настройки"),
    ("person.crop.circle.fill", "Профиль"),
    ("person.2.fill", "Друзья"),
    ("folder.fill", "Папка"),
    ("doc.text.fill", "Документ"),
    ("bell.slash.fill", "Без звука"),
    ("checkmark.seal.fill", "Печать")
]

// MARK: - Main Icon Customizer Screen

private final class MTMenuIconStudioViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let accountContext: AccountContext
    private let presentationData: PresentationData
    private var targets: [MTIconTarget] = []
    private var pendingImageTargetKey: String?

    init(accountContext: AccountContext, presentationData: PresentationData) {
        self.accountContext = accountContext
        self.presentationData = presentationData
        super.init(style: .insetGrouped)
        self.targets = mtBuildIconTargets()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Иконки разделов"
        self.tableView.register(MTIconStudioCell.self, forCellReuseIdentifier: "MTIconStudioCell")
        self.tableView.rowHeight = 56.0
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .done, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сбросить", style: .plain, target: self, action: #selector(self.resetAllTapped))
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func resetAllTapped() {
        mtPresentMenuAlert(
            context: self.accountContext,
            title: "Сбросить все иконки?",
            text: "Все разделы и строки вернутся к чистым системным иконкам по умолчанию.",
            confirmTitle: "Сбросить",
            destructive: true,
            confirmAction: { [weak self] in
                MTCustomMenuIconStore.shared.resetAll()
                self?.tableView.reloadData()
            }
        )
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Быстрое оформление" : "Разделы и пункты меню"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return "Нажми на любой раздел ниже, чтобы поставить анимированный Telegram Premium эмодзи из твоих паков, системный SF Symbol или свою иконку из галереи."
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 1 : self.targets.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = "Авто-подбор Telegram Premium Эмодзи"
            cell.detailTextLabel?.text = "Поставить анимированные прем-эмодзи из твоих паков на главные разделы"
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.imageView?.image = UIImage(systemName: "sparkles")
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "MTIconStudioCell", for: indexPath) as! MTIconStudioCell
        let target = self.targets[indexPath.row]
        let choice = MTCustomMenuIconStore.shared.choice(for: target.key)
        cell.configure(
            target: target,
            choice: choice,
            context: self.accountContext,
            theme: self.presentationData.theme
        )
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            self.applyAutoPremiumEmojis()
            return
        }
        let target = self.targets[indexPath.row]
        self.presentPickerSheet(for: target)
    }

    private func applyAutoPremiumEmojis() {
        let _ = (self.accountContext.account.postbox.transaction { transaction -> [Int64] in
            var ids: [Int64] = []
            var seen = Set<Int64>()
            let namespaces: [ItemCollectionId.Namespace] = [
                Namespaces.ItemCollection.CloudIconStatusEmoji,
                Namespaces.ItemCollection.CloudEmojiPacks,
                Namespaces.ItemCollection.CloudIconTopicEmoji
            ]
            for ns in namespaces {
                for (collectionId, _) in transaction.getItemCollectionsInfos(namespace: ns) {
                    for item in transaction.getItemCollectionItems(collectionId: collectionId) {
                        if let sticker = item as? StickerPackItem {
                            let fileId = sticker.file._parse().fileId.id
                            if fileId != 0 && !seen.contains(fileId) {
                                seen.insert(fileId)
                                ids.append(fileId)
                                if ids.count >= 40 {
                                    return ids
                                }
                            }
                        }
                    }
                }
            }
            return ids
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] fileIds in
            guard let self else { return }
            guard !fileIds.isEmpty else {
                mtPresentMenuAlert(
                    context: self.accountContext,
                    title: "Нет загруженных Прем-эмодзи",
                    text: "Открой клавиатуру эмодзи в любом чате на секунду, чтобы Telegram подгрузил паки Premium Эмодзи, либо введи fileId вручную."
                )
                return
            }
            let count = min(self.targets.count, min(fileIds.count, 16))
            for idx in 0 ..< count {
                MTCustomMenuIconStore.shared.setChoice(.premiumEmoji(fileId: fileIds[idx]), for: self.targets[idx].key)
            }
            self.tableView.reloadData()
        })
    }

    private func presentPickerSheet(for target: MTIconTarget) {
        mtPresentMenuActionSheet(
            context: self.accountContext,
            title: target.title,
            buttons: [
                ("Telegram Premium Эмодзи (из моих паков)", false, { [weak self] in
                    guard let self else { return }
                    let picker = MTPremiumEmojiGridViewController(
                        accountContext: self.accountContext,
                        theme: self.presentationData.theme,
                        sectionTitle: target.title,
                        onSelect: { [weak self] fileId in
                            MTCustomMenuIconStore.shared.setChoice(.premiumEmoji(fileId: fileId), for: target.key)
                            self?.tableView.reloadData()
                        }
                    )
                    self.navigationController?.pushViewController(picker, animated: true)
                }),
                ("Ввести ID Premium Эмодзи вручную", false, { [weak self] in
                    self?.presentManualEmojiIdAlert(for: target)
                }),
                ("Системная иконка (SF Symbol)", false, { [weak self] in
                    guard let self else { return }
                    let picker = MTSfSymbolPickerViewController(accountContext: self.accountContext, sectionTitle: target.title) { [weak self] symbolName in
                        MTCustomMenuIconStore.shared.setChoice(.sfSymbol(symbolName), for: target.key)
                        self?.tableView.reloadData()
                    }
                    self.navigationController?.pushViewController(picker, animated: true)
                }),
                ("Своя картинка из Галереи", false, { [weak self] in
                    guard let self else { return }
                    self.pendingImageTargetKey = target.key
                    let picker = UIImagePickerController()
                    picker.sourceType = .photoLibrary
                    picker.allowsEditing = true
                    picker.delegate = self
                    self.present(picker, animated: true)
                }),
                ("Сбросить по умолчанию", true, { [weak self] in
                    MTCustomMenuIconStore.shared.setChoice(.systemDefault, for: target.key)
                    self?.tableView.reloadData()
                })
            ]
        )
    }

    private func presentManualEmojiIdAlert(for target: MTIconTarget) {
        mtPresentMenuPrompt(
            context: self.accountContext,
            title: "ID Telegram Premium Эмодзи",
            subtitle: "Вставь числовой documentId кастомного эмодзи (например 5368324170671202286):",
            placeholder: "5368324170671202286",
            characterLimit: 32,
            apply: { [weak self] rawVal in
                let raw = rawVal.trimmingCharacters(in: .whitespacesAndNewlines)
                if let fileId = Int64(raw), fileId != 0 {
                    MTCustomMenuIconStore.shared.setChoice(.premiumEmoji(fileId: fileId), for: target.key)
                    self?.tableView.reloadData()
                }
            }
        )
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let key = self.pendingImageTargetKey else { return }
        self.pendingImageTargetKey = nil
        let picked = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        if let image = picked {
            let _ = MTCustomMenuIconStore.shared.saveCustomImage(image, for: key)
            self.tableView.reloadData()
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.pendingImageTargetKey = nil
        picker.dismiss(animated: true)
    }
}

private final class MTIconStudioCell: UITableViewCell {
    private let iconImageView = UIImageView()
    private let emojiHostView = ComponentHostView<Empty>()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.accessoryType = .disclosureIndicator

        self.iconImageView.contentMode = .scaleAspectFit
        self.emojiHostView.isUserInteractionEnabled = false

        self.titleLabel.font = .systemFont(ofSize: 16.0, weight: .regular)
        self.titleLabel.textColor = .label
        self.subtitleLabel.font = .systemFont(ofSize: 12.0, weight: .regular)
        self.subtitleLabel.textColor = .secondaryLabel
        self.badgeLabel.font = .systemFont(ofSize: 12.0, weight: .medium)
        self.badgeLabel.textColor = .secondaryLabel
        self.badgeLabel.textAlignment = .right

        self.contentView.addSubview(self.iconImageView)
        self.contentView.addSubview(self.emojiHostView)
        self.contentView.addSubview(self.titleLabel)
        self.contentView.addSubview(self.subtitleLabel)
        self.contentView.addSubview(self.badgeLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(target: MTIconTarget, choice: MTCustomMenuIconChoice, context: AccountContext, theme: PresentationTheme) {
        self.titleLabel.text = target.title
        self.subtitleLabel.text = target.subtitle
        switch choice {
        case .systemDefault:
            self.emojiHostView.isHidden = true
            self.iconImageView.isHidden = false
            self.iconImageView.image = mtMenuIcon(target.defaultIcon, theme: theme)
            self.badgeLabel.text = "Стандарт"
        case let .premiumEmoji(fileId):
            self.iconImageView.isHidden = true
            self.emojiHostView.isHidden = false
            let component = MTCustomMenuIconStore.shared.emojiComponent(for: fileId, context: context, theme: theme)
            let _ = self.emojiHostView.update(
                transition: .immediate,
                component: component,
                environment: {},
                containerSize: CGSize(width: 26.0, height: 26.0)
            )
            self.badgeLabel.text = "Premium"
        case let .sfSymbol(name):
            self.emojiHostView.isHidden = true
            self.iconImageView.isHidden = false
            self.iconImageView.image = MTCustomMenuIconStore.shared.resolvedImage(for: choice, theme: theme)
            self.badgeLabel.text = name
        case .imageFile:
            self.emojiHostView.isHidden = true
            self.iconImageView.isHidden = false
            self.iconImageView.image = MTCustomMenuIconStore.shared.resolvedImage(for: choice, theme: theme)
            self.badgeLabel.text = "Фото"
        }
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        let iconFrame = CGRect(x: 16.0, y: floor((bounds.height - 26.0) / 2.0), width: 26.0, height: 26.0)
        self.iconImageView.frame = iconFrame
        self.emojiHostView.frame = iconFrame

        let badgeW: CGFloat = 78.0
        self.badgeLabel.frame = CGRect(x: bounds.width - badgeW - 6.0, y: floor((bounds.height - 18.0) / 2.0), width: badgeW, height: 18.0)

        let textX: CGFloat = 56.0
        let textW = max(60.0, self.badgeLabel.frame.minX - textX - 8.0)
        self.titleLabel.frame = CGRect(x: textX, y: 10.0, width: textW, height: 20.0)
        self.subtitleLabel.frame = CGRect(x: textX, y: 31.0, width: textW, height: 15.0)
    }
}

// MARK: - Live Telegram Premium Emoji Grid Picker

private final class MTPremiumEmojiGridViewController: UICollectionViewController {
    private let accountContext: AccountContext
    private let theme: PresentationTheme
    private let isModalRoot: Bool
    private let onSelect: (Int64) -> Void
    private var fileIds: [Int64] = []

    init(accountContext: AccountContext, theme: PresentationTheme, sectionTitle: String, isModalRoot: Bool = false, onSelect: @escaping (Int64) -> Void) {
        self.accountContext = accountContext
        self.theme = theme
        self.isModalRoot = isModalRoot
        self.onSelect = onSelect
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 52.0, height: 52.0)
        layout.minimumInteritemSpacing = 10.0
        layout.minimumLineSpacing = 12.0
        layout.sectionInset = UIEdgeInsets(top: 16.0, left: 16.0, bottom: 24.0, right: 16.0)
        super.init(collectionViewLayout: layout)
        self.title = sectionTitle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func closeModalTapped() {
        self.dismiss(animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if self.isModalRoot {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(self.closeModalTapped))
        }
        self.collectionView.backgroundColor = .systemGroupedBackground
        self.collectionView.register(MTPremiumEmojiGridCell.self, forCellWithReuseIdentifier: "MTPremiumEmojiGridCell")

        let _ = (self.accountContext.account.postbox.transaction { transaction -> [Int64] in
            var result: [Int64] = []
            var seen = Set<Int64>()
            let namespaces: [ItemCollectionId.Namespace] = [
                Namespaces.ItemCollection.CloudIconStatusEmoji,
                Namespaces.ItemCollection.CloudEmojiPacks,
                Namespaces.ItemCollection.CloudIconTopicEmoji
            ]
            for ns in namespaces {
                for (collectionId, _) in transaction.getItemCollectionsInfos(namespace: ns) {
                    for item in transaction.getItemCollectionItems(collectionId: collectionId) {
                        if let sticker = item as? StickerPackItem {
                            let fid = sticker.file._parse().fileId.id
                            if fid != 0 && !seen.contains(fid) {
                                seen.insert(fid)
                                result.append(fid)
                                if result.count >= 360 {
                                    return result
                                }
                            }
                        }
                    }
                }
            }
            return result
        } |> deliverOnMainQueue).startStandalone(next: { [weak self] ids in
            guard let self else { return }
            self.fileIds = ids
            self.collectionView.reloadData()
            if ids.isEmpty {
                let empty = UILabel()
                empty.text = "Паки Telegram Premium Эмодзи ещё не закэшированы.\nОткрой вкладку эмодзи в любом чате и вернись сюда."
                empty.numberOfLines = 0
                empty.textAlignment = .center
                empty.textColor = .secondaryLabel
                empty.font = .systemFont(ofSize: 14.0)
                self.collectionView.backgroundView = empty
            } else {
                self.collectionView.backgroundView = nil
            }
        })
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.fileIds.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MTPremiumEmojiGridCell", for: indexPath) as! MTPremiumEmojiGridCell
        let fileId = self.fileIds[indexPath.item]
        cell.configure(fileId: fileId, context: self.accountContext, theme: self.theme)
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let fileId = self.fileIds[indexPath.item]
        self.onSelect(fileId)
        if self.isModalRoot {
            self.dismiss(animated: true)
        } else {
            let _ = self.navigationController?.popViewController(animated: true)
        }
    }
}

/// Reusable live Telegram Premium Emoji picker backed by the account's cached Postbox emoji packs.
public func mtPresentPremiumEmojiPicker(context: AccountContext, title: String, onSelect: @escaping (Int64) -> Void) {
    let theme = context.sharedContext.currentPresentationData.with { $0 }.theme
    let picker = MTPremiumEmojiGridViewController(accountContext: context, theme: theme, sectionTitle: title, isModalRoot: true) { fileId in
        onSelect(fileId)
    }
    let nav = UINavigationController(rootViewController: picker)
    nav.modalPresentationStyle = .pageSheet
    MTModalPresenter.presentOnTopmost(nav)
}

private final class MTPremiumEmojiGridCell: UICollectionViewCell {
    private let hostView = ComponentHostView<Empty>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.backgroundColor = .secondarySystemGroupedBackground
        self.contentView.layer.cornerRadius = 12.0
        self.contentView.layer.masksToBounds = true
        self.hostView.isUserInteractionEnabled = false
        self.contentView.addSubview(self.hostView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(fileId: Int64, context: AccountContext, theme: PresentationTheme) {
        let component = AnyComponent(EmojiStatusComponent(
            context: context,
            animationCache: context.animationCache,
            animationRenderer: context.animationRenderer,
            content: .animation(
                content: .customEmoji(fileId: fileId),
                size: CGSize(width: 34.0, height: 34.0),
                placeholderColor: theme.list.mediaPlaceholderColor,
                themeColor: theme.list.itemAccentColor,
                loopMode: .forever
            ),
            isVisibleForAnimations: context.sharedContext.energyUsageSettings.loopEmoji,
            action: nil
        ))
        let _ = self.hostView.update(
            transition: .immediate,
            component: component,
            environment: {},
            containerSize: CGSize(width: 34.0, height: 34.0)
        )
        self.hostView.frame = CGRect(x: 9.0, y: 9.0, width: 34.0, height: 34.0)
    }
}

// MARK: - SF Symbol Picker

private final class MTSfSymbolPickerViewController: UITableViewController {
    private let accountContext: AccountContext
    private let onSelect: (String) -> Void

    init(accountContext: AccountContext, sectionTitle: String, onSelect: @escaping (String) -> Void) {
        self.accountContext = accountContext
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        self.title = sectionTitle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Ввести имя", style: .plain, target: self, action: #selector(self.manualInputTapped))
    }

    @objc private func manualInputTapped() {
        mtPresentMenuPrompt(
            context: self.accountContext,
            title: "Имя SF Symbol",
            subtitle: "Введи любое системное имя SF Symbol (например bolt.shield.fill или crown):",
            placeholder: "crown.fill",
            characterLimit: 64,
            apply: { [weak self] rawName in
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, UIImage(systemName: name) != nil {
                    self?.onSelect(name)
                    let _ = self?.navigationController?.popViewController(animated: true)
                }
            }
        )
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return mtCuratedSfSymbols.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "sfCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "sfCell")
        let entry = mtCuratedSfSymbols[indexPath.row]
        cell.textLabel?.text = entry.title
        cell.detailTextLabel?.text = entry.symbol
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: entry.symbol)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.onSelect(mtCuratedSfSymbols[indexPath.row].symbol)
        let _ = self.navigationController?.popViewController(animated: true)
    }
}
