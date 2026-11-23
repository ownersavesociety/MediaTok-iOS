import Foundation
import UIKit
import AVFoundation
import ShazamKit
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
// MediaTok Wave 18 — ShazamKit, Scam/Phishing Detector, Ad Filter, Fake Passcode,
//                    Fake Message Card Builder & Custom Sounds:
//   #124 / .shazam    — Native Apple ShazamKit music recognizer via microphone
//   #157 / .scamcheck — Anti-Scam, IDN Homograph & Social Engineering detector (+ message menu)
//   #161 / .adfilter  — Channel Ad Post filter (#реклама, erid, casino) + clean reader
//   #210 / .fakepass  — Fake Passcode / Panic Mode (hides custom profiles/NFTs/rules cleanly)
//   #212 / .guards    — Accidental Call / Reaction / Channel Send confirmation guards
//   #227/#228 / .fakemsg — Local Fake Message / Screenshot Card Generator (PNG export)
//   #306 / .sounds    — Custom UI Sound Packs (iOS Classic, ICQ, Discord Pop, Cyberpunk)
// ============================================================================

public struct MTWave18GuardsConfig: Codable, Equatable {
    public var confirmCalls: Bool
    public var confirmDoubleTapReaction: Bool
    public var confirmChannelPost: Bool
    public var adFilterEnabled: Bool
    public var customAdKeywords: String
    public var selectedSoundPack: String // "classic", "icq", "discord", "cyberpunk", "silent"
    public var fakePasscodePin: String
    public var isPanicMaskActive: Bool

    private enum CodingKeys: String, CodingKey {
        case confirmCalls, confirmDoubleTapReaction, confirmChannelPost
        case adFilterEnabled, customAdKeywords, selectedSoundPack
        case fakePasscodePin, isPanicMaskActive
    }

    public static let `default` = MTWave18GuardsConfig(
        confirmCalls: false,
        confirmDoubleTapReaction: false,
        confirmChannelPost: false,
        adFilterEnabled: true,
        customAdKeywords: "#реклама, erid:, 2vtz, казино, промокод, реклама., рekлама",
        selectedSoundPack: "classic",
        fakePasscodePin: "",
        isPanicMaskActive: false
    )
}

public enum MTMediaTokWave18Tools {
    private static let configKey = "mediatok.wave18.guards_config.v1"
    public static let confirmDoubleTapReactionDefaultsKey = "mediatok.wave18.confirmDoubleTapReaction"

    public static var isPanicMaskActive: Bool {
        return loadConfig().isPanicMaskActive
    }

