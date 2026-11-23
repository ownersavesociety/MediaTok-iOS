import Foundation
import UIKit
import AVFoundation
import CryptoKit
import ImageIO
import Security
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
import OpusBinding
import UIKitRuntimeUtils
import Darwin

private final class MTWave12LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

// ============================================================================
// MediaTok Wave 12 — 5 Killer Signature Features:
//   #501 — Stealth Photo Steganography (LSB PNG secret text inside normal photo) (.stego)
//   #502 — Real-Time Voice FX Studio (AVAudioEngine pitch/reverb/radio/demon -> .ogg / .m4a) (.vfx)
//   #503 — Burn-After-Reading AES-256-GCM Secret Note with PIN & TTL (.burn)
//   #504 — Cinematic Quote Card Studio (Ray.so / Keynote 1:1, 9:16, 16:9 HD PNG) (.cinematic)
//   #505 — OSINT X-Ray (EXIF/GPS/Camera/AI detector + Link Redirect & Phishing scanner) (.xray)
// ============================================================================

public enum MTMediaTokWave12Tools {
    private static let burnedNotesKey = "mediatok.burn.opened_hashes.v1"
    private static let burnPinAttemptsKey = "mediatok.burn.pin_attempts.v1"
    private static let maxBurnPinAttempts = 5

    public static func register() {
        MTChatScreenHooks.willSendText.register({ request, _ in
            return MTMediaTokWave12Tools.interceptCommands(request)
        }, order: 34)

        MTMessageMenuHooks.items.register({ menuContext in
            return MTMediaTokWave12Tools.messageMenuItems(menuContext)
        }, order: 94)
    }

    private static func interceptCommands(_ request: MTComposedTextRequest) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(".") else { return false }
        let lower = raw.lowercased()
        let peerId = request.chatLocation.peerId

