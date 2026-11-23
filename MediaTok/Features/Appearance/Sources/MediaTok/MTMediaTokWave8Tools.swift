import Foundation
import UIKit
import CoreImage
import Vision
import VisionKit
import PDFKit
import SafariServices
import PhotosUI
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

/// MediaTok Wave 8 (Roadmap Wave 2 — b3776):
/// - #499 Unified Profile Sandbox (live preview of 4K banner, Nitro theme, avatar frame, effect, status & weather before Save)
/// - #466 Custom Gradient Profile QR Code with MediaTok badge
/// - #478 One-Tap Sticker Pack ZIP Downloader (pure-Swift PKZIP + CRC32 from any sticker message)
/// - #480 Reverse Image Search (Google Lens / Yandex / SauceNAO) from any photo message
/// - #460 One-Tap Face Blur via Apple Vision (`VNDetectFaceRectanglesRequest` + `CIGaussianBlur`)
/// - #461 + #462 Document Scanner → PDF (`VNDocumentCameraViewController`) & Finger PDF Signature (`PDFKit`)
/// - #497 Live Weather Profile Wallpaper / Effect via keyless Open-Meteo API
/// - #486 Battery Level & Charging Spoofer for diagnostics / system reports
public enum MTMediaTokWave8Tools {
    private static let batterySpoofEnabledKey = "mediatok.battery.spoof.enabled.v1"
    private static let batterySpoofLevelKey = "mediatok.battery.spoof.level.v1"
    private static let batterySpoofChargingKey = "mediatok.battery.spoof.charging.v1"

    private static let weatherCityKey = "mediatok.weather.city.v1"
    private static let weatherSummaryKey = "mediatok.weather.summary.v1"
    private static let weatherKindKey = "mediatok.weather.kind.v1"

    // MARK: - #486 Battery Spoof State

    private static let swizzleBatteryOnce: Void = {
        let cls: AnyClass = UIDevice.self
        let origLvlSel = #selector(getter: UIDevice.batteryLevel)
        let swizLvlSel = #selector(UIDevice.gg_swizzledBatteryLevel)
        if let origLvl = class_getInstanceMethod(cls, origLvlSel),
           let swizLvl = class_getInstanceMethod(cls, swizLvlSel) {
            if class_addMethod(cls, origLvlSel, method_getImplementation(swizLvl), method_getTypeEncoding(swizLvl)) {
                class_replaceMethod(cls, swizLvlSel, method_getImplementation(origLvl), method_getTypeEncoding(origLvl))
            } else {
                method_exchangeImplementations(origLvl, swizLvl)
            }
        }
        let origStateSel = #selector(getter: UIDevice.batteryState)
        let swizStateSel = #selector(UIDevice.gg_swizzledBatteryState)
        if let origState = class_getInstanceMethod(cls, origStateSel),
           let swizState = class_getInstanceMethod(cls, swizStateSel) {
            if class_addMethod(cls, origStateSel, method_getImplementation(swizState), method_getTypeEncoding(swizState)) {
                class_replaceMethod(cls, swizStateSel, method_getImplementation(origState), method_getTypeEncoding(origState))
            } else {
                method_exchangeImplementations(origState, swizState)
            }
        }
    }()

    public static func installBatterySwizzleIfNeeded() {
        _ = MTMediaTokWave8Tools.swizzleBatteryOnce
    }

