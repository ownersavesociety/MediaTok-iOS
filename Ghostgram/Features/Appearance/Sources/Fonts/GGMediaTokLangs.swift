import Foundation
import UIKit
import TelegramPresentationData
import GGCore
import GGHooks
import GGSettingsUI

/// Full Language Studio for MediaTok iOS:
/// 1) 66 verified live public Telegram language packs (tg://setlanguage?lang=...)
/// 2) 4 instant offline MediaTok presets ("Живой / Умер", "Киберпанк", "Царский", "Кошачий")
/// 3) Full-client runtime string override editor over ALL ~5,500+ iOS PresentationStrings keys (applied LIVE via GGThemeHooks.invalidate!)
enum GGMediaTokLangs {
    private static let defaultsKey = "mediatok.lang.overrides"

    struct PublicPack {
        let slug: String
        let title: String
        let desc: String
        let category: String
    }

    static let publicPacks: [PublicPack] = [
        // Мемы и сленг
        PublicPack(slug: "therussianslang", title: "Сленг", desc: "Разговорный молодёжный сленг", category: "Мемы и сленг"),
        PublicPack(slug: "idontno1", title: "Смешной без мата", desc: "Мега смешной перевод без мата", category: "Мемы и сленг"),
        PublicPack(slug: "userfriendly", title: "Несерьёзный", desc: "Меньше официальности, больше кайфа", category: "Мемы и сленг"),
        PublicPack(slug: "rusmltrs", title: "всё с маленькой буквы", desc: "Эстетичный минимализм без заглавных", category: "Мемы и сленг"),
        PublicPack(slug: "mymylang", title: "вацап.", desc: "Маленькими буквами и с точкой.", category: "Мемы и сленг"),
        PublicPack(slug: "iseeyouforevernow", title: "оно говорит со мной?", desc: "Криповый сломанный стиль", category: "Мемы и сленг"),
        PublicPack(slug: "sadnesssad", title: "Печальный язык", desc: "Грустный вайб для всего ТГ", category: "Мемы и сленг"),
        PublicPack(slug: "shizoid", title: "Шизоид", desc: "Ироничный мемный интерфейс", category: "Мемы и сленг"),
        PublicPack(slug: "abobusgram", title: "Абобусграм", desc: "Мемный стиль Абобус", category: "Мемы и сленг"),
        PublicPack(slug: "draining", title: "Drain / Дед-инсайд", desc: "Мрачный дрейн-стиль", category: "Мемы и сленг"),
        PublicPack(slug: "tokianghoul", title: "Ghoul (Дед инсайд)", desc: "Для настоящих гулей 1000-7", category: "Мемы и сленг"),
        PublicPack(slug: "piratesss", title: "PiRaTeS", desc: "Пиратский стиль интерфейса", category: "Мемы и сленг"),
        PublicPack(slug: "goblincoore", title: "Goblincore", desc: "Лёгкий язык с гоблинами без мата", category: "Мемы и сленг"),
        PublicPack(slug: "akademiad", title: "Dark Academia", desc: "Тёмная академия и эстетика", category: "Мемы и сленг"),
        PublicPack(slug: "churchwex", title: "Церковный", desc: "Церковно-духовный стиль", category: "Мемы и сленг"),
        PublicPack(slug: "udiikwoheh", title: "Нефорский", desc: "Альтернативный сленг", category: "Мемы и сленг"),
        PublicPack(slug: "syrncorelanguage", title: "Русский + секунды", desc: "Точное время с секундами", category: "Мемы и сленг"),
        PublicPack(slug: "teamgram", title: "Tgram (уютный + сек.)", desc: "Уютный перевод с секундами", category: "Мемы и сленг"),
        PublicPack(slug: "tmngram", title: "ТюменьГрам", desc: "Шуточный региональный перевод", category: "Мемы и сленг"),
        PublicPack(slug: "russianbyg02m0n1k", title: "Шуточный от G02m0n1k", desc: "Известные фразы и шутки", category: "Мемы и сленг"),

        // Котики и милые
        PublicPack(slug: "kiska", title: "Киска / Кошачий", desc: "Мяу-интерфейс и котики", category: "Котики и милые"),
        PublicPack(slug: "catttish", title: "Catttish", desc: "Кошачий сленг", category: "Котики и милые"),
        PublicPack(slug: "meowtg", title: "MeowTG", desc: "Мурлыкающий Telegram", category: "Котики и милые"),
        PublicPack(slug: "liffan", title: "Kotiki", desc: "Язык с котиками от Liffan", category: "Котики и милые"),
        PublicPack(slug: "krutyshka", title: "Крутышка и котики", desc: "Милый стиль с котиками", category: "Котики и милые"),
        PublicPack(slug: "fluffyru", title: "Пуфыстенький", desc: "Фуррёвый мягкий перевод", category: "Котики и милые"),
        PublicPack(slug: "burviss", title: "Nyan", desc: "Котики и лёгкий сленг :з", category: "Котики и милые"),
        PublicPack(slug: "ruwussian", title: "РУвУсский (UwU)", desc: "Милый UwU / аниме-стиль", category: "Котики и милые"),
        PublicPack(slug: "angeltoangels", title: "Angel Tongue", desc: "Ангелочки, котики, каомодзи", category: "Котики и милые"),
        PublicPack(slug: "sad0vira1", title: "Садовый рай", desc: "Цветочная тематика без мата", category: "Котики и милые"),
        PublicPack(slug: "krasotcka", title: "Tigers", desc: "Для любителей тигров", category: "Котики и милые"),

        // Игры
        PublicPack(slug: "stalkeryazik", title: "S.T.A.L.K.E.R.", desc: "Call of The Zone (Зона)", category: "Игры"),
        PublicPack(slug: "atomicheart20", title: "Atomic Heart", desc: "Вселенная игры Atomic Heart", category: "Игры"),
        PublicPack(slug: "modernwarfare", title: "Call of Duty: MW", desc: "Стиль оригинальной трилогии MW", category: "Игры"),
        PublicPack(slug: "borderland", title: "Borderlands", desc: "Язык Пандоры и Искателей", category: "Игры"),
        PublicPack(slug: "binding-of-isaac", title: "The Binding of Isaac", desc: "Абадоооон / стиль Айзека", category: "Игры"),
        PublicPack(slug: "genshin-8", title: "Genshin Impact", desc: "Перевод по Геншину", category: "Игры"),
        PublicPack(slug: "ultimatehope228", title: "Danganronpa", desc: "Отчаяние и надежда", category: "Игры"),

        // Аниме и кино
        PublicPack(slug: "naturo", title: "Наруто (Синоби)", desc: "Перевод по вселенной Наруто", category: "Аниме и кино"),
        PublicPack(slug: "evang3li0n", title: "Evangelion", desc: "По Евангелиону без мата", category: "Аниме и кино"),
        PublicPack(slug: "jjba", title: "JoJo's Bizarre Adv.", desc: "Аниме-стиль ДжоДжо", category: "Аниме и кино"),
        PublicPack(slug: "bleach", title: "Bleach", desc: "Аниме-стиль Блич", category: "Аниме и кино"),
        PublicPack(slug: "tokiiiio", title: "Токийские мстители", desc: "Перевод по Tokyo Revengers", category: "Аниме и кино"),
        PublicPack(slug: "bungoustraydogslang", title: "Бродячие псы", desc: "Bungou Stray Dogs", category: "Аниме и кино"),
        PublicPack(slug: "middle-earths", title: "Средиземье", desc: "Властелин колец и Хоббит", category: "Аниме и кино"),
        PublicPack(slug: "marvel-ru", title: "Marvel", desc: "Вселенная супергероев Marvel", category: "Аниме и кино"),
        PublicPack(slug: "fightclublmf", title: "Бойцовский клуб", desc: "Первое правило клуба...", category: "Аниме и кино"),
        PublicPack(slug: "223222", title: "Пираты Карибского моря", desc: "Йо-хо-хо и ром", category: "Аниме и кино"),
        PublicPack(slug: "supernaturallanguage", title: "Сверхъестественное", desc: "Для фанатов Винчестеров", category: "Аниме и кино"),
        PublicPack(slug: "katamaranovian", title: "Внутри Лапенко", desc: "Катамарановский стиль", category: "Аниме и кино"),
        PublicPack(slug: "metal-femily", title: "Metal Family", desc: "Перевод по Metal Family", category: "Аниме и кино"),

        // Исторические и коды
        PublicPack(slug: "oldrus111", title: "Дореформенный Русскій", desc: "ѣ, ѳ, і и твёрдые знаки", category: "Исторические и коды"),
        PublicPack(slug: "classicrussian", title: "Русскiй (царский)", desc: "Дореволюционная стилистика", category: "Исторические и коды"),
        PublicPack(slug: "vahtang", title: "Старославянский", desc: "Древнерусский слог", category: "Исторические и коды"),
        PublicPack(slug: "glagol", title: "Глаголица", desc: "Первый славянский алфавит", category: "Исторические и коды"),
        PublicPack(slug: "aprelteam", title: "Советский (СССР)", desc: "Товарищи и комсомол", category: "Исторические и коды"),
        PublicPack(slug: "ilovecp1251", title: "бНОПНЯ (CP1251)", desc: "Сломанная кодировка из 2000-х", category: "Исторические и коды"),
        PublicPack(slug: "koi7codemap", title: "KOI-7 H1", desc: "Ретро-транслит кодировка", category: "Исторические и коды"),

        // 18+ приколы
        PublicPack(slug: "dblogrm", title: "DebiloGram (18+)", desc: "Мемный перевод с матом", category: "18+ приколы"),
        PublicPack(slug: "ebllogram-ru", title: "Еблограм (18+)", desc: "Легендарный Еблограм", category: "18+ приколы"),
        PublicPack(slug: "dlgram", title: "Долбограм (18+)", desc: "Жёсткий сленг и угар", category: "18+ приколы"),
        PublicPack(slug: "piizdosgram", title: "Пиздосграм (18+)", desc: "Поэзия из матов", category: "18+ приколы"),
        PublicPack(slug: "dpxlwop", title: "Ахуительный язык (18+)", desc: "Прикольчики и мат", category: "18+ приколы"),
        PublicPack(slug: "govor", title: "ТоксикРашн (18+)", desc: "Максимальная токсичность", category: "18+ приколы"),
        PublicPack(slug: "chillish", title: "Chill language (18+)", desc: "Шуточный перевод на чилле", category: "18+ приколы"),
        PublicPack(slug: "poshlatina343", title: "Премиум телега (18+)", desc: "Забавный перевод + секунды", category: "18+ приколы")
    ]

