load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

# Owner: MediaTok. Targets:
#
#   MTCameraPipeline  — what the upstream camera modules read: round video / watermark / gallery
#                       camera settings, the recording snapshot, the frame processor protocol and
#                       the camera hook points, the watermark renderer, audio post-processing of
#                       round videos. MTCore + SwiftSignalKit only, so Camera, CameraNeo,
#                       CameraLegacy, MediaEditor, MediaPickerUI and VideoMessageCameraScreen can
#                       depend on it (like MTAppearanceSettings of MediaTok).
#   MTCallFrameBridge — Objective-C, Foundation + CoreVideo only: the one hook tgcalls'
#                       VideoCameraCapturer calls for every call frame (masks in calls).
#   MTCallCameraHooks — MTCore + TelegramVoip: the call camera points TelegramCallsUI asks
#                       (a capturer fed by the virtual camera instead of the device camera).
#   MTCameraMasks     — the feature: mask engine (Core Image + Vision), catalog, own masks, studio,
#                       menus, the round-video camera extension, calls (masks, virtual camera),
#                       «video → round video», photo watermark, migration.
#
# Filegroup compiled INTO VideoMessageCameraScreen (its BUILD lists the label in srcs), so the code
# stays under MediaTok/: the video part of the round video settings on the camera screen.

swift_library(
    name = "MTCameraPipeline",
    module_name = "MTCameraPipeline",
    srcs = glob([
        "Pipeline/Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

objc_library(
    name = "MTCallFrameBridge",
    enable_modules = True,
    module_name = "MTCallFrameBridge",
    srcs = glob([
        "CallBridge/Sources/**/*.m",
    ]),
    copts = [
        "-Werror",
    ],
    hdrs = glob([
        "CallBridge/PublicHeaders/**/*.h",
    ]),
    includes = [
        "CallBridge/PublicHeaders",
    ],
    sdk_frameworks = [
        "Foundation",
        "CoreVideo",
    ],
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "VideoMessageCameraScreenSources",
    srcs = glob([
        "Upstream/VideoMessageCameraScreen/**/*.swift",
    ]),
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "MTCallCameraHooks",
    module_name = "MTCallCameraHooks",
    srcs = glob([
        "CallHooks/Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
        "//submodules/TelegramVoip:TelegramVoip",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "MTCameraMasks",
    module_name = "MTCameraMasks",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":MTCameraPipeline",
        ":MTCallFrameBridge",
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
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AppBundle:AppBundle",
        "//submodules/ImageCompression:ImageCompression",
        "//submodules/LocalMediaResources:LocalMediaResources",
        "//submodules/TelegramUI/Components/MediaEditor",
        "//submodules/LegacyComponents:LegacyComponents",
        "//submodules/PromptUI:PromptUI",
        ":MTCallCameraHooks",
        "//MediaTok/Features/CallsMedia/Hooks:MTCallsMediaHooks",
        "//submodules/TelegramVoip:TelegramVoip",
    ],
    visibility = [
        "//visibility:public",
    ],
)
