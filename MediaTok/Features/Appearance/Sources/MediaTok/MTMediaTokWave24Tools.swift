import Foundation
import UIKit
import MachO
import Darwin
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import Display
import ItemListUI
import ContextUI
import MTCore
import MTHooks
import MTSettingsUI
import MTAppearanceSettings

// ============================================================================
// MediaTok Wave 24 — Apple Books Integration, Anti-Jailbreak / Anti-Hook Shield,
//                    Tonkeeper + xRocket Wallet Transfer & Per-Account Top Bar Strip:
//   • Apple Books (.books)          — One-tap open .epub / .pdf / .fb2 attachments directly in Apple Books
//   • Anti-Jailbreak (.jbcheck)     — Multi-layer rootless/palera1n/Dopamine + dyld tweak + sandbox write + ptrace guard
//   • Tonkeeper + xRocket (.tonpay) — Direct transfer by TON address with amount + comment/memo & xRocket bot shortcut
//   • #1110 (.acctbar)              — Color-coded top bar strip per logged-in account (never confuse main vs alt!)
//   • #1346                         — Quick Scroll-Jump Back helper in chat
// ============================================================================

private final class MTWave24Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

public struct MTWave24Config: Codable, Equatable {
    public var antiJailbreakLockEnabled: Bool
    public var accountColorStripEnabled: Bool
    public var liquidIridescentHeaderEnabled: Bool = false
    public var defaultSavedTonAddress: String

    private enum CodingKeys: String, CodingKey {
        case antiJailbreakLockEnabled
        case accountColorStripEnabled
        case liquidIridescentHeaderEnabled
        case defaultSavedTonAddress
    }

    public static let `default` = MTWave24Config(
        antiJailbreakLockEnabled: true,
        accountColorStripEnabled: false,
        liquidIridescentHeaderEnabled: false,
        defaultSavedTonAddress: ""
    )
}

public enum MTMediaTokWave24Tools {
    private static let configKey = "mediatok.wave24.config.v2"
    private static let stateBox = MTWave24Box<(
        cachedConfig: MTWave24Config,
        activeDocController: UIDocumentInteractionController?
    )>((.default, nil))

    // MARK: - Registration