    public static var isBatterySpoofEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave8Tools.batterySpoofEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: MTMediaTokWave8Tools.batterySpoofEnabledKey)
            if newValue {
                MTMediaTokWave8Tools.installBatterySwizzleIfNeeded()
            }
        }
    }

    public static var spoofedBatteryLevel: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: MTMediaTokWave8Tools.batterySpoofLevelKey)
            return v > 0 ? min(100, v) : 100
        }
        set { UserDefaults.standard.set(max(1, min(100, newValue)), forKey: MTMediaTokWave8Tools.batterySpoofLevelKey) }
    }

    public static var spoofedBatteryCharging: Bool {
        get { return UserDefaults.standard.bool(forKey: MTMediaTokWave8Tools.batterySpoofChargingKey) }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave8Tools.batterySpoofChargingKey) }
    }

    public static var effectiveBatteryDescription: String {
        if MTMediaTokWave8Tools.isBatterySpoofEnabled {
            let icon = MTMediaTokWave8Tools.spoofedBatteryCharging ? "⚡" : "🔋"
            return "\(icon) \(MTMediaTokWave8Tools.spoofedBatteryLevel)% (spoofed)"
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let lvl = UIDevice.current.batteryLevel
        let pct = lvl >= 0 ? "\(Int((lvl * 100.0).rounded()))%" : "N/A"
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        return "\(charging ? "⚡" : "🔋") \(pct)"
    }

    // MARK: - #497 Weather State

    public static var weatherCity: String {
        get { return UserDefaults.standard.string(forKey: MTMediaTokWave8Tools.weatherCityKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave8Tools.weatherCityKey) }
    }

    public static var weatherSummary: String {
        get { return UserDefaults.standard.string(forKey: MTMediaTokWave8Tools.weatherSummaryKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave8Tools.weatherSummaryKey) }
    }

    /// "clear", "cloudy", "rain", "snow", "storm"
    public static var weatherKind: String {
        get { return UserDefaults.standard.string(forKey: MTMediaTokWave8Tools.weatherKindKey) ?? "clear" }
        set { UserDefaults.standard.set(newValue, forKey: MTMediaTokWave8Tools.weatherKindKey) }
    }

    // MARK: - Registration

    public static func register() {
        if MTMediaTokWave8Tools.isBatterySpoofEnabled {
            MTMediaTokWave8Tools.installBatterySwizzleIfNeeded()
        }

        // Chat inline commands: .sandbox, .myqr, .blurface, .scanpdf, .weather <city>
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave8Tools.interceptCommands(request)
        }, order: 28)

        // Send button long-press menu: Blur Faces, Scan/Sign PDF, Profile Sandbox, Profile QR
        MTChatScreenHooks.sendMenuItems.register({ sendContext in
            return MTMediaTokWave8Tools.sendMenuItems(sendContext)
        }, order: 80)

        // Message long-press menu: #480 Reverse Image Search on photos + #478 Sticker Pack ZIP on stickers
        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave8Tools.messageMenuItems(menuContext)
        }, order: 90)
    }

    // MARK: - Wave 2 Studio Hub

    public static func presentWave2Studio(context: AccountContext) {
        DispatchQueue.main.async {
            let bat = MTMediaTokWave8Tools.isBatterySpoofEnabled ? "\(MTMediaTokWave8Tools.spoofedBatteryLevel)%" : "Выкл"
            let weather = MTMediaTokWave8Tools.weatherSummary.isEmpty ? "Не задан" : MTMediaTokWave8Tools.weatherSummary
            let sheet = UIAlertController(
                title: "🎨 MediaTok Студия b3776 (Волна 2)",
                message: "Погода: \(weather)\nСпуфинг батареи: \(bat)",
                preferredStyle: .actionSheet
            )
            sheet.addAction(UIAlertAction(title: "🪞 Примерочная профиля (Sandbox)", style: .default, handler: { _ in
                MTMediaTokWave8Tools.presentProfileSandbox(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "📱 Красивый QR-код профиля", style: .default, handler: { _ in
                MTMediaTokWave8Tools.presentProfileQR(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "🌤 Живые обои под погоду в городе", style: .default, handler: { _ in
                MTMediaTokWave8Tools.presentWeatherSetup(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "😶‍🌫️ Размыть лица на фото (Vision AI)", style: .default, handler: { _ in
                MTMediaTokWave8Tools.presentFaceBlurPicker(context: context, targetPeerId: nil)
            }))
            sheet.addAction(UIAlertAction(title: "📄 Сканер документов → PDF", style: .default, handler: { _ in
                MTMediaTokWave8Tools.presentDocumentScanner(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "✍️ Подписать PDF пальцем", style: .default, handler: { _ in
                MTMediaTokWave8Tools.presentPdfFilePickerForSignature(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "🔋 Спуфинг батареи (\(bat))", style: .default, handler: { _ in
                MTMediaTokWave8Tools.presentBatterySpoofSheet(context: context)
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))

            MTMediaTokWave8Tools.configurePopover(sheet)
            MTMediaTokWave5Tools.presentOnRoot(sheet)
        }
    }

    // MARK: - Feature Launchers

    public static func presentProfileSandbox(context: AccountContext) {
        DispatchQueue.main.async {
            let vc = MTProfileSandboxViewController(context: context)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            MTMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    public static func presentProfileQR(context: AccountContext) {
        DispatchQueue.main.async {
            let vc = MTProfileQRViewController(context: context)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            MTMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    public static func presentFaceBlurPicker(context: AccountContext, targetPeerId: PeerId?) {
        DispatchQueue.main.async {
            let vc = MTFaceBlurViewController(context: context, targetPeerId: targetPeerId)
            vc.overrideUserInterfaceStyle = .dark
            let nav = UINavigationController(rootViewController: vc)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .pageSheet
            MTMediaTokWave5Tools.presentOnRoot(nav)
        }
    }

    public static func presentDocumentScanner(context: AccountContext) {
        DispatchQueue.main.async {
            guard VNDocumentCameraViewController.isSupported else {
                MTMediaTokWave5Tools.showToast(context: context, text: "Сканер документов не поддерживается на этом устройстве")
                return
            }
            let coordinator = MTDocumentScannerCoordinator.shared
            coordinator.startScan(context: context)
        }
    }

    public static func presentPdfFilePickerForSignature(context: AccountContext) {
        DispatchQueue.main.async {
            MTDocumentScannerCoordinator.shared.pickPdfToSign(context: context)
        }
    }

    public static func presentBatterySpoofSheet(context: AccountContext) {
        DispatchQueue.main.async {
            let status = MTMediaTokWave8Tools.isBatterySpoofEnabled
                ? "ВКЛ (\(MTMediaTokWave8Tools.spoofedBatteryLevel)%, \(MTMediaTokWave8Tools.spoofedBatteryCharging ? "зарядка ⚡" : "от батареи"))"
                : "ВЫКЛ"
            let sheet = UIAlertController(
                title: "🔋 Спуфинг батареи (#486)",
                message: "Текущий режим: \(status)",
                preferredStyle: .actionSheet
            )
            let toggleTitle = MTMediaTokWave8Tools.isBatterySpoofEnabled ? "✅ Спуфинг: ВКЛ (выключить)" : "☑️ Спуфинг: ВЫКЛ (включить)"
            sheet.addAction(UIAlertAction(title: toggleTitle, style: .default, handler: { _ in
                MTMediaTokWave8Tools.isBatterySpoofEnabled.toggle()
                MTMediaTokWave5Tools.showToast(context: context, text: "🔋 Спуфинг батареи: \(MTMediaTokWave8Tools.isBatterySpoofEnabled ? "ВКЛ" : "ВЫКЛ")")
            }))
            for pct in [100, 88, 50, 15, 1] {
                sheet.addAction(UIAlertAction(title: "Установить \(pct)%", style: .default, handler: { _ in
                    MTMediaTokWave8Tools.isBatterySpoofEnabled = true
                    MTMediaTokWave8Tools.spoofedBatteryLevel = pct
                    MTMediaTokWave5Tools.showToast(context: context, text: "🔋 Заряд подменён на \(pct)%")
                }))
            }
            let chTitle = MTMediaTokWave8Tools.spoofedBatteryCharging ? "⚡ Статус зарядки: На зарядке (переключить)" : "🔋 Статус зарядки: Разряжается (переключить)"
            sheet.addAction(UIAlertAction(title: chTitle, style: .default, handler: { _ in
                MTMediaTokWave8Tools.isBatterySpoofEnabled = true
                MTMediaTokWave8Tools.spoofedBatteryCharging.toggle()
                let st = MTMediaTokWave8Tools.spoofedBatteryCharging ? "На зарядке ⚡" : "От батареи"
                MTMediaTokWave5Tools.showToast(context: context, text: "🔋 Статус зарядки: \(st)")
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            MTMediaTokWave8Tools.configurePopover(sheet)
            MTMediaTokWave5Tools.presentOnRoot(sheet)
        }
    }

    // MARK: - #497 Open-Meteo Weather Service

    public static func presentWeatherSetup(context: AccountContext) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "🌤 Погода в профиле (#497)",
                message: "Введи город — MediaTok загрузит живую погоду (Open-Meteo) и подберёт эффект и статус профиля:",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.placeholder = "Например: Москва, Алматы, Токио"
                tf.text = MTMediaTokWave8Tools.weatherCity
            }
            alert.addAction(UIAlertAction(title: "Обновить и применить", style: .default, handler: { _ in
                let city = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !city.isEmpty else { return }
                MTMediaTokWave5Tools.showToast(context: context, text: "🌤 Загрузка погоды для «\(city)»...")
                MTMediaTokWave8Tools.fetchWeather(city: city) { result in
                    guard let result else {
                        MTMediaTokWave5Tools.showToast(context: context, text: "Город «\(city)» не найден")
                        return
                    }
                    MTMediaTokWave8Tools.weatherCity = result.city
                    MTMediaTokWave8Tools.weatherKind = result.kind
                    MTMediaTokWave8Tools.weatherSummary = result.summary

                    var profile = MTDiscordProfileStore.shared.profile(for: context.account.peerId) ?? MTDiscordProfileData()
                    profile.effectId = result.effectId
                    profile.customStatus = result.summary
                    profile.updatedAt = Int64(Date().timeIntervalSince1970)
                    MTDiscordProfileStore.shared.setProfile(profile, for: context.account.peerId, publishGlobally: true)
                    MTMediaTokWave5Tools.showToast(context: context, text: "✅ Профиль обновлён: \(result.summary)")
                }
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            MTMediaTokWave5Tools.presentOnRoot(alert)
        }
    }

    public struct WeatherResult {
        public let city: String
        public let kind: String
        public let summary: String
        public let effectId: String
    }

    public static func fetchWeather(city: String, completion: @escaping (WeatherResult?) -> Void) {
        var geoComp = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        geoComp?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "ru")
        ]
        guard let geoUrl = geoComp?.url else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        URLSession.shared.dataTask(with: geoUrl) { data, _, _ in
            guard let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let lat = first["latitude"] as? Double,
                  let lon = first["longitude"] as? Double else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let resolvedCity = (first["name"] as? String) ?? city
            var wComp = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
            wComp?.queryItems = [
                URLQueryItem(name: "latitude", value: "\(lat)"),
                URLQueryItem(name: "longitude", value: "\(lon)"),
                URLQueryItem(name: "current", value: "temperature_2m,weather_code")
            ]
            guard let wUrl = wComp?.url else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            URLSession.shared.dataTask(with: wUrl) { wData, _, _ in
                guard let wData,
                      let wJson = (try? JSONSerialization.jsonObject(with: wData)) as? [String: Any],
                      let current = wJson["current"] as? [String: Any],
                      let temp = current["temperature_2m"] as? Double else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let code = current["weather_code"] as? Int ?? 0
                let mapped = MTMediaTokWave8Tools.mapWeatherCode(code)
                let rounded = Int(temp.rounded())
                let sign = rounded > 0 ? "+" : ""
                let summary = "\(mapped.emoji) \(resolvedCity) • \(sign)\(rounded)°C"
                let res = WeatherResult(city: resolvedCity, kind: mapped.kind, summary: summary, effectId: mapped.effectId)
                DispatchQueue.main.async { completion(res) }
            }.resume()
        }.resume()
    }

    private static func mapWeatherCode(_ code: Int) -> (kind: String, emoji: String, effectId: String) {
        switch code {
        case 0, 1:
            return ("clear", "☀️", "stars")
        case 2, 3, 45, 48:
            return ("cloudy", "☁️", "neon")
        case 51...67, 80...82:
            return ("rain", "🌧", "rain")
        case 71...77, 85, 86:
            return ("snow", "❄️", "snow")
        case 95...99:
            return ("storm", "⛈", "lightning")
        default:
            return ("clear", "🌤", "stars")
        }
    }

    // MARK: - Inline Commands & Menus

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let lower = raw.lowercased()

        if lower == ".sandbox" || lower == ".preview" {
            request.replace(ChatTextInputState())
            MTMediaTokWave8Tools.presentProfileSandbox(context: request.context)
            return true
        }
        if lower == ".myqr" || lower == ".profileqr" {
            request.replace(ChatTextInputState())
            MTMediaTokWave8Tools.presentProfileQR(context: request.context)
            return true
        }
        if lower == ".blurface" || lower == ".blur" {
            request.replace(ChatTextInputState())
            MTMediaTokWave8Tools.presentFaceBlurPicker(context: request.context, targetPeerId: request.chatLocation.peerId)
            return true
        }
        if lower == ".scanpdf" || lower == ".scan" {
            request.replace(ChatTextInputState())
            MTMediaTokWave8Tools.presentDocumentScanner(context: request.context)
            return true
        }
        if lower == ".signpdf" {
            request.replace(ChatTextInputState())
            MTMediaTokWave8Tools.presentPdfFilePickerForSignature(context: request.context)
            return true
        }
        if lower == ".weather" || lower.hasPrefix(".weather ") {
            request.replace(ChatTextInputState())
            let city = lower.hasPrefix(".weather ") ? String(raw.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if city.isEmpty {
                MTMediaTokWave8Tools.presentWeatherSetup(context: request.context)
            } else {
                MTMediaTokWave5Tools.showToast(context: request.context, text: "🌤 Загрузка погоды для «\(city)»...")
                MTMediaTokWave8Tools.fetchWeather(city: city) { res in
                    guard let res else {
                        MTMediaTokWave5Tools.showToast(context: request.context, text: "Город «\(city)» не найден")
                        return
                    }
                    MTMediaTokWave8Tools.weatherCity = res.city
                    MTMediaTokWave8Tools.weatherKind = res.kind
                    MTMediaTokWave8Tools.weatherSummary = res.summary
                    var profile = MTDiscordProfileStore.shared.profile(for: request.context.account.peerId) ?? MTDiscordProfileData()
                    profile.effectId = res.effectId
                    profile.customStatus = res.summary
                    profile.updatedAt = Int64(Date().timeIntervalSince1970)
                    MTDiscordProfileStore.shared.setProfile(profile, for: request.context.account.peerId, publishGlobally: true)
                    MTMediaTokWave5Tools.showToast(context: request.context, text: "✅ Профиль обновлён: \(res.summary)")
                }
            }
            return true
        }
        return false
    }

    private static func sendMenuItems(_ sendContext: MTSendMenuContext) -> [ContextMenuItem] {
        var entries: [ContextMenuItem] = []
        let ctx = sendContext.context
        let pid = sendContext.peerId
        let dismiss = sendContext.dismiss

        entries.append(.action(ContextMenuActionItem(
            text: "😶‍🌫️ Размыть лица на фото",
            icon: { theme in
                return UIImage(systemName: "eye.slash.circle")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave8Tools.presentFaceBlurPicker(context: ctx, targetPeerId: pid)
            }
        )))

        entries.append(.action(ContextMenuActionItem(
            text: "📄 Сканер PDF / ✍️ Подписать PDF",
            icon: { theme in
                return UIImage(systemName: "doc.viewfinder")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
            },
            action: { contextController, _ in
                contextController?.dismiss(completion: nil)
                dismiss()
                MTMediaTokWave8Tools.presentWave2Studio(context: ctx)
            }
        )))

        return entries
    }

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        var entries: [MTMessageMenuEntry] = []

        // #480 Reverse Image Search on any photo message
        if let imageMedia = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage,
           let rep = largestImageRepresentation(imageMedia.representations) {
            let resource = rep.resource
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Найти фото",
                icon: { theme in
                    return UIImage(systemName: "photo.badge.magnifyingglass")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave8Tools.runReverseImageSearch(context: context, message: message, imageMedia: imageMedia, resource: resource)
                }
            ))))
        }

        // #478 Sticker Pack ZIP Downloader on any sticker message
        if let fileMedia = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile {
            var packRef: StickerPackReference?
            for attr in fileMedia.attributes {
                if case let .Sticker(_, ref, _) = attr, let ref {
                    packRef = ref
                    break
                }
            }
            if let packRef {
                entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                    text: "Скачать стикерпак (ZIP)",
                    icon: { theme in
                        return UIImage(systemName: "archivebox.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                    },
                    action: { _, f in
                        f(.default)
                        MTMediaTokWave8Tools.downloadStickerPackAsZip(context: context, reference: packRef)
                    }
                ))))
            }
        }

        return entries
    }

    // MARK: - #480 Reverse Image Search

    private static let activeReverseSearchDisposable = MetaDisposable()
    private static let reverseSearchLock = NSLock()
    private static var activeReverseSearchToken: Int = 0
    private static var activeReverseSearchTask: URLSessionDataTask?

    private static func nextReverseSearchToken() -> Int {
        self.reverseSearchLock.lock()
        self.activeReverseSearchToken += 1
        let token = self.activeReverseSearchToken
        let prev = self.activeReverseSearchTask
        self.activeReverseSearchTask = nil
        self.reverseSearchLock.unlock()
        prev?.cancel()
        return token
    }

    private static func isCurrentReverseSearch(_ token: Int) -> Bool {
        self.reverseSearchLock.lock()
        let ok = self.activeReverseSearchToken == token
        self.reverseSearchLock.unlock()
        return ok
    }

    private static func setActiveReverseSearchTask(_ task: URLSessionDataTask?, token: Int) -> Bool {
        self.reverseSearchLock.lock()
        guard self.activeReverseSearchToken == token else {
            self.reverseSearchLock.unlock()
            task?.cancel()
            return false
        }
        let prev = self.activeReverseSearchTask
        self.activeReverseSearchTask = task
        self.reverseSearchLock.unlock()
        if prev !== task {
            prev?.cancel()
        }
        return true
    }

    private static func isValidHttpsUrl(_ raw: String) -> Bool {
        guard !raw.isEmpty,
              !raw.contains(where: { $0.isWhitespace || $0.isNewline }),
              let parsed = URL(string: raw),
              parsed.scheme?.lowercased() == "https",
              let host = parsed.host, !host.isEmpty else {
            return false
        }
        return true
    }

    private static func percentEncodeQueryValue(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    private enum ReverseSearchEngine {
        case googleLens
        case yandex
        case saucenao
        case copyLink

        var displayName: String {
            switch self {
            case .googleLens: return "Google Lens"
            case .yandex: return "Яндекс Картинки"
            case .saucenao: return "SauceNAO"
            case .copyLink: return "прямую ссылку"
            }
        }
    }

    private static func runReverseImageSearch(context: AccountContext, message: Message, imageMedia: TelegramMediaImage, resource: TelegramMediaResource) {
        let sheet = UIAlertController(
            title: "Обратный поиск фото",
            message: "Выбери поисковик — фото загрузится на временную ссылку и сразу откроется:",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Google Lens", style: .default, handler: { _ in
            MTMediaTokWave8Tools.executeReverseImageSearch(engine: .googleLens, context: context, message: message, imageMedia: imageMedia, resource: resource)
        }))
        sheet.addAction(UIAlertAction(title: "Яндекс Картинки", style: .default, handler: { _ in
            MTMediaTokWave8Tools.executeReverseImageSearch(engine: .yandex, context: context, message: message, imageMedia: imageMedia, resource: resource)
        }))
        sheet.addAction(UIAlertAction(title: "SauceNAO (Аниме / Арт)", style: .default, handler: { _ in
            MTMediaTokWave8Tools.executeReverseImageSearch(engine: .saucenao, context: context, message: message, imageMedia: imageMedia, resource: resource)
        }))
        sheet.addAction(UIAlertAction(title: "Скопировать прямую ссылку", style: .default, handler: { _ in
            MTMediaTokWave8Tools.executeReverseImageSearch(engine: .copyLink, context: context, message: message, imageMedia: imageMedia, resource: resource)
        }))
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTMediaTokWave8Tools.configurePopover(sheet)
        MTMediaTokWave5Tools.presentOnRoot(sheet)
    }

    private static func executeReverseImageSearch(engine: ReverseSearchEngine, context: AccountContext, message: Message, imageMedia: TelegramMediaImage, resource: TelegramMediaResource) {
        let token = MTMediaTokWave8Tools.nextReverseSearchToken()
        MTMediaTokWave5Tools.showToast(context: context, text: "Загружаю фото в \(engine.displayName)...")
        let combined = DisposableSet()
        let fetchDisp = fetchedMediaResource(
            mediaBox: context.account.postbox.mediaBox,
            userLocation: .other,
            userContentType: .image,
            reference: ImageMediaReference.message(message: MessageReference(message), media: imageMedia).resourceReference(resource)
        ).startStandalone()
        combined.add(fetchDisp)

        let dataDisp = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
            |> filter { $0.complete }
            |> take(1)
            |> timeout(20.0, queue: Queue.mainQueue(), alternate: .single(MediaResourceData(path: "", offset: 0, size: 0, complete: false)))
            |> deliverOnMainQueue).startStandalone(next: { data in
                fetchDisp.dispose()
                guard MTMediaTokWave8Tools.isCurrentReverseSearch(token) else { return }
                guard data.complete, !data.path.isEmpty else {
                    MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось загрузить фото из Telegram")
                    return
                }
                let path = data.path
                DispatchQueue.global(qos: .userInitiated).async {
                    guard MTMediaTokWave8Tools.isCurrentReverseSearch(token) else { return }
                    guard let rawBytes = try? Data(contentsOf: URL(fileURLWithPath: path)), !rawBytes.isEmpty else {
                        DispatchQueue.main.async {
                            MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось прочитать файл фото")
                        }
                        return
                    }
                    let uploadBytes: Data
                    if let img = UIImage(data: rawBytes) {
                        let maxSide: CGFloat = 1600.0
                        let pxW = img.size.width * img.scale
                        let pxH = img.size.height * img.scale
                        if max(pxW, pxH) > maxSide || img.imageOrientation != .up {
                            let ratio = min(1.0, maxSide / max(1.0, max(pxW, pxH)))
                            let target = CGSize(width: max(64.0, floor(pxW * ratio)), height: max(64.0, floor(pxH * ratio)))
                            let fmt = UIGraphicsImageRendererFormat()
                            fmt.scale = 1.0
                            fmt.opaque = true
                            let normalized = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
                                img.draw(in: CGRect(origin: .zero, size: target))
                            }
                            uploadBytes = normalized.jpegData(compressionQuality: 0.85) ?? rawBytes
                        } else {
                            uploadBytes = img.jpegData(compressionQuality: 0.85) ?? rawBytes
                        }
                    } else {
                        uploadBytes = rawBytes
                    }

                    MTMediaTokWave8Tools.uploadTempImageForSearch(data: uploadBytes, fileName: "search.jpg", mimeType: "image/jpeg", token: token) { uploadedUrl in
                        DispatchQueue.main.async {
                            guard MTMediaTokWave8Tools.isCurrentReverseSearch(token) else { return }
                            guard let uploadedUrl, !uploadedUrl.isEmpty else {
                                MTMediaTokWave5Tools.showToast(context: context, text: "Ошибка загрузки фото для поиска (проверь сеть/VPN)")
                                return
                            }
                            let encoded = MTMediaTokWave8Tools.percentEncodeQueryValue(uploadedUrl)
                            switch engine {
                            case .googleLens:
                                MTMediaTokWave8Tools.openSafariURL("https://lens.google.com/uploadbyurl?url=\(encoded)")
                            case .yandex:
                                MTMediaTokWave8Tools.openSafariURL("https://yandex.ru/images/search?rpt=imageview&url=\(encoded)")
                            case .saucenao:
                                MTMediaTokWave8Tools.openSafariURL("https://saucenao.com/search.php?url=\(encoded)")
                            case .copyLink:
                                UIPasteboard.general.string = uploadedUrl
                                MTMediaTokWave5Tools.showToast(context: context, text: "Ссылка на фото скопирована")
                            }
                        }
                    }
                }
            })
        combined.add(dataDisp)
        MTMediaTokWave8Tools.activeReverseSearchDisposable.set(combined)
    }

    private static func openSafariURL(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        let safari = SFSafariViewController(url: url)
        MTMediaTokWave5Tools.presentOnRoot(safari)
    }

    private static func buildMultipartBody(boundary: String, fields: [(String, String)], fileField: String, fileName: String, mimeType: String, data: Data) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private static let searchUploadUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1"

    private static func uploadTempImageForSearch(data: Data, fileName: String, mimeType: String, token: Int, completion: @escaping (String?) -> Void) {
        // Inline-JPEG friendly fallback chain so Google Lens, Yandex, and SauceNAO fetch cleanly:
        // uguu.se (3h TTL, direct inline image) -> catbox.moe -> tmpfiles.org (1h TTL)
        guard MTMediaTokWave8Tools.isCurrentReverseSearch(token) else { completion(nil); return }
        uploadToUguu(data: data, fileName: fileName, mimeType: mimeType, token: token) { url1 in
            if let url1 { completion(url1); return }
            guard MTMediaTokWave8Tools.isCurrentReverseSearch(token) else { completion(nil); return }
            uploadToCatboxForSearch(data: data, fileName: fileName, mimeType: mimeType, token: token) { url2 in
                if let url2 { completion(url2); return }
                guard MTMediaTokWave8Tools.isCurrentReverseSearch(token) else { completion(nil); return }
                uploadToTmpfiles(data: data, fileName: fileName, mimeType: mimeType, token: token, completion: completion)
            }
        }
    }

    private static func uploadToTmpfiles(data: Data, fileName: String, mimeType: String, token: Int, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://tmpfiles.org/api/v1/upload") else { completion(nil); return }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url, timeoutInterval: 10.0)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(MTMediaTokWave8Tools.searchUploadUserAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = buildMultipartBody(boundary: boundary, fields: [], fileField: "file", fileName: fileName, mimeType: mimeType, data: data)

        let session = MTMediaTokWave9Tools.urlSession(for: url)
        let task = session.dataTask(with: req) { respData, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let respData,
                  let json = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any],
                  let inner = json["data"] as? [String: Any],
                  let rawUrl = inner["url"] as? String,
                  rawUrl.hasPrefix("https://tmpfiles.org/") || rawUrl.hasPrefix("http://tmpfiles.org/") else {
                completion(nil)
                return
            }
            let httpsUrl = rawUrl.replacingOccurrences(of: "http://tmpfiles.org/", with: "https://tmpfiles.org/")
            let directUrl = httpsUrl.hasPrefix("https://tmpfiles.org/dl/")
                ? httpsUrl
                : httpsUrl.replacingOccurrences(of: "https://tmpfiles.org/", with: "https://tmpfiles.org/dl/")
            completion(MTMediaTokWave8Tools.isValidHttpsUrl(directUrl) ? directUrl : nil)
        }
        guard MTMediaTokWave8Tools.setActiveReverseSearchTask(task, token: token) else { completion(nil); return }
        task.resume()
    }

    private static func uploadToUguu(data: Data, fileName: String, mimeType: String, token: Int, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://uguu.se/upload?output=text") else { completion(nil); return }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url, timeoutInterval: 10.0)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(MTMediaTokWave8Tools.searchUploadUserAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = buildMultipartBody(boundary: boundary, fields: [], fileField: "files[]", fileName: fileName, mimeType: mimeType, data: data)

        let session = MTMediaTokWave9Tools.urlSession(for: url)
        let task = session.dataTask(with: req) { respData, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let respData,
                  let text = String(data: respData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  MTMediaTokWave8Tools.isValidHttpsUrl(text) else {
                completion(nil)
                return
            }
            completion(text)
        }
        guard MTMediaTokWave8Tools.setActiveReverseSearchTask(task, token: token) else { completion(nil); return }
        task.resume()
    }

    private static func uploadToCatboxForSearch(data: Data, fileName: String, mimeType: String, token: Int, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://catbox.moe/user/api.php") else { completion(nil); return }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url, timeoutInterval: 12.0)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(MTMediaTokWave8Tools.searchUploadUserAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = buildMultipartBody(boundary: boundary, fields: [("reqtype", "fileupload")], fileField: "fileToUpload", fileName: fileName, mimeType: mimeType, data: data)

        let session = MTMediaTokWave9Tools.urlSession(for: url)
        let task = session.dataTask(with: req) { respData, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let respData,
                  let text = String(data: respData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  MTMediaTokWave8Tools.isValidHttpsUrl(text) else {
                completion(nil)
                return
            }
            completion(text)
        }
        guard MTMediaTokWave8Tools.setActiveReverseSearchTask(task, token: token) else { completion(nil); return }
        task.resume()
    }

    // MARK: - #478 Sticker Pack ZIP Downloader

    private static func downloadStickerPackAsZip(context: AccountContext, reference: StickerPackReference) {
        MTMediaTokWave5Tools.showToast(context: context, text: "📦 Загрузка стикерпака для ZIP...")
        let signal = context.engine.stickers.loadedStickerPack(reference: reference, forceActualized: true)
            |> filter { pack in
                if case .fetching = pack { return false }
                return true
            }
            |> take(1)
            |> deliverOnMainQueue

        let _ = signal.startStandalone(next: { pack in
            guard case let .result(info, items, _) = pack, !items.isEmpty else {
                MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось загрузить стикерпак")
                return
            }
            let packInfo = info._parse()
            let safeName = packInfo.shortName.isEmpty ? "stickerpack_\(packInfo.id.id)" : packInfo.shortName
            let maxCount = min(items.count, 120)
            let slice = Array(items.prefix(maxCount))
            MTMediaTokWave5Tools.showToast(context: context, text: "📦 Скачивание \(slice.count) стикеров...")

            let group = DispatchGroup()
            let lock = NSLock()
            var entries: [(name: String, data: Data)] = []
            var localDisposables: [Disposable] = []

            for (idx, item) in slice.enumerated() {
                let file = item.file._parse()
                let ext: String
                if file.mimeType.contains("tgsticker") {
                    ext = "tgs"
                } else if file.mimeType.contains("webm") {
                    ext = "webm"
                } else if file.mimeType.contains("png") {
                    ext = "png"
                } else {
                    ext = "webp"
                }
                let fileName = String(format: "%03d.%@", idx + 1, ext)

                group.enter()
                var didLeave = false
                let leaveOnce: () -> Void = {
                    lock.lock()
                    let shouldLeave = !didLeave
                    didLeave = true
                    lock.unlock()
                    if shouldLeave {
                        group.leave()
                    }
                }
                let fetchDisp = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .sticker, reference: FileMediaReference.stickerPack(stickerPack: reference, media: file).resourceReference(file.resource)).startStandalone()
                let dataDisp = (context.account.postbox.mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: false))
                    |> filter { $0.complete }
                    |> take(1)).startStandalone(next: { resData in
                        if let bytes = try? Data(contentsOf: URL(fileURLWithPath: resData.path)), !bytes.isEmpty {
                            lock.lock()
                            if !didLeave {
                                entries.append((name: fileName, data: bytes))
                            }
                            lock.unlock()
                        }
                        fetchDisp.dispose()
                        leaveOnce()
                    })
                lock.lock()
                localDisposables.append(fetchDisp)
                localDisposables.append(dataDisp)
                lock.unlock()

                // Safety timeout per sticker so a single missing item never hangs or crashes DispatchGroup
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 18.0) {
                    dataDisp.dispose()
                    fetchDisp.dispose()
                    leaveOnce()
                }
            }

            group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                lock.lock()
                let toDispose = localDisposables
                localDisposables.removeAll()
                var snapshot = entries
                lock.unlock()
                for disp in toDispose {
                    disp.dispose()
                }
                guard !snapshot.isEmpty else {
                    DispatchQueue.main.async {
                        MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось скачать файлы стикеров")
                    }
                    return
                }
                snapshot.sort { $0.name < $1.name }
                let zipData = MTSimpleZipWriter.makeZip(entries: snapshot)
                let outUrl = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).zip")
                do {
                    try zipData.write(to: outUrl, options: [.atomic])
                    DispatchQueue.main.async {
                        let share = UIActivityViewController(activityItems: [outUrl], applicationActivities: nil)
                        share.completionWithItemsHandler = { _, _, _, _ in
                            try? FileManager.default.removeItem(at: outUrl)
                        }
                        MTMediaTokWave8Tools.configurePopover(share)
                        MTMediaTokWave5Tools.presentOnRoot(share)
                    }
                } catch {
                    DispatchQueue.main.async {
                        MTMediaTokWave5Tools.showToast(context: context, text: "Ошибка записи ZIP-архива")
                    }
                }
            }
        })
    }

    static func configurePopover(_ vc: UIViewController) {
        if let pop = vc.popoverPresentationController {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let win = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
            pop.sourceView = win
            if let win {
                pop.sourceRect = CGRect(x: win.bounds.midX, y: win.bounds.midY, width: 1, height: 1)
            }
            pop.permittedArrowDirections = []
        }
    }
}

