import Foundation
import UIKit
import AVFoundation
import CoreLocation
import AudioToolbox
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

#if canImport(AppIntents)
import AppIntents
#endif

// ============================================================================
// MediaTok Wave 22 — Pro Round Video Studio, Action Button & App Intents,
//                    Stream Auto-Raise Hand, Geo Safe-Zone Vault, Pill Dock & TON Ticker:
//   #703/#705/#710/#712 / .procam — Pro Round Camera Studio (DualCam Front+Back PiP,
//                                   Cinematic Gyro Stabilization, Timelapse 2x/4x/8x, Ring Light + Manual WB/ISO)
//   #571 / .streamhand           — Auto-Raise Hand in Voice/Stream Chats + Haptic/Sound alert when unmuted
//   #755 / #758 / .actionbtn     — iPhone Action Button & Siri App Intents + mediatok:// URL router
//   #751–#754 / .island          — Floating Dynamic HUD Pill (TON Live Price, Peer Online Radar, Voice Timer)
//   #803 / .geovault             — Geo Safe-Zone Fence (auto-locks MediaTok curtain outside trusted radius)
//   #981 / .pilldock             — Floating Glass Pill Quick-Dock launcher
// ============================================================================

private final class MTWave22Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

public struct MTWave22Config: Codable, Equatable {
    public var autoStreamRaiseHand: Bool
    public var floatingPillDockEnabled: Bool
    public var tonLiveTickerEnabled: Bool
    public var geoFenceEnabled: Bool
    public var safeLatitude: Double
    public var safeLongitude: Double
    public var safeRadiusMeters: Double

    private enum CodingKeys: String, CodingKey {
        case autoStreamRaiseHand
        case floatingPillDockEnabled
        case tonLiveTickerEnabled
        case geoFenceEnabled
        case safeLatitude
        case safeLongitude
        case safeRadiusMeters
    }

    public static let `default` = MTWave22Config(
        autoStreamRaiseHand: false,
        floatingPillDockEnabled: false,
        tonLiveTickerEnabled: false,
        geoFenceEnabled: false,
        safeLatitude: 0,
        safeLongitude: 0,
        safeRadiusMeters: 350
    )
}

public enum MTMediaTokWave22Tools {
    private static let configKey = "mediatok.wave22.config.v1"

    private static let stateBox = MTWave22Box<(
        cachedConfig: MTWave22Config,
        lastContext: AccountContext?,
        groupCallDisp: MetaDisposable,
        groupStateDisp: MetaDisposable,
        wasCannotUnmute: Bool,
        didAutoRaiseForCurrentCall: Bool
    )>((.default, nil, MetaDisposable(), MetaDisposable(), false, false))

    private static var floatingDockWindow: UIVisualEffectView?
    private static var floatingHudBanner: UIVisualEffectView?
    private static var hudTimer: Foundation.Timer?
    private static var geoCoordinator: MTGeoFenceCoordinator?

    // MARK: - Registration

