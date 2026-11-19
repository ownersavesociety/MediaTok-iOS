import Foundation
import UIKit
import TelegramCore
import AccountContext
import GGCore
import GGHooks

/// Inline `.c <expr|currency>` and `.c! <expr|currency>` calculator & live currency/crypto converter.
/// Visible to 100% of official Telegram users on any device.
/// Examples:
///   .c 2+2*10           ->  2+2*10 = 22
///   .c! sqrt(144)*5     ->  60
///   .c 100 usd          ->  100 USD = 9 850 RUB · 49 500 KZT · 4 150 UAH
///   .c 5000 rub to usd  ->  5 000 RUB = 50.76 USD
///   .c 10 ton в руб     ->  10 TON = 5 420 RUB
enum GGMediaTokCalculator {
    private static let lock = NSLock()
    // Rates are expressed as "how many USD is 1 unit of currency" (e.g. USD=1, RUB≈0.0102, BTC≈90000)
    private static var usdPerUnit: [String: Double] = GGMediaTokCalculator.fallbackRates
    private static var lastFetchAt: TimeInterval = 0.0
    private static var isFetching = false

    private static let fallbackRates: [String: Double] = [
        "USD": 1.0, "EUR": 1.08, "GBP": 1.27, "RUB": 1.0 / 98.0, "KZT": 1.0 / 495.0,
        "UAH": 1.0 / 41.5, "BYN": 1.0 / 3.28, "TRY": 1.0 / 34.5, "CNY": 1.0 / 7.25,
        "JPY": 1.0 / 154.0, "AED": 1.0 / 3.6725, "UZS": 1.0 / 12800.0, "PLN": 1.0 / 4.05,
        "USDT": 1.0, "BTC": 92000.0, "ETH": 3100.0, "TON": 5.4, "SOL": 210.0, "NOT": 0.0075
    ]

    private static let currencyAliases: [String: String] = [
        "usd": "USD", "$": "USD", "долл": "USD", "доллар": "USD", "долларов": "USD", "бакс": "USD", "баксов": "USD",
        "eur": "EUR", "€": "EUR", "евро": "EUR",
        "rub": "RUB", "₽": "RUB", "руб": "RUB", "рублей": "RUB", "рубля": "RUB", "р": "RUB",
        "kzt": "KZT", "₸": "KZT", "тг": "KZT", "тенге": "KZT",
        "uah": "UAH", "₴": "UAH", "грн": "UAH", "гривен": "UAH",
        "byn": "BYN", "бел": "BYN",
        "gbp": "GBP", "£": "GBP", "фунт": "GBP", "фунтов": "GBP",
        "try": "TRY", "₺": "TRY", "лир": "TRY", "лира": "TRY",
        "cny": "CNY", "¥": "CNY", "юань": "CNY", "юаней": "CNY",
        "jpy": "JPY", "иен": "JPY", "йен": "JPY",
        "aed": "AED", "дирхам": "AED",
        "uzs": "UZS", "сум": "UZS",
        "pln": "PLN", "злот": "PLN",
        "usdt": "USDT", "btc": "BTC", "биток": "BTC", "биткоин": "BTC",
        "eth": "ETH", "эфир": "ETH",
        "ton": "TON", "тон": "TON",
        "sol": "SOL", "солана": "SOL",
        "not": "NOT"
    ]

    static func register() {
        GGChatScreenHooks.willSendText.register({ request, proceed in
            return GGMediaTokCalculator.intercept(request, proceed: proceed)
        }, order: 30)
    }

