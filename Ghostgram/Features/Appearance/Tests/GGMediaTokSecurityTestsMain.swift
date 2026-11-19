import Foundation
import CryptoKit
import CoreText

@main
enum GGMediaTokSecurityTestsMain {
    private static var passed = 0
    private static var failed = 0

    static func main() {
        Self.run("MathSafetyAndPrecedence", Self.testMathSafetyAndPrecedence)
        Self.run("LangFormatStringSafety", Self.testLangFormatStringSafety)
        Self.run("CatboxHostAllowlist", Self.testCatboxHostAllowlist)
        Self.run("SteamUrlSanitization", Self.testSteamUrlSanitization)
        Self.run("IpLoggerHiddenTextUrlDetection", Self.testIpLoggerHiddenTextUrlDetection)
        Self.run("E2EV2PBKDF2AndCrossChatReplay", Self.testE2EV2PBKDF2AndCrossChatReplay)
        Self.run("AudioGuardPcmVerdicts", Self.testAudioGuardPcmVerdicts)
        Self.run("CyrillicTtfCoreTextValidation", Self.testCyrillicTtfCoreTextValidation)

        print("MediaTok Security Tests Summary: \(Self.passed) passed, \(Self.failed) failed")
        if Self.failed > 0 {
            exit(1)
        }
    }

    private static func run(_ name: String, _ block: () -> Void) {
        let beforeFailed = Self.failed
        block()
        if Self.failed == beforeFailed {
            Self.passed += 1
            print("[PASS] \(name)")
        } else {
            print("[FAIL] \(name)")
        }
    }

    private static func check(_ condition: Bool, _ msg: String) {
        if !condition {
            Self.failed += 1
            print("  Assertion failed: \(msg)")
        }
    }

    private static func testMathSafetyAndPrecedence() {
        let v1 = GGMediaTokCoreLogic.evaluateMath("2+2*10")
        Self.check(v1 != nil && abs((v1 ?? 0) - 22.0) < 1e-9, "2+2*10 should equal 22")

        let v2 = GGMediaTokCoreLogic.evaluateMath("-2^2")
        Self.check(v2 != nil && abs((v2 ?? 0) - (-4.0)) < 1e-9, "-2^2 must equal -4, got \(String(describing: v2))")

        let v3 = GGMediaTokCoreLogic.evaluateMath("2^-3")
        Self.check(v3 != nil && abs((v3 ?? 0) - 0.125) < 1e-9, "2^-3 must equal 0.125, got \(String(describing: v3))")

        Self.check(GGMediaTokCoreLogic.evaluateMath("1/0") == nil, "division by zero must return nil")

        let deepParens = String(repeating: "(", count: 300) + "1" + String(repeating: ")", count: 300)
        Self.check(GGMediaTokCoreLogic.evaluateMath(deepParens) == nil, "deeply nested parens must return nil without stack overflow")
    }

    private static func testLangFormatStringSafety() {
        Self.check(!GGMediaTokCoreLogic.isFormatSafe(original: "В сети", candidate: "%s%s%s"), "must reject %s%s%s")
        Self.check(!GGMediaTokCoreLogic.isFormatSafe(original: "Был в %@", candidate: "%@ и %@"), "must reject mismatched arg count")
        Self.check(!GGMediaTokCoreLogic.isFormatSafe(original: "Число %d", candidate: "Число %n"), "must reject %n")
        Self.check(GGMediaTokCoreLogic.isFormatSafe(original: "Был в %@", candidate: "умер в %@"), "valid %@ override allowed")
        Self.check(GGMediaTokCoreLogic.isFormatSafe(original: "В сети", candidate: "100% онлайн"), "bare percent literal allowed")
    }

