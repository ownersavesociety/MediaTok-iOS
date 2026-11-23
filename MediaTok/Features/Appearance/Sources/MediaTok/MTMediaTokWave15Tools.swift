import Foundation
import UIKit
import CoreImage
import MediaPlayer
import UniformTypeIdentifiers
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ContextUI
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

// ============================================================================
// MediaTok Wave 15 — Profile FX, Rich Presence, Portals Browser, Roulette & Craft, NFT QR/JSON:
//   #3 / #6 / #7   — Avatar Frames & Nickname Glow/Shimmer/Gradient studio (.nickfx / .avatarframe)
//   #8 / #10       — Live Now Playing (Apple Music) + Discord Lanyard Rich Presence (.nowplaying / .lanyard)
//   #51 / #52      — Built-in Portals NFT Market Browser with Rarity Filters (<0.5%, 1%, Rare, Epic, Legendary) (.portals)
//   #82 / #83      — Interactive Upgrade Roulette & Cross-Craft Simulator (.roulette / .craft)
//   #85 / #86      — NFT Collection JSON Export/Import & QR Code Transfer (.nftexport / .nftqr)
// ============================================================================

public struct MTProfileFxConfig: Codable, Equatable {
    public var avatarFrameStyle: String   // "none", "neon", "gold", "sakura", "fire", "rainbow"
    public var nickEffectStyle: String    // "none", "glow", "shimmer", "gradient"
    public var nickColorHex: String       // e.g. "#7C5CFF"
    public var discordUserId: String      // For Lanyard live Spotify/Game status
    public var autoSyncNowPlaying: Bool

    private enum CodingKeys: String, CodingKey {
        case avatarFrameStyle
        case nickEffectStyle
        case nickColorHex
        case discordUserId
        case autoSyncNowPlaying
    }

    public static let `default` = MTProfileFxConfig(
        avatarFrameStyle: "none",
        nickEffectStyle: "none",
        nickColorHex: "#7C5CFF",
        discordUserId: "",
        autoSyncNowPlaying: false
    )
}

public struct MTPortalsCatalogItem: Codable, Equatable {
    public let id: String
    public let name: String
    public let nameRu: String
    public let model: String
    public let backdrop: String
    public let symbol: String
    public let rarityPercent: Double
    public let floorTon: Double
    public let tier: String // "Legendary", "Epic", "Rare", "Uncommon"
    public let accentHex: UInt32

    private enum CodingKeys: String, CodingKey {
        case id, name, nameRu, model, backdrop, symbol, rarityPercent, floorTon, tier, accentHex
    }
}

public enum MTMediaTokWave15Tools {
    private static let fxConfigKey = "mediatok.wave15.profile_fx.v1"
    private static let savedNftsKey = "mediatok.wave15.custom_nfts.v1"
    private static var activeNftImportCoordinator: MTNftJsonDocumentCoordinator?

