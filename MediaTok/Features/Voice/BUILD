load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

# Owner: MediaTok («Голос»). Targets:
#
#   MTVoiceDSP           — plain C: the one voice effect graph (voice messages, round videos, calls)
#                          and the playback equalizer. No Foundation, realtime-safe processing. Linked
#                          into UniversalMediaPlayer (equalizer in the audio renderers) and MTVoice.
#   MTVoiceTranscription — transcription of voice messages and round videos: the engine is chosen at
#                          the moment of the request by the account's live Premium status (owner's
#                          decision 2026-10-21): Telegram's server, or Apple Speech. Word timings,
#                          the word bubbles model, the transcription quote. Used by the bubble nodes.
#   MTVoice              — the feature: menu, preview, voice changer for voice messages / round
#                          videos / calls, equalizer parameters, auto-transcription, migrations.
#
# Filegroups compiled INTO upstream modules (their BUILD lists the label in srcs), so the code stays
# under MediaTok/:
#   TelegramAudioPoints                 — the built-in microphone policy (ManagedAudioSession).
#   UniversalMediaPlayerSources         — the equalizer instance of the audio renderers.
#   ChatMessageInteractiveFileNodeSources — the word bubbles layer of the transcription.

objc_library(
    name = "MTVoiceDSP",
    enable_modules = True,
    module_name = "MTVoiceDSP",
    srcs = glob([
        "DSP/Sources/**/*.c",
    ]),
    hdrs = glob([
        "DSP/PublicHeaders/**/*.h",
    ]),
    includes = [
        "DSP/PublicHeaders",
        "DSP/PublicHeaders/MTVoiceDSP",
    ],
    copts = [
        "-std=c11",
        "-O2",
        "-Werror",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "MTVoiceTranscription",
    module_name = "MTVoiceTranscription",
    srcs = glob([
        "Transcription/Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//MediaTok/MTCore:MTCore",
        "//MediaTok/Features/Shared:MTFeaturesShared",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "TelegramAudioPoints",
    srcs = glob([
        "Points/TelegramAudio/**/*.swift",
    ]),
    visibility = [
        "//submodules/TelegramAudio:__pkg__",
    ],
)

filegroup(
    name = "UniversalMediaPlayerSources",
    srcs = glob([
        "Points/UniversalMediaPlayer/**/*.swift",
    ]),
    visibility = [
        "//submodules/MediaPlayer:__pkg__",
    ],
)

filegroup(
    name = "ChatMessageInteractiveFileNodeSources",
    srcs = glob([
        "Points/ChatMessageInteractiveFileNode/**/*.swift",
    ]),
    visibility = [
        "//submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode:__pkg__",
    ],
)

# Feature module MTVoice. May depend on everything below TelegramUI; never on TelegramUI or another
# MT<Feature> module. MTCameraPipeline, MTCallAudio and MTCallsMediaHooks are
# the light point libraries of MediaTok / MediaTok, not their feature modules.
swift_library(
    name = "MTVoice",
    module_name = "MTVoice",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":MTVoiceDSP",
        ":MTVoiceTranscription",
        "//MediaTok/MTCore:MTCore",
        "//MediaTok/MTHooks:MTHooks",
        "//MediaTok/MTSettingsUI:MTSettingsUI",
        "//MediaTok/Features/Shared:MTFeaturesShared",
        "//MediaTok/Features/CameraMasks:MTCameraPipeline",
        "//MediaTok/Features/CallsMedia/CallAudio:MTCallAudio",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/TelegramAudio:TelegramAudio",
        "//submodules/TelegramVoip:TelegramVoip",
        "//submodules/TelegramCallsUI:TelegramCallsUI",
        "//submodules/LegacyComponents:LegacyComponents",
        "//submodules/OpusBinding:OpusBinding",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/UndoUI:UndoUI",
        "//submodules/PromptUI:PromptUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