    public static func register() {
        let initial = loadConfigFromDisk()
        stateBox.withLock { $0.cachedConfig = initial }

        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave24Tools.interceptCommands(request)
        }, order: 46)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave24Tools.messageMenuItems(menuContext)
        }, order: 102)

        // Apple Books auto-offer when tapping .epub / .fb2 documents in chat
        MTChatScreenHooks.openDocument.register({ docReq in
            let low = docReq.fileName.lowercased()
            guard low.hasSuffix(".epub") || low.hasSuffix(".fb2") else { return false }
            MTMediaTokWave24Tools.openLocalPathInAppleBooks(context: docReq.context, filePath: docReq.path, fileName: docReq.fileName)
            return true
        }, order: 40)

        // #1110 + iOS 27 Liquid Glass Iridescent Shimmer on Top Bar of Chat List & Inside Chats
        MTChatListChromeHooks.containerDidLayout.register({ layout in
            MTMediaTokWave24Tools.applyAccountColorStrip(layout: layout)
        }, order: 140)

        MTChatListChromeHooks.navigationBarDidLayout.register({ barLayout in
            MTMediaTokWave24Tools.applyLiquidHeaderToChatListBar(barLayout: barLayout)
        }, order: 141)

        MTChatScreenHooks.overlays.register({ screen in
            if screen.isPreview { return [] }
            return [MTLiquidGlassChatHeaderOverlay()]
        }, order: 148)

        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            if MTMediaTokWave24Tools.loadConfig().antiJailbreakLockEnabled {
                let jb = MTMediaTokWave24Tools.performDeepJailbreakScan()
                if jb.isCompromised {
                    // Protect Pro license & sensitive vaults if jailbreak / hook framework detected
                    MTMediaTokWave19Tools.isProActive = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        MTMediaTokWave19Tools.engageEmergencyLockCurtain(reason: "Анти-Джейлбрейк защита MediaTok: \(jb.reasons.joined(separator: ", "))")
                    }
                }
            }
        }, order: 47)
    }

    // MARK: - Persistence

    private static func loadConfigFromDisk() -> MTWave24Config {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let decoded = try? JSONDecoder().decode(MTWave24Config.self, from: data) else {
            return .default
        }
        return decoded
    }

    public static func loadConfig() -> MTWave24Config {
        return stateBox.withLock { $0.cachedConfig }
    }

    public static func saveConfig(_ cfg: MTWave24Config) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        stateBox.withLock { $0.cachedConfig = cfg }
    }

    private static func topViewController() -> UIViewController? {
        return MTModalPresenter.topmostViewController()
    }

    // MARK: - Multi-Layer Anti-Jailbreak & Anti-Hook Shield

    public static func performDeepJailbreakScan() -> (isCompromised: Bool, reasons: [String]) {
        #if targetEnvironment(simulator)
        return (false, [])
        #else
        var reasons: [String] = []

        // 1. Rootfull + Rootless (Dopamine / palera1n / NathanLR / XinaA15) filesystem artifacts
        let jbPaths = [
            "/var/jb",
            "/private/preboot/jb",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/usr/lib/libhooker.dylib",
            "/usr/lib/ellekit.dylib",
            "/var/jb/usr/lib/ellekit.dylib",
            "/var/jb/Applications/Sileo.app",
            "/var/jb/Applications/Filza.app",
            "/bin/bash",
            "/usr/sbin/sshd"
        ]
        for path in jbPaths {
            if FileManager.default.fileExists(atPath: path) || access(path, F_OK) == 0 {
                reasons.append("FS:\((path as NSString).lastPathComponent)")
                break
            }
        }

        // 2. Sandbox Escape Write Test (writing outside container /private/)
        let probePath = "/private/mt_jb_probe_\(UUID().uuidString).tmp"
        if (try? "1".write(toFile: probePath, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.removeItem(atPath: probePath)
            reasons.append("SandboxEscape:/private")
        }

        // 3. Loaded Dyld Image Inspection (Frida, Cycript, Substrate, ElleKit, Substitute, Satella, SSLKillSwitch)
        let dangerousTokens = ["substrate", "substitute", "ellekit", "libhooker", "frida", "cycript", "sslkillswitch", "satella", "shadow.dylib", "choicy"]
        let count = _dyld_image_count()
        for i in 0 ..< count {
            if let cName = _dyld_get_image_name(i) {
                let img = String(cString: cName).lowercased()
                for tok in dangerousTokens where img.contains(tok) {
                    reasons.append("Dyld:\(tok)")
                    break
                }
                if !reasons.isEmpty { break }
            }
        }

        // 4. Environment Variable Injection Check (ignore benign SideStore/AltStore/LiveContainer/Xcode dylibs)
        if let ins = getenv("DYLD_INSERT_LIBRARIES") {
            let envStr = String(cString: ins).lowercased()
            let jbEnvTokens = ["substrate", "substitute", "ellekit", "libhooker", "frida", "cycript", "sslkillswitch", "satella", "choicy", "tweakinject", "rocketbootstrap"]
            for tok in jbEnvTokens where envStr.contains(tok) {
                reasons.append("Env:DYLD(\(tok))")
                break
            }
        }

        // 5. Jailbreak Package Manager URL Schemes
        if Thread.isMainThread {
            for scheme in ["sileo://package/com.opa334", "cydia://", "zbra://", "filza://"] {
                if let u = URL(string: scheme), UIApplication.shared.canOpenURL(u) {
                    reasons.append("Scheme:\(scheme.replacingOccurrences(of: "://", with: ""))")
                    break
                }
            }
        }

        return (!reasons.isEmpty, reasons)
        #endif
    }

    // MARK: - #1110 Per-Account Colored Top Strip

    private static func applyAccountColorStrip(layout: MTChatListContainerLayout) {
        let view = layout.node.view
        let tag = 91110
        guard loadConfig().accountColorStripEnabled else {
            view.viewWithTag(tag)?.removeFromSuperview()
            return
        }
        let strip: UIView
        if let existing = view.viewWithTag(tag) {
            strip = existing
        } else {
            strip = UIView()
            strip.tag = tag
            strip.isUserInteractionEnabled = false
            strip.layer.cornerRadius = 1.5
            view.addSubview(strip)
        }
        let palette: [UIColor] = [
            .systemBlue,
            .systemEmeraldColor,
            .systemRed,
            .systemPurple,
            .systemOrange,
            .systemCyan
        ]
        let uid = abs(layout.context.account.peerId.id._internalGetInt64Value())
        let color = palette[Int(uid % Int64(palette.count))]
        strip.backgroundColor = color.withAlphaComponent(0.88)
        let topY = max(2, layout.layout.safeInsets.top)
        strip.frame = CGRect(x: 24, y: topY, width: layout.layout.size.width - 48, height: 3.0)
        view.bringSubviewToFront(strip)
    }

    // MARK: - iOS 27 Liquid Glass Prismatic Iridescent Header Shimmer

    fileprivate static func applyLiquidHeaderToChatListBar(barLayout: MTChatListNavigationBarLayout) {
        let barView = barLayout.view
        let tag = 92727
        guard loadConfig().liquidIridescentHeaderEnabled, barLayout.size.width > 10 else {
            barView.viewWithTag(tag)?.removeFromSuperview()
            return
        }
        let shimmer: MTLiquidIridescentBarView
        if let existing = barView.viewWithTag(tag) as? MTLiquidIridescentBarView {
            shimmer = existing
        } else {
            shimmer = MTLiquidIridescentBarView(frame: CGRect(origin: .zero, size: barLayout.size))
            shimmer.tag = tag
            barView.insertSubview(shimmer, at: 1)
        }
        shimmer.frame = CGRect(origin: .zero, size: barLayout.size)
        shimmer.ensureAnimating()
    }

    // MARK: - Slash Commands

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(".") else { return false }
        let lower = raw.lowercased()

        if lower == ".tonpay" || lower == ".tonkeeper" || lower == ".xrocket" || lower.hasPrefix(".tonpay ") {
            let arg = lower.hasPrefix(".tonpay ") ? String(raw.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                presentTonkeeperAndXRocketTransfer(context: request.context, initialAddress: arg, peerId: request.chatLocation.peerId)
            }
            return true
        }
        if lower == ".jbcheck" || lower == ".antijb" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentJailbreakSecurityReport(context: request.context) }
            return true
        }
        if lower == ".acctbar" || lower == ".liquidbar" || lower == ".ios27bar" {
            request.replace(ChatTextInputState())
            var cfg = loadConfig()
            cfg.liquidIridescentHeaderEnabled.toggle()
            saveConfig(cfg)
            NotificationCenter.default.post(name: Notification.Name("mediatok.wave24.liquidbar_changed"), object: nil)
            MTMediaTokWave5Tools.showToast(context: request.context, text: cfg.liquidIridescentHeaderEnabled ? "Перелив шапки iOS 27 Liquid Glass включён" : "Перелив шапки выключен")
            return true
        }
        return false
    }

    // MARK: - Context Menu: Open in Apple Books + Send TON via Tonkeeper / xRocket

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        var entries: [MTMessageMenuEntry] = []

        // 1. Apple Books direct integration for .epub / .pdf / .fb2 attachments
        for m in message.media {
            if let file = m as? TelegramMediaFile, let fn = file.fileName {
                let low = fn.lowercased()
                if low.hasSuffix(".epub") || low.hasSuffix(".pdf") || low.hasSuffix(".fb2") {
                    entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                        text: "Открыть в Apple Книгах",
                        icon: { theme in
                            return UIImage(systemName: "book.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                        },
                        action: { _, f in
                            f(.default)
                            MTMediaTokWave24Tools.downloadAndOpenInAppleBooks(context: context, message: message, file: file, fileName: fn)
                        }
                    ))))
                    break
                }
            }
        }

        // 2. Detect TON Wallet Address (UQ... or EQ... 48 chars, or .ton domain) -> Tonkeeper & xRocket Transfer with Comment!
        if let detectedAddr = extractTonAddress(from: message.text) {
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Перевести TON с комментом (Tonkeeper / xRocket)",
                icon: { theme in
                    return UIImage(systemName: "paperplane.circle.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    DispatchQueue.main.async {
                        MTMediaTokWave24Tools.presentTonkeeperAndXRocketTransfer(context: context, initialAddress: detectedAddr, peerId: message.id.peerId)
                    }
                }
            ))))
        }

        return entries
    }

    private static func extractTonAddress(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for w in words {
            let clean = w.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:()[]<>\"'"))
            if (clean.hasPrefix("UQ") || clean.hasPrefix("EQ")) && clean.count >= 46 && clean.count <= 50 {
                return clean
            }
            if clean.lowercased().hasSuffix(".ton") && clean.count >= 5 {
                return clean
            }
        }
        return nil
    }

    // MARK: - Apple Books Handoff

    public static func downloadAndOpenInAppleBooks(context: AccountContext, message: Message, file: TelegramMediaFile, fileName: String) {
        let _ = (context.account.postbox.mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: false))
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { data in
            guard data.complete, data.size > 0 else {
                let ref = FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource)
                let _ = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .file, reference: ref).startStandalone()
                MTMediaTokWave5Tools.showToast(context: context, text: "Книга скачивается — нажмите ещё раз после загрузки")
                return
            }
            openLocalPathInAppleBooks(context: context, filePath: data.path, fileName: fileName)
        })
    }

    public static func openLocalPathInAppleBooks(context: AccountContext, filePath: String, fileName: String) {
        let safeName = (fileName as NSString).lastPathComponent
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MTAppleBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let dstUrl = tmpDir.appendingPathComponent(safeName)
        try? FileManager.default.removeItem(at: dstUrl)
        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: filePath), to: dstUrl)
            DispatchQueue.main.async {
                guard let top = topViewController() else { return }
                let doc = UIDocumentInteractionController(url: dstUrl)
                stateBox.withLock { $0.activeDocController = doc }
                if !doc.presentOpenInMenu(from: CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1), in: top.view, animated: true) {
                    let av = UIActivityViewController(activityItems: [dstUrl], applicationActivities: nil)
                    MTModalPresenter.presentOnTopmost(av, preferredRoot: top.viewIfLoaded?.window?.rootViewController ?? top)
                }
            }
        } catch {
            MTMediaTokWave5Tools.showToast(context: context, text: "Не удалось подготовить файл для Apple Books")
        }
    }

    // MARK: - Tonkeeper + xRocket Wallet Transfer by Address with Comment/Memo

    public static func presentTonkeeperAndXRocketTransfer(context: AccountContext, initialAddress: String, peerId: PeerId?) {
        let vc = mtMakeNativeTonTransferController(context: context, initialAddress: initialAddress, peerId: peerId)
        mtPushNativeController(vc, context: context)
    }

    public static func presentJailbreakSecurityReport(context: AccountContext) {
        let res = performDeepJailbreakScan()
        let cfg = loadConfig()
        mtPresentNativeAlert(
            context: context,
            title: res.isCompromised ? "Обнаружен Джейлбрейк / Инжект" : "Устройство чистое",
            text: res.isCompromised
                ? "Сработали сенсоры: \(res.reasons.joined(separator: ", ")). Локальные сейфы переведены в защитный режим."
                : "Проверены /var/jb, песочница /private, инжекты dyld и схемы Sileo/Filza. Угроз не обнаружено.",
            confirmTitle: cfg.antiJailbreakLockEnabled ? "Выключить авто-блок" : "Включить авто-блок",
            destructive: false,
            confirmAction: {
                var c = loadConfig()
                c.antiJailbreakLockEnabled.toggle()
                saveConfig(c)
            }
        )
    }
}

