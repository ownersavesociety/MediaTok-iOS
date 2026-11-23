import Foundation
import CryptoKit
import Security

/// Pure-Swift security, crypto, parsing, PCM acoustic analysis, and TrueType compiler core
/// shared across MediaTok iOS (`MTAppearance`) and the macOS Swift 6.3 security test suite.
enum MTMediaTokCoreLogic {

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
        let origSpecs = MTMediaTokCoreLogic.extractFormatSpecifiers(original)
        let candSpecs = MTMediaTokCoreLogic.extractFormatSpecifiers(candidate)
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
            for domain in MTMediaTokCoreLogic.ipLoggerDomains {
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
        MTMediaTokCoreLogic.cryptoLock.lock()
        MTMediaTokCoreLogic.pbkdf2Cache.removeAll()
        MTMediaTokCoreLogic.cryptoLock.unlock()
    }

    static func deriveKeyPBKDF2(passphrase: String, salt: Data, iterations: Int = 100_000) -> SymmetricKey? {
        guard !passphrase.isEmpty, !salt.isEmpty, iterations >= 1 else {
            return nil
        }
        let cacheKey = "\(iterations):\(salt.base64EncodedString()):\(passphrase)"
        MTMediaTokCoreLogic.cryptoLock.lock()
        if let cached = MTMediaTokCoreLogic.pbkdf2Cache[cacheKey] {
            MTMediaTokCoreLogic.cryptoLock.unlock()
            return cached
        }
        MTMediaTokCoreLogic.cryptoLock.unlock()

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
        MTMediaTokCoreLogic.cryptoLock.lock()
        if MTMediaTokCoreLogic.pbkdf2Cache.count > 256 {
            MTMediaTokCoreLogic.pbkdf2Cache.removeAll()
        }
        MTMediaTokCoreLogic.pbkdf2Cache[cacheKey] = key
        MTMediaTokCoreLogic.cryptoLock.unlock()
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
        guard let key = MTMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: passphrase, salt: salt) else {
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
        return MTMediaTokCoreLogic.prefixV2 + b64
    }

