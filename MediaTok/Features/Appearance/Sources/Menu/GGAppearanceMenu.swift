import Foundation
import UIKit
import Display
import ItemListUI
import TelegramPresentationData
import GGCore
import GGSettingsUI
import GGAppearanceSettings

/// The appearance rows of the MediaTok menu: tabs «Сообщения», «Тема и фон» and the
/// «Профиль» part of «Профиль и Настройки». Every setting has exactly one row; titles are computed
/// at display time; sliders write once, on release (the preview follows the finger).
enum GGAppearanceMenu {
    // Sections of «Сообщения».
    static let messagesBubbles = GGMenuSectionID("appearance.messages.bubbles")
    static let messagesChecks = GGMenuSectionID("appearance.messages.checkmarks")
    static let messagesStickers = GGMenuSectionID("appearance.messages.stickers")
    static let messagesInterface = GGMenuSectionID("appearance.messages.interface")
    static let messagesTopBar = GGMenuSectionID("appearance.messages.topBar")
    // Sections of «Тема и фон».
    static let themeEdges = GGMenuSectionID("appearance.themeBackground.edges")
    static let themeBackground = GGMenuSectionID("appearance.themeBackground.chatBackground")
    static let themeSnow = GGMenuSectionID("appearance.themeBackground.snow")
    // Sections of «Профиль и Настройки» (the «Настройки» part belongs to the interface feature).
    static let profileInfo = GGMenuSectionID("appearance.profileSettings.profile")
    static let profileBackground = GGMenuSectionID("appearance.profileSettings.profileBackground")
    // The font tab.
    static let fontTab = GGMenuTabID("appearance.font")
    static let fontCustom = GGMenuSectionID("appearance.font.custom")
    static let fontBundled = GGMenuSectionID("appearance.font.bundled")
    static let fontSystem = GGMenuSectionID("appearance.font.systemDesigns")
    static let fontFamilies = GGMenuSectionID("appearance.font.families")
    // The stylish outgoing chat text font tab.
    static let chatFontTab = GGMenuTabID("appearance.chatFont")
    static let chatFontDisable = GGMenuSectionID("appearance.chatFont.disable")
    static let chatFontCyrillic = GGMenuSectionID("appearance.chatFont.cyrillic")
    static let chatFontMath = GGMenuSectionID("appearance.chatFont.math")

    static func register() {
        GGAppearanceMenu.registerMessages()
        GGAppearanceMenu.registerFont()
        GGAppearanceMenu.registerChatFont()
        GGAppearanceMenu.registerTheme()
        GGAppearanceMenu.registerProfile()
    }

    // MARK: Formats

    static func percent(_ value: Double) -> String {
        return GGStrings.Appearance.Common.percent(value: "\(Int(value.rounded()))")
    }

    static func points(_ value: Double) -> String {
        return GGStrings.Appearance.Common.points(value: "\(Int(value.rounded()))")
    }

    static func colorLabel(_ setting: GGSetting<String>) -> String {
        if let rgb = ggAppearanceParseColor(setting.value) {
            return "#" + ggAppearanceColorString(rgb)
        }
        return GGStrings.Appearance.Common.automatic
    }

    // MARK: «Сообщения»

