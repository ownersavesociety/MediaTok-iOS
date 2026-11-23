load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feature module GGGhostMode. Owner: MediaTok (from wave 2 on this BUILD belongs to the owner).
# May depend on everything below TelegramUI; never on TelegramUI or another GG<Feature> module
#.
swift_library(
    name = "GGGhostMode",
    module_name = "GGGhostMode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/GGCore:GGCore",
        "//MediaTok/GGHooks:GGHooks",
        "//MediaTok/GGSettingsUI:GGSettingsUI",
        "//MediaTok/Features/Shared:GGFeaturesShared",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        # Explicit read receipts and "offline".
        "//submodules/MtProtoKit:MtProtoKit",
        # Exception screens, menu items, toasts and alerts.
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AlertUI:AlertUI",
        "//submodules/ContextUI:ContextUI",
        "//submodules/AppBundle:AppBundle",
        "//submodules/UndoUI:UndoUI",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        # GGChatListHooks (preview text of chats whose last message is hidden) compile into ChatListUI.
        "//submodules/ChatListUI:ChatListUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