    static func decryptAny(_ ciphertext: String, passphrase: String, peerKey: String) -> String? {
        if ciphertext.hasPrefix(MTMediaTokCoreLogic.prefixV2) {
            var b64 = String(ciphertext.dropFirst(MTMediaTokCoreLogic.prefixV2.count))
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
            guard let key = MTMediaTokCoreLogic.deriveKeyPBKDF2(passphrase: passphrase, salt: salt),
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
        if ciphertext.hasPrefix(MTMediaTokCoreLogic.prefixV1) {
            var b64 = String(ciphertext.dropFirst(MTMediaTokCoreLogic.prefixV1.count))
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let rem = b64.count % 4
            if rem > 0 { b64.append(String(repeating: "=", count: 4 - rem)) }
            guard let raw = Data(base64Encoded: b64),
                  let box = try? AES.GCM.SealedBox(combined: raw) else {
                return nil
            }
            let key = MTMediaTokCoreLogic.deriveLegacyKeyV1(passphrase: passphrase)
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
        MTMediaTokCoreLogic.appendU16(&d, UInt16(bitPattern: v))
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
        MTMediaTokCoreLogic.appendS16(&out, Int16(rects.count))
        MTMediaTokCoreLogic.appendS16(&out, Int16(xMin))
        MTMediaTokCoreLogic.appendS16(&out, Int16(yMin))
        MTMediaTokCoreLogic.appendS16(&out, Int16(xMax))
        MTMediaTokCoreLogic.appendS16(&out, Int16(yMax))
        for i in 0 ..< rects.count {
            MTMediaTokCoreLogic.appendU16(&out, UInt16(i * 4 + 3))
        }
        MTMediaTokCoreLogic.appendU16(&out, 0)
        out.append(contentsOf: [UInt8](repeating: 1, count: rects.count * 4))
        var prevX = 0
        for r in rects {
            for x in [r.x1, r.x1, r.x2, r.x2] {
                MTMediaTokCoreLogic.appendS16(&out, Int16(x - prevX))
                prevX = x
            }
        }
        var prevY = 0
        for r in rects {
            for y in [r.y1, r.y2, r.y2, r.y1] {
                MTMediaTokCoreLogic.appendS16(&out, Int16(y - prevY))
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
        let macName = MTMediaTokCoreLogic.transliterateAscii(fontName)
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
            MTMediaTokCoreLogic.appendU32(&loca, UInt32(glyf.count))
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
            glyf.append(MTMediaTokCoreLogic.buildSimpleGlyph(rects))
            MTMediaTokCoreLogic.appendU16(&hmtx, adv)
            MTMediaTokCoreLogic.appendS16(&hmtx, lsb)
            maxPoints = max(maxPoints, UInt16(rects.count * 4))
            maxContours = max(maxContours, UInt16(rects.count))
        }
        MTMediaTokCoreLogic.appendU32(&loca, UInt32(glyf.count))

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
        MTMediaTokCoreLogic.appendU16(&fmt4, 4)
        MTMediaTokCoreLogic.appendU16(&fmt4, 16 + segCount * 8)
        MTMediaTokCoreLogic.appendU16(&fmt4, 0)
        MTMediaTokCoreLogic.appendU16(&fmt4, segCount * 2)
        MTMediaTokCoreLogic.appendU16(&fmt4, sr)
        MTMediaTokCoreLogic.appendU16(&fmt4, es)
        MTMediaTokCoreLogic.appendU16(&fmt4, rs)
        for s in segs { MTMediaTokCoreLogic.appendU16(&fmt4, s.end) }
        MTMediaTokCoreLogic.appendU16(&fmt4, 0)
        for s in segs { MTMediaTokCoreLogic.appendU16(&fmt4, s.start) }
        for s in segs { MTMediaTokCoreLogic.appendU16(&fmt4, s.delta) }
        for _ in segs { MTMediaTokCoreLogic.appendU16(&fmt4, 0) }

        var cmap = Data()
        MTMediaTokCoreLogic.appendU16(&cmap, 0)
        MTMediaTokCoreLogic.appendU16(&cmap, 2)
        MTMediaTokCoreLogic.appendU16(&cmap, 0); MTMediaTokCoreLogic.appendU16(&cmap, 3); MTMediaTokCoreLogic.appendU32(&cmap, 20)
        MTMediaTokCoreLogic.appendU16(&cmap, 3); MTMediaTokCoreLogic.appendU16(&cmap, 1); MTMediaTokCoreLogic.appendU32(&cmap, 20)
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
            for unit in s.utf16 { MTMediaTokCoreLogic.appendU16(&b, unit) }
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
            for unit in s.utf16 { MTMediaTokCoreLogic.appendU16(&b, unit) }
            recs.append(TtfNameRec(pid: 3, eid: 1, lid: 0x0409, nid: nid, len: UInt16(b.count), off: UInt16(strBlob.count)))
            strBlob.append(b)
        }
        recs.sort { ($0.pid, $0.eid, $0.lid, $0.nid) < ($1.pid, $1.eid, $1.lid, $1.nid) }

        var nameTbl = Data()
        MTMediaTokCoreLogic.appendU16(&nameTbl, 0)
        MTMediaTokCoreLogic.appendU16(&nameTbl, UInt16(recs.count))
        MTMediaTokCoreLogic.appendU16(&nameTbl, UInt16(6 + recs.count * 12))
        for r in recs {
            MTMediaTokCoreLogic.appendU16(&nameTbl, r.pid)
            MTMediaTokCoreLogic.appendU16(&nameTbl, r.eid)
            MTMediaTokCoreLogic.appendU16(&nameTbl, r.lid)
            MTMediaTokCoreLogic.appendU16(&nameTbl, r.nid)
            MTMediaTokCoreLogic.appendU16(&nameTbl, r.len)
            MTMediaTokCoreLogic.appendU16(&nameTbl, r.off)
        }
        nameTbl.append(strBlob)

        var head = Data()
        MTMediaTokCoreLogic.appendU32(&head, 0x00010000); MTMediaTokCoreLogic.appendU32(&head, 0x00010000)
        MTMediaTokCoreLogic.appendU32(&head, 0); MTMediaTokCoreLogic.appendU32(&head, 0x5F0F3CF5)
        MTMediaTokCoreLogic.appendU16(&head, 0x000B); MTMediaTokCoreLogic.appendU16(&head, 1000)
        for _ in 0 ..< 4 { MTMediaTokCoreLogic.appendU32(&head, 0) }
        MTMediaTokCoreLogic.appendS16(&head, 0); MTMediaTokCoreLogic.appendS16(&head, -200)
        MTMediaTokCoreLogic.appendS16(&head, 1000); MTMediaTokCoreLogic.appendS16(&head, 900)
        MTMediaTokCoreLogic.appendU16(&head, 0); MTMediaTokCoreLogic.appendU16(&head, 8)
        MTMediaTokCoreLogic.appendS16(&head, 2); MTMediaTokCoreLogic.appendS16(&head, 1); MTMediaTokCoreLogic.appendS16(&head, 0)

        var hhea = Data()
        MTMediaTokCoreLogic.appendU32(&hhea, 0x00010000)
        MTMediaTokCoreLogic.appendS16(&hhea, 850); MTMediaTokCoreLogic.appendS16(&hhea, -200)
        MTMediaTokCoreLogic.appendS16(&hhea, 50); MTMediaTokCoreLogic.appendU16(&hhea, 1000)
        MTMediaTokCoreLogic.appendS16(&hhea, 0); MTMediaTokCoreLogic.appendS16(&hhea, 0)
        MTMediaTokCoreLogic.appendS16(&hhea, 1000); MTMediaTokCoreLogic.appendS16(&hhea, 1)
        for _ in 0 ..< 7 { MTMediaTokCoreLogic.appendS16(&hhea, 0) }
        MTMediaTokCoreLogic.appendU16(&hhea, numGlyphs)

        var maxp = Data()
        MTMediaTokCoreLogic.appendU32(&maxp, 0x00010000)
        MTMediaTokCoreLogic.appendU16(&maxp, numGlyphs)
        MTMediaTokCoreLogic.appendU16(&maxp, maxPoints)
        MTMediaTokCoreLogic.appendU16(&maxp, maxContours)
        MTMediaTokCoreLogic.appendU16(&maxp, 0); MTMediaTokCoreLogic.appendU16(&maxp, 0); MTMediaTokCoreLogic.appendU16(&maxp, 2)
        for _ in 0 ..< 8 { MTMediaTokCoreLogic.appendU16(&maxp, 0) }

        var os2 = Data()
        MTMediaTokCoreLogic.appendU16(&os2, 3); MTMediaTokCoreLogic.appendS16(&os2, 600)
        MTMediaTokCoreLogic.appendU16(&os2, 400); MTMediaTokCoreLogic.appendU16(&os2, 5); MTMediaTokCoreLogic.appendS16(&os2, 0)
        MTMediaTokCoreLogic.appendS16(&os2, 650); MTMediaTokCoreLogic.appendS16(&os2, 600); MTMediaTokCoreLogic.appendS16(&os2, 0); MTMediaTokCoreLogic.appendS16(&os2, 75)
        MTMediaTokCoreLogic.appendS16(&os2, 650); MTMediaTokCoreLogic.appendS16(&os2, 600); MTMediaTokCoreLogic.appendS16(&os2, 0); MTMediaTokCoreLogic.appendS16(&os2, 350)
        MTMediaTokCoreLogic.appendS16(&os2, 50); MTMediaTokCoreLogic.appendS16(&os2, 300); MTMediaTokCoreLogic.appendS16(&os2, 0)
        os2.append(contentsOf: [2, 0, 5, 3, 0, 0, 0, 0, 0, 0])
        MTMediaTokCoreLogic.appendU32(&os2, 0x00000201); MTMediaTokCoreLogic.appendU32(&os2, 0); MTMediaTokCoreLogic.appendU32(&os2, 0); MTMediaTokCoreLogic.appendU32(&os2, 0)
        os2.append(contentsOf: [UInt8]("MTOK".utf8))
        MTMediaTokCoreLogic.appendU16(&os2, 0x0040); MTMediaTokCoreLogic.appendU16(&os2, 32)
        MTMediaTokCoreLogic.appendU16(&os2, mappedCps.last ?? 0x04FF)
        MTMediaTokCoreLogic.appendS16(&os2, 850); MTMediaTokCoreLogic.appendS16(&os2, -200); MTMediaTokCoreLogic.appendS16(&os2, 50)
        MTMediaTokCoreLogic.appendU16(&os2, 900); MTMediaTokCoreLogic.appendU16(&os2, 250)
        MTMediaTokCoreLogic.appendU32(&os2, 0x00000005); MTMediaTokCoreLogic.appendU32(&os2, 0)
        MTMediaTokCoreLogic.appendS16(&os2, 500); MTMediaTokCoreLogic.appendS16(&os2, 720)
        MTMediaTokCoreLogic.appendU16(&os2, 0); MTMediaTokCoreLogic.appendU16(&os2, 32); MTMediaTokCoreLogic.appendU16(&os2, 0)

        var post = Data()
        MTMediaTokCoreLogic.appendU32(&post, 0x00030000); MTMediaTokCoreLogic.appendU32(&post, 0)
        MTMediaTokCoreLogic.appendS16(&post, -100); MTMediaTokCoreLogic.appendS16(&post, 50)
        for _ in 0 ..< 5 { MTMediaTokCoreLogic.appendU32(&post, 0) }

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
        MTMediaTokCoreLogic.appendU32(&full, 0x00010000)
        MTMediaTokCoreLogic.appendU16(&full, nt)
        MTMediaTokCoreLogic.appendU16(&full, tsr)
        MTMediaTokCoreLogic.appendU16(&full, tes)
        MTMediaTokCoreLogic.appendU16(&full, trs)

        var offset = UInt32(12 + Int(nt) * 16)
        var headOffset = 0
        var body = Data()
        for (tag, data) in tables {
            full.append(contentsOf: [UInt8](tag.utf8))
            MTMediaTokCoreLogic.appendU32(&full, MTMediaTokCoreLogic.calcChecksum(data))
            MTMediaTokCoreLogic.appendU32(&full, offset)
            MTMediaTokCoreLogic.appendU32(&full, UInt32(data.count))
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
        let adj = UInt32(0xB1B0AFBA) &- MTMediaTokCoreLogic.calcChecksum(full)
        full[headOffset + 8] = UInt8((adj >> 24) & 0xFF)
        full[headOffset + 9] = UInt8((adj >> 16) & 0xFF)
        full[headOffset + 10] = UInt8((adj >> 8) & 0xFF)
        full[headOffset + 11] = UInt8(adj & 0xFF)
        return full
    }

    // MARK: - 8. Personal /stickers 10K Vault Search, Translit & Vision Tagging

    struct StickerEntry: Codable, Equatable {
        let id: String
        let fileName: String
        var tags: [String]
        var ocrText: String
        var visionLabels: [String]
        let addedAt: Int64
        var usageCount: Int
    }

    static func normalizeSearchText(_ text: String) -> String {
        let lower = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        var out = ""
        out.reserveCapacity(lower.count)
        var lastWasSpace = true
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let ruToEnMap: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ж": "zh",
        "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n",
        "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
        "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y",
        "ь": "", "э": "e", "ю": "yu", "я": "ya"
    ]

    private static let enToRuDigraphs: [(String, String)] = [
        ("sch", "щ"), ("shch", "щ"), ("zh", "ж"), ("ch", "ч"), ("sh", "ш"),
        ("yu", "ю"), ("ya", "я"), ("yo", "е"), ("ts", "ц"), ("kh", "х")
    ]

    private static let enToRuSingle: [Character: String] = [
        "a": "а", "b": "б", "c": "к", "d": "д", "e": "е", "f": "ф", "g": "г",
        "h": "х", "i": "и", "j": "дж", "k": "к", "l": "л", "m": "м", "n": "н",
        "o": "о", "p": "п", "q": "к", "r": "р", "s": "с", "t": "т", "u": "у",
        "v": "в", "w": "в", "x": "кс", "y": "и", "z": "з"
    ]

    static func ruEnTranslitVariants(_ token: String) -> [String] {
        let norm = MTMediaTokCoreLogic.normalizeSearchText(token)
        guard !norm.isEmpty else { return [] }
        var variants: [String] = [norm]

        var toLatin = ""
        for ch in norm {
            if let rep = MTMediaTokCoreLogic.ruToEnMap[ch] {
                toLatin += rep
            } else {
                toLatin.append(ch)
            }
        }
        if !toLatin.isEmpty && !variants.contains(toLatin) {
            variants.append(toLatin)
        }
        // Also collapse double letters (e.g., "mellstroy" <-> "мелстрой")
        let altLatin = toLatin.replacingOccurrences(of: "h", with: "")
        if !altLatin.isEmpty && !variants.contains(altLatin) {
            variants.append(altLatin)
        }

        // Phonetic Latin -> Cyrillic
        var idx = norm.startIndex
        var toCyr = ""
        while idx < norm.endIndex {
            var matched = false
            for (digraph, cyr) in MTMediaTokCoreLogic.enToRuDigraphs {
                if norm[idx...].hasPrefix(digraph) {
                    toCyr += cyr
                    idx = norm.index(idx, offsetBy: digraph.count)
                    matched = true
                    break
                }
            }
            if !matched {
                let ch = norm[idx]
                if let rep = MTMediaTokCoreLogic.enToRuSingle[ch] {
                    toCyr += rep
                } else {
                    toCyr.append(ch)
                }
                idx = norm.index(after: idx)
            }
        }
        if !toCyr.isEmpty && !variants.contains(toCyr) {
            variants.append(toCyr)
        }
        if norm.contains("ll") {
            let singleL = toCyr.replacingOccurrences(of: "лл", with: "л")
            if !variants.contains(singleL) {
                variants.append(singleL)
            }
        } else if norm.contains("елс") || norm.contains("els") {
            let doubleL = norm.replacingOccurrences(of: "лс", with: "ллс")
            if !variants.contains(doubleL) {
                variants.append(doubleL)
            }
        }
        return variants
    }

    static func visionLabelToRussianTags(_ identifier: String) -> [String] {
        let key = identifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        let clean = key.replacingOccurrences(of: "_", with: " ")
        var result: [String] = [clean]
        let mapping: [(String, [String])] = [
            ("cat", ["кот", "котик", "кошка", "мем"]),
            ("dog", ["собака", "пес", "песик", "мем"]),
            ("person", ["человек", "лицо", "парень", "девушка", "чел"]),
            ("face", ["лицо", "эмоция", "рофл"]),
            ("cartoon", ["мульт", "аниме", "арт", "персонаж"]),
            ("anime", ["аниме", "тян", "кун"]),
            ("car", ["машина", "тачка", "авто"]),
            ("food", ["еда", "вкусно", "жрать"]),
            ("fire", ["огонь", "горит", "краш", "имба"]),
            ("flower", ["цветы", "цветок", "букет"]),
            ("money", ["деньги", "кеш", "доллар", "бабки", "лут"]),
            ("computer", ["комп", "пк", "код", "прогер"]),
            ("weapon", ["оружие", "пушка", "нож", "шутер"]),
            ("heart", ["сердце", "любовь", "лайк"]),
            ("smile", ["смайл", "улыбка", "угар", "смех"]),
            ("text", ["текст", "цитата", "надпись"]),
            ("screenshot", ["скрин", "скриншот", "мем"]),
            ("sport", ["спорт", "качалка", "гигачад"]),
            ("music", ["музыка", "трек", "вайб"]),
            ("animal", ["животное", "зверь"]),
            ("bird", ["птица", "голубь", "утка"])
        ]
        for (needle, extra) in mapping {
            if clean.contains(needle) {
                for tag in extra where !result.contains(tag) {
                    result.append(tag)
                }
            }
        }
        return result
    }

    static func searchStickers(_ entries: [StickerEntry], query: String, limit: Int = 80) -> [StickerEntry] {
        let normQuery = MTMediaTokCoreLogic.normalizeSearchText(query)
        let cap = max(1, limit)
        if normQuery.isEmpty {
            return Array(entries.sorted {
                if $0.usageCount != $1.usageCount { return $0.usageCount > $1.usageCount }
                return $0.addedAt > $1.addedAt
            }.prefix(cap))
        }

        let tokens = normQuery.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return Array(entries.prefix(cap))
        }
        let tokenVariants: [[String]] = tokens.map { MTMediaTokCoreLogic.ruEnTranslitVariants($0) }

        var scored: [(entry: StickerEntry, score: Int)] = []
        scored.reserveCapacity(min(entries.count, cap * 2))

        for entry in entries {
            let joinedTags = MTMediaTokCoreLogic.normalizeSearchText(entry.tags.joined(separator: " "))
            let joinedVision = MTMediaTokCoreLogic.normalizeSearchText(entry.visionLabels.joined(separator: " "))
            let normOcr = MTMediaTokCoreLogic.normalizeSearchText(entry.ocrText)
            let normFile = MTMediaTokCoreLogic.normalizeSearchText(entry.fileName)

            var totalScore = 0
            var matchedAllTokens = true

            for variants in tokenVariants {
                var bestTokenScore = 0
                for variant in variants where !variant.isEmpty {
                    if entry.tags.contains(where: { MTMediaTokCoreLogic.normalizeSearchText($0) == variant }) {
                        bestTokenScore = max(bestTokenScore, 120)
                    } else if joinedTags.contains(variant) {
                        bestTokenScore = max(bestTokenScore, 90)
                    }
                    if normOcr.contains(variant) {
                        bestTokenScore = max(bestTokenScore, 75)
                    }
                    if joinedVision.contains(variant) {
                        bestTokenScore = max(bestTokenScore, 55)
                    }
                    if normFile.contains(variant) {
                        bestTokenScore = max(bestTokenScore, 40)
                    }
                }
                if bestTokenScore == 0 {
                    matchedAllTokens = false
                    break
                }
                totalScore += bestTokenScore
            }

            if matchedAllTokens {
                totalScore += min(entry.usageCount, 50)
                scored.append((entry, totalScore))
            }
        }

        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.entry.usageCount != $1.entry.usageCount { return $0.entry.usageCount > $1.entry.usageCount }
            return $0.entry.addedAt > $1.entry.addedAt
        }
        return Array(scored.prefix(cap).map { $0.entry })
    }

    // MARK: - 9. Malicious Document / APK / RLO Trojan Inspector

    struct DocumentThreat: Equatable {
        let isCritical: Bool
        let reason: String
    }

    private static let dangerousDocExtensions: Set<String> = [
        "apk", "exe", "scr", "bat", "cmd", "vbs", "vbe", "ps1",
        "msi", "hta", "lnk", "jar", "com", "pif", "reg", "mobileconfig", "ipa"
    ]

    static func inspectIncomingDocument(fileName: String, mimeType: String) -> DocumentThreat? {
        // Check BiDi / Right-to-Left Override spoofing characters (e.g., "photo_gnp.exe")
        for scalar in fileName.unicodeScalars {
            let v = scalar.value
            if (v >= 0x202A && v <= 0x202E) || (v >= 0x2066 && v <= 0x2069) {
                return DocumentThreat(
                    isCritical: true,
                    reason: "Подмена расширения скрытыми символами RLO/BiDi!"
                )
            }
        }

        let lowerName = fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerMime = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !lowerName.isEmpty {
            let parts = lowerName.split(separator: ".").map { String($0) }
            if let lastExt = parts.last, parts.count >= 2, MTMediaTokCoreLogic.dangerousDocExtensions.contains(lastExt) {
                if parts.count >= 3 {
                    let prevExt = parts[parts.count - 2]
                    if ["jpg", "jpeg", "png", "gif", "webp", "pdf", "doc", "docx", "txt", "mp4", "mp3", "zip", "rar"].contains(prevExt) {
                        return DocumentThreat(
                            isCritical: true,
                            reason: "Двойное расширение .\((prevExt)).\(lastExt) — возможен троян/маскировка!"
                        )
                    }
                }
                if lastExt == "apk" {
                    return DocumentThreat(isCritical: true, reason: "Android APK-файл — проверяйте источник перед передачей!")
                }
                if lastExt == "mobileconfig" {
                    return DocumentThreat(isCritical: true, reason: "Профиль конфигурации iOS (.mobileconfig) — может менять DNS/VPN/сертификаты!")
                }
                if ["exe", "scr", "bat", "cmd", "vbs", "ps1", "hta", "msi"].contains(lastExt) {
                    return DocumentThreat(isCritical: true, reason: "Исполняемый файл (.\(lastExt)) — опасен для Windows/ПК!")
                }
                return DocumentThreat(isCritical: false, reason: "Установочный / скриптовый файл (.\(lastExt))")
            }
        }

        if lowerMime == "application/vnd.android.package-archive" {
            return DocumentThreat(isCritical: true, reason: "Android APK-пакет — проверяйте источник!")
        }
        if lowerMime == "application/x-msdownload" || lowerMime == "application/x-dosexec" {
            return DocumentThreat(isCritical: true, reason: "Исполняемый Windows EXE/DLL-файл!")
        }
        if lowerMime == "application/x-apple-aspen-config" {
            return DocumentThreat(isCritical: true, reason: "Профиль конфигурации iOS (.mobileconfig)!")
        }
        return nil
    }

    // MARK: - 10. Chat Streaks Engine (Огоньки + Заморозка)

    struct StreakRecord: Codable, Equatable {
        var currentStreak: Int
        var bestStreak: Int
        var lastDayKey: String
        var freezesRemaining: Int
        var freezeMonthKey: String
        var totalMessages: Int
    }

    private static func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return cal
    }

