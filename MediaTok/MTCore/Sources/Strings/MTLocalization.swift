import Foundation
import SwiftSignalKit

/// A language MediaTok has strings for, named in that language.
public struct MTLanguageInfo: Equatable {
    public let code: String
    public let nativeName: String
}

/// Runtime of the MediaTok strings. Code reads strings only through the generated `MTStrings`
/// accessors; this class resolves the language and looks keys up.
///
/// Language: the manual override (`core.language`, "" follows Telegram) → Telegram's language as
/// the UI layer reports it → "en". A missing key falls back to English, never to Russian.
/// Region and variant suffixes are dropped (`ru-RU`, `ru-raw` → `ru`).
public final class MTLocalization {
    public static let shared = MTLocalization(dataSource: MTGeneratedStringsDataSource())

    /// "" follows Telegram's language. App Group scope, so the extensions use it too.
    public static let languageOverride = MTSetting<String>("core.language", default: "", scope: .appGroup, flags: [.extensions])

    static let fallbackLanguage = "en"

    private let dataSource: MTStringsDataSource
    private let lock = MTUnfairLock()
    private var telegramLanguageCode: String = ""
    /// The language a custom Telegram language pack is built on (`strings.baseLanguageCode`): a pack
    /// has its own code («jdflag»), and MediaTok follows the base language then, not English.
    private var telegramBaseLanguageCode: String = ""
    private var resolvedLanguageCode: String = MTLocalization.fallbackLanguage
    private var tables: [String: [String: String]] = [:]
    private let languageCell = MTValueCell<String>(MTLocalization.fallbackLanguage)
    private var overrideDisposable: Disposable?

    init(dataSource: MTStringsDataSource) {
        self.dataSource = dataSource
        self.resolve()
        // Resolution is thread-safe, so the change is applied on the writer's thread at once.
        self.overrideDisposable = MTLocalization.languageOverride.signal.start(next: { [weak self] _ in
            self?.resolve()
        })
    }

    deinit {
        self.overrideDisposable?.dispose()
    }

    /// From the UI layer whenever Telegram's `PresentationData` changes
    /// (`presentationData.strings.primaryComponent.languageCode`).
    /// `baseCode` — `presentationData.strings.baseLanguageCode`, the base of a custom language pack.
    public func setTelegramLanguageCode(_ code: String, baseCode: String = "") {
        let normalized = MTLocalization.normalizedLanguageCode(code)
        let normalizedBase = MTLocalization.normalizedLanguageCode(baseCode)
        let changed = self.lock.withLock { () -> Bool in
            if self.telegramLanguageCode == normalized && self.telegramBaseLanguageCode == normalizedBase {
                return false
            }
            self.telegramLanguageCode = normalized
            self.telegramBaseLanguageCode = normalizedBase
            return true
        }
        if changed {
            self.resolve()
        }
    }

    /// Resolved: override ?? Telegram's ?? "en".
    public var languageCode: String {
        return self.lock.withLock {
            return self.resolvedLanguageCode
        }
    }

    /// The resolved language first, then every change.
    public var languageCodeSignal: Signal<String, NoError> {
        return self.languageCell.signal()
    }

    /// Languages with MediaTok strings, each named in itself, for the language picker.
    public var availableLanguages: [MTLanguageInfo] {
        return self.dataSource.languages.map { code in
            let name = self.table(for: code)["core.languageNativeName"] ?? code
            return MTLanguageInfo(code: code, nativeName: name)
        }
    }

    // MARK: - Lookup (used by the generated accessors)

    func string(_ key: String) -> String {
        let language = self.languageCode
        if let value = self.table(for: language)[key] {
            return value
        }
        if language != MTLocalization.fallbackLanguage, let value = self.table(for: MTLocalization.fallbackLanguage)[key] {
            return value
        }
        MTLog.debug("strings", "missing string \(key)")
        return key
    }

    func format(_ key: String, _ arguments: [(String, String)]) -> String {
        return MTLocalization.substitute(self.string(key), arguments)
    }

    func plural(_ key: String, count: Int, _ arguments: [(String, String)]) -> String {
        let language = self.languageCode
        var template = MTLocalization.pluralTemplate(self.table(for: language), key: key, category: MTPluralRules.category(for: count, language: language))
        if template == nil && language != MTLocalization.fallbackLanguage {
            let fallback = MTLocalization.fallbackLanguage
            template = MTLocalization.pluralTemplate(self.table(for: fallback), key: key, category: MTPluralRules.category(for: count, language: fallback))
        }
        var allArguments = arguments
        allArguments.append(("count", String(count)))
        guard let resolvedTemplate = template else {
            MTLog.debug("strings", "missing plural \(key)")
            return key
        }
        return MTLocalization.substitute(resolvedTemplate, allArguments)
    }