    private static func testCatboxHostAllowlist() {
        Self.check(GGMediaTokCoreLogic.isAllowedMediaURL("https://files.catbox.moe/abc123.jpg") != nil, "valid catbox URL allowed")
        Self.check(GGMediaTokCoreLogic.isAllowedMediaURL("http://files.catbox.moe/abc123.jpg") == nil, "http scheme must be rejected")
        Self.check(GGMediaTokCoreLogic.isAllowedMediaURL("https://evil.example/logger.png") == nil, "arbitrary host must be rejected")
        Self.check(GGMediaTokCoreLogic.isAllowedMediaURL("https://files.catbox.moe.evil.com/a.jpg") == nil, "lookalike domain must be rejected")
        Self.check(GGMediaTokCoreLogic.isAllowedMediaURL("https://files.catbox.moe/../secret") == nil, "path traversal must be rejected")
        Self.check(GGMediaTokCoreLogic.isAllowedMediaURL("https://user@files.catbox.moe/a.jpg") == nil, "embedded userinfo must be rejected")
    }

    private static func testSteamUrlSanitization() {
        Self.check(GGMediaTokCoreLogic.normalizeSteam("gaben")?.cleanLabel == "gaben", "vanity slug allowed")
        Self.check(GGMediaTokCoreLogic.normalizeSteam("76561197960287930")?.profileUrl.absoluteString == "https://steamcommunity.com/profiles/76561197960287930", "SteamID64 allowed")
        Self.check(GGMediaTokCoreLogic.normalizeSteam("https://steamcommunity.com/id/gaben/")?.xmlUrl.absoluteString == "https://steamcommunity.com/id/gaben?xml=1", "full Steam URL normalized")
        Self.check(GGMediaTokCoreLogic.normalizeSteam("id/../../../evil") == nil, "traversal slug rejected")
        Self.check(GGMediaTokCoreLogic.normalizeSteam("foo@evil.com") == nil, "userinfo injection rejected")
        Self.check(GGMediaTokCoreLogic.normalizeSteam("profiles/notdigits") == nil, "invalid profile id rejected")
    }

    private static func testIpLoggerHiddenTextUrlDetection() {
        Self.check(GGMediaTokCoreLogic.detectIpLoggerHost(text: "смотри сюда https://grabify.link/XYZ", extraUrls: []) == "grabify.link", "plain text grabify detected")
        Self.check(GGMediaTokCoreLogic.detectIpLoggerHost(text: "Забери Telegram Premium бесплатно", extraUrls: ["https://sub.iplogger.org/track1"]) == "iplogger.org", "hidden TextUrl IP logger detected")
        Self.check(GGMediaTokCoreLogic.detectIpLoggerHost(text: "обычная ссылка https://example.com/grabify_fake", extraUrls: []) == nil, "safe host substring must not false-positive")
    }

    private static func testE2EV2PBKDF2AndCrossChatReplay() {
        // Verify RFC 7914 / RFC 6070 PBKDF2-HMAC-SHA256 test vector ("password", "salt", c=1, dkLen=32)
        if let rfcKey = GGMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: "password", salt: Data("salt".utf8), iterations: 1) {
            let hex = rfcKey.withUnsafeBytes { raw in
                raw.map { String(format: "%02x", $0) }.joined()
            }
            Self.check(hex == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", "PBKDF2-HMAC-SHA256 RFC vector mismatch: \(hex)")
        } else {
            Self.check(false, "RFC PBKDF2 vector returned nil")
        }

        let msg = "Секретное сообщение MediaTok 🔐🔥"
        let pass = "strong_pass_2026"
        let peerA = "0_111111"
        let peerB = "0_222222"

        guard let ct = GGMediaTokCoreLogic.encryptV2(msg, passphrase: pass, peerKey: peerA) else {
            Self.check(false, "encryptV2 returned nil")
            return
        }
        Self.check(ct.hasPrefix(GGMediaTokCoreLogic.prefixV2), "must use v2 prefix")
        Self.check(GGMediaTokCoreLogic.decryptAny(ct, passphrase: pass, peerKey: peerA) == msg, "decrypt round-trip must succeed")
        Self.check(GGMediaTokCoreLogic.decryptAny(ct, passphrase: "wrong", peerKey: peerA) == nil, "wrong passphrase must fail")
        Self.check(GGMediaTokCoreLogic.decryptAny(ct, passphrase: pass, peerKey: peerB) == nil, "cross-chat replay must fail AAD check")

        // Verify backward compatibility with legacy v1 ciphertext
        let v1Key = SymmetricKey(data: SHA256.hash(data: Data("MediaTokE2E:v1:\(pass)".utf8)))
        if let sealed = try? AES.GCM.seal(Data(msg.utf8), using: v1Key),
           let combined = sealed.combined {
            let b64 = combined.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let legacy = GGMediaTokCoreLogic.prefixV1 + b64
            Self.check(GGMediaTokCoreLogic.decryptAny(legacy, passphrase: pass, peerKey: peerA) == msg, "legacy v1 decrypt compatibility preserved")
        } else {
            Self.check(false, "failed constructing legacy v1 test vector")
        }
    }

