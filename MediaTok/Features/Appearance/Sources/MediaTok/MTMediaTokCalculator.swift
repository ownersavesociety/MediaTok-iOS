import Foundation
import UIKit
import TelegramCore
import AccountContext
import MTCore
import MTHooks

/// Inline `.c <expr|currency>` and `.c! <expr|currency>` calculator & live currency/crypto converter.
/// Visible to 100% of official Telegram users on any device.
/// Examples:
///   .c 2+2*10           ->  2+2*10 = 22
///   .c! sqrt(144)*5     ->  60
///   .c 100 usd          ->  100 USD = 9 850 RUB · 49 500 KZT · 4 150 UAH
///   .c 5000 rub to usd  ->  5 000 RUB = 50.76 USD
///   .c 10 ton в руб     ->  10 TON = 5 420 RUB
enum MTMediaTokCalculator {
    private static let lock = NSLock()
    // Rates are expressed as "how many USD is 1 unit of currency" (e.g. USD=1, RUB≈0.0108, BTC≈64000)
    private static var usdPerUnit: [String: Double] = MTMediaTokCalculator.fallbackRates
    private static var lastFetchAt: TimeInterval = 0.0
    private static var isFetching = false
    private static var pendingCompletions: [() -> Void] = []

    private static let fallbackRates: [String: Double] = [
        "USD": 1.0, "EUR": 1.08, "GBP": 1.27, "RUB": 1.0 / 92.0, "KZT": 1.0 / 510.0,
        "UAH": 1.0 / 41.5, "BYN": 1.0 / 3.28, "TRY": 1.0 / 34.5, "CNY": 1.0 / 7.25,
        "JPY": 1.0 / 154.0, "AED": 1.0 / 3.6725, "UZS": 1.0 / 12800.0, "PLN": 1.0 / 4.05,
        "USDT": 1.0, "BTC": 64000.0, "ETH": 1810.0, "TON": 1.03, "SOL": 85.0, "NOT": 0.003
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
        MTChatScreenHooks.willSendText.register({ request, proceed in
            return MTMediaTokCalculator.intercept(request, proceed: proceed)
        }, order: 30)
    }