    static let popularKeys: [(key: String, label: String)] = [
        ("Presence.online", "В сети"),
        ("LastSeen.Lately", "Был(а) недавно"),
        ("LastSeen.JustNow", "Был(а) только что"),
        ("LastSeen.TodayAt", "Был(а) сегодня в %@"),
        ("LastSeen.YesterdayAt", "Был(а) вчера в %@"),
        ("LastSeen.AtDate", "Был(а) %@"),
        ("LastSeen.WithinAWeek", "Был(а) на этой неделе"),
        ("LastSeen.WithinAMonth", "Был(а) в этом месяце"),
        ("LastSeen.ALongTimeAgo", "Был(а) очень давно"),
        ("LastSeen.Offline", "Офлайн"),
        ("DialogList.Typing", "Печатает (в списке)"),
        ("Conversation.typing", "Печатает (в чате)"),
        ("Activity.RecordingAudio", "Записывает голосовое"),
        ("Activity.UploadingPhoto", "Отправляет фото"),
        ("Activity.UploadingVideo", "Отправляет видео"),
        ("Activity.UploadingDocument", "Отправляет файл"),
        ("DialogList.SavedMessages", "Избранное"),
        ("ChatList.Archive", "Архив"),
        ("DialogList.Title", "Чаты"),
        ("Conversation.InputTextPlaceholder", "Поле «Сообщение»"),
        ("Conversation.ContextMenuReply", "Ответить"),
        ("Conversation.ContextMenuForward", "Переслать"),
        ("Conversation.ContextMenuCopy", "Копировать"),
        ("Conversation.ContextMenuDelete", "Удалить"),
        ("Conversation.MessageEditedLabel", "Пометка «изменено»"),
        ("DialogList.Draft", "Черновик"),
        ("Settings.Title", "Настройки"),
        ("Contacts.Title", "Контакты"),
        ("Calls.TabTitle", "Звонки"),
        ("Common.Search", "Поиск"),
        ("User.DeletedAccount", "Удалённый аккаунт"),
        ("Bot.GenericBotStatus", "Бот"),
        ("Conversation.BlockUser", "Заблокировать"),
        ("Conversation.UnblockUser", "Разблокировать"),
        ("Common.Done", "Готово"),
        ("Common.Cancel", "Отмена"),
        ("Common.Close", "Закрыть")
    ]