    public static func register() {
        let initial = loadConfigFromDisk()
        stateBox.withLock { $0.cachedConfig = initial }

        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave22Tools.interceptCommands(request)
        }, order: 44)

        MTLifecycleHooks.openURL.register({ url, context, _ in
            return MTMediaTokWave22Tools.handleDeepLink(url: url, context: context)
        }, order: 120)

        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTMediaTokWave22Tools.stateBox.withLock { $0.lastContext = context }
            MTMediaTokWave22Tools.setupGroupCallHandMonitor(context: context)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MTMediaTokWave22Tools.refreshFloatingOverlays()
                MTMediaTokWave22Tools.refreshGeoFence()
            }
        }, order: 45)
    }

    // MARK: - Persistence

    private static func loadConfigFromDisk() -> MTWave22Config {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let decoded = try? JSONDecoder().decode(MTWave22Config.self, from: data) else {
            return .default
        }
        return decoded
    }

    public static func loadConfig() -> MTWave22Config {
        return stateBox.withLock { $0.cachedConfig }
    }

    public static func saveConfig(_ cfg: MTWave22Config) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        stateBox.withLock { $0.cachedConfig = cfg }
        DispatchQueue.main.async {
            refreshFloatingOverlays()
            refreshGeoFence()
        }
    }

    private static func keyWindow() -> UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return nil
        }
        return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
    }

    private static func topViewController() -> UIViewController? {
        guard let root = keyWindow()?.rootViewController else { return nil }
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
        let peerId = request.chatLocation.peerId

        if lower == ".procam" || lower == ".dualcam" || lower == ".timelapse" || lower == ".ringlight" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async {
                presentProRoundCameraStudio(context: request.context, peerId: peerId ?? request.context.account.peerId)
            }
            return true
        }
        if lower == ".wave22" || lower == ".island" || lower == ".pilldock" || lower == ".geovault" || lower == ".streamhand" || lower == ".actionbtn" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentWave22Hub(context: request.context) }
            return true
        }
        return false
    }

    // MARK: - #755 / #758 Deep-Link Router for iPhone Action Button & Siri Shortcuts

    private static func handleDeepLink(url: URL, context: AccountContext) -> Bool {
        guard let scheme = url.scheme?.lowercased(), (scheme == "mediatok" || scheme == "mt") else {
            return false
        }
        let host = (url.host ?? "").lowercased()
        switch host {
        case "procam":
            presentProRoundCameraStudio(context: context, peerId: context.account.peerId)
            return true
        case "spotlight":
            MTMediaTokWave7Tools.presentSpotlightPalette(accountContext: context, menuContext: nil)
            return true
        case "panic", "lock":
            MTMediaTokWave19Tools.engageEmergencyLockCurtain(reason: "Активировано кнопкой Action Button / Командой (#755)")
            return true
        case "shazam":
            MTMediaTokWave18Tools.presentShazamRecognizer(context: context)
            return true
        case "music":
            MTMediaTokWave21Tools.presentOfflineMusicHub(context: context)
            return true
        default:
            return false
        }
    }

    // MARK: - #571 Auto-Raise Hand in Streams & Unmute Alert

    private static func setupGroupCallHandMonitor(context: AccountContext) {
        guard let callManager = context.sharedContext.callManager else { return }
        let groupDisp = stateBox.withLock { $0.groupCallDisp }
        let stateDisp = stateBox.withLock { $0.groupStateDisp }

        groupDisp.set((callManager.currentGroupCallSignal
        |> deliverOnMainQueue).start(next: { videoChatCall in
            stateBox.withLock {
                $0.wasCannotUnmute = false
                $0.didAutoRaiseForCurrentCall = false
            }
            guard let videoChatCall, case let .group(groupCall) = videoChatCall else {
                stateDisp.set(nil)
                return
            }
            stateDisp.set((groupCall.state
            |> deliverOnMainQueue).start(next: { callState in
                guard loadConfig().autoStreamRaiseHand else { return }
                if let mute = callState.muteState {
                    if !mute.canUnmute {
                        let shouldRaise = stateBox.withLock { st -> Bool in
                            st.wasCannotUnmute = true
                            if !st.didAutoRaiseForCurrentCall && !callState.raisedHand {
                                st.didAutoRaiseForCurrentCall = true
                                return true
                            }
                            return false
                        }
                        if shouldRaise {
                            groupCall.raiseHand()
                            MTMediaTokWave5Tools.showToast(context: context, text: "Рука поднята автоматически (#571)")
                        }
                    } else {
                        let justGranted = stateBox.withLock { st -> Bool in
                            if st.wasCannotUnmute {
                                st.wasCannotUnmute = false
                                return true
                            }
                            return false
                        }
                        if justGranted {
                            AudioServicesPlaySystemSound(1520)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            MTMediaTokWave5Tools.showToast(context: context, text: "Вам дали слово в эфире! Микрофон доступен (#571)")
                        }
                    }
                }
            }))
        }))
    }

    // MARK: - #981 Floating Glass Pill Dock & #754 Live TON Ticker HUD

    public static func refreshFloatingOverlays() {
        guard let win = keyWindow() else { return }
        let cfg = loadConfig()

        // 1. #981 Floating Pill Quick-Dock
        if cfg.floatingPillDockEnabled {
            if floatingDockWindow == nil {
                let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
                pill.layer.cornerRadius = 22
                pill.clipsToBounds = true
                pill.layer.borderWidth = 0.8
                pill.layer.borderColor = UIColor(white: 1.0, alpha: 0.22).cgColor
                let w: CGFloat = 196
                let h: CGFloat = 44
                pill.frame = CGRect(x: (win.bounds.width - w) * 0.5, y: win.bounds.height - 142, width: w, height: h)
                pill.autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin, .flexibleRightMargin]

                let stack = UIStackView()
                stack.axis = .horizontal
                stack.distribution = .fillEqually
                stack.frame = pill.bounds.insetBy(dx: 8, dy: 4)
                stack.autoresizingMask = [.flexibleWidth, .flexibleHeight]

                let actions: [(String, () -> Void)] = [
                    ("sparkle.magnifyingglass", {
                        if let ctx = stateBox.withLock({ $0.lastContext }) {
                            MTMediaTokWave7Tools.presentSpotlightPalette(accountContext: ctx, menuContext: nil)
                        }
                    }),
                    ("camera.aperture", {
                        if let ctx = stateBox.withLock({ $0.lastContext }) {
                            presentProRoundCameraStudio(context: ctx, peerId: ctx.account.peerId)
                        }
                    }),
                    ("music.note", {
                        if let ctx = stateBox.withLock({ $0.lastContext }) {
                            MTMediaTokWave21Tools.presentOfflineMusicHub(context: ctx)
                        }
                    }),
                    ("lock.shield.fill", {
                        MTMediaTokWave19Tools.engageEmergencyLockCurtain(reason: "Ручная блокировка с плавающего дока (#981)")
                    })
                ]

                for (sym, handler) in actions {
                    let btn = UIButton(type: .system, primaryAction: UIAction { _ in handler() })
                    btn.setImage(UIImage(systemName: sym), for: .normal)
                    btn.tintColor = .white
                    stack.addArrangedSubview(btn)
                }

                let pan = UIPanGestureRecognizer(target: MTPillDragHelper.shared, action: #selector(MTPillDragHelper.handlePan(_:)))
                pill.addGestureRecognizer(pan)

                pill.contentView.addSubview(stack)
                win.addSubview(pill)
                floatingDockWindow = pill
            }
        } else {
            floatingDockWindow?.removeFromSuperview()
            floatingDockWindow = nil
        }

        // 2. #751–#754 Compact Dynamic Island / Top HUD Live Ticker (TON/USD + Active Tasks)
        if cfg.tonLiveTickerEnabled {
            if floatingHudBanner == nil {
                let hud = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
                hud.layer.cornerRadius = 13
                hud.clipsToBounds = true
                hud.isUserInteractionEnabled = false
                let hw: CGFloat = 154
                let hh: CGFloat = 26
                hud.frame = CGRect(x: win.bounds.width - hw - 14, y: max(54, win.safeAreaInsets.top + 4), width: hw, height: hh)
                hud.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]

                let lbl = UILabel(frame: hud.bounds.insetBy(dx: 8, dy: 2))
                lbl.tag = 754
                lbl.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .bold)
                lbl.textColor = .systemCyan
                lbl.textAlignment = .center
                lbl.text = "TON · загрузка..."
                hud.contentView.addSubview(lbl)
                win.addSubview(hud)
                floatingHudBanner = hud

                fetchTonTickerPrice()
                hudTimer?.invalidate()
                hudTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { _ in
                    fetchTonTickerPrice()
                }
            }
        } else {
            hudTimer?.invalidate()
            hudTimer = nil
            floatingHudBanner?.removeFromSuperview()
            floatingHudBanner = nil
        }
    }

    private static func fetchTonTickerPrice() {
        guard let url = URL(string: "https://tonapi.io/v2/rates?tokens=ton&currencies=usd,rub") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let rates = root["rates"] as? [String: Any],
                  let ton = rates["TON"] as? [String: Any],
                  let prices = ton["prices"] as? [String: Any],
                  let usd = prices["USD"] as? Double else { return }
            let rub = (prices["RUB"] as? Double) ?? 0
            DispatchQueue.main.async {
                if let lbl = floatingHudBanner?.contentView.viewWithTag(754) as? UILabel {
                    lbl.text = rub > 0 ? String(format: "TON $%.2f · %.0f₽", usd, rub) : String(format: "TON $%.2f", usd)
                }
            }
        }.resume()
    }

    // MARK: - #803 Geo Safe-Zone Vault

    public static func refreshGeoFence() {
        let cfg = loadConfig()
        if cfg.geoFenceEnabled && (cfg.safeLatitude != 0 || cfg.safeLongitude != 0) {
            if geoCoordinator == nil {
                geoCoordinator = MTGeoFenceCoordinator()
            }
            geoCoordinator?.startMonitoring(lat: cfg.safeLatitude, lon: cfg.safeLongitude, radius: cfg.safeRadiusMeters)
        } else {
            geoCoordinator?.stop()
            geoCoordinator = nil
        }
    }

    // MARK: - Launchers

    public static func presentProRoundCameraStudio(context: AccountContext, peerId: PeerId) {
        guard let top = topViewController() else { return }
        let vc = MTProRoundCameraController(context: context, peerId: peerId)
        vc.modalPresentationStyle = .fullScreen
        top.present(vc, animated: true)
    }

    public static func presentWave22Hub(context: AccountContext) {
        guard let top = topViewController() else { return }
        let vc = MTWave22HubController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }
}

