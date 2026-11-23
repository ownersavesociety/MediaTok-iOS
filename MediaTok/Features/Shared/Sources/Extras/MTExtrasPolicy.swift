import Foundation
import TelegramCore
import MTCore

/// What the upstream GHOST call sites of the Swiftgram-parity features ask. Every answer is
/// a read of a settings snapshot (no disk, no locks); with the setting off it is upstream's value.
public enum MTExtrasPolicy {
    // MARK: Notifications

    /// Extra «Отключить на…» intervals (seconds) for the profile's notification sheet: 4 h, 8 h, 1 day.
    /// Empty when the setting is off.
    public static var extraMuteIntervals: [Int32] {
        if !MTExtrasSettings.extraMuteDurations.value {
            return []
        }
        return [4 * 60 * 60, 8 * 60 * 60, 1 * 24 * 60 * 60]
    }

    /// The notification service never adds «→ account» to a push.
    public static var hidesRecipientAccountInNotifications: Bool {
        return MTExtrasSettings.hideAccountInNotifications.value
    }

    // MARK: Chats and input

    public static var hidesRecordingTooltip: Bool {
        return MTExtrasSettings.noRecordTooltip.value
    }

    public static var showsArchiveInChatMenu: Bool {
        return MTExtrasSettings.archiveInChatMenu.value
    }

    public static var hidesPremiumOffers: Bool {
        return MTExtrasSettings.hidePremiumOffers.value
    }


    // MARK: Links and sharing

    /// A tap on a link preview's picture opens the picture instead of the link.
    public static var linkPreviewOpensMedia: Bool {
        return MTExtrasSettings.linkPreviewOpensMedia.value
    }

    /// Profile descriptions link every URL, not only Telegram's own, without Premium.
    public static var clickableBioLinks: Bool {
        return MTExtrasSettings.bioLinks.value
    }

    /// «Safari в приложении» and the system browser in Telegram's browser settings.
    public static var allowsMoreBrowsers: Bool {
        return MTExtrasSettings.moreBrowsers.value
    }

    /// The identifier Telegram's browser settings store for «Safari в приложении». Upstream already
    /// treats an unknown value as Safari, so a stale value is harmless once the setting is off.
    public static let inAppSafariBrowserIdentifier = "inApp"
    /// The identifier for the system's default browser. Telegram finds no app for it among its
    /// «Открыть в» options and hands the link to iOS, which opens it in the default browser.
    public static let systemBrowserIdentifier = "default"

    /// The share sheet opens the iOS sheet at once. Only where the caller allows sharing outside the
    /// app (`externalShare`), so protected content never leaves through it.
    public static func opensSystemShareSheet(externalShare: Bool) -> Bool {
        return externalShare && MTExtrasSettings.systemShareSheet.value
    }

    public static var hidesRepostToStory: Bool {
        return MTExtrasSettings.hideRepostToStory.value
    }

    // MARK: Message tools

    /// «В Избранное» and «Переслать без автора» on the selection panel.
    public static var showsSelectionPanelButtons: Bool {
        return MTExtrasSettings.selectionPanelButtons.value
    }

    // MARK: Groups and channels

    public static var adminListsForAllAdmins: Bool {
        return MTExtrasSettings.adminListsForAllAdmins.value
    }

    public static var showsDiscussionWithDirectMessages: Bool {
        return MTExtrasSettings.discussionButton.value
    }

    public static var showsRecentActionsInProfile: Bool {
        return MTExtrasSettings.recentActionsShortcut.value
    }

    /// «Ограничить до…» picks a date and a time.
    public static var restrictsUntilTime: Bool {
        return MTExtrasSettings.restrictUntilTime.value
    }

    // MARK: Media

    public static var forcesYouTubePictureInPicture: Bool {
        return MTExtrasSettings.youTubePictureInPicture.value
    }

    /// The cache size limits (gigabytes, `Int32.max` = no limit) with 1 GB in front.
    public static func maximumCacheSizeValues(_ values: [Int32]) -> [Int32] {
        if !MTExtrasSettings.extraCacheOptions.value || values.contains(1) {
            return values
        }
        return [1] + values
    }

    /// The «Хранить медиа» presets (seconds, `Int32.max` = forever) with 1 hour at the end.
    public static func keepMediaPresets(_ values: [Int32]) -> [Int32] {
        let hour: Int32 = 60 * 60
        if !MTExtrasSettings.extraCacheOptions.value || values.contains(hour) {
            return values
        }
        return values + [hour]
    }

    /// The smallest cache limit Telegram's screen may store (it clamps to 5 GB upstream).
    public static var minimumCacheSizeLimit: Int32 {
        return MTExtrasSettings.extraCacheOptions.value ? 1 : 5
    }

    // MARK: Sessions and lock