        if lower == ".stego" || lower == ".secretphoto" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentStegoStudio(context: request.context, initialImage: nil, peerId: peerId) }
            return true
        }
        if lower == ".vfx" || lower == ".voicefx" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentVoiceFxStudio(context: request.context, peerId: peerId) }
            return true
        }
        if lower == ".burn" || lower == ".bomb" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentBurnNoteComposer(context: request.context, peerId: peerId) }
            return true
        }
        if lower == ".cinematic" || lower == ".card" {
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentCinematicCard(context: request.context, initialText: nil, author: nil, peerId: peerId) }
            return true
        }
        if lower == ".xray" || lower == ".osint" || lower.hasPrefix(".xray ") || lower.hasPrefix(".osint ") {
            let arg: String
            if lower.hasPrefix(".xray ") {
                arg = String(raw.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lower.hasPrefix(".osint ") {
                arg = String(raw.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                arg = ""
            }
            request.replace(ChatTextInputState())
            DispatchQueue.main.async { presentOsintXRay(context: request.context, initialUrl: arg.isEmpty ? nil : arg, initialImageData: nil) }
            return true
        }
        return false
    }

    private static func messageMenuItems(_ menuContext: MTMessageMenuContext) -> [MTMessageMenuEntry] {
        guard let message = menuContext.messages.first else { return [] }
        let context = menuContext.context
        var entries: [MTMessageMenuEntry] = []
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // #503 Burn-after-reading card detector
        if let range = text.range(of: #"\[MT:BURN2?:[A-Za-z0-9+/=_-]+\]"#, options: .regularExpression) {
            let token = String(text[range])
            entries.append(MTMessageMenuEntry(position: .top, item: .action(ContextMenuActionItem(
                text: "Открыть сгорающую записку (PIN)",
                icon: { theme in
                    UIImage(systemName: "flame.fill")?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
                        ?? UIImage(systemName: "lock.fill")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    MTMediaTokWave12Tools.presentBurnNoteDecryptor(context: context, token: token)
                }
            ))))
        }

        // Steganography decoder only on uncompressed PNG documents (never cluttering compressed photos)
        if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile,
           (file.mimeType.lowercased() == "image/png" || (file.fileName?.lowercased().hasSuffix(".png") ?? false)),
           !file.isSticker {
            let res = file.resource
            entries.append(MTMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(
                text: "Извлечь стего-секрет из PNG",
                icon: { theme in
                    UIImage(systemName: "eye.slash")?.withTintColor(theme.contextMenu.primaryColor, renderingMode: .alwaysOriginal)
                },
                action: { _, f in
                    f(.default)
                    inspectImageFileResource(context: context, message: message, file: file, resource: res)
                }
            ))))
        }

        return entries
    }

    private static func inspectImageFileResource(context: AccountContext, message: Message, file: TelegramMediaFile, resource: MediaResource) {
        MTMediaTokWave5Tools.showToast(context: context, text: "🕵️‍♂️ Анализирую пиксели и метаданные...")
        let fetchDisp = fetchedMediaResource(
            mediaBox: context.account.postbox.mediaBox,
            userLocation: .other,
            userContentType: .file,
            reference: FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(resource)
        ).startStandalone()
        let dataDisp = (context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
            |> filter { $0.complete }
            |> take(1)
            |> deliverOnMainQueue).startStandalone(next: { data in
                fetchDisp.dispose()
                let filePath = data.path
                DispatchQueue.global(qos: .userInitiated).async {
                    let fileUrl = URL(fileURLWithPath: filePath)
                    let size = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? NSNumber)?.int64Value ?? 0
                    guard size > 0, size <= 50 * 1024 * 1024,
                          let bytes = try? Data(contentsOf: fileUrl, options: [.mappedIfSafe]) else {
                        DispatchQueue.main.async {
                            MTMediaTokWave5Tools.showToast(context: context, text: "Файл превышает лимит 50 МБ или недоступен")
                        }
                        return
                    }
                    let outcome: MTStegoDecodeOutcome
                    if let img = UIImage(data: bytes) {
                        outcome = MTStegoCodec.decodeOutcome(from: img, password: "")
                    } else {
                        outcome = .notFound
                    }
                    DispatchQueue.main.async {
                        switch outcome {
                        case .plain(let secret):
                            presentDecodedStegoAlert(context: context, secret: secret, imageBytes: bytes)
                        case .passwordRequired:
                            presentStegoPasswordPrompt(context: context, imageBytes: bytes)
                        case .wrongPassword, .notFound:
                            presentOsintXRay(context: context, initialUrl: nil, initialImageData: bytes)
                        }
                    }
                }
            })
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 25.0) {
            fetchDisp.dispose()
            dataDisp.dispose()
        }
    }

    private static func presentDecodedStegoAlert(context: AccountContext, secret: String, imageBytes: Data) {
        mtPresentNativeActionSheet(
            context: context,
            title: "Найдено скрытое послание:\n\(secret)",
            buttons: [
                ("Скопировать текст послания", false, {
                    UIPasteboard.general.string = secret
                    mtPresentNativeToast(context: context, text: "Секрет скопирован в буфер обмена")
                }),
                ("Открыть EXIF-Рентген", false, {
                    presentOsintXRay(context: context, initialUrl: nil, initialImageData: imageBytes)
                })
            ]
        )
    }

    private static func presentStegoPasswordPrompt(context: AccountContext, imageBytes: Data) {
        mtPresentNativePrompt(
            context: context,
            title: "Зашифрованный Сейф-Фото",
            subtitle: "В этом PNG обнаружен скрытый контейнер MediaTok (AES-256). Введите пароль для расшифровки:",
            placeholder: "Пароль от стего-контейнера",
            characterLimit: 128,
            apply: { pass in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let img = UIImage(data: imageBytes) else { return }
                    let outcome = MTStegoCodec.decodeOutcome(from: img, password: pass)
                    DispatchQueue.main.async {
                        switch outcome {
                        case .plain(let secret):
                            presentDecodedStegoAlert(context: context, secret: secret, imageBytes: imageBytes)
                        case .passwordRequired, .wrongPassword:
                            mtPresentNativeToast(context: context, text: "Неверный пароль от стего-контейнера")
                        case .notFound:
                            presentOsintXRay(context: context, initialUrl: nil, initialImageData: imageBytes)
                        }
                    }
                }
            }
        )
    }

    // MARK: - Presenters

    public static func presentSignatureHub(context: AccountContext, peerId: PeerId? = nil) {
        mtPresentNativeActionSheet(
            context: context,
            title: "Инструменты безопасности и медиа",
            buttons: [
                ("Призрачный Сейф-Фото (Стеганография .stego)", false, {
                    presentStegoStudio(context: context, initialImage: nil, peerId: peerId)
                }),
                ("Голос-Студия: Диктор / Рация / Демон (.vfx)", false, {
                    presentVoiceFxStudio(context: context, peerId: peerId)
                }),
                ("Сгорающая AES-256 записка с PIN (.burn)", false, {
                    presentBurnNoteComposer(context: context, peerId: peerId)
                }),
                ("Кино-карточка цитат (.cinematic)", false, {
                    presentCinematicCard(context: context, initialText: nil, author: nil, peerId: peerId)
                }),
                ("OSINT-Рентген EXIF и ссылок (.xray)", false, {
                    presentOsintXRay(context: context, initialUrl: nil, initialImageData: nil)
                })
            ]
        )
    }

    public static func presentStegoStudio(context: AccountContext, initialImage: UIImage?, peerId: PeerId? = nil) {
        let vc = MTStegoStudioViewController(context: context, initialImage: initialImage, peerId: peerId)
        let nav = UINavigationController(rootViewController: vc)
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func presentVoiceFxStudio(context: AccountContext, peerId: PeerId? = nil) {
        let vc = MTVoiceFxStudioViewController(context: context, peerId: peerId)
        let nav = UINavigationController(rootViewController: vc)
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func presentBurnNoteComposer(context: AccountContext, peerId: PeerId?) {
        let controller = mtMakeNativeBurnNoteComposerController(context: context, peerId: peerId)
        mtPushNativeController(controller, context: context)
    }

    private static func recordBurnHash(_ hash: String) {
        var updated = UserDefaults.standard.stringArray(forKey: burnedNotesKey) ?? []
        if !updated.contains(hash) {
            updated.append(hash)
        }
        if updated.count > 200 {
            updated.removeFirst(updated.count - 200)
        }
        UserDefaults.standard.set(updated, forKey: burnedNotesKey)
    }

    public static func presentBurnNoteDecryptor(context: AccountContext, token: String) {
        let hash = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        let burned = UserDefaults.standard.stringArray(forKey: burnedNotesKey) ?? []
        if burned.contains(hash) {
            mtPresentNativeAlert(context: context, title: "Записка уже сгорела", text: "Эта одноразовая записка была прочитана и уничтожена на этом устройстве.")
            return
        }

        let attemptsDict = (UserDefaults.standard.dictionary(forKey: burnPinAttemptsKey) as? [String: Int]) ?? [:]
        let usedAttempts = attemptsDict[hash] ?? 0
        if usedAttempts >= maxBurnPinAttempts {
            recordBurnHash(hash)
            mtPresentNativeAlert(context: context, title: "Записка уничтожена", text: "Превышен лимит попыток ввода PIN-кода (\(maxBurnPinAttempts)). Записка сожжена.")
            return
        }

        let remainingBefore = maxBurnPinAttempts - usedAttempts
        mtPresentNativePrompt(
            context: context,
            title: "Сгорающая записка",
            subtitle: "Введите PIN/пароль от отправителя (осталось попыток: \(remainingBefore), после открытия будет 10 секунд):",
            placeholder: "PIN-код или пароль",
            characterLimit: 64,
            apply: { raw in
                let pin = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pin.isEmpty else {
                    mtPresentNativeToast(context: context, text: "Введите PIN-код или пароль")
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let res = MTBurnNoteCrypto.decrypt(token: token, pin: pin)
                    DispatchQueue.main.async {
                        switch res {
                        case .success(let secret):
                            var dict = (UserDefaults.standard.dictionary(forKey: burnPinAttemptsKey) as? [String: Int]) ?? [:]
                            dict.removeValue(forKey: hash)
                            UserDefaults.standard.set(dict, forKey: burnPinAttemptsKey)

                            let viewer = MTBurnNoteCountdownViewController(secretText: secret, onPresented: {
                                recordBurnHash(hash)
                            })
                            viewer.modalPresentationStyle = .overFullScreen
                            MTModalPresenter.presentOnTopmost(viewer)
                        case .expired:
                            recordBurnHash(hash)
                            mtPresentNativeToast(context: context, text: "Срок жизни записки истёк — она сгорела")
                        case .wrongPin:
                            var dict = (UserDefaults.standard.dictionary(forKey: burnPinAttemptsKey) as? [String: Int]) ?? [:]
                            let nextCount = (dict[hash] ?? 0) + 1
                            dict[hash] = nextCount
                            if dict.count > 200, let firstKey = dict.keys.first {
                                dict.removeValue(forKey: firstKey)
                            }
                            UserDefaults.standard.set(dict, forKey: burnPinAttemptsKey)
                            if nextCount >= maxBurnPinAttempts {
                                recordBurnHash(hash)
                                mtPresentNativeToast(context: context, text: "5 неверных попыток — записка уничтожена")
                            } else {
                                let left = maxBurnPinAttempts - nextCount
                                mtPresentNativeToast(context: context, text: "Неверный PIN (осталось попыток: \(left))")
                            }
                        }
                    }
                }
            }
        )
    }

    public static func presentCinematicCard(context: AccountContext, initialText: String?, author: String?, peerId: PeerId? = nil) {
        let vc = MTCinematicCardViewController(context: context, initialText: initialText, author: author, peerId: peerId)
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func presentOsintXRay(context: AccountContext, initialUrl: String?, initialImageData: Data?, sourceWarning: String? = nil) {
        let vc = MTOsintXRayViewController(context: context, initialUrl: initialUrl, initialImageData: initialImageData, sourceWarning: sourceWarning)
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        MTModalPresenter.presentOnTopmost(nav)
    }

    public static func isBlockedOrPrivateHost(_ rawHost: String, resolveDNS: Bool = false) -> Bool {
        return MTOsintXRayViewController.isBlockedOrPrivateHost(rawHost, resolveDNS: resolveDNS)
    }
}

// ============================================================================
// #501 — Stealth Photo Steganography (LSB RGBX sRGB PNG Codec + Studio UI)
// ============================================================================

private enum MTStegoDecodeOutcome {
    case plain(String)
    case passwordRequired
    case wrongPassword
    case notFound
}

private enum MTStegoCodec {
    private static let legacyMagic: [UInt8] = [0x4D, 0x54, 0x53, 0x47] // "MTSG"
    private static let magicV2: [UInt8] = [0x4D, 0x54, 0x53, 0x32]     // "MTS2"
    private static let maxPixels = 16_000_000

    private static func xorStream(_ data: Data, password: String) -> Data {
        guard !password.isEmpty else { return data }
        let keyHash = Array(SHA256.hash(data: Data(password.utf8)))
        var out = Data(capacity: data.count)
        for (i, b) in data.enumerated() {
            out.append(b ^ keyHash[i % keyHash.count])
        }
        return out
    }

    private static func normalizedRGBX(from image: UIImage, maxDimension: Int?) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let rawW = max(1, Int((image.size.width * image.scale).rounded()))
        let rawH = max(1, Int((image.size.height * image.scale).rounded()))
        let width: Int
        let height: Int
        if let maxDim = maxDimension, max(rawW, rawH) > maxDim {
            let ratio = Double(maxDim) / Double(max(rawW, rawH))
            width = max(1, Int((Double(rawW) * ratio).rounded()))
            height = max(1, Int((Double(rawH) * ratio).rounded()))
        } else {
            width = rawW
            height = rawH
        }
        guard width * height <= maxPixels else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0xFF, count: bytesPerRow * height)
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        return (pixels, width, height)
    }

    private static func encodeRGBXToPNG(pixels: inout [UInt8], width: Int, height: Int) -> Data? {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: bitmapInfo
        ),
              let cg = ctx.makeImage(),
              let outData = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(outData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return outData as Data
    }

    static func encode(secret: String, into image: UIImage, password: String) -> Data? {
        guard var buf = normalizedRGBX(from: image, maxDimension: 1600) else { return nil }
        let width = buf.width
        let height = buf.height

        let plainBytes = Data(secret.utf8)
        let flag: UInt8
        let bodyData: Data
        if password.isEmpty {
            flag = 0x00
            bodyData = plainBytes
        } else {
            flag = 0x01
            var saltBytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
                return nil
            }
            let salt = Data(saltBytes)
            guard let key = MTMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: password, salt: salt, iterations: 100_000),
                  let sealed = try? AES.GCM.seal(plainBytes, using: key, authenticating: Data("MTS2".utf8)),
                  let combined = sealed.combined else {
                return nil
            }
            var enc = Data()
            enc.append(salt)
            enc.append(combined)
            bodyData = enc
        }

        var payload = Data(magicV2)
        payload.append(flag)
        var len = UInt32(bodyData.count).bigEndian
        payload.append(Data(bytes: &len, count: 4))
        payload.append(bodyData)

        let totalBits = payload.count * 8
        let availableChannels = width * height * 3 // R, G, B channels (skip X)
        guard totalBits <= availableChannels else { return nil }

        var bitIdx = 0
        for px in 0..<(width * height) {
            let base = px * 4
            for ch in 0..<3 {
                if bitIdx >= totalBits { break }
                let byteVal = payload[bitIdx / 8]
                let bit = (byteVal >> (7 - (bitIdx % 8))) & 1
                buf.pixels[base + ch] = (buf.pixels[base + ch] & 0xFE) | bit
                bitIdx += 1
            }
            if bitIdx >= totalBits { break }
        }

        return encodeRGBXToPNG(pixels: &buf.pixels, width: width, height: height)
    }

    static func decodeOutcome(from image: UIImage, password: String) -> MTStegoDecodeOutcome {
        guard let buf = normalizedRGBX(from: image, maxDimension: nil) else { return .notFound }
        let width = buf.width
        let height = buf.height
        let pixels = buf.pixels

        func readBytes(count: Int, startBit: Int) -> Data? {
            let endBit = startBit + count * 8
            guard count >= 0, endBit <= width * height * 3 else { return nil }
            var result = Data(count: count)
            for b in 0..<count {
                var val: UInt8 = 0
                for k in 0..<8 {
                    let gBit = startBit + b * 8 + k
                    let px = gBit / 3
                    let ch = gBit % 3
                    let lsb = pixels[px * 4 + ch] & 1
                    val = (val << 1) | lsb
                }
                result[b] = val
            }
            return result
        }

        guard let magicBytes = readBytes(count: 4, startBit: 0) else { return .notFound }
        let magicArr = Array(magicBytes)

        if magicArr == magicV2 {
            guard let meta = readBytes(count: 5, startBit: 32) else { return .notFound }
            let flag = meta[0]
            let len = (UInt32(meta[1]) << 24) | (UInt32(meta[2]) << 16) | (UInt32(meta[3]) << 8) | UInt32(meta[4])
            guard len > 0 && len < 250_000,
                  let body = readBytes(count: Int(len), startBit: 72) else {
                return .notFound
            }
            if flag == 0x00 {
                guard let str = String(data: body, encoding: .utf8) else { return .notFound }
                return .plain(str)
            } else if flag == 0x01 {
                if password.isEmpty {
                    return .passwordRequired
                }
                guard body.count > 16 + 28 else { return .wrongPassword }
                let salt = Data(body.prefix(16))
                let combined = Data(body.dropFirst(16))
                guard let key = MTMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: password, salt: salt, iterations: 100_000),
                      let box = try? AES.GCM.SealedBox(combined: combined),
                      let plain = try? AES.GCM.open(box, using: key, authenticating: Data("MTS2".utf8)),
                      let str = String(data: plain, encoding: .utf8) else {
                    return .wrongPassword
                }
                return .plain(str)
            }
            return .notFound
        } else if magicArr == legacyMagic {
            guard let lenBytes = readBytes(count: 4, startBit: 32) else { return .notFound }
            let len = (UInt32(lenBytes[0]) << 24) | (UInt32(lenBytes[1]) << 16) | (UInt32(lenBytes[2]) << 8) | UInt32(lenBytes[3])
            guard len > 0 && len < 250_000,
                  let body = readBytes(count: Int(len), startBit: 64) else {
                return .notFound
            }
            let decoded = xorStream(body, password: password)
            if let str = String(data: decoded, encoding: .utf8) {
                return .plain(str)
            }
            return password.isEmpty ? .passwordRequired : .wrongPassword
        }
        return .notFound
    }

    static func decode(from image: UIImage, password: String) -> String? {
        if case let .plain(str) = decodeOutcome(from: image, password: password) {
            return str
        }
        return nil
    }
}

