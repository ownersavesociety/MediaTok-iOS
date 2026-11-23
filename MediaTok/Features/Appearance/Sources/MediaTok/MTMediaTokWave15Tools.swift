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
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
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
            MTMediaTokWave5Tools.showToast(context: context, text: "Паник-режим активен: эффекты профиля скрыты")
            return
        }
        guard let top = topViewController() else { return }
        let vc = MTProfileFxStudioController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
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
            MTMediaTokWave5Tools.showToast(context: context, text: "Паник-режим активен: Portals NFT скрыт")
            return
        }
        guard let top = topViewController() else { return }
        let vc = MTPortalsBrowserController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #82 Upgrade Roulette

    public static func presentUpgradeRoulette(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            MTMediaTokWave5Tools.showToast(context: context, text: "Паник-режим активен: рулетка NFT скрыта")
            return
        }
        guard let top = topViewController() else { return }
        let vc = MTUpgradeRouletteController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #83 Craft Simulator

    public static func presentCraftSimulator(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            MTMediaTokWave5Tools.showToast(context: context, text: "Паник-режим активен: крафт NFT скрыт")
            return
        }
        guard let top = topViewController() else { return }
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

        let alert = UIAlertController(
            title: "Крафт NFT завершён",
            message: "Выпала уникальная комбинация:\n\nМодель: \(crafted.name)\nФон: \(crafted.backdrop)\nУзор: \(crafted.symbol)\nРедкость: 0.1% (Legendary)\nОценка: \(Int(crafted.floorTon)) TON",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Сохранить в коллекцию", style: .default) { _ in
            saveCustomNft(crafted)
            MTMediaTokWave5Tools.showToast(context: context, text: "Крафт \(crafted.name) сохранён!")
        })
        alert.addAction(UIAlertAction(title: "QR-передача", style: .default) { _ in
            saveCustomNft(crafted)
            presentNftQrTransfer(context: context, item: crafted)
        })
        alert.addAction(UIAlertAction(title: "Скрафтить ещё", style: .default) { _ in
            presentCraftSimulator(context: context)
        })
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        top.present(alert, animated: true)
    }

    // MARK: - #85 NFT JSON Export / Import

    public static func presentNftJsonManager(context: AccountContext) {
        if MTMediaTokWave18Tools.isPanicMaskActive {
            MTMediaTokWave5Tools.showToast(context: context, text: "Паник-режим активен: коллекция NFT скрыта")
            return
        }
        guard let top = topViewController() else { return }
        let saved = loadSavedCustomNfts()
        let alert = UIAlertController(
            title: "Экспорт / Импорт коллекции NFT (JSON)",
            message: "Сохранено кастомных NFT: \(saved.count)",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Экспортировать в JSON и скопировать", style: .default) { _ in
            guard !saved.isEmpty else {
                MTMediaTokWave5Tools.showToast(context: context, text: "Коллекция кастомных NFT пуста — нечего экспортировать")
                return
            }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            if let data = try? enc.encode(saved), let str = String(data: data, encoding: .utf8) {
                UIPasteboard.general.string = str
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("mediatok_nfts_\(Int(Date().timeIntervalSince1970)).json")
                try? data.write(to: url)
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
        })
        alert.addAction(UIAlertAction(title: "Импортировать JSON из Файлов", style: .default) { _ in
            guard let host = topViewController() else { return }
            let coordinator = MTNftJsonDocumentCoordinator(context: context) {
                activeNftImportCoordinator = nil
            }
            activeNftImportCoordinator = coordinator
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json, UTType.data])
            picker.delegate = coordinator
            host.present(picker, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Импортировать JSON из буфера обмена", style: .default) { _ in
            guard let raw = UIPasteboard.general.string,
                  let data = raw.data(using: .utf8),
                  importNftJsonData(data, context: context) else {
                MTMediaTokWave5Tools.showToast(context: context, text: "В буфере обмена нет корректного JSON коллекции MediaTok")
                return
            }
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        top.present(alert, animated: true)
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

// MARK: - #3/#6/#7 Profile FX Studio Controller

private final class MTProfileFxStudioController: UIViewController {
    private let context: AccountContext
    private var config: MTProfileFxConfig

    private let frameSegment = UISegmentedControl(items: ["Нет", "Неон", "Золото", "Сакура", "Огонь", "Радуга"])
    private let nickSegment = UISegmentedControl(items: ["Обычный", "Свечение", "Перелив", "Градиент"])
    private let discordField = UITextField()
    private let previewAvatar = UIView()
    private let previewName = UILabel()

    private let frameKeys = ["none", "neon", "gold", "sakura", "fire", "rainbow"]
    private let nickKeys = ["none", "glow", "shimmer", "gradient"]

    init(context: AccountContext) {
        self.context = context
        var cfg = MTMediaTokWave15Tools.loadFxConfig()
        if let profile = MTDiscordProfileStore.shared.profile(for: context.account.peerId) {
            let mapped = MTMediaTokWave15Tools.fxFrameStyle(for: profile.avatarFrameId)
            if mapped != "none" {
                cfg.avatarFrameStyle = mapped
            }
        }
        self.config = cfg
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Студия эффектов профиля"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(saveTapped))

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Live preview card
        let previewCard = UIView()
        previewCard.backgroundColor = .secondarySystemGroupedBackground
        previewCard.layer.cornerRadius = 18
        previewCard.layer.cornerCurve = .continuous
        previewCard.translatesAutoresizingMaskIntoConstraints = false

        self.previewAvatar.backgroundColor = UIColor(red: 0.20, green: 0.26, blue: 0.42, alpha: 1.0)
        self.previewAvatar.layer.cornerRadius = 40
        self.previewAvatar.translatesAutoresizingMaskIntoConstraints = false

        self.previewName.text = "MediaTok Profile"
        self.previewName.font = .systemFont(ofSize: 22, weight: .bold)
        self.previewName.textAlignment = .center
        self.previewName.translatesAutoresizingMaskIntoConstraints = false

        previewCard.addSubview(self.previewAvatar)
        previewCard.addSubview(self.previewName)
        NSLayoutConstraint.activate([
            previewCard.heightAnchor.constraint(equalToConstant: 150),
            self.previewAvatar.widthAnchor.constraint(equalToConstant: 80),
            self.previewAvatar.heightAnchor.constraint(equalToConstant: 80),
            self.previewAvatar.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor),
            self.previewAvatar.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 18),
            self.previewName.topAnchor.constraint(equalTo: self.previewAvatar.bottomAnchor, constant: 12),
            self.previewName.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor)
        ])

        let frameLabel = UILabel()
        frameLabel.text = "Рамка аватара (#3)"
        frameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        frameLabel.textColor = .secondaryLabel

        self.frameSegment.selectedSegmentIndex = self.frameKeys.firstIndex(of: self.config.avatarFrameStyle) ?? 0
        self.frameSegment.addTarget(self, action: #selector(updatePreview), for: .valueChanged)

        let nickLabel = UILabel()
        nickLabel.text = "Эффект никнейма (#6 / #7 · превью студии)"
        nickLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nickLabel.textColor = .secondaryLabel

        self.nickSegment.selectedSegmentIndex = self.nickKeys.firstIndex(of: self.config.nickEffectStyle) ?? 0
        self.nickSegment.addTarget(self, action: #selector(updatePreview), for: .valueChanged)

        let discordLabel = UILabel()
        discordLabel.text = "Discord User ID для Live-статуса (Lanyard #8 / #10)"
        discordLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        discordLabel.textColor = .secondaryLabel

        self.discordField.borderStyle = .roundedRect
        self.discordField.placeholder = "Например: 123456789012345678"
        self.discordField.keyboardType = .numberPad
        self.discordField.text = self.config.discordUserId

        let syncBtn = UIButton(type: .system)
        var syncCfg = UIButton.Configuration.filled()
        syncCfg.title = "Обновить Live-статус сейчас (Музыка / Discord)"
        syncCfg.image = UIImage(systemName: "music.note")
        syncCfg.imagePadding = 8
        syncCfg.cornerStyle = .large
        syncBtn.configuration = syncCfg
        syncBtn.addTarget(self, action: #selector(syncNowTapped), for: .touchUpInside)

        stack.addArrangedSubview(previewCard)
        stack.addArrangedSubview(frameLabel)
        stack.addArrangedSubview(self.frameSegment)
        stack.addArrangedSubview(nickLabel)
        stack.addArrangedSubview(self.nickSegment)
        stack.addArrangedSubview(discordLabel)
        stack.addArrangedSubview(self.discordField)
        stack.addArrangedSubview(syncBtn)

        self.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16)
        ])

        self.updatePreview()
    }

    @objc private func updatePreview() {
        let frameStyle = self.frameKeys[self.frameSegment.selectedSegmentIndex]
        switch frameStyle {
        case "neon":
            self.previewAvatar.layer.borderWidth = 4
            self.previewAvatar.layer.borderColor = UIColor.systemCyan.cgColor
        case "gold":
            self.previewAvatar.layer.borderWidth = 4
            self.previewAvatar.layer.borderColor = UIColor.systemYellow.cgColor
        case "sakura":
            self.previewAvatar.layer.borderWidth = 4
            self.previewAvatar.layer.borderColor = UIColor.systemPink.cgColor
        case "fire":
            self.previewAvatar.layer.borderWidth = 4
            self.previewAvatar.layer.borderColor = UIColor.systemOrange.cgColor
        case "rainbow":
            self.previewAvatar.layer.borderWidth = 4
            self.previewAvatar.layer.borderColor = UIColor.systemPurple.cgColor
        default:
            self.previewAvatar.layer.borderWidth = 0
        }

        let nickStyle = self.nickKeys[self.nickSegment.selectedSegmentIndex]
        switch nickStyle {
        case "glow":
            self.previewName.textColor = .systemCyan
            self.previewName.layer.shadowColor = UIColor.systemCyan.cgColor
            self.previewName.layer.shadowRadius = 8
            self.previewName.layer.shadowOpacity = 0.9
            self.previewName.layer.shadowOffset = .zero
        case "shimmer":
            self.previewName.textColor = .systemYellow
            self.previewName.layer.shadowColor = UIColor.systemOrange.cgColor
            self.previewName.layer.shadowRadius = 6
            self.previewName.layer.shadowOpacity = 0.7
            self.previewName.layer.shadowOffset = .zero
        case "gradient":
            self.previewName.textColor = .systemPurple
            self.previewName.layer.shadowOpacity = 0
        default:
            self.previewName.textColor = .label
            self.previewName.layer.shadowOpacity = 0
        }
    }

    @objc private func syncNowTapped() {
        self.saveConfigOnly()
        MTMediaTokWave15Tools.syncNowPlayingOrLanyardStatus(context: self.context)
    }

    private func saveConfigOnly() {
        self.config.avatarFrameStyle = self.frameKeys[self.frameSegment.selectedSegmentIndex]
        self.config.nickEffectStyle = self.nickKeys[self.nickSegment.selectedSegmentIndex]
        self.config.discordUserId = (self.discordField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        MTMediaTokWave15Tools.saveFxConfig(self.config)

        var profile = MTDiscordProfileStore.shared.profile(for: self.context.account.peerId) ?? MTDiscordProfileData()
        profile.avatarFrameId = MTMediaTokWave15Tools.discordFrameId(for: self.config.avatarFrameStyle)
        MTDiscordProfileStore.shared.setProfile(profile, for: self.context.account.peerId, publishGlobally: true)
    }

    @objc private func saveTapped() {
        self.saveConfigOnly()
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Эффекты профиля сохранены")
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

// MARK: - #51/#52 Portals NFT Browser Controller

private final class MTPortalsBrowserController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let context: AccountContext
    private var visibleItems: [MTPortalsCatalogItem] = MTMediaTokWave15Tools.catalog

    private let searchBar = UISearchBar()
    private let raritySegment = UISegmentedControl(items: ["Все", "<0.5%", "≤1%", "Rare", "Мои"])
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Portals NFT Маркет"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "JSON", style: .plain, target: self, action: #selector(jsonTapped))

        self.searchBar.placeholder = "Поиск NFT (RU / EN: Пепе, Pepe, Кепка...)"
        self.searchBar.delegate = self
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false

        self.raritySegment.selectedSegmentIndex = 0
        self.raritySegment.addTarget(self, action: #selector(applyFilter), for: .valueChanged)
        self.raritySegment.translatesAutoresizingMaskIntoConstraints = false

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.searchBar)
        self.view.addSubview(self.raritySegment)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            self.searchBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.raritySegment.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor, constant: 6),
            self.raritySegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.raritySegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            self.tableView.topAnchor.constraint(equalTo: self.raritySegment.bottomAnchor, constant: 8),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func jsonTapped() {
        MTMediaTokWave15Tools.presentNftJsonManager(context: self.context)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.applyFilter()
    }

    @objc private func applyFilter() {
        let q = (self.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [MTPortalsCatalogItem] = (self.raritySegment.selectedSegmentIndex == 4)
            ? MTMediaTokWave15Tools.loadSavedCustomNfts()
            : MTMediaTokWave15Tools.catalog

        self.visibleItems = base.filter { item in
            switch self.raritySegment.selectedSegmentIndex {
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
        self.tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.visibleItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "portalsCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "portalsCell")
        let item = self.visibleItems[indexPath.row]
        cell.textLabel?.text = "\(item.name) · \(item.model)"
        cell.detailTextLabel?.text = "\(item.nameRu) · \(item.backdrop) · \(item.rarityPercent)% (\(item.tier))"
        cell.imageView?.image = UIImage(systemName: "sparkles")?.withTintColor(UIColor(rgb: item.accentHex), renderingMode: .alwaysOriginal)

        let price = UILabel()
        price.text = String(format: "%.0f TON", item.floorTon)
        price.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        price.textColor = .systemBlue
        price.sizeToFit()
        cell.accessoryView = price
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = self.visibleItems[indexPath.row]
        let alert = UIAlertController(
            title: "\(item.name) (\(item.model))",
            message: "Фон: \(item.backdrop)\nУзор: \(item.symbol)\nРедкость: \(item.rarityPercent)% · Floor: \(Int(item.floorTon)) TON",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Сохранить в мою коллекцию", style: .default) { _ in
            MTMediaTokWave15Tools.saveCustomNft(item)
            MTMediaTokWave5Tools.showToast(context: self.context, text: "\(item.name) добавлен в коллекцию!")
        })
        alert.addAction(UIAlertAction(title: "QR-код передачи NFT", style: .default) { _ in
            MTMediaTokWave15Tools.presentNftQrTransfer(context: self.context, item: item)
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let pop = alert.popoverPresentationController, let cell = tableView.cellForRow(at: indexPath) {
            pop.sourceView = cell
            pop.sourceRect = cell.bounds
        }
        self.present(alert, animated: true)
    }
}

// MARK: - #82 Upgrade Roulette Controller

private final class MTUpgradeRouletteController: UIViewController {
    private let context: AccountContext
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let spinButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    private var currentWin: MTPortalsCatalogItem?
    private var spinTimer: Foundation.Timer?
    private var ticksRemaining = 0

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        self.spinTimer?.invalidate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.spinTimer?.invalidate()
        self.spinTimer = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Рулетка апгрейда NFT"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.cardView.backgroundColor = .secondarySystemGroupedBackground
        self.cardView.layer.cornerRadius = 22
        self.cardView.layer.cornerCurve = .continuous
        self.cardView.layer.borderWidth = 2
        self.cardView.layer.borderColor = UIColor.systemPurple.cgColor
        self.cardView.translatesAutoresizingMaskIntoConstraints = false

        self.titleLabel.text = "Нажмите «Крутить рулетку»"
        self.titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 2
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false

        self.detailLabel.text = "Бесплатный симулятор апгрейда редких моделей Telegram Gifts"
        self.detailLabel.font = .systemFont(ofSize: 14)
        self.detailLabel.textColor = .secondaryLabel
        self.detailLabel.textAlignment = .center
        self.detailLabel.numberOfLines = 0
        self.detailLabel.translatesAutoresizingMaskIntoConstraints = false

        self.cardView.addSubview(self.titleLabel)
        self.cardView.addSubview(self.detailLabel)

        var spinCfg = UIButton.Configuration.filled()
        spinCfg.title = "Крутить рулетку"
        spinCfg.image = UIImage(systemName: "dice.fill")
        spinCfg.imagePadding = 8
        spinCfg.cornerStyle = .large
        self.spinButton.configuration = spinCfg
        self.spinButton.addTarget(self, action: #selector(spinTapped), for: .touchUpInside)
        self.spinButton.translatesAutoresizingMaskIntoConstraints = false

        var saveCfg = UIButton.Configuration.tinted()
        saveCfg.title = "Забрать выпавший NFT"
        saveCfg.image = UIImage(systemName: "plus.circle.fill")
        saveCfg.imagePadding = 8
        saveCfg.cornerStyle = .large
        self.saveButton.configuration = saveCfg
        self.saveButton.isEnabled = false
        self.saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        self.saveButton.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.cardView)
        self.view.addSubview(self.spinButton)
        self.view.addSubview(self.saveButton)

        NSLayoutConstraint.activate([
            self.cardView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 32),
            self.cardView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.cardView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            self.cardView.heightAnchor.constraint(equalToConstant: 220),

            self.titleLabel.centerYAnchor.constraint(equalTo: self.cardView.centerYAnchor, constant: -24),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor, constant: 16),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.cardView.trailingAnchor, constant: -16),

            self.detailLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 12),
            self.detailLabel.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor, constant: 16),
            self.detailLabel.trailingAnchor.constraint(equalTo: self.cardView.trailingAnchor, constant: -16),

            self.spinButton.topAnchor.constraint(equalTo: self.cardView.bottomAnchor, constant: 24),
            self.spinButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.spinButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            self.spinButton.heightAnchor.constraint(equalToConstant: 52),

            self.saveButton.topAnchor.constraint(equalTo: self.spinButton.bottomAnchor, constant: 12),
            self.saveButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.saveButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            self.saveButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func spinTapped() {
        self.spinTimer?.invalidate()
        self.spinButton.isEnabled = false
        self.saveButton.isEnabled = false
        self.ticksRemaining = 18

        self.spinTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let candidate = MTMediaTokWave15Tools.catalog.randomElement() ?? MTMediaTokWave15Tools.catalog[0]
            self.titleLabel.text = "\(candidate.name) · \(candidate.model)"
            self.detailLabel.text = "\(candidate.backdrop) · \(candidate.rarityPercent)% (\(candidate.tier)) · \(Int(candidate.floorTon)) TON"
            self.cardView.layer.borderColor = UIColor(rgb: candidate.accentHex).cgColor
            self.ticksRemaining -= 1
            if self.ticksRemaining <= 0 {
                timer.invalidate()
                self.spinTimer = nil
                self.currentWin = candidate
                self.spinButton.isEnabled = true
                self.saveButton.isEnabled = true
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
            }
        }
    }

    @objc private func saveTapped() {
        guard let win = self.currentWin else { return }
        MTMediaTokWave15Tools.saveCustomNft(win)
        MTMediaTokWave5Tools.showToast(context: self.context, text: "\(win.name) (\(win.model)) добавлен в коллекцию!")
    }

    @objc private func closeTapped() {
        self.spinTimer?.invalidate()
        self.spinTimer = nil
        self.dismiss(animated: true)
    }
}
