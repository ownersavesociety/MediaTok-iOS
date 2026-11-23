load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatTextInputActionButtonsNode",
    module_name = "ChatTextInputActionButtonsNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        # MEDIATOK: composer points of MediaTok (input bar geometry, formatting toolbar)
        "//MediaTok/Features/Interface:ChatTextInputActionButtonsNodePointSources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/ContextUI",
        "//submodules/ChatPresentationInterfaceState",
        "//submodules/ChatMessageBackground",
        "//submodules/TelegramUI/Components/ChatControllerInteraction",
        "//submodules/AccountContext",
        "//submodules/TelegramUI/Components/ChatTextInputMediaRecordingButton",
        "//submodules/TelegramUI/Components/ChatSendButtonRadialStatusNode",
        "//submodules/ChatSendMessageActionUI",
        "//submodules/ComponentFlow",
        "//submodules/AnimatedCountLabelNode",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        "//submodules/TelegramUI/Components/StarsParticleEffect",
        # MEDIATOK: hook points
        "//MediaTok/GGCore:GGCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