    private static func parseDayKey(_ dayKey: String) -> Date? {
        let comps = dayKey.split(separator: "-")
        guard comps.count == 3,
              let y = Int(comps[0]),
              let m = Int(comps[1]),
              let d = Int(comps[2]),
              y >= 1970, (1 ... 12).contains(m), (1 ... 31).contains(d) else {
            return nil
        }
        var dc = DateComponents()
        dc.calendar = MTMediaTokCoreLogic.utcCalendar()
        dc.timeZone = TimeZone(secondsFromGMT: 0)
        dc.year = y
        dc.month = m
        dc.day = d
        return dc.date
    }

    static func dayDiffBetween(oldDayKey: String, newDayKey: String) -> Int? {
        guard let d1 = MTMediaTokCoreLogic.parseDayKey(oldDayKey),
              let d2 = MTMediaTokCoreLogic.parseDayKey(newDayKey) else {
            return nil
        }
        return MTMediaTokCoreLogic.utcCalendar().dateComponents([.day], from: d1, to: d2).day
    }

    static func applyStreakActivity(
        record: StreakRecord?,
        dayKey: String,
        monthKey: String
    ) -> (updated: StreakRecord, usedFreeze: Bool, milestoneReached: Int?) {
        guard var current = record else {
            let fresh = StreakRecord(
                currentStreak: 1,
                bestStreak: 1,
                lastDayKey: dayKey,
                freezesRemaining: 2,
                freezeMonthKey: monthKey,
                totalMessages: 1
            )
            return (fresh, false, nil)
        }

        if current.freezeMonthKey != monthKey {
            current.freezeMonthKey = monthKey
            current.freezesRemaining = 2
        }

        if current.lastDayKey == dayKey {
            current.totalMessages += 1
            return (current, false, nil)
        }

        var usedFreeze = false
        var milestone: Int?
        let diff = MTMediaTokCoreLogic.dayDiffBetween(oldDayKey: current.lastDayKey, newDayKey: dayKey) ?? 999

        if diff < 0 {
            // Do not regress or overwrite newer local state with stale clock timestamp
            return (current, false, nil)
        } else if diff == 1 {
            current.currentStreak += 1
        } else if diff == 2 && current.freezesRemaining > 0 {
            current.freezesRemaining -= 1
            current.currentStreak += 1
            usedFreeze = true
        } else {
            current.currentStreak = 1
        }

        if current.currentStreak > current.bestStreak {
            current.bestStreak = current.currentStreak
        }
        current.lastDayKey = dayKey
        current.totalMessages += 1

        let milestones = [7, 30, 100, 365]
        if milestones.contains(current.currentStreak) {
            milestone = current.currentStreak
        }
        return (current, usedFreeze, milestone)
    }

