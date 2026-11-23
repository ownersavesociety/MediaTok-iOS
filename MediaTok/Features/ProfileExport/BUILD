load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feature module MTProfileExport: nick badges (MediaTok), fake gifts, chat export. Owner: MediaTok.
# May depend on everything below TelegramUI; never on TelegramUI or another MT<Feature> module
#.
swift_library(
    name = "MTProfileExport",
    module_name = "MTProfileExport",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
        "//MediaTok/MTHooks:MTHooks",
        "//MediaTok/MTSettingsUI:MTSettingsUI",
        "//MediaTok/Features/Shared:MTFeaturesShared",
        ":MTNickBadgeSlot",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        # Screens: lists, inputs, alerts, toasts, context menus.
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AlertUI:AlertUI",
        "//submodules/UndoUI:UndoUI",
        "//submodules/ContextUI:ContextUI",
        # «Локальные звёзды»: the amount is typed into a prompt.
        "//submodules/PromptUI:PromptUI",
        "//submodules/AppBundle:AppBundle",
        # Badge slot in chat list rows (ChatListItemNode.titleNode) and the profile header
        # (ComponentHostView icons next to the name).
        "//submodules/ChatListUI:ChatListUI",
        "//submodules/ComponentFlow:ComponentFlow",
        # Names (displayTitle) and service message texts in bulletins, editors and the export.
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        # Fake gifts: the gift screen's menu point (MTGiftViewHooks) and Portals NFT marketplace browser.
        "//submodules/TelegramUI/Components/Gifts/GiftViewScreen:GiftViewScreen",
        "//submodules/TelegramUI/Components/Gifts/GiftStoreScreen:GiftStoreScreen",
        "//submodules/ConfettiEffect",
        # Chat export: the archive.
        "//third-party/ZipArchive:ZipArchive",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The slot next to a name where the nick badge is drawn: a provider point and one view. Light on
# purpose — ChatTitleView, ContactsPeerItem and PeerListItemComponent depend on it, so it must stay
# below all of them (MTCore, TelegramCore, AccountContext, Display only).
swift_library(
    name = "MTNickBadgeSlot",
    module_name = "MTNickBadgeSlot",
    srcs = glob([
        "BadgeSlot/Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/Display:Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The gift screen's menu point (MTGiftViewHooks), compiled INTO GiftViewScreen: it reads
# GiftViewScreen.Subject's internal `arguments`.
filegroup(
    name = "GiftViewScreenHookSources",
    srcs = glob([
        "GiftViewHooks/*.swift",
    ]),
    visibility = [
        "//submodules/TelegramUI/Components/Gifts/GiftViewScreen:__pkg__",
    ],
)
