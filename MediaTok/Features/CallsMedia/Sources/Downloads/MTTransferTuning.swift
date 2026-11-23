import Foundation
import UIKit
import TelegramCore
import ImageCompression
import MTCore
import MTFeaturesShared

/// Upload / download boost and outgoing photo quality and size.
/// All of it goes through the network and image points; nothing here touches the network itself.
enum MTTransferTuning {
    /// Files up to this size keep upstream's parts: boosting tiny files (avatars, thumbnails) gains
    /// nothing and only multiplies requests.
    static let minimumBoostedFileSize: Int64 = 1024 * 1024

    static func register() {
        MTNetworkHooks.uploadParameters.register({ parameters in
            guard MTCallsMediaSettings.uploadBoost.value else {
                return
            }
            // Larger parts and more of them in parallel — what the server grants Premium. A burst of
            // FLOOD_PREMIUM_WAIT is handled by upstream's upload loop (it waits and retries).
            parameters.useLargerParts = true
            parameters.increaseParallelParts = true
        })

        MTNetworkHooks.downloadParameters.register({ parameters in
            let expFlags = UserDefaults.standard.dictionary(forKey: "mediatok.wave19.exp_flags.v1") as? [String: Bool]
            let expParallel = expFlags?["parallel_chunk_fetch"] ?? true
            let rawMode = MTDownloadBoostMode(rawValue: MTCallsMediaSettings.downloadBoost.value) ?? .off
            let effectiveMode: MTDownloadBoostMode = (rawMode == .off && expParallel) ? .medium : rawMode
            guard effectiveMode != .off else {
                return
            }
            guard let fileSize = parameters.fileSize, fileSize > MTTransferTuning.minimumBoostedFileSize else {
                return
            }
            // The point asks for one value at a time; the other one is 0.
            if parameters.partSize != 0 {
                // Part sizes must be divisible by 4 KB and divide 1 MB.
                let boosted: Int64 = effectiveMode == .maximum ? 1024 * 1024 : 512 * 1024
                parameters.partSize = max(parameters.partSize, boosted)
            }
            if parameters.pendingParts != 0 {
                let boosted = effectiveMode == .maximum ? 12 : 8
                parameters.pendingParts = max(parameters.pendingParts, boosted)
            }
        })

        // The share extension registers the same handler (`mtShareExtensionDidStart`).
        MTOutgoingImageHooks.parameters.register({ parameters in
            MTOutgoingPhotoSettings.apply(maxSide: &parameters.maxSide, jpegQuality: &parameters.jpegQuality, isHd: parameters.isHd)
        })
    }
}
