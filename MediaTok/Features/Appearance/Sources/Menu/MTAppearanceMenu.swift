import Foundation
import UIKit
import Display
import ItemListUI
import TelegramPresentationData
import MTCore
import MTSettingsUI
import MTAppearanceSettings

/// The appearance rows of the MediaTok menu: tabs «Сообщения», «Тема и фон» and the
/// «Профиль» part of «Профиль и Настройки». Every setting has exactly one row; titles are computed
/// at display time; sliders write once, on release (the preview follows the finger).
enum MTAppearanceMenu {
    // Sections of «Сообщения».
    static let messagesBubbles = MTMenuSectionID("appearance.messages.bubbles")
    static let messagesChecks = MTMenuSectionID("appearance.messages.checkmarks")
    static let messagesStickers = MTMenuSectionID("appearance.messages.stickers")
    static let messagesInterface = MTMenuSectionID("appearance.messages.interface")
    static let messagesTopBar = MTMenuSectionID("appearance.messages.topBar")
    // Sections of «Тема и фон».
    static let themeEdges = MTMenuSectionID("appearance.themeBackground.edges")
    static let themeBackground = MTMenuSectionID("appearance.themeBackground.chatBackground")
    static let themeSnow = MTMenuSectionID("appearance.themeBackground.snow")
    // Sections of «Профиль и Настройки» (the «Настройки» part belongs to the interface feature).
    static let profileInfo = MTMenuSectionID("appearance.profileSettings.profile")
    static let profileBackground = MTMenuSectionID("appearance.profileSettings.profileBackground")
    // The font tab.
    static let fontTab = MTMenuTabID("appearance.font")
    static let fontCustom = MTMenuSectionID("appearance.font.custom")
    static let fontBundled = MTMenuSectionID("appearance.font.bundled")
    static let fontSystem = MTMenuSectionID("appearance.font.systemDesigns")
    static let fontFamilies = MTMenuSectionID("appearance.font.families")
    // The stylish outgoing chat text font tab.
    static let chatFontTab = MTMenuTabID("appearance.chatFont")
    static let chatFontDisable = MTMenuSectionID("appearance.chatFont.disable")
    static let chatFontCyrillic = MTMenuSectionID("appearance.chatFont.cyrillic")
    static let chatFontMath = MTMenuSectionID("appearance.chatFont.math")

    static func register() {
        MTAppearanceMenu.registerMessages()
        MTAppearanceMenu.registerFont()
        MTAppearanceMenu.registerChatFont()
        MTAppearanceMenu.registerTheme()
        MTAppearanceMenu.registerProfile()
    }

    // MARK: Formats

    static func percent(_ value: Double) -> String {
        return MTStrings.Appearance.Common.percent(value: "\(Int(value.rounded()))")
    }

    static func points(_ value: Double) -> String {
        return MTStrings.Appearance.Common.points(value: "\(Int(value.rounded()))")
    }

    static func colorLabel(_ setting: MTSetting<String>) -> String {
        if let rgb = mtAppearanceParseColor(setting.value) {
            return "#" + mtAppearanceColorString(rgb)
        }
        return MTStrings.Appearance.Common.automatic
    }

    // MARK: «Сообщения»