    static let presets: [(name: String, map: [String: String])] = [
        ("Живой / Умер 💀", [
            "Presence.online": "живой 🟢",
            "LastSeen.Lately": "умер 💀",
            "LastSeen.JustNow": "только что дышал",
            "LastSeen.TodayAt": "был живой сегодня в %@",
            "LastSeen.YesterdayAt": "умер вчера в %@",
            "LastSeen.AtDate": "умер %@",
            "LastSeen.WithinAWeek": "сдох на неделе 💀",
            "LastSeen.WithinAMonth": "разлагается месяц 🪦",
            "LastSeen.ALongTimeAgo": "давно в гробу ⚰️",
            "LastSeen.Offline": "умер 💀",
            "DialogList.Typing": "строчит бред",
            "Conversation.typing": "строчит бред",
            "Activity.RecordingAudio": "ноет в микро",
            "Activity.UploadingPhoto": "кидает фотку",
            "Activity.UploadingVideo": "кидает видос",
            "DialogList.SavedMessages": "Тайник",
            "ChatList.Archive": "Свалка",
            "DialogList.Title": "Тёрки",
            "Conversation.InputTextPlaceholder": "Чиркани чё-нить...",
            "Conversation.ContextMenuReply": "Ответить по факту",
            "Conversation.ContextMenuForward": "Слить",
            "Conversation.ContextMenuCopy": "Скопипастить",
            "Conversation.ContextMenuDelete": "Сжечь",
            "Conversation.MessageEditedLabel": "переобулся",
            "DialogList.Draft": "Недописал",
            "Settings.Title": "Крутилки",
            "Contacts.Title": "Кенты",
            "Calls.TabTitle": "Звонилка",
            "Common.Search": "Шерлок",
            "User.DeletedAccount": "Призрак 👻",
            "Bot.GenericBotStatus": "железяка 🤖",
            "Conversation.BlockUser": "В бан",
            "Conversation.UnblockUser": "Помиловать"
        ]),
        ("Киберпанк 2077 ⚡", [
            "Presence.online": "[ONLINE // ACTIVE]",
            "LastSeen.Lately": "[OFFLINE // SIGNAL LOST]",
            "LastSeen.WithinAWeek": "[OFFLINE > 7D]",
            "LastSeen.WithinAMonth": "[OFFLINE > 30D]",
            "LastSeen.ALongTimeAgo": "[NODE TERMINATED]",
            "LastSeen.Offline": "[OFFLINE]",
            "DialogList.Typing": "[INJECTING PAYLOAD]",
            "Conversation.typing": "[INJECTING PAYLOAD]",
            "Activity.RecordingAudio": "[AUDIO STREAM]",
            "DialogList.SavedMessages": "VAULT // LOCAL",
            "ChatList.Archive": "COLD STORAGE",
            "Conversation.InputTextPlaceholder": "> input_command...",
            "Conversation.ContextMenuDelete": "PURGE",
            "Conversation.MessageEditedLabel": "patched",
            "Settings.Title": "SYS_CONFIG",
            "Contacts.Title": "NET_PEERS",
            "User.DeletedAccount": "GHOST_NODE",
            "Bot.GenericBotStatus": "AI_DAEMON"
        ]),
        ("Царскій 👑", [
            "Presence.online": "въ сѣти",
            "LastSeen.Lately": "почивалъ намедни",
            "LastSeen.WithinAWeek": "не видать съ седмицы",
            "LastSeen.ALongTimeAgo": "канулъ въ Лету",
            "LastSeen.Offline": "не въ сѣти",
            "DialogList.Typing": "изволитъ писать",
            "Conversation.typing": "изволитъ писать",
            "Activity.RecordingAudio": "глаголетъ въ трубу",
            "DialogList.SavedMessages": "Сундукъ",
            "ChatList.Archive": "Чуланъ",
            "Conversation.InputTextPlaceholder": "Начертать грамоту...",
            "Conversation.ContextMenuReply": "Отвѣтствовать",
            "Conversation.ContextMenuDelete": "Предати огню",
            "Settings.Title": "Уложеніе",
            "Contacts.Title": "Знакомцы",
            "User.DeletedAccount": "Усопшій аккъ"
        ]),
        ("Кошачий / Мяу 🐾", [
            "Presence.online": "мурлычет в сети 🐱",
            "LastSeen.Lately": "спит на батарее 💤",
            "LastSeen.WithinAWeek": "ушёл гулять по крышам",
            "LastSeen.ALongTimeAgo": "убежал в которай",
            "LastSeen.Offline": "спит 💤",
            "DialogList.Typing": "тыгыдыкает по клаве",
            "Conversation.typing": "тыгыдыкает по клаве",
            "Activity.RecordingAudio": "мяукает в микро",
            "DialogList.SavedMessages": "Коробка 📦",
            "ChatList.Archive": "Лоток",
            "Conversation.InputTextPlaceholder": "Мяукнуть...",
            "Conversation.ContextMenuDelete": "Закопать",
            "Conversation.MessageEditedLabel": "перемяукал",
            "Settings.Title": "Когтеточка",
            "Contacts.Title": "Котики 🐾",
            "User.DeletedAccount": "Призрачный кот"
        ])
    ]

