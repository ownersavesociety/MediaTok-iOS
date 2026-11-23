// Compiled into ShareExtensionContext (filegroup //MediaTok/MTHooks:ShareExtensionHookSources):
// photos sent from other apps through the share extension get the same size, JPEG quality and
// watermark as photos sent from the app (MEDIA-12). The settings are App Group ones
// (`MTOutgoingPhotoSettings`, `MTPhotoWatermarkSettings`); the handlers are the app's own.

import Foundation
import UIKit
import ImageCompression
import MTCore
import MTFeaturesShared
import MTCameraPipeline

/// From `mtShareExtensionDidStart`, before `MTHookRegistry.freeze()`.
func mtShareExtensionRegisterPhotoHandlers() {
    MTPhotoWatermarkSettings.declare()
    MTOutgoingImageHooks.parameters.register({ parameters in
        MTOutgoingPhotoSettings.apply(maxSide: &parameters.maxSide, jpegQuality: &parameters.jpegQuality, isHd: parameters.isHd)
    })
    MTOutgoingImageHooks.image.register({ image, _ in
        return MTPhotoWatermarkConfig.applyCurrent(to: image)
    }, order: 500)
}

/// MediaTok hook target, before the shared items are read (`TGItemProviderSignals.setGGPhotoMaxPixelSize`):
/// the long side a shared photo is decoded to when MediaTok changes something about it, 0 when
/// nothing changes (the item provider then compresses it itself, as upstream does).
func mtShareExtensionPhotoMaxPixelSize() -> CGFloat {
    let maxSide = MTOutgoingImageHooks.maxSide(1280.0, hd: false)
    let quality = MTOutgoingImageHooks.jpegQuality(0.52, hd: false)
    if maxSide == 1280.0 && quality == 0.52 && MTPhotoWatermarkConfig.current() == nil {
        return 0.0
    }
    return maxSide
}
