load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TopMessageReactions",
    module_name = "TopMessageReactions",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        # MEDIATOK: own recent reactions point
        "//MediaTok/Features/Interface:TopMessageReactionsPointSources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/AccountContext",
        "//submodules/ReactionSelectionNode",
        # MEDIATOK: hook points
        "//MediaTok/GGCore:GGCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
