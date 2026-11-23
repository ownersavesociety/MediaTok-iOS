load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatMessageSelectionInputPanelNode",
    module_name = "ChatMessageSelectionInputPanelNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramPresentationData",
        "//submodules/AppBundle",
        "//submodules/ChatPresentationInterfaceState",
        "//submodules/TelegramUI/Components/Chat/ChatInputPanelNode",
        "//submodules/TelegramUI/Components/EntityKeyboard",
        "//submodules/TelegramUI/Components/Chat/TopMessageReactions",
        "//submodules/ReactionSelectionNode",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        # MEDIATOK: Swiftgram-parity settings and points
        "//MediaTok/GGCore:GGCore",
        "//MediaTok/Features/Shared:GGFeaturesShared",
        "//MediaTok/Features/Extras:GGExtrasHooks",
    ],
    visibility = [
        "//visibility:public",
    ],
)