    static var overrides: [String: String] {
        return (UserDefaults.standard.dictionary(forKey: GGMediaTokLangs.defaultsKey) as? [String: String]) ?? [:]
    }

    static var overrideCount: Int {
        return GGMediaTokLangs.overrides.count
    }

    static func saveOverrides(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: GGMediaTokLangs.defaultsKey)
        GGThemeHooks.invalidate()
    }

    static func register() {
        GGThemeHooks.presentationData.register({ presentationData, _ in
            return GGMediaTokLangs.applyOverrides(to: presentationData)
        }, order: 50)
    }

    private static func applyOverrides(to presentationData: PresentationData) -> PresentationData {
        let custom = GGMediaTokLangs.overrides
        guard !custom.isEmpty else {
            return presentationData
        }
        let primary = presentationData.strings.primaryComponent
        let secondaryDict = presentationData.strings.secondaryComponent?.dict
        var merged = primary.dict
        for (k, v) in custom where !v.isEmpty {
            let orig = primary.dict[k] ?? secondaryDict?[k] ?? ""
            if GGMediaTokCoreLogic.isFormatSafe(original: orig, candidate: v) {
                merged[k] = v
            }
        }
        let newPrimary = PresentationStrings.Component(
            languageCode: primary.languageCode,
            localizedName: primary.localizedName,
            pluralizationRulesCode: primary.pluralizationRulesCode,
            dict: merged
        )
        let newStrings = PresentationStrings(
            primaryComponent: newPrimary,
            secondaryComponent: presentationData.strings.secondaryComponent,
            groupingSeparator: presentationData.strings.groupingSeparator
        )
        return PresentationData(
            strings: newStrings,
            theme: presentationData.theme,
            autoNightModeTriggered: presentationData.autoNightModeTriggered,
            chatWallpaper: presentationData.chatWallpaper,
            chatFontSize: presentationData.chatFontSize,
            chatBubbleCorners: presentationData.chatBubbleCorners,
            listsFontSize: presentationData.listsFontSize,
            dateTimeFormat: presentationData.dateTimeFormat,
            nameDisplayOrder: presentationData.nameDisplayOrder,
            nameSortOrder: presentationData.nameSortOrder,
            reduceMotion: presentationData.reduceMotion,
            largeEmoji: presentationData.largeEmoji
        )
    }

    static func presentStudio(context: GGMenuContext) {
        var baseDict = context.presentationData.strings.secondaryComponent?.dict ?? [:]
        for (k, v) in context.presentationData.strings.primaryComponent.dict {
            baseDict[k] = v
        }
        let openPack: (String) -> Void = { slug in
            context.openTelegramLink("https://t.me/setlanguage/\(slug)")
        }
        let vc = GGLangStudioViewController(baseDict: baseDict, openPack: openPack)
        vc.overrideUserInterfaceStyle = .dark
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        nav.modalPresentationStyle = .pageSheet
        context.presentNative(nav)
    }
}

