#!/bin/bash
# Build MediaTok for the simulator (debug_sim_arm64), with bazel's progress visible.
#
#   build-system/MTBuild.sh [extra Make.py args...]      e.g. --continueOnError
#
# Config: build-system/mediatok-configuration.json (gitignored, holds api_id / api_hash /
# team_id; the committed template is mediatok-configuration.example.json).
# Signing: the simulator ignores signatures, but Make.py still resolves aps-environment from a
# profile whose application-identifier is <team_id>.<bundle_id>. The fake profiles are issued for
# ph.telegra.Telegraph, so the MediaTok profiles (build-system/mediatok-codesigning, gitignored)
# are used when present; MT_CODESIGN overrides.
#
# Do not pipe this through grep: bazel's "[N / TOTAL] <action>" line is the only progress
# indicator. The full output goes to the log named below.

set -uo pipefail
cd "$(dirname "$0")/.."

CONFIG="build-system/mediatok-configuration.json"
[ -f "$CONFIG" ] || { echo "ERROR: $CONFIG is missing — copy mediatok-configuration.example.json and fill in the keys." >&2; exit 1; }

CODESIGN="${MT_CODESIGN:-build-system/mediatok-codesigning}"
[ -d "$CODESIGN/profiles" ] || CODESIGN="build-system/fake-codesigning"

LOG="${MT_BUILD_LOG:-/tmp/gg-build.log}"
echo "config     : $CONFIG"
echo "signing    : $CODESIGN"
echo "log        : $LOG"
echo

build-system/MTXcodeConfig.sh || exit 1

# Our changes inside submodules live as patches (a submodule commit would point at nothing upstream).
# Each is applied once per checkout; an already-applied patch is left alone.
apply_patch() {
    local dir="$1" patch="$2"
    local abs_patch
    abs_patch="$(pwd)/$patch"
    if git -C "$dir" apply --check "$abs_patch" 2>/dev/null; then
        git -C "$dir" apply "$abs_patch" && echo "patched    : $dir ($patch)"
    elif ! git -C "$dir" apply --reverse --check "$abs_patch" 2>/dev/null; then
        echo "ERROR: $patch neither applies nor is already applied — $dir changed, update the patch." >&2
        exit 1
    fi
}
# rules_apple's strip action ignores --action_env (see MTXcodeConfig.sh).
apply_patch build-system/bazel-rules/rules_apple build-system/MTPatches/rules_apple-strip-shell-env.patch
# Masks and the virtual camera in calls: the frame hook in tgcalls' camera capturer.
apply_patch submodules/TgVoipWebrtc/tgcalls build-system/MTPatches/tgcalls-call-camera-masks.patch

# MTBuildRelease.sh reuses the patch step only.
[ "${MT_PATCHES_ONLY:-0}" = "1" ] && exit 0

python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    build \
    --configurationPath "$CONFIG" \
    --codesigningInformationPath "$CODESIGN" \
    --buildNumber=1 --configuration=debug_sim_arm64 \
    "$@" 2>&1 | tee "$LOG"

# PIPESTATUS[0] is Make.py's status; [1] would be tee's, which is always 0.
status=${PIPESTATUS[0]}
echo
if [ "$status" = "0" ]; then
    echo "BUILD OK"
else
    echo "BUILD FAILED (exit $status) — errors:"
    grep -E "^ERROR:|error: " "$LOG" | head -20
fi
exit "$status"