    private static func registerMessages() {
        let tab = GGMenuTabID.appearanceMessages

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.messages.preview",
            section: .preview(of: tab),
            order: 100,
            title: { "" },
            // Live: bubbles follow the sliders of the bubble editor while dragged (U6); the top bar
            // follows «Скрыть в шапке чата» (U7).
            kind: .preview(.miniChat(GGAppearancePreview.configuration(scope: "appearance.messages", overlays: false, content: { _ in
                var content = GGAppearancePreview.sampleContent()
                if content.messages.count > 1 {
                    // Shows the «edited» label, the time and the checkmarks the options change.
                    content.messages[1].isEdited = true
                }
                return content
            })))
        ))

        // Font: its own tab with samples.
        GGMenuRegistry.register(tab: GGMenuTabDescriptor(
            id: GGAppearanceMenu.fontTab,
            parent: .tab(tab),
            title: { GGStrings.Appearance.Font.title },
            topView: GGMenuTopView(content: .emoji("🔤"), text: { GGStrings.Appearance.Font.info }),
            searchKeywords: { [GGStrings.Appearance.Font.keywords] }
        ), linkIn: .main(of: tab), order: 100, subtitle: { GGStrings.Appearance.Font.subtitle }, icon: .bundle("Chat/Context Menu/FormatText"), label: { _ in
            return GGFonts.selectedDisplayName
        })

        // Stylish outgoing chat text fonts (32 Unicode + Cyrillic styles visible to everyone).
        GGMenuRegistry.register(tab: GGMenuTabDescriptor(
            id: GGAppearanceMenu.chatFontTab,
            parent: .tab(tab),
            title: { GGStrings.Appearance.ChatFont.title },
            topView: GGMenuTopView(content: .emoji("✨"), text: { GGStrings.Appearance.ChatFont.info }),
            searchKeywords: { [GGStrings.Appearance.ChatFont.keywords] }
        ), linkIn: .main(of: tab), order: 150, subtitle: { GGStrings.Appearance.ChatFont.subtitle }, icon: .bundle("Chat/Context Menu/FormatText"), label: { _ in
            return GGChatTextFonts.selectedDisplayName
        })

        // Dedicated top quick-access MediaTok section on Root Settings screen.
        let rootMediaTokSection = GGMenuSectionID("root.mediatokStudio")
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(
            id: rootMediaTokSection,
            screen: .root,
            order: 100,
            header: { "⚡ ЭКСКЛЮЗИВЫ MEDIATOK" }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.spotlight",
            section: rootMediaTokSection,
            order: 50,
            title: { "🔍 Палитра команд (Spotlight)" },
            subtitle: { "Быстрый поиск всех фич MediaTok, LRC, сети и ГС" },
            icon: .system("magnifyingglass"),
            kind: .action({ context in
                GGMediaTokWave7Tools.presentSpotlightPalette(accountContext: context.context, menuContext: context)
            }),
            searchKeywords: { ["spotlight", "cmd", "поиск", "палитра", "команды", "490"] },
            label: { _ in "CMD" }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.discordProfile",
            section: rootMediaTokSection,
            order: 100,
            title: { GGStrings.Appearance.DiscordProfile.title },
            subtitle: { GGStrings.Appearance.DiscordProfile.subtitle },
            icon: .system("sparkles"),
            kind: .action({ context in
                GGMediaTokDiscordProfile.presentOwnEditor(context: context)
            }),
            label: { context in
                let p = GGDiscordProfileStore.shared.profile(for: context.context.account.peerId)
                return (p != nil && !(p?.isEmpty ?? true)) ? "ON" : "4K"
            }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.tiktokFeed",
            section: rootMediaTokSection,
            order: 200,
            title: { "🎬 TikTok-лента каналов" },
            subtitle: { "Вертикальная свайп-лента видео и кружков из каналов" },
            icon: .system("play.rectangle.fill"),
            kind: .action({ context in
                let feed = GGTikTokFeedViewController(context: context.context, navigationController: context.navigationController)
                context.presentNative(feed)
            }),
            label: { _ in "REELS" }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.stickerVault",
            section: rootMediaTokSection,
            order: 300,
            title: { "🎭 /stickers — База 10к стикеров + ИИ" },
            subtitle: { "Команды /s и /s!, OCR и загрузка папок с ПК по Wi-Fi" },
            icon: .system("face.smiling"),
            kind: .action({ context in
                GGMediaTokStickerVault.presentManagerFromMenu(context: context)
            }),
            label: { _ in
                let c = GGStickerVaultStore.shared.count
                return c > 0 ? "\(c)" : "10K"
            }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.liquidUi",
            section: rootMediaTokSection,
            order: 400,
            title: { "🧊 Liquid Glass / Zero-Bloat / 4K 60fps" },
            subtitle: { "Стекло iOS 27, компактный чат, стиль галочек, видео 4K" },
            icon: .system("cube.transparent"),
            kind: .action({ context in
                GGMediaTokLiquidUI.presentStudio(context: context)
            }),
            label: { _ in
                return GGMediaTokLiquidUI.isVideo4k60Enabled ? "4K60" : "iOS27"
            }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.premiumEmoji",
            section: rootMediaTokSection,
            order: 450,
            title: { "✨ Премиум Эмодзи" },
            subtitle: { "Все паки в клавиатуре, отправка в чатах без подписки, эмодзи-статус" },
            icon: .system("face.smiling"),
            kind: .action({ context in
                GGMediaTokWave5Tools.presentPremiumEmojiSheet(context: context)
            }),
            searchKeywords: { ["emoji", "эмодзи", "премиум", "premium", "статус"] },
            label: { _ in GGMediaTokWave5Tools.isPremiumEmojiEnabled ? "ВКЛ" : "ВЫКЛ" }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.wave8Studio",
            section: rootMediaTokSection,
            order: 470,
            title: { "🪞 Примерочная / QR / Размытие лиц / PDF / Погода" },
            subtitle: { "Sandbox профиля, градиент-QR, стикеры в ZIP, поиск фото, PDF-подпись" },
            icon: .system("wand.and.stars"),
            kind: .action({ context in
                GGMediaTokWave8Tools.presentWave2Studio(context: context.context)
            }),
            searchKeywords: { ["sandbox", "примерочная", "qr", "zip", "pdf", "погода", "лица", "батарея", "499", "466", "478", "480", "460", "461", "462", "497", "486"] },
            label: { _ in "b3777" }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.wave9Network",
            section: rootMediaTokSection,
            order: 472,
            title: { "🌐 Сеть / Спидтест DC / VPN-слот / Аккаунты (∞)" },
            subtitle: { "DC1–DC5 пинг, прокси на аккаунт, клон настроек, Sync v2, DoH, SHA-256" },
            icon: .system("network"),
            kind: .action({ context in
                GGMediaTokWave9Tools.presentWave3NetworkHub(context: context.context)
            }),
            searchKeywords: { ["dc", "speedtest", "vpn", "proxy", "sync", "doh", "sha256", "аккаунты", "сеть", "401", "406", "422", "423", "495"] },
            label: { context in "DC\(context.context.account.network.datacenterId)" }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.wave7Tools",
            section: rootMediaTokSection,
            order: 475,
            title: { "🎵 Текст песни (LRC) / Сеть / ГС / Safe Mode" },
            subtitle: { "Караоке lrclib.net, Force Reconnect, подтверждение ГС и 99:59, b3777" },
            icon: .system("waveform.badge.magnifyingglass"),
            kind: .action({ context in
                GGMediaTokWave7Tools.presentWave7QuickHub(context: context)
            }),
            searchKeywords: { ["lyrics", "lrc", "reconnect", "voice", "гс", "safe", "whatsnew", "371", "416", "493"] },
            label: { _ in "LRC" }
        ))
        GGMenuRegistry.register(GGMenuRow(
            id: "root.mediatok.allFeatures",
            section: rootMediaTokSection,
            order: 500,
            title: { "🛠 Все фичи MediaTok Studio (24)" },
            subtitle: { "Spotlight, LRC, ГС, языки, E2E AES-256, Anti-Screamer, AdBlock, Call Guard" },
            icon: .system("bolt.fill"),
            kind: .action({ context in
                context.open(tab: .appearanceMessages)
            }),
            label: { _ in "Все" }
        ))

        // Dedicated MediaTok Studio section in Appearance -> Messages (right below live preview).
        let mediaTokSection = GGMenuSectionID("appearance.messages.mediatokStudio")
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(
            id: mediaTokSection,
            screen: .tab(tab),
            order: 150,
            header: { "⚡ Эксклюзивы MediaTok Studio" }
        ))

        // Premium Emoji without subscription (keyboard unlock, zero-width chat codec, profile emoji status).
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.premiumEmoji",
            section: mediaTokSection,
            order: 50,
            title: { "✨ Премиум Эмодзи" },
            subtitle: { "Разблокировка всех паков в клавиатуре, отправка в чатах и эмодзи-статус" },
            kind: .action({ context in
                GGMediaTokWave5Tools.presentPremiumEmojiSheet(context: context)
            }),
            searchKeywords: { ["emoji", "эмодзи", "премиум", "premium", "статус"] },
            label: { _ in GGMediaTokWave5Tools.isPremiumEmojiEnabled ? "ВКЛ" : "ВЫКЛ" }
        ))

        // Language Studio: 66 public Telegram language packs + Full Language Editor (all strings, LIVE).
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.langs.studio",
            section: mediaTokSection,
            order: 100,
            title: { GGStrings.Appearance.LangStudio.title },
            subtitle: { GGStrings.Appearance.LangStudio.subtitle },
            kind: .action({ context in
                GGMediaTokLangs.presentStudio(context: context)
            }),
            searchKeywords: { [GGStrings.Appearance.LangStudio.keywords] },
            label: { _ in
                let n = GGMediaTokLangs.overrideCount
                return n > 0 ? "\(n)" : "66+"
            }
        ))

        // Discord-style Profile Studio (4K banner + animated effects + avatar frame + Steam & Roblox + global sync).
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.discordProfile",
            section: mediaTokSection,
            order: 200,
            title: { GGStrings.Appearance.DiscordProfile.title },
            subtitle: { GGStrings.Appearance.DiscordProfile.subtitle },
            kind: .action({ context in
                GGMediaTokDiscordProfile.presentOwnEditor(context: context)
            }),
            searchKeywords: { [GGStrings.Appearance.DiscordProfile.keywords] },
            label: { context in
                let p = GGDiscordProfileStore.shared.profile(for: context.context.account.peerId)
                return (p != nil && !(p?.isEmpty ?? true)) ? "ON" : "4K"
            }
        ))

        // Per-chat AES-256-GCM E2E Encryption manager.
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.e2e",
            section: mediaTokSection,
            order: 300,
            title: { GGStrings.Appearance.E2e.title },
            subtitle: { GGStrings.Appearance.E2e.subtitle },
            kind: .action({ context in
                GGMediaTokE2E.presentManager(context: context)
            }),
            searchKeywords: { [GGStrings.Appearance.E2e.keywords] },
            label: { _ in
                let n = GGMediaTokE2E.activeCount
                return n > 0 ? "\(n)" : "AES"
            }
        ))

        // Anti-Screamer, Loud Bad Sounds & Moan Filter.
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.audioGuard",
            section: mediaTokSection,
            order: 400,
            title: { GGStrings.Appearance.AudioGuard.title },
            subtitle: { GGStrings.Appearance.AudioGuard.subtitle },
            kind: .action({ context in
                GGMediaTokAudioGuard.presentSettings(context: context)
            }),
            searchKeywords: { [GGStrings.Appearance.AudioGuard.keywords] },
            label: { _ in
                return GGMediaTokAudioGuard.modeLabel
            }
        ))

        // Quick cheat-sheet & Wave 4 tools (.q quote stickers, .stats, AFK, OCR, Cutout stickers, Wallpaper sound).
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.commands",
            section: mediaTokSection,
            order: 500,
            title: { GGStrings.Appearance.Commands.title },
            subtitle: { GGStrings.Appearance.Commands.subtitle },
            kind: .action({ context in
                GGMediaTokWave4Tools.presentHub(context: context)
            }),
            searchKeywords: { [GGStrings.Appearance.Commands.keywords] }
        ))

        // Wave 5: /stickers 10K AI Vault + PC Wi-Fi Uploader
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.stickerVault",
            section: mediaTokSection,
            order: 600,
            title: { "🎭 /stickers — База 10к стикеров + ИИ-поиск" },
            subtitle: { "Команды /s и /s!, OCR и Vision AI, загрузка папок с ПК по Wi-Fi" },
            kind: .action({ context in
                GGMediaTokStickerVault.presentManagerFromMenu(context: context)
            }),
            searchKeywords: { ["stickers", "стикеры", "поиск", "ии", "ai", "wifi"] },
            label: { _ in
                let c = GGStickerVaultStore.shared.count
                return c > 0 ? "\(c)" : "10K"
            }
        ))

        // Wave 5: Liquid Glass iOS 27 / Zero-Bloat / Compact / Checkmarks / 4K 60fps
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.liquidUi",
            section: mediaTokSection,
            order: 700,
            title: { "🧊 Liquid Glass / Zero-Bloat / Галочки / 4K 60fps" },
            subtitle: { "Стекло iOS 27, убрать лишнее, компактный чат, стиль галочек, видео 4K" },
            kind: .action({ context in
                GGMediaTokLiquidUI.presentStudio(context: context)
            }),
            searchKeywords: { ["glass", "liquid", "bloat", "4k", "60fps", "галочки", "стекло", "видео"] },
            label: { _ in
                return GGMediaTokLiquidUI.isVideo4k60Enabled ? "4K60" : "iOS27"
            }
        ))

        // Wave 5: Streaks / Clipboard / Guards / Metadata Stripper / Games / Updater
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.wave5Hub",
            section: mediaTokSection,
            order: 800,
            title: { "🔥 Огоньки / Буфер / Защита / Игры / Обновления" },
            subtitle: { "Серии чатов, история буфера обмена, EXIF/PDF, подтверждения, 2048, ESign" },
            kind: .action({ context in
                GGMediaTokWave5Tools.presentHub(context: context)
            }),
            searchKeywords: { ["огоньки", "streak", "буфер", "clipboard", "games", "игры", "esign", "обновления"] },
            label: { _ in
                let top = GGMediaTokStreaks.topStreaks(limit: 1).first?.record.currentStreak ?? 0
                return top > 0 ? "🔥\(top)" : "W5"
            }
        ))

        // Wave 6: TikTok / Reels Channel Media Feed (#187)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.tiktokFeed",
            section: mediaTokSection,
            order: 900,
            title: { "🎬 TikTok-лента каналов" },
            subtitle: { "Вертикальная свайп-лента видео и видеосообщений со всех каналов" },
            kind: .action({ context in
                let feed = GGTikTokFeedViewController(context: context.context, navigationController: context.navigationController)
                context.presentNative(feed)
            }),
            searchKeywords: { ["tiktok", "тикток", "лента", "видео", "reels", "shorts"] },
            label: { _ in "REELS" }
        ))

        // Wave 6: MediaTok Achievements System (#168)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.achievements",
            section: mediaTokSection,
            order: 1000,
            title: { "🏆 Достижения MediaTok" },
            subtitle: { "Ранги, ночной дозор, стрикер, криптограф, шеринг карточки" },
            kind: .action({ context in
                let vc = GGAchievementsViewController()
                vc.overrideUserInterfaceStyle = .dark
                let nav = UINavigationController(rootViewController: vc)
                nav.overrideUserInterfaceStyle = .dark
                context.presentNative(nav)
            }),
            searchKeywords: { ["ачивки", "достижения", "ранг", "награды", "achievements"] },
            label: { _ in
                let c = GGMediaTokWave6Tools.getUnlockedAchievements().count
                return "\(c)/12"
            }
        ))

        // Wave 6: Bottom Bar / Tab Bar Editor (#110)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.bottomBar",
            section: mediaTokSection,
            order: 1100,
            title: { "📱 Редактор нижнего бара" },
            subtitle: { "Пресеты таббара, скрыть звонки/контакты, парящий бар (+8pt)" },
            kind: .action({ context in
                let vc = GGBottomBarStudioViewController()
                vc.overrideUserInterfaceStyle = .dark
                let nav = UINavigationController(rootViewController: vc)
                nav.overrideUserInterfaceStyle = .dark
                context.presentNative(nav)
            }),
            searchKeywords: { ["бар", "таббар", "низ", "панель", "110", "минимал"] },
            label: { _ in "110" }
        ))

        // Wave 6: Call Confirm Guard (#58)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.callConfirm",
            section: mediaTokSection,
            order: 1200,
            title: { "📞 Защита от случайных звонков (Call Guard)" },
            subtitle: { "Подтверждение перед стартом аудио- и видеозвонков из чатов и профилей" },
            kind: .action({ context in
                GGMediaTokWave6Tools.isCallConfirmEnabled.toggle()
                GGMediaTokLiquidUI.applyMediaTokGlobalSettings(["ghostMode.confirmCalls": false])
                let st = GGMediaTokWave6Tools.isCallConfirmEnabled ? "ВКЛ" : "ВЫКЛ"
                context.presentToast("Защита звонков: \(st)")
            }),
            searchKeywords: { ["звонки", "call", "confirm", "случайный", "guard"] },
            label: { _ in GGMediaTokWave6Tools.isCallConfirmEnabled ? "ВКЛ" : "ВЫКЛ" }
        ))

        // Wave 6: Channel Ad-Blocker (#188)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.adBlock",
            section: mediaTokSection,
            order: 1300,
            title: { "🚫 Блокировщик рекламы в каналах (#188)" },
            subtitle: { "Авто-заглушение и сворачивание рекламных постов (erid, #реклама, ООО)" },
            kind: .action({ context in
                GGMediaTokWave6Tools.isAdBlockEnabled.toggle()
                let st = GGMediaTokWave6Tools.isAdBlockEnabled ? "ВКЛ" : "ВЫКЛ"
                context.presentToast("Анти-реклама каналов: \(st)")
            }),
            searchKeywords: { ["реклама", "adblock", "erid", "спам", "каналы"] },
            label: { _ in GGMediaTokWave6Tools.isAdBlockEnabled ? "ВКЛ" : "ВЫКЛ" }
        ))

        // Wave 6: MediaTok Wrapped (#169), Self-Diagnostics (#199) & Privacy Screen (#48)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.wrappedDiag",
            section: mediaTokSection,
            order: 1400,
            title: { "🩺 MediaTok Wrapped / Диагностика / Защита от плеча" },
            subtitle: { "Итоги статистики, статус модулей, сниппеты, граффити, .ai/.wiki/.scratch/.qr" },
            kind: .action({ context in
                GGMediaTokWave6Tools.presentWrappedAndDiagnostics(context: context)
            }),
            searchKeywords: { ["wrapped", "итоги", "диагностика", "privacy", "плеча", "статистика"] },
            label: { _ in "W6" }
        ))

        // Wave 7 (Roadmap Wave 1 — b3775): Spotlight (#490), LRC Lyrics (#371), Force Reconnect (#416), Voice Tools (#379/#377), What's New/Bug/Safe Mode (#491/#492/#493)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.spotlight",
            section: mediaTokSection,
            order: 1500,
            title: { "🔍 Палитра команд MediaTok (Spotlight)" },
            subtitle: { "Быстрый поиск и запуск любой функции MediaTok (.cmd в чате)" },
            kind: .action({ context in
                GGMediaTokWave7Tools.presentSpotlightPalette(accountContext: context.context, menuContext: context)
            }),
            searchKeywords: { ["spotlight", "cmd", "палитра", "поиск", "команды", "490"] },
            label: { _ in "CMD" }
        ))

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.lrcLyrics",
            section: mediaTokSection,
            order: 1600,
            title: { "🎵 Синхронные тексты песен (LRC)" },
            subtitle: { "Живая подсветка строк под музыку Telegram через lrclib.net (.lyrics)" },
            kind: .action({ context in
                GGMediaTokWave7Tools.presentLyricsViewer(context: context.context)
            }),
            searchKeywords: { ["lyrics", "lrc", "текст", "песни", "караоке", "музыка", "371"] },
            label: { _ in "LRC" }
        ))

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.forceReconnect",
            section: mediaTokSection,
            order: 1700,
            title: { "🔄 Переподключить сеть (Force Reconnect)" },
            subtitle: { "Мгновенный сброс зависшего соединения с серверами Telegram (.reconnect)" },
            kind: .action({ context in
                GGMediaTokWave7Tools.forceReconnect(context: context.context)
            }),
            searchKeywords: { ["reconnect", "сеть", "переподключить", "интернет", "416"] },
            label: { _ in "NET" }
        ))

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.voiceTools",
            section: mediaTokSection,
            order: 1800,
            title: { "🎙 Голосовые (ГС): Подтверждение и 99:59" },
            subtitle: { "Подтверждать отправку ГС и опциональная фейк-длительность (0:00 / 99:59)" },
            kind: .action({ context in
                GGMediaTokWave7Tools.presentVoiceToolsSheet(context: context.context)
            }),
            searchKeywords: { ["гс", "голосовые", "voice", "подтверждение", "99:59", "длительность", "377", "379"] },
            label: { _ in GGMediaTokWave7Tools.voiceSummaryLabel }
        ))

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.whatsNewSafeMode",
            section: mediaTokSection,
            order: 1900,
            title: { "✨ Что нового (b3777) / Баг-репорт / Safe Mode" },
            subtitle: { "Список изменений, копирование диагностики и безопасный сброс визуала" },
            kind: .action({ context in
                GGMediaTokWave7Tools.presentWave7QuickHub(context: context)
            }),
            searchKeywords: { ["whatsnew", "нового", "баг", "идея", "safe", "безопасный", "491", "492", "493"] },
            label: { _ in "b3777" }
        ))

        // Wave 8 (Roadmap Wave 2 — b3776): Sandbox (#499), Profile QR (#466), Face Blur (#460), PDF Scan/Sign (#461/#462), Weather (#497), Battery Spoof (#486)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.profileSandbox",
            section: mediaTokSection,
            order: 2000,
            title: { "🪞 Примерочная профиля (MediaTok Sandbox)" },
            subtitle: { "Живой превью темы Nitro, рамки, эффекта, погоды и статуса до сохранения" },
            kind: .action({ context in
                GGMediaTokWave8Tools.presentProfileSandbox(context: context.context)
            }),
            searchKeywords: { ["sandbox", "примерочная", "профиль", "превью", "499"] },
            label: { _ in "499" }
        ))

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.profileQr",
            section: mediaTokSection,
            order: 2100,
            title: { "📱 Красивый QR-код профиля" },
            subtitle: { "Градиентная карточка с логотипом MediaTok и твоим @username" },
            kind: .action({ context in
                GGMediaTokWave8Tools.presentProfileQR(context: context.context)
            }),
            searchKeywords: { ["qr", "код", "профиль", "градиент", "466"] },
            label: { _ in "QR" }
        ))

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.faceBlur",
            section: mediaTokSection,
            order: 2200,
            title: { "😶‍🌫️ Размытие лиц на фото (Vision AI)" },
            subtitle: { "Автоматическое обнаружение и размытие лиц в 1 тап (.blurface)" },
            kind: .action({ context in
                GGMediaTokWave8Tools.presentFaceBlurPicker(context: context.context, targetPeerId: nil)
            }),
            searchKeywords: { ["blur", "лица", "размытие", "фото", "vision", "460"] },
            label: { _ in "AI" }
        ))

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.pdfScanSign",
            section: mediaTokSection,
            order: 2300,
            title: { "📄 Сканер документов → PDF и ✍️ Подпись PDF" },
            subtitle: { "Сканирование камерой в PDF + подпись пальцем любого PDF-файла" },
            kind: .action({ context in
                GGMediaTokWave8Tools.presentWave2Studio(context: context.context)
            }),
            searchKeywords: { ["pdf", "скан", "сканер", "подпись", "документ", "461", "462"] },
            label: { _ in "PDF" }
        ))

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.weatherBattery",
            section: mediaTokSection,
            order: 2400,
            title: { "🌤 Живая погода профиля и 🔋 Спуфинг батареи" },
            subtitle: { "Open-Meteo погода города на профиль + подмена заряда батареи" },
            kind: .action({ context in
                GGMediaTokWave8Tools.presentWave2Studio(context: context.context)
            }),
            searchKeywords: { ["weather", "погода", "батарея", "battery", "spoof", "497", "486"] },
            label: { _ in GGMediaTokWave8Tools.isBatterySpoofEnabled ? "\(GGMediaTokWave8Tools.spoofedBatteryLevel)%" : "497" }
        ))

        // Wave 9 (Roadmap Wave 3 — b3778): DC Speedtest (#406/#415), VPN Slot (#401/#402), Unlimited Accounts/Proxies (#422/#423), Sync v2 (#495/#409), DoH (#417), SHA-256 (#420/#421)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.dcSpeedtest",
            section: mediaTokSection,
            order: 2500,
            title: { "📡 Спидтест DC1–DC5 и монитор сети" },
            subtitle: { "Замер пинга серверов Telegram, Catbox CDN и MediaTok Sync (.dc)" },
            kind: .action({ context in
                GGMediaTokWave9Tools.presentDcSpeedtest(context: context.context)
            }),
            searchKeywords: { ["dc", "speedtest", "ping", "сеть", "пинг", "406", "415"] },
            label: { context in "DC\(context.context.account.network.datacenterId)" }
        ))

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.wave3Hub",
            section: mediaTokSection,
            order: 2600,
            title: { "🌐 VPN-слот / Прокси (∞ акк.) / Sync v2 / DoH / SHA-256" },
            subtitle: { "Split Tunneling, клонирование настроек на аккаунты, резервное зеркало синка" },
            kind: .action({ context in
                GGMediaTokWave9Tools.presentWave3NetworkHub(context: context.context)
            }),
            searchKeywords: { ["vpn", "split", "proxy", "аккаунты", "клон", "sync", "doh", "sha256", "401", "402", "422", "423", "495", "417", "420"] },
            label: { _ in "W3" }
        ))

        // Wave 10 (Roadmap Wave 4 — b3779): Sticker Maker (#456), Mini Apps (#451-#455), Voicemod Presets (#380), Chat Analytics/Top/TimeMachine/FakeRoute
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.wave4Hub",
            section: mediaTokSection,
            order: 2700,
            title: { "🚀 Аналитика / ГС +15 dB / Стикеры / Mini Apps / Маршрут" },
            subtitle: { "График чата, топ постов, конструктор 512px, фейк-гео, Машина времени, Mini Apps" },
            kind: .action({ context in
                GGMediaTokWave10Tools.presentWave4Hub(context: context.context, peerId: nil)
            }),
            searchKeywords: { ["аналитика", "график", "топ", "стикеры", "miniapps", "маршрут", "гео", "машина времени", "гс", "voicemod", "375", "376", "380", "451", "456", "476", "477", "485", "498"] },
            label: { _ in "W4" }
        ))

        // Wave 11 (Roadmap Wave 5): OCR Translate (#479), Magic Eraser (#481), 4K Upscale (#482), Mini-Games (#467), RSS (#470), Shared Clipboard (#419), Ecosystem (#487-#489/#494)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.wave5EcosystemHub",
            section: mediaTokSection,
            order: 2800,
            title: { "✨ AI Фото / Ластик / 4K / Игры / RSS / Буфер ПК / Siri" },
            subtitle: { "Перевод манги/фото, Magic Eraser, 4K апскейл, Крестики-нолики & 2048, RSS, буфер ПК, Команды" },
            kind: .action({ context in
                GGMediaTokWave11Tools.presentWave5Hub(context: context.context, peerId: nil)
            }),
            searchKeywords: { ["ocr", "манга", "перевод", "ластик", "eraser", "upscale", "4k", "игры", "2048", "крестики", "rss", "буфер", "clipboard", "siri", "команды", "виджеты", "479", "481", "482", "467", "470", "419", "487", "488", "489", "494"] },
            label: { _ in "W5" }
        ))

        // Wave 12 (Signature 5): Stego (#501), Voice FX Studio (#502), Burn-After-Reading (#503), Cinematic Cards (#504), OSINT X-Ray (#505)
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.mediatok.wave12Lab",
            section: mediaTokSection,
            order: 2900,
            title: { "🔥 MediaTok Lab: Стеганография / Голос-FX / Бомба / Кино / OSINT" },
            subtitle: { "Секрет в пикселях PNG, студия голоса, AES-записки с PIN, кино-карточки, EXIF/фишинг" },
            kind: .action({ context in
                GGMediaTokWave12Tools.presentSignatureHub(context: context.context, peerId: nil)
            }),
            searchKeywords: { ["stego", "стеганография", "vfx", "голос", "демон", "рация", "burn", "бомба", "pin", "cinematic", "карточка", "osint", "xray", "exif", "фишинг", "501", "502", "503", "504", "505"] },
            label: { _ in "LAB" }
        ))

        // Bubbles.
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.messagesBubbles, screen: .tab(tab), order: 300, header: { GGStrings.Appearance.Bubbles.header }, footer: { _ in GGStrings.Appearance.Bubbles.footer }))
        let editorOn: (GGMenuContext) -> Bool = { _ in GGAppearanceSettings.bubbleEditor.value }
        GGMenuRegistry.register(GGMenuRow(id: "appearance.bubbles.editor", section: GGAppearanceMenu.messagesBubbles, order: 100, title: { GGStrings.Appearance.Bubbles.editor }, subtitle: { GGStrings.Appearance.Bubbles.editorInfo }, kind: .toggle(.global(GGAppearanceSettings.bubbleEditor)), searchKeywords: { [GGStrings.Appearance.Bubbles.keywords] }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.bubbles.incomingRadius", section: GGAppearanceMenu.messagesBubbles, order: 200, title: { GGStrings.Appearance.Bubbles.incomingRadius }, kind: .slider(.global(GGAppearanceSettings.bubbleIncomingRadius), range: 0.0 ... 16.0, step: 1.0, format: GGAppearanceMenu.points), isVisible: editorOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.bubbles.outgoingRadius", section: GGAppearanceMenu.messagesBubbles, order: 300, title: { GGStrings.Appearance.Bubbles.outgoingRadius }, kind: .slider(.global(GGAppearanceSettings.bubbleOutgoingRadius), range: 0.0 ... 16.0, step: 1.0, format: GGAppearanceMenu.points), isVisible: editorOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.bubbles.padding", section: GGAppearanceMenu.messagesBubbles, order: 400, title: { GGStrings.Appearance.Bubbles.padding }, kind: .slider(.global(GGAppearanceSettings.bubblePadding), range: 0.0 ... 24.0, step: 1.0, format: GGAppearanceMenu.points), isVisible: editorOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.bubbles.width", section: GGAppearanceMenu.messagesBubbles, order: 500, title: { GGStrings.Appearance.Bubbles.width }, kind: .slider(.global(GGAppearanceSettings.bubbleWidth), range: 40.0 ... 100.0, step: 5.0, format: GGAppearanceMenu.percent), isVisible: editorOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.bubbles.backgroundOpacity", section: GGAppearanceMenu.messagesBubbles, order: 600, title: { GGStrings.Appearance.Bubbles.backgroundOpacity }, kind: .slider(.global(GGAppearanceSettings.bubbleBackgroundOpacity), range: 0.0 ... 100.0, step: 5.0, format: GGAppearanceMenu.percent), isVisible: editorOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.bubbles.outlineOpacity", section: GGAppearanceMenu.messagesBubbles, order: 700, title: { GGStrings.Appearance.Bubbles.outlineOpacity }, kind: .slider(.global(GGAppearanceSettings.bubbleOutlineOpacity), range: 0.0 ... 100.0, step: 5.0, format: GGAppearanceMenu.percent), isVisible: editorOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.bubbles.reset", section: GGAppearanceMenu.messagesBubbles, order: 800, title: { GGStrings.Appearance.Bubbles.reset }, kind: .action({ _ in
            GGAppearanceSettings.bubbleIncomingRadius.reset()
            GGAppearanceSettings.bubbleOutgoingRadius.reset()
            GGAppearanceSettings.bubblePadding.reset()
            GGAppearanceSettings.bubbleWidth.reset()
            GGAppearanceSettings.bubbleBackgroundOpacity.reset()
            GGAppearanceSettings.bubbleOutlineOpacity.reset()
        }), isVisible: editorOn, isDestructive: true))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.bubbles.hideTails", section: GGAppearanceMenu.messagesBubbles, order: 900, title: { GGStrings.Appearance.Bubbles.hideTails }, subtitle: { GGStrings.Appearance.Bubbles.hideTailsInfo }, kind: .toggle(.global(GGAppearanceSettings.bubbleHideTails))))

        // Checkmarks.
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.messagesChecks, screen: .tab(tab), order: 400, header: { GGStrings.Appearance.Checkmarks.header }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.checkmarks.readColor", section: GGAppearanceMenu.messagesChecks, order: 100, title: { GGStrings.Appearance.Checkmarks.readColor }, kind: .action({ context in
            GGColorPicker.present(context: context, setting: GGAppearanceSettings.readCheckColor, fallback: UIColor(rgb: 0x19c700))
        }), searchKeywords: { [GGStrings.Appearance.Checkmarks.keywords] }, label: { _ in GGAppearanceMenu.colorLabel(GGAppearanceSettings.readCheckColor) }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.checkmarks.unreadSameAsRead", section: GGAppearanceMenu.messagesChecks, order: 200, title: { GGStrings.Appearance.Checkmarks.unreadSameAsRead }, kind: .toggle(.global(GGAppearanceSettings.unreadCheckSameAsRead)), isVisible: { _ in !GGAppearanceSettings.readCheckColor.value.isEmpty }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.checkmarks.unreadColor", section: GGAppearanceMenu.messagesChecks, order: 300, title: { GGStrings.Appearance.Checkmarks.unreadColor }, kind: .action({ context in
            GGColorPicker.present(context: context, setting: GGAppearanceSettings.unreadCheckColor, fallback: UIColor(rgb: 0xa3a3a3))
        }), isVisible: { _ in !GGAppearanceSettings.unreadCheckSameAsRead.value || GGAppearanceSettings.readCheckColor.value.isEmpty }, label: { _ in GGAppearanceMenu.colorLabel(GGAppearanceSettings.unreadCheckColor) }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.checkmarks.inChatList", section: GGAppearanceMenu.messagesChecks, order: 400, title: { GGStrings.Appearance.Checkmarks.inChatList }, kind: .toggle(.global(GGAppearanceSettings.checkColorsInChatList)), isVisible: { _ in !GGAppearanceSettings.readCheckColor.value.isEmpty }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.checkmarks.reset", section: GGAppearanceMenu.messagesChecks, order: 500, title: { GGStrings.Appearance.Checkmarks.reset }, kind: .action({ _ in
            GGAppearanceSettings.readCheckColor.reset()
            GGAppearanceSettings.unreadCheckColor.reset()
        }), isVisible: { _ in !GGAppearanceSettings.readCheckColor.value.isEmpty || !GGAppearanceSettings.unreadCheckColor.value.isEmpty }, isDestructive: true))

        // Stickers.
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.messagesStickers, screen: .tab(tab), order: 500, header: { GGStrings.Appearance.Stickers.header }))
        // Live: the emoji and the sticker follow the size slider while it is dragged (2026-11-02).
        GGMenuRegistry.register(GGMenuRow(id: "appearance.stickers.preview", section: GGAppearanceMenu.messagesStickers, order: 50, title: { "" }, kind: .preview(.custom(height: GGStickerSizePreviewView.height, make: { _ in
            return GGStickerSizePreviewView(frame: .zero)
        }))))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.stickers.size", section: GGAppearanceMenu.messagesStickers, order: 100, title: { GGStrings.Appearance.Stickers.size }, kind: .slider(.global(GGAppearanceSettings.stickerSize), range: 50.0 ... 200.0, step: 5.0, format: GGAppearanceMenu.percent)))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.stickers.hideTime", section: GGAppearanceMenu.messagesStickers, order: 200, title: { GGStrings.Appearance.Stickers.hideTime }, kind: .toggle(.global(GGAppearanceSettings.stickerHideTime))))

        // Message interface.
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.messagesInterface, screen: .tab(tab), order: 600, header: { GGStrings.Appearance.Messages.header }))
        // «Скрыть в сообщениях» (2026-10-27): four switches in one row that opens in place.
        let hiddenInMessages: [(String, () -> String, GGSetting<Bool>)] = [
            ("appearance.messages.hideEdited", { GGStrings.Appearance.Messages.hiddenEdited }, GGAppearanceSettings.hideEdited),
            ("appearance.messages.hideTime", { GGStrings.Appearance.Messages.hiddenTime }, GGAppearanceSettings.hideTime),
            ("appearance.messages.hideViewCounts", { GGStrings.Appearance.Messages.hiddenViewCounts }, GGAppearanceSettings.hideViewCounts),
            ("appearance.messages.hideChannelComments", { GGStrings.Appearance.Messages.hiddenChannelComments }, GGAppearanceSettings.hideChannelComments)
        ]
        GGMenuRegistry.register(GGMenuRow(id: "appearance.messages.hidden", section: GGAppearanceMenu.messagesInterface, order: 100, title: { GGStrings.Appearance.Messages.hidden }, kind: .expandableList(children: GGAppearanceMenu.hiddenChildren(hiddenInMessages, section: GGAppearanceMenu.messagesInterface), summary: GGAppearanceMenu.hiddenSummary)))
        let toggles: [(String, Int, () -> String, (() -> String)?, GGSetting<Bool>)] = [
            ("appearance.messages.secondsInTime", 300, { GGStrings.Appearance.Messages.secondsInTime }, { GGStrings.Appearance.Messages.secondsInTimeInfo }, GGAppearanceSettings.secondsInTime),
            ("appearance.messages.exactLastSeen", 400, { GGStrings.Appearance.Messages.exactLastSeen }, { GGStrings.Appearance.Messages.exactLastSeenInfo }, GGAppearanceSettings.exactLastSeen),
            ("appearance.messages.wideChannelPosts", 900, { GGStrings.Appearance.Messages.wideChannelPosts }, nil, GGAppearanceSettings.wideChannelPosts),
            ("appearance.messages.authorOnline", 1000, { GGStrings.Appearance.Messages.authorOnline }, { GGStrings.Appearance.Messages.authorOnlineInfo }, GGAppearanceSettings.authorOnlineIndicator),
            ("appearance.messages.colorSwatches", 1100, { GGStrings.Appearance.Messages.colorSwatches }, { GGStrings.Appearance.Messages.colorSwatchesInfo }, GGAppearanceSettings.colorSwatches),
            ("appearance.messages.noSelectionBlur", 1200, { GGStrings.Appearance.Messages.noSelectionBlur }, nil, GGAppearanceSettings.noSelectionBlur)
        ]
        for (id, order, title, subtitle, setting) in toggles {
            GGMenuRegistry.register(GGMenuRow(id: id, section: GGAppearanceMenu.messagesInterface, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting))))
        }
        // Two choices instead of four switches (2026-10-27): where reactions and formatting are hidden.
        GGMenuRegistry.register(GGMenuRow(id: "appearance.messages.hideReactions", section: GGAppearanceMenu.messagesInterface, order: 500, title: { GGStrings.Appearance.Messages.hideReactions }, kind: .choice(.global(GGAppearanceSettings.hideReactions), options: [
            GGMenuChoiceOption(value: GGHiddenReactions.off.rawValue, title: { GGStrings.Appearance.Messages.hiddenNowhere }),
            GGMenuChoiceOption(value: GGHiddenReactions.chats.rawValue, title: { GGStrings.Appearance.Messages.hideReactionsChats }),
            GGMenuChoiceOption(value: GGHiddenReactions.channels.rawValue, title: { GGStrings.Appearance.Messages.hideReactionsChannels }),
            GGMenuChoiceOption(value: GGHiddenReactions.all.rawValue, title: { GGStrings.Appearance.Messages.hiddenEverywhere })
        ])))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.messages.hideFormatting", section: GGAppearanceMenu.messagesInterface, order: 800, title: { GGStrings.Appearance.Messages.hideFormatting }, subtitle: { GGStrings.Appearance.Messages.hideFormattingInfo }, kind: .choice(.global(GGAppearanceSettings.hideFormatting), options: [
            GGMenuChoiceOption(value: GGHiddenFormatting.off.rawValue, title: { GGStrings.Appearance.Messages.hiddenNowhere }),
            GGMenuChoiceOption(value: GGHiddenFormatting.incoming.rawValue, title: { GGStrings.Appearance.Messages.hideFormattingIncoming }),
            GGMenuChoiceOption(value: GGHiddenFormatting.outgoing.rawValue, title: { GGStrings.Appearance.Messages.hideFormattingOutgoing }),
            GGMenuChoiceOption(value: GGHiddenFormatting.all.rawValue, title: { GGStrings.Appearance.Messages.hiddenEverywhere })
        ])))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.messages.tripleTapDelete", section: GGAppearanceMenu.messagesInterface, order: 1300, title: { GGStrings.Appearance.Messages.tripleTapDelete }, kind: .choice(.global(GGAppearanceSettings.tripleTapDelete), options: [
            GGMenuChoiceOption(value: GGTripleTapDelete.off.rawValue, title: { GGStrings.Appearance.Messages.tripleTapOff }),
            GGMenuChoiceOption(value: GGTripleTapDelete.local.rawValue, title: { GGStrings.Appearance.Messages.tripleTapLocal }),
            GGMenuChoiceOption(value: GGTripleTapDelete.everyone.rawValue, title: { GGStrings.Appearance.Messages.tripleTapEveryone })
        ])))

        // «Скрыть в шапке чата» (2026-10-27): the chat's top bar, four switches in one row. The
        // section keeps only its footer: the row's title says what it is.
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.messagesTopBar, screen: .tab(tab), order: 700, footer: { _ in GGStrings.Appearance.TopBar.footer }))
        let hiddenInTopBar: [(String, () -> String, GGSetting<Bool>)] = [
            ("appearance.chatTopBar.hideBackButton", { GGStrings.Appearance.TopBar.backButton }, GGAppearanceSettings.hideBackButton),
            ("appearance.chatTopBar.hideTitle", { GGStrings.Appearance.TopBar.title }, GGAppearanceSettings.hideTitlePanel),
            ("appearance.chatTopBar.hideAvatar", { GGStrings.Appearance.TopBar.avatar }, GGAppearanceSettings.hideAvatar),
            ("appearance.chatTopBar.hidePinned", { GGStrings.Appearance.TopBar.pinned }, GGAppearanceSettings.hidePinnedMessages)
        ]
        GGMenuRegistry.register(GGMenuRow(id: "appearance.chatTopBar.hidden", section: GGAppearanceMenu.messagesTopBar, order: 100, title: { GGStrings.Appearance.TopBar.hidden }, kind: .expandableList(children: GGAppearanceMenu.hiddenChildren(hiddenInTopBar, section: GGAppearanceMenu.messagesTopBar), summary: GGAppearanceMenu.hiddenSummary), searchKeywords: { [GGStrings.Appearance.TopBar.keywords] }))
    }

    /// The switches of a «Скрыть в …» row, in the given order.
    private static func hiddenChildren(_ items: [(String, () -> String, GGSetting<Bool>)], section: GGMenuSectionID) -> [GGMenuRow] {
        var result: [GGMenuRow] = []
        var order = 100
        for (id, title, setting) in items {
            result.append(GGMenuRow(id: id, section: section, order: order, title: title, kind: .toggle(.global(setting))))
            order += 100
        }
        return result
    }

    /// «скрыто: 2 из 4» on the right of a «Скрыть в …» row (nothing while none is hidden).
    static func hiddenSummary(_ count: GGMenuGroupCount) -> String {
        return GGStrings.Appearance.Messages.hiddenCount(selected: "\(count.selected)", total: "\(count.total)")
    }

    // MARK: Font tab

    /// The user's own fonts, then the system font and its designs, then the
    /// families preinstalled in iOS. Nothing bundled, no font licenses to list.
    private static func registerFont() {
        GGAppearanceMenu.registerCustomFonts()
        GGAppearanceMenu.registerBundledFonts()

        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.fontSystem, screen: .tab(GGAppearanceMenu.fontTab), order: 100, header: { GGStrings.Appearance.Font.systemHeader }, footer: { _ in
            if GGFonts.needsRestart {
                return GGStrings.Core.requiresRestartFooter
            }
            return GGStrings.Appearance.Font.systemFooter
        }))
        var order = 100
        for family in [GGFontFamily.system] + GGFonts.designFamilies {
            GGAppearanceMenu.registerFontRow(family: family, section: GGAppearanceMenu.fontSystem, order: order)
            order += 100
        }

        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.fontFamilies, screen: .tab(GGAppearanceMenu.fontTab), order: 400, header: { GGStrings.Appearance.Font.familiesHeader }, footer: { _ in GGStrings.Appearance.Font.familiesFooter }))
        order = 100
        for family in GGFonts.installedFamilies {
            GGAppearanceMenu.registerFontRow(family: family, section: GGAppearanceMenu.fontFamilies, order: order)
            order += 100
        }
    }

    private static func registerBundledFonts() {
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.fontBundled, screen: .tab(GGAppearanceMenu.fontTab), order: 250, header: { GGStrings.Appearance.Font.bundledHeader }, footer: { _ in
            if GGFonts.needsRestart && GGFonts.selectedBundledFont != nil {
                return GGStrings.Core.requiresRestartFooter
            }
            return GGStrings.Appearance.Font.bundledFooter
        }))
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.font.bundled.resetSystem",
            section: GGAppearanceMenu.fontBundled,
            order: 50,
            title: { "🔄 Вернуть стандартный шрифт (SF Pro)" },
            kind: .action({ context in
                GGAppearanceSettings.fontFamily.set(GGFontFamily.system.rawValue)
                context.presentToast("Системный шрифт SF Pro восстановлен")
            }),
            isVisible: { _ in GGAppearanceSettings.fontFamily.value != GGFontFamily.system.rawValue }
        ))
        var order = 100
        for bundledFont in GGMediaTokFonts.all {
            GGMenuRegistry.register(GGMenuRow(id: "appearance.font.bundled.\(bundledFont.slug)", section: GGAppearanceMenu.fontBundled, order: order, title: { bundledFont.displayName }, kind: .custom({ context in
                return GGAppearanceMenu.bundledFontItem(bundledFont, context: context)
            }), searchKeywords: { [bundledFont.displayName, bundledFont.category] }))
            order += 10
        }
    }

    private static func bundledFontItem(_ bundledFont: GGBundledFont, context: GGMenuContext) -> ListViewItem {
        let presentationData = context.itemListPresentationData
        let isSelected = GGFonts.selectedBundledFont == bundledFont
        let sample = GGFonts.sampleImage(bundledFont: bundledFont, color: presentationData.theme.list.itemPrimaryTextColor)
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: sample, iconSize: sample?.size, title: bundledFont.displayName, subtitle: bundledFont.category, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
            let target = isSelected ? GGFontFamily.system.rawValue : GGMediaTokFonts.settingValue(bundledFont)
            GGMenuBinding.global(GGAppearanceSettings.fontFamily).set(target, in: context)
        })
    }

    private static func registerChatFont() {
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.chatFontDisable, screen: .tab(GGAppearanceMenu.chatFontTab), order: 100, footer: { _ in GGStrings.Appearance.ChatFont.footer }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.chatFont.off", section: GGAppearanceMenu.chatFontDisable, order: 100, title: { GGStrings.Appearance.ChatFont.disableTitle }, kind: .custom({ context in
            let presentationData = context.itemListPresentationData
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: GGStrings.Appearance.ChatFont.disableTitle, style: .right, checked: GGChatTextFonts.selectedStyle == nil, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
                GGMenuBinding.global(GGAppearanceSettings.chatTextFont).set("", in: context)
            })
        })))

        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.chatFontCyrillic, screen: .tab(GGAppearanceMenu.chatFontTab), order: 200, header: { GGStrings.Appearance.ChatFont.cyrillicHeader }))
        var order = 100
        for style in GGChatTextFonts.cyrillicStyles {
            GGAppearanceMenu.registerChatFontRow(style: style, section: GGAppearanceMenu.chatFontCyrillic, order: order)
            order += 10
        }

        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.chatFontMath, screen: .tab(GGAppearanceMenu.chatFontTab), order: 300, header: { GGStrings.Appearance.ChatFont.mathHeader }))
        order = 100
        for style in GGChatTextFonts.mathStyles {
            GGAppearanceMenu.registerChatFontRow(style: style, section: GGAppearanceMenu.chatFontMath, order: order)
            order += 10
        }
    }

    private static func registerChatFontRow(style: GGChatTextStyle, section: GGMenuSectionID, order: Int) {
        GGMenuRegistry.register(GGMenuRow(id: "appearance.chatFont.\(style.id)", section: section, order: order, title: { style.name }, kind: .custom({ context in
            let presentationData = context.itemListPresentationData
            let isSelected = GGChatTextFonts.selectedStyle == style
            let preview = GGChatTextFonts.preview(for: style)
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: "\(style.name)  (.f \(style.id))", subtitle: preview, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
                let nextValue = isSelected ? "" : style.id
                GGMenuBinding.global(GGAppearanceSettings.chatTextFont).set(nextValue, in: context)
            })
        }), searchKeywords: { [style.name, style.id] }))
    }

    private static func registerFontRow(family: GGFontFamily, section: GGMenuSectionID, order: Int) {
        // «SF Mono», «New York» find the rows of the system designs too.
        let properName = GGFonts.properName(family)
        GGMenuRegistry.register(GGMenuRow(id: "appearance.font.\(family.rawValue)", section: section, order: order, title: { GGFonts.displayName(family) }, kind: .custom({ context in
            return GGAppearanceMenu.fontItem(family: family, context: context)
        }), isVisible: { _ in GGFonts.isAvailable(family) }, searchKeywords: { properName.map { [$0] } ?? [] }))
    }

    /// «Свои шрифты»: a row per added font (fixed slots: the registry is static, the list is a
    /// setting), «Добавить шрифт…» and «Удалить шрифт…».
    private static func registerCustomFonts() {
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.fontCustom, screen: .tab(GGAppearanceMenu.fontTab), order: 200, header: { GGStrings.Appearance.Font.customHeader }, footer: { _ in
            if GGFonts.needsRestart && GGFonts.selectedCustomFont != nil {
                return GGStrings.Core.requiresRestartFooter
            }
            return GGStrings.Appearance.Font.customFooter
        }))
        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.font.custom.resetSystem",
            section: GGAppearanceMenu.fontCustom,
            order: 50,
            title: { "🔄 Вернуть стандартный шрифт (SF Pro)" },
            kind: .action({ context in
                GGAppearanceSettings.fontFamily.set(GGFontFamily.system.rawValue)
                context.presentToast("Системный шрифт SF Pro восстановлен")
            }),
            isVisible: { _ in GGAppearanceSettings.fontFamily.value != GGFontFamily.system.rawValue }
        ))
        for index in 0 ..< GGCustomFonts.maximumCount {
            let font: () -> GGCustomFont? = {
                let fonts = GGCustomFonts.fonts
                return index < fonts.count ? fonts[index] : nil
            }
            GGMenuRegistry.register(GGMenuRow(id: "appearance.font.custom.\(index)", section: GGAppearanceMenu.fontCustom, order: 100 + index * 10, title: { font()?.familyName ?? "" }, kind: .custom({ context in
                guard let customFont = font() else {
                    return GGAppearanceMenu.fontItem(family: .system, context: context)
                }
                return GGAppearanceMenu.customFontItem(customFont, context: context)
            }), isVisible: { _ in font() != nil }))
        }
        GGMenuRegistry.register(GGMenuRow(id: "appearance.font.add", section: GGAppearanceMenu.fontCustom, order: 2000, title: { GGStrings.Appearance.Font.add }, kind: .action({ context in
            GGPickers.pickFont(context: context)
        }), searchKeywords: { [GGStrings.Appearance.Font.keywords] }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.font.createTtf", section: GGAppearanceMenu.fontCustom, order: 2050, title: { GGStrings.Appearance.Font.createTtf }, subtitle: { GGStrings.Appearance.Font.createTtfInfo }, kind: .action({ context in
            GGMediaTokTtfCreator.present(context: context)
        }), searchKeywords: { [GGStrings.Appearance.Font.keywords] }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.font.remove", section: GGAppearanceMenu.fontCustom, order: 2100, title: { GGStrings.Appearance.Font.remove }, kind: .action({ context in
            GGAppearanceMenu.presentRemoveFont(context: context)
        }), isVisible: { _ in !GGCustomFonts.fonts.isEmpty }, isDestructive: true))
    }

    private static func customFontItem(_ customFont: GGCustomFont, context: GGMenuContext) -> ListViewItem {
        let presentationData = context.itemListPresentationData
        let isSelected = GGFonts.selectedCustomFont == customFont
        let sample = GGFonts.sampleImage(customFont: customFont, color: presentationData.theme.list.itemPrimaryTextColor)
        let detail: String? = GGFonts.hasCyrillic(customFont) ? nil : GGStrings.Appearance.Font.noCyrillic
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: sample, iconSize: sample?.size, title: customFont.familyName, subtitle: detail, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
            let target = isSelected ? GGFontFamily.system.rawValue : GGCustomFonts.settingValue(customFont)
            GGMenuBinding.global(GGAppearanceSettings.fontFamily).set(target, in: context)
        })
    }

    private static func presentRemoveFont(context: GGMenuContext) {
        let sheet = UIAlertController(title: GGStrings.Appearance.Font.removeTitle, message: nil, preferredStyle: .actionSheet)
        for customFont in GGCustomFonts.fonts {
            sheet.addAction(UIAlertAction(title: customFont.familyName, style: .destructive, handler: { _ in
                GGCustomFonts.remove(customFont)
            }))
        }
        sheet.addAction(UIAlertAction(title: context.presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
        context.presentNative(sheet)
    }

    private static func fontItem(family: GGFontFamily, context: GGMenuContext) -> ListViewItem {
        let presentationData = context.itemListPresentationData
        let isSelected = GGFonts.selectedCustomFont == nil && GGFonts.selectedBundledFont == nil && GGFonts.selectedFamily == family
        let sample = GGFonts.sampleImage(family: family, color: presentationData.theme.list.itemPrimaryTextColor)
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: sample, iconSize: sample?.size, title: GGFonts.displayName(family), subtitle: GGFonts.detail(family), style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
            let target = (isSelected && family != .system) ? GGFontFamily.system.rawValue : family.rawValue
            GGMenuBinding.global(GGAppearanceSettings.fontFamily).set(target, in: context)
        })
    }

    // MARK: «Тема и фон»

    private static func registerTheme() {
        let tab = GGMenuTabID.appearanceThemeBackground

        GGMenuRegistry.register(GGMenuRow(
            id: "appearance.theme.preview",
            section: .preview(of: tab),
            order: 100,
            title: { "" },
            // Live: the theme follows its sliders while dragged; the animated background, the snow
            // and the edge bands are shown as in a chat (U6, U7).
            kind: .preview(.miniChat(GGAppearancePreview.configuration(scope: "appearance.theme", overlays: true, content: { _ in
                return GGAppearancePreview.sampleContent()
            })))
        ))

        let main = GGMenuSectionID.main(of: tab)
        GGMenuRegistry.register(GGMenuRow(id: "appearance.theme.amoled", section: main, order: 100, title: { GGStrings.Appearance.Theme.amoled }, subtitle: { GGStrings.Appearance.Theme.amoledInfo }, kind: .toggle(.global(GGAppearanceSettings.amoled)), searchKeywords: { [GGStrings.Appearance.Theme.amoledKeywords] }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.theme.amoledKeyboard", section: main, order: 200, title: { GGStrings.Appearance.Theme.amoledKeyboard }, subtitle: { GGStrings.Appearance.Theme.amoledKeyboardInfo }, kind: .toggle(.global(GGAppearanceSettings.amoledKeyboard))))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.theme.hideSeparators", section: main, order: 300, title: { GGStrings.Appearance.Theme.hideSeparators }, kind: .toggle(.global(GGAppearanceSettings.hideSeparators))))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.theme.nameSaturation", section: main, order: 400, title: { GGStrings.Appearance.Theme.nameSaturation }, subtitle: { GGStrings.Appearance.Theme.nameSaturationInfo }, kind: .slider(.global(GGAppearanceSettings.nameColorSaturation), range: 0.0 ... 100.0, step: 5.0, format: GGAppearanceMenu.percent)))

        // «Затемнение краёв» (one group since 2026-10-27): the kind of band, then only what it uses.
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.themeEdges, screen: .tab(tab), order: 400, header: { GGStrings.Appearance.Edges.header }, footer: { _ in GGStrings.Appearance.Edges.footer }))
        let edgeStyle: () -> GGEdgeStyle = { GGEdgeStyle(rawValue: GGAppearanceSettings.edgeStyle.value) ?? .off }
        let edgesOn: (GGMenuContext) -> Bool = { _ in edgeStyle() != .off }
        GGMenuRegistry.register(GGMenuRow(id: "appearance.edges.style", section: GGAppearanceMenu.themeEdges, order: 100, title: { GGStrings.Appearance.Edges.header }, kind: .discreteChoice(.global(GGAppearanceSettings.edgeStyle), options: [
            GGMenuChoiceOption(value: GGEdgeStyle.off.rawValue, title: { GGStrings.Appearance.Edges.styleOff }),
            GGMenuChoiceOption(value: GGEdgeStyle.blur.rawValue, title: { GGStrings.Appearance.Edges.styleBlur }),
            GGMenuChoiceOption(value: GGEdgeStyle.gradient.rawValue, title: { GGStrings.Appearance.Edges.styleGradient })
        ]), searchKeywords: { [GGStrings.Appearance.Edges.keywords] }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.edges.intensity", section: GGAppearanceMenu.themeEdges, order: 200, title: { GGStrings.Appearance.Edges.intensity }, kind: .slider(.global(GGAppearanceSettings.edgeIntensity), range: 0.0 ... 100.0, step: 5.0, format: GGAppearanceMenu.percent), isVisible: edgesOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.edges.size", section: GGAppearanceMenu.themeEdges, order: 300, title: { GGStrings.Appearance.Edges.size }, kind: .slider(.global(GGAppearanceSettings.edgeSize), range: GGEdgeStyle.sizeRange, step: 4.0, format: GGAppearanceMenu.points), isVisible: edgesOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.edges.color", section: GGAppearanceMenu.themeEdges, order: 400, title: { GGStrings.Appearance.Edges.color }, kind: .action({ context in
            // The picker starts where the old rows did: the bar's color for the blur, the accent for the gradient.
            let fallback = edgeStyle() == .gradient ? context.presentationData.theme.list.itemAccentColor : context.presentationData.theme.rootController.navigationBar.opaqueBackgroundColor
            GGColorPicker.present(context: context, setting: GGAppearanceSettings.edgeColor, fallback: fallback)
        }), isVisible: edgesOn, label: { _ in GGAppearanceMenu.colorLabel(GGAppearanceSettings.edgeColor) }))
        // Back to «Automatic» (the bar's color, following the theme) once a color was chosen.
        GGMenuRegistry.register(GGMenuRow(id: "appearance.edges.resetColor", section: GGAppearanceMenu.themeEdges, order: 450, title: { GGStrings.Appearance.Edges.resetColor }, kind: .action({ _ in
            GGAppearanceSettings.edgeColor.reset()
        }), isVisible: { context in edgesOn(context) && !GGAppearanceSettings.edgeColor.value.isEmpty }, isDestructive: true))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.edges.hideInChatList", section: GGAppearanceMenu.themeEdges, order: 500, title: { GGStrings.Appearance.Edges.hideInChatList }, kind: .toggle(.global(GGAppearanceSettings.edgeHideInChatList)), isVisible: { _ in edgeStyle() == .gradient }))

        // Animated chat background.
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.themeBackground, screen: .tab(tab), order: 500, header: { GGStrings.Appearance.Background.chatHeader }, footer: { _ in GGStrings.Appearance.Background.footer }))
        GGAppearanceMenu.registerBackgroundRows(kind: .chat, section: GGAppearanceMenu.themeBackground, idPrefix: "appearance.chatBackground")

        // Snowfall.
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.themeSnow, screen: .tab(tab), order: 600, header: { GGStrings.Appearance.Snow.header }, footer: { _ in
            // Says so when the system is what stops the snow right now (the switch alone looked broken).
            if GGAppearanceSettings.snow.value && GGSystemState.current {
                return GGStrings.Appearance.Snow.footer + "\n\n" + GGStrings.Appearance.Snow.pausedNow
            }
            return GGStrings.Appearance.Snow.footer
        }))
        let snowOn: (GGMenuContext) -> Bool = { _ in GGAppearanceSettings.snow.value }
        GGMenuRegistry.register(GGMenuRow(id: "appearance.snow.enabled", section: GGAppearanceMenu.themeSnow, order: 100, title: { GGStrings.Appearance.Snow.enabled }, kind: .toggle(.global(GGAppearanceSettings.snow)), searchKeywords: { [GGStrings.Appearance.Snow.keywords] }))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.snow.style", section: GGAppearanceMenu.themeSnow, order: 200, title: { GGStrings.Appearance.Snow.style }, kind: .choice(.global(GGAppearanceSettings.snowStyle), options: [
            GGMenuChoiceOption(value: GGSnowStyle.snow.rawValue, title: { GGStrings.Appearance.Snow.styleSnow }),
            GGMenuChoiceOption(value: GGSnowStyle.lightning.rawValue, title: { GGStrings.Appearance.Snow.styleLightning })
        ]), isVisible: snowOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.snow.intensity", section: GGAppearanceMenu.themeSnow, order: 300, title: { GGStrings.Appearance.Snow.intensity }, kind: .slider(.global(GGAppearanceSettings.snowIntensity), range: 10.0 ... 100.0, step: 5.0, format: GGAppearanceMenu.percent), isVisible: snowOn))
        GGMenuRegistry.register(GGMenuRow(id: "appearance.snow.hideInChats", section: GGAppearanceMenu.themeSnow, order: 400, title: { GGStrings.Appearance.Snow.hideInChats }, kind: .toggle(.global(GGAppearanceSettings.snowHideInChats)), isVisible: snowOn))
    }

    /// Rows of an animated background: on/off (once a file exists), pick, opacity, delete.
    private static func registerBackgroundRows(kind: GGAnimatedBackgroundKind, section: GGMenuSectionID, idPrefix: String) {
        let hasFile: (GGMenuContext) -> Bool = { _ in kind.versionSetting.value != 0 }
        GGMenuRegistry.register(GGMenuRow(id: "\(idPrefix).enabled", section: section, order: 100, title: { GGStrings.Appearance.Background.enabled }, kind: .toggle(.global(kind.enabledSetting)), isVisible: hasFile))
        GGMenuRegistry.register(GGMenuRow(id: "\(idPrefix).pick", section: section, order: 200, title: { GGStrings.Appearance.Background.pick }, subtitle: { GGStrings.Appearance.Background.pickInfo }, kind: .action({ context in
            GGPickers.pickBackground(context: context, kind: kind)
        }), searchKeywords: { [GGStrings.Appearance.Background.keywords] }, label: { _ in
            return kind.versionSetting.value != 0 ? GGStrings.Appearance.Background.isSet : GGStrings.Appearance.Background.notSet
        }))
        GGMenuRegistry.register(GGMenuRow(id: "\(idPrefix).opacity", section: section, order: 300, title: { GGStrings.Appearance.Background.opacity }, kind: .slider(.global(kind.opacitySetting), range: 5.0 ... 100.0, step: 5.0, format: GGAppearanceMenu.percent), isVisible: hasFile))
        GGMenuRegistry.register(GGMenuRow(id: "\(idPrefix).remove", section: section, order: 400, title: { GGStrings.Appearance.Background.remove }, kind: .action({ _ in
            GGAnimatedBackgrounds.remove(kind)
        }), isVisible: hasFile, isDestructive: true))
    }

    // MARK: «Профиль»

    private static func registerProfile() {
        let tab = GGMenuTabID.appearanceProfileSettings
        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.profileInfo, screen: .tab(tab), order: 300, header: { GGStrings.Appearance.Profile.header }, footer: { _ in GGStrings.Appearance.Profile.footer }))
        let rows: [(String, () -> String, (() -> String)?, GGSetting<Bool>)] = [
            ("appearance.profile.showId", { GGStrings.Appearance.Profile.showId }, nil, GGAppearanceSettings.profileShowId),
            ("appearance.profile.showDataCenter", { GGStrings.Appearance.Profile.showDataCenter }, { GGStrings.Appearance.Profile.showDataCenterInfo }, GGAppearanceSettings.profileShowDataCenter),
            ("appearance.profile.showDates", { GGStrings.Appearance.Profile.showDates }, { GGStrings.Appearance.Profile.showDatesInfo }, GGAppearanceSettings.profileShowDates),
            ("appearance.profile.hideDescription", { GGStrings.Appearance.Profile.hideDescription }, nil, GGAppearanceSettings.profileHideDescription),
            ("appearance.profile.hideShareButton", { GGStrings.Appearance.Profile.hideShareButton }, nil, GGAppearanceSettings.profileHideShareButton),
            ("appearance.profile.hideStarRating", { GGStrings.Appearance.Profile.hideStarRating }, nil, GGAppearanceSettings.profileHideStarRating)
        ]
        var order = 100
        for (id, title, subtitle, setting) in rows {
            GGMenuRegistry.register(GGMenuRow(id: id, section: GGAppearanceMenu.profileInfo, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting))))
            order += 100
        }

        GGMenuRegistry.register(section: GGMenuSectionDescriptor(id: GGAppearanceMenu.profileBackground, screen: .tab(tab), order: 400, header: { GGStrings.Appearance.Background.profileHeader }, footer: { _ in GGStrings.Appearance.Background.profileFooter }))
        GGAppearanceMenu.registerBackgroundRows(kind: .profile, section: GGAppearanceMenu.profileBackground, idPrefix: "appearance.profileBackground")
    }
}