private final class MTStegoStudioViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let context: AccountContext
    private let peerId: PeerId?
    private var selectedImage: UIImage?
    private var encodedPngData: Data?

    private let imageView = UIImageView()
    private let secretField = UITextView()
    private let passField = UITextField()
    private let statusLabel = UILabel()

    init(context: AccountContext, initialImage: UIImage?, peerId: PeerId?) {
        self.context = context
        self.peerId = peerId
        self.selectedImage = initialImage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🕵️‍♂️ Призрачный Сейф-Фото"
        self.view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Фото", style: .done, target: self, action: #selector(pickPhotoTapped))

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        self.imageView.layer.cornerRadius = 12
        self.imageView.clipsToBounds = true
        self.imageView.image = self.selectedImage

        self.secretField.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        self.secretField.textColor = .white
        self.secretField.font = .systemFont(ofSize: 14)
        self.secretField.layer.cornerRadius = 10
        self.secretField.text = ""

        self.passField.borderStyle = .roundedRect
        self.passField.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        self.passField.textColor = .white
        self.passField.placeholder = "Пароль AES-256 (необязательно)"

        self.statusLabel.textColor = .secondaryLabel
        self.statusLabel.font = .systemFont(ofSize: 12)
        self.statusLabel.numberOfLines = 2
        self.statusLabel.text = "Спрячь текст в пикселях PNG (отправляй как Файл без сжатия!) или расшифруй полученное фото."

        let encBtn = makeBtn("🔒 Спрятать в фото (PNG)", .systemBlue, #selector(encodeTapped))
        let decBtn = makeBtn("🔓 Извлечь секрет", .systemPurple, #selector(decodeTapped))
        let sendBtnTitle = self.peerId != nil ? "📤 В чат (Файл PNG без сжатия)" : "📤 Экспорт PNG как файл"
        let sendBtn = makeBtn(sendBtnTitle, .systemGreen, #selector(sendAsDocumentTapped))
        let shareBtn = makeBtn("📁 Поделиться PNG...", UIColor(white: 0.22, alpha: 1.0), #selector(shareTapped))

        let row = UIStackView(arrangedSubviews: [encBtn, decBtn])
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        let actionRow: UIStackView
        if self.peerId != nil {
            actionRow = UIStackView(arrangedSubviews: [sendBtn, shareBtn])
        } else {
            actionRow = UIStackView(arrangedSubviews: [shareBtn])
        }
        actionRow.axis = .horizontal
        actionRow.spacing = 10
        actionRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [self.imageView, self.secretField, self.passField, self.statusLabel, row, actionRow])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            self.imageView.heightAnchor.constraint(equalToConstant: 200),
            self.passField.heightAnchor.constraint(equalToConstant: 40),
            row.heightAnchor.constraint(equalToConstant: 44),
            actionRow.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func makeBtn(_ title: String, _ bg: UIColor, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 12
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    @objc private func pickPhotoTapped() {
        let p = UIImagePickerController()
        p.sourceType = .photoLibrary
        p.delegate = self
        self.present(p, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let img = info[.originalImage] as? UIImage {
            self.selectedImage = img
            self.imageView.image = img
            self.encodedPngData = nil
            self.statusLabel.text = "Фото выбрано. Введи текст и нажми «Спрятать» или «Извлечь»."
        }
    }

    @objc private func encodeTapped() {
        guard let img = self.selectedImage else { pickPhotoTapped(); return }
        let secret = self.secretField.text ?? ""
        guard !secret.isEmpty else { self.statusLabel.text = "Введи секретный текст!"; return }
        let pass = self.passField.text ?? ""
        self.statusLabel.text = "⚙️ Вшиваю секрет в LSB-каналы PNG..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let png = MTStegoCodec.encode(secret: secret, into: img, password: pass)
            DispatchQueue.main.async {
                guard let self else { return }
                if let png {
                    self.encodedPngData = png
                    if let preview = UIImage(data: png) {
                        self.imageView.image = preview
                    }
                    self.statusLabel.text = "✅ Секрет (\(secret.utf8.count) байт) вшит в PNG (\(png.count / 1024) KB)! Отправляй как Файл."
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "🕵️‍♂️ Текст спрятан в пиксели PNG!")
                } else {
                    self.statusLabel.text = "Не удалось закодировать (слишком длинный текст или огромная картинка)."
                }
            }
        }
    }

    @objc private func decodeTapped() {
        guard let img = self.selectedImage else { pickPhotoTapped(); return }
        let pass = self.passField.text ?? ""
        self.statusLabel.text = "⚙️ Анализирую LSB-каналы..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = MTStegoCodec.decodeOutcome(from: img, password: pass)
            DispatchQueue.main.async {
                guard let self else { return }
                switch outcome {
                case .plain(let found):
                    self.secretField.text = found
                    UIPasteboard.general.string = found
                    self.statusLabel.text = "🔓 Найдено и скопировано скрытое сообщение!"
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "🔓 Секрет извлечён из фото!")
                case .passwordRequired:
                    self.statusLabel.text = "🔒 Этот PNG защищён паролем (AES-256). Введи пароль в поле выше!"
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "🔒 Введи пароль для расшифровки")
                case .wrongPassword:
                    self.statusLabel.text = "❌ Неверный пароль или повреждённый контейнер."
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "❌ Неверный пароль")
                case .notFound:
                    self.statusLabel.text = "Скрытое послание MediaTok не найдено (возможно, фото было сжато в JPEG)."
                }
            }
        }
    }

    @objc private func sendAsDocumentTapped() {
        guard let png = self.encodedPngData else {
            self.statusLabel.text = "Сначала нажми «Спрятать в фото»."
            return
        }
        guard let peerId = self.peerId else {
            shareTapped()
            return
        }
        let fileId = Int64.random(in: Int64.min ... Int64.max)
        let resource = LocalFileMediaResource(fileId: fileId)
        self.context.account.postbox.mediaBox.storeResourceData(resource.id, data: png, synchronous: true)
        var attrs: [TelegramMediaFileAttribute] = [
            .FileName(fileName: "MediaTok_Stego.png")
        ]
        if let img = UIImage(data: png) {
            let w = Int32((img.size.width * img.scale).rounded())
            let h = Int32((img.size.height * img.scale).rounded())
            attrs.append(.ImageSize(size: PixelDimensions(width: w, height: h)))
        }
        let media = TelegramMediaFile(
            fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: fileId),
            partialReference: nil,
            resource: resource,
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: "image/png",
            size: Int64(png.count),
            attributes: attrs,
            alternativeRepresentations: []
        )
        let msg: EnqueueMessage = .message(
            text: "",
            attributes: [],
            inlineStickers: [:],
            mediaReference: .standalone(media: media),
            threadId: nil,
            replyToMessageId: nil,
            replyToStoryId: nil,
            localGroupingKey: nil,
            correlationId: nil,
            bubbleUpEmojiOrStickersets: []
        )
        _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).start()
        MTMediaTokWave5Tools.showToast(context: self.context, text: "🕵️‍♂️ PNG-файл со скрытым посланием отправлен без сжатия!")
        self.dismiss(animated: true)
    }

    @objc private func shareTapped() {
        guard let png = self.encodedPngData else {
            self.statusLabel.text = "Сначала нажми «Спрятать в фото»."
            return
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MediaTok_Stego_\(Int(Date().timeIntervalSince1970)).png")
        try? png.write(to: tmp, options: [.atomic])
        let ac = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        ac.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: tmp)
        }
        MTModalPresenter.configurePopover(ac, hostView: self.view)
        self.present(ac, animated: true)
    }
}

// ============================================================================
// #502 — Real-Time Voice FX Studio (AVAudioEngine Offline Renderer -> Voice Ogg/Opus & .m4a)
// ============================================================================

private enum MTVoiceFxPreset: Int, CaseIterable {
    case announcer = 0
    case radio
    case demon
    case chipmunk
    case robot
    case hall

    var title: String {
        switch self {
        case .announcer: return "🎙 Диктор"
        case .radio: return "📻 Рация"
        case .demon: return "👹 Демон"
        case .chipmunk: return "🐿 Бурундук"
        case .robot: return "🤖 Робот"
        case .hall: return "🏛 Зал"
        }
    }
}

private final class MTVoiceFxStudioViewController: UIViewController {
    private let context: AccountContext
    private let peerId: PeerId?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var rawUrl: URL?
    private var renderedUrl: URL?
    private var selectedPreset: MTVoiceFxPreset = .announcer

    private let statusLabel = UILabel()
    private let presetSegment = UISegmentedControl(items: MTVoiceFxPreset.allCases.map(\.title))
    private let recordBtn = UIButton(type: .system)

    init(context: AccountContext, peerId: PeerId?) {
        self.context = context
        self.peerId = peerId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        self.recorder?.stop()
        self.player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if let raw = self.rawUrl {
            try? FileManager.default.removeItem(at: raw)
        }
        if let rend = self.renderedUrl {
            try? FileManager.default.removeItem(at: rend)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🎛 Голос-Студия FX"
        self.view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))

