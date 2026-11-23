load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Feature module MTAntiDelete. Owner: MediaTok (from wave 2 on this BUILD belongs to the owner).
# May depend on everything below TelegramUI; never on TelegramUI or another MT<Feature> module
#. The capture, the attributes and the index are in MTFeaturesShared
# (Sources/AntiDelete): the notification service links them too.
swift_library(
    name = "MTAntiDelete",
    module_name = "MTAntiDelete",
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
        "//submodules/ContextUI:ContextUI",
        "//submodules/PromptUI:PromptUI",
        "//submodules/Pasteboard:Pasteboard",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        # MTChatListHooks (chat list preview) and chatListFilterPredicate (folder exclusions).
        "//submodules/ChatListUI:ChatListUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The bookmark row under the chat search field. A separate small library because the upstream
# component ChatSearchNavigationContentNode links it: it may only
# depend on modules below that component, never on MTAntiDelete itself.
swift_library(
    name = "MTBookmarkSearchRow",
    module_name = "MTBookmarkSearchRow",
    srcs = glob([
        "SearchRow/Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
        "//MediaTok/Features/Shared:MTFeaturesShared",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/Display:Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests of the pure model of anti-delete: the index (logs, caps, pruning, pages,
# summaries), the inbox records of the notification service, the migration of the legacy MediaTok
# archive and the reply quote. Only those sources and MTCore are compiled, like MTCoreTests.
#   ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/AntiDelete:MTAntiDeleteTests
# The model sources live in MTFeaturesShared (Sources/AntiDelete/Model); the filegroup that exports
# them is requested from the orchestrator (MediaTok spec, P5).
swift_test(
    name = "MTAntiDeleteTests",
    srcs = glob([
        "Tests/**/*.swift",
    ]) + [
        "//MediaTok/Features/Shared:AntiDeleteModelSources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
    ],
)
