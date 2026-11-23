// Call camera points, used by TelegramCallsUI (owner of the call files: MediaTok, MediaTok spec):
//   - every `OngoingCallVideoCapturer()` made for the device camera in PresentationCall,
//     PresentationGroupCall and VideoChatScreen (camera preview) asks `makeCameraCapturer()` first;
//   - `switchVideoCamera()` asks `switchCamera(capturer:isFront:)` first.
// The masks / virtual camera buttons of the call screens go through MediaTok's
// `MTCallsMediaHooks.overlayItems`. Without handlers every helper returns nil / false: upstream.

import Foundation
import TelegramVoip
import MTCore

public enum MTCallCameraHooks {
    /// Asked whenever a call needs a camera capturer. Non-nil: a capturer MediaTok feeds itself
    /// (the virtual camera); the device camera is never started for it. Main thread.
    public static let cameraCapturer = MTHookPoint<() -> OngoingCallVideoCapturer?>("calls.cameraCapturer")

    /// Asked before switching cameras: `true` = the feature handled it (its capturer has no device).
    public static let cameraSwitch = MTHookPoint<(OngoingCallVideoCapturer, Bool) -> Bool>("calls.cameraSwitch")

    public static func makeCameraCapturer() -> OngoingCallVideoCapturer? {
        if MTCallCameraHooks.cameraCapturer.isEmpty {
            return nil
        }
        for handler in MTCallCameraHooks.cameraCapturer.handlers {
            if let capturer = handler() {
                return capturer
            }
        }
        return nil
    }

    public static func switchCamera(capturer: OngoingCallVideoCapturer, isFront: Bool) -> Bool {
        if MTCallCameraHooks.cameraSwitch.isEmpty {
            return false
        }
        for handler in MTCallCameraHooks.cameraSwitch.handlers {
            if handler(capturer, isFront) {
                return true
            }
        }
        return false
    }
}