        self.presetSegment.selectedSegmentIndex = 0
        self.presetSegment.addTarget(self, action: #selector(presetChanged), for: .valueChanged)

        self.statusLabel.textColor = .white
        self.statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 3
        self.statusLabel.text = "Запиши фразу, выбери эффект (Диктор, Рация, Демон, Бурундук, Робот, Зал) и слушай/отправляй!"

        self.recordBtn.setTitle("🔴 Записать голос", for: .normal)
        self.recordBtn.setTitleColor(.white, for: .normal)
        self.recordBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        self.recordBtn.backgroundColor = .systemRed
        self.recordBtn.layer.cornerRadius = 14
        self.recordBtn.addTarget(self, action: #selector(toggleRecordTapped), for: .touchUpInside)

        let playBtn = makeBtn("▶️ Применить FX и прослушать", .systemBlue, #selector(renderAndPlayTapped))
        let voiceBtn = makeBtn("🎙 Отправить как ГС в чат", .systemGreen, #selector(sendVoiceTapped))
        let shareBtn = makeBtn("📤 Экспорт .m4a", UIColor(white: 0.22, alpha: 1.0), #selector(shareTapped))

        var views: [UIView] = [self.statusLabel, self.presetSegment, self.recordBtn, playBtn]
        if self.peerId != nil {
            views.append(voiceBtn)
        }
        views.append(shareBtn)

        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            self.recordBtn.heightAnchor.constraint(equalToConstant: 54),
            playBtn.heightAnchor.constraint(equalToConstant: 48),
            voiceBtn.heightAnchor.constraint(equalToConstant: 48),
            shareBtn.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func makeBtn(_ title: String, _ bg: UIColor, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 12
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    @objc private func closeTapped() {
        self.recorder?.stop()
        self.player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        self.dismiss(animated: true)
    }

    private func invalidateRenderedAudio() {
        self.player?.stop()
        self.player = nil
        if let old = self.renderedUrl {
            try? FileManager.default.removeItem(at: old)
            self.renderedUrl = nil
        }
    }

    @objc private func presetChanged() {
        self.selectedPreset = MTVoiceFxPreset(rawValue: self.presetSegment.selectedSegmentIndex) ?? .announcer
        invalidateRenderedAudio()
    }

    private func stopActiveRecordingIfNeeded() {
        if let rec = self.recorder, rec.isRecording {
            rec.stop()
            self.recorder = nil
            self.recordBtn.setTitle("🔴 Записать заново", for: .normal)
            self.recordBtn.backgroundColor = .systemRed
        }
    }

    @objc private func toggleRecordTapped() {
        if let rec = self.recorder, rec.isRecording {
            stopActiveRecordingIfNeeded()
            self.statusLabel.text = "✅ Запись сохранена! Выбери эффект и нажми «Применить FX и прослушать»."
            return
        }

        self.player?.stop()
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.statusLabel.text = "❌ Нет доступа к микрофону. Разреши доступ в Настройках iOS."
                    MTMediaTokWave5Tools.showToast(context: self.context, text: "❌ Нет доступа к микрофону")
                    return
                }
                self.beginRecordingWithPermission()
            }
        }
    }

    private func beginRecordingWithPermission() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            self.statusLabel.text = "Ошибка инициализации аудио-сессии."
            return
        }

        invalidateRenderedAudio()
        if let oldRaw = self.rawUrl {
            try? FileManager.default.removeItem(at: oldRaw)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mediatok_raw_\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings), rec.record() else {
            self.statusLabel.text = "Не удалось начать запись с микрофона."
            return
        }
        self.recorder = rec
        self.rawUrl = url
        self.recordBtn.setTitle("⏹ Остановить запись", for: .normal)
        self.recordBtn.backgroundColor = .systemOrange
        self.statusLabel.text = "🎙 Идёт запись... Говори в микрофон!"
    }

    @objc private func renderAndPlayTapped() {
        stopActiveRecordingIfNeeded()
        guard let rawUrl = self.rawUrl else {
            self.statusLabel.text = "Сначала запиши голос!"
            return
        }
        let preset = self.selectedPreset
        self.statusLabel.text = "⚙️ Рендеринг эффекта «\(preset.title)»..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let outUrl = self.renderOffline(inputUrl: rawUrl, preset: preset) else {
                DispatchQueue.main.async { [weak self] in
                    self?.statusLabel.text = "Ошибка рендеринга аудио (проверь запись)."
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    try? FileManager.default.removeItem(at: outUrl)
                    return
                }
                if let oldRendered = self.renderedUrl, oldRendered != outUrl {
                    try? FileManager.default.removeItem(at: oldRendered)
                }
                self.renderedUrl = outUrl
                self.statusLabel.text = "▶️ Воспроизведение: \(preset.title)"
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .default)
                try? session.setActive(true)
                self.player = try? AVAudioPlayer(contentsOf: outUrl)
                _ = self.player?.play()
            }
        }
    }

    private func renderOffline(inputUrl: URL, preset: MTVoiceFxPreset) -> URL? {
        guard let srcFile = try? AVAudioFile(forReading: inputUrl), srcFile.length > 0 else { return nil }
        let srcFormat = srcFile.processingFormat
        guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000.0, channels: 2) else { return nil }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let upmixMixer = AVAudioMixerNode()
        let pitchNode = AVAudioUnitTimePitch()
        let reverbNode = AVAudioUnitReverb()
        let distNode = AVAudioUnitDistortion()
        let eqNode = AVAudioUnitEQ(numberOfBands: 2)

        switch preset {
        case .announcer:
            pitchNode.pitch = -180
            reverbNode.loadFactoryPreset(.smallRoom)
            reverbNode.wetDryMix = 12
            distNode.wetDryMix = 0
            eqNode.bands[0].filterType = .lowShelf
            eqNode.bands[0].frequency = 140
            eqNode.bands[0].gain = 7.0
            eqNode.bands[0].bypass = false
        case .radio:
            pitchNode.pitch = 0
            reverbNode.wetDryMix = 0
            distNode.loadFactoryPreset(.speechRadioTower)
            distNode.wetDryMix = 55
            eqNode.bands[0].filterType = .bandPass
            eqNode.bands[0].frequency = 1400
            eqNode.bands[0].bandwidth = 1.2
            eqNode.bands[0].bypass = false
        case .demon:
            pitchNode.pitch = -700
            reverbNode.loadFactoryPreset(.cathedral)
            reverbNode.wetDryMix = 42
            distNode.loadFactoryPreset(.drumsBitBrush)
            distNode.wetDryMix = 18
        case .chipmunk:
            pitchNode.pitch = 680
            reverbNode.wetDryMix = 5
            distNode.wetDryMix = 0
        case .robot:
            pitchNode.pitch = -90
            reverbNode.loadFactoryPreset(.plate)
            reverbNode.wetDryMix = 30
            distNode.loadFactoryPreset(.speechCosmicInterference)
            distNode.wetDryMix = 62
        case .hall:
            pitchNode.pitch = 0
            reverbNode.loadFactoryPreset(.largeHall2)
            reverbNode.wetDryMix = 65
            distNode.wetDryMix = 0
        }

        engine.attach(playerNode)
        engine.attach(upmixMixer)
        engine.attach(pitchNode)
        engine.attach(eqNode)
        engine.attach(distNode)
        engine.attach(reverbNode)

        let maxFrames: AVAudioFrameCount = 4096
        guard (try? engine.enableManualRenderingMode(.offline, format: stereoFormat, maximumFrameCount: maxFrames)) != nil else {
            return nil
        }

        engine.connect(playerNode, to: upmixMixer, format: srcFormat)
        engine.connect(upmixMixer, to: pitchNode, format: stereoFormat)
        engine.connect(pitchNode, to: eqNode, format: stereoFormat)
        engine.connect(eqNode, to: distNode, format: stereoFormat)
        engine.connect(distNode, to: reverbNode, format: stereoFormat)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: stereoFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: stereoFormat)

        guard (try? engine.start()) != nil else {
            return nil
        }
        playerNode.scheduleFile(srcFile, at: nil)
        playerNode.play()

        let outUrl = FileManager.default.temporaryDirectory.appendingPathComponent("MediaTok_FX_\(preset.rawValue)_\(UUID().uuidString).m4a")
        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: stereoFormat.sampleRate,
            AVNumberOfChannelsKey: stereoFormat.channelCount,
            AVEncoderBitRateKey: 128000
        ]
        guard let outFile = try? AVAudioFile(forWriting: outUrl, settings: outSettings),
              let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames) else {
            playerNode.stop()
            engine.stop()
            return nil
        }

        let tailSeconds: Double = (preset == .demon || preset == .hall) ? 2.2 : 0.8
        let srcDuration = Double(srcFile.length) / max(1.0, srcFormat.sampleRate)
        let targetLength = AVAudioFramePosition((srcDuration + tailSeconds) * stereoFormat.sampleRate)

        var cannotRenderRetries = 0
        while engine.manualRenderingSampleTime < targetLength {
            let remaining = targetLength - engine.manualRenderingSampleTime
            let framesToRender = min(AVAudioFrameCount(remaining), maxFrames)
            guard let status = try? engine.renderOffline(framesToRender, to: buffer) else { break }
            switch status {
            case .success:
                cannotRenderRetries = 0
                try? outFile.write(from: buffer)
            case .insufficientDataFromInputNode:
                cannotRenderRetries = 0
                buffer.frameLength = framesToRender
                if let chData = buffer.floatChannelData {
                    for c in 0 ..< Int(buffer.format.channelCount) {
                        memset(chData[c], 0, Int(framesToRender) * MemoryLayout<Float>.size)
                    }
                }
                try? outFile.write(from: buffer)
            case .cannotDoInCurrentContext:
                cannotRenderRetries += 1
                if cannotRenderRetries > 50 {
                    playerNode.stop()
                    engine.stop()
                    return nil
                }
                usleep(10_000)
                continue
            case .error:
                playerNode.stop()
                engine.stop()
                return nil
            @unknown default:
                playerNode.stop()
                engine.stop()
                return nil
            }
        }
        playerNode.stop()
        engine.stop()
        return outUrl
    }

    private static func encodeAudioFileToOggOpus(url: URL) -> (data: Data, duration: Double)? {
        guard let audioFile = try? AVAudioFile(forReading: url), audioFile.length > 0 else { return nil }
        let srcFormat = audioFile.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(audioFile.length)),
              (try? audioFile.read(into: buf)) != nil,
              let chData = buf.floatChannelData else {
            return nil
        }
        let frameLen = Int(buf.frameLength)
        let channels = Int(srcFormat.channelCount)
        guard frameLen > 0, channels > 0 else { return nil }

        var monoPcm = [Int16](repeating: 0, count: frameLen)
        if channels == 1 {
            let c0 = chData[0]
            for i in 0 ..< frameLen {
                let clamped = max(-1.0, min(1.0, c0[i]))
                monoPcm[i] = Int16(clamped * 32767.0)
            }
        } else {
            let c0 = chData[0]
            let c1 = chData[1]
            for i in 0 ..< frameLen {
                let avg = (c0[i] + c1[i]) * 0.5
                let clamped = max(-1.0, min(1.0, avg))
                monoPcm[i] = Int16(clamped * 32767.0)
            }
        }

        let dataItem = TGDataItem()
        let writer = TGOggOpusWriter()
        guard writer.begin(with: dataItem) else { return nil }

        let samplesPerPacket = 960 // 20ms @ 48kHz
        var offset = 0
        while offset < frameLen {
            let take = min(samplesPerPacket, frameLen - offset)
            let ok = monoPcm.withUnsafeMutableBufferPointer { ptr -> Bool in
                guard let base = ptr.baseAddress else { return false }
                let rawPtr = UnsafeMutableRawPointer(base.advanced(by: offset)).assumingMemoryBound(to: UInt8.self)
                return writer.writeFrame(rawPtr, frameByteCount: UInt(take * 2))
            }
            if !ok { return nil }
            offset += take
        }
        _ = writer.writeFrame(nil, frameByteCount: 0)
        guard let oggData = dataItem.data(), !oggData.isEmpty else { return nil }
        return (oggData, max(1.0, writer.encodedDuration()))
    }

    @objc private func sendVoiceTapped() {
        stopActiveRecordingIfNeeded()
        guard let peerId = self.peerId else {
            shareTapped()
            return
        }
        guard let rawUrl = self.rawUrl else {
            self.statusLabel.text = "Сначала запиши голос!"
            return
        }
        let preset = self.selectedPreset
        let existingRendered = self.renderedUrl
        self.statusLabel.text = "⚙️ Кодирую голосовое сообщение Ogg/Opus..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let targetUrl = existingRendered ?? self.renderOffline(inputUrl: rawUrl, preset: preset)
            guard let audioUrl = targetUrl,
                  let opus = Self.encodeAudioFileToOggOpus(url: audioUrl) else {
                DispatchQueue.main.async { [weak self] in
                    self?.statusLabel.text = "Ошибка кодирования Ogg/Opus."
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.renderedUrl == nil {
                    self.renderedUrl = audioUrl
                }
                let fileId = Int64.random(in: Int64.min ... Int64.max)
                let resource = LocalFileMediaResource(fileId: fileId)
                self.context.account.postbox.mediaBox.storeResourceData(resource.id, data: opus.data, synchronous: true)
                let media = TelegramMediaFile(
                    fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: fileId),
                    partialReference: nil,
                    resource: resource,
                    previewRepresentations: [],
                    videoThumbnails: [],
                    immediateThumbnailData: nil,
                    mimeType: "audio/ogg",
                    size: Int64(opus.data.count),
                    attributes: [
                        .Audio(isVoice: true, duration: Int(opus.duration.rounded()), title: nil, performer: nil, waveform: nil),
                        .FileName(fileName: "voice.ogg")
                    ],
                    alternativeRepresentations: []
                )
                let msg: EnqueueMessage = .message(
                    text: "",
                    attributes: [],
                    inlineStickers: [:],
                    mediaReference: .standalone(media: media),
                    threadId: nil,
                    replyToMessageId: nil,
                    replyToStoryId: nil,
                    localGroupingKey: nil,
                    correlationId: nil,
                    bubbleUpEmojiOrStickersets: []
                )
                _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).start()
                MTMediaTokWave5Tools.showToast(context: self.context, text: "🎙 Голосовое сообщение с FX отправлено!")
                self.closeTapped()
            }
        }
    }

    @objc private func shareTapped() {
        guard let url = self.renderedUrl else {
            self.statusLabel.text = "Сначала нажми «Применить FX и прослушать»."
            return
        }
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        MTModalPresenter.configurePopover(ac, hostView: self.view)
        self.present(ac, animated: true)
    }
}