    public static func register() {
        UserDefaults.standard.set(loadConfig().confirmDoubleTapReaction, forKey: confirmDoubleTapReactionDefaultsKey)

        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave18Tools.interceptCommands(request)
        }, order: 40)

        // #212 Channel post confirmation gate (runs after all slash commands)
        MTChatScreenHooks.willSendText.register({ request, proceed in
            return MTMediaTokWave18Tools.confirmChannelPostIfNeeded(request, proceed: proceed)
        }, order: 200)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave18Tools.messageMenuItems(menuContext)
        }, order: 97)

        // #212 Wire real outgoing call confirmation gate via MTCallHooks (lower priority than Wave 6 & Ghost Mode)
        MTCallHooks.outgoingCall.register({ request, proceed in
            let cfg = MTMediaTokWave18Tools.loadConfig()
            guard cfg.confirmCalls, !MTMediaTokWave6Tools.isCallConfirmEnabled else { return false }
            let kind = request.isVideo ? "видеозвонок" : "аудиозвонок"
            mtPresentNativeAlert(
                context: request.context,
                title: "Подтвердить звонок?",
                text: "Начать \(kind) этому собеседнику?",
                confirmTitle: "Позвонить",
                destructive: false,
                confirmAction: {
                    proceed()
                }
            )
            return true
        }, order: 120)
    }

    public static func loadConfig() -> MTWave18GuardsConfig {
        var cfg: MTWave18GuardsConfig
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(MTWave18GuardsConfig.self, from: data) {
            cfg = decoded
        } else {
            cfg = .default
        }
        cfg.adFilterEnabled = MTMediaTokWave6Tools.isAdBlockEnabled
        return cfg
    }

    public static func saveConfig(_ cfg: MTWave18GuardsConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        UserDefaults.standard.set(cfg.confirmDoubleTapReaction, forKey: confirmDoubleTapReactionDefaultsKey)
        MTMediaTokWave6Tools.isAdBlockEnabled = cfg.adFilterEnabled
    }

    private static func topViewController() -> UIViewController? {
        return MTModalPresenter.topmostViewController()
    }

    // MARK: - Slash Commands

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(".") else { return false }
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        if lower == ".shazam" || lower == ".track" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentShazamRecognizer(context: request.context) }
            return true
        }
        if lower == ".scamcheck" || lower.hasPrefix(".scamcheck ") {
            let text = lower.hasPrefix(".scamcheck ") ? String(raw.dropFirst(11)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentScamReport(context: request.context, text: text.isEmpty ? (UIPasteboard.general.string ?? "") : text) }
            return true
        }
        if lower == ".adfilter" || lower == ".cleanfeed" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentAdCleanFeed(context: request.context, peerId: peerId) }
            return true
        }
        if lower == ".fakepass" || lower == ".panic" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentFakePasscodeManager(context: request.context) }
            return true
        }
        if lower == ".guards" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentGuardsAndSounds(context: request.context) }
            return true
        }
        if lower == ".sounds" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentGuardsAndSounds(context: request.context) }
            return true
        }
        if lower == ".fakemsg" || lower == ".fakechat" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentFakeMessageBuilder(context: request.context) }
            return true
        }

        return false
    }

    private static func confirmChannelPostIfNeeded(_ request: MTComposedTextRequest, proceed: @escaping () -> Void) -> Bool {
        guard loadConfig().confirmChannelPost else { return false }
        guard let peerId = request.chatLocation.peerId, peerId.namespace == Namespaces.Peer.CloudChannel else {
            return false
        }
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.hasPrefix(".") else { return false }

        let context = request.context
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).startStandalone(next: { peer in
            guard case let .channel(channel) = peer, case .broadcast = channel.info else {
                proceed()
                return
            }
            mtPresentNativeAlert(
                context: context,
                title: "Опубликовать пост в канале?",
                text: "Канал: \(channel.title)\nСообщение увидят все подписчики.",
                confirmTitle: "Опубликовать",
                destructive: false,
                confirmAction: {
                    proceed()
                }
            )
        })
        return true
    }

    // MARK: - Message Context Menu (#157 Scam Check)

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let context = menuContext.context

        return [
            MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Проверить на скам / фишинг",
                icon: { theme in
                    return UIImage(systemName: "shield.lefthalf.filled.badge.checkmark")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave18Tools.presentScamReport(context: context, text: trimmed)
                }
            )))
        ]
    }

    // MARK: - #157 Scam / Phishing / Homograph Analyzer

    public static func analyzeScamRisk(_ text: String) -> (score: Int, verdict: String, reasons: [String]) {
        let lower = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        var score = 0
        var reasons: [String] = []

        let scamPhrases: [(String, String, Int)] = [
            ("сид-фраз", "Запрос сид-фразы (seed phrase) — 100% кража кошелька", 80),
            ("seed phrase", "Запрос seed phrase — кража кошелька", 80),
            ("12 слов", "Запрос 12 слов восстановления кошелька", 70),
            ("проголосуй за", "Классическая схема угона аккаунта («проголосуй за племянницу/подругу»)", 65),
            ("бесплатный premium", "Приманка «Бесплатный Telegram Premium»", 55),
            ("подарил вам telegram premium", "Фишинговый фейк-подарок Premium", 65),
            ("срочно переведи", "Давление срочностью (социальная инженерия)", 40),
            ("подключи кошелек", "Возможный TonConnect/WalletConnect дрейнер", 45),
            ("airdrop claim", "Подозрительный клейм аирдропа", 45),
            ("удвоим ton", "Скам-обещание удвоения крипты", 75)
        ]

        for (needle, reason, pts) in scamPhrases {
            if lower.contains(needle) {
                score += pts
                reasons.append("• \(reason)")
            }
        }

        // Check mixed Latin + Cyrillic inside URLs / domains (IDN homograph attack)
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        for rawToken in tokens {
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "()[]<>\"'.,!?"))
            let lowTok = token.lowercased()
            let hasLat = token.unicodeScalars.contains { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }
            let hasCyr = token.unicodeScalars.contains { (0x0400 ... 0x04FF).contains($0.value) }
            let looksLikeUrlOrDomain = lowTok.contains(".") && (
                lowTok.contains("http") || lowTok.contains("://") || lowTok.contains("t.me") ||
                lowTok.contains("tg") || lowTok.contains("ton") || lowTok.contains("frag") ||
                (hasLat && hasCyr)
            )
            guard looksLikeUrlOrDomain else { continue }

            if hasLat && hasCyr {
                score += 85
                reasons.append("• Обнаружена подмена букв (кириллица + латиница / ё/е гомоглиф в ссылке): \(token)")
            }
            let normalizedTok = lowTok.replacingOccurrences(of: "ё", with: "е")
            if normalizedTok.contains("grabify") || normalizedTok.contains("iplogger") || normalizedTok.contains("2no.co") {
                score += 90
                reasons.append("• Известный IP-логгер в ссылке: \(token)")
            } else {
                let verdict = MTMediaTokCoreLogic.inspectUrlForPhishing(token)
                if verdict.isSuspicious {
                    score += 75
                    reasons.append("• \(verdict.reason ?? "Подозрительная ссылка"): \(token)")
                }
            }
        }

        let clamped = min(100, score)
        let verdict: String
        if clamped >= 65 {
            verdict = "ВЫСОКИЙ РИСК СКАМА (\(clamped)/100)"
        } else if clamped >= 30 {
            verdict = "ПОДОЗРИТЕЛЬНО (\(clamped)/100)"
        } else {
            verdict = "УГРОЗ НЕ ОБНАРУЖЕНО (\(clamped)/100)"
        }
        return (clamped, verdict, reasons)
    }

    public static func presentScamReport(context: AccountContext, text: String) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            mtPresentNativeToast(context: context, text: "Передайте текст после .scamcheck или скопируйте подозрительное сообщение")
            return
        }
        let res = analyzeScamRisk(input)
        let detail = res.reasons.isEmpty ? "Признаков фишинга, IP-логгеров и социальной инженерии не найдено." : res.reasons.joined(separator: "\n")
        mtPresentNativeAlert(context: context, title: res.verdict, text: detail)
    }

    // MARK: - #124 ShazamKit Recognizer

    public static func presentShazamRecognizer(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTShazamRecognizerController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    // MARK: - #161 Channel Ad Filter Reader

    public static func presentAdCleanFeed(context: AccountContext, peerId: PeerId?) {
        guard let peerId = peerId else {
            mtPresentNativeToast(context: context, text: "Откройте канал и введите .adfilter для просмотра чистой ленты без рекламы")
            return
        }
        let controller = mtMakeNativeAdCleanFeedController(context: context, peerId: peerId)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #210 Fake Passcode / Panic Mode

    public static func presentFakePasscodeManager(context: AccountContext) {
        let cfg = loadConfig()
        if cfg.isPanicMaskActive {
            mtPresentNativePrompt(
                context: context,
                title: "Паник-режим активен",
                subtitle: "Введите ПИН-код для выхода из маскировки (.nickfx, коллекция NFT, .vbm и .fakemsg снова станут видимы):",
                placeholder: "ПИН-код",
                characterLimit: 16,
                apply: { raw in
                    let enteredPin = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let current = loadConfig()
                    let isPinValid = current.fakePasscodePin.isEmpty || enteredPin == current.fakePasscodePin
                    guard isPinValid else {
                        mtPresentNativeAlert(
                            context: context,
                            title: "Неверный ПИН-код",
                            text: "Введён неправильный паник-код. Паник-режим остаётся активным."
                        )
                        return
                    }
                    var updated = current
                    updated.isPanicMaskActive = false
                    saveConfig(updated)
                    mtPresentNativeToast(context: context, text: "Паник-режим выключен")
                }
            )
        } else {
            mtPresentNativePrompt(
                context: context,
                title: "Ложный пароль и Паник-режим",
                subtitle: "Задайте ПИН-код (например 4 цифры) для включения маскировки (.nickfx, NFT, .vbm и .fakemsg будут скрыты):",
                value: cfg.fakePasscodePin,
                placeholder: "ПИН-код (например 0000)",
                characterLimit: 16,
                apply: { raw in
                    var updated = loadConfig()
                    let pin = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let effectivePin = pin.isEmpty ? updated.fakePasscodePin : pin
                    guard !effectivePin.isEmpty else {
                        mtPresentNativeAlert(
                            context: context,
                            title: "Требуется ПИН-код",
                            text: "Укажите ПИН-код перед активацией паник-режима, чтобы защитить выход."
                        )
                        return
                    }
                    updated.fakePasscodePin = effectivePin
                    updated.isPanicMaskActive = true
                    saveConfig(updated)
                    mtPresentNativeToast(context: context, text: "Паник-режим активирован")
                }
            )
        }
    }

    // MARK: - #212 Guards & #306 Custom Sounds

    public static func presentGuardsAndSounds(context: AccountContext) {
        let controller = mtMakeNativeGuardsAndSoundsController(context: context)
        mtPushNativeController(controller, context: context)
    }

    // MARK: - #227/#228 Local Fake Message Card Builder

    public static func presentFakeMessageBuilder(context: AccountContext) {
        if isPanicMaskActive {
            MTMediaTokWave5Tools.showToast(context: context, text: "Паник-режим активен: конструктор скрин-сообщений скрыт")
            return
        }
        guard let top = topViewController() else { return }
        let vc = MTFakeMessageBuilderController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        MTModalPresenter.presentOnTopmost(nav, preferredRoot: top.viewIfLoaded?.window?.rootViewController ?? top)
    }
}

// MARK: - #124 ShazamKit Controller

private final class MTShazamRecognizerController: UIViewController, SHSessionDelegate {
    private let context: AccountContext
    private let session = SHSession()
    private var audioEngine = AVAudioEngine()

    private let statusLabel = UILabel()
    private let resultLabel = UILabel()
    private let listenButton = UIButton(type: .system)
    private var isListening = false

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        if self.isListening {
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "ShazamKit Распознавание"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.session.delegate = self

        self.statusLabel.text = "Нажмите «Слушать», чтобы определить играющий трек"
        self.statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        self.statusLabel.textColor = .secondaryLabel
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 0
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false

        self.resultLabel.text = ""
        self.resultLabel.font = .systemFont(ofSize: 20, weight: .bold)
        self.resultLabel.textAlignment = .center
        self.resultLabel.numberOfLines = 0
        self.resultLabel.translatesAutoresizingMaskIntoConstraints = false

        var cfg = UIButton.Configuration.filled()
        cfg.title = "Слушать трек (ShazamKit)"
        cfg.image = UIImage(systemName: "shazam.logo.fill")
        cfg.imagePadding = 8
        cfg.cornerStyle = .capsule
        self.listenButton.configuration = cfg
        self.listenButton.addTarget(self, action: #selector(toggleListening), for: .touchUpInside)
        self.listenButton.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.statusLabel)
        self.view.addSubview(self.resultLabel)
        self.view.addSubview(self.listenButton)

        NSLayoutConstraint.activate([
            self.statusLabel.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: -60),
            self.statusLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),

            self.resultLabel.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 16),
            self.resultLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
            self.resultLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),

            self.listenButton.topAnchor.constraint(equalTo: self.resultLabel.bottomAnchor, constant: 28),
            self.listenButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.listenButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.stopListening()
    }

    @objc private func toggleListening() {
        if self.isListening {
            self.stopListening()
        } else {
            self.startListening()
        }
    }

    private func startListening() {
        let audioSession = AVAudioSession.sharedInstance()
        audioSession.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.statusLabel.text = "Нет доступа к микрофону. Разрешите микрофон в Настройках iOS."
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "Нет доступа к микрофону")
                    return
                }
                self.beginAudioEngineListening()
            }
        }
    }

    private func beginAudioEngineListening() {
        do {
            if self.isListening {
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.audioEngine.stop()
                self.isListening = false
            }
            let audioSession = AVAudioSession.sharedInstance()
            var btOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP]
            #if canImport(AlarmKit)
            btOptions.insert(.allowBluetoothHFP)
            #else
            btOptions.insert(.allowBluetooth)
            #endif
            try audioSession.setCategory(.playAndRecord, mode: .default, options: btOptions)
            try audioSession.setActive(true)
            self.audioEngine = AVAudioEngine()
            let inputNode = self.audioEngine.inputNode
            let hwFormat = inputNode.inputFormat(forBus: 0)
            guard hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 else {
                self.statusLabel.text = "Микрофон недоступен (формат \(Int(hwFormat.sampleRate)) Hz, \(hwFormat.channelCount) ch)."
                return
            }
            inputNode.removeTap(onBus: 0)
            let session = self.session
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak session] buffer, time in
                guard buffer.frameLength > 0 else { return }
                session?.matchStreamingBuffer(buffer, at: time)
            }
            self.audioEngine.prepare()
            try self.audioEngine.start()
            self.isListening = true
            self.statusLabel.text = "Слушаю аудио через ShazamKit..."
            var cfg = self.listenButton.configuration ?? UIButton.Configuration.filled()
            cfg.title = "Остановить"
            cfg.baseBackgroundColor = .systemRed
            self.listenButton.configuration = cfg
        } catch {
            self.statusLabel.text = "Ошибка микрофона: \(error.localizedDescription)"
        }
    }

    private func stopListening() {
        if self.isListening {
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            self.isListening = false
            var cfg = self.listenButton.configuration ?? UIButton.Configuration.filled()
            cfg.title = "Слушать трек (ShazamKit)"
            cfg.baseBackgroundColor = .systemBlue
            self.listenButton.configuration = cfg
        }
    }

    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        let title = item.title ?? "Неизвестный трек"
        let artist = item.artist ?? ""
        let full = artist.isEmpty ? title : "\(artist) — \(title)"
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopListening()
            self.statusLabel.text = "Трек распознан и скопирован в буфер обмена!"
            self.resultLabel.text = full
            UIPasteboard.general.string = full
            MTMediaTokWave5Tools.showToast(context: self.context, text: "Найдено: \(full)")
        }
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let error {
                self.stopListening()
                self.statusLabel.text = "Ошибка ShazamKit: \(error.localizedDescription)"
            } else {
                self.statusLabel.text = "Пока не распознано — поднесите ближе к источнику звука..."
            }
        }
    }

    @objc private func closeTapped() {
        self.stopListening()
        self.dismiss(animated: true)
    }
}