    /// How often the app lock renews its «last active» mark while the app is in front. With the
    /// 5-second auto-lock the upstream 5 s step would lock on a quick return. Only when that option
    /// is the chosen one: the switch is on by default, and every other timeout keeps
    /// upstream's 5 s step (each step writes the lock state file).
    public static func appLockActivityRenewInterval(autolockTimeout: Int32?) -> Double {
        if MTExtrasSettings.autolockFiveSeconds.value, let autolockTimeout, autolockTimeout > 0, autolockTimeout <= 5 {
            return 2.5
        }
        return 5.0
    }

    public static var showsSessionDetails: Bool {
        return MTExtrasSettings.sessionDetails.value
    }

    private static let publicIpLock = NSLock()
    private static var cachedPublicIp: String?
    private static var cachedPublicIpTimestamp: TimeInterval = 0
    private static var isFetchingPublicIp = false

    /// «Приложение» of a session, with its api_id when the details are on.
    public static func sessionApplicationString(_ base: String, apiId: Int32, isCurrent: Bool) -> String {
        let _ = isCurrent
        if !MTExtrasSettings.sessionDetails.value {
            return base
        }
        return base + " · api_id " + String(apiId)
    }

    /// Resolves the display string for `IP-адрес` in session details so it is never blank:
    /// - if the server provided `session.ip`, returns it;
    /// - if `isCurrent` and server returned empty `ip`, resolves the device's live exit IP asynchronously;
    /// - if another session and server redacted `ip` (e.g. fresh <24h login), shows a clear explanation.
    public static func displaySessionIP(sessionIp: String, isCurrent: Bool, onResolved: @escaping () -> Void) -> String? {
        guard MTExtrasSettings.sessionDetails.value else {
            return nil
        }
        let trimmed = sessionIp.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if !isCurrent {
            let lang = MTLocalization.shared.languageCode
            return (lang == "ru" || lang == "uk") ? "Скрыт Telegram (новый сеанс < 24ч)" : "Hidden by Telegram (< 24h session)"
        }
        let now = Date().timeIntervalSince1970
        var existing: String?
        var shouldFetch = false
        MTExtrasPolicy.publicIpLock.lock()
        if let ip = MTExtrasPolicy.cachedPublicIp, now - MTExtrasPolicy.cachedPublicIpTimestamp < 120.0 {
            existing = ip
        } else if !MTExtrasPolicy.isFetchingPublicIp {
            MTExtrasPolicy.isFetchingPublicIp = true
            shouldFetch = true
            existing = MTExtrasPolicy.cachedPublicIp
        } else {
            existing = MTExtrasPolicy.cachedPublicIp
        }
        MTExtrasPolicy.publicIpLock.unlock()

        if shouldFetch {
            MTExtrasPolicy.fetchPublicExitIP(onResolved: onResolved)
        }
        if let existing, !existing.isEmpty {
            return existing
        }
        let lang = MTLocalization.shared.languageCode
        return (lang == "ru" || lang == "uk") ? "Определение…" : "Resolving…"
    }

