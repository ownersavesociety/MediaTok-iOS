load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feature module MTVless («VPN по подписке»). Owner: MediaTok.
# May depend on everything below TelegramUI; never on TelegramUI or another MT<Feature> module
#. The Xray core is NOT a dependency: it is a separate dynamic framework
# opened with dlopen (see README.md), so nothing here links Go code.
swift_library(
    name = "MTVless",
    module_name = "MTVless",
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
        # Screens: lists, inputs, alerts.
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AlertUI:AlertUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The Telegram app's ipa_post_processor (one line in Telegram/BUILD, MediaTok spec): copies the
# prebuilt MTXrayCore.framework slice into Frameworks/ before signing. The slices are outputs of
# Core/build-core.sh and are not committed; with none built the script does nothing.
genrule(
    name = "EmbedXrayCore",
    srcs = [
        "Core/make-embed-script.sh",
    ] + glob([
        "Core/build/*/MTXrayCore.framework.zip",
    ], allow_empty = True),
    outs = [
        "EmbedXrayCore.sh",
    ],
    cmd_bash = "bash $(location Core/make-embed-script.sh) $@ $(SRCS)",
    executable = True,
    visibility = [
        "//Telegram:__pkg__",
    ],
)