    private static func registerMessages() {
        let tab = MTMenuTabID.appearanceMessages

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.messages.preview",
            section: .preview(of: tab),
            order: 100,
            title: { "" },
            // Live: bubbles follow the sliders of the bubble editor while dragged (U6); the top bar
            // follows «Скрыть в шапке чата» (U7).
            kind: .preview(.miniChat(MTAppearancePreview.configuration(scope: "appearance.messages", overlays: false, content: { _ in
                var content = MTAppearancePreview.sampleContent()
                if content.messages.count > 1 {
                    // Shows the «edited» label, the time and the checkmarks the options change.
                    content.messages[1].isEdited = true
                }
                return content
            })))
        ))

        // Font: its own tab with samples.
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(
            id: MTAppearanceMenu.fontTab,
            parent: .tab(tab),
            title: { MTStrings.Appearance.Font.title },
            topView: MTMenuTopView(content: .emoji("🔤"), text: { MTStrings.Appearance.Font.info }),
            searchKeywords: { [MTStrings.Appearance.Font.keywords] }
        ), linkIn: .main(of: tab), order: 100, subtitle: { MTStrings.Appearance.Font.subtitle }, icon: .bundle("Chat/Context Menu/FormatText"), label: { _ in
            return MTFonts.selectedDisplayName
        })

        // Stylish outgoing chat text fonts (32 Unicode + Cyrillic styles visible to everyone).
        MTMenuRegistry.register(tab: MTMenuTabDescriptor(
            id: MTAppearanceMenu.chatFontTab,
            parent: .tab(tab),
            title: { MTStrings.Appearance.ChatFont.title },
            topView: MTMenuTopView(content: .emoji("✨"), text: { MTStrings.Appearance.ChatFont.info }),
            searchKeywords: { [MTStrings.Appearance.ChatFont.keywords] }
        ), linkIn: .main(of: tab), order: 150, subtitle: { MTStrings.Appearance.ChatFont.subtitle }, icon: .bundle("Chat/Context Menu/FormatText"), label: { _ in
            return MTChatTextFonts.selectedDisplayName
        })

        // Dedicated top quick-access MediaTok section on Root Settings screen.
        let rootMediaTokSection = MTMenuSectionID("root.mediatokStudio")
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: rootMediaTokSection,
            screen: .root,
            order: 100,
            header: { "ЭКСКЛЮЗИВЫ MEDIATOK" }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.spotlight",
            section: rootMediaTokSection,
            order: 50,
            title: { "Палитра команд (Spotlight)" },
            subtitle: { "Быстрый поиск всех фич MediaTok, LRC, сети и ГС" },
            icon: .system("magnifyingglass"),
            kind: .action({ context in
                MTMediaTokWave7Tools.presentSpotlightPalette(accountContext: context.context, menuContext: context)
            }),
            searchKeywords: { ["spotlight", "cmd", "поиск", "палитра", "команды", "490"] },
            label: { _ in "CMD" }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.discordProfile",
            section: rootMediaTokSection,
            order: 100,
            title: { MTStrings.Appearance.DiscordProfile.title },
            subtitle: { MTStrings.Appearance.DiscordProfile.subtitle },
            icon: .system("sparkles"),
            kind: .action({ context in
                MTMediaTokDiscordProfile.presentOwnEditor(context: context)
            }),
            label: { context in
                let p = MTDiscordProfileStore.shared.profile(for: context.context.account.peerId)
                return (p != nil && !(p?.isEmpty ?? true)) ? "ON" : "4K"
            }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.tiktokFeed",
            section: rootMediaTokSection,
            order: 200,
            title: { "TikTok-лента каналов" },
            subtitle: { "Вертикальная свайп-лента видео и кружков из каналов" },
            icon: .system("play.rectangle.fill"),
            kind: .action({ context in
                let feed = MTTikTokFeedViewController(context: context.context, navigationController: context.navigationController)
                context.presentNative(feed)
            }),
            label: { _ in "REELS" }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.stickerVault",
            section: rootMediaTokSection,
            order: 300,
            title: { "/stickers — База 10к стикеров + ИИ" },
            subtitle: { "Команды /s и /s!, OCR и загрузка папок с ПК по Wi-Fi" },
            icon: .system("face.smiling"),
            kind: .action({ context in
                MTMediaTokStickerVault.presentManagerFromMenu(context: context)
            }),
            label: { _ in
                let c = MTStickerVaultStore.shared.count
                return c > 0 ? "\(c)" : "10K"
            }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.liquidUi",
            section: rootMediaTokSection,
            order: 400,
            title: { "Liquid Glass / Zero-Bloat / 4K 60fps" },
            subtitle: { "Стекло iOS 27, компактный чат, стиль галочек, видео 4K" },
            icon: .system("cube.transparent"),
            kind: .action({ context in
                MTMediaTokLiquidUI.presentStudio(context: context)
            }),
            label: { _ in
                return MTMediaTokLiquidUI.isVideo4k60Enabled ? "4K60" : "iOS27"
            }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.menuIcons",
            section: rootMediaTokSection,
            order: 425,
            title: { "Иконки разделов и Премиум-эмодзи" },
            subtitle: { "Свои Telegram Premium эмодзи, SF Symbols или фото на любой раздел" },
            icon: .system("paintpalette"),
            kind: .action({ context in
                mtPresentMenuIconStudio(context: context)
            }),
            searchKeywords: { ["иконки", "эмодзи", "премиум", "кастом", "разделы", "icons", "emoji"] },
            label: { _ in
                let n = MTCustomMenuIconStore.shared.customCount
                return n > 0 ? "\(n)" : "Custom"
            }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.premiumEmoji",
            section: rootMediaTokSection,
            order: 450,
            title: { "Премиум Эмодзи" },
            subtitle: { "Все паки в клавиатуре, отправка в чатах без подписки, эмодзи-статус" },
            icon: .system("star.circle"),
            kind: .action({ context in
                MTMediaTokWave5Tools.presentPremiumEmojiSheet(context: context)
            }),
            searchKeywords: { ["emoji", "эмодзи", "премиум", "premium", "статус"] },
            label: { _ in MTMediaTokWave5Tools.isPremiumEmojiEnabled ? "ВКЛ" : "ВЫКЛ" }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.wave8Studio",
            section: rootMediaTokSection,
            order: 470,
            title: { "Примерочная, QR, Размытие лиц, PDF и Погода" },
            subtitle: { "Sandbox профиля, градиент-QR, стикеры в ZIP, поиск фото, PDF-подпись" },
            icon: .system("wand.and.stars"),
            kind: .action({ context in
                MTMediaTokWave8Tools.presentWave2Studio(context: context.context)
            }),
            searchKeywords: { ["sandbox", "примерочная", "qr", "zip", "pdf", "погода", "лица", "батарея", "499", "466", "478", "480", "460", "461", "462", "497", "486"] },
            label: { _ in "Tools" }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.wave9Network",
            section: rootMediaTokSection,
            order: 472,
            title: { "Сеть, Спидтест DC, VPN-слот и Аккаунты" },
            subtitle: { "DC1–DC5 пинг, прокси на аккаунт, клон настроек, Sync v2, DoH, SHA-256" },
            icon: .system("network"),
            kind: .action({ context in
                MTMediaTokWave9Tools.presentWave3NetworkHub(context: context.context)
            }),
            searchKeywords: { ["dc", "speedtest", "vpn", "proxy", "sync", "doh", "sha256", "аккаунты", "сеть", "401", "406", "422", "423", "495"] },
            label: { context in "DC\(context.context.account.network.datacenterId)" }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.wave7Tools",
            section: rootMediaTokSection,
            order: 475,
            title: { "Текст песни (LRC), Сеть, ГС и Safe Mode" },
            subtitle: { "Караоке lrclib.net, Force Reconnect, подтверждение ГС и 99:59" },
            icon: .system("waveform.badge.magnifyingglass"),
            kind: .action({ context in
                MTMediaTokWave7Tools.presentWave7QuickHub(context: context)
            }),
            searchKeywords: { ["lyrics", "lrc", "reconnect", "voice", "гс", "safe", "whatsnew", "371", "416", "493"] },
            label: { _ in "LRC" }
        ))
        MTMenuRegistry.register(MTMenuRow(
            id: "root.mediatok.allFeatures",
            section: rootMediaTokSection,
            order: 500,
            title: { "Все фичи MediaTok Studio" },
            subtitle: { "Spotlight, LRC, ГС, языки, E2E AES-256, Anti-Screamer, AdBlock, Call Guard" },
            icon: .system("square.grid.2x2"),
            kind: .action({ context in
                context.open(tab: .appearanceMessages)
            }),
            label: { _ in "Все" }
        ))

        // Also expose Section Icon & Premium Emoji customizer in Appearance -> Icons.
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.icons.sectionIcons",
            section: .main(of: .appearanceIcons),
            order: 50,
            title: { "Иконки разделов и Премиум-эмодзи" },
            subtitle: { "Выбери Telegram Premium эмодзи, SF Symbol или картинку для каждого раздела" },
            icon: .system("paintpalette"),
            kind: .action({ context in
                mtPresentMenuIconStudio(context: context)
            }),
            searchKeywords: { ["иконки", "эмодзи", "премиум", "разделы", "кастом"] },
            label: { _ in
                let n = MTCustomMenuIconStore.shared.customCount
                return n > 0 ? "\(n)" : "Custom"
            }
        ))

        // Dedicated MediaTok Studio section in Appearance -> Messages (right below live preview).
        let mediaTokSection = MTMenuSectionID("appearance.messages.mediatokStudio")
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(
            id: mediaTokSection,
            screen: .tab(tab),
            order: 150,
            header: { "Эксклюзивы MediaTok Studio" }
        ))

        // Premium Emoji without subscription (keyboard unlock, zero-width chat codec, profile emoji status).
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.premiumEmoji",
            section: mediaTokSection,
            order: 50,
            title: { "Премиум Эмодзи" },
            subtitle: { "Разблокировка всех паков в клавиатуре, отправка в чатах и эмодзи-статус" },
            icon: .system("star.circle"),
            kind: .action({ context in
                MTMediaTokWave5Tools.presentPremiumEmojiSheet(context: context)
            }),
            searchKeywords: { ["emoji", "эмодзи", "премиум", "premium", "статус"] },
            label: { _ in MTMediaTokWave5Tools.isPremiumEmojiEnabled ? "ВКЛ" : "ВЫКЛ" }
        ))

        // Language Studio: 66 public Telegram language packs + Full Language Editor (all strings, LIVE).
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.langs.studio",
            section: mediaTokSection,
            order: 100,
            title: { MTStrings.Appearance.LangStudio.title },
            subtitle: { MTStrings.Appearance.LangStudio.subtitle },
            kind: .action({ context in
                MTMediaTokLangs.presentStudio(context: context)
            }),
            searchKeywords: { [MTStrings.Appearance.LangStudio.keywords] },
            label: { _ in
                let n = MTMediaTokLangs.overrideCount
                return n > 0 ? "\(n)" : "66+"
            }
        ))

        // Discord-style Profile Studio (4K banner + animated effects + avatar frame + Steam & Roblox + global sync).
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.discordProfile",
            section: mediaTokSection,
            order: 200,
            title: { MTStrings.Appearance.DiscordProfile.title },
            subtitle: { MTStrings.Appearance.DiscordProfile.subtitle },
            kind: .action({ context in
                MTMediaTokDiscordProfile.presentOwnEditor(context: context)
            }),
            searchKeywords: { [MTStrings.Appearance.DiscordProfile.keywords] },
            label: { context in
                let p = MTDiscordProfileStore.shared.profile(for: context.context.account.peerId)
                return (p != nil && !(p?.isEmpty ?? true)) ? "ON" : "4K"
            }
        ))

        // Per-chat AES-256-GCM E2E Encryption manager.
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.e2e",
            section: mediaTokSection,
            order: 300,
            title: { MTStrings.Appearance.E2e.title },
            subtitle: { MTStrings.Appearance.E2e.subtitle },
            kind: .action({ context in
                MTMediaTokE2E.presentManager(context: context)
            }),
            searchKeywords: { [MTStrings.Appearance.E2e.keywords] },
            label: { _ in
                let n = MTMediaTokE2E.activeCount
                return n > 0 ? "\(n)" : "AES"
            }
        ))

        // Anti-Screamer, Loud Bad Sounds & Moan Filter.
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.audioGuard",
            section: mediaTokSection,
            order: 400,
            title: { MTStrings.Appearance.AudioGuard.title },
            subtitle: { MTStrings.Appearance.AudioGuard.subtitle },
            kind: .action({ context in
                MTMediaTokAudioGuard.presentSettings(context: context)
            }),
            searchKeywords: { [MTStrings.Appearance.AudioGuard.keywords] },
            label: { _ in
                return MTMediaTokAudioGuard.modeLabel
            }
        ))

        // Quick cheat-sheet & Wave 4 tools (.q quote stickers, .stats, AFK, OCR, Cutout stickers, Wallpaper sound).
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.commands",
            section: mediaTokSection,
            order: 500,
            title: { MTStrings.Appearance.Commands.title },
            subtitle: { MTStrings.Appearance.Commands.subtitle },
            kind: .action({ context in
                MTMediaTokWave4Tools.presentHub(context: context)
            }),
            searchKeywords: { [MTStrings.Appearance.Commands.keywords] }
        ))

        // Wave 5: /stickers 10K AI Vault + PC Wi-Fi Uploader
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.stickerVault",
            section: mediaTokSection,
            order: 600,
            title: { "/stickers — База 10к стикеров + ИИ-поиск" },
            subtitle: { "Команды /s и /s!, OCR и Vision AI, загрузка папок с ПК по Wi-Fi" },
            icon: .system("face.smiling"),
            kind: .action({ context in
                MTMediaTokStickerVault.presentManagerFromMenu(context: context)
            }),
            searchKeywords: { ["stickers", "стикеры", "поиск", "ии", "ai", "wifi"] },
            label: { _ in
                let c = MTStickerVaultStore.shared.count
                return c > 0 ? "\(c)" : "10K"
            }
        ))

        // Wave 5: Liquid Glass iOS 27 / Zero-Bloat / Compact / Checkmarks / 4K 60fps
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.liquidUi",
            section: mediaTokSection,
            order: 700,
            title: { "Liquid Glass / Zero-Bloat / Галочки / 4K 60fps" },
            subtitle: { "Стекло iOS 27, убрать лишнее, компактный чат, стиль галочек, видео 4K" },
            icon: .system("cube.transparent"),
            kind: .action({ context in
                MTMediaTokLiquidUI.presentStudio(context: context)
            }),
            searchKeywords: { ["glass", "liquid", "bloat", "4k", "60fps", "галочки", "стекло", "видео"] },
            label: { _ in
                return MTMediaTokLiquidUI.isVideo4k60Enabled ? "4K60" : "iOS27"
            }
        ))

        // Wave 5: Streaks / Clipboard / Guards / Metadata Stripper / Games / Updater
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.wave5Hub",
            section: mediaTokSection,
            order: 800,
            title: { "Огоньки, Буфер, Защита, Игры и Обновления" },
            subtitle: { "Серии чатов, история буфера обмена, EXIF/PDF, подтверждения, 2048, ESign" },
            icon: .system("flame"),
            kind: .action({ context in
                MTMediaTokWave5Tools.presentHub(context: context)
            }),
            searchKeywords: { ["огоньки", "streak", "буфер", "clipboard", "games", "игры", "esign", "обновления"] },
            label: { _ in
                let top = MTMediaTokStreaks.topStreaks(limit: 1).first?.record.currentStreak ?? 0
                return top > 0 ? "\(top)d" : "W5"
            }
        ))

        // Wave 6: TikTok / Reels Channel Media Feed (#187)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.tiktokFeed",
            section: mediaTokSection,
            order: 900,
            title: { "TikTok-лента каналов" },
            subtitle: { "Вертикальная свайп-лента видео и видеосообщений со всех каналов" },
            icon: .system("play.rectangle"),
            kind: .action({ context in
                let feed = MTTikTokFeedViewController(context: context.context, navigationController: context.navigationController)
                context.presentNative(feed)
            }),
            searchKeywords: { ["tiktok", "тикток", "лента", "видео", "reels", "shorts"] },
            label: { _ in "REELS" }
        ))

        // Wave 6: MediaTok Achievements System (#168)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.achievements",
            section: mediaTokSection,
            order: 1000,
            title: { "Достижения MediaTok" },
            subtitle: { "Ранги, ночной дозор, стрикер, криптограф, шеринг карточки" },
            icon: .system("rosette"),
            kind: .action({ context in
                context.push(MTMediaTokWave6Tools.makeAchievementsController(context: context.context))
            }),
            searchKeywords: { ["ачивки", "достижения", "ранг", "награды", "achievements"] },
            label: { _ in
                let c = MTMediaTokWave6Tools.getUnlockedAchievements().count
                return "\(c)/12"
            }
        ))

        // Wave 6: Bottom Bar / Tab Bar Editor (#110)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.bottomBar",
            section: mediaTokSection,
            order: 1100,
            title: { "Редактор нижнего бара" },
            subtitle: { "Пресеты таббара, скрыть звонки/контакты, парящий бар (+8pt)" },
            icon: .system("dock.rectangle"),
            kind: .action({ context in
                context.push(MTMediaTokWave6Tools.makeBottomBarStudioController(context: context.context))
            }),
            searchKeywords: { ["бар", "таббар", "низ", "панель", "110", "минимал"] },
            label: { _ in "Bar" }
        ))

        // Wave 6: Call Confirm Guard (#58)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.callConfirm",
            section: mediaTokSection,
            order: 1200,
            title: { "Защита от случайных звонков (Call Guard)" },
            subtitle: { "Подтверждение перед стартом аудио- и видеозвонков из чатов и профилей" },
            icon: .system("phone.badge.checkmark"),
            kind: .action({ context in
                MTMediaTokWave6Tools.isCallConfirmEnabled.toggle()
                MTMediaTokLiquidUI.applyMediaTokGlobalSettings(["ghostMode.confirmCalls": false])
                let st = MTMediaTokWave6Tools.isCallConfirmEnabled ? "ВКЛ" : "ВЫКЛ"
                context.presentToast("Защита звонков: \(st)")
            }),
            searchKeywords: { ["звонки", "call", "confirm", "случайный", "guard"] },
            label: { _ in MTMediaTokWave6Tools.isCallConfirmEnabled ? "ВКЛ" : "ВЫКЛ" }
        ))

        // Wave 6: Channel Ad-Blocker (#188)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.adBlock",
            section: mediaTokSection,
            order: 1300,
            title: { "Блокировщик рекламы в каналах" },
            subtitle: { "Авто-заглушение и сворачивание рекламных постов (erid, #реклама, ООО)" },
            icon: .system("hand.raised.slash"),
            kind: .action({ context in
                MTMediaTokWave6Tools.isAdBlockEnabled.toggle()
                let st = MTMediaTokWave6Tools.isAdBlockEnabled ? "ВКЛ" : "ВЫКЛ"
                context.presentToast("Анти-реклама каналов: \(st)")
            }),
            searchKeywords: { ["реклама", "adblock", "erid", "спам", "каналы"] },
            label: { _ in MTMediaTokWave6Tools.isAdBlockEnabled ? "ВКЛ" : "ВЫКЛ" }
        ))

        // Wave 6: MediaTok Wrapped (#169), Self-Diagnostics (#199) & Privacy Screen (#48)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.wrappedDiag",
            section: mediaTokSection,
            order: 1400,
            title: { "MediaTok Wrapped, Диагностика и Приватность" },
            subtitle: { "Итоги статистики, статус модулей, сниппеты, граффити, .ai/.wiki/.scratch/.qr" },
            icon: .system("waveform.path.ecg"),
            kind: .action({ context in
                MTMediaTokWave6Tools.presentWrappedAndDiagnostics(context: context)
            }),
            searchKeywords: { ["wrapped", "итоги", "диагностика", "privacy", "плеча", "статистика"] },
            label: { _ in "W6" }
        ))

        // Wave 7: Spotlight (#490), LRC Lyrics (#371), Force Reconnect (#416), Voice Tools (#379/#377), What's New/Bug/Safe Mode (#491/#492/#493)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.spotlight",
            section: mediaTokSection,
            order: 1500,
            title: { "Палитра команд MediaTok (Spotlight)" },
            subtitle: { "Быстрый поиск и запуск любой функции MediaTok (.cmd в чате)" },
            icon: .system("magnifyingglass"),
            kind: .action({ context in
                MTMediaTokWave7Tools.presentSpotlightPalette(accountContext: context.context, menuContext: context)
            }),
            searchKeywords: { ["spotlight", "cmd", "палитра", "поиск", "команды", "490"] },
            label: { _ in "CMD" }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.lrcLyrics",
            section: mediaTokSection,
            order: 1600,
            title: { "Синхронные тексты песен (LRC)" },
            subtitle: { "Живая подсветка строк под музыку Telegram через lrclib.net (.lyrics)" },
            icon: .system("music.note"),
            kind: .action({ context in
                MTMediaTokWave7Tools.presentLyricsViewer(context: context.context)
            }),
            searchKeywords: { ["lyrics", "lrc", "текст", "песни", "караоке", "музыка", "371"] },
            label: { _ in "LRC" }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.forceReconnect",
            section: mediaTokSection,
            order: 1700,
            title: { "Переподключить сеть (Force Reconnect)" },
            subtitle: { "Мгновенный сброс зависшего соединения с серверами Telegram (.reconnect)" },
            icon: .system("arrow.clockwise"),
            kind: .action({ context in
                MTMediaTokWave7Tools.forceReconnect(context: context.context)
            }),
            searchKeywords: { ["reconnect", "сеть", "переподключить", "интернет", "416"] },
            label: { _ in "NET" }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.voiceTools",
            section: mediaTokSection,
            order: 1800,
            title: { "Голосовые (ГС): Подтверждение и 99:59" },
            subtitle: { "Подтверждать отправку ГС и опциональная фейк-длительность (0:00 / 99:59)" },
            icon: .system("mic"),
            kind: .action({ context in
                MTMediaTokWave7Tools.presentVoiceToolsSheet(context: context.context)
            }),
            searchKeywords: { ["гс", "голосовые", "voice", "подтверждение", "99:59", "длительность", "377", "379"] },
            label: { _ in MTMediaTokWave7Tools.voiceSummaryLabel }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.whatsNewSafeMode",
            section: mediaTokSection,
            order: 1900,
            title: { "Что нового, Баг-репорт и Safe Mode" },
            subtitle: { "Список изменений, копирование диагностики и безопасный сброс визуала" },
            icon: .system("sparkles"),
            kind: .action({ context in
                MTMediaTokWave7Tools.presentWave7QuickHub(context: context)
            }),
            searchKeywords: { ["whatsnew", "нового", "баг", "идея", "safe", "безопасный", "491", "492", "493"] },
            label: { _ in "Info" }
        ))

        // Wave 8: Sandbox (#499), Profile QR (#466), Face Blur (#460), PDF Scan/Sign (#461/#462), Weather (#497), Battery Spoof (#486)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.profileSandbox",
            section: mediaTokSection,
            order: 2000,
            title: { "Примерочная профиля (MediaTok Sandbox)" },
            subtitle: { "Живой превью темы Nitro, рамки, эффекта, погоды и статуса до сохранения" },
            icon: .system("person.crop.square"),
            kind: .action({ context in
                MTMediaTokWave8Tools.presentProfileSandbox(context: context.context)
            }),
            searchKeywords: { ["sandbox", "примерочная", "профиль", "превью", "499"] },
            label: { _ in "499" }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.profileQr",
            section: mediaTokSection,
            order: 2100,
            title: { "Красивый QR-код профиля" },
            subtitle: { "Градиентная карточка с логотипом MediaTok и твоим @username" },
            icon: .system("qrcode"),
            kind: .action({ context in
                MTMediaTokWave8Tools.presentProfileQR(context: context.context)
            }),
            searchKeywords: { ["qr", "код", "профиль", "градиент", "466"] },
            label: { _ in "QR" }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.faceBlur",
            section: mediaTokSection,
            order: 2200,
            title: { "Размытие лиц на фото (Vision AI)" },
            subtitle: { "Автоматическое обнаружение и размытие лиц в 1 тап (.blurface)" },
            icon: .system("eye.slash"),
            kind: .action({ context in
                MTMediaTokWave8Tools.presentFaceBlurPicker(context: context.context, targetPeerId: nil)
            }),
            searchKeywords: { ["blur", "лица", "размытие", "фото", "vision", "460"] },
            label: { _ in "AI" }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.pdfScanSign",
            section: mediaTokSection,
            order: 2300,
            title: { "Сканер документов и Подпись PDF" },
            subtitle: { "Сканирование камерой в PDF + подпись пальцем любого PDF-файла" },
            icon: .system("doc.text.viewfinder"),
            kind: .action({ context in
                MTMediaTokWave8Tools.presentWave2Studio(context: context.context)
            }),
            searchKeywords: { ["pdf", "скан", "сканер", "подпись", "документ", "461", "462"] },
            label: { _ in "PDF" }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.weatherBattery",
            section: mediaTokSection,
            order: 2400,
            title: { "Живая погода профиля и Спуфинг батареи" },
            subtitle: { "Open-Meteo погода города на профиль + подмена заряда батареи" },
            icon: .system("cloud.sun"),
            kind: .action({ context in
                MTMediaTokWave8Tools.presentWave2Studio(context: context.context)
            }),
            searchKeywords: { ["weather", "погода", "батарея", "battery", "spoof", "497", "486"] },
            label: { _ in MTMediaTokWave8Tools.isBatterySpoofEnabled ? "\(MTMediaTokWave8Tools.spoofedBatteryLevel)%" : "497" }
        ))

        // Wave 9: DC Speedtest (#406/#415), VPN Slot (#401/#402), Unlimited Accounts/Proxies (#422/#423), Sync v2 (#495/#409), DoH (#417), SHA-256 (#420/#421)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.dcSpeedtest",
            section: mediaTokSection,
            order: 2500,
            title: { "Спидтест DC1–DC5 и монитор сети" },
            subtitle: { "Замер пинга серверов Telegram, Catbox CDN и MediaTok Sync (.dc)" },
            icon: .system("antenna.radiowaves.left.and.right"),
            kind: .action({ context in
                MTMediaTokWave9Tools.presentDcSpeedtest(context: context.context)
            }),
            searchKeywords: { ["dc", "speedtest", "ping", "сеть", "пинг", "406", "415"] },
            label: { context in "DC\(context.context.account.network.datacenterId)" }
        ))

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.wave3Hub",
            section: mediaTokSection,
            order: 2600,
            title: { "VPN-слот, Прокси, Sync v2 и DoH" },
            subtitle: { "Split Tunneling, клонирование настроек на аккаунты, резервное зеркало синка" },
            icon: .system("network"),
            kind: .action({ context in
                MTMediaTokWave9Tools.presentWave3NetworkHub(context: context.context)
            }),
            searchKeywords: { ["vpn", "split", "proxy", "аккаунты", "клон", "sync", "doh", "sha256", "401", "402", "422", "423", "495", "417", "420"] },
            label: { _ in "NET" }
        ))

        // Wave 10: Sticker Maker (#456), Mini Apps (#451-#455), Voicemod Presets (#380), Chat Analytics/Top/TimeMachine/FakeRoute
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.wave4Hub",
            section: mediaTokSection,
            order: 2700,
            title: { "Аналитика, ГС +15 dB, Стикеры и Mini Apps" },
            subtitle: { "График чата, топ постов, конструктор 512px, фейк-гео, Машина времени, Mini Apps" },
            icon: .system("chart.bar"),
            kind: .action({ context in
                MTMediaTokWave10Tools.presentWave4Hub(context: context.context, peerId: nil)
            }),
            searchKeywords: { ["аналитика", "график", "топ", "стикеры", "miniapps", "маршрут", "гео", "машина времени", "гс", "voicemod", "375", "376", "380", "451", "456", "476", "477", "485", "498"] },
            label: { _ in "W10" }
        ))

        // Wave 11: OCR Translate (#479), Magic Eraser (#481), 4K Upscale (#482), Mini-Games (#467), RSS (#470), Shared Clipboard (#419), Ecosystem (#487-#489/#494)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.wave5EcosystemHub",
            section: mediaTokSection,
            order: 2800,
            title: { "AI Фото, Ластик, 4K, RSS, Буфер ПК и Siri" },
            subtitle: { "Перевод манги/фото, Magic Eraser, 4K апскейл, Крестики-нолики & 2048, RSS, буфер ПК, Команды" },
            icon: .system("wand.and.stars.inverse"),
            kind: .action({ context in
                MTMediaTokWave11Tools.presentWave5Hub(context: context.context, peerId: nil)
            }),
            searchKeywords: { ["ocr", "манга", "перевод", "ластик", "eraser", "upscale", "4k", "игры", "2048", "крестики", "rss", "буфер", "clipboard", "siri", "команды", "виджеты", "479", "481", "482", "467", "470", "419", "487", "488", "489", "494"] },
            label: { _ in "W11" }
        ))

        // Wave 12 (Signature 5): Stego (#501), Voice FX Studio (#502), Burn-After-Reading (#503), Cinematic Cards (#504), OSINT X-Ray (#505)
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.mediatok.wave12Lab",
            section: mediaTokSection,
            order: 2900,
            title: { "MediaTok Lab: Стеганография, Голос-FX и OSINT" },
            subtitle: { "Секрет в пикселях PNG, студия голоса, AES-записки с PIN, кино-карточки, EXIF/фишинг" },
            icon: .system("flask"),
            kind: .action({ context in
                MTMediaTokWave12Tools.presentSignatureHub(context: context.context, peerId: nil)
            }),
            searchKeywords: { ["stego", "стеганография", "vfx", "голос", "демон", "рация", "burn", "бомба", "pin", "cinematic", "карточка", "osint", "xray", "exif", "фишинг", "501", "502", "503", "504", "505"] },
            label: { _ in "LAB" }
        ))

        // Bubbles.
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.messagesBubbles, screen: .tab(tab), order: 300, header: { MTStrings.Appearance.Bubbles.header }, footer: { _ in MTStrings.Appearance.Bubbles.footer }))
        let editorOn: (MTMenuContext) -> Bool = { _ in MTAppearanceSettings.bubbleEditor.value }
        MTMenuRegistry.register(MTMenuRow(id: "appearance.bubbles.editor", section: MTAppearanceMenu.messagesBubbles, order: 100, title: { MTStrings.Appearance.Bubbles.editor }, subtitle: { MTStrings.Appearance.Bubbles.editorInfo }, kind: .toggle(.global(MTAppearanceSettings.bubbleEditor)), searchKeywords: { [MTStrings.Appearance.Bubbles.keywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.bubbles.incomingRadius", section: MTAppearanceMenu.messagesBubbles, order: 200, title: { MTStrings.Appearance.Bubbles.incomingRadius }, kind: .slider(.global(MTAppearanceSettings.bubbleIncomingRadius), range: 0.0 ... 26.0, step: 1.0, format: MTAppearanceMenu.points), isVisible: editorOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.bubbles.outgoingRadius", section: MTAppearanceMenu.messagesBubbles, order: 300, title: { MTStrings.Appearance.Bubbles.outgoingRadius }, kind: .slider(.global(MTAppearanceSettings.bubbleOutgoingRadius), range: 0.0 ... 26.0, step: 1.0, format: MTAppearanceMenu.points), isVisible: editorOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.bubbles.padding", section: MTAppearanceMenu.messagesBubbles, order: 400, title: { MTStrings.Appearance.Bubbles.padding }, kind: .slider(.global(MTAppearanceSettings.bubblePadding), range: 0.0 ... 24.0, step: 1.0, format: MTAppearanceMenu.points), isVisible: editorOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.bubbles.width", section: MTAppearanceMenu.messagesBubbles, order: 500, title: { MTStrings.Appearance.Bubbles.width }, kind: .slider(.global(MTAppearanceSettings.bubbleWidth), range: 40.0 ... 100.0, step: 5.0, format: MTAppearanceMenu.percent), isVisible: editorOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.bubbles.backgroundOpacity", section: MTAppearanceMenu.messagesBubbles, order: 600, title: { MTStrings.Appearance.Bubbles.backgroundOpacity }, kind: .slider(.global(MTAppearanceSettings.bubbleBackgroundOpacity), range: 0.0 ... 100.0, step: 5.0, format: MTAppearanceMenu.percent), isVisible: editorOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.bubbles.outlineOpacity", section: MTAppearanceMenu.messagesBubbles, order: 700, title: { MTStrings.Appearance.Bubbles.outlineOpacity }, kind: .slider(.global(MTAppearanceSettings.bubbleOutlineOpacity), range: 0.0 ... 100.0, step: 5.0, format: MTAppearanceMenu.percent), isVisible: editorOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.bubbles.reset", section: MTAppearanceMenu.messagesBubbles, order: 800, title: { MTStrings.Appearance.Bubbles.reset }, kind: .action({ _ in
            MTAppearanceSettings.bubbleIncomingRadius.reset()
            MTAppearanceSettings.bubbleOutgoingRadius.reset()
            MTAppearanceSettings.bubblePadding.reset()
            MTAppearanceSettings.bubbleWidth.reset()
            MTAppearanceSettings.bubbleBackgroundOpacity.reset()
            MTAppearanceSettings.bubbleOutlineOpacity.reset()
        }), isVisible: editorOn, isDestructive: true))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.bubbles.hideTails", section: MTAppearanceMenu.messagesBubbles, order: 900, title: { MTStrings.Appearance.Bubbles.hideTails }, subtitle: { MTStrings.Appearance.Bubbles.hideTailsInfo }, kind: .toggle(.global(MTAppearanceSettings.bubbleHideTails))))

        // Checkmarks.
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.messagesChecks, screen: .tab(tab), order: 400, header: { MTStrings.Appearance.Checkmarks.header }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.checkmarks.readColor", section: MTAppearanceMenu.messagesChecks, order: 100, title: { MTStrings.Appearance.Checkmarks.readColor }, kind: .action({ context in
            MTColorPicker.present(context: context, setting: MTAppearanceSettings.readCheckColor, fallback: UIColor(rgb: 0x19c700))
        }), searchKeywords: { [MTStrings.Appearance.Checkmarks.keywords] }, label: { _ in MTAppearanceMenu.colorLabel(MTAppearanceSettings.readCheckColor) }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.checkmarks.unreadSameAsRead", section: MTAppearanceMenu.messagesChecks, order: 200, title: { MTStrings.Appearance.Checkmarks.unreadSameAsRead }, kind: .toggle(.global(MTAppearanceSettings.unreadCheckSameAsRead)), isVisible: { _ in !MTAppearanceSettings.readCheckColor.value.isEmpty }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.checkmarks.unreadColor", section: MTAppearanceMenu.messagesChecks, order: 300, title: { MTStrings.Appearance.Checkmarks.unreadColor }, kind: .action({ context in
            MTColorPicker.present(context: context, setting: MTAppearanceSettings.unreadCheckColor, fallback: UIColor(rgb: 0xa3a3a3))
        }), isVisible: { _ in !MTAppearanceSettings.unreadCheckSameAsRead.value || MTAppearanceSettings.readCheckColor.value.isEmpty }, label: { _ in MTAppearanceMenu.colorLabel(MTAppearanceSettings.unreadCheckColor) }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.checkmarks.inChatList", section: MTAppearanceMenu.messagesChecks, order: 400, title: { MTStrings.Appearance.Checkmarks.inChatList }, kind: .toggle(.global(MTAppearanceSettings.checkColorsInChatList)), isVisible: { _ in !MTAppearanceSettings.readCheckColor.value.isEmpty }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.checkmarks.reset", section: MTAppearanceMenu.messagesChecks, order: 500, title: { MTStrings.Appearance.Checkmarks.reset }, kind: .action({ _ in
            MTAppearanceSettings.readCheckColor.reset()
            MTAppearanceSettings.unreadCheckColor.reset()
        }), isVisible: { _ in !MTAppearanceSettings.readCheckColor.value.isEmpty || !MTAppearanceSettings.unreadCheckColor.value.isEmpty }, isDestructive: true))

        // Stickers.
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.messagesStickers, screen: .tab(tab), order: 500, header: { MTStrings.Appearance.Stickers.header }))
        // Live: the emoji and the sticker follow the size slider while it is dragged (2026-11-02).
        MTMenuRegistry.register(MTMenuRow(id: "appearance.stickers.preview", section: MTAppearanceMenu.messagesStickers, order: 50, title: { "" }, kind: .preview(.custom(height: MTStickerSizePreviewView.height, make: { _ in
            return MTStickerSizePreviewView(frame: .zero)
        }))))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.stickers.size", section: MTAppearanceMenu.messagesStickers, order: 100, title: { MTStrings.Appearance.Stickers.size }, kind: .slider(.global(MTAppearanceSettings.stickerSize), range: 50.0 ... 200.0, step: 5.0, format: MTAppearanceMenu.percent)))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.stickers.hideTime", section: MTAppearanceMenu.messagesStickers, order: 200, title: { MTStrings.Appearance.Stickers.hideTime }, kind: .toggle(.global(MTAppearanceSettings.stickerHideTime))))

        // Message interface.
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.messagesInterface, screen: .tab(tab), order: 600, header: { MTStrings.Appearance.Messages.header }))
        // «Скрыть в сообщениях» (2026-10-27): four switches in one row that opens in place.
        let hiddenInMessages: [(String, () -> String, MTSetting<Bool>)] = [
            ("appearance.messages.hideEdited", { MTStrings.Appearance.Messages.hiddenEdited }, MTAppearanceSettings.hideEdited),
            ("appearance.messages.hideTime", { MTStrings.Appearance.Messages.hiddenTime }, MTAppearanceSettings.hideTime),
            ("appearance.messages.hideViewCounts", { MTStrings.Appearance.Messages.hiddenViewCounts }, MTAppearanceSettings.hideViewCounts),
            ("appearance.messages.hideChannelComments", { MTStrings.Appearance.Messages.hiddenChannelComments }, MTAppearanceSettings.hideChannelComments)
        ]
        MTMenuRegistry.register(MTMenuRow(id: "appearance.messages.hidden", section: MTAppearanceMenu.messagesInterface, order: 100, title: { MTStrings.Appearance.Messages.hidden }, kind: .expandableList(children: MTAppearanceMenu.hiddenChildren(hiddenInMessages, section: MTAppearanceMenu.messagesInterface), summary: MTAppearanceMenu.hiddenSummary)))
        let toggles: [(String, Int, () -> String, (() -> String)?, MTSetting<Bool>)] = [
            ("appearance.messages.secondsInTime", 300, { MTStrings.Appearance.Messages.secondsInTime }, { MTStrings.Appearance.Messages.secondsInTimeInfo }, MTAppearanceSettings.secondsInTime),
            ("appearance.messages.exactLastSeen", 400, { MTStrings.Appearance.Messages.exactLastSeen }, { MTStrings.Appearance.Messages.exactLastSeenInfo }, MTAppearanceSettings.exactLastSeen),
            ("appearance.messages.wideChannelPosts", 900, { MTStrings.Appearance.Messages.wideChannelPosts }, nil, MTAppearanceSettings.wideChannelPosts),
            ("appearance.messages.authorOnline", 1000, { MTStrings.Appearance.Messages.authorOnline }, { MTStrings.Appearance.Messages.authorOnlineInfo }, MTAppearanceSettings.authorOnlineIndicator),
            ("appearance.messages.colorSwatches", 1100, { MTStrings.Appearance.Messages.colorSwatches }, { MTStrings.Appearance.Messages.colorSwatchesInfo }, MTAppearanceSettings.colorSwatches),
            ("appearance.messages.noSelectionBlur", 1200, { MTStrings.Appearance.Messages.noSelectionBlur }, nil, MTAppearanceSettings.noSelectionBlur)
        ]
        for (id, order, title, subtitle, setting) in toggles {
            MTMenuRegistry.register(MTMenuRow(id: id, section: MTAppearanceMenu.messagesInterface, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting))))
        }
        // Two choices instead of four switches (2026-10-27): where reactions and formatting are hidden.
        MTMenuRegistry.register(MTMenuRow(id: "appearance.messages.hideReactions", section: MTAppearanceMenu.messagesInterface, order: 500, title: { MTStrings.Appearance.Messages.hideReactions }, kind: .choice(.global(MTAppearanceSettings.hideReactions), options: [
            MTMenuChoiceOption(value: MTHiddenReactions.off.rawValue, title: { MTStrings.Appearance.Messages.hiddenNowhere }),
            MTMenuChoiceOption(value: MTHiddenReactions.chats.rawValue, title: { MTStrings.Appearance.Messages.hideReactionsChats }),
            MTMenuChoiceOption(value: MTHiddenReactions.channels.rawValue, title: { MTStrings.Appearance.Messages.hideReactionsChannels }),
            MTMenuChoiceOption(value: MTHiddenReactions.all.rawValue, title: { MTStrings.Appearance.Messages.hiddenEverywhere })
        ])))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.messages.hideFormatting", section: MTAppearanceMenu.messagesInterface, order: 800, title: { MTStrings.Appearance.Messages.hideFormatting }, subtitle: { MTStrings.Appearance.Messages.hideFormattingInfo }, kind: .choice(.global(MTAppearanceSettings.hideFormatting), options: [
            MTMenuChoiceOption(value: MTHiddenFormatting.off.rawValue, title: { MTStrings.Appearance.Messages.hiddenNowhere }),
            MTMenuChoiceOption(value: MTHiddenFormatting.incoming.rawValue, title: { MTStrings.Appearance.Messages.hideFormattingIncoming }),
            MTMenuChoiceOption(value: MTHiddenFormatting.outgoing.rawValue, title: { MTStrings.Appearance.Messages.hideFormattingOutgoing }),
            MTMenuChoiceOption(value: MTHiddenFormatting.all.rawValue, title: { MTStrings.Appearance.Messages.hiddenEverywhere })
        ])))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.messages.tripleTapDelete", section: MTAppearanceMenu.messagesInterface, order: 1300, title: { MTStrings.Appearance.Messages.tripleTapDelete }, kind: .choice(.global(MTAppearanceSettings.tripleTapDelete), options: [
            MTMenuChoiceOption(value: MTTripleTapDelete.off.rawValue, title: { MTStrings.Appearance.Messages.tripleTapOff }),
            MTMenuChoiceOption(value: MTTripleTapDelete.local.rawValue, title: { MTStrings.Appearance.Messages.tripleTapLocal }),
            MTMenuChoiceOption(value: MTTripleTapDelete.everyone.rawValue, title: { MTStrings.Appearance.Messages.tripleTapEveryone })
        ])))

        // «Скрыть в шапке чата» (2026-10-27): the chat's top bar, four switches in one row. The
        // section keeps only its footer: the row's title says what it is.
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.messagesTopBar, screen: .tab(tab), order: 700, footer: { _ in MTStrings.Appearance.TopBar.footer }))
        let hiddenInTopBar: [(String, () -> String, MTSetting<Bool>)] = [
            ("appearance.chatTopBar.hideBackButton", { MTStrings.Appearance.TopBar.backButton }, MTAppearanceSettings.hideBackButton),
            ("appearance.chatTopBar.hideTitle", { MTStrings.Appearance.TopBar.title }, MTAppearanceSettings.hideTitlePanel),
            ("appearance.chatTopBar.hideAvatar", { MTStrings.Appearance.TopBar.avatar }, MTAppearanceSettings.hideAvatar),
            ("appearance.chatTopBar.hidePinned", { MTStrings.Appearance.TopBar.pinned }, MTAppearanceSettings.hidePinnedMessages)
        ]
        MTMenuRegistry.register(MTMenuRow(id: "appearance.chatTopBar.hidden", section: MTAppearanceMenu.messagesTopBar, order: 100, title: { MTStrings.Appearance.TopBar.hidden }, kind: .expandableList(children: MTAppearanceMenu.hiddenChildren(hiddenInTopBar, section: MTAppearanceMenu.messagesTopBar), summary: MTAppearanceMenu.hiddenSummary), searchKeywords: { [MTStrings.Appearance.TopBar.keywords] }))
    }

    /// The switches of a «Скрыть в …» row, in the given order.
    private static func hiddenChildren(_ items: [(String, () -> String, MTSetting<Bool>)], section: MTMenuSectionID) -> [MTMenuRow] {
        var result: [MTMenuRow] = []
        var order = 100
        for (id, title, setting) in items {
            result.append(MTMenuRow(id: id, section: section, order: order, title: title, kind: .toggle(.global(setting))))
            order += 100
        }
        return result
    }

    /// «скрыто: 2 из 4» on the right of a «Скрыть в …» row (nothing while none is hidden).
    static func hiddenSummary(_ count: MTMenuGroupCount) -> String {
        return MTStrings.Appearance.Messages.hiddenCount(selected: "\(count.selected)", total: "\(count.total)")
    }

    // MARK: Font tab

    /// The user's own fonts, then the system font and its designs, then the
    /// families preinstalled in iOS. Nothing bundled, no font licenses to list.
    private static func registerFont() {
        MTAppearanceMenu.registerCustomFonts()
        MTAppearanceMenu.registerBundledFonts()

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.fontSystem, screen: .tab(MTAppearanceMenu.fontTab), order: 100, header: { MTStrings.Appearance.Font.systemHeader }, footer: { _ in
            if MTFonts.needsRestart {
                return MTStrings.Core.requiresRestartFooter
            }
            return MTStrings.Appearance.Font.systemFooter
        }))
        var order = 100
        for family in [MTFontFamily.system] + MTFonts.designFamilies {
            MTAppearanceMenu.registerFontRow(family: family, section: MTAppearanceMenu.fontSystem, order: order)
            order += 100
        }

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.fontFamilies, screen: .tab(MTAppearanceMenu.fontTab), order: 400, header: { MTStrings.Appearance.Font.familiesHeader }, footer: { _ in MTStrings.Appearance.Font.familiesFooter }))
        order = 100
        for family in MTFonts.installedFamilies {
            MTAppearanceMenu.registerFontRow(family: family, section: MTAppearanceMenu.fontFamilies, order: order)
            order += 100
        }
    }

    private static func registerBundledFonts() {
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.fontBundled, screen: .tab(MTAppearanceMenu.fontTab), order: 250, header: { MTStrings.Appearance.Font.bundledHeader }, footer: { _ in
            if MTFonts.needsRestart && MTFonts.selectedBundledFont != nil {
                return MTStrings.Core.requiresRestartFooter
            }
            return MTStrings.Appearance.Font.bundledFooter
        }))
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.font.bundled.resetSystem",
            section: MTAppearanceMenu.fontBundled,
            order: 50,
            title: { "Вернуть стандартный шрифт (SF Pro)" },
            kind: .action({ context in
                MTAppearanceSettings.fontFamily.set(MTFontFamily.system.rawValue)
                context.presentToast("Системный шрифт SF Pro восстановлен")
            }),
            isVisible: { _ in MTAppearanceSettings.fontFamily.value != MTFontFamily.system.rawValue }
        ))
        var order = 100
        for bundledFont in MTMediaTokFonts.all {
            MTMenuRegistry.register(MTMenuRow(id: "appearance.font.bundled.\(bundledFont.slug)", section: MTAppearanceMenu.fontBundled, order: order, title: { bundledFont.displayName }, kind: .custom({ context in
                return MTAppearanceMenu.bundledFontItem(bundledFont, context: context)
            }), searchKeywords: { [bundledFont.displayName, bundledFont.category] }))
            order += 10
        }
    }

    private static func bundledFontItem(_ bundledFont: MTBundledFont, context: MTMenuContext) -> ListViewItem {
        let presentationData = context.itemListPresentationData
        let isSelected = MTFonts.selectedBundledFont == bundledFont
        let sample = MTFonts.sampleImage(bundledFont: bundledFont, color: presentationData.theme.list.itemPrimaryTextColor)
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: sample, iconSize: sample?.size, title: bundledFont.displayName, subtitle: bundledFont.category, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
            let target = isSelected ? MTFontFamily.system.rawValue : MTMediaTokFonts.settingValue(bundledFont)
            MTMenuBinding.global(MTAppearanceSettings.fontFamily).set(target, in: context)
        })
    }

    private static func registerChatFont() {
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.chatFontDisable, screen: .tab(MTAppearanceMenu.chatFontTab), order: 100, footer: { _ in MTStrings.Appearance.ChatFont.footer }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.chatFont.off", section: MTAppearanceMenu.chatFontDisable, order: 100, title: { MTStrings.Appearance.ChatFont.disableTitle }, kind: .custom({ context in
            let presentationData = context.itemListPresentationData
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: MTStrings.Appearance.ChatFont.disableTitle, style: .right, checked: MTChatTextFonts.selectedStyle == nil, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
                MTMenuBinding.global(MTAppearanceSettings.chatTextFont).set("", in: context)
            })
        })))

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.chatFontCyrillic, screen: .tab(MTAppearanceMenu.chatFontTab), order: 200, header: { MTStrings.Appearance.ChatFont.cyrillicHeader }))
        var order = 100
        for style in MTChatTextFonts.cyrillicStyles {
            MTAppearanceMenu.registerChatFontRow(style: style, section: MTAppearanceMenu.chatFontCyrillic, order: order)
            order += 10
        }

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.chatFontMath, screen: .tab(MTAppearanceMenu.chatFontTab), order: 300, header: { MTStrings.Appearance.ChatFont.mathHeader }))
        order = 100
        for style in MTChatTextFonts.mathStyles {
            MTAppearanceMenu.registerChatFontRow(style: style, section: MTAppearanceMenu.chatFontMath, order: order)
            order += 10
        }
    }

    private static func registerChatFontRow(style: MTChatTextStyle, section: MTMenuSectionID, order: Int) {
        MTMenuRegistry.register(MTMenuRow(id: "appearance.chatFont.\(style.id)", section: section, order: order, title: { style.name }, kind: .custom({ context in
            let presentationData = context.itemListPresentationData
            let isSelected = MTChatTextFonts.selectedStyle == style
            let preview = MTChatTextFonts.preview(for: style)
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: "\(style.name)  (.f \(style.id))", subtitle: preview, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
                let nextValue = isSelected ? "" : style.id
                MTMenuBinding.global(MTAppearanceSettings.chatTextFont).set(nextValue, in: context)
            })
        }), searchKeywords: { [style.name, style.id] }))
    }

    private static func registerFontRow(family: MTFontFamily, section: MTMenuSectionID, order: Int) {
        // «SF Mono», «New York» find the rows of the system designs too.
        let properName = MTFonts.properName(family)
        MTMenuRegistry.register(MTMenuRow(id: "appearance.font.\(family.rawValue)", section: section, order: order, title: { MTFonts.displayName(family) }, kind: .custom({ context in
            return MTAppearanceMenu.fontItem(family: family, context: context)
        }), isVisible: { _ in MTFonts.isAvailable(family) }, searchKeywords: { properName.map { [$0] } ?? [] }))
    }

    /// «Свои шрифты»: a row per added font (fixed slots: the registry is static, the list is a
    /// setting), «Добавить шрифт…» and «Удалить шрифт…».
    private static func registerCustomFonts() {
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.fontCustom, screen: .tab(MTAppearanceMenu.fontTab), order: 200, header: { MTStrings.Appearance.Font.customHeader }, footer: { _ in
            if MTFonts.needsRestart && MTFonts.selectedCustomFont != nil {
                return MTStrings.Core.requiresRestartFooter
            }
            return MTStrings.Appearance.Font.customFooter
        }))
        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.font.custom.resetSystem",
            section: MTAppearanceMenu.fontCustom,
            order: 50,
            title: { "Вернуть стандартный шрифт (SF Pro)" },
            kind: .action({ context in
                MTAppearanceSettings.fontFamily.set(MTFontFamily.system.rawValue)
                context.presentToast("Системный шрифт SF Pro восстановлен")
            }),
            isVisible: { _ in MTAppearanceSettings.fontFamily.value != MTFontFamily.system.rawValue }
        ))
        for index in 0 ..< MTCustomFonts.maximumCount {
            let font: () -> MTCustomFont? = {
                let fonts = MTCustomFonts.fonts
                return index < fonts.count ? fonts[index] : nil
            }
            MTMenuRegistry.register(MTMenuRow(id: "appearance.font.custom.\(index)", section: MTAppearanceMenu.fontCustom, order: 100 + index * 10, title: { font()?.familyName ?? "" }, kind: .custom({ context in
                guard let customFont = font() else {
                    return MTAppearanceMenu.fontItem(family: .system, context: context)
                }
                return MTAppearanceMenu.customFontItem(customFont, context: context)
            }), isVisible: { _ in font() != nil }))
        }
        MTMenuRegistry.register(MTMenuRow(id: "appearance.font.add", section: MTAppearanceMenu.fontCustom, order: 2000, title: { MTStrings.Appearance.Font.add }, kind: .action({ context in
            MTPickers.pickFont(context: context)
        }), searchKeywords: { [MTStrings.Appearance.Font.keywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.font.createTtf", section: MTAppearanceMenu.fontCustom, order: 2050, title: { MTStrings.Appearance.Font.createTtf }, subtitle: { MTStrings.Appearance.Font.createTtfInfo }, kind: .action({ context in
            MTMediaTokTtfCreator.present(context: context)
        }), searchKeywords: { [MTStrings.Appearance.Font.keywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.font.remove", section: MTAppearanceMenu.fontCustom, order: 2100, title: { MTStrings.Appearance.Font.remove }, kind: .action({ context in
            MTAppearanceMenu.presentRemoveFont(context: context)
        }), isVisible: { _ in !MTCustomFonts.fonts.isEmpty }, isDestructive: true))
    }

    private static func customFontItem(_ customFont: MTCustomFont, context: MTMenuContext) -> ListViewItem {
        let presentationData = context.itemListPresentationData
        let isSelected = MTFonts.selectedCustomFont == customFont
        let sample = MTFonts.sampleImage(customFont: customFont, color: presentationData.theme.list.itemPrimaryTextColor)
        let detail: String? = MTFonts.hasCyrillic(customFont) ? nil : MTStrings.Appearance.Font.noCyrillic
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: sample, iconSize: sample?.size, title: customFont.familyName, subtitle: detail, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
            let target = isSelected ? MTFontFamily.system.rawValue : MTCustomFonts.settingValue(customFont)
            MTMenuBinding.global(MTAppearanceSettings.fontFamily).set(target, in: context)
        })
    }

    private static func presentRemoveFont(context: MTMenuContext) {
        let sheet = UIAlertController(title: MTStrings.Appearance.Font.removeTitle, message: nil, preferredStyle: .actionSheet)
        for customFont in MTCustomFonts.fonts {
            sheet.addAction(UIAlertAction(title: customFont.familyName, style: .destructive, handler: { _ in
                MTCustomFonts.remove(customFont)
            }))
        }
        sheet.addAction(UIAlertAction(title: context.presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
        context.presentNative(sheet)
    }

    private static func fontItem(family: MTFontFamily, context: MTMenuContext) -> ListViewItem {
        let presentationData = context.itemListPresentationData
        let isSelected = MTFonts.selectedCustomFont == nil && MTFonts.selectedBundledFont == nil && MTFonts.selectedFamily == family
        let sample = MTFonts.sampleImage(family: family, color: presentationData.theme.list.itemPrimaryTextColor)
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: sample, iconSize: sample?.size, title: MTFonts.displayName(family), subtitle: MTFonts.detail(family), style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
            let target = (isSelected && family != .system) ? MTFontFamily.system.rawValue : family.rawValue
            MTMenuBinding.global(MTAppearanceSettings.fontFamily).set(target, in: context)
        })
    }

    // MARK: «Тема и фон»

    private static func registerTheme() {
        let tab = MTMenuTabID.appearanceThemeBackground

        MTMenuRegistry.register(MTMenuRow(
            id: "appearance.theme.preview",
            section: .preview(of: tab),
            order: 100,
            title: { "" },
            // Live: the theme follows its sliders while dragged; the animated background, the snow
            // and the edge bands are shown as in a chat (U6, U7).
            kind: .preview(.miniChat(MTAppearancePreview.configuration(scope: "appearance.theme", overlays: true, content: { _ in
                return MTAppearancePreview.sampleContent()
            })))
        ))

        let main = MTMenuSectionID.main(of: tab)
        MTMenuRegistry.register(MTMenuRow(id: "appearance.theme.amoled", section: main, order: 100, title: { MTStrings.Appearance.Theme.amoled }, subtitle: { MTStrings.Appearance.Theme.amoledInfo }, kind: .toggle(.global(MTAppearanceSettings.amoled)), searchKeywords: { [MTStrings.Appearance.Theme.amoledKeywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.theme.amoledKeyboard", section: main, order: 200, title: { MTStrings.Appearance.Theme.amoledKeyboard }, subtitle: { MTStrings.Appearance.Theme.amoledKeyboardInfo }, kind: .toggle(.global(MTAppearanceSettings.amoledKeyboard))))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.theme.hideSeparators", section: main, order: 300, title: { MTStrings.Appearance.Theme.hideSeparators }, kind: .toggle(.global(MTAppearanceSettings.hideSeparators))))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.theme.nameSaturation", section: main, order: 400, title: { MTStrings.Appearance.Theme.nameSaturation }, subtitle: { MTStrings.Appearance.Theme.nameSaturationInfo }, kind: .slider(.global(MTAppearanceSettings.nameColorSaturation), range: 0.0 ... 100.0, step: 5.0, format: MTAppearanceMenu.percent)))

        // «Затемнение краёв» (one group since 2026-10-27): the kind of band, then only what it uses.
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.themeEdges, screen: .tab(tab), order: 400, header: { MTStrings.Appearance.Edges.header }, footer: { _ in MTStrings.Appearance.Edges.footer }))
        let edgeStyle: () -> MTEdgeStyle = { MTEdgeStyle(rawValue: MTAppearanceSettings.edgeStyle.value) ?? .off }
        let edgesOn: (MTMenuContext) -> Bool = { _ in edgeStyle() != .off }
        MTMenuRegistry.register(MTMenuRow(id: "appearance.edges.style", section: MTAppearanceMenu.themeEdges, order: 100, title: { MTStrings.Appearance.Edges.header }, kind: .discreteChoice(.global(MTAppearanceSettings.edgeStyle), options: [
            MTMenuChoiceOption(value: MTEdgeStyle.off.rawValue, title: { MTStrings.Appearance.Edges.styleOff }),
            MTMenuChoiceOption(value: MTEdgeStyle.blur.rawValue, title: { MTStrings.Appearance.Edges.styleBlur }),
            MTMenuChoiceOption(value: MTEdgeStyle.gradient.rawValue, title: { MTStrings.Appearance.Edges.styleGradient })
        ]), searchKeywords: { [MTStrings.Appearance.Edges.keywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.edges.intensity", section: MTAppearanceMenu.themeEdges, order: 200, title: { MTStrings.Appearance.Edges.intensity }, kind: .slider(.global(MTAppearanceSettings.edgeIntensity), range: 0.0 ... 100.0, step: 5.0, format: MTAppearanceMenu.percent), isVisible: edgesOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.edges.size", section: MTAppearanceMenu.themeEdges, order: 300, title: { MTStrings.Appearance.Edges.size }, kind: .slider(.global(MTAppearanceSettings.edgeSize), range: MTEdgeStyle.sizeRange, step: 4.0, format: MTAppearanceMenu.points), isVisible: edgesOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.edges.color", section: MTAppearanceMenu.themeEdges, order: 400, title: { MTStrings.Appearance.Edges.color }, kind: .action({ context in
            // The picker starts where the old rows did: the bar's color for the blur, the accent for the gradient.
            let fallback = edgeStyle() == .gradient ? context.presentationData.theme.list.itemAccentColor : context.presentationData.theme.rootController.navigationBar.opaqueBackgroundColor
            MTColorPicker.present(context: context, setting: MTAppearanceSettings.edgeColor, fallback: fallback)
        }), isVisible: edgesOn, label: { _ in MTAppearanceMenu.colorLabel(MTAppearanceSettings.edgeColor) }))
        // Back to «Automatic» (the bar's color, following the theme) once a color was chosen.
        MTMenuRegistry.register(MTMenuRow(id: "appearance.edges.resetColor", section: MTAppearanceMenu.themeEdges, order: 450, title: { MTStrings.Appearance.Edges.resetColor }, kind: .action({ _ in
            MTAppearanceSettings.edgeColor.reset()
        }), isVisible: { context in edgesOn(context) && !MTAppearanceSettings.edgeColor.value.isEmpty }, isDestructive: true))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.edges.hideInChatList", section: MTAppearanceMenu.themeEdges, order: 500, title: { MTStrings.Appearance.Edges.hideInChatList }, kind: .toggle(.global(MTAppearanceSettings.edgeHideInChatList)), isVisible: { _ in edgeStyle() == .gradient }))

        // Animated chat background.
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.themeBackground, screen: .tab(tab), order: 500, header: { MTStrings.Appearance.Background.chatHeader }, footer: { _ in MTStrings.Appearance.Background.footer }))
        MTAppearanceMenu.registerBackgroundRows(kind: .chat, section: MTAppearanceMenu.themeBackground, idPrefix: "appearance.chatBackground")

        // Snowfall.
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.themeSnow, screen: .tab(tab), order: 600, header: { MTStrings.Appearance.Snow.header }, footer: { _ in
            // Says so when the system is what stops the snow right now (the switch alone looked broken).
            if MTAppearanceSettings.snow.value && MTSystemState.current {
                return MTStrings.Appearance.Snow.footer + "\n\n" + MTStrings.Appearance.Snow.pausedNow
            }
            return MTStrings.Appearance.Snow.footer
        }))
        let snowOn: (MTMenuContext) -> Bool = { _ in MTAppearanceSettings.snow.value }
        MTMenuRegistry.register(MTMenuRow(id: "appearance.snow.enabled", section: MTAppearanceMenu.themeSnow, order: 100, title: { MTStrings.Appearance.Snow.enabled }, kind: .toggle(.global(MTAppearanceSettings.snow)), searchKeywords: { [MTStrings.Appearance.Snow.keywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.snow.style", section: MTAppearanceMenu.themeSnow, order: 200, title: { MTStrings.Appearance.Snow.style }, kind: .choice(.global(MTAppearanceSettings.snowStyle), options: [
            MTMenuChoiceOption(value: MTSnowStyle.snow.rawValue, title: { MTStrings.Appearance.Snow.styleSnow }),
            MTMenuChoiceOption(value: MTSnowStyle.lightning.rawValue, title: { MTStrings.Appearance.Snow.styleLightning })
        ]), isVisible: snowOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.snow.intensity", section: MTAppearanceMenu.themeSnow, order: 300, title: { MTStrings.Appearance.Snow.intensity }, kind: .slider(.global(MTAppearanceSettings.snowIntensity), range: 10.0 ... 100.0, step: 5.0, format: MTAppearanceMenu.percent), isVisible: snowOn))
        MTMenuRegistry.register(MTMenuRow(id: "appearance.snow.hideInChats", section: MTAppearanceMenu.themeSnow, order: 400, title: { MTStrings.Appearance.Snow.hideInChats }, kind: .toggle(.global(MTAppearanceSettings.snowHideInChats)), isVisible: snowOn))
    }

    /// Rows of an animated background: on/off (once a file exists), pick, opacity, delete.
    private static func registerBackgroundRows(kind: MTAnimatedBackgroundKind, section: MTMenuSectionID, idPrefix: String) {
        let hasFile: (MTMenuContext) -> Bool = { _ in kind.versionSetting.value != 0 }
        MTMenuRegistry.register(MTMenuRow(id: "\(idPrefix).enabled", section: section, order: 100, title: { MTStrings.Appearance.Background.enabled }, kind: .toggle(.global(kind.enabledSetting)), isVisible: hasFile))
        MTMenuRegistry.register(MTMenuRow(id: "\(idPrefix).pick", section: section, order: 200, title: { MTStrings.Appearance.Background.pick }, subtitle: { MTStrings.Appearance.Background.pickInfo }, kind: .action({ context in
            MTPickers.pickBackground(context: context, kind: kind)
        }), searchKeywords: { [MTStrings.Appearance.Background.keywords] }, label: { _ in
            return kind.versionSetting.value != 0 ? MTStrings.Appearance.Background.isSet : MTStrings.Appearance.Background.notSet
        }))
        MTMenuRegistry.register(MTMenuRow(id: "\(idPrefix).opacity", section: section, order: 300, title: { MTStrings.Appearance.Background.opacity }, kind: .slider(.global(kind.opacitySetting), range: 5.0 ... 100.0, step: 5.0, format: MTAppearanceMenu.percent), isVisible: hasFile))
        MTMenuRegistry.register(MTMenuRow(id: "\(idPrefix).remove", section: section, order: 400, title: { MTStrings.Appearance.Background.remove }, kind: .action({ _ in
            MTAnimatedBackgrounds.remove(kind)
        }), isVisible: hasFile, isDestructive: true))
    }

    // MARK: «Профиль»

    private static func registerProfile() {
        let tab = MTMenuTabID.appearanceProfileSettings
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.profileInfo, screen: .tab(tab), order: 300, header: { MTStrings.Appearance.Profile.header }, footer: { _ in MTStrings.Appearance.Profile.footer }))
        let rows: [(String, () -> String, (() -> String)?, MTSetting<Bool>)] = [
            ("appearance.profile.showId", { MTStrings.Appearance.Profile.showId }, nil, MTAppearanceSettings.profileShowId),
            ("appearance.profile.showDataCenter", { MTStrings.Appearance.Profile.showDataCenter }, { MTStrings.Appearance.Profile.showDataCenterInfo }, MTAppearanceSettings.profileShowDataCenter),
            ("appearance.profile.showDates", { MTStrings.Appearance.Profile.showDates }, { MTStrings.Appearance.Profile.showDatesInfo }, MTAppearanceSettings.profileShowDates),
            ("appearance.profile.hideDescription", { MTStrings.Appearance.Profile.hideDescription }, nil, MTAppearanceSettings.profileHideDescription),
            ("appearance.profile.hideShareButton", { MTStrings.Appearance.Profile.hideShareButton }, nil, MTAppearanceSettings.profileHideShareButton),
            ("appearance.profile.hideStarRating", { MTStrings.Appearance.Profile.hideStarRating }, nil, MTAppearanceSettings.profileHideStarRating)
        ]
        var order = 100
        for (id, title, subtitle, setting) in rows {
            MTMenuRegistry.register(MTMenuRow(id: id, section: MTAppearanceMenu.profileInfo, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting))))
            order += 100
        }

        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: MTAppearanceMenu.profileBackground, screen: .tab(tab), order: 400, header: { MTStrings.Appearance.Background.profileHeader }, footer: { _ in MTStrings.Appearance.Background.profileFooter }))
        MTAppearanceMenu.registerBackgroundRows(kind: .profile, section: MTAppearanceMenu.profileBackground, idPrefix: "appearance.profileBackground")
    }
}