    static func streakTierBadge(days: Int) -> String {
        if days >= 365 { return "🌈" }
        if days >= 100 { return "🟣" }
        if days >= 30 { return "🔵" }
        if days >= 7 { return "🟠" }
        return "🔥"
    }

    // MARK: - 11. Info-Card (.card) Command Parser

    struct CardPayload: Equatable {
        let title: String
        let subtitle: String
        let lines: [String]
    }

    static func parseCardCommand(_ text: String) -> CardPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(".card ") else { return nil }
        let body = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let rawParts = body.components(separatedBy: "|").map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        }
        let nonEmpty = rawParts.filter { !$0.isEmpty }
        guard let title = nonEmpty.first, !title.isEmpty else { return nil }
        let subtitle = nonEmpty.count >= 2 ? nonEmpty[1] : ""
        let lines = nonEmpty.count >= 3 ? Array(nonEmpty.dropFirst(2).prefix(6)) : []
        return CardPayload(title: title, subtitle: subtitle, lines: lines)
    }

    // MARK: - 12. Live Music (ListenBrainz / Last.fm) & Connections Parsers

    struct LiveMusicTrack: Equatable {
        let artist: String
        let track: String
        let isLive: Bool
    }

    static func parseListenBrainzJson(_ data: Data) -> LiveMusicTrack? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let listens = payload["listens"] as? [[String: Any]],
              let first = listens.first,
              let meta = first["track_metadata"] as? [String: Any] else {
            return nil
        }
        let artist = (meta["artist_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let track = (meta["track_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !track.isEmpty else { return nil }
        let playingNow = (payload["playing_now"] as? Bool ?? false) || (first["playing_now"] as? Bool ?? false)
        return LiveMusicTrack(artist: artist, track: track, isLive: playingNow)
    }

    static func parseLastFmHtml(_ html: String) -> LiveMusicTrack? {
        guard let tbodyStart = html.range(of: "<tr"),
              let rowEnd = html.range(of: "</tr>", range: tbodyStart.lowerBound ..< html.endIndex) else {
            return nil
        }
        let row = String(html[tbodyStart.lowerBound ..< rowEnd.upperBound])
        let isLive = row.contains("chartlist-now-scrobbling") || row.lowercased().contains("scrobbling now")

        func extractClassText(_ className: String) -> String {
            guard let marker = row.range(of: className),
                  let tagClose = row.range(of: ">", range: marker.upperBound ..< row.endIndex),
                  let aStart = row.range(of: "<a", range: tagClose.upperBound ..< row.endIndex),
                  let aClose = row.range(of: ">", range: aStart.upperBound ..< row.endIndex),
                  let aEnd = row.range(of: "</a>", range: aClose.upperBound ..< row.endIndex) else {
                return ""
            }
            return MTMediaTokCoreLogic.decodeBasicHtmlEntities(String(row[aClose.upperBound ..< aEnd.lowerBound]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let track = extractClassText("chartlist-name")
        let artist = extractClassText("chartlist-artist")
        guard !track.isEmpty else { return nil }
        return LiveMusicTrack(artist: artist, track: track, isLive: isLive)
    }

    private static func decodeBasicHtmlEntities(_ input: String) -> String {
        return input
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }

    static func normalizeConnection(platform: String, raw: String) -> (label: String, handle: String, url: URL)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(".."), !s.contains("\\") else { return nil }
        let p = platform.lowercased()

        if p == "discord" {
            let clean = s.hasPrefix("@") ? String(s.dropFirst()) : s
            guard !clean.isEmpty, clean.count <= 48, !clean.contains("@"),
                  clean.allSatisfy({ $0.isASCII && !$0.isWhitespace }) else {
                return nil
            }
            guard let u = URL(string: "https://discord.com/users/\(clean)") else { return nil }
            return ("Discord", clean, u)
        }

        if let schemeRange = s.range(of: "://") {
            let scheme = s[..<schemeRange.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
            if let slashIdx = s[schemeRange.upperBound...].lastIndex(of: "/") {
                let tail = String(s[s.index(after: slashIdx)...])
                if !tail.isEmpty { s = tail }
            }
        }
        if let qIdx = s.firstIndex(of: "?") { s = String(s[..<qIdx]) }
        if let fIdx = s.firstIndex(of: "#") { s = String(s[..<fIdx]) }
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasPrefix("@") { s.removeFirst() }
        guard !s.isEmpty, s.count <= 64, !s.contains("@"), !s.contains("/") else { return nil }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        switch p {
        case "twitch":
            guard let u = URL(string: "https://www.twitch.tv/\(s)") else { return nil }
            return ("Twitch", s, u)
        case "github":
            guard let u = URL(string: "https://github.com/\(s)") else { return nil }
            return ("GitHub", s, u)
        case "youtube":
            guard let u = URL(string: "https://www.youtube.com/@\(s)") else { return nil }
            return ("YouTube", "@\(s)", u)
        case "tiktok":
            guard let u = URL(string: "https://www.tiktok.com/@\(s)") else { return nil }
            return ("TikTok", "@\(s)", u)
        case "kick":
            guard let u = URL(string: "https://kick.com/\(s)") else { return nil }
            return ("Kick", s, u)
        default:
            return nil
        }
    }

    // MARK: - 13. LAN Wi-Fi Uploader Helpers

    static func sanitizeUploadFileName(_ raw: String) -> String {
        let base = raw
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map { String($0) } ?? "upload"
        let replaced = base.replacingOccurrences(of: "..", with: "_")
        let safeScalars = replaced.unicodeScalars.filter { scalar in
            if scalar.value < 32 || scalar.value == 127 { return false }
            return !CharacterSet(charactersIn: "/\\:*?\"<>|\0").contains(scalar)
        }
        let cleaned = String(String.UnicodeScalarView(safeScalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "file_\(Int(Date().timeIntervalSince1970))"
        }
        return String(cleaned.prefix(80))
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let bytesA = Array(a.utf8)
        let bytesB = Array(b.utf8)
        guard bytesA.count == bytesB.count else { return false }
        var diff: UInt8 = 0
        for i in 0 ..< bytesA.count {
            diff |= bytesA[i] ^ bytesB[i]
        }
        return diff == 0
    }

    // MARK: - 14. Scratch Message Command Parser

    struct ScratchPayload: Equatable {
        let title: String
        let secret: String
        let seed: UInt64
    }

    static func parseScratchCommand(_ raw: String) -> ScratchPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(".scratch") else { return nil }
        let rest = trimmed.dropFirst(".scratch".count).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty { return nil }

        let title: String
        let secret: String
        if let barIdx = rest.firstIndex(of: "|") {
            title = String(rest[..<barIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            secret = String(rest[rest.index(after: barIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            title = "Секретный билет 🎟️"
            secret = rest
        }
        guard !secret.isEmpty else { return nil }

        var h: UInt64 = 14695981039346656037
        for b in secret.utf8 {
            h ^= UInt64(b)
            h &*= 1099511628211
        }
        return ScratchPayload(
            title: String(title.prefix(40)),
            secret: String(secret.prefix(500)),
            seed: h
        )
    }

    // MARK: - 15. Bidirectional Keyboard Layout Fixer (.fix / .ghbdtn)

    private static let qwertyLower = "qwertyuiop[]asdfghjkl;'zxcvbnm,./`"
    private static let jcukenLower = "йцукенгшщзхъфывапролджэячсмитьбю.ё"
    private static let qwertyUpper = "QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~"
    private static let jcukenUpper = "ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё"

    static func fixKeyboardLayout(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var ruCount = 0
        var enCount = 0
        for ch in text {
            if ("а"..."я").contains(ch) || ("А"..."Я").contains(ch) || ch == "ё" || ch == "Ё" {
                ruCount += 1
            } else if ("a"..."z").contains(ch) || ("A"..."Z").contains(ch) {
                enCount += 1
            }
        }
        let toRussian = enCount >= ruCount

        var enToRu: [Character: Character] = [:]
        var ruToEn: [Character: Character] = [:]

        let ql = Array(qwertyLower)
        let jl = Array(jcukenLower)
        for i in 0 ..< min(ql.count, jl.count) {
            enToRu[ql[i]] = jl[i]
            ruToEn[jl[i]] = ql[i]
        }
        let qu = Array(qwertyUpper)
        let ju = Array(jcukenUpper)
        for i in 0 ..< min(qu.count, ju.count) {
            enToRu[qu[i]] = ju[i]
            ruToEn[ju[i]] = qu[i]
        }

        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            if toRussian {
                result.append(enToRu[ch] ?? ch)
            } else {
                result.append(ruToEn[ch] ?? ch)
            }
        }
        return result
    }

    /// Detects whether `text` plausibly looks like a message typed in the wrong QWERTY/JCUKEN keyboard layout,
    /// returning the direction label (`"EN → RU"` or `"RU → EN"`) and converted text, or `nil` for normal text/URLs.
    static func detectWrongLayoutSuggestion(_ text: String) -> (direction: String, converted: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 600 else { return nil }
        let low = trimmed.lowercased()
        if low.contains("http://") || low.contains("https://") || low.contains("t.me/") || low.hasPrefix("/") || low.hasPrefix("@") {
            return nil
        }

        var ruLetters = 0
        var enLetters = 0
        for ch in low {
            if ("а" ... "я").contains(ch) || ch == "ё" {
                ruLetters += 1
            } else if ("a" ... "z").contains(ch) {
                enLetters += 1
            }
        }
        guard (ruLetters + enLetters) >= 3 else { return nil }
        let converted = MTMediaTokCoreLogic.fixKeyboardLayout(trimmed)
        guard converted != trimmed else { return nil }
        let convLow = converted.lowercased()

        let ruVowels: Set<Character> = Set("аеёиоуыэюя")
        let enVowels: Set<Character> = Set("aeiouy")

        if enLetters >= 3 && ruLetters == 0 {
            let enVowelCount = low.filter { enVowels.contains($0) }.count
            let convRuVowelCount = convLow.filter { ruVowels.contains($0) }.count
            let hasJcukenPunctInsideWord = trimmed.range(of: #"[A-Za-z][\[\];',.`][A-Za-z]"#, options: .regularExpression) != nil
            let enRatio = Double(enVowelCount) / Double(max(1, enLetters))
            let ruRatio = Double(convRuVowelCount) / Double(max(1, enLetters))
            if convRuVowelCount >= 1 && (hasJcukenPunctInsideWord || (enRatio < 0.22 && ruRatio >= 0.25)) {
                return ("EN → RU", converted)
            }
            return nil
        }

        if ruLetters >= 3 && enLetters == 0 {
            let ruVowelCount = low.filter { ruVowels.contains($0) }.count
            let convEnVowelCount = convLow.filter { enVowels.contains($0) }.count
            let hasWeirdRuCluster = low.contains("щк") || low.contains("цщ") || low.contains("ддщ") || low.contains("еуы") || low.contains("фвм") || low.contains("Зф") || low.contains("рудд")
            let ruRatio = Double(ruVowelCount) / Double(max(1, ruLetters))
            let enRatio = Double(convEnVowelCount) / Double(max(1, ruLetters))
            if convEnVowelCount >= 1 && (hasWeirdRuCluster || (ruRatio < 0.20 && enRatio >= 0.25)) {
                return ("RU → EN", converted)
            }
            return nil
        }

        return nil
    }

    static func parseFixCommand(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix(".fix ") {
            let body = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : fixKeyboardLayout(body)
        } else if trimmed.lowercased().hasPrefix(".ghbdtn ") {
            let body = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : fixKeyboardLayout(body)
        } else if trimmed.lowercased() == ".fix" || trimmed.lowercased() == ".ghbdtn" {
            return ""
        }
        return nil
    }

    // MARK: - 16. MediaTok Achievements System

    enum AchievementId: String, CaseIterable, Codable {
        case nightOwl = "night_owl"
        case stickerCollector = "sticker_collector"
        case fontStylist = "font_stylist"
        case e2eMaster = "e2e_master"
        case audiophile = "audiophile"
        case streak7d = "streak_7d"
        case streak30d = "streak_30d"
        case metaCleaner = "meta_cleaner"
        case gamer = "gamer"
        case liquidGlass = "liquid_glass"
        case callGuard = "call_guard"
        case mediatokOg = "mediatok_og"
    }

    struct AchievementDef: Equatable {
        let id: AchievementId
        let title: String
        let subtitle: String
        let icon: String
        let rarity: String
    }

    static let allAchievements: [AchievementDef] = [
        AchievementDef(id: .mediatokOg, title: "MediaTok OG", subtitle: "Первые шаги в MediaTok iOS", icon: "👑", rarity: "Обычная"),
        AchievementDef(id: .nightOwl, title: "Ночной призрак", subtitle: "Активность в чате с 03:00 до 05:00", icon: "🌙", rarity: "Редкая"),
        AchievementDef(id: .stickerCollector, title: "Стикермагнат", subtitle: "Более 50 стикеров в /stickers", icon: "🗃️", rarity: "Эпическая"),
        AchievementDef(id: .fontStylist, title: "Шрифтовой маньяк", subtitle: "Установлен собственный TTF/OTF шрифт", icon: "🎨", rarity: "Редкая"),
        AchievementDef(id: .e2eMaster, title: "Шифропанк", subtitle: "Отправлено зашифрованное E2E сообщение", icon: "🔒", rarity: "Эпическая"),
        AchievementDef(id: .audiophile, title: "Аудиофил", subtitle: "Подключен бесконечный плейлист профиля", icon: "🎧", rarity: "Редкая"),
        AchievementDef(id: .streak7d, title: "Огненная серия", subtitle: "7 дней непрерывного общения", icon: "🔥", rarity: "Редкая"),
        AchievementDef(id: .streak30d, title: "Пламенный титан", subtitle: "30 дней непрерывного общения", icon: "🟠", rarity: "Легендарная"),
        AchievementDef(id: .metaCleaner, title: "Чистильщик", subtitle: "Отправлен файл с удалением EXIF/PDF-меты", icon: "🧹", rarity: "Обычная"),
        AchievementDef(id: .gamer, title: "Ретро-геймер", subtitle: "Набрано 500+ очков в 2048, Змейке или Сапёре", icon: "🎮", rarity: "Редкая"),
        AchievementDef(id: .liquidGlass, title: "Жидкое стекло", subtitle: "Активирован пресет Liquid Glass iOS 27", icon: "🧊", rarity: "Обычная"),
        AchievementDef(id: .callGuard, title: "Анти-прозвон", subtitle: "Включена защита от случайных звонков", icon: "🛡️", rarity: "Обычная")
    ]

    static func evaluateAchievements(unlockedIds: Set<String>) -> (unlocked: [AchievementDef], locked: [AchievementDef], tier: String) {
        var unlocked: [AchievementDef] = []
        var locked: [AchievementDef] = []
        for a in allAchievements {
            if unlockedIds.contains(a.id.rawValue) {
                unlocked.append(a)
            } else {
                locked.append(a)
            }
        }
        let count = unlocked.count
        let tier: String
        switch count {
        case 0...2: tier = "Новичок 🥉"
        case 3...6: tier = "Энтузиаст 🥈"
        case 7...10: tier = "Ветеран 🥇"
        default: tier = "Легенда MediaTok 💎"
        }
        return (unlocked, locked, tier)
    }

    // MARK: - 17. Watermark Formatter

    static func formatWatermarkText(recipient: String, date: Date = Date(), appTag: String = "MediaTok") -> String {
        let cleanRecipient = recipient
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayRecip = cleanRecipient.isEmpty ? "Личное" : cleanRecipient
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let dateStr = String(format: "%02d.%02d.%04d", comps.day ?? 1, comps.month ?? 1, comps.year ?? 2026)
        return "Для @\(displayRecip) · \(dateStr) · \(appTag)"
    }

    // MARK: - 18. Bottom Bar Presets

    enum BottomTabPreset: String, CaseIterable {
        case standard = "standard"
        case minimal = "minimal"
        case mediaHub = "media_hub"
        case fullPower = "full_power"

        var title: String {
            switch self {
            case .standard: return "Стандарт Telegram"
            case .minimal: return "Минимал (Чаты + Настройки)"
            case .mediaHub: return "Медиа-хаб (Чаты + TikTok + Настройки)"
            case .fullPower: return "Максимум (Все вкладки)"
            }
        }

        var hiddenTabs: [String] {
            switch self {
            case .standard: return []
            case .minimal: return ["calls", "contacts"]
            case .mediaHub: return ["calls", "contacts"]
            case .fullPower: return []
            }
        }

        var isWide: Bool {
            switch self {
            case .standard, .minimal: return false
            case .mediaHub, .fullPower: return true
            }
        }
    }

    // MARK: - 19. Neon Minesweeper Core Engine

    struct MinesweeperCell: Equatable {
        var isMine: Bool
        var isRevealed: Bool
        var isFlagged: Bool
        var adjacentMines: Int
    }

    struct MinesweeperGame: Equatable {
        let rows: Int = 8
        let cols: Int = 8
        let totalMines: Int = 10
        var grid: [MinesweeperCell]
        var isGameOver: Bool
        var isWon: Bool
        var hasStarted: Bool

        init() {
            self.grid = Array(repeating: MinesweeperCell(isMine: false, isRevealed: false, isFlagged: false, adjacentMines: 0), count: 64)
            self.isGameOver = false
            self.isWon = false
            self.hasStarted = false
        }

        mutating func reveal(at index: Int) {
            guard index >= 0 && index < 64, !isGameOver, !grid[index].isFlagged, !grid[index].isRevealed else { return }
            if !hasStarted {
                hasStarted = true
                var candidates = Array(0..<64).filter { $0 != index }
                var seed = (UInt64(index + 37) &* 6364136223846793005) &+ 1
                for i in stride(from: candidates.count - 1, through: 1, by: -1) {
                    seed = seed &* 6364136223846793005 &+ 1
                    let j = Int(seed % UInt64(i + 1))
                    candidates.swapAt(i, j)
                }
                for i in 0..<totalMines {
                    grid[candidates[i]].isMine = true
                }
                for r in 0..<8 {
                    for c in 0..<8 {
                        let idx = r * 8 + c
                        if grid[idx].isMine { continue }
                        var count = 0
                        for dr in -1...1 {
                            for dc in -1...1 {
                                if dr == 0 && dc == 0 { continue }
                                let nr = r + dr
                                let nc = c + dc
                                if nr >= 0 && nr < 8 && nc >= 0 && nc < 8 {
                                    if grid[nr * 8 + nc].isMine { count += 1 }
                                }
                            }
                        }
                        grid[idx].adjacentMines = count
                    }
                }
            }

            if grid[index].isMine {
                grid[index].isRevealed = true
                isGameOver = true
                isWon = false
                for i in 0..<64 {
                    if grid[i].isMine { grid[i].isRevealed = true }
                }
                return
            }

            var queue = [index]
            grid[index].isRevealed = true
            while !queue.isEmpty {
                let curr = queue.removeFirst()
                let r = curr / 8
                let c = curr % 8
                if grid[curr].adjacentMines == 0 {
                    for dr in -1...1 {
                        for dc in -1...1 {
                            let nr = r + dr
                            let nc = c + dc
                            if nr >= 0 && nr < 8 && nc >= 0 && nc < 8 {
                                let nIdx = nr * 8 + nc
                                if !grid[nIdx].isRevealed && !grid[nIdx].isFlagged && !grid[nIdx].isMine {
                                    grid[nIdx].isRevealed = true
                                    if grid[nIdx].adjacentMines == 0 {
                                        queue.append(nIdx)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            let unrevealedSafe = grid.enumerated().filter { !$0.element.isMine && !$0.element.isRevealed }.count
            if unrevealedSafe == 0 {
                isWon = true
                isGameOver = true
            }
        }

        mutating func toggleFlag(at index: Int) {
            guard index >= 0 && index < 64, !isGameOver, !grid[index].isRevealed else { return }
            grid[index].isFlagged.toggle()
        }
    }

    // MARK: - 20. Anti-Phishing & Homograph Detector (#45)

    struct PhishingVerdict: Equatable {
        let isSuspicious: Bool
        let reason: String?
    }

    static func inspectUrlForPhishing(_ rawUrl: String) -> PhishingVerdict {
        var s = rawUrl.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemeIdx = s.range(of: "://") {
            s = String(s[schemeIdx.upperBound...])
        }
        if let slashIdx = s.firstIndex(of: "/") {
            s = String(s[..<slashIdx])
        }
        if let colonIdx = s.firstIndex(of: ":") {
            s = String(s[..<colonIdx])
        }
        if let qIdx = s.firstIndex(of: "?") {
            s = String(s[..<qIdx])
        }
        let host = s
        guard !host.isEmpty else {
            return PhishingVerdict(isSuspicious: false, reason: nil)
        }

        var hasLatin = false
        var hasCyrillic = false
        for ch in host {
            if ("a"..."z").contains(ch) {
                hasLatin = true
            } else if ("а"..."я").contains(ch) || ch == "ё" {
                hasCyrillic = true
            }
        }
        if hasLatin && hasCyrillic {
            return PhishingVerdict(isSuspicious: true, reason: "Обнаружена подмена букв (Cyrillic/Latin homograph) в домене \(host)")
        }

        let suspiciousTlds = [".xyz", ".top", ".tk", ".ml", ".ga", ".cf", ".gq", ".buzz", ".fit", ".rest", ".cam", ".click"]
        for tld in suspiciousTlds {
            if host.hasSuffix(tld) {
                return PhishingVerdict(isSuspicious: true, reason: "Подозрительная доменная зона \(tld)")
            }
        }

        let telegramSpoofs = ["te1egram", "telegraam", "te1egr", "t-me.", "tele-gram"]
        for sp in telegramSpoofs {
            if host.contains(sp) {
                return PhishingVerdict(isSuspicious: true, reason: "Подозрение на поддельный домен Telegram")
            }
        }

        return PhishingVerdict(isSuspicious: false, reason: nil)
    }

    // MARK: - 21. QR Code Command Parser (#65)

    static func parseQrCommand(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(".qr ") else { return nil }
        let content = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : String(content.prefix(500))
    }

    // MARK: - 22. Channel Ad-Blocker Filter (#188)

    static func isChannelAdPost(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("erid:") || lower.contains("erid=") || lower.contains("erid ") {
            return true
        }
        if lower.contains("#реклама") || lower.contains("#ad ") || lower.contains("#промо") || lower.contains("#promo") {
            return true
        }
        if lower.contains("реклама.") && (lower.contains("ооо ") || lower.contains("инн ") || lower.contains("токена")) {
            return true
        }
        return false
    }

    // MARK: - 23. Voice Speed Presets (#3)

    static let expandedVoiceSpeeds: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0]

    // MARK: - 24. Wheel of Fortune Parser (#170)

    static func parseWheelCommand(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(".wheel ") else { return nil }
        let body = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = body.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.count >= 2 ? parts : nil
    }

    // MARK: - 25. 1-on-1 Private Poll Parser (#176)

    struct PollPayload: Equatable {
        let question: String
        let options: [String]
    }

    static func parsePollCommand(_ raw: String) -> PollPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(".poll ") else { return nil }
        let body = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = body.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard parts.count >= 3 else { return nil }
        return PollPayload(question: parts[0], options: Array(parts.dropFirst()))
    }

    // MARK: - 26. Split Bill Parser (#177)

    struct SplitBillPayload: Equatable {
        let total: Double
        let peopleCount: Int
        let perPerson: Double
    }

    static func parseSplitBillCommand(_ raw: String) -> SplitBillPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(".split ") else { return nil }
        let body = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = body.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count == 2,
              let total = Double(tokens[0]),
              let count = Int(tokens[1]),
              total > 0, count > 0 else {
            return nil
        }
        let per = (total / Double(count) * 100.0).rounded() / 100.0
        return SplitBillPayload(total: total, peopleCount: count, perPerson: per)
    }

    // MARK: - 27. Time Capsule Parser (#166)

    struct TimeCapsulePayload: Equatable {
        let unlockDateStr: String
        let message: String
    }

    static func parseTimeCapsuleCommand(_ raw: String) -> TimeCapsulePayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(".capsule ") else { return nil }
        let body = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let spaceIdx = body.firstIndex(of: " ") else { return nil }
        let dateStr = String(body[..<spaceIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        let msg = String(body[body.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dateStr.isEmpty, !msg.isEmpty else { return nil }
        return TimeCapsulePayload(unlockDateStr: dateStr, message: msg)
    }

    // MARK: - 28. Mood Bubble Parser (#31)

    struct MoodPayload: Equatable {
        let emoji: String
        let text: String
    }

    static func parseMoodCommand(_ raw: String) -> MoodPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(".mood ") else { return nil }
        let body = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        if let spaceIdx = body.firstIndex(of: " ") {
            let em = String(body[..<spaceIdx])
            let tx = String(body[body.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return MoodPayload(emoji: em, text: tx)
        }
        return MoodPayload(emoji: "✨", text: body)
    }

    // MARK: - 29. Wishlist Parser (#178)

    static func parseWishCommand(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(".wish ") else { return nil }
        let body = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : String(body.prefix(200))
    }

    // MARK: - 30. Scratch Message End-to-End Wire Codec (#163)

    static let scratchWirePrefix = "🎟️MTS1:"

    static func encodeScratchWireMessage(_ payload: ScratchPayload) -> String {
        let joined = "\(payload.title)\u{001F}\(payload.secret)"
        let b64 = Data(joined.utf8).base64EncodedString()
        return "🎟️ Скретч-карта «\(payload.title)»\n🪙 Зажми сообщение → «Стереть пальцем» в MediaTok\n\(scratchWirePrefix)\(b64)"
    }

    static func decodeScratchWireMessage(_ text: String) -> ScratchPayload? {
        guard let range = text.range(of: scratchWirePrefix) else { return nil }
        let tail = String(text[range.upperBound...])
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .first
            .map { String($0) } ?? ""
        guard !tail.isEmpty,
              let data = Data(base64Encoded: tail),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parts = decoded.split(separator: "\u{001F}", maxSplits: 1, omittingEmptySubsequences: false)
        let title = parts.count > 0 ? String(parts[0]) : "Секретный билет 🎟️"
        let secret = parts.count > 1 ? String(parts[1]) : decoded
        guard !secret.isEmpty else { return nil }
        var h: UInt64 = 14695981039346656037
        for b in secret.utf8 {
            h ^= UInt64(b)
            h &*= 1099511628211
        }
        return ScratchPayload(title: String(title.prefix(40)), secret: String(secret.prefix(500)), seed: h)
    }

    // MARK: - 31. Custom Snippets / Macros Parser (#61)

    enum SnippetCommand: Equatable {
        case list
        case add(key: String, value: String)
        case remove(key: String)
        case expand(key: String)
    }

    static func parseSnippetCommand(_ raw: String) -> SnippetCommand? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == ".sn" || lower == ".sn list" || lower == ".snippets" {
            return .list
        }
        guard lower.hasPrefix(".sn ") else { return nil }
        let rest = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        let restLower = rest.lowercased()
        if restLower.hasPrefix("add ") {
            let body = String(rest.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let sp = body.firstIndex(of: " ") else { return nil }
            let key = String(body[..<sp]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let val = String(body[body.index(after: sp)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !val.isEmpty else { return nil }
            return .add(key: String(key.prefix(32)), value: String(val.prefix(2000)))
        }
        if restLower.hasPrefix("del ") {
            let key = String(rest.dropFirst(4)).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : .remove(key: String(key.prefix(32)))
        }
        let key = rest.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : .expand(key: String(key.prefix(32)))
    }

    // MARK: - 32. Wiki / Unshort / AI / Note / JSON Helpers (#64, #66, #121, #193, #198)

    static func parsePrefixPayload(_ raw: String, prefixes: [String], maxLen: Int = 500) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for p in prefixes {
            if lower.hasPrefix(p) {
                let body = String(trimmed.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return body.isEmpty ? nil : String(body.prefix(maxLen))
            }
        }
        return nil
    }

    static func prettyPrintJsonIfValid(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return str
    }

    // MARK: - 33. MediaTok Cloud Backup (.mtbak for Telegram Saved Messages)

    struct MediaTokBackupPayload: Codable, Equatable {
        let version: Int
        let createdAt: Int64
        let bools: [String: Bool]
        let strings: [String: String]
        let stringArrays: [String: [String]]
        let snippets: [String: String]
        let notes: [String: String]
    }

    static func encodeBackupPayload(_ payload: MediaTokBackupPayload) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(payload)
    }

    static func decodeBackupPayload(_ data: Data) -> MediaTokBackupPayload? {
        guard !data.isEmpty, data.count <= 2 * 1024 * 1024 else { return nil }
        guard let decoded = try? JSONDecoder().decode(MediaTokBackupPayload.self, from: data),
              decoded.version == 1 else {
            return nil
        }
        return decoded
    }
}
