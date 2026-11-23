load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Aggregator of the feature modules: only `register()` calls. TelegramUI depends on it.
# Owner: MediaTok; the twelve feature modules are listed once here so nobody edits it in waves 2–4.
swift_library(
    name = "GGFeatures",
    module_name = "GGFeatures",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/GGSettingsUI:GGSettingsUI",
        "//MediaTok/Features/Shared:GGFeaturesShared",
        "//MediaTok/Features/GhostMode:GGGhostMode",
        "//MediaTok/Features/AntiDelete:GGAntiDelete",
        "//MediaTok/Features/Messages:GGMessages",
        "//MediaTok/Features/Appearance:GGAppearance",
        "//MediaTok/Features/Interface:GGInterface",
        "//MediaTok/Features/Voice:GGVoice",
        "//MediaTok/Features/CameraMasks:GGCameraMasks",
        "//MediaTok/Features/CallsMedia:GGCallsMedia",
        "//MediaTok/Features/Security:GGSecurity",
        "//MediaTok/Features/NetworkSpoof:GGNetworkSpoof",
        "//MediaTok/Features/Vless:GGVless",
        "//MediaTok/Features/ProfileExport:GGProfileExport",
        # MediaTok: Swiftgram-parity features
        "//MediaTok/Features/Extras:GGExtras",
        # MediaTok: «Дата регистрации»
        "//MediaTok/Features/RegDate:GGRegDate",
    ],
    visibility = [
        "//visibility:public",
    ],
)
