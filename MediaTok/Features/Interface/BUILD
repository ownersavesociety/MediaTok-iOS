load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Feature module MTInterface. Owner: MediaTok.
# May depend on everything below TelegramUI; never on TelegramUI or another MT<Feature> module
#.
#
# Points/<Module>/ — extension points that compile INTO MediaTok's own (not frozen) upstream modules,
# the same way MTHooks/<Module>/ does for the frozen ones. Each such module also gets
# "//MediaTok/MTCore:MTCore" in its deps. MTInterface registers the handlers.

filegroup(
    name = "AvatarNodePointSources",
    srcs = glob(["Points/AvatarNode/**/*.swift"]),
    visibility = ["//submodules/AvatarNode:__pkg__"],
)

filegroup(
    name = "TabBarComponentPointSources",
    srcs = glob(["Points/TabBarComponent/**/*.swift"]),
    visibility = ["//submodules/TelegramUI/Components/TabBarComponent:__pkg__"],
)

filegroup(
    name = "ChatListTitleViewPointSources",
    srcs = glob(["Points/ChatListTitleView/**/*.swift"]),
    visibility = ["//submodules/TelegramUI/Components/ChatListTitleView:__pkg__"],
)

filegroup(
    name = "ChatTextInputActionButtonsNodePointSources",
    srcs = glob(["Points/ChatTextInputActionButtonsNode/**/*.swift"]),
    visibility = ["//submodules/TelegramUI/Components/Chat/ChatTextInputActionButtonsNode:__pkg__"],
)

filegroup(
    name = "EntityKeyboardPointSources",
    srcs = glob(["Points/EntityKeyboard/**/*.swift"]),
    visibility = ["//submodules/TelegramUI/Components/EntityKeyboard:__pkg__"],
)

filegroup(
    name = "TopMessageReactionsPointSources",
    srcs = glob(["Points/TopMessageReactions/**/*.swift"]),
    visibility = ["//submodules/TelegramUI/Components/Chat/TopMessageReactions:__pkg__"],
)

# Zone assets (the bundled island badge). Listed in the app's resources next to
# //MediaTok/MTSettingsUI:MTSettingsUIAssets in Telegram/BUILD.
filegroup(
    name = "MTInterfaceAssets",
    srcs = glob(["Assets/MTInterface.xcassets/**"]),
    visibility = ["//visibility:public"],
)

# MediaTok's alternate app icon; wired into Telegram/BUILD's alternate icons.
filegroup(
    name = "MediaTokAppIcon",
    srcs = glob(["Assets/AppIcons/MediaTok.alticon/*.png"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "MTInterface",
    module_name = "MTInterface",
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
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/AppBundle:AppBundle",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent:GlassBackgroundComponent",
        "//submodules/WallpaperBackgroundNode:WallpaperBackgroundNode",
        "//submodules/ContextUI:ContextUI",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/UndoUI:UndoUI",
        "//submodules/PromptUI:PromptUI",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/AvatarNode:AvatarNode",
        "//submodules/ChatListUI:ChatListUI",
        "//submodules/SettingsUI:SettingsUI",
        "//submodules/AttachmentTextInputPanelNode:AttachmentTextInputPanelNode",
        "//submodules/Utils/DeviceModel:DeviceModel",
        "//submodules/TelegramUI/Components/ChatListTitleView:ChatListTitleView",
        "//submodules/TelegramUI/Components/ChatListHeaderComponent:ChatListHeaderComponent",
        "//submodules/TelegramUI/Components/NavigationBarComponent:NavigationBarComponent",
        "//submodules/TelegramUI/Components/ChatList/ChatListFilterTabContainerNode:ChatListFilterTabContainerNode",
        "//submodules/TelegramUI/Components/TabBarComponent:TabBarComponent",
        "//submodules/TelegramUI/Components/EntityKeyboard:EntityKeyboard",
        "//submodules/TelegramUI/Components/EmojiStatusSelectionComponent:EmojiStatusSelectionComponent",
        "//submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen:PeerInfoScreen",
        "//submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode:ChatTextInputPanelNode",
        "//submodules/TelegramUI/Components/Chat/ChatTextInputActionButtonsNode:ChatTextInputActionButtonsNode",
        "//submodules/TelegramUI/Components/Chat/TopMessageReactions:TopMessageReactions",
        # The formatting toolbar formats through each composer directly (BUGHUNT UI-14).
        "//submodules/ChatPresentationInterfaceState:ChatPresentationInterfaceState",
        "//submodules/TelegramUI/Components/Chat/ChatInputTextNode:ChatInputTextNode",
        "//submodules/TelegramUI/Components/TextFieldComponent:TextFieldComponent",
        "//third-party/ZipArchive:ZipArchive",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests of «Скругление углов» (2026-10-27): only Sources/Settings/MTAvatarCorners.swift
# (Foundation). Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/Interface:MTAvatarCornersTests
swift_test(
    name = "MTAvatarCornersTests",
    srcs = [
        "Sources/Settings/MTAvatarCorners.swift",
    ] + glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
)