// ============================================================================
// #503 — Burn-After-Reading AES-256-GCM Secret Note with PBKDF2 PIN & TTL
// ============================================================================

private enum MTBurnDecryptResult {
    case success(String)
    case expired
    case wrongPin
}

private enum MTBurnNoteCrypto {
    private static let burn2Prefix = "[MT:BURN2:"
    private static let legacyPrefix = "[MT:BURN:"
    private static let burn2AAD = Data("MT:BURN2".utf8)
    private static let pbkdf2Iterations = 200_000

    private static func deriveLegacyKey(pin: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data("MediaTokBurnV1|\(pin)".utf8))
        return SymmetricKey(data: digest)
    }

    static func encrypt(secret: String, pin: String, ttlSeconds: TimeInterval) -> String? {
        let expiresAt = Int64(Date().timeIntervalSince1970 + ttlSeconds)
        let payloadDict: [String: Any] = ["exp": expiresAt, "msg": secret]
        guard let plain = try? JSONSerialization.data(withJSONObject: payloadDict, options: []) else { return nil }
        var saltBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            return nil
        }
        let salt = Data(saltBytes)
        guard let key = MTMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: pin, salt: salt, iterations: pbkdf2Iterations),
              let sealed = try? AES.GCM.seal(plain, using: key, authenticating: burn2AAD),
              let combined = sealed.combined else {
            return nil
        }
        var envelope = Data()
        envelope.append(salt)
        envelope.append(combined)
        let b64 = envelope.base64EncodedString()
        return "[MT:BURN2:\(b64)]"
    }

    static func decrypt(token: String, pin: String) -> MTBurnDecryptResult {
        if token.hasPrefix(burn2Prefix) {
            let clean = token.replacingOccurrences(of: burn2Prefix, with: "").replacingOccurrences(of: "]", with: "")
            guard let raw = Data(base64Encoded: clean), raw.count > 16 + 28 else { return .wrongPin }
            let salt = Data(raw.prefix(16))
            let combined = Data(raw.dropFirst(16))
            guard let key = MTMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: pin, salt: salt, iterations: pbkdf2Iterations),
                  let box = try? AES.GCM.SealedBox(combined: combined),
                  let plain = try? AES.GCM.open(box, using: key, authenticating: burn2AAD),
                  let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
                  let exp = (obj["exp"] as? NSNumber)?.int64Value,
                  let msg = obj["msg"] as? String else {
                return .wrongPin
            }
            if Int64(Date().timeIntervalSince1970) > exp {
                return .expired
            }
            return .success(msg)
        }

        let clean = token.replacingOccurrences(of: legacyPrefix, with: "").replacingOccurrences(of: "]", with: "")
        guard let raw = Data(base64Encoded: clean),
              let box = try? AES.GCM.SealedBox(combined: raw) else { return .wrongPin }
        let key = deriveLegacyKey(pin: pin)
        guard let plain = try? AES.GCM.open(box, using: key),
              let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let exp = (obj["exp"] as? NSNumber)?.int64Value,
              let msg = obj["msg"] as? String else {
            return .wrongPin
        }
        if Int64(Date().timeIntervalSince1970) > exp {
            return .expired
        }
        return .success(msg)
    }
}

private struct MTBurnNoteComposerState: Equatable {
    var secretText: String = ""
    var pin: String = ""
    var ttlIndex: Int = 1 // 0=5m, 1=1h, 2=24h
    var isEncrypting: Bool = false
}