    /// One table per language, parsed once from the generated JSON chunks.
    func table(for language: String) -> [String: String] {
        if let table = self.lock.withLock({ self.tables[language] }) {
            return table
        }
        var table: [String: String] = [:]
        for chunk in self.dataSource.chunks(for: language) ?? [] {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(chunk.utf8), options: [])) as? [String: String] else {
                assertionFailure("Damaged string table of \(language)")
                continue
            }
            table.merge(object, uniquingKeysWith: { current, _ in current })
        }
        return self.lock.withLock { () -> [String: String] in
            if let existing = self.tables[language] {
                return existing
            }
            self.tables[language] = table
            return table
        }
    }

    // MARK: - Pure helpers

    static func normalizedLanguageCode(_ code: String) -> String {
        let lowercased = code.lowercased()
        if let separator = lowercased.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            return String(lowercased[lowercased.startIndex ..< separator])
        }
        return lowercased
    }

    /// Named substitution: `{name}` → value, `{{` / `}}` → literal braces. Values are inserted as
    /// is and never scanned again; nothing goes through `String(format:)`.
    static func substitute(_ template: String, _ arguments: [(String, String)]) -> String {
        if !template.contains("{") && !template.contains("}") {
            return template
        }
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            let next = template.index(after: index)
            if character == "{" {
                if next < template.endIndex && template[next] == "{" {
                    result.append("{")
                    index = template.index(after: next)
                    continue
                }
                if let close = template[next...].firstIndex(of: "}") {
                    let name = String(template[next ..< close])
                    if let argument = arguments.first(where: { $0.0 == name }) {
                        result.append(argument.1)
                        index = template.index(after: close)
                        continue
                    }
                }
            } else if character == "}" {
                if next < template.endIndex && template[next] == "}" {
                    result.append("}")
                    index = template.index(after: next)
                    continue
                }
            }
            result.append(character)
            index = next
        }
        return result
    }

    static func pluralTemplate(_ table: [String: String], key: String, category: MTPluralCategory) -> String? {
        if let value = table["\(key)#\(category.rawValue)"] {
            return value
        }
        if let value = table["\(key)#other"] {
            return value
        }
        for fallback in MTPluralCategory.allCases {
            if let value = table["\(key)#\(fallback.rawValue)"] {
                return value
            }
        }
        return nil
    }

    private func resolve() {
        let override = MTLocalization.normalizedLanguageCode(MTLocalization.languageOverride.value)
        let supported = self.dataSource.languages
        let code = self.lock.withLock { () -> String in
            let resolved: String
            if !override.isEmpty && supported.contains(override) {
                resolved = override
            } else if supported.contains(self.telegramLanguageCode) {
                resolved = self.telegramLanguageCode
            } else if supported.contains(self.telegramBaseLanguageCode) {
                resolved = self.telegramBaseLanguageCode
            } else {
                resolved = MTLocalization.fallbackLanguage
            }
            self.resolvedLanguageCode = resolved
            return resolved
        }
        self.languageCell.update(code)
    }
}

/// CLDR plural categories.
public enum MTPluralCategory: String, CaseIterable {
    case zero
    case one
    case two
    case few
    case many
    case other
}

/// CLDR cardinal rules for whole numbers in the languages MediaTok ships.
enum MTPluralRules {
    static func category(for count: Int, language: String) -> MTPluralCategory {
        let n = count.magnitude
        switch language {
        case "ru", "uk", "be":
            let mod10 = n % 10
            let mod100 = n % 100
            if mod10 == 1 && mod100 != 11 {
                return .one
            }
            if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) {
                return .few
            }
            return .many
        case "ar":
            if n == 0 {
                return .zero
            }
            if n == 1 {
                return .one
            }
            if n == 2 {
                return .two
            }
            let mod100 = n % 100
            if mod100 >= 3 && mod100 <= 10 {
                return .few
            }
            if mod100 >= 11 {
                return .many
            }
            return .other
        default:
            return n == 1 ? .one : .other
        }
    }
}

protocol MTStringsDataSource {
    var languages: [String] { get }
    func chunks(for language: String) -> [String]?
}

struct MTGeneratedStringsDataSource: MTStringsDataSource {
    var languages: [String] {
        return MTStringsData.languages
    }

    func chunks(for language: String) -> [String]? {
        return MTStringsData.chunks(for: language)
    }
}