// MARK: - #161 Native Channel Ad-Free Clean Reader

private struct MTAdCleanFeedPostItem: Equatable {
    let id: Int32
    let date: String
    let text: String
}

private struct MTAdCleanFeedState: Equatable {
    var posts: [MTAdCleanFeedPostItem] = []
    var skipped: Int = 0
    var loaded: Bool = false
}

private func mtMakeNativeAdCleanFeedController(context: AccountContext, peerId: PeerId) -> ViewController {
    let statePromise = ValuePromise(MTAdCleanFeedState(), ignoreRepeated: true)

    let cfg = MTMediaTokWave18Tools.loadConfig()
    let stopWords = cfg.customAdKeywords
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }

    let _ = (context.account.postbox.transaction { transaction -> ([MTAdCleanFeedPostItem], Int) in
        var clean: [MTAdCleanFeedPostItem] = []
        var skipped = 0
        let df = DateFormatter()
        df.dateFormat = "dd.MM HH:mm"

        transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 400) { msg in
            let txt = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !txt.isEmpty else { return true }
            let low = txt.lowercased()
            if stopWords.contains(where: { low.contains($0) }) || MTMediaTokCoreLogic.isChannelAdPost(txt) {
                skipped += 1
            } else {
                clean.append(MTAdCleanFeedPostItem(
                    id: msg.id.id,
                    date: df.string(from: Date(timeIntervalSince1970: TimeInterval(msg.timestamp))),
                    text: txt
                ))
            }
            return true
        }
        return (clean, skipped)
    } |> deliverOnMainQueue).startStandalone(next: { clean, skipped in
        statePromise.set(MTAdCleanFeedState(posts: clean, skipped: skipped, loaded: true))
    })

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Чистая лента без рекламы")

        let statusText = st.loaded
            ? "Показано постов: \(st.posts.count) · Отфильтровано рекламы: \(st.skipped)"
            : "Сканирую историю канала и скрываю рекламные посты..."
        model.sections.append([
            .init(id: "s_hdr", kind: .header("Статистика фильтрации")),
            .init(id: "s_info", kind: .info(statusText))
        ])

        var postRows: [MTNativeRow] = [.init(id: "p_hdr", kind: .header("Публикации без рекламы"))]
        if st.loaded && st.posts.isEmpty {
            postRows.append(.init(id: "p_empty", kind: .info("Чистых текстовых постов в кэше этого канала пока нет.")))
        } else {
            for p in st.posts.prefix(80) {
                let rowId = "post_\(p.id)"
                let snippet = String(p.text.prefix(260))
                postRows.append(.init(id: rowId, kind: .info("\(p.date)\n\(snippet)")))
                let copyId = "copy_\(p.id)"
                postRows.append(.init(id: copyId, kind: .action(title: "Скопировать пост (\(p.date))", destructive: false, enabled: true)))
                model.tap[copyId] = {
                    UIPasteboard.general.string = p.text
                    mtPresentNativeToast(context: context, text: "Пост скопирован в буфер обмена")
                }
            }
        }
        model.sections.append(postRows)
        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #212 Guards & #306 Native Custom Sounds Controller