private final class MTPillDragHelper: NSObject {
    static let shared = MTPillDragHelper()
    @objc func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let v = gr.view, let sup = v.superview else { return }
        let delta = gr.translation(in: sup)
        v.center = CGPoint(
            x: max(v.bounds.width * 0.5 + 8, min(sup.bounds.width - v.bounds.width * 0.5 - 8, v.center.x + delta.x)),
            y: max(90, min(sup.bounds.height - 60, v.center.y + delta.y))
        )
        gr.setTranslation(.zero, in: sup)
    }
}

// MARK: - #803 CLLocationManager Safe-Zone Watcher

private final class MTGeoFenceCoordinator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var centerCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private var radiusMeters: Double = 350
    private var pendingOneShotAfterAuth: Bool = false
    private var lastLockTriggerTime: TimeInterval = 0

    override init() {
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func startMonitoring(lat: Double, lon: Double, radius: Double) {
        self.centerCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        self.radiusMeters = max(100, radius)
        if self.manager.authorizationStatus == .notDetermined {
            self.manager.requestWhenInUseAuthorization()
        } else {
            self.manager.startUpdatingLocation()
        }
    }

    func stop() {
        self.manager.stopUpdatingLocation()
    }

    func captureCurrentLocationOnce(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.oneShotCompletion = completion
        if self.manager.authorizationStatus == .notDetermined {
            self.pendingOneShotAfterAuth = true
            self.manager.requestWhenInUseAuthorization()
        } else {
            self.manager.requestLocation()
        }
    }

    private var oneShotCompletion: ((CLLocationCoordinate2D?) -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if self.pendingOneShotAfterAuth {
                self.pendingOneShotAfterAuth = false
                manager.requestLocation()
            } else if MTMediaTokWave22Tools.loadConfig().geoFenceEnabled {
                manager.startUpdatingLocation()
            }
        } else if status == .denied || status == .restricted {
            self.pendingOneShotAfterAuth = false
            if let cb = self.oneShotCompletion {
                self.oneShotCompletion = nil
                cb(nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        if let cb = self.oneShotCompletion {
            self.oneShotCompletion = nil
            cb(loc.coordinate)
            return
        }
        guard loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 120.0 else { return }
        guard MTMediaTokWave22Tools.loadConfig().geoFenceEnabled else { return }
        let now = Date().timeIntervalSince1970
        if now - self.lastLockTriggerTime < 1800.0 { return }
        let safeLoc = CLLocation(latitude: self.centerCoord.latitude, longitude: self.centerCoord.longitude)
        let dist = loc.distance(from: safeLoc)
        if dist > self.radiusMeters {
            self.lastLockTriggerTime = now
            DispatchQueue.main.async {
                MTMediaTokWave19Tools.engageEmergencyLockCurtain(reason: "Выход за пределы доверенной Гео-зоны (#803: \(Int(dist)) м)")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let cb = self.oneShotCompletion {
            self.oneShotCompletion = nil
            cb(nil)
        }
    }
}

// MARK: - #703 / #705 / #710 / #712 Pro Round Video Studio (DualCam + Gyro Stabilization + Timelapse + Ring Light + Manual WB)

private final class MTProRoundCameraController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let context: AccountContext
    private let peerId: PeerId

    private let ringLightBorder = UIView()
    private let circleContainer = UIView()
    private let mainPreviewView = UIImageView()
    private let pipPreviewView = UIImageView()
    private let timerLabel = UILabel()

    private let speedSeg = UISegmentedControl(items: ["1×", "2× Таймлапс", "4×", "8×"])
    private let ringSwitch = UISwitch()
    private let dualCamSwitch = UISwitch()
    private let exposureSlider = UISlider()
    private let recordBtn = UIButton(type: .system)

    private var singleSession: AVCaptureSession?
    private var multiSession: AVCaptureMultiCamSession?
    private var mainDevice: AVCaptureDevice?
    private var mainVideoOutput: AVCaptureVideoDataOutput?
    private var pipVideoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?

    private let sessionQueue = DispatchQueue(label: "mediatok.wave22.procam.queue")
    private let ciContext = CIContext()

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var outputUrl: URL?

    private let recLock = NSLock()
    private var isRecording = false
    private var frameCounter: Int = 0
    private var timelapseFactor: Int = 1
    private var startPts: CMTime?
    private var latestPipImage: CIImage?
    private var prevScreenBrightness: CGFloat = UIScreen.main.brightness
    private var uiTimer: Foundation.Timer?
    private var recSeconds: Int = 0

    init(context: AccountContext, peerId: PeerId) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black

        // #712 Soft White Screen Ring Light Frame
        self.ringLightBorder.layer.borderColor = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 0.96).cgColor
        self.ringLightBorder.layer.borderWidth = 0
        self.ringLightBorder.layer.cornerRadius = 38
        self.ringLightBorder.isUserInteractionEnabled = false
        self.ringLightBorder.frame = self.view.bounds.insetBy(dx: 6, dy: 6)
        self.ringLightBorder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(self.ringLightBorder)

        let closeBtn = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in
            self?.closeStudio()
        })
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(closeBtn)

        let circleSide: CGFloat = 296
        self.circleContainer.layer.cornerRadius = circleSide * 0.5
        self.circleContainer.clipsToBounds = true
        self.circleContainer.layer.borderWidth = 3
        self.circleContainer.layer.borderColor = UIColor.systemCyan.cgColor
        self.circleContainer.translatesAutoresizingMaskIntoConstraints = false

        self.mainPreviewView.contentMode = .scaleAspectFill
        self.mainPreviewView.frame = CGRect(x: 0, y: 0, width: circleSide, height: circleSide)
        self.circleContainer.addSubview(self.mainPreviewView)

        // #703 DualCam PiP bubble inside the round video
        self.pipPreviewView.contentMode = .scaleAspectFill
        self.pipPreviewView.layer.cornerRadius = 42
        self.pipPreviewView.clipsToBounds = true
        self.pipPreviewView.layer.borderWidth = 2
        self.pipPreviewView.layer.borderColor = UIColor.white.cgColor
        self.pipPreviewView.frame = CGRect(x: circleSide - 98, y: circleSide - 98, width: 84, height: 84)
        self.pipPreviewView.isHidden = true
        self.circleContainer.addSubview(self.pipPreviewView)

        self.timerLabel.text = "Pro Кружок · 384×384 H.264"
        self.timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        self.timerLabel.textColor = .white
        self.timerLabel.textAlignment = .center

        self.speedSeg.selectedSegmentIndex = 0
        self.speedSeg.selectedSegmentTintColor = .systemCyan
        self.speedSeg.addTarget(self, action: #selector(speedChanged), for: .valueChanged)

        self.ringSwitch.addTarget(self, action: #selector(ringToggled), for: .valueChanged)
        self.dualCamSwitch.isEnabled = AVCaptureMultiCamSession.isMultiCamSupported
        self.dualCamSwitch.addTarget(self, action: #selector(dualCamToggled), for: .valueChanged)

        self.exposureSlider.minimumValue = -2.0
        self.exposureSlider.maximumValue = 2.0
        self.exposureSlider.value = 0.0
        self.exposureSlider.addTarget(self, action: #selector(exposureChanged), for: .valueChanged)

        var recCfg = UIButton.Configuration.filled()
        recCfg.baseBackgroundColor = .systemRed
        recCfg.title = "Начать запись кружка"
        recCfg.image = UIImage(systemName: "record.circle")
        recCfg.imagePadding = 8
        recCfg.cornerStyle = .capsule
        self.recordBtn.configuration = recCfg
        self.recordBtn.addTarget(self, action: #selector(toggleRecordTapped), for: .touchUpInside)

        let controlsStack = UIStackView(arrangedSubviews: [
            self.timerLabel,
            self.speedSeg,
            makeControlRow("Кольцевая вспышка экрана (#712)", self.ringSwitch),
            makeControlRow("DualCam Фронт + Тыл (#703)", self.dualCamSwitch),
            makeSliderRow("Экспозиция AE (#712)", self.exposureSlider),
            self.recordBtn
        ])
        controlsStack.axis = .vertical
        controlsStack.spacing = 11
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.circleContainer)
        self.view.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeBtn.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -18),
            closeBtn.widthAnchor.constraint(equalToConstant: 36),
            closeBtn.heightAnchor.constraint(equalToConstant: 36),
            self.circleContainer.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 24),
            self.circleContainer.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.circleContainer.widthAnchor.constraint(equalToConstant: circleSide),
            self.circleContainer.heightAnchor.constraint(equalToConstant: circleSide),
            self.recordBtn.heightAnchor.constraint(equalToConstant: 50),
            controlsStack.topAnchor.constraint(equalTo: self.circleContainer.bottomAnchor, constant: 18),
            controlsStack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            controlsStack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20)
        ])

        self.reconfigureCaptureSession(enableDualCam: false)
    }

    private func makeControlRow(_ title: String, _ sw: UISwitch) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        let l = UILabel()
        l.text = title
        l.textColor = .white
        l.font = .systemFont(ofSize: 13, weight: .medium)
        row.addArrangedSubview(l)
        row.addArrangedSubview(sw)
        return row
    }

    private func makeSliderRow(_ title: String, _ sl: UISlider) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        let l = UILabel()
        l.text = title
        l.textColor = .lightGray
        l.font = .systemFont(ofSize: 12, weight: .medium)
        row.addArrangedSubview(l)
        row.addArrangedSubview(sl)
        return row
    }

    private func reconfigureCaptureSession(enableDualCam: Bool) {
        self.sessionQueue.async { [weak self] in
            guard let self else { return }
            self.singleSession?.stopRunning()
            self.multiSession?.stopRunning()
            self.singleSession = nil
            self.multiSession = nil

            if enableDualCam && AVCaptureMultiCamSession.isMultiCamSupported {
                let mSession = AVCaptureMultiCamSession()
                mSession.beginConfiguration()

                if let backCam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let backIn = try? AVCaptureDeviceInput(device: backCam),
                   mSession.canAddInput(backIn) {
                    mSession.addInputWithNoConnections(backIn)
                    self.mainDevice = backCam
                    let mainOut = AVCaptureVideoDataOutput()
                    mainOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    mainOut.setSampleBufferDelegate(self, queue: self.sessionQueue)
                    if mSession.canAddOutput(mainOut),
                       let port = backIn.ports(for: .video, sourceDeviceType: backCam.deviceType, sourceDevicePosition: .back).first {
                        mSession.addOutputWithNoConnections(mainOut)
                        let conn = AVCaptureConnection(inputPorts: [port], output: mainOut)
                        conn.videoOrientation = .portrait
                        if conn.isVideoStabilizationSupported {
                            conn.preferredVideoStabilizationMode = .cinematicExtended // #705 Gyro Stabilization
                        }
                        if mSession.canAddConnection(conn) { mSession.addConnection(conn) }
                        self.mainVideoOutput = mainOut
                    }
                }

                if let frontCam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                   let frontIn = try? AVCaptureDeviceInput(device: frontCam),
                   mSession.canAddInput(frontIn) {
                    mSession.addInputWithNoConnections(frontIn)
                    let pipOut = AVCaptureVideoDataOutput()
                    pipOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    pipOut.setSampleBufferDelegate(self, queue: self.sessionQueue)
                    if mSession.canAddOutput(pipOut),
                       let port = frontIn.ports(for: .video, sourceDeviceType: frontCam.deviceType, sourceDevicePosition: .front).first {
                        mSession.addOutputWithNoConnections(pipOut)
                        let conn = AVCaptureConnection(inputPorts: [port], output: pipOut)
                        conn.videoOrientation = .portrait
                        conn.isVideoMirrored = true
                        if mSession.canAddConnection(conn) { mSession.addConnection(conn) }
                        self.pipVideoOutput = pipOut
                    }
                }

                if let mic = AVCaptureDevice.default(for: .audio),
                   let micIn = try? AVCaptureDeviceInput(device: mic),
                   mSession.canAddInput(micIn) {
                    mSession.addInput(micIn)
                    let aOut = AVCaptureAudioDataOutput()
                    aOut.setSampleBufferDelegate(self, queue: self.sessionQueue)
                    if mSession.canAddOutput(aOut) {
                        mSession.addOutput(aOut)
                        self.audioOutput = aOut
                    }
                }

                mSession.commitConfiguration()
                mSession.startRunning()
                self.multiSession = mSession
            } else {
                let sSession = AVCaptureSession()
                sSession.sessionPreset = .hd1280x720
                sSession.beginConfiguration()

                if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ?? AVCaptureDevice.default(for: .video),
                   let vIn = try? AVCaptureDeviceInput(device: cam),
                   sSession.canAddInput(vIn) {
                    sSession.addInput(vIn)
                    self.mainDevice = cam
                    let vOut = AVCaptureVideoDataOutput()
                    vOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    vOut.setSampleBufferDelegate(self, queue: self.sessionQueue)
                    if sSession.canAddOutput(vOut) {
                        sSession.addOutput(vOut)
                        if let conn = vOut.connection(with: .video) {
                            conn.videoOrientation = .portrait
                            conn.isVideoMirrored = (cam.position == .front)
                            if conn.isVideoStabilizationSupported {
                                conn.preferredVideoStabilizationMode = .cinematicExtended // #705 Gyro Stabilization
                            }
                        }
                        self.mainVideoOutput = vOut
                    }
                }

                if let mic = AVCaptureDevice.default(for: .audio),
                   let micIn = try? AVCaptureDeviceInput(device: mic),
                   sSession.canAddInput(micIn) {
                    sSession.addInput(micIn)
                    let aOut = AVCaptureAudioDataOutput()
                    aOut.setSampleBufferDelegate(self, queue: self.sessionQueue)
                    if sSession.canAddOutput(aOut) {
                        sSession.addOutput(aOut)
                        self.audioOutput = aOut
                    }
                }

                sSession.commitConfiguration()
                sSession.startRunning()
                self.singleSession = sSession
            }
        }
    }

    @objc private func speedChanged() {
        let factors = [1, 2, 4, 8]
        self.timelapseFactor = factors[max(0, min(3, self.speedSeg.selectedSegmentIndex))]
    }

    @objc private func ringToggled() {
        if self.ringSwitch.isOn {
            self.prevScreenBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            self.ringLightBorder.layer.borderWidth = 22
        } else {
            UIScreen.main.brightness = self.prevScreenBrightness
            self.ringLightBorder.layer.borderWidth = 0
        }
    }

    @objc private func dualCamToggled() {
        self.pipPreviewView.isHidden = !self.dualCamSwitch.isOn
        self.reconfigureCaptureSession(enableDualCam: self.dualCamSwitch.isOn)
    }

    @objc private func exposureChanged() {
        let bias = self.exposureSlider.value
        self.sessionQueue.async { [weak self] in
            guard let dev = self?.mainDevice else { return }
            if (try? dev.lockForConfiguration()) != nil {
                let clamped = max(dev.minExposureTargetBias, min(dev.maxExposureTargetBias, bias))
                dev.setExposureTargetBias(clamped, completionHandler: nil)
                dev.unlockForConfiguration()
            }
        }
    }

    @objc private func toggleRecordTapped() {
        let currentlyRec = self.recLock.withLock { self.isRecording }
        if currentlyRec {
            self.stopAndSendRoundVideo()
        } else {
            self.startRecordingRoundVideo()
        }
    }

    private func startRecordingRoundVideo() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mt_pro_round_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }

        let vSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 384,
            AVVideoHeightKey: 384,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_400_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vIn.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vIn,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 384,
                kCVPixelBufferHeightKey as String: 384
            ]
        )
        if writer.canAdd(vIn) { writer.add(vIn) }

        var aIn: AVAssetWriterInput?
        if self.timelapseFactor == 1 {
            let aSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                aIn = input
            }
        }

        self.recLock.lock()
        self.outputUrl = url
        self.assetWriter = writer
        self.videoInput = vIn
        self.pixelAdaptor = adaptor
        self.audioInput = aIn
        self.frameCounter = 0
        self.startPts = nil
        self.isRecording = true
        self.recLock.unlock()

        self.recSeconds = 0
        var cfg = self.recordBtn.configuration ?? UIButton.Configuration.filled()
        cfg.title = "Остановить и отправить кружок"
        cfg.baseBackgroundColor = .systemOrange
        self.recordBtn.configuration = cfg
        self.speedSeg.isEnabled = false
        self.dualCamSwitch.isEnabled = false

        self.uiTimer?.invalidate()
        self.uiTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recSeconds += 1
            self.timerLabel.text = String(format: "REC %02d:%02d · %d×", self.recSeconds / 60, self.recSeconds % 60, self.timelapseFactor)
            if self.recSeconds >= 59 {
                self.stopAndSendRoundVideo()
            }
        }
    }

    private func stopAndSendRoundVideo() {
        self.uiTimer?.invalidate()
        self.uiTimer = nil

        self.recLock.lock()
        guard self.isRecording, let writer = self.assetWriter, let outUrl = self.outputUrl else {
            self.recLock.unlock()
            return
        }
        self.isRecording = false
        let vIn = self.videoInput
        let aIn = self.audioInput
        self.recLock.unlock()

        self.recordBtn.isEnabled = false
        self.timerLabel.text = "Финализация кружка..."

        self.sessionQueue.async { [weak self] in
            guard writer.status == .writing else {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: outUrl)
                DispatchQueue.main.async {
                    self?.closeStudio()
                }
                return
            }
            vIn?.markAsFinished()
            aIn?.markAsFinished()
            writer.finishWriting {
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let mp4Data = try? Data(contentsOf: outUrl), !mp4Data.isEmpty {
                        let res = LocalFileMediaResource(fileId: Int64.random(in: 1 ... Int64.max))
                        self.context.account.postbox.mediaBox.storeResourceData(res.id, data: mp4Data, synchronous: true)
                        let outDur = max(1, self.recSeconds / max(1, self.timelapseFactor))
                        let media = TelegramMediaFile(
                            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: 1 ... Int64.max)),
                            partialReference: nil,
                            resource: res,
                            previewRepresentations: [],
                            videoThumbnails: [],
                            immediateThumbnailData: nil,
                            mimeType: "video/mp4",
                            size: Int64(mp4Data.count),
                            attributes: [
                                .Video(duration: Double(outDur), size: PixelDimensions(width: 384, height: 384), flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: "avc1")
                            ],
                            alternativeRepresentations: []
                        )
                        let _ = enqueueMessages(account: self.context.account, peerId: self.peerId, messages: [
                            .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        ]).startStandalone()
                        MTMediaTokWave5Tools.showToast(context: self.context, text: "Pro-кружок отправлен!")
                    }
                    try? FileManager.default.removeItem(at: outUrl)
                    self.closeStudio()
                }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === self.pipVideoOutput {
            if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let ci = CIImage(cvPixelBuffer: pb)
                self.recLock.withLock { self.latestPipImage = ci }
                if let cg = self.ciContext.createCGImage(ci, from: ci.extent) {
                    let ui = UIImage(cgImage: cg)
                    DispatchQueue.main.async { [weak self] in
                        self?.pipPreviewView.image = ui
                    }
                }
            }
            return
        }

        if output === self.audioOutput {
            self.recLock.lock()
            let rec = self.isRecording
            let factor = self.timelapseFactor
            let writer = self.assetWriter
            let aIn = self.audioInput
            let started = (self.startPts != nil)
            self.recLock.unlock()

            if rec && factor == 1 && started, writer?.status == .writing, let aIn, aIn.isReadyForMoreMediaData {
                let _ = aIn.append(sampleBuffer)
            }
            return
        }

        guard output === self.mainVideoOutput, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let mainCi = CIImage(cvPixelBuffer: pb)
        let ext = mainCi.extent
        let side = min(ext.width, ext.height)
        let cropRect = CGRect(x: (ext.width - side) * 0.5, y: (ext.height - side) * 0.5, width: side, height: side)
        var squareCi = mainCi.cropped(to: cropRect).transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        let scale = 384.0 / max(1.0, side)
        squareCi = squareCi.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Composite DualCam PiP in bottom-right corner if active
        if let pip = self.recLock.withLock({ self.latestPipImage }), self.multiSession != nil {
            let pExt = pip.extent
            let pSide = min(pExt.width, pExt.height)
            let pCrop = CGRect(x: (pExt.width - pSide) * 0.5, y: (pExt.height - pSide) * 0.5, width: pSide, height: pSide)
            let pScale = 104.0 / max(1.0, pSide)
            let pipScaled = pip.cropped(to: pCrop)
                .transformed(by: CGAffineTransform(translationX: -pCrop.origin.x, y: -pCrop.origin.y))
                .transformed(by: CGAffineTransform(scaleX: pScale, y: pScale))
                .transformed(by: CGAffineTransform(translationX: 256, y: 24))
            squareCi = pipScaled.composited(over: squareCi)
        }

        let targetRect = CGRect(x: 0, y: 0, width: 384, height: 384)
        if let cg = self.ciContext.createCGImage(squareCi, from: targetRect) {
            let ui = UIImage(cgImage: cg)
            DispatchQueue.main.async { [weak self] in
                self?.mainPreviewView.image = ui
            }
        }

        // Append frame to MP4 writer with #710 Timelapse PTS scaling
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        self.recLock.lock()
        guard self.isRecording, let writer = self.assetWriter, let vIn = self.videoInput, let adaptor = self.pixelAdaptor else {
            self.recLock.unlock()
            return
        }
        let idx = self.frameCounter
        self.frameCounter += 1
        let factor = max(1, self.timelapseFactor)
        if idx % factor != 0 {
            self.recLock.unlock()
            return
        }
        if self.startPts == nil {
            self.startPts = pts
            writer.startWriting()
            writer.startSession(atSourceTime: factor == 1 ? pts : .zero)
        }
        let basePts = self.startPts ?? pts
        self.recLock.unlock()

        guard writer.status == .writing, vIn.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }
        var outPb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outPb)
        if let outPb {
            self.ciContext.render(squareCi, to: outPb, bounds: targetRect, colorSpace: CGColorSpaceCreateDeviceRGB())
            let appendPts: CMTime
            if factor > 1 {
                let elapsed = CMTimeSubtract(pts, basePts)
                appendPts = CMTimeMultiplyByRatio(elapsed, multiplier: 1, divisor: Int32(factor))
            } else {
                appendPts = pts
            }
            let _ = adaptor.append(outPb, withPresentationTime: appendPts)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.uiTimer?.invalidate()
        self.uiTimer = nil
        if self.ringSwitch.isOn {
            UIScreen.main.brightness = self.prevScreenBrightness
        }
        self.sessionQueue.async { [weak self] in
            self?.singleSession?.stopRunning()
            self?.multiSession?.stopRunning()
        }
    }

    private func closeStudio() {
        self.uiTimer?.invalidate()
        self.uiTimer = nil
        if self.ringSwitch.isOn {
            UIScreen.main.brightness = self.prevScreenBrightness
        }
        self.sessionQueue.async { [weak self] in
            self?.singleSession?.stopRunning()
            self?.multiSession?.stopRunning()
        }
        self.dismiss(animated: true)
    }
}

