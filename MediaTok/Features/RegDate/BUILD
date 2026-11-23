load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Feature module MTRegDate, «Дата регистрации».
# May depend on everything below TelegramUI; never on TelegramUI or another MT<Feature> module
#.
swift_library(
    name = "MTRegDate",
    module_name = "MTRegDate",
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
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        # The explanation alert and the «copied» toast.
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/UndoUI:UndoUI",
        # The shared profile-photo cache of the profile header (`peerInfoProfilePhotosWithCache`).
        "//submodules/PeerAvatarGalleryUI:PeerAvatarGalleryUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests of the plain logic: the contract and the estimate, the store, the
# remote contract and the display rules. Foundation only. Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/Features/RegDate:MTRegDateTests
swift_test(
    name = "MTRegDateTests",
    srcs = glob([
        "Sources/Model/**/*.swift",
        "Sources/Estimate/**/*.swift",
        "Sources/Store/**/*.swift",
        "Tests/**/*.swift",
    ]) + [
        "Sources/Format/MTRegDateDisplay.swift",
        "Sources/Remote/MTRegDateRemoteResponse.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)