private func mtMakeNativeGuardsAndSoundsController(context: AccountContext) -> ViewController {
    let initial = MTMediaTokWave18Tools.loadConfig()
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)

    let soundPacks: [(key: String, title: String, effectId: String?)] = [
        ("classic", "iOS Classic", "chime"),
        ("icq", "ICQ Классика", "icq_uhoh"),
        ("discord", "Discord Pop", "vine_boom"),
        ("cyberpunk", "Cyberpunk", "laser"),
        ("silent", "Без звукового эффекта", nil)
    ]

    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { cfg in
        var model = MTNativeScreenModel(title: "Защиты и Звуки")

        model.sections.append([
            .init(id: "g_hdr", kind: .header("Защита от случайных нажатий")),
            .init(id: "g_calls", kind: .toggle(title: "Подтверждать исходящие звонки", value: cfg.confirmCalls, enabled: true)),
            .init(id: "g_react", kind: .toggle(title: "Защита от реакции двойным тапом", value: cfg.confirmDoubleTapReaction, enabled: true)),
            .init(id: "g_chan", kind: .toggle(title: "Подтверждать посты в каналах", value: cfg.confirmChannelPost, enabled: true)),
            .init(id: "g_ads", kind: .toggle(title: "Авто-фильтр рекламы в каналах", value: cfg.adFilterEnabled, enabled: true)),
            .init(id: "g_ftr", kind: .footer("Защищает от случайного старта звонка, лайка или публикации в публичный канал."))
        ])

        model.toggle["g_calls"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.confirmCalls = val; return c }
            MTMediaTokWave18Tools.saveConfig(next)
            statePromise.set(next)
        }
        model.toggle["g_react"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.confirmDoubleTapReaction = val; return c }
            MTMediaTokWave18Tools.saveConfig(next)
            statePromise.set(next)
        }
        model.toggle["g_chan"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.confirmChannelPost = val; return c }
            MTMediaTokWave18Tools.saveConfig(next)
            statePromise.set(next)
        }
        model.toggle["g_ads"] = { val in
            let next = stateValue.modify { cur in var c = cur; c.adFilterEnabled = val; return c }
            MTMediaTokWave18Tools.saveConfig(next)
            statePromise.set(next)
        }

        var soundRows: [MTNativeRow] = [.init(id: "s_hdr", kind: .header("Звуковой пакет уведомлений"))]
        for sp in soundPacks {
            let id = "sp_\(sp.key)"
            soundRows.append(.init(id: id, kind: .check(title: sp.title, subtitle: nil, checked: cfg.selectedSoundPack == sp.key)))
            model.tap[id] = {
                let next = stateValue.modify { cur in var c = cur; c.selectedSoundPack = sp.key; return c }
                MTMediaTokWave18Tools.saveConfig(next)
                statePromise.set(next)
                if let effectId = sp.effectId {
                    let pcm = MTMediaTokWave16Tools.synthesizeSoundEffect(id: effectId)
                    MTMediaTokWave16Tools.playPcm48kLocally(pcm)
                }
            }
        }
        model.sections.append(soundRows)

        model.sections.append([
            .init(id: "p_hdr", kind: .header("Маскировка")),
            .init(id: "panic_mgr", kind: .disclosure(title: "Ложный пароль и Паник-режим", label: cfg.isPanicMaskActive ? "Активен" : "Выкл", icon: .system("lock.shield"), enabled: true))
        ])
        model.tap["panic_mgr"] = {
            MTMediaTokWave18Tools.presentFakePasscodeManager(context: context)
        }

        return model
    }

    return mtMakeNativeListController(context: context, model: modelSignal)
}