// MARK: - Wave 22 Hub Controller

private final class MTWave22HubController: UIViewController {
    private let context: AccountContext
    private var config = MTMediaTokWave22Tools.loadConfig()
    private let geoHelper = MTGeoFenceCoordinator()

    private let streamHandSwitch = UISwitch()
    private let pillDockSwitch = UISwitch()
    private let tonHudSwitch = UISwitch()
    private let geoFenceSwitch = UISwitch()
    private let geoStatusLabel = UILabel()

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Камера, Эфиры и Экосистема iOS"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(saveTapped))

        self.streamHandSwitch.isOn = self.config.autoStreamRaiseHand
        self.pillDockSwitch.isOn = self.config.floatingPillDockEnabled
        self.tonHudSwitch.isOn = self.config.tonLiveTickerEnabled
        self.geoFenceSwitch.isOn = self.config.geoFenceEnabled

        var camCfg = UIButton.Configuration.filled()
        camCfg.title = "Открыть Pro-студию кружков (.procam #703/#710/#712)"
        camCfg.image = UIImage(systemName: "camera.aperture")
        camCfg.imagePadding = 8
        camCfg.cornerStyle = .large
        let camBtn = UIButton(configuration: camCfg, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let ctx = self.context
            self.dismiss(animated: true) {
                MTMediaTokWave22Tools.presentProRoundCameraStudio(context: ctx, peerId: ctx.account.peerId)
            }
        })

        var geoBtnCfg = UIButton.Configuration.tinted()
        geoBtnCfg.title = "Запомнить текущую точку как Доверенную зону (#803)"
        geoBtnCfg.image = UIImage(systemName: "location.fill.viewfinder")
        geoBtnCfg.imagePadding = 8
        geoBtnCfg.cornerStyle = .large
        let geoBtn = UIButton(configuration: geoBtnCfg, primaryAction: UIAction { [weak self] _ in
            self?.captureCurrentSafeZone()
        })

        var actionBtnCfg = UIButton.Configuration.tinted()
        actionBtnCfg.title = "Скопировать ссылки для Action Button / Команд (#755/#758)"
        actionBtnCfg.image = UIImage(systemName: "button.programmable")
        actionBtnCfg.imagePadding = 8
        actionBtnCfg.cornerStyle = .large
        let actionCopyBtn = UIButton(configuration: actionBtnCfg, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = "mediatok://procam\nmediatok://spotlight\nmediatok://panic\nmediatok://shazam\nmediatok://music"
            MTMediaTokWave5Tools.showToast(context: self.context, text: "URL-схемы для приложения «Команды» / Action Button скопированы!")
        })

        self.geoStatusLabel.font = .systemFont(ofSize: 12)
        self.geoStatusLabel.textColor = .secondaryLabel
        self.geoStatusLabel.numberOfLines = 0
        self.updateGeoLabel()

        let stack = UIStackView(arrangedSubviews: [
            camBtn,
            makeRow("Авто-поднятие руки в стримах + вибро при размуте (#571)", self.streamHandSwitch),
            makeRow("Плавающий стеклянный док быстрого доступа (#981)", self.pillDockSwitch),
            makeRow("Живой курс TON/USD/₽ в верхней пилюле (#754)", self.tonHudSwitch),
            makeRow("Гео-сейф: авто-блокировка вне дома/офиса (#803)", self.geoFenceSwitch),
            geoBtn,
            self.geoStatusLabel,
            actionCopyBtn
        ])
        stack.axis = .vertical
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            camBtn.heightAnchor.constraint(equalToConstant: 48),
            geoBtn.heightAnchor.constraint(equalToConstant: 44),
            actionCopyBtn.heightAnchor.constraint(equalToConstant: 44),
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16)
        ])
    }

    private func makeRow(_ title: String, _ sw: UISwitch) -> UIView {
        let r = UIStackView()
        r.axis = .horizontal
        r.alignment = .center
        r.spacing = 8
        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 13.5)
        l.numberOfLines = 0
        r.addArrangedSubview(l)
        r.addArrangedSubview(sw)
        return r
    }

    private func updateGeoLabel() {
        if self.config.safeLatitude == 0 && self.config.safeLongitude == 0 {
            self.geoStatusLabel.text = "Доверенная точка ещё не задана (радиус охраны: 350 м)."
        } else {
            self.geoStatusLabel.text = String(format: "Доверенная зона: %.4f, %.4f (радиус %.0f м)", self.config.safeLatitude, self.config.safeLongitude, self.config.safeRadiusMeters)
        }
    }

    private func captureCurrentSafeZone() {
        self.geoStatusLabel.text = "Определяю GPS-координаты..."
        self.geoHelper.captureCurrentLocationOnce { [weak self] coord in
            DispatchQueue.main.async {
                guard let self else { return }
                if let coord {
                    self.config.safeLatitude = coord.latitude
                    self.config.safeLongitude = coord.longitude
                    self.updateGeoLabel()
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "Координаты доверенной зоны сохранены!")
                } else {
                    self.geoStatusLabel.text = "Не удалось получить геолокацию (проверьте доступ в Настройках iOS)."
                }
            }
        }
    }

    @objc private func saveTapped() {
        self.config.autoStreamRaiseHand = self.streamHandSwitch.isOn
        self.config.floatingPillDockEnabled = self.pillDockSwitch.isOn
        self.config.tonLiveTickerEnabled = self.tonHudSwitch.isOn
        self.config.geoFenceEnabled = self.geoFenceSwitch.isOn
        MTMediaTokWave22Tools.saveConfig(self.config)
        MTMediaTokWave5Tools.showToast(context: self.context, text: "Настройки Wave 22 применены!")
        self.dismiss(animated: true)
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }
}

// MARK: - #758 Native iOS 16+ App Intents (Siri & Action Button Shortcuts)

#if canImport(AppIntents)
@available(iOS 16.0, *)
struct MTOpenProRoundCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "MediaTok: Записать Pro-кружок"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "mediatok://procam") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct MTEmergencyLockIntent: AppIntent {
    static let title: LocalizedStringResource = "MediaTok: Экстренная блокировка"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        MTMediaTokWave19Tools.engageEmergencyLockCurtain(reason: "Запущено через команду App Intent / Action Button (#755)")
        return .result()
    }
}

@available(iOS 16.0, *)
struct MTOpenSpotlightIntent: AppIntent {
    static let title: LocalizedStringResource = "MediaTok: Открыть командный центр"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "mediatok://spotlight") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}
#endif
