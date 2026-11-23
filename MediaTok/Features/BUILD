load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Aggregator of the feature modules: only `register()` calls. TelegramUI depends on it.
# Owner: MediaTok; the twelve feature modules are listed once here so nobody edits it in waves 2–4.
swift_library(
    name = "MTFeatures",
    module_name = "MTFeatures",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTSettingsUI:MTSettingsUI",
        "//MediaTok/Features/Shared:MTFeaturesShared",
        "//MediaTok/Features/GhostMode:MTGhostMode",
        "//MediaTok/Features/AntiDelete:MTAntiDelete",
        "//MediaTok/Features/Messages:MTMessages",
        "//MediaTok/Features/Appearance:MTAppearance",
        "//MediaTok/Features/Interface:MTInterface",
        "//MediaTok/Features/Voice:MTVoice",
        "//MediaTok/Features/CameraMasks:MTCameraMasks",
        "//MediaTok/Features/CallsMedia:MTCallsMedia",
        "//MediaTok/Features/Security:MTSecurity",
        "//MediaTok/Features/NetworkSpoof:MTNetworkSpoof",
        "//MediaTok/Features/Vless:MTVless",
        "//MediaTok/Features/ProfileExport:MTProfileExport",
        # MediaTok: Swiftgram-parity features
        "//MediaTok/Features/Extras:MTExtras",
        # MediaTok: «Дата регистрации»
        "//MediaTok/Features/RegDate:MTRegDate",
    ],
    visibility = [
        "//visibility:public",
    ],
)