    private static func intercept(_ request: GGComposedTextRequest, proceed: @escaping () -> Void) -> Bool {
        let raw = request.state.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let resultOnly: Bool
        let expr: String
        if lower.hasPrefix(".c! ") {
            resultOnly = true
            expr = String(raw.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix(".c ") {
            resultOnly = false
            expr = String(raw.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return false
        }
        guard !expr.isEmpty else {
            return false
        }

        // Check unit conversion (km/mi, kg/lb, cm/in, C/F)
        if let unitOut = GGMediaTokCalculator.tryConvertUnits(expr, resultOnly: resultOnly) {
            request.replace(ChatTextInputState(inputText: NSAttributedString(string: unitOut)))
            proceed()
            return true
        }

        // Check currency conversion first
        if let conv = GGMediaTokCalculator.parseCurrencyQuery(expr) {
            GGMediaTokCalculator.ensureFreshRates {
                let output = GGMediaTokCalculator.formatCurrencyConversion(conv, resultOnly: resultOnly)
                request.replace(ChatTextInputState(inputText: NSAttributedString(string: output)))
                proceed()
            }
            return true
        }

        // Otherwise evaluate math synchronously
        if let value = GGMediaTokCalculator.evaluateMath(expr) {
            let formatted = GGMediaTokCalculator.formatNumber(value)
            let output = resultOnly ? formatted : "\(expr) = \(formatted)"
            request.replace(ChatTextInputState(inputText: NSAttributedString(string: output)))
            proceed()
            return true
        }
        return false
    }

    // MARK: - Currency Conversion

    private struct CurrencyQuery {
        let amount: Double
        let fromCode: String
        let toCode: String?
    }

    private static func parseCurrencyQuery(_ raw: String) -> CurrencyQuery? {
        var cleaned = raw.replacingOccurrences(of: ",", with: ".")
        // Separate leading/trailing currency symbols like "$100" or "500₽"
        for sym in ["$", "€", "₽", "₸", "₴", "£", "₺", "¥"] {
            cleaned = cleaned.replacingOccurrences(of: sym, with: " \(sym) ")
        }
        let tokens = cleaned.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        guard tokens.count >= 2 && tokens.count <= 5 else {
            return nil
        }

        func resolveCode(_ s: String) -> String? {
            return GGMediaTokCalculator.currencyAliases[s.lowercased()]
        }
        func parseAmt(_ s: String) -> Double? {
            var t = s.lowercased()
            var mult = 1.0
            if t.hasSuffix("kk") || t.hasSuffix("кк") || t.hasSuffix("m") || t.hasSuffix("м") {
                mult = 1_000_000.0
                t = String(t.dropLast(t.hasSuffix("kk") || t.hasSuffix("кк") ? 2 : 1))
            } else if t.hasSuffix("k") || t.hasSuffix("к") {
                mult = 1_000.0
                t = String(t.dropLast())
            }
            if let v = Double(t) { return v * mult }
            if let v = GGMediaTokCalculator.evaluateMath(t) { return v * mult }
            return nil
        }

        var amount: Double?
        var fromCode: String?
        var toCode: String?

        // Support "$ 100" or "100 $" or "100 usd to rub" or "100 usd rub"
        for tok in tokens {
            let low = tok.lowercased()
            if low == "to" || low == "in" || low == "в" || low == "->" || low == "=>" || low == "=" {
                continue
            }
            if let code = resolveCode(tok) {
                if fromCode == nil {
                    fromCode = code
                } else if toCode == nil {
                    toCode = code
                }
            } else if amount == nil, let num = parseAmt(tok) {
                amount = num
            } else {
                return nil
            }
        }
        guard let a = amount, let from = fromCode else {
            return nil
        }
        return CurrencyQuery(amount: a, fromCode: from, toCode: toCode)
    }

    private static func ensureFreshRates(completion: @escaping () -> Void) {
        let now = Date().timeIntervalSince1970
        GGMediaTokCalculator.lock.lock()
        let fresh = (now - GGMediaTokCalculator.lastFetchAt) < 1800.0 && GGMediaTokCalculator.lastFetchAt > 0.0
        let busy = GGMediaTokCalculator.isFetching
        if !fresh && !busy {
            GGMediaTokCalculator.isFetching = true
        }
        GGMediaTokCalculator.lock.unlock()

        if fresh || busy {
            completion()
            return
        }

        let group = DispatchGroup()
        var fetchedFiat: [String: Double] = [:]
        var fetchedCrypto: [String: Double] = [:]

        if let url = URL(string: "https://open.er-api.com/v6/latest/USD") {
            group.enter()
            var req = URLRequest(url: url, timeoutInterval: 4.5)
            req.setValue("MediaTok/Calc", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                if let data,
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   let rates = json["rates"] as? [String: Double] {
                    for (code, perUsd) in rates where perUsd > 0 {
                        fetchedFiat[code.uppercased()] = 1.0 / perUsd
                    }
                }
                group.leave()
            }.resume()
        }

        if let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,the-open-network,tether,solana,notcoin&vs_currencies=usd") {
            group.enter()
            var req = URLRequest(url: url, timeoutInterval: 4.5)
            req.setValue("MediaTok/Calc", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                if let data,
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Double]] {
                    let map: [(String, String)] = [
                        ("bitcoin", "BTC"), ("ethereum", "ETH"), ("the-open-network", "TON"),
                        ("tether", "USDT"), ("solana", "SOL"), ("notcoin", "NOT")
                    ]
                    for (cgId, code) in map {
                        if let usd = json[cgId]?["usd"], usd > 0 {
                            fetchedCrypto[code] = usd
                        }
                    }
                }
                group.leave()
            }.resume()
        }

        group.notify(queue: .main) {
            GGMediaTokCalculator.lock.lock()
            for (k, v) in fetchedFiat { GGMediaTokCalculator.usdPerUnit[k] = v }
            for (k, v) in fetchedCrypto { GGMediaTokCalculator.usdPerUnit[k] = v }
            if !fetchedFiat.isEmpty || !fetchedCrypto.isEmpty {
                GGMediaTokCalculator.lastFetchAt = Date().timeIntervalSince1970
            }
            GGMediaTokCalculator.isFetching = false
            GGMediaTokCalculator.lock.unlock()
            completion()
        }
    }