    private static func fetchPublicExitIP(onResolved: @escaping () -> Void) {
        let endpoints = [
            "https://api.ipify.org",
            "https://checkip.amazonaws.com"
        ]
        func tryIndex(_ idx: Int) {
            guard idx < endpoints.count, let url = URL(string: endpoints[idx]) else {
                MTExtrasPolicy.publicIpLock.lock()
                MTExtrasPolicy.isFetchingPublicIp = false
                MTExtrasPolicy.publicIpLock.unlock()
                return
            }
            var req = URLRequest(url: url, timeoutInterval: 6.0)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: req) { data, response, _ in
                if let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                   let data, let text = String(data: data, encoding: .utf8) {
                    let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if candidate.count >= 7, candidate.count <= 45,
                       candidate.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == ":" }) {
                        MTExtrasPolicy.publicIpLock.lock()
                        MTExtrasPolicy.cachedPublicIp = candidate
                        MTExtrasPolicy.cachedPublicIpTimestamp = Date().timeIntervalSince1970
                        MTExtrasPolicy.isFetchingPublicIp = false
                        MTExtrasPolicy.publicIpLock.unlock()
                        DispatchQueue.main.async {
                            onResolved()
                        }
                        return
                    }
                }
                tryIndex(idx + 1)
            }.resume()
        }
        tryIndex(0)
    }

    public static var alwaysShowsAddAccount: Bool {
        return MTExtrasSettings.addAccountRow.value
    }

    public static var alwaysShowsQRLogin: Bool {
        return MTExtrasSettings.qrLoginAlways.value
    }

    /// The text of the alert shown when the server ended this session; with the setting on it
    /// starts with the likely reasons.
    public static func loggedOutAlertText(_ text: String, isDropAuth: Bool) -> String {
        if !isDropAuth || !MTExtrasSettings.logoutReason.value {
            return text
        }
        return MTStrings.Extras.Logout.reasons + "\n\n" + text
    }

    // MARK: Languages

    /// Community translations of Telegram offered next to the official languages. The language
    /// packs come from Telegram's own translation platform (`langpack.getLangPack`), as with a
    /// `t.me/setlanguage/<code>` link — no third-party server.
    public static var extraLocalizations: [LocalizationInfo] {
        if !MTExtrasSettings.extraLanguages.value {
            return []
        }
        return [
            LocalizationInfo(languageCode: "zhcncc", baseLanguageCode: "zh-hans-raw", customPluralizationCode: "zh", title: "Chinese (Simplified)", localizedTitle: "简体中文", isOfficial: true, totalStringCount: 7160, translatedStringCount: 7144, platformUrl: "https://translations.telegram.org/zhcncc/"),
            LocalizationInfo(languageCode: "taiwan", baseLanguageCode: "zh-hant-raw", customPluralizationCode: "zh", title: "Chinese (Taiwan)", localizedTitle: "正體中文", isOfficial: true, totalStringCount: 7160, translatedStringCount: 3761, platformUrl: "https://translations.telegram.org/taiwan/"),
            LocalizationInfo(languageCode: "hongkong", baseLanguageCode: "zh-hant-raw", customPluralizationCode: "zh", title: "Chinese (Hong Kong)", localizedTitle: "中文（香港）", isOfficial: true, totalStringCount: 7358, translatedStringCount: 6083, platformUrl: "https://translations.telegram.org/hongkong/"),
            LocalizationInfo(languageCode: "ja-raw", baseLanguageCode: "ja-raw", customPluralizationCode: "ja", title: "Japanese", localizedTitle: "日本語 (beta)", isOfficial: true, totalStringCount: 9697, translatedStringCount: 9683, platformUrl: "https://translations.telegram.org/ja/"),
            LocalizationInfo(languageCode: "vi-raw", baseLanguageCode: "vi-raw", customPluralizationCode: "vi", title: "Vietnamese", localizedTitle: "Tiếng Việt (beta)", isOfficial: true, totalStringCount: 7160, translatedStringCount: 3795, platformUrl: "https://translations.telegram.org/vi/"),
            LocalizationInfo(languageCode: "hi-raw", baseLanguageCode: "hi-raw", customPluralizationCode: "hi", title: "Hindi", localizedTitle: "हिन्दी (beta)", isOfficial: true, totalStringCount: 7358, translatedStringCount: 992, platformUrl: "https://translations.telegram.org/hi/"),
            LocalizationInfo(languageCode: "earmenian", baseLanguageCode: "earmenian", customPluralizationCode: "hy", title: "Armenian", localizedTitle: "Հայերեն", isOfficial: true, totalStringCount: 7358, translatedStringCount: 6384, platformUrl: "https://translations.telegram.org/earmenian/")
        ]
    }
}

/// «Цепочка упоминаний»: a long press on a mention suggestion asks the panel to put « @» after the
/// mention instead of a space. Main thread only: the suggestion list and the panel live there.
public enum MTExtrasMentionChain {
    private static var isRequested = false

    /// The suggestion was long-pressed; the panel's selection handler runs right after.
    public static func request() {
        assert(Thread.isMainThread)
        MTExtrasMentionChain.isRequested = true
    }

    /// Whether the selection being handled continues the chain; the request is used once.
    public static func consume() -> Bool {
        assert(Thread.isMainThread)
        let value = MTExtrasMentionChain.isRequested
        MTExtrasMentionChain.isRequested = false
        return value
    }

    /// Text that follows an inserted mention.
    public static func suffix() -> String {
        return MTExtrasMentionChain.consume() ? " @" : " "
    }
}

/// «Показать закреп»: a profile's menu asks the chat to show its pinned-message bar again. The chat
/// takes the request when it appears (the request lives 30 s, then it is forgotten). Main thread.
public enum MTExtrasPinnedRequests {
    private static var requests: [EnginePeer.Id: Double] = [:]
    private static let lifetime: Double = 30.0

    public static func request(peerId: EnginePeer.Id) {
        assert(Thread.isMainThread)
        MTExtrasPinnedRequests.requests[peerId] = CFAbsoluteTimeGetCurrent()
    }

    /// Whether the chat with `peerId` should clear its «closed pinned message» now.
    public static func take(peerId: EnginePeer.Id) -> Bool {
        assert(Thread.isMainThread)
        if MTExtrasPinnedRequests.requests.isEmpty {
            return false
        }
        guard let timestamp = MTExtrasPinnedRequests.requests.removeValue(forKey: peerId) else {
            return false
        }
        return CFAbsoluteTimeGetCurrent() - timestamp < MTExtrasPinnedRequests.lifetime
    }
}