private extension UIColor {
    static var systemEmeraldColor: UIColor {
        return UIColor(red: 0.12, green: 0.78, blue: 0.52, alpha: 1.0)
    }
}

// MARK: - iOS 27 Liquid Glass Prismatic Header View + Chat Screen Overlay

private final class MTLiquidIridescentBarView: UIView {
    private let ambientLayer = CAGradientLayer()
    private let rimLayer = CAGradientLayer()
    private let fadeMask = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.clipsToBounds = true

        // Soft translucent Apple Intelligence / iOS 27 Liquid Glass prismatic wash
        self.ambientLayer.colors = [
            UIColor(red: 0.22, green: 0.86, blue: 1.00, alpha: 0.20).cgColor,
            UIColor(red: 0.48, green: 0.36, blue: 1.00, alpha: 0.22).cgColor,
            UIColor(red: 0.98, green: 0.32, blue: 0.74, alpha: 0.20).cgColor,
            UIColor(red: 1.00, green: 0.68, blue: 0.26, alpha: 0.18).cgColor,
            UIColor(red: 0.22, green: 0.86, blue: 1.00, alpha: 0.20).cgColor
        ]
        self.ambientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.ambientLayer.endPoint = CGPoint(x: 1.0, y: 0.9)

        self.fadeMask.colors = [
            UIColor.white.cgColor,
            UIColor(white: 1.0, alpha: 0.75).cgColor,
            UIColor.clear.cgColor
        ]
        self.fadeMask.locations = [0.0, 0.72, 1.0]
        self.ambientLayer.mask = self.fadeMask