    private static func formatCurrencyConversion(_ q: CurrencyQuery, resultOnly: Bool) -> String {
        GGMediaTokCalculator.lock.lock()
        let rates = GGMediaTokCalculator.usdPerUnit
        GGMediaTokCalculator.lock.unlock()

        guard let fromUsd = rates[q.fromCode] else {
            return "\(GGMediaTokCalculator.formatNumber(q.amount)) \(q.fromCode)"
        }
        let usdAmount = q.amount * fromUsd

        if let target = q.toCode, let toUsd = rates[target], toUsd > 0 {
            let converted = usdAmount / toUsd
            let right = "\(GGMediaTokCalculator.formatCurrencyNum(converted)) \(target)"
            if resultOnly { return right }
            return "\(GGMediaTokCalculator.formatCurrencyNum(q.amount)) \(q.fromCode) = \(right)"
        }

        // Default multi-target summary
        let defaults: [String]
        if q.fromCode == "RUB" {
            defaults = ["USD", "EUR", "KZT", "UAH"]
        } else if q.fromCode == "KZT" {
            defaults = ["RUB", "USD", "EUR"]
        } else if q.fromCode == "USD" || q.fromCode == "USDT" {
            defaults = ["RUB", "KZT", "UAH", "EUR"]
        } else {
            defaults = ["USD", "RUB", "KZT"]
        }
        let parts = defaults.compactMap { code -> String? in
            guard code != q.fromCode, let r = rates[code], r > 0 else { return nil }
            return "\(GGMediaTokCalculator.formatCurrencyNum(usdAmount / r)) \(code)"
        }
        let summary = parts.joined(separator: " · ")
        if resultOnly { return summary }
        return "\(GGMediaTokCalculator.formatCurrencyNum(q.amount)) \(q.fromCode) = \(summary)"
    }