    private static func testAudioGuardPcmVerdicts() {
        let sr = 16000
        let n = sr * 4

        // 1. Normal speech (~0.18 peak, paused cadence) -> clean
        var speech = [Int16](repeating: 0, count: n)
        for i in 0 ..< n {
            let env = 0.5 + 0.5 * sin(2.0 * Double.pi * 3.5 * Double(i) / Double(sr))
            let val = 6500.0 * sin(2.0 * Double.pi * 210.0 * Double(i) / Double(sr)) * env
            speech[i] = Int16(max(-32767.0, min(32767.0, val)))
        }
        Self.check(GGMediaTokCoreLogic.analyzeAudioPcm16k(speech) == .clean, "normal speech must be clean")

        // 2. Loud music (~0.50 peak across mixed bands, low clipping) -> clean
        var music = [Int16](repeating: 0, count: n)
        for i in 0 ..< n {
            let val = 15000.0 * sin(2.0 * Double.pi * 90.0 * Double(i) / Double(sr))
                + 8000.0 * sin(2.0 * Double.pi * 650.0 * Double(i) / Double(sr))
                + 3500.0 * sin(2.0 * Double.pi * 2800.0 * Double(i) / Double(sr))
            music[i] = Int16(max(-32767.0, min(32767.0, val)))
        }
        Self.check(GGMediaTokCoreLogic.analyzeAudioPcm16k(music) == .clean, "normal loud music must be clean")

        // 3. Screamer jump -> loudScreamer
        var screamer = [Int16](repeating: 0, count: n)
        for i in 0 ..< n {
            let raw = (i < sr)
                ? 1800.0 * sin(2.0 * Double.pi * 200.0 * Double(i) / Double(sr))
                : 45000.0 * sin(2.0 * Double.pi * 1800.0 * Double(i) / Double(sr))
            screamer[i] = Int16(max(-32767.0, min(32767.0, raw)))
        }
        Self.check(GGMediaTokCoreLogic.analyzeAudioPcm16k(screamer) == .loudScreamer, "screamer must trigger loudScreamer")

        // 4. Rhythmic moan prank (720 Hz bursts at 1.8 Hz) -> moanPrank
        var moan = [Int16](repeating: 0, count: n)
        for i in 0 ..< n {
            let amp = (sin(2.0 * Double.pi * 1.8 * Double(i) / Double(sr)) > 0.15) ? 26000.0 : 1500.0
            let val = amp * sin(2.0 * Double.pi * 720.0 * Double(i) / Double(sr))
            moan[i] = Int16(max(-32767.0, min(32767.0, val)))
        }
        Self.check(GGMediaTokCoreLogic.analyzeAudioPcm16k(moan) == .moanPrank, "moan signature must trigger moanPrank")
    }