    public static func register() {
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave15Tools.interceptCommands(request)
        }, order: 37)
    }

    // MARK: - Persistence

    public static func loadFxConfig() -> MTProfileFxConfig {
        guard let data = UserDefaults.standard.data(forKey: fxConfigKey),
              let cfg = try? JSONDecoder().decode(MTProfileFxConfig.self, from: data) else {
            return .default
        }
        return cfg
    }

    public static func saveFxConfig(_ cfg: MTProfileFxConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: fxConfigKey)
        }
    }

    public static func loadSavedCustomNfts() -> [MTPortalsCatalogItem] {
        guard let data = UserDefaults.standard.data(forKey: savedNftsKey),
              let arr = try? JSONDecoder().decode([MTPortalsCatalogItem].self, from: data) else {
            return []
        }
        return arr
    }

    public static func saveCustomNft(_ item: MTPortalsCatalogItem) {
        var list = loadSavedCustomNfts()
        list.removeAll { $0.id == item.id }
        list.insert(item, at: 0)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: savedNftsKey)
        }
    }

    fileprivate static func discordFrameId(for style: String) -> String {
        switch style {
        case "neon": return "neon_cyan"
        case "gold": return "gold"
        case "sakura": return "sakura"
        case "fire": return "fire"
        case "rainbow": return "rainbow"
        default: return "none"
        }
    }

    fileprivate static func fxFrameStyle(for discordFrameId: String) -> String {
        switch discordFrameId {
        case "neon_cyan": return "neon"
        case "gold": return "gold"
        case "sakura": return "sakura"
        case "fire": return "fire"
        case "rainbow": return "rainbow"
        default: return "none"
        }
    }

    public static func replaceSavedCustomNfts(_ items: [MTPortalsCatalogItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: savedNftsKey)
        }
    }

    // MARK: - Curated Portals NFT Catalog

    public static let catalog: [MTPortalsCatalogItem] = [
        MTPortalsCatalogItem(id: "pepe_onyx", name: "Plush Pepe", nameRu: "Плюшевый Пепе", model: "Onyx Black", backdrop: "Midnight Onyx", symbol: "Crown", rarityPercent: 0.2, floorTon: 980.0, tier: "Legendary", accentHex: 0x34D399),
        MTPortalsCatalogItem(id: "pepe_gold", name: "Plush Pepe", nameRu: "Плюшевый Пепе", model: "Golden Frog", backdrop: "Pure Gold", symbol: "Diamond", rarityPercent: 0.3, floorTon: 740.0, tier: "Legendary", accentHex: 0xFBBF24),
        MTPortalsCatalogItem(id: "durov_cap_neon", name: "Durov's Cap", nameRu: "Кепка Дурова", model: "Cyberpunk", backdrop: "Electric Indigo", symbol: "Lightning", rarityPercent: 0.4, floorTon: 520.0, tier: "Legendary", accentHex: 0x818CF8),
        MTPortalsCatalogItem(id: "astral_shard_void", name: "Astral Shard", nameRu: "Астральный осколок", model: "Void Crystal", backdrop: "Obsidian", symbol: "Star", rarityPercent: 0.5, floorTon: 210.0, tier: "Legendary", accentHex: 0xA78BFA),
        MTPortalsCatalogItem(id: "loot_bag_diamond", name: "Loot Bag", nameRu: "Мешок лута", model: "Diamond Sack", backdrop: "Sapphire", symbol: "Gem", rarityPercent: 0.8, floorTon: 145.0, tier: "Epic", accentHex: 0x38BDF8),
        MTPortalsCatalogItem(id: "heart_locket_ruby", name: "Heart Locket", nameRu: "Медальон сердце", model: "Crimson Ruby", backdrop: "Velvet Red", symbol: "Heart", rarityPercent: 0.9, floorTon: 310.0, tier: "Epic", accentHex: 0xFB7185),
        MTPortalsCatalogItem(id: "swiss_watch_gold", name: "Swiss Watch", nameRu: "Швейцарские часы", model: "Chrono Gold", backdrop: "Emerald", symbol: "Clock", rarityPercent: 1.0, floorTon: 95.0, tier: "Epic", accentHex: 0x10B981),
        MTPortalsCatalogItem(id: "scared_cat_ghost", name: "Scared Cat", nameRu: "Напуганный кот", model: "Phantom", backdrop: "Mystic Purple", symbol: "Moon", rarityPercent: 1.2, floorTon: 68.0, tier: "Rare", accentHex: 0xC084FC),
        MTPortalsCatalogItem(id: "ion_gem_plasma", name: "Ion Gem", nameRu: "Ионный камень", model: "Plasma Core", backdrop: "Neon Cyan", symbol: "Atom", rarityPercent: 1.5, floorTon: 48.0, tier: "Rare", accentHex: 0x22D3EE),
        MTPortalsCatalogItem(id: "vintage_cigar_king", name: "Vintage Cigar", nameRu: "Винтажная сигара", model: "Royal Smoke", backdrop: "Amber", symbol: "Flame", rarityPercent: 2.0, floorTon: 34.0, tier: "Rare", accentHex: 0xF59E0B),
        MTPortalsCatalogItem(id: "perfume_bottle_rose", name: "Perfume Bottle", nameRu: "Флакон духов", model: "Sakura Bloom", backdrop: "Rose Quartz", symbol: "Petal", rarityPercent: 2.5, floorTon: 26.0, tier: "Uncommon", accentHex: 0xF472B6),
        MTPortalsCatalogItem(id: "magic_potion_toxic", name: "Magic Potion", nameRu: "Магическое зелье", model: "Toxic Neon", backdrop: "Matrix Green", symbol: "Skull", rarityPercent: 3.0, floorTon: 19.5, tier: "Uncommon", accentHex: 0x4ADE80)
    ]

    // MARK: - Top VC Helper

    private static func topViewController() -> UIViewController? {
        return MTModalPresenter.topmostViewController()
    }

    // MARK: - Slash Commands

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(".") else { return false }
        let lower = raw.lowercased()

        if lower == ".nickfx" || lower == ".avatarframe" || lower == ".profilefx" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentProfileFxStudio(context: request.context) }
            return true
        }
        if lower == ".nowplaying" || lower == ".musicstatus" || lower == ".lanyard" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { syncNowPlayingOrLanyardStatus(context: request.context) }
            return true
        }
        if lower == ".portals" || lower == ".nftmarket" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentPortalsBrowser(context: request.context) }
            return true
        }
        if lower == ".roulette" || lower == ".upgrade" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentUpgradeRoulette(context: request.context) }
            return true
        }
        if lower == ".craft" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentCraftSimulator(context: request.context) }
            return true
        }
        if lower == ".nftexport" || lower == ".nftjson" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentNftJsonManager(context: request.context) }
            return true
        }
        if lower == ".nftqr" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentNftQrTransfer(context: request.context, item: loadSavedCustomNfts().first ?? catalog[0]) }
            return true
        }

        return false
    }

    // MARK: - #3/#6/#7 Profile FX Studio

    public static func presentProfileFxStudio(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            mtPresentNativeToast(context: context, text: "Паник-режим активен: эффекты профиля скрыты")
            return
        }
        let controller = mtMakeNativeProfileFxStudioController(context: context)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #8/#10 Now Playing & Discord Lanyard Live Status

    public static func syncNowPlayingOrLanyardStatus(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            MTMediaTokWave5Tools.showToast(context: context, text: "Паник-режим активен: live-статус замаскирован")
            return
        }
        let authStatus = MPMediaLibrary.authorizationStatus()
        if authStatus == .notDetermined {
            MPMediaLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    continueNowPlayingOrLanyardSync(context: context, allowAppleMusic: status == .authorized)
                }
            }
        } else {
            continueNowPlayingOrLanyardSync(context: context, allowAppleMusic: authStatus == .authorized)
        }
    }

    private static func continueNowPlayingOrLanyardSync(context: AccountContext, allowAppleMusic: Bool) {
        let cfg = loadFxConfig()
        // 1. Check Apple Music / System Now Playing first (only when TCC permission is granted)
        if allowAppleMusic,
           let item = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem,
           let title = item.title, !title.isEmpty {
            let artist = item.artist ?? ""
            let statusLine = artist.isEmpty ? "Слушает: \(title)" : "Слушает: \(artist) — \(title)"
            applyCustomStatusText(context: context, statusText: statusLine)
            MTMediaTokWave5Tools.showToast(context: context, text: "Музыкальный статус обновлён: \(statusLine)")
            return
        }

        // 2. Check Discord Lanyard Rich Presence if Discord User ID is configured
        let discordId = cfg.discordUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !discordId.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: context, text: "Сейчас ничего не играет. Укажите Discord ID в .nickfx для синхронизации Spotify/Игр.")
            return
        }
        let isValidDiscordId = discordId.allSatisfy(\.isNumber) && (17 ... 20).contains(discordId.count)
        guard isValidDiscordId,
              let encodedId = discordId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lanyard.rest/v1/users/\(encodedId)") else {
            MTMediaTokWave5Tools.showToast(context: context, text: "Некорректный Discord User ID (ожидается 17–20 цифр)")
            return
        }

        MTMediaTokWave5Tools.showToast(context: context, text: "Синхронизирую Discord Lanyard...")
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["data"] as? [String: Any] else {
                DispatchQueue.main.async {
                    MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось получить статус Discord Lanyard")
                }
                return
            }

            var statusText: String? = nil
            if let spotify = payload["spotify"] as? [String: Any],
               let song = spotify["song"] as? String {
                let artist = (spotify["artist"] as? String) ?? ""
                statusText = artist.isEmpty ? "Spotify: \(song)" : "Spotify: \(artist) — \(song)"
            } else if let activities = payload["activities"] as? [[String: Any]] {
                if let game = activities.first(where: { ($0["type"] as? Int) == 0 }),
                   let name = game["name"] as? String {
                    statusText = "Играет в \(name)"
                }
            }

            DispatchQueue.main.async {
                if let text = statusText {
                    applyCustomStatusText(context: context, statusText: text)
                    MTMediaTokWave5Tools.showToast(context: context, text: "Статус обновлён: \(text)")
                } else {
                    MTMediaTokWave5Tools.showToast(context: context, text: "В Discord сейчас нет активной музыки или игры")
                }
            }
        }.resume()
    }

    private static func applyCustomStatusText(context: AccountContext, statusText: String) {
        if let key = MTPeerKey(namespace: Int32(context.account.peerId.namespace._internalGetInt32Value()), id: context.account.peerId.id._internalGetInt64Value()) {
            var ov = MTVisualProfileStore.shared.override(for: key) ?? MTVisualPeerOverride()
            ov.customOnlineStatus = statusText
            MTVisualProfileStore.shared.setOverride(ov, for: key)
        }
        var profile = MTDiscordProfileStore.shared.profile(for: context.account.peerId) ?? MTDiscordProfileData()
        profile.customStatus = String(statusText.prefix(140))
        MTDiscordProfileStore.shared.setProfile(profile, for: context.account.peerId, publishGlobally: true)
    }

    // MARK: - #51/#52 Portals Browser

    public static func presentPortalsBrowser(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            mtPresentNativeToast(context: context, text: "Паник-режим активен: Portals NFT скрыт")
            return
        }
        let controller = mtMakeNativePortalsBrowserController(context: context)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #82 Upgrade Roulette

    public static func presentUpgradeRoulette(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            mtPresentNativeToast(context: context, text: "Паник-режим активен: рулетка NFT скрыта")
            return
        }
        let controller = mtMakeNativeUpgradeRouletteController(context: context)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #83 Craft Simulator

    public static func presentCraftSimulator(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            mtPresentNativeToast(context: context, text: "Паник-режим активен: крафт NFT скрыт")
            return
        }
        let models = ["Plush Pepe", "Durov's Cap", "Astral Shard", "Heart Locket", "Loot Bag", "Swiss Watch"]
        let backdrops = ["Midnight Onyx", "Pure Gold", "Electric Indigo", "Velvet Red", "Neon Cyan", "Matrix Green"]
        let symbols = ["Crown", "Diamond", "Lightning", "Star", "Flame", "Skull"]

        let pickedModel = models.randomElement() ?? "Plush Pepe"
        let pickedBackdrop = backdrops.randomElement() ?? "Midnight Onyx"
        let pickedSymbol = symbols.randomElement() ?? "Crown"
        let niceNumbers = [1, 7, 13, 69, 77, 100, 333, 666, 777, 888, 1337]
        let num = niceNumbers.randomElement() ?? 777
        let crafted = MTPortalsCatalogItem(
            id: "craft_\(UUID().uuidString.prefix(8))",
            name: "\(pickedModel) #\(num)",
            nameRu: "Крафт: \(pickedModel) #\(num)",
            model: "Crafted \(pickedModel)",
            backdrop: pickedBackdrop,
            symbol: pickedSymbol,
            rarityPercent: 0.1,
            floorTon: Double(Int.random(in: 120 ... 990)),
            tier: "Legendary",
            accentHex: 0xA855F7
        )

        mtPresentNativeActionSheet(
            context: context,
            title: "Крафт NFT завершён: \(crafted.name) · Фон: \(crafted.backdrop) · Узор: \(crafted.symbol) · 0.1% (\(Int(crafted.floorTon)) TON)",
            buttons: [
                ("Сохранить в коллекцию", false, {
                    saveCustomNft(crafted)
                    mtPresentNativeToast(context: context, text: "Крафт \(crafted.name) сохранён в коллекцию")
                }),
                ("QR-передача NFT", false, {
                    saveCustomNft(crafted)
                    presentNftQrTransfer(context: context, item: crafted)
                }),
                ("Скрафтить ещё", false, {
                    presentCraftSimulator(context: context)
                })
            ]
        )
    }

    // MARK: - #85 NFT JSON Export / Import

    public static func presentNftJsonManager(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            mtPresentNativeToast(context: context, text: "Паник-режим активен: коллекция NFT скрыта")
            return
        }
        let saved = loadSavedCustomNfts()
        mtPresentNativeActionSheet(
            context: context,
            title: "Коллекция NFT (JSON) · Сохранено: \(saved.count)",
            buttons: [
                ("Экспортировать в JSON и поделиться", false, {
                    guard !saved.isEmpty else {
                        mtPresentNativeToast(context: context, text: "Коллекция кастомных NFT пуста")
                        return
                    }
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted]
                    if let data = try? enc.encode(saved), let str = String(data: data, encoding: .utf8) {
                        UIPasteboard.general.string = str
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mediatok_nfts_\(Int(Date().timeIntervalSince1970)).json")
                        try? data.write(to: url)
                        guard let top = topViewController() else { return }
                        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        share.completionWithItemsHandler = { _, _, _, _ in
                            try? FileManager.default.removeItem(at: url)
                        }
                        if let pop = share.popoverPresentationController {
                            pop.sourceView = top.view
                            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                        }
                        top.present(share, animated: true)
                    }
                }),
                ("Импортировать JSON из Файлов", false, {
                    guard let host = topViewController() else { return }
                    let coordinator = MTNftJsonDocumentCoordinator(context: context) {
                        activeNftImportCoordinator = nil
                    }
                    activeNftImportCoordinator = coordinator
                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json, UTType.data])
                    picker.delegate = coordinator
                    host.present(picker, animated: true)
                }),
                ("Импортировать JSON из буфера обмена", false, {
                    guard let raw = UIPasteboard.general.string,
                          let data = raw.data(using: .utf8),
                          importNftJsonData(data, context: context) else {
                        mtPresentNativeToast(context: context, text: "В буфере обмена нет корректного JSON коллекции MediaTok")
                        return
                    }
                })
            ]
        )
    }

    @discardableResult
    fileprivate static func importNftJsonData(_ data: Data, context: AccountContext) -> Bool {
        guard let imported = try? JSONDecoder().decode([MTPortalsCatalogItem].self, from: data) else {
            return false
        }
        var merged = loadSavedCustomNfts()
        var existingIds = Set(merged.map(\.id))
        var addedCount = 0
        for item in imported where !existingIds.contains(item.id) {
            merged.append(item)
            existingIds.insert(item.id)
            addedCount += 1
        }
        replaceSavedCustomNfts(merged)
        MTMediaTokWave5Tools.showToast(context: context, text: "Импортировано \(addedCount) новых NFT (всего: \(merged.count))")
        return true
    }

    // MARK: - #86 NFT QR Transfer

    public static func presentNftQrTransfer(context: AccountContext, item: MTPortalsCatalogItem) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            MTMediaTokWave5Tools.showToast(context: context, text: "Паник-режим активен: QR-передача NFT скрыта")
            return
        }
        guard let top = topViewController() else { return }
        let payload = (try? JSONEncoder().encode([item])).flatMap { String(data: $0, encoding: .utf8) } ?? item.name
        let qrImage = generateQrImage(from: payload, size: 240)

        let vc = UIViewController()
        vc.title = "QR-передача NFT"
        vc.view.backgroundColor = .systemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let imgView = UIImageView(image: qrImage)
        imgView.layer.magnificationFilter = .nearest
        imgView.contentMode = .scaleAspectFit
        imgView.backgroundColor = .white
        imgView.layer.cornerRadius = 16
        imgView.clipsToBounds = true
        imgView.translatesAutoresizingMaskIntoConstraints = false

        let titleLbl = UILabel()
        titleLbl.text = "\(item.name) · \(item.model)"
        titleLbl.font = .systemFont(ofSize: 18, weight: .bold)

        let subLbl = UILabel()
        subLbl.text = "Фон: \(item.backdrop) · Узор: \(item.symbol)\nРедкость: \(item.rarityPercent)% · Оценка: \(Int(item.floorTon)) TON"
        subLbl.font = .systemFont(ofSize: 13)
        subLbl.textColor = .secondaryLabel
        subLbl.numberOfLines = 0
        subLbl.textAlignment = .center

        stack.addArrangedSubview(imgView)
        stack.addArrangedSubview(titleLbl)
        stack.addArrangedSubview(subLbl)
        vc.view.addSubview(stack)

        NSLayoutConstraint.activate([
            imgView.widthAnchor.constraint(equalToConstant: 240),
            imgView.heightAnchor.constraint(equalToConstant: 240),
            stack.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: vc.view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: vc.view.trailingAnchor, constant: -20)
        ])

        let nav = UINavigationController(rootViewController: vc)
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak nav] _ in
            nav?.dismiss(animated: true)
        })
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    private static func generateQrImage(from string: String, size: CGFloat) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaleX = size / output.extent.size.width
        let scaleY = size / output.extent.size.height
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private final class MTNftJsonDocumentCoordinator: NSObject, UIDocumentPickerDelegate {
    private let context: AccountContext
    private let onComplete: () -> Void

    init(context: AccountContext, onComplete: @escaping () -> Void) {
        self.context = context
        self.onComplete = onComplete
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        defer { self.onComplete() }
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              MTMediaTokWave15Tools.importNftJsonData(data, context: self.context) else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Файл не содержит корректный JSON коллекции MediaTok")
            return
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.onComplete()
    }
}