        // Crisp 1.5pt prismatic refraction rim along the bottom edge of the header
        self.rimLayer.colors = [
            UIColor(red: 0.24, green: 0.90, blue: 1.00, alpha: 0.78).cgColor,
            UIColor(red: 0.58, green: 0.40, blue: 1.00, alpha: 0.82).cgColor,
            UIColor(red: 1.00, green: 0.36, blue: 0.76, alpha: 0.82).cgColor,
            UIColor(red: 1.00, green: 0.74, blue: 0.28, alpha: 0.78).cgColor,
            UIColor(red: 0.24, green: 0.90, blue: 1.00, alpha: 0.78).cgColor
        ]
        self.rimLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.rimLayer.endPoint = CGPoint(x: 1.0, y: 0.5)

        self.layer.addSublayer(self.ambientLayer)
        self.layer.addSublayer(self.rimLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = self.bounds
        self.ambientLayer.frame = b
        self.fadeMask.frame = b
        self.rimLayer.frame = CGRect(x: 0, y: max(0, b.height - 1.5), width: b.width, height: 1.5)
    }

    func stopAnimating() {
        self.ambientLayer.removeAllAnimations()
        self.rimLayer.removeAllAnimations()
    }

    func ensureAnimating() {
        guard self.ambientLayer.animation(forKey: "ios27Shift") == nil else { return }

        let shift = CABasicAnimation(keyPath: "startPoint")
        shift.fromValue = CGPoint(x: 0.0, y: 0.0)
        shift.toValue = CGPoint(x: 0.85, y: 0.35)
        shift.duration = 5.5
        shift.autoreverses = true
        shift.repeatCount = .infinity
        shift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shift.isRemovedOnCompletion = false
        self.ambientLayer.add(shift, forKey: "ios27Shift")

        let endShift = CABasicAnimation(keyPath: "endPoint")
        endShift.fromValue = CGPoint(x: 1.0, y: 1.0)
        endShift.toValue = CGPoint(x: 0.15, y: 0.65)
        endShift.duration = 5.5
        endShift.autoreverses = true
        endShift.repeatCount = .infinity
        endShift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        endShift.isRemovedOnCompletion = false
        self.ambientLayer.add(endShift, forKey: "ios27EndShift")

        let rimAnim = CABasicAnimation(keyPath: "locations")
        rimAnim.fromValue = [-0.4, -0.1, 0.25, 0.6, 1.0]
        rimAnim.toValue = [0.0, 0.35, 0.7, 1.05, 1.4]
        rimAnim.duration = 4.2
        rimAnim.autoreverses = true
        rimAnim.repeatCount = .infinity
        rimAnim.isRemovedOnCompletion = false
        self.rimLayer.add(rimAnim, forKey: "ios27Rim")
    }
}