    private static func formatCurrencyNum(_ v: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.groupingSeparator = " "
        nf.decimalSeparator = "."
        if abs(v) >= 100.0 {
            nf.maximumFractionDigits = 2
        } else if abs(v) >= 1.0 {
            nf.maximumFractionDigits = 2
        } else {
            nf.maximumFractionDigits = 6
        }
        return nf.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    private static func formatNumber(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "Ошибка" }
        if abs(v - v.rounded()) < 1e-9 && abs(v) < 1e15 {
            let nf = NumberFormatter()
            nf.numberStyle = .decimal
            nf.groupingSeparator = " "
            nf.maximumFractionDigits = 0
            return nf.string(from: NSNumber(value: Int64(v.rounded()))) ?? "\(Int64(v.rounded()))"
        }
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.groupingSeparator = " "
        nf.decimalSeparator = "."
        nf.maximumFractionDigits = 6
        return nf.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // MARK: - Safe Recursive-Descent Math Evaluator

    private final class MathParser {
        private let chars: [Character]
        private var pos = 0

        init(_ input: String) {
            let normalized = input
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: " ", with: "")
            self.chars = Array(normalized)
        }

        func parse() -> Double? {
            guard !self.chars.isEmpty else { return nil }
            guard let v = self.parseAddSub(), self.pos == self.chars.count, v.isFinite else {
                return nil
            }
            return v
        }

        private func peek() -> Character? {
            return self.pos < self.chars.count ? self.chars[self.pos] : nil
        }

        private func parseAddSub() -> Double? {
            guard var left = self.parseMulDiv() else { return nil }
            while let ch = self.peek(), ch == "+" || ch == "-" {
                self.pos += 1
                guard let right = self.parseMulDiv() else { return nil }
                left = (ch == "+") ? (left + right) : (left - right)
            }
            return left
        }

        private func parseMulDiv() -> Double? {
            guard var left = self.parsePower() else { return nil }
            while let ch = self.peek(), ch == "*" || ch == "/" || ch == "%" {
                self.pos += 1
                guard let right = self.parsePower() else { return nil }
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

        private func parsePower() -> Double? {
            guard let base = self.parseUnary() else { return nil }
            if self.peek() == "^" {
                self.pos += 1
                guard let exp = self.parsePower() else { return nil }
                return pow(base, exp)
            }
            return base
        }

        private func parseUnary() -> Double? {
            if self.peek() == "+" {
                self.pos += 1
                return self.parseUnary()
            }
            if self.peek() == "-" {
                self.pos += 1
                guard let v = self.parseUnary() else { return nil }
                return -v
            }
            return self.parsePrimary()
        }

        private func parsePrimary() -> Double? {
            if self.peek() == "(" {
                self.pos += 1
                guard let v = self.parseAddSub(), self.peek() == ")" else { return nil }
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
                guard let arg = self.parseAddSub(), self.peek() == ")" else { return nil }
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
        return MathParser(expr).parse()
    }

    private static func tryConvertUnits(_ raw: String, resultOnly: Bool) -> String? {
        let tokens = raw.replacingOccurrences(of: ",", with: ".").split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        guard tokens.count >= 2, let val = Double(tokens[0]) else { return nil }
        let unit = tokens[1].lowercased()
        let out: (String, String)?
        switch unit {
        case "km", "км":
            out = ("\(GGMediaTokCalculator.formatCurrencyNum(val)) км", "\(GGMediaTokCalculator.formatCurrencyNum(val * 0.621371)) миль")
        case "mi", "миль", "мили":
            out = ("\(GGMediaTokCalculator.formatCurrencyNum(val)) миль", "\(GGMediaTokCalculator.formatCurrencyNum(val * 1.60934)) км")
        case "kg", "кг":
            out = ("\(GGMediaTokCalculator.formatCurrencyNum(val)) кг", "\(GGMediaTokCalculator.formatCurrencyNum(val * 2.20462)) фунтов (lb)")
        case "lb", "lbs", "фунт", "фунтов":
            out = ("\(GGMediaTokCalculator.formatCurrencyNum(val)) lb", "\(GGMediaTokCalculator.formatCurrencyNum(val * 0.453592)) кг")
        case "cm", "см":
            out = ("\(GGMediaTokCalculator.formatCurrencyNum(val)) см", "\(GGMediaTokCalculator.formatCurrencyNum(val / 2.54)) дюймов (in)")
        case "in", "inch", "дюйм", "дюймов":
            out = ("\(GGMediaTokCalculator.formatCurrencyNum(val)) in", "\(GGMediaTokCalculator.formatCurrencyNum(val * 2.54)) см")
        case "c", "°c", "цельсия":
            out = ("\(GGMediaTokCalculator.formatCurrencyNum(val)) °C", "\(GGMediaTokCalculator.formatCurrencyNum(val * 9.0 / 5.0 + 32.0)) °F")
        case "f", "°f", "фаренгейта":
            out = ("\(GGMediaTokCalculator.formatCurrencyNum(val)) °F", "\(GGMediaTokCalculator.formatCurrencyNum((val - 32.0) * 5.0 / 9.0)) °C")
        default:
            out = nil
        }
        guard let (left, right) = out else { return nil }
        return resultOnly ? right : "\(left) = \(right)"
    }
}
