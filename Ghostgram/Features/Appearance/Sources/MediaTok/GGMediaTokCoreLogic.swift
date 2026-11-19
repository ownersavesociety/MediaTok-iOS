import Foundation
import CryptoKit
import Security

/// Pure-Swift security, crypto, parsing, PCM acoustic analysis, and TrueType compiler core
/// shared across MediaTok iOS (`GGAppearance`) and the macOS Swift 6.3 security test suite.
enum GGMediaTokCoreLogic {

    // MARK: - 1. Media URL Allowlist & Steam Sanitizer

    static func isAllowedMediaURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(),
              scheme == "https",
              let host = comps.host?.lowercased(),
              host == "files.catbox.moe",
              comps.user == nil,
              comps.password == nil else {
            return nil
        }
        if let port = comps.port, port != 443 {
            return nil
        }
        let path = comps.percentEncodedPath
        guard path.count > 1, !path.contains(".."), let url = comps.url else {
            return nil
        }
        return url
    }

    static func sanitizeAudioExtension(_ rawExt: String) -> String {
        let clean = rawExt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed: Set<String> = ["mp3", "m4a", "wav", "aac", "ogg", "flac", "opus"]
        return allowed.contains(clean) ? clean : "mp3"
    }

    static func normalizeSteam(_ raw: String) -> (profileUrl: URL, xmlUrl: URL, cleanLabel: String)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let idx = lower.range(of: "steamcommunity.com/") else { return nil }
            let offset = lower.distance(from: lower.startIndex, to: idx.upperBound)
            s = String(s.dropFirst(offset))
        } else if lower.hasPrefix("steamcommunity.com/") {
            s = String(s.dropFirst("steamcommunity.com/".count))
        }

        if let qIdx = s.firstIndex(of: "?") { s = String(s[..<qIdx]) }
        if let fIdx = s.firstIndex(of: "#") { s = String(s[..<fIdx]) }
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.contains(".."), !s.contains("@"), !s.contains("\\") else {
            return nil
        }

        func isValidVanitySlug(_ slug: String) -> Bool {
            guard !slug.isEmpty, slug.count <= 64 else { return false }
            return slug.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        }

        func isValidSteamId64(_ digits: String) -> Bool {
            return digits.count == 17 && digits.allSatisfy { $0.isASCII && $0.isNumber }
        }

        let path: String
        let label: String
        if s.hasPrefix("profiles/") {
            let tail = String(s.dropFirst("profiles/".count))
            guard isValidSteamId64(tail) else { return nil }
            path = "profiles/\(tail)"
            label = tail
        } else if s.hasPrefix("id/") {
            let tail = String(s.dropFirst("id/".count))
            guard isValidVanitySlug(tail) else { return nil }
            path = "id/\(tail)"
            label = tail
        } else if isValidSteamId64(s) {
            path = "profiles/\(s)"
            label = s
        } else if isValidVanitySlug(s) {
            path = "id/\(s)"
            label = s
        } else {
            return nil
        }

        guard let pUrl = URL(string: "https://steamcommunity.com/\(path)"),
              let xUrl = URL(string: "https://steamcommunity.com/\(path)?xml=1") else {
            return nil
        }
        return (pUrl, xUrl, label)
    }

    // MARK: - 2. Format-String Safety Validator for Language Overrides

    static func extractFormatSpecifiers(_ text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        var specs: [String] = []
        var i = 0
        let convChars = Set<UnicodeScalar>("@dDuUxXoOfeEgGcCsSpaAFn".unicodeScalars)
        let flagChars = Set<UnicodeScalar>("-+# 0'".unicodeScalars)
        let lengthChars = Set<UnicodeScalar>("hlqLztj".unicodeScalars)

        while i < scalars.count {
            if scalars[i] != "%" {
                i += 1
                continue
            }
            if i + 1 < scalars.count && scalars[i + 1] == "%" {
                i += 2
                continue
            }
            var j = i + 1
            var posPrefix = ""
            var k = j
            while k < scalars.count && scalars[k].value >= 0x30 && scalars[k].value <= 0x39 {
                k += 1
            }
            if k > j && k < scalars.count && scalars[k] == "$" {
                posPrefix = String(scalars[j ... k].map { Character($0) })
                j = k + 1
            }
            while j < scalars.count && flagChars.contains(scalars[j]) {
                j += 1
            }
            if j < scalars.count && scalars[j] == "*" {
                specs.append("*")
                j += 1
            } else {
                while j < scalars.count && scalars[j].value >= 0x30 && scalars[j].value <= 0x39 {
                    j += 1
                }
            }
            if j < scalars.count && scalars[j] == "." {
                j += 1
                if j < scalars.count && scalars[j] == "*" {
                    specs.append("*")
                    j += 1
                } else {
                    while j < scalars.count && scalars[j].value >= 0x30 && scalars[j].value <= 0x39 {
                        j += 1
                    }
                }
            }
            while j < scalars.count && lengthChars.contains(scalars[j]) {
                j += 1
            }
            if j < scalars.count && convChars.contains(scalars[j]) {
                specs.append(posPrefix + String(scalars[j]))
                i = j + 1
            } else {
                // Lone '%' without valid conversion character (e.g. "100% онлайн")
                i += 1
            }
        }
        return specs
    }

    static func isFormatSafe(original: String, candidate: String) -> Bool {
        if candidate.count > 1000 {
            return false
        }
        let origSpecs = GGMediaTokCoreLogic.extractFormatSpecifiers(original)
        let candSpecs = GGMediaTokCoreLogic.extractFormatSpecifiers(candidate)
        for spec in candSpecs {
            if spec.hasSuffix("n") {
                return false
            }
            if (spec.hasSuffix("s") || spec.hasSuffix("p")) && !origSpecs.contains(spec) {
                return false
            }
        }
        return origSpecs == candSpecs
    }

    // MARK: - 3. Anti-IP-Logger Host Detector

    static let ipLoggerDomains: [String] = [
        "grabify.link", "iplogger.org", "iplogger.com", "iplogger.ru", "iplogger.co",
        "2no.co", "ezstat.ru", "yip.su", "blasze.tk", "blasze.com", "ps3cfw.com",
        "bmwforum.co", "leancoding.co", "stopify.co", "freegiftcards.co", "joinmy.site",
        "curiouscat.club", "wl.gl", "ed.tc", "bc.ax", "maper.info", "canarytokens.com",
        "oastify.com", "interact.sh"
    ]

    static func detectIpLoggerHost(text: String, extraUrls: [String]) -> String? {
        var candidates: [String] = extraUrls
        let delimiters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>()[]\"'`,;"))
        for token in text.components(separatedBy: delimiters) where !token.isEmpty && token.contains(".") {
            candidates.append(token)
        }
        for raw in candidates {
            var trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;\"'()[]<>"))
            guard !trimmed.isEmpty else { continue }
            if !trimmed.contains("://") {
                trimmed = "https://" + trimmed
            }
            guard let host = URLComponents(string: trimmed)?.host?.lowercased(), !host.isEmpty else {
                continue
            }
            for domain in GGMediaTokCoreLogic.ipLoggerDomains {
                if host == domain || host.hasSuffix("." + domain) {
                    return domain
                }
            }
        }
        return nil
    }

    // MARK: - 4. Hardened E2E Crypto (PBKDF2-HMAC-SHA256 + AAD Peer Binding)

    static let prefixV1 = "🔒MT1:"
    static let prefixV2 = "🔒MT2:"

    private static let cryptoLock = NSLock()
    private static var pbkdf2Cache: [String: SymmetricKey] = [:]

    static func clearCryptoCache() {
        GGMediaTokCoreLogic.cryptoLock.lock()
        GGMediaTokCoreLogic.pbkdf2Cache.removeAll()
        GGMediaTokCoreLogic.cryptoLock.unlock()
    }

    static func deriveKeyPBKDF2(passphrase: String, salt: Data, iterations: Int = 100_000) -> SymmetricKey? {
        guard !passphrase.isEmpty, !salt.isEmpty, iterations >= 1 else {
            return nil
        }
        let cacheKey = "\(iterations):\(salt.base64EncodedString()):\(passphrase)"
        GGMediaTokCoreLogic.cryptoLock.lock()
        if let cached = GGMediaTokCoreLogic.pbkdf2Cache[cacheKey] {
            GGMediaTokCoreLogic.cryptoLock.unlock()
            return cached
        }
        GGMediaTokCoreLogic.cryptoLock.unlock()

        let hmacKey = SymmetricKey(data: Data(passphrase.utf8))
        var blockInput = Data(salt)
        blockInput.append(contentsOf: [0, 0, 0, 1])

        var u = Array(HMAC<SHA256>.authenticationCode(for: blockInput, using: hmacKey))
        var dk = u
        if iterations > 1 {
            for _ in 2 ... iterations {
                let mac = HMAC<SHA256>.authenticationCode(for: u, using: hmacKey)
                var idx = 0
                for byte in mac {
                    dk[idx] ^= byte
                    u[idx] = byte
                    idx += 1
                }
            }
        }
        let key = SymmetricKey(data: Data(dk))
        GGMediaTokCoreLogic.cryptoLock.lock()
        if GGMediaTokCoreLogic.pbkdf2Cache.count > 256 {
            GGMediaTokCoreLogic.pbkdf2Cache.removeAll()
        }
        GGMediaTokCoreLogic.pbkdf2Cache[cacheKey] = key
        GGMediaTokCoreLogic.cryptoLock.unlock()
        return key
    }

    private static func deriveLegacyKeyV1(passphrase: String) -> SymmetricKey {
        let material = Data("MediaTokE2E:v1:\(passphrase)".utf8)
        let hash = SHA256.hash(data: material)
        return SymmetricKey(data: hash)
    }

    static func encryptV2(_ plaintext: String, passphrase: String, peerKey: String) -> String? {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        let secStatus = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        guard secStatus == errSecSuccess else {
            return nil
        }
        let salt = Data(saltBytes)
        guard let key = GGMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: passphrase, salt: salt) else {
            return nil
        }
        let aad = Data("MT2:\(peerKey)".utf8)
        let plainData = Data(plaintext.utf8)
        guard let sealed = try? AES.GCM.seal(plainData, using: key, authenticating: aad),
              let combined = sealed.combined else {
            return nil
        }
        var payload = Data()
        payload.append(salt)
        payload.append(combined)
        let b64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return GGMediaTokCoreLogic.prefixV2 + b64
    }

    static func decryptAny(_ ciphertext: String, passphrase: String, peerKey: String) -> String? {
        if ciphertext.hasPrefix(GGMediaTokCoreLogic.prefixV2) {
            var b64 = String(ciphertext.dropFirst(GGMediaTokCoreLogic.prefixV2.count))
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let rem = b64.count % 4
            if rem > 0 { b64.append(String(repeating: "=", count: 4 - rem)) }
            guard let raw = Data(base64Encoded: b64),
                  raw.count > 16 + 28 else {
                return nil
            }
            let salt = raw.prefix(16)
            let combined = raw.dropFirst(16)
            guard let key = GGMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: passphrase, salt: salt),
                  let box = try? AES.GCM.SealedBox(combined: combined) else {
                return nil
            }
            let aad = Data("MT2:\(peerKey)".utf8)
            guard let plain = try? AES.GCM.open(box, using: key, authenticating: aad),
                  let str = String(data: plain, encoding: .utf8) else {
                return nil
            }
            return str
        }
        if ciphertext.hasPrefix(GGMediaTokCoreLogic.prefixV1) {
            var b64 = String(ciphertext.dropFirst(GGMediaTokCoreLogic.prefixV1.count))
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let rem = b64.count % 4
            if rem > 0 { b64.append(String(repeating: "=", count: 4 - rem)) }
            guard let raw = Data(base64Encoded: b64),
                  let box = try? AES.GCM.SealedBox(combined: raw) else {
                return nil
            }
            let key = GGMediaTokCoreLogic.deriveLegacyKeyV1(passphrase: passphrase)
            guard let plain = try? AES.GCM.open(box, using: key),
                  let str = String(data: plain, encoding: .utf8) else {
                return nil
            }
            return str
        }
        return nil
    }

    // MARK: - 5. Depth-Bounded Math Evaluator (Fixes Stack Overflow & `-2^2 == -4`)

    private final class SafeMathParser {
        private let chars: [Character]
        private var pos = 0
        private let maxDepth = 64

        init?(_ input: String) {
            guard input.count <= 512 else { return nil }
            let normalized = input
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: " ", with: "")
            guard !normalized.isEmpty, normalized.count <= 512 else { return nil }
            self.chars = Array(normalized)
        }

        func parse() -> Double? {
            guard let v = self.parseAddSub(depth: 0), self.pos == self.chars.count, v.isFinite else {
                return nil
            }
            return v
        }

        private func peek() -> Character? {
            return self.pos < self.chars.count ? self.chars[self.pos] : nil
        }

        private func parseAddSub(depth: Int) -> Double? {
            guard depth <= self.maxDepth, var left = self.parseMulDiv(depth: depth + 1) else { return nil }
            while let ch = self.peek(), ch == "+" || ch == "-" {
                self.pos += 1
                guard let right = self.parseMulDiv(depth: depth + 1) else { return nil }
                left = (ch == "+") ? (left + right) : (left - right)
            }
            return left
        }

        private func parseMulDiv(depth: Int) -> Double? {
            guard depth <= self.maxDepth, var left = self.parseUnary(depth: depth + 1) else { return nil }
            while let ch = self.peek(), ch == "*" || ch == "/" || ch == "%" {
                self.pos += 1
                guard let right = self.parseUnary(depth: depth + 1) else { return nil }
                if ch == "*" {
                    left *= right
                } else if ch == "/" {
                    if right == 0 { return nil }
                    left /= right
                } else {
                    if right == 0 { return nil }
                    left = left.truncatingRemainder(dividingBy: right)
                }
            }
            return left
        }

        private func parseUnary(depth: Int) -> Double? {
            guard depth <= self.maxDepth else { return nil }
            if self.peek() == "+" {
                self.pos += 1
                return self.parseUnary(depth: depth + 1)
            }
            if self.peek() == "-" {
                self.pos += 1
                guard let v = self.parseUnary(depth: depth + 1) else { return nil }
                return -v
            }
            return self.parsePower(depth: depth + 1)
        }

        private func parsePower(depth: Int) -> Double? {
            guard depth <= self.maxDepth, let base = self.parsePrimary(depth: depth + 1) else { return nil }
            if self.peek() == "^" {
                self.pos += 1
                guard let exp = self.parseUnary(depth: depth + 1) else { return nil }
                return pow(base, exp)
            }
            return base
        }

        private func parsePrimary(depth: Int) -> Double? {
            guard depth <= self.maxDepth else { return nil }
            if self.peek() == "(" {
                self.pos += 1
                guard let v = self.parseAddSub(depth: depth + 1), self.peek() == ")" else { return nil }
                self.pos += 1
                return v
            }
            if let ch = self.peek(), ch.isLetter {
                let start = self.pos
                while let c = self.peek(), c.isLetter || c.isNumber {
                    self.pos += 1
                }
                let ident = String(self.chars[start ..< self.pos]).lowercased()
                if ident == "pi" { return Double.pi }
                if ident == "e" { return 2.71828182845904523536 }
                guard self.peek() == "(" else { return nil }
                self.pos += 1
                guard let arg = self.parseAddSub(depth: depth + 1), self.peek() == ")" else { return nil }
                self.pos += 1
                switch ident {
                case "sqrt": return arg >= 0 ? sqrt(arg) : nil
                case "abs": return abs(arg)
                case "sin": return sin(arg)
                case "cos": return cos(arg)
                case "tan": return tan(arg)
                case "ln": return arg > 0 ? log(arg) : nil
                case "log", "log10": return arg > 0 ? log10(arg) : nil
                case "round": return arg.rounded()
                case "floor": return floor(arg)
                case "ceil": return ceil(arg)
                default: return nil
                }
            }
            let start = self.pos
            var hasDot = false
            while let ch = self.peek() {
                if ch.isNumber {
                    self.pos += 1
                } else if ch == "." && !hasDot {
                    hasDot = true
                    self.pos += 1
                } else {
                    break
                }
            }
            guard self.pos > start else { return nil }
            var val = Double(String(self.chars[start ..< self.pos]))
            if let v = val, let suffix = self.peek() {
                let low = String(suffix).lowercased()
                if low == "k" || low == "к" {
                    self.pos += 1
                    if let s2 = self.peek(), String(s2).lowercased() == "k" || String(s2).lowercased() == "к" {
                        self.pos += 1
                        val = v * 1_000_000.0
                    } else {
                        val = v * 1_000.0
                    }
                }
            }
            return val
        }
    }

    static func evaluateMath(_ expr: String) -> Double? {
        return SafeMathParser(expr)?.parse()
    }

    // MARK: - 6. Acoustic PCM 16 kHz Screamer & Moan Prank Analyzer

    enum AudioVerdict: Int {
        case clean = 0
        case loudScreamer = 1
        case moanPrank = 2
    }

    static func analyzeAudioPcm16k(_ samples: [Int16]) -> AudioVerdict {
        let sampleRate = 16000
        let windowSize = 800 // 50 ms at 16 kHz
        guard samples.count > sampleRate / 3 else {
            return .clean
        }

        let inspectCount = min(samples.count, sampleRate * 15)
        var clippedSamples = 0
        var sumSqTotal: Double = 0.0
        var windowSumSq: Double = 0.0
        var windowZeroCrossings = 0
        var windowCount = 0
        var prevSample: Int16 = 0
        var windowRmsList: [Double] = []
        var windowZcrList: [Double] = []

        for idx in 0 ..< inspectCount {
            let s = samples[idx]
            let absVal = s == Int16.min ? 32768 : abs(Int(s))
            if absVal >= 28500 {
                clippedSamples += 1
            }
            let norm = Double(s) / 32768.0
            let sq = norm * norm
            sumSqTotal += sq
            windowSumSq += sq
            if (s >= 0 && prevSample < 0) || (s < 0 && prevSample >= 0) {
                windowZeroCrossings += 1
            }
            prevSample = s
            windowCount += 1

            if windowCount >= windowSize {
                let rms = sqrt(windowSumSq / Double(windowCount))
                let zcrHz = (Double(windowZeroCrossings) * Double(sampleRate)) / (2.0 * Double(windowCount))
                windowRmsList.append(rms)
                windowZcrList.append(zcrHz)
                windowSumSq = 0.0
                windowZeroCrossings = 0
                windowCount = 0
            }
        }

        guard !windowRmsList.isEmpty else {
            return .clean
        }

        let overallRms = sqrt(sumSqTotal / Double(inspectCount))
        let clipRatio = Double(clippedSamples) / Double(inspectCount)
        let maxWindowRms = windowRmsList.max() ?? 0.0

        if clipRatio > 0.032 || (overallRms > 0.62 && clipRatio > 0.012) || (maxWindowRms > 0.86 && clipRatio > 0.015) {
            return .loudScreamer
        }

        if windowRmsList.count >= 6 {
            var quietBaseline = 0.05
            for i in 0 ..< windowRmsList.count {
                let r = windowRmsList[i]
                if i >= 3 && r > 0.78 && quietBaseline < 0.09 {
                    return .loudScreamer
                }
                quietBaseline = quietBaseline * 0.8 + r * 0.2
            }
        }

        var vocalBurstWindows = 0
        var burstTransitions = 0
        var inBurst = false
        for i in 0 ..< windowRmsList.count {
            let r = windowRmsList[i]
            let z = windowZcrList[i]
            let isLoudVocal = r > 0.34 && z >= 380.0 && z <= 1280.0
            if isLoudVocal {
                vocalBurstWindows += 1
                if !inBurst {
                    inBurst = true
                    burstTransitions += 1
                }
            } else if r < 0.16 {
                inBurst = false
            }
        }
        let vocalFraction = Double(vocalBurstWindows) / Double(windowRmsList.count)
        if burstTransitions >= 2 && vocalFraction >= 0.22 && maxWindowRms >= 0.52 {
            return .moanPrank
        }

        return .clean
    }

    // MARK: - 7. Binary TrueType (.ttf) Compiler with Cyrillic Name & Unique PostScript ID Fix

    private struct TtfRectI {
        let x1: Int
        let y1: Int
        let x2: Int
        let y2: Int
    }

    private struct TtfCmapSeg {
        var start: UInt16
        var end: UInt16
        let delta: UInt16
    }

    private struct TtfNameRec {
        let pid: UInt16
        let eid: UInt16
        let lid: UInt16
        let nid: UInt16
        let len: UInt16
        let off: UInt16
    }

    private static func appendU16(_ d: inout Data, _ v: UInt16) {
        d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8(v & 0xFF))
    }

    private static func appendS16(_ d: inout Data, _ v: Int16) {
        GGMediaTokCoreLogic.appendU16(&d, UInt16(bitPattern: v))
    }

    private static func appendU32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8((v >> 24) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF))
        d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8(v & 0xFF))
    }

    private static func calcChecksum(_ data: Data) -> UInt32 {
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

    private static func transliterateAscii(_ input: String) -> String {
        let latin = input.applyingTransform(.toLatin, reverse: false) ?? input
        let stripped = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        let asciiOnly = String(stripped.unicodeScalars.filter { $0.value >= 32 && $0.value <= 126 }.map { Character($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return asciiOnly.isEmpty ? "MediaTok Custom" : asciiOnly
    }

    private static func buildSimpleGlyph(_ rects: [TtfRectI]) -> Data {
        if rects.isEmpty {
            return Data()
        }
        var xMin = Int.max
        var yMin = Int.max
        var xMax = Int.min
        var yMax = Int.min
        for r in rects {
            xMin = min(xMin, min(r.x1, r.x2))
            xMax = max(xMax, max(r.x1, r.x2))
            yMin = min(yMin, min(r.y1, r.y2))
            yMax = max(yMax, max(r.y1, r.y2))
        }
        var out = Data()
        GGMediaTokCoreLogic.appendS16(&out, Int16(rects.count))
        GGMediaTokCoreLogic.appendS16(&out, Int16(xMin))
        GGMediaTokCoreLogic.appendS16(&out, Int16(yMin))
        GGMediaTokCoreLogic.appendS16(&out, Int16(xMax))
        GGMediaTokCoreLogic.appendS16(&out, Int16(yMax))
        for i in 0 ..< rects.count {
            GGMediaTokCoreLogic.appendU16(&out, UInt16(i * 4 + 3))
        }
        GGMediaTokCoreLogic.appendU16(&out, 0)
        out.append(contentsOf: [UInt8](repeating: 1, count: rects.count * 4))
        var prevX = 0
        for r in rects {
            for x in [r.x1, r.x1, r.x2, r.x2] {
                GGMediaTokCoreLogic.appendS16(&out, Int16(x - prevX))
                prevX = x
            }
        }
        var prevY = 0
        for r in rects {
            for y in [r.y1, r.y2, r.y2, r.y1] {
                GGMediaTokCoreLogic.appendS16(&out, Int16(y - prevY))
                prevY = y
            }
        }
        while out.count % 4 != 0 {
            out.append(0)
        }
        return out
    }

    static func compileTtf(fontNameRaw: String, grids: [Character: [Bool]], pixelStyle: Int, uniqueTag: String? = nil) -> Data {
        let gridW = 10
        let gridH = 12
        let trimmed = fontNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fontName = trimmed.isEmpty ? "MediaTok Custom" : trimmed
        let macName = GGMediaTokCoreLogic.transliterateAscii(fontName)
        let cellW = (pixelStyle == 2) ? 82 : 76
        let cellH = 82
        let gap = (pixelStyle == 1) ? 10 : 0
        let slantPerRow = (pixelStyle == 3) ? 14 : 0
        let baselineRow = 9

        var charRects: [UInt16: [TtfRectI]] = [32: []]
        for (ch, grid) in grids {
            guard ch.unicodeScalars.count == 1,
                  let scalar = ch.unicodeScalars.first,
                  scalar.value <= 0xFFFF,
                  scalar.value != 32,
                  grid.count == gridW * gridH else {
                continue
            }
            var rects: [TtfRectI] = []
            for row in 0 ..< gridH {
                let yBottom = (baselineRow - row) * cellH + gap / 2
                let yTop = (baselineRow - row + 1) * cellH - gap / 2
                let slant = (baselineRow - row) * slantPerRow
                var col = 0
                while col < gridW {
                    if !grid[row * gridW + col] {
                        col += 1
                        continue
                    }
                    let startCol = col
                    if pixelStyle == 1 {
                        rects.append(TtfRectI(x1: 40 + startCol * cellW + gap / 2 + slant, y1: yBottom, x2: 40 + (startCol + 1) * cellW - gap / 2 + slant, y2: yTop))
                        col += 1
                    } else {
                        while col < gridW && grid[row * gridW + col] {
                            col += 1
                        }
                        rects.append(TtfRectI(x1: 40 + startCol * cellW + slant, y1: yBottom, x2: 40 + col * cellW + slant, y2: yTop))
                    }
                }
            }
            charRects[UInt16(scalar.value)] = rects
        }

        let cps = charRects.keys.filter { $0 != 32 }.sorted()
        var glyphOrder: [UInt16] = [0, 32]
        glyphOrder.append(contentsOf: cps)
        var cpToGid: [UInt16: UInt16] = [32: 1]
        for (idx, cp) in cps.enumerated() {
            cpToGid[cp] = UInt16(idx + 2)
        }
        let numGlyphs = UInt16(glyphOrder.count)

        var glyf = Data()
        var loca = Data()
        var hmtx = Data()
        var maxPoints: UInt16 = 0
        var maxContours: UInt16 = 0

        for gid in 0 ..< Int(numGlyphs) {
            GGMediaTokCoreLogic.appendU32(&loca, UInt32(glyf.count))
            let cp = glyphOrder[gid]
            let rects: [TtfRectI]
            let adv: UInt16
            let lsb: Int16
            if gid == 0 {
                rects = [TtfRectI(x1: 80, y1: 0, x2: 520, y2: 720)]
                adv = 600
                lsb = 80
            } else if cp == 32 {
                rects = []
                adv = 400
                lsb = 0
            } else {
                rects = charRects[cp] ?? []
                if !rects.isEmpty {
                    let xMin = rects.map { min($0.x1, $0.x2) }.min() ?? 0
                    let xMax = rects.map { max($0.x1, $0.x2) }.max() ?? 400
                    adv = UInt16(max(440, xMax + 70))
                    lsb = Int16(xMin)
                } else {
                    adv = 400
                    lsb = 0
                }
            }
            glyf.append(GGMediaTokCoreLogic.buildSimpleGlyph(rects))
            GGMediaTokCoreLogic.appendU16(&hmtx, adv)
            GGMediaTokCoreLogic.appendS16(&hmtx, lsb)
            maxPoints = max(maxPoints, UInt16(rects.count * 4))
            maxContours = max(maxContours, UInt16(rects.count))
        }
        GGMediaTokCoreLogic.appendU32(&loca, UInt32(glyf.count))

        let mappedCps = cpToGid.keys.sorted()
        var segs: [TtfCmapSeg] = []
        for cp in mappedCps {
            let gid = cpToGid[cp] ?? 0
            let delta = UInt16((Int(gid) - Int(cp)) & 0xFFFF)
            if !segs.isEmpty && cp == segs[segs.count - 1].end &+ 1 && delta == segs[segs.count - 1].delta {
                segs[segs.count - 1].end = cp
            } else {
                segs.append(TtfCmapSeg(start: cp, end: cp, delta: delta))
            }
        }
        segs.append(TtfCmapSeg(start: 0xFFFF, end: 0xFFFF, delta: 1))
        let segCount = UInt16(segs.count)
        var pow2: UInt16 = 1
        var es: UInt16 = 0
        while pow2 * 2 <= segCount {
            pow2 *= 2
            es += 1
        }
        let sr = pow2 * 2
        let rs = segCount * 2 - sr

        var fmt4 = Data()
        GGMediaTokCoreLogic.appendU16(&fmt4, 4)
        GGMediaTokCoreLogic.appendU16(&fmt4, 16 + segCount * 8)
        GGMediaTokCoreLogic.appendU16(&fmt4, 0)
        GGMediaTokCoreLogic.appendU16(&fmt4, segCount * 2)
        GGMediaTokCoreLogic.appendU16(&fmt4, sr)
        GGMediaTokCoreLogic.appendU16(&fmt4, es)
        GGMediaTokCoreLogic.appendU16(&fmt4, rs)
        for s in segs { GGMediaTokCoreLogic.appendU16(&fmt4, s.end) }
        GGMediaTokCoreLogic.appendU16(&fmt4, 0)
        for s in segs { GGMediaTokCoreLogic.appendU16(&fmt4, s.start) }
        for s in segs { GGMediaTokCoreLogic.appendU16(&fmt4, s.delta) }
        for _ in segs { GGMediaTokCoreLogic.appendU16(&fmt4, 0) }

        var cmap = Data()
        GGMediaTokCoreLogic.appendU16(&cmap, 0)
        GGMediaTokCoreLogic.appendU16(&cmap, 2)
        GGMediaTokCoreLogic.appendU16(&cmap, 0); GGMediaTokCoreLogic.appendU16(&cmap, 3); GGMediaTokCoreLogic.appendU32(&cmap, 20)
        GGMediaTokCoreLogic.appendU16(&cmap, 3); GGMediaTokCoreLogic.appendU16(&cmap, 1); GGMediaTokCoreLogic.appendU32(&cmap, 20)
        cmap.append(fmt4)

        let asciiPsBase = macName.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let suffix = uniqueTag ?? String(format: "%04X", UInt16.random(in: 0 ... UInt16.max))
        let trimmedBase = String((asciiPsBase.isEmpty ? "MediaTokCustom" : asciiPsBase).prefix(34))
        let safePs = "\(trimmedBase)_\(suffix)"

        let macPairs: [(UInt16, String)] = [
            (1, macName), (2, "Regular"), (3, "MediaTok-\(safePs)"),
            (4, macName), (5, "Version 1.0"), (6, safePs)
        ]
        let uniPairs: [(UInt16, String)] = [
            (1, fontName), (2, "Regular"), (3, "MediaTok-\(safePs)"),
            (4, fontName), (5, "Version 1.0"), (6, safePs)
        ]

        var recs: [TtfNameRec] = []
        var strBlob = Data()

        // Platform 0 (Unicode) UTF-16BE
        for (nid, s) in uniPairs {
            var b = Data()
            for unit in s.utf16 { GGMediaTokCoreLogic.appendU16(&b, unit) }
            recs.append(TtfNameRec(pid: 0, eid: 3, lid: 0, nid: nid, len: UInt16(b.count), off: UInt16(strBlob.count)))
            strBlob.append(b)
        }
        // Platform 1 (Mac Roman ASCII — clean transliteration, never "???")
        for (nid, s) in macPairs {
            var b = Data()
            for scalar in s.unicodeScalars {
                b.append((scalar.value >= 32 && scalar.value <= 126) ? UInt8(scalar.value) : UInt8(95))
            }
            recs.append(TtfNameRec(pid: 1, eid: 0, lid: 0, nid: nid, len: UInt16(b.count), off: UInt16(strBlob.count)))
            strBlob.append(b)
        }
        // Platform 3 (Windows Unicode BMP) UTF-16BE — full Cyrillic name preserved
        for (nid, s) in uniPairs {
            var b = Data()
            for unit in s.utf16 { GGMediaTokCoreLogic.appendU16(&b, unit) }
            recs.append(TtfNameRec(pid: 3, eid: 1, lid: 0x0409, nid: nid, len: UInt16(b.count), off: UInt16(strBlob.count)))
            strBlob.append(b)
        }
        recs.sort { ($0.pid, $0.eid, $0.lid, $0.nid) < ($1.pid, $1.eid, $1.lid, $1.nid) }

        var nameTbl = Data()
        GGMediaTokCoreLogic.appendU16(&nameTbl, 0)
        GGMediaTokCoreLogic.appendU16(&nameTbl, UInt16(recs.count))
        GGMediaTokCoreLogic.appendU16(&nameTbl, UInt16(6 + recs.count * 12))
        for r in recs {
            GGMediaTokCoreLogic.appendU16(&nameTbl, r.pid)
            GGMediaTokCoreLogic.appendU16(&nameTbl, r.eid)
            GGMediaTokCoreLogic.appendU16(&nameTbl, r.lid)
            GGMediaTokCoreLogic.appendU16(&nameTbl, r.nid)
            GGMediaTokCoreLogic.appendU16(&nameTbl, r.len)
            GGMediaTokCoreLogic.appendU16(&nameTbl, r.off)
        }
        nameTbl.append(strBlob)

        var head = Data()
        GGMediaTokCoreLogic.appendU32(&head, 0x00010000); GGMediaTokCoreLogic.appendU32(&head, 0x00010000)
        GGMediaTokCoreLogic.appendU32(&head, 0); GGMediaTokCoreLogic.appendU32(&head, 0x5F0F3CF5)
        GGMediaTokCoreLogic.appendU16(&head, 0x000B); GGMediaTokCoreLogic.appendU16(&head, 1000)
        for _ in 0 ..< 4 { GGMediaTokCoreLogic.appendU32(&head, 0) }
        GGMediaTokCoreLogic.appendS16(&head, 0); GGMediaTokCoreLogic.appendS16(&head, -200)
        GGMediaTokCoreLogic.appendS16(&head, 1000); GGMediaTokCoreLogic.appendS16(&head, 900)
        GGMediaTokCoreLogic.appendU16(&head, 0); GGMediaTokCoreLogic.appendU16(&head, 8)
        GGMediaTokCoreLogic.appendS16(&head, 2); GGMediaTokCoreLogic.appendS16(&head, 1); GGMediaTokCoreLogic.appendS16(&head, 0)

        var hhea = Data()
        GGMediaTokCoreLogic.appendU32(&hhea, 0x00010000)
        GGMediaTokCoreLogic.appendS16(&hhea, 850); GGMediaTokCoreLogic.appendS16(&hhea, -200)
        GGMediaTokCoreLogic.appendS16(&hhea, 50); GGMediaTokCoreLogic.appendU16(&hhea, 1000)
        GGMediaTokCoreLogic.appendS16(&hhea, 0); GGMediaTokCoreLogic.appendS16(&hhea, 0)
        GGMediaTokCoreLogic.appendS16(&hhea, 1000); GGMediaTokCoreLogic.appendS16(&hhea, 1)
        for _ in 0 ..< 7 { GGMediaTokCoreLogic.appendS16(&hhea, 0) }
        GGMediaTokCoreLogic.appendU16(&hhea, numGlyphs)

        var maxp = Data()
        GGMediaTokCoreLogic.appendU32(&maxp, 0x00010000)
        GGMediaTokCoreLogic.appendU16(&maxp, numGlyphs)
        GGMediaTokCoreLogic.appendU16(&maxp, maxPoints)
        GGMediaTokCoreLogic.appendU16(&maxp, maxContours)
        GGMediaTokCoreLogic.appendU16(&maxp, 0); GGMediaTokCoreLogic.appendU16(&maxp, 0); GGMediaTokCoreLogic.appendU16(&maxp, 2)
        for _ in 0 ..< 8 { GGMediaTokCoreLogic.appendU16(&maxp, 0) }

        var os2 = Data()
        GGMediaTokCoreLogic.appendU16(&os2, 3); GGMediaTokCoreLogic.appendS16(&os2, 600)
        GGMediaTokCoreLogic.appendU16(&os2, 400); GGMediaTokCoreLogic.appendU16(&os2, 5); GGMediaTokCoreLogic.appendS16(&os2, 0)
        GGMediaTokCoreLogic.appendS16(&os2, 650); GGMediaTokCoreLogic.appendS16(&os2, 600); GGMediaTokCoreLogic.appendS16(&os2, 0); GGMediaTokCoreLogic.appendS16(&os2, 75)
        GGMediaTokCoreLogic.appendS16(&os2, 650); GGMediaTokCoreLogic.appendS16(&os2, 600); GGMediaTokCoreLogic.appendS16(&os2, 0); GGMediaTokCoreLogic.appendS16(&os2, 350)
        GGMediaTokCoreLogic.appendS16(&os2, 50); GGMediaTokCoreLogic.appendS16(&os2, 300); GGMediaTokCoreLogic.appendS16(&os2, 0)
        os2.append(contentsOf: [2, 0, 5, 3, 0, 0, 0, 0, 0, 0])
        GGMediaTokCoreLogic.appendU32(&os2, 0x00000201); GGMediaTokCoreLogic.appendU32(&os2, 0); GGMediaTokCoreLogic.appendU32(&os2, 0); GGMediaTokCoreLogic.appendU32(&os2, 0)
        os2.append(contentsOf: [UInt8]("MTOK".utf8))
        GGMediaTokCoreLogic.appendU16(&os2, 0x0040); GGMediaTokCoreLogic.appendU16(&os2, 32)
        GGMediaTokCoreLogic.appendU16(&os2, mappedCps.last ?? 0x04FF)
        GGMediaTokCoreLogic.appendS16(&os2, 850); GGMediaTokCoreLogic.appendS16(&os2, -200); GGMediaTokCoreLogic.appendS16(&os2, 50)
        GGMediaTokCoreLogic.appendU16(&os2, 900); GGMediaTokCoreLogic.appendU16(&os2, 250)
        GGMediaTokCoreLogic.appendU32(&os2, 0x00000005); GGMediaTokCoreLogic.appendU32(&os2, 0)
        GGMediaTokCoreLogic.appendS16(&os2, 500); GGMediaTokCoreLogic.appendS16(&os2, 720)
        GGMediaTokCoreLogic.appendU16(&os2, 0); GGMediaTokCoreLogic.appendU16(&os2, 32); GGMediaTokCoreLogic.appendU16(&os2, 0)

        var post = Data()
        GGMediaTokCoreLogic.appendU32(&post, 0x00030000); GGMediaTokCoreLogic.appendU32(&post, 0)
        GGMediaTokCoreLogic.appendS16(&post, -100); GGMediaTokCoreLogic.appendS16(&post, 50)
        for _ in 0 ..< 5 { GGMediaTokCoreLogic.appendU32(&post, 0) }

        let tables: [(String, Data)] = [
            ("OS/2", os2), ("cmap", cmap), ("glyf", glyf), ("head", head),
            ("hhea", hhea), ("hmtx", hmtx), ("loca", loca), ("maxp", maxp),
            ("name", nameTbl), ("post", post)
        ].sorted { $0.0 < $1.0 }

        let nt = UInt16(tables.count)
        var tpow2: UInt16 = 1
        var tes: UInt16 = 0
        while tpow2 * 2 <= nt {
            tpow2 *= 2
            tes += 1
        }
        let tsr = tpow2 * 16
        let trs = nt * 16 - tsr

        var full = Data()
        GGMediaTokCoreLogic.appendU32(&full, 0x00010000)
        GGMediaTokCoreLogic.appendU16(&full, nt)
        GGMediaTokCoreLogic.appendU16(&full, tsr)
        GGMediaTokCoreLogic.appendU16(&full, tes)
        GGMediaTokCoreLogic.appendU16(&full, trs)

        var offset = UInt32(12 + Int(nt) * 16)
        var headOffset = 0
        var body = Data()
        for (tag, data) in tables {
            full.append(contentsOf: [UInt8](tag.utf8))
            GGMediaTokCoreLogic.appendU32(&full, GGMediaTokCoreLogic.calcChecksum(data))
            GGMediaTokCoreLogic.appendU32(&full, offset)
            GGMediaTokCoreLogic.appendU32(&full, UInt32(data.count))
            if tag == "head" {
                headOffset = Int(offset)
            }
            body.append(data)
            let pad = (4 - (data.count % 4)) % 4
            if pad > 0 {
                body.append(contentsOf: [UInt8](repeating: 0, count: pad))
            }
            offset += UInt32(data.count + pad)
        }
        full.append(body)
        let adj = UInt32(0xB1B0AFBA) &- GGMediaTokCoreLogic.calcChecksum(full)
        full[headOffset + 8] = UInt8((adj >> 24) & 0xFF)
        full[headOffset + 9] = UInt8((adj >> 16) & 0xFF)
        full[headOffset + 10] = UInt8((adj >> 8) & 0xFF)
        full[headOffset + 11] = UInt8(adj & 0xFF)
        return full
    }
}
