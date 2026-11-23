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
        Self.run("StickerVaultSearchAndTranslit", Self.testStickerVaultSearchAndTranslit)
        Self.run("MaliciousDocumentAndRloInspector", Self.testMaliciousDocumentAndRloInspector)
        Self.run("ChatStreaksAndFreezeShields", Self.testChatStreaksAndFreezeShields)
        Self.run("CardCommandParser", Self.testCardCommandParser)
        Self.run("MusicAndConnectionsParsers", Self.testMusicAndConnectionsParsers)
        Self.run("LanUploaderSanitizers", Self.testLanUploaderSanitizers)
        Self.run("ScratchCommandParser", Self.testScratchCommandParser)
        Self.run("KeyboardLayoutFixer", Self.testKeyboardLayoutFixer)
        Self.run("AchievementEvaluation", Self.testAchievementEvaluation)
        Self.run("WatermarkFormatter", Self.testWatermarkFormatter)
        Self.run("BottomBarPresets", Self.testBottomBarPresets)
        Self.run("MinesweeperCoreEngine", Self.testMinesweeperCoreEngine)
        Self.run("AntiPhishingAndHomographDetector", Self.testAntiPhishingAndHomographDetector)
        Self.run("QrCommandParser", Self.testQrCommandParser)
        Self.run("ChannelAdBlockerFilter", Self.testChannelAdBlockerFilter)
        Self.run("WheelCommandParser", Self.testWheelCommandParser)
        Self.run("PollCommandParser", Self.testPollCommandParser)
        Self.run("SplitBillParser", Self.testSplitBillParser)
        Self.run("TimeCapsuleParser", Self.testTimeCapsuleParser)
        Self.run("MoodAndWishParsers", Self.testMoodAndWishParsers)
        Self.run("ScratchWireCodecAndSnippets", Self.testScratchWireCodecAndSnippets)
        Self.run("PrefixPayloadsAndJsonPrettyPrint", Self.testPrefixPayloadsAndJsonPrettyPrint)
        Self.run("CloudBackupCodec", Self.testCloudBackupCodec)

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

    private static func testStickerVaultSearchAndTranslit() {
        let entries: [GGMediaTokCoreLogic.StickerEntry] = [
            .init(id: "1", fileName: "mellstroy_dance.webp", tags: ["mellstroy", "казино", "мем"], ocrText: "ДЕНЬГИ СЮДА", visionLabels: ["person"], addedAt: 100, usageCount: 15),
            .init(id: "2", fileName: "gojo.webp", tags: ["anime", "jjk", "годжо"], ocrText: "", visionLabels: ["cartoon", "аниме"], addedAt: 200, usageCount: 4),
            .init(id: "3", fileName: "cat_sad.webp", tags: ["грустный"], ocrText: "плачу", visionLabels: ["cat", "кот"], addedAt: 300, usageCount: 20)
        ]

        let mell = GGMediaTokCoreLogic.searchStickers(entries, query: "меллстрой")
        Self.check(mell.first?.id == "1", "Cyrillic 'меллстрой' must find Latin 'mellstroy' via translit")

        let narutoStyle = GGMediaTokCoreLogic.searchStickers(entries, query: "аниме")
        Self.check(narutoStyle.first?.id == "2", "Russian 'аниме' must match anime sticker")

        let catOcr = GGMediaTokCoreLogic.searchStickers(entries, query: "плачу")
        Self.check(catOcr.first?.id == "3", "OCR text search must match 'плачу'")

        let visionMap = GGMediaTokCoreLogic.visionLabelToRussianTags("domestic_cat")
        Self.check(visionMap.contains("кот"), "Vision label mapping must include Russian tag 'кот'")
    }

    private static func testMaliciousDocumentAndRloInspector() {
        Self.check(GGMediaTokCoreLogic.inspectIncomingDocument(fileName: "report.pdf", mimeType: "application/pdf") == nil, "normal PDF is safe")

        let rlo = GGMediaTokCoreLogic.inspectIncomingDocument(fileName: "photo_\u{202E}gpj.exe", mimeType: "application/octet-stream")
        Self.check(rlo?.isCritical == true, "RLO BiDi filename spoofing must be flagged critical")

        let doubleExt = GGMediaTokCoreLogic.inspectIncomingDocument(fileName: "nude.jpg.exe", mimeType: "application/octet-stream")
        Self.check(doubleExt?.isCritical == true, "double extension .jpg.exe must be flagged critical")

        let apkMime = GGMediaTokCoreLogic.inspectIncomingDocument(fileName: "update.bin", mimeType: "application/vnd.android.package-archive")
        Self.check(apkMime?.isCritical == true, "APK MIME type must trigger threat alert")
    }

    private static func testChatStreaksAndFreezeShields() {
        let day1 = GGMediaTokCoreLogic.applyStreakActivity(record: nil, dayKey: "2026-11-01", monthKey: "2026-11")
        Self.check(day1.updated.currentStreak == 1 && day1.updated.freezesRemaining == 2, "Day 1 initializes streak=1 and 2 freezes")

        let day2 = GGMediaTokCoreLogic.applyStreakActivity(record: day1.updated, dayKey: "2026-11-02", monthKey: "2026-11")
        Self.check(day2.updated.currentStreak == 2 && !day2.usedFreeze, "Consecutive day increments streak without freeze")

        let skippedOneDay = GGMediaTokCoreLogic.applyStreakActivity(record: day2.updated, dayKey: "2026-11-04", monthKey: "2026-11")
        Self.check(skippedOneDay.updated.currentStreak == 3 && skippedOneDay.usedFreeze && skippedOneDay.updated.freezesRemaining == 1, "Missed 1 day spends freeze and keeps streak")

        let missedMany = GGMediaTokCoreLogic.applyStreakActivity(record: skippedOneDay.updated, dayKey: "2026-11-10", monthKey: "2026-11")
        Self.check(missedMany.updated.currentStreak == 1 && missedMany.updated.bestStreak == 3, "Missed >2 days resets streak to 1 preserving bestStreak")

        let nextMonth = GGMediaTokCoreLogic.applyStreakActivity(record: missedMany.updated, dayKey: "2026-12-01", monthKey: "2026-12")
        Self.check(nextMonth.updated.freezesRemaining == 2, "New month resets freezesRemaining back to 2")
        Self.check(GGMediaTokCoreLogic.streakTierBadge(days: 365) == "🌈", "365d tier badge must be rainbow")
    }

    private static func testCardCommandParser() {
        let card = GGMediaTokCoreLogic.parseCardCommand(".card MediaTok | iOS 27 Pro | Версия 5.0 | 4K 60fps")
        Self.check(card?.title == "MediaTok", "card title parsed")
        Self.check(card?.subtitle == "iOS 27 Pro", "card subtitle parsed")
        Self.check(card?.lines.count == 2, "card body lines parsed")
        Self.check(GGMediaTokCoreLogic.parseCardCommand(".card    ") == nil, "empty card command returns nil")
    }

    private static func testMusicAndConnectionsParsers() {
        let lbJson = Data("""
        {"payload":{"playing_now":true,"listens":[{"playing_now":true,"track_metadata":{"artist_name":"Miyagi & Andy Panda","track_name":"Kosandra"}}]}}
        """.utf8)
        let lb = GGMediaTokCoreLogic.parseListenBrainzJson(lbJson)
        Self.check(lb?.artist == "Miyagi & Andy Panda" && lb?.track == "Kosandra" && lb?.isLive == true, "ListenBrainz playing-now parsed")

        let lastFmHtml = """
        <table><tbody><tr class="chartlist-row chartlist-now-scrobbling"><td class="chartlist-name"><a href="/track">Nightcall</a></td><td class="chartlist-artist"><a href="/artist">Kavinsky</a></td></tr></tbody></table>
        """
        let lf = GGMediaTokCoreLogic.parseLastFmHtml(lastFmHtml)
        Self.check(lf?.artist == "Kavinsky" && lf?.track == "Nightcall" && lf?.isLive == true, "Last.fm HTML now playing parsed")

        Self.check(GGMediaTokCoreLogic.normalizeConnection(platform: "twitch", raw: "https://www.twitch.tv/s1mple")?.handle == "s1mple", "Twitch URL normalized")
        Self.check(GGMediaTokCoreLogic.normalizeConnection(platform: "github", raw: "../../../etc/passwd") == nil, "GitHub traversal rejected")
        Self.check(GGMediaTokCoreLogic.normalizeConnection(platform: "youtube", raw: "user@evil.com") == nil, "YouTube userinfo injection rejected")
    }

    private static func testLanUploaderSanitizers() {
        Self.check(GGMediaTokCoreLogic.sanitizeUploadFileName("../../etc/passwd\0.png") == "passwd.png", "path traversal & null stripped")
        Self.check(GGMediaTokCoreLogic.constantTimeEquals("4829", "4829"), "constantTimeEquals matches identical PIN")
        Self.check(!GGMediaTokCoreLogic.constantTimeEquals("4829", "4820"), "constantTimeEquals rejects mismatched PIN")
    }

    private static func testScratchCommandParser() {
        let p1 = GGMediaTokCoreLogic.parseScratchCommand(".scratch Секретный промокод | MT-2026-DEMO")
        Self.check(p1?.title == "Секретный промокод" && p1?.secret == "MT-2026-DEMO", "Scratch command with title and secret parsed")
        Self.check(p1?.seed != 0, "Scratch seed must be non-zero")

        let p2 = GGMediaTokCoreLogic.parseScratchCommand(".scratch Только для тебя!")
        Self.check(p2?.title == "Секретный билет 🎟️" && p2?.secret == "Только для тебя!", "Scratch command default title parsed")
        Self.check(GGMediaTokCoreLogic.parseScratchCommand(".scratch") == nil, "Empty scratch command returns nil")
    }

    private static func testKeyboardLayoutFixer() {
        let fixed1 = GGMediaTokCoreLogic.fixKeyboardLayout("ghbdtn rfr ltkf")
        Self.check(fixed1 == "привет как дела", "QWERTY to JCUKEN converted correctly: \(fixed1)")

        let fixed2 = GGMediaTokCoreLogic.fixKeyboardLayout("Ghbdtn!")
        Self.check(fixed2 == "Привет!", "QWERTY with caps and punctuation converted correctly: \(fixed2)")

        let fixedRu = GGMediaTokCoreLogic.fixKeyboardLayout("руддщ цщкдв")
        Self.check(fixedRu == "hello world", "JCUKEN to QWERTY converted correctly: \(fixedRu)")

        Self.check(GGMediaTokCoreLogic.parseFixCommand(".fix ghbdtn") == "привет", ".fix command parsed")
        Self.check(GGMediaTokCoreLogic.parseFixCommand(".ghbdtn rfr") == "как", ".ghbdtn command parsed")
    }

    private static func testAchievementEvaluation() {
        let unlockedSet: Set<String> = [
            GGMediaTokCoreLogic.AchievementId.mediatokOg.rawValue,
            GGMediaTokCoreLogic.AchievementId.nightOwl.rawValue,
            GGMediaTokCoreLogic.AchievementId.streak7d.rawValue,
            GGMediaTokCoreLogic.AchievementId.e2eMaster.rawValue
        ]
        let eval = GGMediaTokCoreLogic.evaluateAchievements(unlockedIds: unlockedSet)
        Self.check(eval.unlocked.count == 4, "4 achievements unlocked")
        Self.check(eval.locked.count == 8, "8 achievements locked")
        Self.check(eval.tier == "Энтузиаст 🥈", "Tier evaluated as Энтузиаст 🥈")
    }

    private static func testWatermarkFormatter() {
        let wm = GGMediaTokCoreLogic.formatWatermarkText(recipient: "durov\nadmin", date: Date(timeIntervalSince1970: 1795171200))
        Self.check(wm.contains("Для @durov admin"), "Recipient control chars replaced with space")
        Self.check(wm.contains("MediaTok"), "Default app tag present in watermark")
    }

    private static func testBottomBarPresets() {
        let standard = GGMediaTokCoreLogic.BottomTabPreset.standard
        Self.check(standard.hiddenTabs.isEmpty && !standard.isWide, "Standard preset has no hidden tabs")

        let minimal = GGMediaTokCoreLogic.BottomTabPreset.minimal
        Self.check(minimal.hiddenTabs.contains("calls") && minimal.hiddenTabs.contains("contacts"), "Minimal preset hides calls and contacts")

        let mediaHub = GGMediaTokCoreLogic.BottomTabPreset.mediaHub
        Self.check(mediaHub.isWide, "Media hub preset uses wide tab bar")
    }

    private static func testMinesweeperCoreEngine() {
        var game = GGMediaTokCoreLogic.MinesweeperGame()
        Self.check(!game.hasStarted && !game.isGameOver && !game.isWon, "New game is not started")

        // First click is always safe
        game.reveal(at: 0)
        Self.check(game.hasStarted, "Game started after first reveal")
        Self.check(!game.isGameOver, "First click at index 0 is guaranteed safe")
        Self.check(game.grid[0].isRevealed, "Clicked cell is revealed")

        // Test flag toggle
        game.toggleFlag(at: 10)
        Self.check(game.grid[10].isFlagged, "Cell 10 flagged")
        game.toggleFlag(at: 10)
        Self.check(!game.grid[10].isFlagged, "Cell 10 unflagged")
    }

    private static func testAntiPhishingAndHomographDetector() {
        // Homograph attack (Cyrillic 'e' in telegram)
        let homo = GGMediaTokCoreLogic.inspectUrlForPhishing("https://t\u{0435}l\u{0435}gram.org/login")
        Self.check(homo.isSuspicious, "Homograph spoofing detected")

        // Suspicious TLD (.xyz)
        let xyz = GGMediaTokCoreLogic.inspectUrlForPhishing("https://free-telegram-stars.xyz/claim")
        Self.check(xyz.isSuspicious, "Suspicious .xyz TLD detected")

        // Telegram spoof name (te1egram)
        let sp = GGMediaTokCoreLogic.inspectUrlForPhishing("https://te1egram-gift.com")
        Self.check(sp.isSuspicious, "Telegram spoofing detected")

        // Legitimate domain
        let ok = GGMediaTokCoreLogic.inspectUrlForPhishing("https://telegram.org")
        Self.check(!ok.isSuspicious, "Legitimate domain is not marked suspicious")
    }

    private static func testQrCommandParser() {
        Self.check(GGMediaTokCoreLogic.parseQrCommand(".qr https://github.com") == "https://github.com", ".qr link parsed")
        Self.check(GGMediaTokCoreLogic.parseQrCommand(".qr ") == nil, "empty .qr returns nil")
    }

    private static func testChannelAdBlockerFilter() {
        let ad1 = "Купить курсы со скидкой 50%! erid: 2Vtzqw73b"
        Self.check(GGMediaTokCoreLogic.isChannelAdPost(ad1), "Post with erid is identified as ad")

        let ad2 = "Свежие новости мира IT. #реклама"
        Self.check(GGMediaTokCoreLogic.isChannelAdPost(ad2), "Post with #реклама is identified as ad")

        let normal = "Вышло обновление клиента MediaTok iOS 13.1.1!"
        Self.check(!GGMediaTokCoreLogic.isChannelAdPost(normal), "Normal post is not identified as ad")
    }

    private static func testWheelCommandParser() {
        let w = GGMediaTokCoreLogic.parseWheelCommand(".wheel Пицца | Суши | Бургер")
        Self.check(w?.count == 3 && w?[0] == "Пицца", "Wheel options parsed")
        Self.check(GGMediaTokCoreLogic.parseWheelCommand(".wheel Пицца") == nil, "Wheel requires at least 2 options")
    }

    private static func testPollCommandParser() {
        let p = GGMediaTokCoreLogic.parsePollCommand(".poll Где встретимся? | Центр | Парк | Кафе")
        Self.check(p?.question == "Где встретимся?" && p?.options.count == 3, "Poll question and options parsed")
        Self.check(GGMediaTokCoreLogic.parsePollCommand(".poll Только вопрос | Один") == nil, "Poll requires question and at least 2 options")
    }

    private static func testSplitBillParser() {
        let s = GGMediaTokCoreLogic.parseSplitBillCommand(".split 4500 3")
        Self.check(s?.total == 4500 && s?.peopleCount == 3 && s?.perPerson == 1500, "Split bill parsed")
        Self.check(GGMediaTokCoreLogic.parseSplitBillCommand(".split -100 2") == nil, "Negative bill rejected")
    }

    private static func testTimeCapsuleParser() {
        let c = GGMediaTokCoreLogic.parseTimeCapsuleCommand(".capsule 2027-01-01 С Новым Годом!")
        Self.check(c?.unlockDateStr == "2027-01-01" && c?.message == "С Новым Годом!", "Capsule parsed")
        Self.check(GGMediaTokCoreLogic.parseTimeCapsuleCommand(".capsule") == nil, "Empty capsule returns nil")
    }

    private static func testMoodAndWishParsers() {
        let m = GGMediaTokCoreLogic.parseMoodCommand(".mood 🔥 Работаю над MediaTok")
        Self.check(m?.emoji == "🔥" && m?.text == "Работаю над MediaTok", "Mood with emoji parsed")

        let w = GGMediaTokCoreLogic.parseWishCommand(".wish AirPods Pro 2")
        Self.check(w == "AirPods Pro 2", "Wish parsed")
    }

    private static func testScratchWireCodecAndSnippets() {
        let orig = GGMediaTokCoreLogic.ScratchPayload(title: "Сюрприз", secret: "PROMO-777", seed: 123)
        let wire = GGMediaTokCoreLogic.encodeScratchWireMessage(orig)
        let decoded = GGMediaTokCoreLogic.decodeScratchWireMessage(wire)
        Self.check(decoded?.title == "Сюрприз" && decoded?.secret == "PROMO-777", "Scratch wire round-trip preserves title & secret")
        Self.check(GGMediaTokCoreLogic.decodeScratchWireMessage("обычное сообщение") == nil, "Non-scratch text returns nil")

        Self.check(GGMediaTokCoreLogic.parseSnippetCommand(".sn add карта 2200 7007 1234") == .add(key: "карта", value: "2200 7007 1234"), "Snippet add parsed")
        Self.check(GGMediaTokCoreLogic.parseSnippetCommand(".sn карта") == .expand(key: "карта"), "Snippet expand parsed")
        Self.check(GGMediaTokCoreLogic.parseSnippetCommand(".sn del карта") == .remove(key: "карта"), "Snippet del parsed")
        Self.check(GGMediaTokCoreLogic.parseSnippetCommand(".sn") == .list, "Snippet list parsed")
    }

    private static func testPrefixPayloadsAndJsonPrettyPrint() {
        Self.check(GGMediaTokCoreLogic.parsePrefixPayload(".wiki Swift", prefixes: [".wiki ", ".def "]) == "Swift", "Wiki prefix parsed")
        Self.check(GGMediaTokCoreLogic.parsePrefixPayload(".ai Привет", prefixes: [".ai "]) == "Привет", "AI prefix parsed")
        let pretty = GGMediaTokCoreLogic.prettyPrintJsonIfValid("{\"b\":2,\"a\":1}")
        Self.check(pretty != nil && pretty!.contains("\n"), "Valid JSON pretty-printed")
        Self.check(GGMediaTokCoreLogic.prettyPrintJsonIfValid("not json") == nil, "Invalid JSON returns nil")
    }

    private static func testCloudBackupCodec() {
        let payload = GGMediaTokCoreLogic.MediaTokBackupPayload(
            version: 1,
            createdAt: 1795171200,
            bools: ["mediatok.adblock.enabled.v1": true, "mediatok.video.4k60.v1": true],
            strings: ["mediatok.liquid_glass.preset.v1": "ios27_clear"],
            stringArrays: ["mediatok.achievements.unlocked.v1": ["mediatok_og", "night_owl"]],
            snippets: ["карта": "2200 7007"],
            notes: ["12345": "Напомнить завтра"]
        )
        let data = GGMediaTokCoreLogic.encodeBackupPayload(payload)
        Self.check(data != nil && !data!.isEmpty, "Backup payload encoded")
        let decoded = data.flatMap { GGMediaTokCoreLogic.decodeBackupPayload($0) }
        Self.check(decoded == payload, "Backup payload round-trip matches exactly")
        Self.check(GGMediaTokCoreLogic.decodeBackupPayload(Data("{\"version\":99}".utf8)) == nil, "Unknown backup version rejected")
    }
}