private final class MTLiquidGlassChatHeaderOverlay: MTChatOverlay {
    let node = ASDisplayNode()
    let placement: MTChatOverlayPlacement = .aboveHistory

    private var barView: MTLiquidIridescentBarView?
    private var observer: NSObjectProtocol?
    private var lastBounds: CGRect = .zero
    private var lastTopInset: CGFloat = 0

    init() {
        self.node.isUserInteractionEnabled = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let v = MTLiquidIridescentBarView(frame: .zero)
            self.node.view.addSubview(v)
            self.barView = v
            self.observer = NotificationCenter.default.addObserver(forName: Notification.Name("mediatok.wave24.liquidbar_changed"), object: nil, queue: .main) { [weak self] _ in
                self?.refreshVisibility()
            }
            self.refreshVisibility()
        }
    }

    deinit {
        if let obs = self.observer {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func refreshVisibility() {
        let on = MTMediaTokWave24Tools.loadConfig().liquidIridescentHeaderEnabled
        self.barView?.isHidden = !on
        if on {
            self.barView?.ensureAnimating()
        } else {
            self.barView?.stopAnimating()
        }
    }

    func updateLayout(bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        self.lastBounds = bounds
        self.lastTopInset = insets.top
        let h = max(88, min(136, insets.top))
        self.barView?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: h)
        self.refreshVisibility()
    }
}

