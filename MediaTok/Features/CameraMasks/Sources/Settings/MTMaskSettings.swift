import Foundation
import MTCore

/// Settings of the masks themselves (round videos, calls, the catalog, the virtual camera). The
/// camera-pipeline settings (round video quality, watermarks, gallery camera) live in
/// MTCameraPipeline, the anonymous mode in MTFeaturesShared.
enum MTMaskSettings {
    /// Masks in round videos: the button and panel on the camera screen, and processing.
    static let enabled = MTSetting<Bool>("cameraMasks.masks.enabled", default: false)
    /// `MTMaskSelection.storage`.
    static let selection = MTSetting<String>("cameraMasks.masks.selection", default: "")
    /// The same mask in calls (front camera).
    static let inCalls = MTSetting<Bool>("cameraMasks.masks.calls", default: false)
    /// Disk limit of downloaded catalog masks, MB: "50", "100", "200", "400", "800", "1024".
    static let cacheLimit = MTSetting<String>("cameraMasks.masks.cacheLimit", default: "200")
    /// Service state of the catalog: never exported.
    static let catalogETag = MTSetting<String>("cameraMasks.masks.catalogETag", default: "", flags: [.noExport])
    static let catalogFetchedAt = MTSetting<Double>("cameraMasks.masks.catalogFetchedAt", default: 0.0, flags: [.noExport])

    static func declare() {
        let _ = MTMaskSettings.enabled
        let _ = MTMaskSettings.selection
        let _ = MTMaskSettings.inCalls
        let _ = MTMaskSettings.cacheLimit
        let _ = MTMaskSettings.catalogETag
        let _ = MTMaskSettings.catalogFetchedAt
    }
}

/// One item of the virtual camera library: metadata here, the file in the app container.
struct MTVirtualCameraItem: Codable, Equatable, MTSettingValue {
    enum Kind: String, Codable {
        case image
        case gif
        case video
    }

    var id: String
    var title: String
    /// File name only (the container path changes between installs).
    var fileName: String
    var kind: Kind
    var createdAt: Double
}

enum MTVirtualCameraSettings {
    /// Calls send a picture, GIF or video instead of the camera.
    static let enabled = MTSetting<Bool>("cameraMasks.virtualCamera.enabled", default: false)
    /// Id of the chosen item; "" = none (the real camera).
    static let selected = MTSetting<String>("cameraMasks.virtualCamera.selected", default: "")
    /// A video starts over at the end (otherwise its last frame stays).
    static let loop = MTSetting<Bool>("cameraMasks.virtualCamera.loop", default: false)
    /// The library (files stay on this device: not exported).
    static let items = MTSetting<[MTVirtualCameraItem]>("cameraMasks.virtualCamera.items", default: [], flags: [.noExport])

    static func declare() {
        let _ = MTVirtualCameraSettings.enabled
        let _ = MTVirtualCameraSettings.selected
        let _ = MTVirtualCameraSettings.loop
        let _ = MTVirtualCameraSettings.items
    }

    static var selectedItem: MTVirtualCameraItem? {
        guard MTVirtualCameraSettings.enabled.value else {
            return nil
        }
        let id = MTVirtualCameraSettings.selected.value
        if id.isEmpty {
            return nil
        }
        return MTVirtualCameraSettings.items.value.first(where: { $0.id == id })
    }
}