// MARK: - #227/#228 Local Fake Message Card Builder

private final class MTFakeMessageBuilderController: UIViewController {
    private let context: AccountContext
    private let authorField = UITextField()
    private let textField = UITextField()
    private let timeField = UITextField()
    private let outgoingSwitch = UISwitch()
    private let previewCard = UIView()
    private let bubbleView = UIView()
    private let authorLbl = UILabel()
    private let bodyLbl = UILabel()
    private let timeLbl = UILabel()
    private var incomingLeadingConstraint: NSLayoutConstraint?
    private var incomingMaxTrailingConstraint: NSLayoutConstraint?
    private var outgoingTrailingConstraint: NSLayoutConstraint?
    private var outgoingMaxLeadingConstraint: NSLayoutConstraint?

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Конструктор скрин-сообщения"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "В PNG", style: .done, target: self, action: #selector(exportPngTapped))

        self.previewCard.backgroundColor = UIColor(red: 0.07, green: 0.10, blue: 0.16, alpha: 1.0)
        self.previewCard.layer.cornerRadius = 18
        self.previewCard.layer.cornerCurve = .continuous
        self.previewCard.translatesAutoresizingMaskIntoConstraints = false

        self.bubbleView.backgroundColor = UIColor(red: 0.14, green: 0.21, blue: 0.34, alpha: 1.0)
        self.bubbleView.layer.cornerRadius = 16
        self.bubbleView.layer.cornerCurve = .continuous
        self.bubbleView.translatesAutoresizingMaskIntoConstraints = false