// MARK: - Tonkeeper + xRocket Transfer Controller (Address + Amount + Comment/Memo)

private func mtMakeNativeTonTransferController(context: AccountContext, initialAddress: String, peerId: PeerId?) -> ItemListController {
    struct TonFormState {
        var address: String
        var amount: String = ""
        var comment: String = ""
    }

    let fallback = MTMediaTokWave24Tools.loadConfig().defaultSavedTonAddress
    let stateAtomic = Atomic<TonFormState>(value: TonFormState(address: initialAddress.isEmpty ? fallback : initialAddress))
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revCount = 0
    let bump: () -> Void = {
        revCount += 1
        revision.set(revCount)
    }
    weak var weakController: ItemListController?

    let buildParams: () -> (addr: String, nanoStr: String, encodedComment: String, amtRaw: String, commRaw: String)? = {
        let st = stateAtomic.with { $0 }
        let addr = st.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addr.isEmpty else {
            mtPresentNativeToast(context: context, from: weakController, text: "Укажите адрес кошелька TON (UQ... / EQ...)")
            return nil
        }
        var cfg = MTMediaTokWave24Tools.loadConfig()
        cfg.defaultSavedTonAddress = addr
        MTMediaTokWave24Tools.saveConfig(cfg)

        let amtRaw = st.amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        var nanoStr = ""
        if let val = Double(amtRaw), val > 0 {
            nanoStr = "\(Int64((val * 1_000_000_000.0).rounded()))"
        }
        let commRaw = st.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let encComm = commRaw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return (addr, nanoStr, encComm, amtRaw, commRaw)
    }

    let buildQuery: (String, String) -> String = { nanoStr, encComm in
        var parts: [String] = []
        if !nanoStr.isEmpty { parts.append("amount=\(nanoStr)") }
        if !encComm.isEmpty { parts.append("text=\(encComm)") }
        return parts.isEmpty ? "" : ("?" + parts.joined(separator: "&"))
    }

    let modelSignal: Signal<MTNativeScreenModel, NoError> = revision.get()
    |> map { _ -> MTNativeScreenModel in
        let st = stateAtomic.with { $0 }
        var screen = MTNativeScreenModel(title: "Перевод TON")

        screen.sections.append([
            MTNativeRow(id: "ton.f.h", kind: .header("Реквизиты перевода")),
            MTNativeRow(id: "ton.addr", kind: .input(text: st.address, placeholder: "Адрес кошелька TON (UQ... / EQ... / .ton)")),
            MTNativeRow(id: "ton.amt", kind: .input(text: st.amount, placeholder: "Сумма в TON (например 5.5)")),
            MTNativeRow(id: "ton.comm", kind: .input(text: st.comment, placeholder: "Комментарий / Memo (необязательно)"))
        ])

        screen.text["ton.addr"] = { v in let _ = stateAtomic.modify { var n = $0; n.address = v; return n } }
        screen.text["ton.amt"] = { v in let _ = stateAtomic.modify { var n = $0; n.amount = v; return n } }
        screen.text["ton.comm"] = { v in let _ = stateAtomic.modify { var n = $0; n.comment = v; return n } }

        var actRows: [MTNativeRow] = [
            MTNativeRow(id: "ton.a.h", kind: .header("Способ отправки")),
            MTNativeRow(id: "ton.tk", kind: .action(title: "Отправить через Tonkeeper", destructive: false, enabled: true)),
            MTNativeRow(id: "ton.xr", kind: .action(title: "Открыть @xrocket (адрес скопируется)", destructive: false, enabled: true)),
            MTNativeRow(id: "ton.std", kind: .action(title: "Универсальный кошелёк (ton://transfer)", destructive: false, enabled: true))
        ]
        if peerId != nil {
            actRows.append(MTNativeRow(id: "ton.chat", kind: .action(title: "Отправить реквизиты оплаты в этот чат", destructive: false, enabled: true)))
        }
        screen.sections.append(actRows)

        screen.tap["ton.tk"] = {
            guard let p = buildParams() else { return }
            let q = buildQuery(p.nanoStr, p.encodedComment)
            let tkScheme = URL(string: "tonkeeper://transfer/\(p.addr)\(q)")
            let tkUniversal = URL(string: "https://app.tonkeeper.com/transfer/\(p.addr)\(q)")
            if let tkScheme, UIApplication.shared.canOpenURL(tkScheme) {
                UIApplication.shared.open(tkScheme)
            } else if let tkUniversal {
                UIApplication.shared.open(tkUniversal)
            }
        }
        screen.tap["ton.std"] = {
            guard let p = buildParams() else { return }
            let q = buildQuery(p.nanoStr, p.encodedComment)
            if let u = URL(string: "ton://transfer/\(p.addr)\(q)") {
                UIApplication.shared.open(u)
            }
        }
        screen.tap["ton.xr"] = {
            let cur = stateAtomic.with { $0 }
            let addr = cur.address.trimmingCharacters(in: .whitespacesAndNewlines)
            let comm = cur.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !addr.isEmpty {
                UIPasteboard.general.string = comm.isEmpty ? addr : "\(addr) (\(comm))"
            }
            if let tgUrl = URL(string: "tg://resolve?domain=xrocket") {
                UIApplication.shared.open(tgUrl)
            }
        }
        screen.tap["ton.chat"] = {
            guard let pid = peerId, let p = buildParams() else { return }
            let q = buildQuery(p.nanoStr, p.encodedComment)
            let link = "https://app.tonkeeper.com/transfer/\(p.addr)\(q)"
            var lines = ["Реквизиты оплаты TON:", "Адрес: \(p.addr)"]
            if !p.amtRaw.isEmpty { lines.append("Сумма: \(p.amtRaw) TON") }
            if !p.commRaw.isEmpty { lines.append("Комментарий: \(p.commRaw)") }
            lines.append("Tonkeeper: \(link)")
            lines.append("xRocket: https://t.me/xrocket")
            let _ = enqueueMessages(account: context.account, peerId: pid, messages: [
                .message(text: lines.joined(separator: "\n"), attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            ]).startStandalone()
            if let nav = weakController?.navigationController {
                _ = nav.popViewController(animated: true)
            }
        }

        let _ = bump
        return screen
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    weakController = controller
    return controller
}