private final class GGLangStudioViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let baseDict: [String: String]
    private let openPack: (String) -> Void
    private var currentTab = 0      // 0 = Catalog(66) + Presets, 1 = Own Language (curated groups), 2 = Export/Import
    private var editorFilter = 0    // 0 = Curated groups, 1 = Modified only
    private var query = ""

    private static let curatedSections: [(title: String, keys: [(key: String, label: String)])] = [
        ("Статусы и активность", [
            ("Presence.online", "В сети"),
            ("LastSeen.Lately", "Был(а) недавно"),
            ("LastSeen.JustNow", "Был(а) только что"),
            ("LastSeen.TodayAt", "Был(а) сегодня в %@"),
            ("LastSeen.YesterdayAt", "Был(а) вчера в %@"),
            ("LastSeen.Offline", "Офлайн"),
            ("DialogList.Typing", "Печатает (в списке)"),
            ("Conversation.typing", "Печатает (в чате)"),
            ("Activity.RecordingAudio", "Записывает голосовое"),
            ("Activity.UploadingPhoto", "Отправляет фото"),
            ("Activity.UploadingVideo", "Отправляет видео")
        ]),
        ("Главный экран и вкладки", [
            ("DialogList.Title", "Чаты"),
            ("Contacts.Title", "Контакты"),
            ("Calls.TabTitle", "Звонки"),
            ("Settings.Title", "Настройки"),
            ("DialogList.SavedMessages", "Избранное"),
            ("ChatList.Archive", "Архив"),
            ("Common.Search", "Поиск"),
            ("DialogList.Draft", "Черновик")
        ]),
        ("Внутри чата", [
            ("Conversation.InputTextPlaceholder", "Поле «Сообщение»"),
            ("Conversation.MessageEditedLabel", "Пометка «изменено»"),
            ("Conversation.ContextMenuReply", "Ответить"),
            ("Conversation.ContextMenuForward", "Переслать"),
            ("Conversation.ContextMenuCopy", "Копировать"),
            ("Conversation.ContextMenuDelete", "Удалить")
        ]),
        ("Профиль и статусы аккаунта", [
            ("User.DeletedAccount", "Удалённый аккаунт"),
            ("Bot.GenericBotStatus", "Бот"),
            ("Conversation.BlockUser", "Заблокировать"),
            ("Conversation.UnblockUser", "Разблокировать")
        ])
    ]

    private var filteredPacks: [GGMediaTokLangs.PublicPack] = GGMediaTokLangs.publicPacks
    private var visibleEditorSections: [(title: String, keys: [(key: String, label: String)])] = []

    private let tabControl = UISegmentedControl(items: ["Каталог (66)", "Свой язык", ".mtlang"])
    private let filterControl = UISegmentedControl(items: ["Основные", "Изменённые"])
    private let previewBanner = UILabel()
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(baseDict: [String: String], openPack: @escaping (String) -> Void) {
        self.baseDict = baseDict
        self.openPack = openPack
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
        self.title = "Языки MediaTok"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closeTapped))

        self.tabControl.selectedSegmentIndex = 0
        self.tabControl.addTarget(self, action: #selector(self.tabChanged), for: .valueChanged)

        self.filterControl.selectedSegmentIndex = 0
        self.filterControl.addTarget(self, action: #selector(self.filterChanged), for: .valueChanged)

        self.previewBanner.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        self.previewBanner.textColor = .secondaryLabel
        self.previewBanner.backgroundColor = .secondarySystemGroupedBackground
        self.previewBanner.layer.cornerRadius = 10.0
        self.previewBanner.clipsToBounds = true
        self.previewBanner.textAlignment = .center
        self.previewBanner.numberOfLines = 2
        self.previewBanner.heightAnchor.constraint(equalToConstant: 44.0).isActive = true

        self.searchBar.delegate = self
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.placeholder = "Поиск пака или фразы..."

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = .onDrag

        let topStack = UIStackView(arrangedSubviews: [self.tabControl, self.filterControl, self.previewBanner, self.searchBar])
        topStack.axis = .vertical
        topStack.spacing = 6.0
        topStack.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(topStack)
        self.view.addSubview(self.tableView)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 8.0),
            topStack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 12.0),
            topStack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -12.0),
            self.tableView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 4.0),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.refreshData()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func tabChanged() {
        self.currentTab = self.tabControl.selectedSegmentIndex
        self.refreshData()
    }

    @objc private func filterChanged() {
        self.editorFilter = self.filterControl.selectedSegmentIndex
        self.refreshData()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.refreshData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    private func refreshData() {
        let overrides = GGMediaTokLangs.overrides
        self.filterControl.isHidden = (self.currentTab != 1)
        self.previewBanner.isHidden = (self.currentTab != 1)
        self.searchBar.isHidden = (self.currentTab == 2)
        self.filterControl.setTitle("Изменённые (\(overrides.count))", forSegmentAt: 1)

        let onlineText = overrides["Presence.online"] ?? self.baseDict["Presence.online"] ?? "в сети"
        let inputText = overrides["Conversation.InputTextPlaceholder"] ?? self.baseDict["Conversation.InputTextPlaceholder"] ?? "Сообщение"
        self.previewBanner.text = "Превью: Анна · \(onlineText)   |   «\(inputText)»"

        if self.currentTab == 0 {
            if self.query.isEmpty {
                self.filteredPacks = GGMediaTokLangs.publicPacks
            } else {
                self.filteredPacks = GGMediaTokLangs.publicPacks.filter {
                    $0.title.lowercased().contains(self.query) ||
                    $0.desc.lowercased().contains(self.query) ||
                    $0.category.lowercased().contains(self.query) ||
                    $0.slug.lowercased().contains(self.query)
                }
            }
        } else if self.currentTab == 1 {
            if self.editorFilter == 1 {
                let knownLabels = Dictionary(uniqueKeysWithValues: GGMediaTokLangs.popularKeys.map { ($0.key, $0.label) })
                let items: [(key: String, label: String)] = overrides.keys.sorted().compactMap { k in
                    let label = knownLabels[k] ?? k
                    let val = overrides[k] ?? ""
                    let orig = self.baseDict[k] ?? ""
                    if !self.query.isEmpty && !label.lowercased().contains(self.query) && !val.lowercased().contains(self.query) && !orig.lowercased().contains(self.query) {
                        return nil
                    }
                    return (k, label)
                }
                self.visibleEditorSections = items.isEmpty ? [] : [("Изменённые фразы (\(items.count))", items)]
            } else {
                var built: [(title: String, keys: [(key: String, label: String)])] = []
                for sec in GGLangStudioViewController.curatedSections {
                    let matching = sec.keys.filter { item in
                        if self.query.isEmpty { return true }
                        let orig = (self.baseDict[item.key] ?? "").lowercased()
                        let ov = (overrides[item.key] ?? "").lowercased()
                        return item.label.lowercased().contains(self.query) || orig.contains(self.query) || ov.contains(self.query)
                    }
                    if !matching.isEmpty {
                        built.append((sec.title, matching))
                    }
                }
                self.visibleEditorSections = built
            }
        }
        self.tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        if self.currentTab == 0 {
            return self.query.isEmpty ? 2 : 1
        }
        if self.currentTab == 1 {
            return max(1, self.visibleEditorSections.count)
        }
        return 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if self.currentTab == 0 {
            if self.query.isEmpty && section == 0 {
                return "Быстрые стили интерфейса (офлайн, сразу)"
            }
            return "Публичные языки Telegram (\(self.filteredPacks.count))"
        } else if self.currentTab == 1 {
            if self.visibleEditorSections.isEmpty {
                return "Нет изменённых фраз — выберите любую в «Основные»"
            }
            return self.visibleEditorSections[section].title
        }
        return "Экспорт и импорт своего языка (.mtlang JSON)"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.currentTab == 0 {
            if self.query.isEmpty && section == 0 {
                return GGMediaTokLangs.presets.count
            }
            return self.filteredPacks.count
        } else if self.currentTab == 1 {
            if self.visibleEditorSections.isEmpty {
                return 0
            }
            return self.visibleEditorSections[section].keys.count
        }
        return 3
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.textLabel?.numberOfLines = 1
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .none

        if self.currentTab == 0 {
            if self.query.isEmpty && indexPath.section == 0 {
                let preset = GGMediaTokLangs.presets[indexPath.row]
                cell.textLabel?.text = preset.name
                cell.detailTextLabel?.text = "Онлайн → «\(preset.map["Presence.online"] ?? "")» · Офлайн → «\(preset.map["LastSeen.Lately"] ?? "")» (\(preset.map.count) фраз)"
                cell.accessoryType = .disclosureIndicator
            } else {
                let pack = self.filteredPacks[indexPath.row]
                cell.textLabel?.text = "\(pack.title)  [\(pack.category)]"
                cell.detailTextLabel?.text = "\(pack.desc) · t.me/setlanguage/\(pack.slug)"
                cell.accessoryType = .disclosureIndicator
            }
        } else if self.currentTab == 1 {
            let item = self.visibleEditorSections[indexPath.section].keys[indexPath.row]
            let orig = self.baseDict[item.key] ?? item.label
            let custom = GGMediaTokLangs.overrides[item.key]
            cell.textLabel?.text = item.label
            cell.detailTextLabel?.text = custom != nil ? "\(orig)  →  \(custom ?? "")" : orig
            cell.accessoryType = custom != nil ? .checkmark : .disclosureIndicator
        } else {
            let count = GGMediaTokLangs.overrideCount
            if indexPath.row == 0 {
                cell.textLabel?.text = "Скопировать мой язык в буфер (\(count) фраз)"
                cell.detailTextLabel?.text = "JSON-словарь .mtlang — можно скинуть другу"
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Импортировать язык из буфера обмена"
                cell.detailTextLabel?.text = "Вставит JSON и сразу применит без перезапуска"
            } else {
                cell.textLabel?.text = "Сбросить все правки языка (\(count))"
                cell.detailTextLabel?.text = "Вернуть стандартные строки"
                cell.textLabel?.textColor = .systemRed
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if self.currentTab == 0 {
            if self.query.isEmpty && indexPath.section == 0 {
                let preset = GGMediaTokLangs.presets[indexPath.row]
                var merged = GGMediaTokLangs.overrides
                for (k, v) in preset.map { merged[k] = v }
                GGMediaTokLangs.saveOverrides(merged)
                self.refreshData()
                self.showAlert(title: "Применено!", message: "Стиль «\(preset.name)» (\(preset.map.count) фраз) активен сразу!")
            } else {
                let pack = self.filteredPacks[indexPath.row]
                let openPack = self.openPack
                self.dismiss(animated: true) {
                    openPack(pack.slug)
                }
            }
        } else if self.currentTab == 1 {
            guard indexPath.section < self.visibleEditorSections.count else { return }
            let item = self.visibleEditorSections[indexPath.section].keys[indexPath.row]
            let orig = self.baseDict[item.key] ?? item.label
            let current = GGMediaTokLangs.overrides[item.key] ?? orig
            let hint = orig.contains("%") ? "\nСохраняй подстановки вроде %@ (туда подставляется время)." : ""
            let alert = UIAlertController(title: item.label, message: "Сейчас: «\(orig)»\(hint)", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.text = current
                tf.placeholder = orig
            }
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak self, weak alert] _ in
                guard let strongSelf = self else { return }
                let newVal = alert?.textFields?.first?.text ?? ""
                var map = GGMediaTokLangs.overrides
                if newVal.isEmpty || newVal == orig {
                    map.removeValue(forKey: item.key)
                } else if !GGMediaTokCoreLogic.isFormatSafe(original: orig, candidate: newVal) {
                    strongSelf.showAlert(
                        title: "Небезопасный формат",
                        message: "В переводе должны точно совпадать подстановки из оригинала (например %@ или %d), а %s и %n запрещены, чтобы клиент не вылетал."
                    )
                    return
                } else {
                    map[item.key] = newVal
                }
                GGMediaTokLangs.saveOverrides(map)
                strongSelf.refreshData()
            }))
            alert.addAction(UIAlertAction(title: "Сбросить", style: .destructive, handler: { [weak self] _ in
                guard let strongSelf = self else { return }
                var map = GGMediaTokLangs.overrides
                map.removeValue(forKey: item.key)
                GGMediaTokLangs.saveOverrides(map)
                strongSelf.refreshData()
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            GGModalPresenter.presentWhenReady(alert, from: self)
        } else {
            if indexPath.row == 0 {
                if let data = try? JSONSerialization.data(withJSONObject: GGMediaTokLangs.overrides, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    UIPasteboard.general.string = str
                    self.showAlert(title: "Скопировано", message: "Язык (\(GGMediaTokLangs.overrideCount) фраз) скопирован в буфер обмена.")
                }
            } else if indexPath.row == 1 {
                guard let raw = UIPasteboard.general.string,
                      raw.count <= 2_000_000,
                      let data = raw.data(using: .utf8),
                      let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
                      dict.count <= 20_000 else {
                    self.showAlert(title: "Ошибка", message: "В буфере обмена нет корректного JSON языка (или он слишком большой).")
                    return
                }
                var merged = GGMediaTokLangs.overrides
                var count = 0
                var skipped = 0
                for (k, v) in dict where !k.isEmpty && !v.isEmpty {
                    let orig = self.baseDict[k] ?? ""
                    if GGMediaTokCoreLogic.isFormatSafe(original: orig, candidate: v) {
                        merged[k] = v
                        count += 1
                    } else {
                        skipped += 1
                    }
                }
                GGMediaTokLangs.saveOverrides(merged)
                self.refreshData()
                let extra = skipped > 0 ? "\nПропущено небезопасных строк: \(skipped)." : ""
                self.showAlert(title: "Импортировано", message: "Применено \(count) фраз сразу!\(extra)")
            } else {
                GGMediaTokLangs.saveOverrides([:])
                self.refreshData()
                self.showAlert(title: "Сброшено", message: "Все правки языка сброшены к оригиналу.")
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        GGModalPresenter.presentWhenReady(alert, from: self)
    }
}