    private static func intercept(_ request: MTComposedTextRequest, proceed: @escaping () -> Void) -> Bool {
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
        if let unitOut = MTMediaTokCalculator.tryConvertUnits(expr, resultOnly: resultOnly) {
            request.replace(ChatTextInputState(inputText: NSAttributedString(string: unitOut)))
            proceed()
            return true
        }

        // Check currency conversion first
        if let conv = MTMediaTokCalculator.parseCurrencyQuery(expr) {
            MTMediaTokCalculator.ensureFreshRates {
                let output = MTMediaTokCalculator.formatCurrencyConversion(conv, resultOnly: resultOnly)
                request.replace(ChatTextInputState(inputText: NSAttributedString(string: output)))
                proceed()
            }
            return true
        }

        // Otherwise evaluate math synchronously
        if let value = MTMediaTokCalculator.evaluateMath(expr) {
            let formatted = MTMediaTokCalculator.formatNumber(value)
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
            return MTMediaTokCalculator.currencyAliases[s.lowercased()]
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
            if let v = MTMediaTokCalculator.evaluateMath(t) { return v * mult }
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
        MTMediaTokCalculator.lock.lock()
        let fresh = (now - MTMediaTokCalculator.lastFetchAt) < 1800.0 && MTMediaTokCalculator.lastFetchAt > 0.0
        if fresh {
            MTMediaTokCalculator.lock.unlock()
            completion()
            return
        }
        MTMediaTokCalculator.pendingCompletions.append(completion)
        if MTMediaTokCalculator.isFetching {
            MTMediaTokCalculator.lock.unlock()
            return
        }
        MTMediaTokCalculator.isFetching = true
        MTMediaTokCalculator.lock.unlock()

        let group = DispatchGroup()
        let fetchLock = NSLock()
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
                    fetchLock.lock()
                    for (code, perUsd) in rates where perUsd > 0 {
                        fetchedFiat[code.uppercased()] = 1.0 / perUsd
                    }
                    fetchLock.unlock()
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
                    fetchLock.lock()
                    for (cgId, code) in map {
                        if let usd = json[cgId]?["usd"], usd > 0 {
                            fetchedCrypto[code] = usd
                        }
                    }
                    fetchLock.unlock()
                }
                group.leave()
            }.resume()
        }

        group.notify(queue: .main) {
            fetchLock.lock()
            let fiatCopy = fetchedFiat
            let cryptoCopy = fetchedCrypto
            fetchLock.unlock()

            MTMediaTokCalculator.lock.lock()
            for (k, v) in fiatCopy { MTMediaTokCalculator.usdPerUnit[k] = v }
            for (k, v) in cryptoCopy { MTMediaTokCalculator.usdPerUnit[k] = v }
            if !fiatCopy.isEmpty || !cryptoCopy.isEmpty {
                MTMediaTokCalculator.lastFetchAt = Date().timeIntervalSince1970
            }
            MTMediaTokCalculator.isFetching = false
            let callbacks = MTMediaTokCalculator.pendingCompletions
            MTMediaTokCalculator.pendingCompletions.removeAll()
            MTMediaTokCalculator.lock.unlock()

            for cb in callbacks {
                cb()
            }
        }
    }

    private static func formatCurrencyConversion(_ q: CurrencyQuery, resultOnly: Bool) -> String {
        MTMediaTokCalculator.lock.lock()
        let rates = MTMediaTokCalculator.usdPerUnit
        let isOffline = (MTMediaTokCalculator.lastFetchAt == 0.0)
        MTMediaTokCalculator.lock.unlock()
        let offlineTag = isOffline ? " (офлайн)" : ""

        guard let fromUsd = rates[q.fromCode] else {
            return "\(MTMediaTokCalculator.formatNumber(q.amount)) \(q.fromCode)\(offlineTag)"
        }
        let usdAmount = q.amount * fromUsd

        if let target = q.toCode, let toUsd = rates[target], toUsd > 0 {
            let converted = usdAmount / toUsd
            let right = "\(MTMediaTokCalculator.formatCurrencyNum(converted)) \(target)\(offlineTag)"
            if resultOnly { return right }
            return "\(MTMediaTokCalculator.formatCurrencyNum(q.amount)) \(q.fromCode) = \(right)"
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
            return "\(MTMediaTokCalculator.formatCurrencyNum(usdAmount / r)) \(code)"
        }
        let summary = parts.joined(separator: " · ") + offlineTag
        if resultOnly { return summary }
        return "\(MTMediaTokCalculator.formatCurrencyNum(q.amount)) \(q.fromCode) = \(summary)"
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

    // MARK: - Depth-Bounded Math Evaluator (delegated to MTMediaTokCoreLogic)

    static func evaluateMath(_ expr: String) -> Double? {
        return MTMediaTokCoreLogic.evaluateMath(expr)
    }

    private static func tryConvertUnits(_ raw: String, resultOnly: Bool) -> String? {
        let tokens = raw.replacingOccurrences(of: ",", with: ".").split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        guard tokens.count >= 2, let val = Double(tokens[0]) else { return nil }
        let unit = tokens[1].lowercased()
        let out: (String, String)?
        switch unit {
        case "km", "км":
            out = ("\(MTMediaTokCalculator.formatCurrencyNum(val)) км", "\(MTMediaTokCalculator.formatCurrencyNum(val * 0.621371)) миль")
        case "mi", "миль", "мили":
            out = ("\(MTMediaTokCalculator.formatCurrencyNum(val)) миль", "\(MTMediaTokCalculator.formatCurrencyNum(val * 1.60934)) км")
        case "kg", "кг":
            out = ("\(MTMediaTokCalculator.formatCurrencyNum(val)) кг", "\(MTMediaTokCalculator.formatCurrencyNum(val * 2.20462)) фунтов (lb)")
        case "lb", "lbs":
            out = ("\(MTMediaTokCalculator.formatCurrencyNum(val)) lb", "\(MTMediaTokCalculator.formatCurrencyNum(val * 0.453592)) кг")
        case "cm", "см":
            out = ("\(MTMediaTokCalculator.formatCurrencyNum(val)) см", "\(MTMediaTokCalculator.formatCurrencyNum(val / 2.54)) дюймов (in)")
        case "in", "inch", "дюйм", "дюймов":
            out = ("\(MTMediaTokCalculator.formatCurrencyNum(val)) in", "\(MTMediaTokCalculator.formatCurrencyNum(val * 2.54)) см")
        case "c", "°c", "цельсия":
            out = ("\(MTMediaTokCalculator.formatCurrencyNum(val)) °C", "\(MTMediaTokCalculator.formatCurrencyNum(val * 9.0 / 5.0 + 32.0)) °F")
        case "f", "°f", "фаренгейта":
            out = ("\(MTMediaTokCalculator.formatCurrencyNum(val)) °F", "\(MTMediaTokCalculator.formatCurrencyNum((val - 32.0) * 5.0 / 9.0)) °C")
        default:
            out = nil
        }
        guard let (left, right) = out else { return nil }
        return resultOnly ? right : "\(left) = \(right)"
    }
}