        self.authorLbl.font = .systemFont(ofSize: 13, weight: .semibold)
        self.authorLbl.textColor = .systemCyan
        self.authorLbl.translatesAutoresizingMaskIntoConstraints = false

        self.bodyLbl.font = .systemFont(ofSize: 16)
        self.bodyLbl.textColor = .white
        self.bodyLbl.numberOfLines = 0
        self.bodyLbl.translatesAutoresizingMaskIntoConstraints = false

        self.timeLbl.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        self.timeLbl.textColor = UIColor.white.withAlphaComponent(0.65)
        self.timeLbl.textAlignment = .right
        self.timeLbl.translatesAutoresizingMaskIntoConstraints = false

        self.bubbleView.addSubview(self.authorLbl)
        self.bubbleView.addSubview(self.bodyLbl)
        self.bubbleView.addSubview(self.timeLbl)
        self.previewCard.addSubview(self.bubbleView)

        let inLead = self.bubbleView.leadingAnchor.constraint(equalTo: self.previewCard.leadingAnchor, constant: 18)
        let inMaxTrail = self.bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: self.previewCard.trailingAnchor, constant: -56)
        let outTrail = self.bubbleView.trailingAnchor.constraint(equalTo: self.previewCard.trailingAnchor, constant: -18)
        let outMaxLead = self.bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: self.previewCard.leadingAnchor, constant: 56)
        self.incomingLeadingConstraint = inLead
        self.incomingMaxTrailingConstraint = inMaxTrail
        self.outgoingTrailingConstraint = outTrail
        self.outgoingMaxLeadingConstraint = outMaxLead

        let centerY = self.bubbleView.centerYAnchor.constraint(equalTo: self.previewCard.centerYAnchor)
        centerY.priority = .defaultHigh

        NSLayoutConstraint.activate([
            self.previewCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            centerY,
            self.bubbleView.topAnchor.constraint(greaterThanOrEqualTo: self.previewCard.topAnchor, constant: 18),
            self.bubbleView.bottomAnchor.constraint(lessThanOrEqualTo: self.previewCard.bottomAnchor, constant: -18),
            inLead,
            inMaxTrail,
            self.authorLbl.topAnchor.constraint(equalTo: self.bubbleView.topAnchor, constant: 10),
            self.authorLbl.leadingAnchor.constraint(equalTo: self.bubbleView.leadingAnchor, constant: 14),
            self.authorLbl.trailingAnchor.constraint(equalTo: self.bubbleView.trailingAnchor, constant: -14),
            self.bodyLbl.topAnchor.constraint(equalTo: self.authorLbl.bottomAnchor, constant: 4),
            self.bodyLbl.leadingAnchor.constraint(equalTo: self.bubbleView.leadingAnchor, constant: 14),
            self.bodyLbl.trailingAnchor.constraint(equalTo: self.bubbleView.trailingAnchor, constant: -14),
            self.timeLbl.topAnchor.constraint(equalTo: self.bodyLbl.bottomAnchor, constant: 4),
            self.timeLbl.leadingAnchor.constraint(equalTo: self.bubbleView.leadingAnchor, constant: 14),
            self.timeLbl.trailingAnchor.constraint(equalTo: self.bubbleView.trailingAnchor, constant: -14),
            self.timeLbl.bottomAnchor.constraint(equalTo: self.bubbleView.bottomAnchor, constant: -8)
        ])

        self.authorField.borderStyle = .roundedRect
        self.authorField.placeholder = "Имя автора"
        self.authorField.text = "Pavel Durov"
        self.authorField.addTarget(self, action: #selector(refreshCard), for: .editingChanged)

        self.textField.borderStyle = .roundedRect
        self.textField.placeholder = "Текст сообщения"
        self.textField.text = "MediaTok — лучший клиент для iOS!"
        self.textField.addTarget(self, action: #selector(refreshCard), for: .editingChanged)

        self.timeField.borderStyle = .roundedRect
        self.timeField.placeholder = "Время (например 23:59)"
        self.timeField.text = "23:59"
        self.timeField.addTarget(self, action: #selector(refreshCard), for: .editingChanged)

        self.outgoingSwitch.addTarget(self, action: #selector(refreshCard), for: .valueChanged)

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        let lbl = UILabel()
        lbl.text = "Исходящее сообщение (с галочками ✓✓)"
        lbl.font = .systemFont(ofSize: 14)
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(self.outgoingSwitch)

        let stack = UIStackView(arrangedSubviews: [self.previewCard, self.authorField, self.textField, self.timeField, row])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16)
        ])

        self.refreshCard()
    }

    @objc private func refreshCard() {
        self.authorLbl.text = self.authorField.text ?? ""
        self.bodyLbl.text = self.textField.text ?? ""
        let t = self.timeField.text ?? "12:00"
        let isOut = self.outgoingSwitch.isOn
        self.timeLbl.text = isOut ? "\(t) ✓✓" : t
        self.bubbleView.backgroundColor = isOut
            ? UIColor(red: 0.22, green: 0.44, blue: 0.88, alpha: 1.0)
            : UIColor(red: 0.14, green: 0.21, blue: 0.34, alpha: 1.0)
        self.incomingLeadingConstraint?.isActive = !isOut
        self.incomingMaxTrailingConstraint?.isActive = !isOut
        self.outgoingTrailingConstraint?.isActive = isOut
        self.outgoingMaxLeadingConstraint?.isActive = isOut
        self.previewCard.layoutIfNeeded()
    }

    @objc private func exportPngTapped() {
        self.previewCard.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: self.previewCard.bounds)
        let img = renderer.image { ctx in
            self.previewCard.layer.render(in: ctx.cgContext)
        }
        let share = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        if let pop = share.popoverPresentationController {
            pop.sourceView = self.view
            pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
        }
        self.present(share, animated: true)
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}
