load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Light shared part of the features, linked into the extensions. Sources/<Zone>/** belong to the
# zone owners; the aggregator Sources/MTFeaturesShared.swift and this BUILD belong to MediaTok.
# May depend on MTCore, TelegramCore, Postbox, SwiftSignalKit and nothing else.
swift_library(
    name = "MTFeaturesShared",
    module_name = "MTFeaturesShared",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The anti-delete model (index, export, quotes) without iOS dependencies, for the host test
# MTAntiDeleteTests in //MediaTok/Features/AntiDelete. Not part of the app build.
filegroup(
    name = "AntiDeleteModelSources",
    srcs = glob(["Sources/AntiDelete/Model/**/*.swift"]),
    visibility = ["//MediaTok/Features/AntiDelete:__pkg__"],
)

# Host (macOS) tests of the pure merges of 2026-10-27 — the one send delay and the one «no pull to the
# next channel or topic» switch: only their Foundation files. Not part of the app build. Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/Shared:MTFeaturesSharedTests
swift_test(
    name = "MTFeaturesSharedTests",
    srcs = [
        "Sources/GhostMode/MTSendDelaySeconds.swift",
        "Sources/Messages/MTScrollToNextMerge.swift",
    ] + glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
)