// MARK: - Pure-Swift Standard PKZIP Writer (Stored + CRC32)

private enum MTSimpleZipWriter {
    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0 ..< 256 {
            var c = UInt32(i)
            for _ in 0 ..< 8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table[i] = c
        }
        return table
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in data {
            let idx = Int((crc ^ UInt32(b)) & 0xFF)
            crc = MTSimpleZipWriter.crcTable[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func appendLE(_ out: inout Data, _ v: UInt16) {
        var le = v.littleEndian
        out.append(Data(bytes: &le, count: 2))
    }

    private static func appendLE(_ out: inout Data, _ v: UInt32) {
        var le = v.littleEndian
        out.append(Data(bytes: &le, count: 4))
    }

    static func makeZip(entries: [(name: String, data: Data)]) -> Data {
        var archive = Data()
        var centralDir = Data()
        var entryCount: UInt16 = 0

        for item in entries {
            let nameData = Data(item.name.utf8)
            let crc = MTSimpleZipWriter.crc32(item.data)
            let size = UInt32(item.data.count)
            let localOffset = UInt32(archive.count)

            // Local file header
            appendLE(&archive, UInt32(0x04034B50))
            appendLE(&archive, UInt16(20))
            appendLE(&archive, UInt16(0))
            appendLE(&archive, UInt16(0)) // stored
            appendLE(&archive, UInt16(0))
            appendLE(&archive, UInt16(0))
            appendLE(&archive, crc)
            appendLE(&archive, size)
            appendLE(&archive, size)
            appendLE(&archive, UInt16(nameData.count))
            appendLE(&archive, UInt16(0))
            archive.append(nameData)
            archive.append(item.data)

            // Central directory header
            appendLE(&centralDir, UInt32(0x02014B50))
            appendLE(&centralDir, UInt16(20))
            appendLE(&centralDir, UInt16(20))
            appendLE(&centralDir, UInt16(0))
            appendLE(&centralDir, UInt16(0))
            appendLE(&centralDir, UInt16(0))
            appendLE(&centralDir, UInt16(0))
            appendLE(&centralDir, crc)
            appendLE(&centralDir, size)
            appendLE(&centralDir, size)
            appendLE(&centralDir, UInt16(nameData.count))
            appendLE(&centralDir, UInt16(0))
            appendLE(&centralDir, UInt16(0))
            appendLE(&centralDir, UInt16(0))
            appendLE(&centralDir, UInt16(0))
            appendLE(&centralDir, UInt32(0))
            appendLE(&centralDir, localOffset)
            centralDir.append(nameData)

            entryCount &+= 1
        }

        let cdOffset = UInt32(archive.count)
        let cdSize = UInt32(centralDir.count)
        archive.append(centralDir)

        // End of central directory record
        appendLE(&archive, UInt32(0x06054B50))
        appendLE(&archive, UInt16(0))
        appendLE(&archive, UInt16(0))
        appendLE(&archive, entryCount)
        appendLE(&archive, entryCount)
        appendLE(&archive, cdSize)
        appendLE(&archive, cdOffset)
        appendLE(&archive, UInt16(0))
        return archive
    }
}

// MARK: - #499 Unified Profile Sandbox (`MediaTok Sandbox`)

public final class MTProfileSandboxViewController: UIViewController, UITextFieldDelegate {
    private let context: AccountContext
    private var draft: MTDiscordProfileData

    private let scrollView = UIScrollView()
    private let previewCard = UIView()
    private let previewGradient = CAGradientLayer()
    private let liveEffectView = MTDiscordProfileEffectView(frame: .zero)
    private let avatarFrameView = MTAvatarFrameRingView(frame: .zero)
    private let avatarCircle = UIView()
    private let avatarInitials = UILabel()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let badgeLabel = UILabel()
    private let statusField = UITextField()
    private let themeBtn = UIButton(type: .system)
    private let frameBtn = UIButton(type: .system)
    private let effectBtn = UIButton(type: .system)
    private let fontBtn = UIButton(type: .system)
    private let weatherBtn = UIButton(type: .system)
    private let stackView = UIStackView()

    public init(context: AccountContext) {
        self.context = context
        self.draft = MTDiscordProfileStore.shared.profile(for: context.account.peerId) ?? MTDiscordProfileData()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [self.scrollView]
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.isBeingPresented || self.navigationController?.isBeingPresented == true {
            self.view.endEditing(true)
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
        self.title = "Примерочная профиля"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Отмена", style: .plain, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(self.saveTapped))

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.keyboardDismissMode = .interactive
        self.scrollView.alwaysBounceVertical = true
        self.view.addSubview(self.scrollView)

        let bgTap = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboardTapped))
        bgTap.cancelsTouchesInView = false
        self.view.addGestureRecognizer(bgTap)

        NotificationCenter.default.addObserver(self, selector: #selector(self.handleKeyboardFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleKeyboardHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        self.stackView.axis = .vertical
        self.stackView.spacing = 12
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stackView)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.stackView.topAnchor.constraint(equalTo: self.scrollView.topAnchor, constant: 16),
            self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.leadingAnchor, constant: 16),
            self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.trailingAnchor, constant: -16),
            self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.bottomAnchor, constant: -28),
            self.stackView.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor, constant: -32)
        ])

        self.setupPreviewCard()
        self.setupControls()
        self.refreshPreview()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewGradient.frame = self.previewCard.bounds
        self.liveEffectView.frame = self.previewCard.bounds
        self.avatarFrameView.frame = self.avatarCircle.bounds.insetBy(dx: -4, dy: -4)
    }

    @objc private func dismissKeyboardTapped() {
        self.view.endEditing(true)
    }

    @objc private func handleKeyboardFrame(_ note: Notification) {
        guard let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let local = self.view.convert(endFrame, from: nil)
        let overlap = max(0, self.view.bounds.maxY - local.minY)
        self.scrollView.contentInset.bottom = overlap + 16
        self.scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    @objc private func handleKeyboardHide(_ note: Notification) {
        let _ = note
        self.scrollView.contentInset.bottom = 0
        self.scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func setupPreviewCard() {
        self.previewCard.layer.cornerRadius = 26
        self.previewCard.layer.cornerCurve = .continuous
        self.previewCard.clipsToBounds = true
        self.previewCard.layer.borderWidth = 1.0
        self.previewCard.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        self.previewCard.translatesAutoresizingMaskIntoConstraints = false
        self.previewCard.heightAnchor.constraint(equalToConstant: 218).isActive = true

        self.previewGradient.startPoint = CGPoint(x: 0, y: 0)
        self.previewGradient.endPoint = CGPoint(x: 1, y: 1)
        self.previewCard.layer.addSublayer(self.previewGradient)
        self.previewCard.addSubview(self.liveEffectView)

        self.avatarCircle.translatesAutoresizingMaskIntoConstraints = false
        self.avatarCircle.layer.cornerRadius = 42
        self.avatarCircle.clipsToBounds = false
        self.avatarCircle.backgroundColor = .clear

        let innerAvatar = UIView()
        innerAvatar.translatesAutoresizingMaskIntoConstraints = false
        innerAvatar.backgroundColor = UIColor(red: 0.11, green: 0.12, blue: 0.17, alpha: 0.94)
        innerAvatar.layer.cornerRadius = 38
        innerAvatar.clipsToBounds = true
        self.avatarCircle.addSubview(innerAvatar)
        self.avatarCircle.addSubview(self.avatarFrameView)

        self.avatarInitials.text = "MT"
        self.avatarInitials.font = .systemFont(ofSize: 24, weight: .heavy)
        self.avatarInitials.textColor = .white
        self.avatarInitials.textAlignment = .center
        self.avatarInitials.translatesAutoresizingMaskIntoConstraints = false
        innerAvatar.addSubview(self.avatarInitials)

        self.nameLabel.text = "Мой профиль MediaTok"
        self.nameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        self.nameLabel.textColor = .white
        self.nameLabel.textAlignment = .center
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = false

        self.statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        self.statusLabel.textColor = UIColor(white: 0.92, alpha: 1.0)
        self.statusLabel.textAlignment = .center
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        self.badgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        self.badgeLabel.textColor = UIColor(white: 0.85, alpha: 0.88)
        self.badgeLabel.textAlignment = .center
        self.badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        self.previewCard.addSubview(self.avatarCircle)
        self.previewCard.addSubview(self.nameLabel)
        self.previewCard.addSubview(self.statusLabel)
        self.previewCard.addSubview(self.badgeLabel)

        NSLayoutConstraint.activate([
            self.avatarCircle.centerXAnchor.constraint(equalTo: self.previewCard.centerXAnchor),
            self.avatarCircle.topAnchor.constraint(equalTo: self.previewCard.topAnchor, constant: 22),
            self.avatarCircle.widthAnchor.constraint(equalToConstant: 84),
            self.avatarCircle.heightAnchor.constraint(equalToConstant: 84),
            innerAvatar.centerXAnchor.constraint(equalTo: self.avatarCircle.centerXAnchor),
            innerAvatar.centerYAnchor.constraint(equalTo: self.avatarCircle.centerYAnchor),
            innerAvatar.widthAnchor.constraint(equalToConstant: 76),
            innerAvatar.heightAnchor.constraint(equalToConstant: 76),
            self.avatarInitials.centerXAnchor.constraint(equalTo: innerAvatar.centerXAnchor),
            self.avatarInitials.centerYAnchor.constraint(equalTo: innerAvatar.centerYAnchor),
            self.nameLabel.topAnchor.constraint(equalTo: self.avatarCircle.bottomAnchor, constant: 12),
            self.nameLabel.leadingAnchor.constraint(equalTo: self.previewCard.leadingAnchor, constant: 16),
            self.nameLabel.trailingAnchor.constraint(equalTo: self.previewCard.trailingAnchor, constant: -16),
            self.statusLabel.topAnchor.constraint(equalTo: self.nameLabel.bottomAnchor, constant: 4),
            self.statusLabel.leadingAnchor.constraint(equalTo: self.previewCard.leadingAnchor, constant: 16),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.previewCard.trailingAnchor, constant: -16),
            self.badgeLabel.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 6),
            self.badgeLabel.leadingAnchor.constraint(equalTo: self.previewCard.leadingAnchor, constant: 16),
            self.badgeLabel.trailingAnchor.constraint(equalTo: self.previewCard.trailingAnchor, constant: -16)
        ])

        self.stackView.addArrangedSubview(self.previewCard)

        let peerId = self.context.account.peerId
        let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).startStandalone(next: { [weak self] peer in
                guard let self, let peer else { return }
                let title = peer.debugDisplayTitle
                if !title.isEmpty {
                    self.nameLabel.text = title
                    self.avatarInitials.text = String(title.prefix(2)).uppercased()
                }
            })
    }

    private func setupControls() {
        self.statusField.placeholder = "Кастомный статус профиля..."
        self.statusField.text = self.draft.customStatus
        self.statusField.textColor = .white
        self.statusField.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        self.statusField.layer.cornerRadius = 14
        self.statusField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        self.statusField.leftViewMode = .always
        self.statusField.clearButtonMode = .whileEditing
        self.statusField.returnKeyType = .done
        self.statusField.delegate = self
        self.statusField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        self.statusField.addTarget(self, action: #selector(self.statusChanged), for: .editingChanged)
        self.stackView.addArrangedSubview(self.statusField)

        self.configureSectionButton(self.themeBtn, symbol: "paintpalette.fill", tint: .systemPink, action: #selector(self.pickTheme))
        self.configureSectionButton(self.frameBtn, symbol: "circle.dashed.inset.filled", tint: .systemPurple, action: #selector(self.pickFrame))
        self.configureSectionButton(self.effectBtn, symbol: "sparkles", tint: .systemCyan, action: #selector(self.pickEffect))
        self.configureSectionButton(self.fontBtn, symbol: "textformat", tint: .systemOrange, action: #selector(self.pickFont))
        self.configureSectionButton(self.weatherBtn, symbol: "cloud.sun.fill", tint: .systemTeal, action: #selector(self.pickWeather))

        self.stackView.addArrangedSubview(self.themeBtn)
        self.stackView.addArrangedSubview(self.frameBtn)
        self.stackView.addArrangedSubview(self.effectBtn)
        self.stackView.addArrangedSubview(self.fontBtn)
        self.stackView.addArrangedSubview(self.weatherBtn)

        let saveBtn = UIButton(type: .system)
        let saveCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        saveBtn.setImage(UIImage(systemName: "checkmark.circle.fill", withConfiguration: saveCfg)?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        saveBtn.setTitle("  Сохранить и синхронизировать профиль", for: .normal)
        saveBtn.setTitleColor(.white, for: .normal)
        saveBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        saveBtn.backgroundColor = UIColor(red: 0.16, green: 0.52, blue: 1.0, alpha: 1.0)
        saveBtn.layer.cornerRadius = 16
        saveBtn.heightAnchor.constraint(equalToConstant: 50).isActive = true
        saveBtn.addTarget(self, action: #selector(self.saveTapped), for: .touchUpInside)
        self.stackView.addArrangedSubview(saveBtn)
    }

    private func configureSectionButton(_ btn: UIButton, symbol: String, tint: UIColor, action: Selector) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        var btnConfig = UIButton.Configuration.plain()
        btnConfig.image = UIImage(systemName: symbol, withConfiguration: cfg)?.withTintColor(tint, renderingMode: .alwaysOriginal)
        btnConfig.imagePadding = 6
        btnConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        btnConfig.baseForegroundColor = .white
        btn.configuration = btnConfig
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.contentHorizontalAlignment = .left
        btn.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        btn.layer.cornerRadius = 14
        btn.heightAnchor.constraint(equalToConstant: 46).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
    }

    private func refreshPreview() {
        let themeSpec = MTDiscordProfileStore.nitroThemes.first(where: { $0.id == self.draft.nitroThemeId })
        let themeColors = themeSpec?.colors ?? []
        if themeColors.count >= 2 {
            self.previewGradient.colors = themeColors.map { $0.cgColor }
        } else {
            self.previewGradient.colors = [
                UIColor(red: 0.13, green: 0.15, blue: 0.25, alpha: 1.0).cgColor,
                UIColor(red: 0.08, green: 0.09, blue: 0.14, alpha: 1.0).cgColor
            ]
        }

        let frameSpec = MTDiscordProfileStore.avatarFrames.first(where: { $0.id == self.draft.avatarFrameId })
        self.avatarFrameView.configure(frameId: self.draft.avatarFrameId)
        self.avatarFrameView.frame = self.avatarCircle.bounds.insetBy(dx: -4, dy: -4)

        let effectiveEffectId = (!self.draft.effectId.isEmpty && self.draft.effectId != "none")
            ? self.draft.effectId
            : (MTMediaTokWave8Tools.weatherKind == "snow" ? "snow" : (MTMediaTokWave8Tools.weatherKind == "rain" ? "rain" : "none"))
        self.liveEffectView.frame = self.previewCard.bounds
        self.liveEffectView.configure(effectId: effectiveEffectId)

        let effectTitle = MTDiscordProfileStore.effects.first(where: { $0.id == self.draft.effectId })?.title ?? "Выкл."
        let fontTitle = MTDiscordProfileStore.fontDisplayName(for: self.draft.fontSlug)

        self.nameLabel.font = MTDiscordProfileStore.resolvedFont(slug: self.draft.fontSlug, size: 20.0, fallbackWeight: .bold)
        self.statusLabel.font = MTDiscordProfileStore.resolvedFont(slug: self.draft.fontSlug, size: 14.5, fallbackWeight: .medium)
        self.statusField.font = MTDiscordProfileStore.resolvedFont(slug: self.draft.fontSlug, size: 15.0, fallbackWeight: .regular)

        self.statusLabel.text = self.draft.customStatus.isEmpty ? "Без статуса" : self.draft.customStatus
        self.badgeLabel.text = "Эффект: \(effectTitle)  •  Шрифт: \(fontTitle)"

        self.themeBtn.setTitle("   Тема профиля (Nitro): \(themeSpec?.title ?? "Выкл.")", for: .normal)
        self.frameBtn.setTitle("   Рамка аватара: \(frameSpec?.title ?? "Выкл.")", for: .normal)
        self.effectBtn.setTitle("   Эффект профиля: \(effectTitle)", for: .normal)
        self.fontBtn.setTitle("   Шрифт карточки: \(fontTitle)", for: .normal)
        let city = MTMediaTokWave8Tools.weatherCity
        self.weatherBtn.setTitle(city.isEmpty ? "   Погода города в профиле" : "   Погода города: \(city)", for: .normal)
    }

    @objc private func statusChanged() {
        self.draft.customStatus = self.statusField.text ?? ""
        self.refreshPreview()
    }

    @objc private func pickTheme() {
        self.view.endEditing(true)
        let sheet = UIAlertController(title: "Тема профиля (Nitro)", message: nil, preferredStyle: .actionSheet)
        for t in MTDiscordProfileStore.nitroThemes {
            sheet.addAction(UIAlertAction(title: t.title, style: .default, handler: { [weak self] _ in
                self?.draft.nitroThemeId = t.id
                self?.refreshPreview()
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTMediaTokWave8Tools.configurePopover(sheet)
        self.present(sheet, animated: true)
    }

    @objc private func pickFrame() {
        self.view.endEditing(true)
        let sheet = UIAlertController(title: "Рамка аватара", message: nil, preferredStyle: .actionSheet)
        for f in MTDiscordProfileStore.avatarFrames {
            sheet.addAction(UIAlertAction(title: f.title, style: .default, handler: { [weak self] _ in
                self?.draft.avatarFrameId = f.id
                self?.refreshPreview()
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTMediaTokWave8Tools.configurePopover(sheet)
        self.present(sheet, animated: true)
    }

    @objc private func pickEffect() {
        self.view.endEditing(true)
        let sheet = UIAlertController(title: "Эффект профиля", message: nil, preferredStyle: .actionSheet)
        for e in MTDiscordProfileStore.effects {
            sheet.addAction(UIAlertAction(title: e.title, style: .default, handler: { [weak self] _ in
                self?.draft.effectId = e.id
                self?.refreshPreview()
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        MTMediaTokWave8Tools.configurePopover(sheet)
        self.present(sheet, animated: true)
    }

    @objc private func pickFont() {
        self.view.endEditing(true)
        let picker = MTDiscordCardFontPickerController(selectedSlug: self.draft.fontSlug) { [weak self] slug in
            self?.draft.fontSlug = slug
            self?.refreshPreview()
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.overrideUserInterfaceStyle = .dark
        self.present(nav, animated: true)
    }

    @objc private func pickWeather() {
        self.view.endEditing(true)
        let alert = UIAlertController(title: "Город для погоды", message: "Введите город:", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Москва"
            tf.text = MTMediaTokWave8Tools.weatherCity
        }
        alert.addAction(UIAlertAction(title: "Примерить", style: .default, handler: { [weak self] _ in
            guard self != nil else { return }
            let city = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !city.isEmpty else { return }
            MTMediaTokWave8Tools.fetchWeather(city: city) { [weak self] res in
                guard let self, let res else { return }
                MTMediaTokWave8Tools.weatherCity = res.city
                MTMediaTokWave8Tools.weatherKind = res.kind
                MTMediaTokWave8Tools.weatherSummary = res.summary
                self.draft.effectId = res.effectId
                self.draft.customStatus = res.summary
                self.statusField.text = res.summary
                self.refreshPreview()
            }
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.present(alert, animated: true)
    }

    @objc private func saveTapped() {
        self.view.endEditing(true)
        self.draft.updatedAt = Int64(Date().timeIntervalSince1970)
        MTDiscordProfileStore.shared.setProfile(self.draft, for: self.context.account.peerId, publishGlobally: true)
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Профиль сохранён и синхронизирован")
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() {
        self.view.endEditing(true)
        self.dismiss(animated: true)
    }
}

// MARK: - #466 Custom Gradient Profile QR Code

public final class MTProfileQRViewController: UIViewController {
    private let context: AccountContext
    private let imageView = UIImageView()
    private let styleSegment = UISegmentedControl(items: ["Cyber", "Sunset", "Matrix", "Sakura", "Glass"])
    private var qrPayload: String = "https://t.me/"
    private var displayHandle: String = "MediaTok"
    private var renderedCard: UIImage?

    public init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "📱 QR-код профиля"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.closeTapped))

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.layer.cornerRadius = 26
        self.imageView.clipsToBounds = true
        self.imageView.translatesAutoresizingMaskIntoConstraints = false

        self.styleSegment.selectedSegmentIndex = 0
        self.styleSegment.addTarget(self, action: #selector(self.styleChanged), for: .valueChanged)
        self.styleSegment.translatesAutoresizingMaskIntoConstraints = false

        let shareBtn = UIButton(type: .system)
        shareBtn.setTitle("📤 Поделиться / Сохранить QR-карточку", for: .normal)
        shareBtn.setTitleColor(.white, for: .normal)
        shareBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        shareBtn.backgroundColor = UIColor(red: 0.16, green: 0.52, blue: 1.0, alpha: 1.0)
        shareBtn.layer.cornerRadius = 16
        shareBtn.addTarget(self, action: #selector(self.shareTapped), for: .touchUpInside)
        shareBtn.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.imageView)
        self.view.addSubview(self.styleSegment)
        self.view.addSubview(shareBtn)

        NSLayoutConstraint.activate([
            self.imageView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            self.imageView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.imageView.widthAnchor.constraint(equalToConstant: 300),
            self.imageView.heightAnchor.constraint(equalToConstant: 360),
            self.styleSegment.topAnchor.constraint(equalTo: self.imageView.bottomAnchor, constant: 20),
            self.styleSegment.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.styleSegment.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            shareBtn.topAnchor.constraint(equalTo: self.styleSegment.bottomAnchor, constant: 20),
            shareBtn.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            shareBtn.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            shareBtn.heightAnchor.constraint(equalToConstant: 50)
        ])

        let peerId = self.context.account.peerId
        let rawId = peerId.id._internalGetInt64Value()
        self.qrPayload = "tg://user?id=\(rawId)"
        self.displayHandle = "ID \(rawId)"
        self.rebuildCard()

        let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).startStandalone(next: { [weak self] peer in
                guard let self, let peer else { return }
                if let username = peer.addressName, !username.isEmpty {
                    self.qrPayload = "https://t.me/\(username)"
                    self.displayHandle = "@\(username)"
                } else {
                    self.displayHandle = peer.debugDisplayTitle
                }
                self.rebuildCard()
            })
    }

    @objc private func styleChanged() {
        self.rebuildCard()
    }

    private func rebuildCard() {
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(rgb: 0x00C6FF), UIColor(rgb: 0x3A0CA3)),
            (UIColor(rgb: 0xFF512F), UIColor(rgb: 0x810034)),
            (UIColor(rgb: 0x00F5A0), UIColor(rgb: 0x004E64)),
            (UIColor(rgb: 0xFF4D8D), UIColor(rgb: 0x7209B7)),
            (UIColor(rgb: 0x232526), UIColor(rgb: 0x414345))
        ]
        let pal = palettes[max(0, min(self.styleSegment.selectedSegmentIndex, palettes.count - 1))]
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(Data(self.qrPayload.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let ciCtx = CIContext()
        guard let cgQr = ciCtx.createCGImage(scaled, from: scaled.extent) else { return }
        let qrUiImage = UIImage(cgImage: cgQr)

        let cardSize = CGSize(width: 900, height: 1080)
        let img = UIGraphicsImageRenderer(size: cardSize).image { ctx in
            let cg = ctx.cgContext
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [pal.0.cgColor, pal.1.cgColor] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: cardSize.width, y: cardSize.height), options: [])
            }

            let qrBox = CGRect(x: 110, y: 110, width: 680, height: 680)
            let boxPath = UIBezierPath(roundedRect: qrBox, cornerRadius: 56)
            UIColor.white.setFill()
            boxPath.fill()

            let innerQr = qrBox.insetBy(dx: 44, dy: 44)
            qrUiImage.draw(in: innerQr)

            // Center MediaTok badge
            let badgeRect = CGRect(x: qrBox.midX - 68, y: qrBox.midY - 68, width: 136, height: 136)
            let badgePath = UIBezierPath(ovalIn: badgeRect)
            pal.1.setFill()
            badgePath.fill()
            UIColor.white.setStroke()
            badgePath.lineWidth = 10
            badgePath.stroke()

            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .black),
                .foregroundColor: UIColor.white
            ]
            let badgeStr = "MT" as NSString
            let bSize = badgeStr.size(withAttributes: badgeAttrs)
            badgeStr.draw(at: CGPoint(x: badgeRect.midX - bSize.width / 2, y: badgeRect.midY - bSize.height / 2), withAttributes: badgeAttrs)

            // Handle caption
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 54, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            let handleStr = self.displayHandle as NSString
            let hSize = handleStr.size(withAttributes: titleAttrs)
            handleStr.draw(at: CGPoint(x: (cardSize.width - hSize.width) / 2, y: 840), withAttributes: titleAttrs)

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .medium),
                .foregroundColor: UIColor(white: 1.0, alpha: 0.8)
            ]
            let subStr = "MediaTok Profile QR" as NSString
            let sSize = subStr.size(withAttributes: subAttrs)
            subStr.draw(at: CGPoint(x: (cardSize.width - sSize.width) / 2, y: 920), withAttributes: subAttrs)
        }

        self.renderedCard = img
        self.imageView.image = img
    }

    @objc private func shareTapped() {
        guard let img = self.renderedCard else { return }
        let share = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        MTMediaTokWave8Tools.configurePopover(share)
        self.present(share, animated: true)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

// MARK: - #460 One-Tap Face Blur (`Vision` + `CoreImage`)

public final class MTFaceBlurViewController: UIViewController, PHPickerViewControllerDelegate {
    private let context: AccountContext
    private let targetPeerId: PeerId?
    private let imageView = UIImageView()
    private let statusLabel = UILabel()
    private var processedImage: UIImage?

    public init(context: AccountContext, targetPeerId: PeerId?) {
        self.context = context
        self.targetPeerId = targetPeerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "😶‍🌫️ Размытие лиц (AI)"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.closeTapped))

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        self.imageView.layer.cornerRadius = 18
        self.imageView.clipsToBounds = true
        self.imageView.translatesAutoresizingMaskIntoConstraints = false

        self.statusLabel.text = "Выбери фото — Apple Vision автоматически найдёт и размоет все лица"
        self.statusLabel.textColor = UIColor(white: 0.72, alpha: 1.0)
        self.statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 2
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let pickBtn = UIButton(type: .system)
        pickBtn.setTitle("🖼 Выбрать фото из галереи", for: .normal)
        pickBtn.setTitleColor(.white, for: .normal)
        pickBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        pickBtn.backgroundColor = UIColor(red: 0.16, green: 0.52, blue: 1.0, alpha: 1.0)
        pickBtn.layer.cornerRadius = 14
        pickBtn.addTarget(self, action: #selector(self.pickPhotoTapped), for: .touchUpInside)
        pickBtn.translatesAutoresizingMaskIntoConstraints = false

        let shareBtn = UIButton(type: .system)
        shareBtn.setTitle(self.targetPeerId != nil ? "✈️ Отправить в чат / Поделиться" : "📤 Сохранить / Поделиться фото", for: .normal)
        shareBtn.setTitleColor(.white, for: .normal)
        shareBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        shareBtn.backgroundColor = UIColor(white: 0.18, alpha: 1.0)
        shareBtn.layer.cornerRadius = 14
        shareBtn.addTarget(self, action: #selector(self.exportTapped), for: .touchUpInside)
        shareBtn.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.imageView)
        self.view.addSubview(self.statusLabel)
        self.view.addSubview(pickBtn)
        self.view.addSubview(shareBtn)

        NSLayoutConstraint.activate([
            self.imageView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            self.imageView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.imageView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.imageView.heightAnchor.constraint(equalToConstant: 360),
            self.statusLabel.topAnchor.constraint(equalTo: self.imageView.bottomAnchor, constant: 12),
            self.statusLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            pickBtn.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 16),
            pickBtn.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            pickBtn.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            pickBtn.heightAnchor.constraint(equalToConstant: 48),
            shareBtn.topAnchor.constraint(equalTo: pickBtn.bottomAnchor, constant: 10),
            shareBtn.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            shareBtn.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            shareBtn.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func pickPhotoTapped() {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        self.present(picker, animated: true)
    }

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        self.statusLabel.text = "Анализ лиц через Apple Vision..."
        provider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
            guard let img = obj as? UIImage else { return }
            let normalized = MTFaceBlurViewController.normalizeOrientation(img)
            DispatchQueue.global(qos: .userInitiated).async {
                let res = MTFaceBlurViewController.blurFaces(in: normalized)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.processedImage = res.image
                    self.imageView.image = res.image
                    if res.count > 0 {
                        self.statusLabel.text = "✅ Найдено и размыто лиц: \(res.count)"
                    } else {
                        self.statusLabel.text = "Лица не обнаружены — показано исходное фото"
                    }
                }
            }
        }
    }

    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    private static func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func blurFaces(in image: UIImage) -> (image: UIImage, count: Int) {
        guard let cgImage = image.cgImage else { return (image, 0) }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let faces = request.results ?? []
        guard !faces.isEmpty else { return (image, 0) }

        let ciInput = CIImage(cgImage: cgImage)
        let extent = ciInput.extent
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return (image, 0) }
        blurFilter.setValue(ciInput.clampedToExtent(), forKey: kCIInputImageKey)
        blurFilter.setValue(max(18.0, min(extent.width, extent.height) * 0.032), forKey: kCIInputRadiusKey)
        guard let blurred = blurFilter.outputImage?.cropped(to: extent) else { return (image, 0) }

        // Build oval face mask at 1.0x pixel scale to match CIImage extent exactly (avoids 3x OOM & offset)
        let maskFormat = UIGraphicsImageRendererFormat()
        maskFormat.scale = 1.0
        maskFormat.opaque = true
        let maskImg = UIGraphicsImageRenderer(size: extent.size, format: maskFormat).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: extent.size))
            UIColor.white.setFill()
            for face in faces {
                let b = face.boundingBox
                let rect = CGRect(
                    x: b.origin.x * extent.width,
                    y: (1.0 - b.origin.y - b.height) * extent.height,
                    width: b.width * extent.width,
                    height: b.height * extent.height
                ).insetBy(dx: -b.width * extent.width * 0.14, dy: -b.height * extent.height * 0.18)
                ctx.cgContext.fillEllipse(in: rect)
            }
        }
        guard let maskCg = maskImg.cgImage else { return (image, 0) }
        let ciMask = CIImage(cgImage: maskCg)

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return (image, 0) }
        blend.setValue(blurred, forKey: kCIInputImageKey)
        blend.setValue(ciInput, forKey: kCIInputBackgroundImageKey)
        blend.setValue(ciMask, forKey: kCIInputMaskImageKey)

        guard let outImg = blend.outputImage, let outCg = Self.sharedCIContext.createCGImage(outImg, from: extent) else {
            return (image, 0)
        }
        return (UIImage(cgImage: outCg), faces.count)
    }

    @objc private func exportTapped() {
        guard let img = self.processedImage else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Сначала выбери фото")
            return
        }
        if let peerId = self.targetPeerId, let jpeg = img.jpegData(compressionQuality: 0.9) {
            let randomId = Int64.random(in: Int64.min ... Int64.max)
            let resource = LocalFileMediaResource(fileId: randomId)
            self.context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: jpeg)
            let rep = TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: Int32(img.size.width), height: Int32(img.size.height)), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
            let media = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.LocalImage, id: randomId), representations: [rep], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
            let msg = EnqueueMessage.message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).start()
            MTMediaTokWave5Tools.showToast(context: self.context, text: "😶‍🌫️ Фото с размытыми лицами отправлено!")
            self.dismiss(animated: true)
            return
        }
        let share = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        MTMediaTokWave8Tools.configurePopover(share)
        self.present(share, animated: true)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}

// MARK: - #461 Document Scanner → PDF + #462 Finger PDF Signature

private final class MTDocumentScannerCoordinator: NSObject, VNDocumentCameraViewControllerDelegate, UIDocumentPickerDelegate {
    static let shared = MTDocumentScannerCoordinator()
    private var activeContext: AccountContext?

    func startScan(context: AccountContext) {
        self.activeContext = context
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        MTMediaTokWave5Tools.presentOnRoot(scanner)
    }

    func pickPdfToSign(context: AccountContext) {
        self.activeContext = context
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = self
        MTMediaTokWave5Tools.presentOnRoot(picker)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
        if let ctx = self.activeContext {
            MTMediaTokWave5Tools.showToast(context: ctx, text: "Ошибка сканера: \(error.localizedDescription)")
        }
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self, let ctx = self.activeContext, scan.pageCount > 0 else { return }
            let pageCount = scan.pageCount
            MTMediaTokWave5Tools.showToast(context: ctx, text: "📄 Собираем PDF (\(pageCount) стр.)...")
            DispatchQueue.global(qos: .userInitiated).async {
                let doc = PDFDocument()
                for i in 0 ..< pageCount {
                    autoreleasepool {
                        let pageImg = scan.imageOfPage(at: i)
                        if let page = PDFPage(image: pageImg) {
                            doc.insert(page, at: doc.pageCount)
                        }
                    }
                }
                let outUrl = FileManager.default.temporaryDirectory.appendingPathComponent("MediaTok_Scan_\(Int(Date().timeIntervalSince1970)).pdf")
                doc.write(to: outUrl)

                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title: "📄 Скан сохранён (\(pageCount) стр.)",
                        message: "Подписать документ пальцем или сразу поделиться PDF?",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "✍️ Подписать пальцем", style: .default, handler: { _ in
                        let signer = MTPdfSignatureViewController(context: ctx, pdfURL: outUrl)
                        signer.overrideUserInterfaceStyle = .dark
                        let nav = UINavigationController(rootViewController: signer)
                        nav.overrideUserInterfaceStyle = .dark
                        MTMediaTokWave5Tools.presentOnRoot(nav)
                    }))
                    alert.addAction(UIAlertAction(title: "📤 Поделиться PDF", style: .default, handler: { _ in
                        let share = UIActivityViewController(activityItems: [outUrl], applicationActivities: nil)
                        MTMediaTokWave8Tools.configurePopover(share)
                        MTMediaTokWave5Tools.presentOnRoot(share)
                    }))
                    alert.addAction(UIAlertAction(title: "Готово", style: .cancel))
                    MTMediaTokWave5Tools.presentOnRoot(alert)
                }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let ctx = self.activeContext else { return }
        let signer = MTPdfSignatureViewController(context: ctx, pdfURL: url)
        signer.overrideUserInterfaceStyle = .dark
        let nav = UINavigationController(rootViewController: signer)
        nav.overrideUserInterfaceStyle = .dark
        MTMediaTokWave5Tools.presentOnRoot(nav)
    }
}

private final class MTSignatureCanvasView: UIView {
    private var paths: [UIBezierPath] = []
    private var currentPath: UIBezierPath?
    var inkColor: UIColor = UIColor(red: 0.05, green: 0.22, blue: 0.72, alpha: 1.0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor(white: 0.96, alpha: 1.0)
        self.layer.cornerRadius = 16
        self.clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isEmpty: Bool {
        return self.paths.isEmpty && self.currentPath == nil
    }

    func clear() {
        self.paths.removeAll()
        self.currentPath = nil
        self.setNeedsDisplay()
    }

    func renderTransparentImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: self.bounds.size, format: format).image { _ in
            self.inkColor.setStroke()
            for p in self.paths {
                p.stroke()
            }
            self.currentPath?.stroke()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        let path = UIBezierPath()
        path.lineWidth = 4.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: pt)
        self.currentPath = path
        self.setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        self.currentPath?.addLine(to: pt)
        self.setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let p = self.currentPath {
            self.paths.append(p)
            self.currentPath = nil
        }
        self.setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        self.inkColor.setStroke()
        for p in self.paths {
            p.stroke()
        }
        self.currentPath?.stroke()
    }
}

public final class MTPdfSignatureViewController: UIViewController {
    private let context: AccountContext
    private let pdfURL: URL
    private let pdfView = PDFView()
    private let canvas = MTSignatureCanvasView()

    public init(context: AccountContext, pdfURL: URL) {
        self.context = context
        self.pdfURL = pdfURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "✍️ Подпись PDF"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Очистить", style: .plain, target: self, action: #selector(self.clearTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .done, target: self, action: #selector(self.closeTapped))

        self.pdfView.autoScales = true
        self.pdfView.displayMode = .singlePageContinuous
        self.pdfView.document = PDFDocument(url: self.pdfURL)
        self.pdfView.layer.cornerRadius = 14
        self.pdfView.clipsToBounds = true
        self.pdfView.translatesAutoresizingMaskIntoConstraints = false

        let hint = UILabel()
        hint.text = "Нарисуй подпись пальцем ниже — она будет добавлена на последнюю страницу PDF:"
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.textColor = UIColor(white: 0.72, alpha: 1.0)
        hint.numberOfLines = 2
        hint.translatesAutoresizingMaskIntoConstraints = false

        self.canvas.translatesAutoresizingMaskIntoConstraints = false

        let applyBtn = UIButton(type: .system)
        applyBtn.setTitle("✅ Наложить подпись и поделиться PDF", for: .normal)
        applyBtn.setTitleColor(.white, for: .normal)
        applyBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        applyBtn.backgroundColor = UIColor(red: 0.16, green: 0.52, blue: 1.0, alpha: 1.0)
        applyBtn.layer.cornerRadius = 14
        applyBtn.addTarget(self, action: #selector(self.stampAndShareTapped), for: .touchUpInside)
        applyBtn.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.pdfView)
        self.view.addSubview(hint)
        self.view.addSubview(self.canvas)
        self.view.addSubview(applyBtn)

        NSLayoutConstraint.activate([
            self.pdfView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 10),
            self.pdfView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.pdfView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.pdfView.heightAnchor.constraint(equalToConstant: 280),
            hint.topAnchor.constraint(equalTo: self.pdfView.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.canvas.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
            self.canvas.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            self.canvas.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.canvas.heightAnchor.constraint(equalToConstant: 140),
            applyBtn.topAnchor.constraint(equalTo: self.canvas.bottomAnchor, constant: 14),
            applyBtn.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            applyBtn.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            applyBtn.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func clearTapped() {
        self.canvas.clear()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func stampAndShareTapped() {
        guard !self.canvas.isEmpty else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Нарисуй подпись на белом поле")
            return
        }
        guard let doc = PDFDocument(url: self.pdfURL), doc.pageCount > 0 else {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Не удалось открыть PDF")
            return
        }
        let sigImg = self.canvas.renderTransparentImage()
        let outUrl = FileManager.default.temporaryDirectory.appendingPathComponent("Signed_\(Int(Date().timeIntervalSince1970)).pdf")
        let lastIdx = doc.pageCount - 1

        let firstBounds = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)
        let data = renderer.pdfData { ctx in
            for i in 0 ..< doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let pageBounds = page.bounds(for: .mediaBox)
                ctx.beginPage(withBounds: pageBounds, pageInfo: [:])
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: pageBounds.height)
                cg.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()

                if i == lastIdx {
                    let sigW = min(220.0, pageBounds.width * 0.36)
                    let sigH = sigW * 0.45
                    let sigRect = CGRect(
                        x: pageBounds.width - sigW - 36.0,
                        y: pageBounds.height - sigH - 36.0,
                        width: sigW,
                        height: sigH
                    )
                    sigImg.draw(in: sigRect)
                }
            }
        }

        do {
            try data.write(to: outUrl, options: [.atomic])
            let share = UIActivityViewController(activityItems: [outUrl], applicationActivities: nil)
            MTMediaTokWave8Tools.configurePopover(share)
            self.present(share, animated: true)
        } catch {
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Ошибка сохранения подписанного PDF")
        }
    }
}

// MARK: - #486 UIDevice Battery Swizzling (affects VoIP / Low Power / Telegram system checks)

private extension UIDevice {
    @objc dynamic func gg_swizzledBatteryLevel() -> Float {
        if MTMediaTokWave8Tools.isBatterySpoofEnabled {
            return Float(MTMediaTokWave8Tools.spoofedBatteryLevel) / 100.0
        }
        return self.gg_swizzledBatteryLevel()
    }

    @objc dynamic func gg_swizzledBatteryState() -> UIDevice.BatteryState {
        if MTMediaTokWave8Tools.isBatterySpoofEnabled {
            if MTMediaTokWave8Tools.spoofedBatteryCharging {
                return MTMediaTokWave8Tools.spoofedBatteryLevel >= 100 ? .full : .charging
            }
            return .unplugged
        }
        return self.gg_swizzledBatteryState()
    }
}
