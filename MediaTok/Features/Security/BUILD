load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feature module GGSecurity. Owner: MediaTok (from wave 2 on this BUILD belongs to the owner).
# May depend on everything below TelegramUI; never on TelegramUI or another GG<Feature> module
#.
swift_library(
    name = "GGSecurity",
    module_name = "GGSecurity",
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
        # MediaTok: chat lock, secret folder, account button, passcode extras, menu.
        "//submodules/AppBundle:AppBundle",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/ContextUI:ContextUI",
        "//submodules/AvatarNode:AvatarNode",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/UIKitRuntimeUtils:UIKitRuntimeUtils",
        "//submodules/PasscodeCore:PasscodeCore",
        "//submodules/PasscodeUI:PasscodeUI",
        "//submodules/SettingsUI:SettingsUI",
        "//submodules/ChatListUI:ChatListUI",
        "//submodules/TelegramUI/Components/ChatListHeaderComponent:ChatListHeaderComponent",
        "//submodules/TelegramUI/Components/NavigationBarComponent:NavigationBarComponent",
        "//submodules/TelegramUI/Components/PeerInfo/AccountPeerContextItem:AccountPeerContextItem",
    ],
    visibility = [
        "//visibility:public",
    ],
)