private func mtMakeNativeBurnNoteComposerController(context: AccountContext, peerId: PeerId?) -> ViewController {
    let statePromise = ValuePromise(MTBurnNoteComposerState(), ignoreRepeated: true)
    let stateValue = Atomic(value: MTBurnNoteComposerState())
    let ttls: [(sec: TimeInterval, title: String)] = [
        (300, "5 минут"),
        (3600, "1 час"),
        (86400, "24 часа")
    ]

    weak var selfController: ItemListController?
    let modelSignal: Signal<MTNativeScreenModel, NoError> = statePromise.get()
    |> map { st in
        var model = MTNativeScreenModel(title: "Сгорающая записка")

        model.sections.append([
            .init(id: "s_hdr", kind: .header("Секретный текст и PIN (AES-256-GCM)")),
            .init(id: "in_secret", kind: .multilineInput(text: st.secretText, placeholder: "Текст одноразовой записки...")),
            .init(id: "in_pin", kind: .input(text: st.pin, placeholder: "PIN-код или пароль получателя"))
        ])

        model.text["in_secret"] = { val in let _ = stateValue.modify { var c = $0; c.secretText = val; return c } }
        model.text["in_pin"] = { val in let _ = stateValue.modify { var c = $0; c.pin = val; return c } }

        var ttlRows: [MTNativeRow] = [.init(id: "t_hdr", kind: .header("Срок жизни шифротекста"))]
        for (idx, item) in ttls.enumerated() {
            let id = "ttl_\(idx)"
            ttlRows.append(.init(id: id, kind: .check(title: item.title, subtitle: nil, checked: st.ttlIndex == idx)))
            model.tap[id] = {
                let next = stateValue.modify { var c = $0; c.ttlIndex = idx; return c }
                statePromise.set(next)
            }
        }
        ttlRows.append(.init(id: "send_btn", kind: .action(title: st.isEncrypting ? "Шифрую..." : (peerId != nil ? "Зашифровать и отправить в чат" : "Зашифровать и скопировать"), destructive: false, enabled: !st.isEncrypting)))
        ttlRows.append(.init(id: "t_ftr", kind: .footer("Записка шифруется локально ключом PBKDF2-HMAC-SHA256 + AES-256-GCM и самоуничтожается через 10 секунд после открытия.")))
        model.sections.append(ttlRows)

        model.tap["send_btn"] = {
            let cur = stateValue.with { $0 }
            let secret = cur.secretText.trimmingCharacters(in: .whitespacesAndNewlines)
            let pin = cur.pin.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secret.isEmpty, !pin.isEmpty else {
                mtPresentNativeToast(context: context, text: "Укажите текст записки и PIN-код")
                return
            }
            let ttl = ttls[cur.ttlIndex].sec
            let busy = stateValue.modify { var c = $0; c.isEncrypting = true; return c }
            statePromise.set(busy)

            DispatchQueue.global(qos: .userInitiated).async {
                let token = MTBurnNoteCrypto.encrypt(secret: secret, pin: pin, ttlSeconds: ttl)
                DispatchQueue.main.async {
                    let done = stateValue.modify { var c = $0; c.isEncrypting = false; return c }
                    statePromise.set(done)
                    guard let token else { return }
                    let outText = "Сгорающая записка MediaTok (AES-256)\nУдерживайте сообщение → «Открыть сгорающую записку (PIN)»\n\(token)"
                    guard outText.count <= 4096 else {
                        mtPresentNativeToast(context: context, text: "Текст слишком длинный (\(outText.count)/4096)")
                        return
                    }
                    if let peerId {
                        let msg = EnqueueMessage.message(text: outText, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        _ = enqueueMessages(account: context.account, peerId: peerId, messages: [msg]).start()
                        mtPresentNativeToast(context: context, text: "Сгорающая записка отправлена")
                    } else {
                        UIPasteboard.general.string = outText
                        mtPresentNativeToast(context: context, text: "Шифротекст скопирован в буфер обмена")
                    }
                    selfController?.dismiss()
                }
            }
        }

        return model
    }

    let controller = mtMakeNativeListController(context: context, model: modelSignal)
    selfController = controller
    return controller
}

private final class MTBurnNoteCountdownViewController: UIViewController {
    private var secretText: String
    private var onPresented: (() -> Void)?
    private var didMarkPresented = false
    private var secondsLeft = 10
    private var timer: Foundation.Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private let countLabel = UILabel()
    private let msgLabel = UILabel()

    init(secretText: String, onPresented: (() -> Void)? = nil) {
        self.secretText = secretText
        self.onPresented = onPresented
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(red: 0.05, green: 0.03, blue: 0.03, alpha: 0.96)

        self.countLabel.textColor = .systemOrange
        self.countLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .heavy)
        self.countLabel.textAlignment = .center
        self.countLabel.text = "🔥 Сгорит через: 10с"

        self.msgLabel.textColor = .white
        self.msgLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        self.msgLabel.numberOfLines = 0
        self.msgLabel.textAlignment = .center
        self.msgLabel.text = self.secretText
        self.msgLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.addSubview(self.msgLabel)

        NSLayoutConstraint.activate([
            self.msgLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            self.msgLabel.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 8),
            self.msgLabel.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -8),
            self.msgLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8)
        ])

        // Protect scrollView & msgLabel via UIKitRuntimeUtils setLayerDisableScreenshots (reliable across iOS versions)
        setLayerDisableScreenshots(scrollView.layer, true)
        setLayerDisableScreenshots(self.msgLabel.layer, true)
        let hostContainer: UIView = scrollView
        hostContainer.translatesAutoresizingMaskIntoConstraints = false

        let burnNowBtn = UIButton(type: .system)
        burnNowBtn.setTitle("💨 Сжечь сейчас", for: .normal)
        burnNowBtn.setTitleColor(.white, for: .normal)
        burnNowBtn.backgroundColor = .systemRed
        burnNowBtn.layer.cornerRadius = 12
        burnNowBtn.addTarget(self, action: #selector(burnNow), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [self.countLabel, hostContainer, burnNowBtn])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            burnNowBtn.heightAnchor.constraint(equalToConstant: 48)
        ])

        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.userDidTakeScreenshotNotification,
            UIScreen.capturedDidChangeNotification
        ]
        for name in names {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.burnNow()
            }
            self.lifecycleObservers.append(obs)
        }

        self.timer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.secondsLeft -= 1
            if self.secondsLeft <= 0 {
                self.burnNow()
            } else {
                self.countLabel.text = "🔥 Сгорит через: \(self.secondsLeft)с"
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let activeScreen = self.view.window?.windowScene?.screen ?? UIScreen.main
        if activeScreen.isCaptured {
            self.msgLabel.text = "🚫 Запись экрана / AirPlay активна — секрет уничтожен."
            self.burnNow()
            return
        }
        if !self.didMarkPresented {
            self.didMarkPresented = true
            self.onPresented?()
            self.onPresented = nil
        }
    }

    @objc private func burnNow() {
        self.timer?.invalidate()
        self.timer = nil
        self.secretText = ""
        self.msgLabel.text = nil
        for obs in self.lifecycleObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        self.lifecycleObservers.removeAll()
        self.dismiss(animated: true)
    }

    deinit {
        self.timer?.invalidate()
        for obs in self.lifecycleObservers {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

// ============================================================================
// #504 — Cinematic Quote Card Studio (Keynote / Ray.so Style HD PNG)
// ============================================================================

private final class MTCinematicCardViewController: UIViewController {
    private let context: AccountContext
    private let peerId: PeerId?
    private var cardText: String
    private var cardAuthor: String
    private var themeIndex: Int = 0
    private var ratioIndex: Int = 0

    private let previewView = UIImageView()
    private let themeSegment = UISegmentedControl(items: ["Aurora", "Obsidian", "Sunset", "Cyber", "Titanium", "Gold"])
    private let ratioSegment = UISegmentedControl(items: ["1:1 Пост", "9:16 Stories", "16:9 Wide"])

    init(context: AccountContext, initialText: String?, author: String?, peerId: PeerId?) {
        self.context = context
        self.peerId = peerId
        self.cardText = initialText ?? "MediaTok — когда мессенджер становится произведением искусства."
        self.cardAuthor = author ?? "MediaTok Edition"
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🎬 Кино-карточка"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Текст", style: .plain, target: self, action: #selector(editTextTapped))

        self.themeSegment.selectedSegmentIndex = 0
        self.themeSegment.addTarget(self, action: #selector(redraw), for: .valueChanged)
        self.ratioSegment.selectedSegmentIndex = 0
        self.ratioSegment.addTarget(self, action: #selector(redraw), for: .valueChanged)

        self.previewView.contentMode = .scaleAspectFit
        self.previewView.layer.cornerRadius = 14
        self.previewView.clipsToBounds = true

        let exportBtn = UIButton(type: .system)
        exportBtn.setTitle("📤 Экспорт Full HD PNG", for: .normal)
        exportBtn.setTitleColor(.white, for: .normal)
        exportBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        exportBtn.backgroundColor = .systemIndigo
        exportBtn.layer.cornerRadius = 12
        exportBtn.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)

        let sendChatBtn = UIButton(type: .system)
        sendChatBtn.setTitle("💬 В чат", for: .normal)
        sendChatBtn.setTitleColor(.white, for: .normal)
        sendChatBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        sendChatBtn.backgroundColor = .systemBlue
        sendChatBtn.layer.cornerRadius = 12
        sendChatBtn.addTarget(self, action: #selector(sendToChatTapped), for: .touchUpInside)

        let btnRow: UIStackView
        if self.peerId != nil {
            btnRow = UIStackView(arrangedSubviews: [sendChatBtn, exportBtn])
        } else {
            btnRow = UIStackView(arrangedSubviews: [exportBtn])
        }
        btnRow.axis = .horizontal
        btnRow.spacing = 10
        btnRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [self.ratioSegment, self.themeSegment, self.previewView, btnRow])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            btnRow.heightAnchor.constraint(equalToConstant: 48)
        ])

        redraw()
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    @objc private func editTextTapped() {
        let currentText = self.cardText
        let currentAuthor = self.cardAuthor
        let alert = UIAlertController(title: "Текст карточки", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in tf.text = currentText; tf.placeholder = "Цитата" }
        alert.addTextField { tf in tf.text = currentAuthor; tf.placeholder = "Автор" }
        alert.addAction(UIAlertAction(title: "Готово", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            if let t = alert?.textFields?.first?.text, !t.isEmpty { self.cardText = t }
            if let a = alert?.textFields?.dropFirst().first?.text, !a.isEmpty { self.cardAuthor = a }
            self.redraw()
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.present(alert, animated: true)
    }

    @objc private func redraw() {
        self.themeIndex = self.themeSegment.selectedSegmentIndex
        self.ratioIndex = self.ratioSegment.selectedSegmentIndex
        self.previewView.image = renderCardImage()
    }

    private func renderCardImage() -> UIImage {
        let sizes: [CGSize] = [CGSize(width: 1080, height: 1080), CGSize(width: 1080, height: 1920), CGSize(width: 1600, height: 900)]
        let size = sizes[max(0, min(self.ratioIndex, sizes.count - 1))]
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(red: 0.16, green: 0.08, blue: 0.36, alpha: 1), UIColor(red: 0.04, green: 0.42, blue: 0.56, alpha: 1)),
            (UIColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1), UIColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)),
            (UIColor(red: 0.55, green: 0.12, blue: 0.28, alpha: 1), UIColor(red: 0.85, green: 0.42, blue: 0.16, alpha: 1)),
            (UIColor(red: 0.04, green: 0.10, blue: 0.24, alpha: 1), UIColor(red: 0.48, green: 0.08, blue: 0.52, alpha: 1)),
            (UIColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 1), UIColor(red: 0.36, green: 0.38, blue: 0.42, alpha: 1)),
            (UIColor(red: 0.28, green: 0.20, blue: 0.05, alpha: 1), UIColor(red: 0.72, green: 0.54, blue: 0.14, alpha: 1))
        ]
        let pal = palettes[max(0, min(self.themeIndex, palettes.count - 1))]

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: cs, colors: [pal.0.cgColor, pal.1.cgColor] as CFArray, locations: [0.0, 1.0]) {
                cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])
            }

            let padX = size.width * 0.10
            let cardW = size.width - padX * 2
            let textAvailW = max(100, cardW - 84)
            let maxCardH = size.height * 0.78
            let maxTextH = max(120, maxCardH - 168)

            let bodyPara = NSMutableParagraphStyle()
            bodyPara.lineSpacing = 10
            bodyPara.lineBreakMode = .byWordWrapping

            let candidateSizes: [CGFloat] = [42, 36, 30, 24]
            var chosenFontSize: CGFloat = 24
            var measuredTextH: CGFloat = 200
            for candidate in candidateSizes {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: candidate, weight: .semibold),
                    .paragraphStyle: bodyPara
                ]
                let bounds = (self.cardText as NSString).boundingRect(
                    with: CGSize(width: textAvailW, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                chosenFontSize = candidate
                measuredTextH = ceil(bounds.height)
                if measuredTextH <= maxTextH {
                    break
                }
            }

            let cardH = min(maxCardH, max(360, measuredTextH + 188))
            let cardRect = CGRect(x: padX, y: (size.height - cardH) * 0.5, width: cardW, height: cardH)

            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 26), blur: 55, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 36)
            UIColor(white: 0.09, alpha: 0.82).setFill()
            cardPath.fill()
            cg.restoreGState()

            UIColor.white.withAlphaComponent(0.18).setStroke()
            cardPath.lineWidth = 2.0
            cardPath.stroke()

            let dotColors: [UIColor] = [.systemRed, .systemYellow, .systemGreen]
            for (i, c) in dotColors.enumerated() {
                let dRect = CGRect(x: cardRect.minX + 34 + CGFloat(i) * 26, y: cardRect.minY + 32, width: 14, height: 14)
                c.setFill()
                UIBezierPath(ovalIn: dRect).fill()
            }

            let authorPara = NSMutableParagraphStyle()
            authorPara.lineBreakMode = .byTruncatingTail
            let authorAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.75),
                .paragraphStyle: authorPara
            ]
            let authorRect = CGRect(x: cardRect.minX + 128, y: cardRect.minY + 24, width: max(60, cardW - 170), height: 36)
            (self.cardAuthor as NSString).draw(in: authorRect, withAttributes: authorAttrs)

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: chosenFontSize, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: bodyPara
            ]
            let textRect = cardRect.inset(by: UIEdgeInsets(top: 96, left: 42, bottom: 72, right: 42))
            (self.cardText as NSString).draw(in: textRect, withAttributes: bodyAttrs)

            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.50)
            ]
            ("✦ MediaTok Cinematic" as NSString).draw(at: CGPoint(x: cardRect.minX + 42, y: cardRect.maxY - 52), withAttributes: badgeAttrs)
        }
    }

    @objc private func sendToChatTapped() {
        guard let peerId = self.peerId else {
            exportTapped()
            return
        }
        let img = renderCardImage()
        guard let jpeg = img.jpegData(compressionQuality: 0.94) else { return }
        let randomId = Int64.random(in: Int64.min ... Int64.max)
        let resource = LocalFileMediaResource(fileId: randomId)
        self.context.account.postbox.mediaBox.storeResourceData(resource.id, data: jpeg, synchronous: true)
        let rep = TelegramMediaImageRepresentation(
            dimensions: PixelDimensions(width: Int32(img.size.width), height: Int32(img.size.height)),
            resource: resource,
            progressiveSizes: [],
            immediateThumbnailData: nil,
            hasVideo: false,
            isPersonal: false
        )
        let media = TelegramMediaImage(
            imageId: EngineMedia.Id(namespace: Namespaces.Media.LocalImage, id: randomId),
            representations: [rep],
            immediateThumbnailData: nil,
            reference: nil,
            partialReference: nil,
            flags: []
        )
        let msg: EnqueueMessage = .message(
            text: "",
            attributes: [],
            inlineStickers: [:],
            mediaReference: .standalone(media: media),
            threadId: nil,
            replyToMessageId: nil,
            replyToStoryId: nil,
            localGroupingKey: nil,
            correlationId: nil,
            bubbleUpEmojiOrStickersets: []
        )
        _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [msg]).start()
        MTMediaTokWave5Tools.showToast(context: self.context, text: "🎬 Кино-карточка отправлена в чат!")
        self.dismiss(animated: true)
    }

    @objc private func exportTapped() {
        let img = renderCardImage()
        let ac = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        MTModalPresenter.configurePopover(ac, hostView: self.view)
        self.present(ac, animated: true)
    }
}

