import Foundation
import UIKit
import CoreVideo
import CoreMedia
import SwiftSignalKit
import MTCore
import MTCameraPipeline
import MTCallFrameBridge
import MTCallsMediaHooks
import MTFeaturesShared

/// Masks in calls. One processor for every call frame of the front camera, installed in the
/// capturer's single hook (`MTCallFrameBridge`) at launch. The block itself is cheap: it reads two
/// settings and returns at once when masks are off; the Core Image context and Vision are created
/// only on the first frame that really has a mask (an audio call never touches them).
final class MTCallMasks {
    static let shared = MTCallMasks()

    private let lock = NSLock()
    private var accountValue: MTAccountID?
    private lazy var processor: MTMaskFrameProcessor = MTMaskFrameProcessor(maskProvider: { [weak self] in
        return self?.currentMask()
    })

    /// The account of the call on screen (set by the call screen's overlay).
    var currentAccount: MTAccountID? {
        get {
            self.lock.lock()
            defer {
                self.lock.unlock()
            }
            return self.accountValue
        }
        set {
            self.lock.lock()
            self.accountValue = newValue
            self.lock.unlock()
        }
    }

    static func install() {
        MTCallFrameBridge.setProcessor({ pixelBuffer, isFrontCamera, rotation in
            guard isFrontCamera, let processed = MTCallMasks.shared.process(pixelBuffer, rotation: Int(rotation)) else {
                return nil
            }
            return Unmanaged.passRetained(processed)
        })
    }

    /// Masks apply in calls when the user turned them on there, or while the anonymous mode is on.
    private func isEnabled(account: MTAccountID?) -> Bool {
        if let account, MTAnonymousMode.isActive.value(for: account) {
            return true
        }
        return MTMaskSettings.inCalls.value
    }

    private func currentMask() -> MTPreparedMask? {
        let account = self.currentAccount
        guard self.isEnabled(account: account) else {
            return nil
        }
        return MTMaskEngine.shared.mask(for: MTMaskEngine.selection(for: account))
    }

    /// Capture queue of tgcalls. `rotation` is the clockwise angle tgcalls applies for display; the
    /// other side sees the picture unmirrored, so the mask is drawn unmirrored too.
    private func process(_ pixelBuffer: CVPixelBuffer, rotation: Int) -> CVPixelBuffer? {
        guard self.isEnabled(account: self.currentAccount) else {
            return nil
        }
        let info = MTCameraFrameInfo(facing: .front, timestamp: CMClockGetTime(CMClockGetHostTimeClock()), orientation: MTCameraFrameInfo.orientation(quarterTurns: rotation / 90, mirrored: false))
        return self.processor.process(pixelBuffer, info: info)
    }
}

/// The «Masks» button of the call screen's column: the strip of masks.
final class MTCallMasksOverlayItem: MTCallOverlayItem {
    private let accountId: MTAccountID
    private var panel: MTMaskChipsPanel?

    init(accountId: MTAccountID) {
        self.accountId = accountId
    }

    var id: String {
        return "cameraMasks.masks"
    }

    var order: Int {
        return 100
    }

    var icon: UIImage? {
        return UIImage(systemName: "theatermasks.fill")
    }

    func isVisible(state: MTCallScreenState) -> Bool {
        guard state.hasLocalVideo, !state.isTerminated else {
            return false
        }
        return MTMaskSettings.inCalls.value || MTAnonymousMode.isActive.value(for: self.accountId)
    }

    func makePanel() -> UIView? {
        let panel = MTMaskChipsPanel(accountId: self.accountId)
        panel.frame = CGRect(x: 0.0, y: 0.0, width: 320.0, height: MTMaskChipsPanel.height)
        panel.activate()
        self.panel = panel
        return panel
    }

    func buttonTapped() {
    }

    func screenWillClose() {
        self.panel?.invalidate()
        self.panel = nil
    }
}
