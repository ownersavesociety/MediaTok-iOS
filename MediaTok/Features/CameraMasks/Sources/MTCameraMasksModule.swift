import Foundation
import TelegramCore
import AccountContext
import MTCore
import MTHooks
import MTCameraPipeline
import MTCallCameraHooks
import MTCallsMediaHooks
import MTFeaturesShared

/// Entry point of the MTCameraMasks feature module. Owner: MediaTok.
public enum MTCameraMasksModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        MTCameraPipelineSettings.declare()
        MTMaskSettings.declare()
        MTVirtualCameraSettings.declare()
        MTCameraMasksMigrations.register()

        // Round videos: the masks button, panel and processor exist only while masks are on (or
        // the anonymous mode of this account is). Otherwise the camera screen is upstream's.
        MTCameraHooks.roundVideoCamera.register({ context in
            guard MTMaskEngine.isActive(for: context.accountId) else {
                return nil
            }
            return MTRoundVideoMasksExtension(accountId: context.accountId)
        }, order: 100)

        // Calls: one processor in the capturer's frame hook (returns at once while masks are off),
        // the virtual camera's capturer, and two buttons in the call screen's column.
        MTCallMasks.install()
        MTCallCameraHooks.cameraCapturer.register({
            return MTVirtualCameraFeeder.makeCapturer()
        }, order: 100)
        MTCallCameraHooks.cameraSwitch.register({ capturer, isFront in
            return MTVirtualCameraFeeder.switchCamera(capturer: capturer, isFront: isFront)
        }, order: 100)
        MTCallsMediaHooks.overlayItems.register({ screen in
            let accountId = screen.context.account.id.mt
            MTCallMasks.shared.currentAccount = accountId
            // Only the buttons of features that are on: with both off the call screen gets no overlay.
            var items: [MTCallOverlayItem] = []
            if MTMaskSettings.inCalls.value || MTAnonymousMode.isActive.value(for: accountId) {
                items.append(MTCallMasksOverlayItem(accountId: accountId))
            }
            if MTVirtualCameraSettings.enabled.value {
                items.append(MTVirtualCameraOverlayItem(call: screen.call, groupCall: screen.groupCall))
            }
            return items
        }, order: 200)

        // Outgoing media: the photo watermark and «video as a round video».
        MTPhotoWatermarkHandler.register()
        MTRoundVideoImportHandler.register()

        // Telegram's size limit of a round video, known before any round video is encoded (the
        // gallery ones too, which never open the round camera); the camera re-reads it.
        MTLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            MTRoundVideoServerLimits.update(encoding: context.getAppConfigValue("round_video_encoding") as? [String: Any])
            // The calls' account and own video for masks and the virtual camera, also without a call screen.
            MTCameraCallsMonitor.shared.start(sharedContext: context.sharedContext)
        }, order: 300)

        MTCameraMasksMenu.register()

        // Files of the old app (own masks, virtual camera media): moved once, off the launch
        // thread; each is a single existence check when there is nothing to move.
        MTMaskStore.migrateLegacyMasksIfNeeded()
        MTVirtualCameraLibrary.migrateLegacyFilesIfNeeded()
    }
}