// ============================================================================
// #505 — OSINT X-Ray (EXIF / GPS / Camera / AI + URL Redirect & Phishing Scanner)
// ============================================================================

private final class MTNoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private final class MTOsintXRayViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let context: AccountContext
    private let initialUrl: String?
    private let initialImageData: Data?
    private let initialSourceWarning: String?

    private let urlField = UITextField()
    private let reportView = UITextView()

    init(context: AccountContext, initialUrl: String?, initialImageData: Data?, sourceWarning: String? = nil) {
        self.context = context
        self.initialUrl = initialUrl
        self.initialImageData = initialImageData
        self.initialSourceWarning = sourceWarning
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "🔬 OSINT-Рентген"
        self.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Фото EXIF", style: .done, target: self, action: #selector(pickPhotoTapped))

        self.urlField.borderStyle = .roundedRect
        self.urlField.backgroundColor = UIColor(white: 0.14, alpha: 1.0)
        self.urlField.textColor = .white
        self.urlField.placeholder = "Вставь ссылку для проверки редиректов и фишинга..."
        self.urlField.text = self.initialUrl

        self.reportView.backgroundColor = UIColor(white: 0.10, alpha: 1.0)
        self.reportView.textColor = .white
        self.reportView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        self.reportView.isEditable = false
        self.reportView.layer.cornerRadius = 12
        self.reportView.text = "Выбери фото (EXIF/GPS/Камера/SHA-256) или вставь URL для безопасной проверки редиректов."

        let scanBtn = UIButton(type: .system)
        scanBtn.setTitle("🔬 Проверить ссылку (Safe HEAD)", for: .normal)
        scanBtn.setTitleColor(.white, for: .normal)
        scanBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        scanBtn.backgroundColor = .systemTeal
        scanBtn.layer.cornerRadius = 12
        scanBtn.addTarget(self, action: #selector(scanUrlTapped), for: .touchUpInside)

        let copyBtn = UIButton(type: .system)
        copyBtn.setTitle("📋 Скопировать отчёт", for: .normal)
        copyBtn.setTitleColor(.white, for: .normal)
        copyBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        copyBtn.backgroundColor = UIColor(white: 0.22, alpha: 1.0)
        copyBtn.layer.cornerRadius = 12
        copyBtn.addTarget(self, action: #selector(copyReportTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [self.urlField, scanBtn, self.reportView, copyBtn])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            self.urlField.heightAnchor.constraint(equalToConstant: 42),
            scanBtn.heightAnchor.constraint(equalToConstant: 44),
            copyBtn.heightAnchor.constraint(equalToConstant: 42)
        ])

        if let data = self.initialImageData {
            inspectImageBytes(data, sourceWarning: self.initialSourceWarning)
        } else if let u = self.initialUrl, !u.isEmpty {
            scanUrlTapped()
        }
    }

    @objc private func closeTapped() { self.dismiss(animated: true) }

    @objc private func pickPhotoTapped() {
        let p = UIImagePickerController()
        p.sourceType = .photoLibrary
        p.delegate = self
        self.present(p, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let url = info[.imageURL] as? URL {
            self.reportView.text = "🔬 Читаю сырые байты файла и EXIF..."
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0, size <= 50 * 1024 * 1024,
                      let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                    DispatchQueue.main.async {
                        self?.reportView.text = "❌ Не удалось прочитать файл изображения (или размер > 50 МБ)."
                    }
                    return
                }
                DispatchQueue.main.async {
                    self?.inspectImageBytes(data, sourceWarning: nil)
                }
            }
        } else if let img = info[.originalImage] as? UIImage {
            let w = Int((img.size.width * img.scale).rounded())
            let h = Int((img.size.height * img.scale).rounded())
            self.reportView.text = [
                "🔬 EXIF / ФАЙЛ-РЕНТГЕН",
                "────────────────────────",
                "Разрешение UIImage: \(w) × \(h) px",
                "",
                "⚠️ ВНИМАНИЕ: iOS передал перекодированный объект UIImage без ссылки на исходный файл (info[.imageURL] == nil).",
                "При таком выборе iOS не отдаёт сырые EXIF/GPS-байты файла (например, при ограниченном доступе к Фото или нескачанном оригинале iCloud).",
                "Чтобы проверить подлинный EXIF/GPS, открой оригинал файла в чате (отправленный «Как Файл») или предоставь доступ к оригиналу фото."
            ].joined(separator: "\n")
        }
    }

    private func inspectImageBytes(_ data: Data, sourceWarning: String?) {
        self.reportView.text = "🔬 Анализирую SHA-256 и EXIF-метаданные..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            var lines: [String] = [
                "🔬 EXIF / ФАЙЛ-РЕНТГЕН",
                "────────────────────────",
                "Размер: \(data.count) байт (\(String(format: "%.2f", Double(data.count) / 1024.0)) KB)",
                "SHA-256: \(sha.prefix(32))..."
            ]
            if let sourceWarning, !sourceWarning.isEmpty {
                lines.append("")
                lines.append(sourceWarning)
                lines.append("")
            }
            if let src = CGImageSourceCreateWithData(data as CFData, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
                if let w = props[kCGImagePropertyPixelWidth as String], let h = props[kCGImagePropertyPixelHeight as String] {
                    lines.append("Разрешение: \(w) × \(h) px")
                }
                if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                    if let make = tiff[kCGImagePropertyTIFFMake as String] { lines.append("Производитель: \(make)") }
                    if let model = tiff[kCGImagePropertyTIFFModel as String] { lines.append("Камера/Устройство: \(model)") }
                    if let sw = tiff[kCGImagePropertyTIFFSoftware as String] { lines.append("Софт / Редактор: \(sw)") }
                }
                if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                    if let dt = exif[kCGImagePropertyExifDateTimeOriginal as String] { lines.append("Дата съёмки: \(dt)") }
                    if let lens = exif[kCGImagePropertyExifLensModel as String] { lines.append("Объектив: \(lens)") }
                }
                if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any],
                   let rawLat = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
                   let rawLon = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue {
                    let latRef = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased() ?? "N"
                    let lonRef = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased() ?? "E"
                    let lat = latRef == "S" ? -abs(rawLat) : abs(rawLat)
                    let lon = lonRef == "W" ? -abs(rawLon) : abs(rawLon)
                    lines.append("⚠️ НАЙДЕНЫ GPS-КООРДИНАТЫ:")
                    lines.append(String(format: "Lat: %.6f (%@)  Lon: %.6f (%@)", lat, latRef, lon, lonRef))
                } else {
                    lines.append("🟢 GPS-метаданные отсутствуют (очищены).")
                }
            } else {
                lines.append("Метаданные EXIF не обнаружены.")
            }
            let report = lines.joined(separator: "\n")
            DispatchQueue.main.async {
                self?.reportView.text = report
            }
        }
    }

    private static func isPrivateIPv4(_ addr: in_addr) -> Bool {
        let ip = UInt32(bigEndian: addr.s_addr)
        let a = (ip >> 24) & 0xFF
        let b = (ip >> 16) & 0xFF
        if a == 0 || a == 10 || a == 127 { return true }
        if a == 169 && b == 254 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 192 && b == 168 { return true }
        if a == 100 && (64...127).contains(b) { return true }
        if a >= 224 { return true }
        return false
    }

    private static func isPrivateIPv6(_ addr: in6_addr) -> Bool {
        var copy = addr
        return withUnsafeBytes(of: &copy) { raw -> Bool in
            let b = raw.bindMemory(to: UInt8.self)
            let isAllZeroPrefix = (0..<15).allSatisfy { b[$0] == 0 }
            if isAllZeroPrefix && (b[15] == 0 || b[15] == 1) { return true } // :: or ::1
            if (b[0] & 0xFE) == 0xFC { return true }                         // fc00::/7 ULA
            if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }         // fe80::/10 link-local
            if b[0] == 0xFF { return true }                                  // ff00::/8 multicast
            if (0..<10).allSatisfy({ b[$0] == 0 }) && b[10] == 0xFF && b[11] == 0xFF {
                let v4 = in_addr(s_addr: UInt32(b[12]) | (UInt32(b[13]) << 8) | (UInt32(b[14]) << 16) | (UInt32(b[15]) << 24))
                return isPrivateIPv4(v4)
            }
            return false
        }
    }

    static func isBlockedOrPrivateHost(_ rawHost: String, resolveDNS: Bool = false) -> Bool {
        let stripped = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: "%", maxSplits: 1).first.map(String.init) ?? ""
        let host = stripped.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !host.isEmpty else { return true }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") {
            return true
        }
        var v4 = in_addr()
        if inet_aton(host, &v4) != 0 {
            return isPrivateIPv4(v4)
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 {
            return isPrivateIPv6(v6)
        }
        guard resolveDNS else { return false }
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return true }
        defer { freeaddrinfo(res) }
        var cur: UnsafeMutablePointer<addrinfo>? = first
        while let info = cur {
            if let sa = info.pointee.ai_addr {
                if sa.pointee.sa_family == sa_family_t(AF_INET) {
                    let sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    if isPrivateIPv4(sin.sin_addr) { return true }
                } else if sa.pointee.sa_family == sa_family_t(AF_INET6) {
                    let sin6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                    if isPrivateIPv6(sin6.sin6_addr) { return true }
                }
            }
            cur = info.pointee.ai_next
        }
        return false
    }

    private static func analyzeUrlHeuristics(_ url: URL) -> [String] {
        var found: [String] = []
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()
        if scheme != "http" && scheme != "https" {
            found.append("🔴 Недопустимая схема URL (\(scheme)) — разрешены только HTTP/HTTPS")
        }
        if isBlockedOrPrivateHost(host, resolveDNS: false) {
            found.append("🔴 Локальный или приватный IP/хост (\(host)) — запрос заблокирован (защита от SSRF)")
        }
        if url.user != nil || url.password != nil {
            found.append("🔴 Символ @ / userinfo в authority URL (классический приём маскировки фишингового домена!)")
        }
        if host.contains("xn--") {
            found.append("🔴 Punycode / IDN-домен (\(host) — возможен фишинг-спуфинг букв!)")
        }
        if scheme == "http" {
            found.append("🟡 Незащищённый HTTP без TLS (\(host))")
        }
        let suspiciousTlds = [".xyz", ".top", ".click", ".gq", ".tk", ".ml", ".cf", ".zip"]
        if suspiciousTlds.contains(where: { host.hasSuffix($0) }) {
            found.append("🟡 Подозрительная доменная зона (\(host))")
        }
        if host.split(separator: ".").count >= 4 {
            found.append("🟡 Много уровней поддоменов (\(host))")
        }
        if let ipLogger = MTMediaTokCoreLogic.detectIpLoggerHost(text: url.absoluteString, extraUrls: [url.absoluteString]) {
            found.append("🔴 ОБНАРУЖЕН IP-LOGGER ДОМЕН: \(ipLogger) (сетевой запрос заблокирован для защиты твоего IP)")
        }
        return found
    }

    @objc private func scanUrlTapped() {
        let raw = (self.urlField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let startUrl = URL(string: raw.contains("://") ? raw : "https://\(raw)"),
              let scheme = startUrl.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let startHost = startUrl.host, !startHost.isEmpty else {
            self.reportView.text = "Некорректный URL (поддерживаются только http:// и https:// ссылки)."
            return
        }

        let initialCheck = Self.analyzeUrlHeuristics(startUrl)
        let isStartIpLogger = MTMediaTokCoreLogic.detectIpLoggerHost(text: startUrl.absoluteString, extraUrls: [startUrl.absoluteString]) != nil
        if Self.isBlockedOrPrivateHost(startHost, resolveDNS: false) || isStartIpLogger {
            self.reportView.text = ([
                "🔬 OSINT-РЕНТГЕН ССЫЛКИ",
                "────────────────────────",
                "Исходный URL: \(startUrl.absoluteString)",
                "Хост: \(startHost)",
                "",
                "⚠️ ПРЕДУПРЕЖДЕНИЯ:"
            ] + initialCheck).joined(separator: "\n")
            return
        }

        self.reportView.text = "🔬 Проверяю цепочку редиректов для \(startUrl.absoluteString)..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            cfg.httpCookieAcceptPolicy = .never
            cfg.timeoutIntervalForRequest = 8.0
            cfg.timeoutIntervalForResource = 15.0
            let delegate = MTNoRedirectSessionDelegate()
            let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }

            var currentUrl = startUrl
            var hops: [String] = [startUrl.absoluteString]
            var allWarnings: [String] = []
            for w in initialCheck where !allWarnings.contains(w) {
                allWarnings.append(w)
            }
            var lastStatusCode: Int?
            var errorMessage: String?
            let maxRedirects = 5

            for hopIndex in 0 ... maxRedirects {
                if Self.isBlockedOrPrivateHost(currentUrl.host ?? "", resolveDNS: true) {
                    errorMessage = "Заблокирован переход на приватный/локальный адрес (\(currentUrl.host ?? ""))"
                    break
                }
                if let ipLog = MTMediaTokCoreLogic.detectIpLoggerHost(text: currentUrl.absoluteString, extraUrls: [currentUrl.absoluteString]) {
                    errorMessage = "Остановлено: домен является IP-логгером (\(ipLog)) — запрос не отправлен"
                    break
                }
                var req = URLRequest(url: currentUrl, timeoutInterval: 8.0)
                req.httpMethod = "HEAD"
                req.setValue("MediaTok-OSINT/1.0", forHTTPHeaderField: "User-Agent")

                let sem = DispatchSemaphore(value: 0)
                let resultBox = MTWave12LockedBox<(URLResponse?, Error?)>((nil, nil))
                let task = session.dataTask(with: req) { _, resp, err in
                    resultBox.withLock { $0 = (resp, err) }
                    sem.signal()
                }
                task.resume()
                if sem.wait(timeout: .now() + 10.0) == .timedOut {
                    task.cancel()
                    errorMessage = "Таймаут ответа сервера (10с)"
                    break
                }
                let (snapResp, snapErr) = resultBox.withLock { $0 }

                if let snapErr {
                    errorMessage = snapErr.localizedDescription
                    break
                }
                guard let http = snapResp as? HTTPURLResponse else {
                    errorMessage = "Нет HTTP-ответа"
                    break
                }
                lastStatusCode = http.statusCode

                if (300...399).contains(http.statusCode),
                   let loc = http.value(forHTTPHeaderField: "Location"),
                   let nextUrl = URL(string: loc, relativeTo: currentUrl)?.absoluteURL {
                    let nextScheme = (nextUrl.scheme ?? "").lowercased()
                    guard nextScheme == "http" || nextScheme == "https" else {
                        allWarnings.append("🔴 Редирект на небезопасную схему: \(nextUrl.absoluteString)")
                        break
                    }
                    hops.append(nextUrl.absoluteString)
                    allWarnings.append("🟡 Редирект #\(hopIndex + 1) (\(http.statusCode)) → \(nextUrl.host ?? nextUrl.absoluteString)")
                    for w in Self.analyzeUrlHeuristics(nextUrl) where !allWarnings.contains(w) {
                        allWarnings.append(w)
                    }
                    if MTMediaTokCoreLogic.detectIpLoggerHost(text: nextUrl.absoluteString, extraUrls: [nextUrl.absoluteString]) != nil {
                        errorMessage = "Остановлено перед переходом на IP-логгер (\(nextUrl.host ?? ""))"
                        break
                    }
                    if hopIndex == maxRedirects {
                        allWarnings.append("🟡 Достигнут лимит редиректов (\(maxRedirects))")
                        currentUrl = nextUrl
                        break
                    }
                    currentUrl = nextUrl
                } else {
                    break
                }
            }

            var lines: [String] = [
                "🔬 OSINT-РЕНТГЕН ССЫЛКИ",
                "────────────────────────",
                "Исходный URL: \(startUrl.absoluteString)",
                "Хост: \(startHost.lowercased())"
            ]
            if let lastStatusCode {
                lines.append("HTTP код: \(lastStatusCode)")
            }
            if let errorMessage {
                lines.append("Статус запроса: Ошибка (\(errorMessage))")
            }
            lines.append("Финальный URL: \(currentUrl.absoluteString)")
            if hops.count > 1 {
                lines.append("Цепочка переходов (\(hops.count)):")
                for (idx, h) in hops.enumerated() {
                    lines.append("  [\(idx)] \(h)")
                }
            }
            lines.append("")
            if allWarnings.isEmpty {
                lines.append("🟢 ВЕРДИКТ: Ссылка выглядит чистой, явных признаков фишинга не найдено.")
            } else {
                lines.append("⚠️ ПРЕДУПРЕЖДЕНИЯ:")
                lines.append(contentsOf: allWarnings)
            }
            let report = lines.joined(separator: "\n")
            DispatchQueue.main.async {
                self?.reportView.text = report
            }
        }
    }

    @objc private func copyReportTapped() {
        UIPasteboard.general.string = self.reportView.text
        MTMediaTokWave5Tools.showToast(context: self.context, text: "📋 Отчёт скопирован")
    }
}
