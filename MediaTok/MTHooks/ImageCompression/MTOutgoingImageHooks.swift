// Compiled into ImageCompression (filegroup //MediaTok/MTHooks:ImageCompressionHookSources).
// Outgoing photos: size and JPEG quality (photo quality / "large photos") and a pixel
// transform (watermark). Lives in ImageCompression because both sending paths — the legacy
// picker (LegacyMediaPickerUI) and photo-library resources (LocalMediaResources) — import it,
// and both sit below the UI library MTHooks.

import Foundation
import UIKit
import MTCore

public struct MTOutgoingPhotoParameters: Equatable {
    /// Longest side in pixels (upstream: 1280, 2560 for "HD").
    public var maxSide: CGFloat
    /// JPEG quality 0…1 (upstream: 0.6).
    public var jpegQuality: Float
    public let isHd: Bool

    public init(maxSide: CGFloat, jpegQuality: Float, isHd: Bool) {
        self.maxSide = maxSide
        self.jpegQuality = jpegQuality
        self.isHd = isHd
    }
}

public enum MTOutgoingImageHooks {
    /// Transformer of size / quality of an outgoing photo.
    public static let parameters = MTHookPoint<(inout MTOutgoingPhotoParameters) -> Void>("media.outgoingPhotoParameters")

    /// Transformer of the scaled pixels before compression (watermark). Called off the main
    /// thread; `Bool` = HD photo.
    public static let image = MTHookPoint<(UIImage, Bool) -> UIImage>("media.outgoingPhotoImage")

    public static func maxSide(_ side: CGFloat, hd: Bool) -> CGFloat {
        if MTOutgoingImageHooks.parameters.isEmpty {
            return side
        }
        return MTOutgoingImageHooks.resolve(MTOutgoingPhotoParameters(maxSide: side, jpegQuality: 0.6, isHd: hd)).maxSide
    }

    public static func jpegQuality(_ quality: Float, hd: Bool) -> Float {
        if MTOutgoingImageHooks.parameters.isEmpty {
            return quality
        }
        return MTOutgoingImageHooks.resolve(MTOutgoingPhotoParameters(maxSide: hd ? 2560.0 : 1280.0, jpegQuality: quality, isHd: hd)).jpegQuality
    }

    public static func transform(_ image: UIImage, hd: Bool) -> UIImage {
        if MTOutgoingImageHooks.image.isEmpty {
            return image
        }
        var result = image
        for handler in MTOutgoingImageHooks.image.handlers {
            result = handler(result, hd)
        }
        return result
    }

    private static func resolve(_ value: MTOutgoingPhotoParameters) -> MTOutgoingPhotoParameters {
        var result = value
        for handler in MTOutgoingImageHooks.parameters.handlers {
            handler(&result)
        }
        return result
    }
}