// MARK: - #3/#6/#7 Native Profile FX Studio Controller

private func mtMakeNativeProfileFxStudioController(context: AccountContext) -> ViewController {
    var initial = MTMediaTokWave15Tools.loadFxConfig()
    if let profile = MTDiscordProfileStore.shared.profile(for: context.account.peerId) {
        let mapped = MTMediaTokWave15Tools.fxFrameStyle(for: profile.avatarFrameId)
        if mapped != "none" {
            initial.avatarFrameStyle = mapped
        }
    }
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)

    let frames: [(key: String, title: String)] = [
        ("none", "Без рамки"),
        ("neon", "Неон"),
        ("gold", "Золото"),
        ("sakura", "Сакура"),
        ("fire", "Огонь"),
        ("rainbow", "Радуга")
    ]
    let nickEffects: [(key: String, title: String)] = [
        ("none", "Обычный"),
        ("glow", "Свечение"),
        ("shimmer", "Перелив"),
        ("gradient", "Градиент")
    ]

    let persist: (MTProfileFxConfig) -> Void = { cfg in
        MTMediaTokWave15Tools.saveFxConfig(cfg)
        var profile = MTDiscordProfileStore.shared.profile(for: context.account.peerId) ?? MTDiscordProfileData()
        profile.avatarFrameId = MTMediaTokWave15Tools.discordFrameId(for: cfg.avatarFrameStyle)
        MTDiscordProfileStore.shared.setProfile(profile, for: context.account.peerId, publishGlobally: true)
    }

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { cfg in
        var model = MTNativeScreenModel(title: "Эффекты профиля")

        var frameSection: [MTNativeRow] = [.init(id: "f_hdr", kind: .header("Рамка аватара"))]
        for f in frames {
            let id = "frame_\(f.key)"
            frameSection.append(.init(id: id, kind: .check(title: f.title, subtitle: nil, checked: cfg.avatarFrameStyle == f.key)))
            model.tap[id] = {
                let next = stateValue.modify { cur in
                    var c = cur
                    c.avatarFrameStyle = f.key
                    return c
                }
                persist(next)
                statePromise.set(next)
            }
        }
        model.sections.append(frameSection)

        var nickSection: [MTNativeRow] = [.init(id: "n_hdr", kind: .header("Стиль имени"))]
        for n in nickEffects {
            let id = "nick_\(n.key)"
            nickSection.append(.init(id: id, kind: .check(title: n.title, subtitle: nil, checked: cfg.nickEffectStyle == n.key)))
            model.tap[id] = {
                let next = stateValue.modify { cur in
                    var c = cur
                    c.nickEffectStyle = n.key
                    return c
                }
                persist(next)
                statePromise.set(next)
            }
        }
        model.sections.append(nickSection)

        model.sections.append([
            .init(id: "l_hdr", kind: .header("Музыкальный и игровой Live-статус")),
            .init(id: "discord_id", kind: .input(text: cfg.discordUserId, placeholder: "Discord User ID (17–20 цифр для Lanyard)")),
            .init(id: "sync_now", kind: .action(title: "Синхронизировать Live-статус сейчас", destructive: false, enabled: true)),
            .init(id: "l_ftr", kind: .footer("Берёт текущий трек из Apple Music или активную музыку/игру из Discord Lanyard."))
        ])
        model.text["discord_id"] = { val in
            let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
            let next = stateValue.modify { cur in
                var c = cur
                c.discordUserId = trimmed
                return c
            }
            MTMediaTokWave15Tools.saveFxConfig(next)
        }
        model.tap["sync_now"] = {
            MTMediaTokWave15Tools.syncNowPlayingOrLanyardStatus(context: context)
        }

        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #51/#52 Native Portals NFT Browser Controller

private struct MTPortalsBrowserState: Equatable {
    var query: String = ""
    var filterIndex: Int = 0 // 0=All, 1=<0.5%, 2=<=1%, 3=Rare, 4=Saved
    var reloadToken: Int = 0
}

private func mtMakeNativePortalsBrowserController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(MTPortalsBrowserState(), ignoreRepeated: true)
    let stateValue = Atomic(value: MTPortalsBrowserState())

    let filters: [(idx: Int, title: String)] = [
        (0, "Все коллекции"),
        (1, "Редкость < 0.5%"),
        (2, "Редкость ≤ 1.0%"),
        (3, "Категория Rare"),
        (4, "Моя сохранённая коллекция")
    ]

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Portals NFT Маркет")
        model.rightButton = ("JSON", true, {
            MTMediaTokWave15Tools.presentNftJsonManager(context: context)
        })

        let curFilterTitle = filters.first(where: { $0.idx == st.filterIndex })?.title ?? "Все коллекции"
        model.sections.append([
            .init(id: "s_hdr", kind: .header("Поиск и фильтр редкости")),
            .init(id: "q_in", kind: .input(text: st.query, placeholder: "Поиск NFT (Пепе, Pepe, Кепка, Gold...)")),
            .init(id: "f_pick", kind: .disclosure(title: "Фильтр", label: curFilterTitle, icon: .system("line.3.horizontal.decrease.circle"), enabled: true)),
            .init(id: "open_roulette", kind: .disclosure(title: "Рулетка апгрейда NFT", label: "Открыть", icon: .system("dice"), enabled: true)),
            .init(id: "open_craft", kind: .action(title: "Симулятор крафта редкой модели", destructive: false, enabled: true))
        ])

        model.text["q_in"] = { text in
            let next = stateValue.modify { cur in
                var c = cur
                c.query = text
                return c
            }
            statePromise.set(next)
        }
        model.tap["f_pick"] = {
            mtPresentNativeActionSheet(
                context: context,
                title: "Фильтр каталога NFT",
                buttons: filters.map { f in
                    (f.title, false, {
                        let next = stateValue.modify { cur in
                            var c = cur
                            c.filterIndex = f.idx
                            return c
                        }
                        statePromise.set(next)
                    })
                }
            )
        }
        model.tap["open_roulette"] = {
            MTMediaTokWave15Tools.presentUpgradeRoulette(context: context)
        }
        model.tap["open_craft"] = {
            MTMediaTokWave15Tools.presentCraftSimulator(context: context)
        }

        let q = st.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [MTPortalsCatalogItem] = (st.filterIndex == 4)
            ? MTMediaTokWave15Tools.loadSavedCustomNfts()
            : MTMediaTokWave15Tools.catalog
        let visible = base.filter { item in
            switch st.filterIndex {
            case 1 where item.rarityPercent > 0.5: return false
            case 2 where item.rarityPercent > 1.0: return false
            case 3 where item.tier != "Rare": return false
            default: break
            }
            if !q.isEmpty {
                let hay = "\(item.name) \(item.nameRu) \(item.model) \(item.backdrop) \(item.symbol) \(item.tier)".lowercased()
                return hay.contains(q)
            }
            return true
        }

        var listRows: [MTNativeRow] = [.init(id: "c_hdr", kind: .header("Модели (\(visible.count))"))]
        if visible.isEmpty {
            listRows.append(.init(id: "empty", kind: .info("По выбранному фильтру ничего не найдено.")))
        } else {
            for item in visible {
                let rowId = "nft_\(item.id)"
                let label = String(format: "%.0f TON · %.1f%%", item.floorTon, item.rarityPercent)
                listRows.append(.init(id: rowId, kind: .disclosure(title: "\(item.name) · \(item.model)", label: label, icon: .system("sparkles"), enabled: true)))
                model.tap[rowId] = {
                    mtPresentNativeActionSheet(
                        context: context,
                        title: "\(item.name) (\(item.model)) · Фон: \(item.backdrop) · Узор: \(item.symbol) · \(item.rarityPercent)% (\(Int(item.floorTon)) TON)",
                        buttons: [
                            ("Сохранить в мою коллекцию", false, {
                                MTMediaTokWave15Tools.saveCustomNft(item)
                                let next = stateValue.modify { cur in
                                    var c = cur
                                    c.reloadToken += 1
                                    return c
                                }
                                statePromise.set(next)
                                mtPresentNativeToast(context: context, text: "\(item.name) добавлен в коллекцию")
                            }),
                            ("QR-код передачи NFT", false, {
                                MTMediaTokWave15Tools.presentNftQrTransfer(context: context, item: item)
                            })
                        ]
                    )
                }
            }
        }
        model.sections.append(listRows)
        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #82 Native Upgrade Roulette Controller

private struct MTRouletteScreenState: Equatable {
    var currentWin: MTPortalsCatalogItem?
    var spinCount: Int = 0
}

private func mtMakeNativeUpgradeRouletteController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(MTRouletteScreenState(), ignoreRepeated: true)
    let stateValue = Atomic(value: MTRouletteScreenState())

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Рулетка апгрейда NFT")

        var cardSection: [MTNativeRow] = [.init(id: "r_hdr", kind: .header("Результат апгрейда"))]
        if let win = st.currentWin {
            cardSection.append(.init(
                id: "win_info",
                kind: .info("\(win.name) · \(win.model)\nФон: \(win.backdrop) · Узор: \(win.symbol)\nРедкость: \(win.rarityPercent)% (\(win.tier)) · Оценка: \(Int(win.floorTon)) TON")
            ))
        } else {
            cardSection.append(.init(
                id: "win_empty",
                kind: .info("Нажмите «Крутить рулетку», чтобы испытать шанс выпадения редких моделей Telegram Gifts.")
            ))
        }
        cardSection.append(.init(id: "spin_btn", kind: .action(title: "Крутить рулетку", destructive: false, enabled: true)))
        if let win = st.currentWin {
            cardSection.append(.init(id: "save_btn", kind: .action(title: "Забрать \(win.name) в коллекцию", destructive: false, enabled: true)))
            cardSection.append(.init(id: "qr_btn", kind: .disclosure(title: "QR-код передачи", label: win.model, icon: .system("qrcode"), enabled: true)))
            model.tap["save_btn"] = {
                MTMediaTokWave15Tools.saveCustomNft(win)
                mtPresentNativeToast(context: context, text: "\(win.name) (\(win.model)) добавлен в коллекцию")
            }
            model.tap["qr_btn"] = {
                MTMediaTokWave15Tools.presentNftQrTransfer(context: context, item: win)
            }
        }
        cardSection.append(.init(id: "r_ftr", kind: .footer("Прокруток за сессию: \(st.spinCount)")))
        model.sections.append(cardSection)

        model.tap["spin_btn"] = {
            let candidate = MTMediaTokWave15Tools.catalog.randomElement() ?? MTMediaTokWave15Tools.catalog[0]
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let next = stateValue.modify { cur in
                var c = cur
                c.currentWin = candidate
                c.spinCount += 1
                return c
            }
            statePromise.set(next)
        }

        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}
