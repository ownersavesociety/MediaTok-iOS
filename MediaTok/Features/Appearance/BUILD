load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Owner: MediaTok. Two targets:
#
#   MTAppearanceSettings — the appearance settings and their snapshot. MTCore only, so the upstream
#                          modules that draw them (bubble background, status line, text formatting…)
#                          can read the registry directly, down to below TelegramCore.
#   MTAppearance         — the feature: menu rows, previews, theme transformer, bubble shape, fonts,
#                          chat overlays, chat-list header decorations, profile rows, imports, migration.
#                          May depend on everything below TelegramUI.
#
# No font files: the font choice offers only the fonts that ship with iOS.

swift_library(
    name = "MTAppearanceSettings",
    module_name = "MTAppearanceSettings",
    srcs = glob([
        "Settings/Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Compiled INTO ChatMessageItemImpl: the online dot on authors' avatars.
filegroup(
    name = "ChatMessageItemImplSources",
    srcs = glob([
        "Upstream/ChatMessageItemImpl/**/*.swift",
    ]),
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "MTAppearance",
    module_name = "MTAppearance",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":MTAppearanceSettings",
        "//MediaTok/MTCore:MTCore",
        "//MediaTok/MTHooks:MTHooks",
        "//MediaTok/MTSettingsUI:MTSettingsUI",
        "//MediaTok/Features/Shared:MTFeaturesShared",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/LegacyComponents:LegacyComponents",
        "//submodules/TelegramUI/Components/EdgeEffect:EdgeEffect",
        "//submodules/TelegramUI/Components/ChatListHeaderComponent:ChatListHeaderComponent",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AlertUI:AlertUI",
        "//submodules/PromptUI:PromptUI",
        "//submodules/AppBundle:AppBundle",
        "//submodules/UndoUI:UndoUI",
        # The sticker-size preview: the chat's wallpaper, the time format, the account's name.
        "//submodules/WallpaperBackgroundNode:WallpaperBackgroundNode",
        "//submodules/TextFormat:TextFormat",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/ContextUI:ContextUI",
        "//submodules/WebPBinding:WebPBinding",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//MediaTok/Features/Voice:MTVoiceDSP",
        "//submodules/OpusBinding:OpusBinding",
        "//submodules/UIKitRuntimeUtils:UIKitRuntimeUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests of the choices that replaced switch pairs and the screen-edge rows (2026-10-27):
# only Settings/Sources/MTAppearanceChoices.swift (Foundation). Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/Appearance:MTAppearanceChoicesTests
swift_test(
    name = "MTAppearanceChoicesTests",
    srcs = [
        "Settings/Sources/MTAppearanceChoices.swift",
        "Tests/MTAppearanceChoicesTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)
