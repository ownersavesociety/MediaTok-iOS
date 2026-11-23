load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feature module MTNetworkSpoof («Приватность › Подмены»: номер, профиль). Owner: MediaTok.
# May depend on everything below TelegramUI; never on TelegramUI or another MT<Feature> module
#.
swift_library(
    name = "MTNetworkSpoof",
    module_name = "MTNetworkSpoof",
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
        "//submodules/ChatListUI:ChatListUI",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/ContextUI:ContextUI",
        "//submodules/AppBundle:AppBundle",
        # Screens: lists, inputs, alerts.
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AlertUI:AlertUI",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
    ],
    visibility = [
        "//visibility:public",
    ],
)