    private static func sfntChecksum(_ data: Data) -> UInt32 {
        var sum: UInt32 = 0
        let n = data.count
        var i = 0
        while i < n {
            let b0 = UInt32(data[i]) << 24
            let b1 = (i + 1 < n) ? (UInt32(data[i + 1]) << 16) : 0
            let b2 = (i + 2 < n) ? (UInt32(data[i + 2]) << 8) : 0
            let b3 = (i + 3 < n) ? UInt32(data[i + 3]) : 0
            sum = sum &+ (b0 | b1 | b2 | b3)
            i += 4
        }
        return sum
    }

    private static func testCyrillicTtfCoreTextValidation() {
        var grid = [Bool](repeating: false, count: 10 * 12)
        for r in 2 ... 9 {
            grid[r * 10 + 3] = true
            grid[r * 10 + 6] = true
        }
        for c in 3 ... 6 {
            grid[2 * 10 + c] = true
            grid[5 * 10 + c] = true
        }
        let grids: [Character: [Bool]] = ["А": grid, "A": grid]

        let data1 = GGMediaTokCoreLogic.compileTtf(fontNameRaw: "Мой Шрифт", grids: grids, pixelStyle: 0, uniqueTag: "1111")
        let data2 = GGMediaTokCoreLogic.compileTtf(fontNameRaw: "Крутой Шрифт", grids: grids, pixelStyle: 1, uniqueTag: "2222")

        Self.check(Self.sfntChecksum(data1) == 0xB1B0AFBA, "SFNT checksum for TTF #1 must equal 0xB1B0AFBA")
        Self.check(Self.sfntChecksum(data2) == 0xB1B0AFBA, "SFNT checksum for TTF #2 must equal 0xB1B0AFBA")

        let u1 = FileManager.default.temporaryDirectory.appendingPathComponent("mt_test_1_\(UUID().uuidString).ttf")
        let u2 = FileManager.default.temporaryDirectory.appendingPathComponent("mt_test_2_\(UUID().uuidString).ttf")
        defer {
            try? FileManager.default.removeItem(at: u1)
            try? FileManager.default.removeItem(at: u2)
        }
        do {
            try data1.write(to: u1, options: .atomic)
            try data2.write(to: u2, options: .atomic)
        } catch {
            Self.check(false, "failed writing temp TTF files")
            return
        }

        guard let descList1 = CTFontManagerCreateFontDescriptorsFromURL(u1 as CFURL) as? [CTFontDescriptor],
              let d1 = descList1.first,
              let descList2 = CTFontManagerCreateFontDescriptorsFromURL(u2 as CFURL) as? [CTFontDescriptor],
              let d2 = descList2.first else {
            Self.check(false, "CoreText failed loading compiled TTF files")
            return
        }

        let fam1 = CTFontDescriptorCopyAttribute(d1, kCTFontFamilyNameAttribute) as? String ?? ""
        let fam2 = CTFontDescriptorCopyAttribute(d2, kCTFontFamilyNameAttribute) as? String ?? ""
        let ps1 = CTFontDescriptorCopyAttribute(d1, kCTFontNameAttribute) as? String ?? ""
        let ps2 = CTFontDescriptorCopyAttribute(d2, kCTFontNameAttribute) as? String ?? ""

        Self.check(fam1 == "Мой Шрифт", "TTF #1 CoreText family must preserve Cyrillic, got '\(fam1)'")
        Self.check(fam2 == "Крутой Шрифт", "TTF #2 CoreText family must preserve Cyrillic, got '\(fam2)'")
        Self.check(!ps1.isEmpty && !ps1.contains("?"), "PostScript name #1 must be valid ASCII, got '\(ps1)'")
        Self.check(!ps2.isEmpty && !ps2.contains("?"), "PostScript name #2 must be valid ASCII, got '\(ps2)'")
        Self.check(ps1 != ps2, "Two Cyrillic fonts must receive unique PostScript names (\(ps1) vs \(ps2))")
    }
}
