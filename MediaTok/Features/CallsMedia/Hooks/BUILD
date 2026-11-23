load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Extension points of the «Calls» zone for the upstream call modules (TelegramCallsUI) that sit BELOW
# MTCallsMedia and do not see MTHooks. Owner: MediaTok. The handlers live in MTCallsMedia (and, for the
# masks column of the call overlay, in MediaTok's module); an empty point means upstream behaviour.
# Same pattern as //MediaTok/Features/Appearance:MTAppearanceSettings.
swift_library(
    name = "MTCallsMediaHooks",
    module_name = "MTCallsMediaHooks",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
        "//MediaTok/Features/CallsMedia/CallAudio:MTCallAudio",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramVoip:TelegramVoip",
        "//submodules/AccountContext:AccountContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)
