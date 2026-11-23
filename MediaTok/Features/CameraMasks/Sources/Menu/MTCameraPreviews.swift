import Foundation
import UIKit
import MTCore
import MTSettingsUI
import MTCameraPipeline

/// Preview of the «Round videos and camera» tab: a circle with the current mask and the watermark.
/// The camera starts only from the «Show» button and stops when the screen is left.
final class MTRoundVideoPreviewView: UIView, MTMenuPreviewView {
    private let circle = UIView()
    private var cameraView: MTMaskPreviewCameraView?
    private var accountId: MTAccountID?
    private var lastWatermark: MTRoundWatermarkConfig??

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.circle.clipsToBounds = true
        self.circle.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
        self.addSubview(self.circle)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func update(context: MTMenuContext) {
        if self.cameraView == nil {
            let accountId = context.accountID
            self.accountId = accountId
            let cameraView = MTMaskPreviewCameraView(maskProvider: {
                guard MTMaskEngine.isActive(for: accountId) else {
                    return nil
                }
                return MTMaskEngine.shared.mask(for: MTMaskEngine.selection(for: accountId))
            }, autoStart: false)
            self.circle.addSubview(cameraView)
            self.cameraView = cameraView
            self.setNeedsLayout()
        }
        let watermark = MTRoundWatermarkConfig.make(
            text: MTRoundVideoSettings.watermarkText.value,
            font: MTRoundVideoSettings.watermarkFont.value,
            position: MTRoundVideoSettings.watermarkPosition.value,
            size: context.displayValue(.global(MTRoundVideoSettings.watermarkSize)),
            opacity: context.displayValue(.global(MTRoundVideoSettings.watermarkOpacity)),
            color: MTRoundVideoSettings.watermarkColor.value
        )
        let effective = MTRoundVideoSettings.watermark.value ? watermark : nil
        if self.lastWatermark != .some(effective) {
            self.lastWatermark = .some(effective)
            self.renderWatermark(effective)
        }
    }

    private func renderWatermark(_ config: MTRoundWatermarkConfig?) {
        let side = max(1.0, self.circle.bounds.width * UIScreen.main.scale)
        guard let config, let watermark = MTRoundVideoWatermark(config: config, side: Int(side)) else {
            self.cameraView?.overlayView.image = nil
            return
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIImage(cgImage: watermark.image).draw(in: watermark.rect)
        }
        self.cameraView?.overlayView.image = image
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = max(0.0, self.bounds.height - 16.0)
        let previous = self.circle.bounds.width
        self.circle.frame = CGRect(x: (self.bounds.width - side) / 2.0, y: 8.0, width: side, height: side)
        self.circle.layer.cornerRadius = side / 2.0
        self.cameraView?.frame = self.circle.bounds
        if abs(previous - side) > 0.5, let config = self.lastWatermark {
            self.renderWatermark(config)
        }
    }
}

/// Preview of the photo watermark: a sample photo with the watermark as it will be sent.
final class MTPhotoWatermarkPreviewView: UIView, MTMenuPreviewView {
    private let imageView = UIImageView()
    private static let sample: UIImage = {
        let size = CGSize(width: 600.0, height: 400.0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(red: 0.20, green: 0.45, blue: 0.75, alpha: 1.0).cgColor, UIColor(red: 0.95, green: 0.65, blue: 0.35, alpha: 1.0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0.0, y: size.height), options: [])
            }
            UIColor(red: 0.15, green: 0.3, blue: 0.2, alpha: 1.0).setFill()
            let hills = UIBezierPath()
            hills.move(to: CGPoint(x: 0.0, y: size.height))
            hills.addCurve(to: CGPoint(x: size.width, y: size.height * 0.7), controlPoint1: CGPoint(x: size.width * 0.3, y: size.height * 0.5), controlPoint2: CGPoint(x: size.width * 0.6, y: size.height * 0.9))
            hills.addLine(to: CGPoint(x: size.width, y: size.height))
            hills.close()
            hills.fill()
        }
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.layer.cornerRadius = 10.0
        self.imageView.clipsToBounds = true
        self.addSubview(self.imageView)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func update(context: MTMenuContext) {
        let config = MTPhotoWatermarkConfig.make(
            text: MTPhotoWatermarkSettings.text.value.isEmpty ? MTStrings.CameraMasks.Photo.sampleText : MTPhotoWatermarkSettings.text.value,
            font: MTPhotoWatermarkSettings.font.value,
            position: MTPhotoWatermarkSettings.position.value,
            size: context.displayValue(.global(MTPhotoWatermarkSettings.size)),
            opacity: context.displayValue(.global(MTPhotoWatermarkSettings.opacity)),
            color: MTPhotoWatermarkSettings.color.value,
            tiled: MTPhotoWatermarkSettings.tiled.value
        )
        let sample = MTPhotoWatermarkPreviewView.sample
        self.imageView.image = config.map { $0.apply(to: sample) } ?? sample
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.imageView.frame = self.bounds.insetBy(dx: 16.0, dy: 8.0)
    }
}
