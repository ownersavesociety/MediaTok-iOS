load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ImageCompression",
    module_name = "ImageCompression",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        # MEDIATOK: outgoing photo size / quality / pixels (GGOutgoingImageHooks)
        "//MediaTok/GGHooks:ImageCompressionHookSources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/MozjpegBinding:MozjpegBinding",
        # MEDIATOK: hook points
        "//MediaTok/GGCore:GGCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
