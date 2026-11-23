load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# MediaTok core: settings registry and storage, canonical keys, foreground tasks, logger, network
# helper, shared inbox, hook point container, strings runtime + generated accessors. No UIKit, and
# nothing above SwiftSignalKit: TelegramCore and the extensions depend on it.
swift_library(
    name = "MTCore",
    module_name = "MTCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The parts of MTCore that need TelegramCore / Postbox types (AccountRecordId.mt, PeerId.mtKey,
# MessageId.mtKey, the proxy and account bridges). Compiled INTO TelegramCore:
# submodules/TelegramCore/BUILD lists this label in its srcs.
filegroup(
    name = "TelegramCoreBridgeSources",
    srcs = glob([
        "Bridge/TelegramCore/**/*.swift",
    ]),
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests, like //submodules/MetalEngine:MetalPipelineCacheTests: MTCore's own sources are
# compiled into the test module (internal API is reachable without @testable), only SwiftSignalKit
# besides. Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //MediaTok/MTCore:MTCoreTests
# The string tools have their own tests: python3 MediaTok/Strings/tests/test_tools.py
swift_test(
    name = "MTCoreTests",
    srcs = glob([
        "Sources/**/*.swift",
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
)
