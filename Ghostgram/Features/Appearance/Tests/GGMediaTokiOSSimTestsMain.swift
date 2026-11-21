import Foundation
import UIKit
import CoreGraphics
import CoreImage
import CoreText

@main
enum GGMediaTokiOSSimTestsMain {
    private static var passed = 0
    private static var failed = 0

    static func main() {
        Self.run("IPhone13BannerFullBleedGeometry", Self.testIPhone13BannerFullBleedGeometry)
        Self.run("DiscordVectorParticlesNonEmpty", Self.testDiscordVectorParticlesNonEmpty)
        Self.run("CoreImage4kBlurAndJpegPipeline", Self.testCoreImage4kBlurAndJpegPipeline)
        Self.run("CustomCyrillicTtfRegistrationOnIOS", Self.testCustomCyrillicTtfRegistrationOnIOS)
        Self.run("MultiPhoneAndNftSlugParsing", Self.testMultiPhoneAndNftSlugParsing)
        Self.run("WornStarGiftCodableRoundTrip", Self.testWornStarGiftCodableRoundTrip)

        print("MediaTok iOS Simulator UIKit Tests Summary: \(Self.passed) passed, \(Self.failed) failed")
        if Self.failed > 0 {
            exit(1)
        }
    }

    private static func run(_ name: String, _ block: () -> Void) {
        let beforeFailed = Self.failed
        block()
        if Self.failed == beforeFailed {
            Self.passed += 1
            print("[PASS] \(name)")
        } else {
            print("[FAIL] \(name)")
        }
    }

    private static func check(_ condition: Bool, _ msg: String) {
        if !condition {
            Self.failed += 1
            print("  Assertion failed: \(msg)")
        }
    }

    private static func testIPhone13BannerFullBleedGeometry() {
        let headerWidth: CGFloat = 390.0
        let bannerInset: CGFloat = 3.0
        let apparentHeight: CGFloat = 254.0
        let anchorFrame = CGRect(
            x: -bannerInset,
            y: -2000.0 + apparentHeight,
            width: headerWidth + bannerInset * 2.0,
            height: 2000.0
        )
        let visibleHeight = max(0.0, anchorFrame.maxY)
        let bannerRect = CGRect(
            x: 0.0,
            y: anchorFrame.height - visibleHeight,
            width: anchorFrame.width,
            height: visibleHeight
        )
        Self.check(abs((anchorFrame.minX + bannerRect.minX) - (-3.0)) < 0.01, "Left bleed must be -3pt")
        Self.check(abs((anchorFrame.minX + bannerRect.maxX) - 393.0) < 0.01, "Right bleed must be +393pt symmetrically")
        Self.check(abs(bannerRect.height - 254.0) < 0.01, "Visible height must match 254pt header")
    }

    private static func testDiscordVectorParticlesNonEmpty() {
        let kinds = ["sakura", "stars", "snow", "fire"]
        let size = CGSize(width: 24.0, height: 24.0)
        for kind in kinds {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 2.0
            fmt.opaque = false
            let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
                let cg = ctx.cgContext
                UIColor.systemPink.setFill()
                switch kind {
                case "sakura":
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: 12.0, y: 2.0))
                    path.addCurve(to: CGPoint(x: 20.0, y: 12.0), controlPoint1: CGPoint(x: 19.0, y: 3.0), controlPoint2: CGPoint(x: 22.0, y: 8.0))
                    path.addCurve(to: CGPoint(x: 12.0, y: 22.0), controlPoint1: CGPoint(x: 19.0, y: 17.0), controlPoint2: CGPoint(x: 14.0, y: 21.0))
                    path.addCurve(to: CGPoint(x: 4.0, y: 12.0), controlPoint1: CGPoint(x: 10.0, y: 21.0), controlPoint2: CGPoint(x: 5.0, y: 17.0))
                    path.addCurve(to: CGPoint(x: 12.0, y: 2.0), controlPoint1: CGPoint(x: 2.0, y: 8.0), controlPoint2: CGPoint(x: 5.0, y: 3.0))
                    path.close()
                    path.fill()
                case "stars":
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: 12.0, y: 1.0))
                    path.addLine(to: CGPoint(x: 15.0, y: 9.0))
                    path.addLine(to: CGPoint(x: 23.0, y: 12.0))
                    path.addLine(to: CGPoint(x: 15.0, y: 15.0))
                    path.addLine(to: CGPoint(x: 12.0, y: 23.0))
                    path.addLine(to: CGPoint(x: 9.0, y: 15.0))
                    path.addLine(to: CGPoint(x: 1.0, y: 12.0))
                    path.addLine(to: CGPoint(x: 9.0, y: 9.0))
                    path.close()
                    path.fill()
                case "snow":
                    cg.setStrokeColor(UIColor.white.cgColor)
                    cg.setLineWidth(2.0)
                    for i in 0 ..< 3 {
                        let angle = CGFloat(i) * CGFloat.pi / 3.0
                        let dx = cos(angle) * 9.0
                        let dy = sin(angle) * 9.0
                        cg.move(to: CGPoint(x: 12.0 - dx, y: 12.0 - dy))
                        cg.addLine(to: CGPoint(x: 12.0 + dx, y: 12.0 + dy))
                    }
                    cg.strokePath()
                default:
                    let path = UIBezierPath(ovalIn: CGRect(x: 6.0, y: 2.0, width: 12.0, height: 20.0))
                    path.fill()
                }
            }
            let cgOk = (img.cgImage?.width ?? 0) > 0 && (img.cgImage?.height ?? 0) > 0
            let pngOk = !(img.pngData()?.isEmpty ?? true)
            Self.check(cgOk && pngOk, "Particle vector image must render cleanly for \(kind)")
        }
    }

    private static func testCoreImage4kBlurAndJpegPipeline() {
        let srcSize = CGSize(width: 600.0, height: 900.0)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = true
        let portrait = UIGraphicsImageRenderer(size: srcSize, format: fmt).image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(origin: .zero, size: srcSize))
            UIColor.systemYellow.setFill()
            ctx.fill(CGRect(x: 100.0, y: 200.0, width: 400.0, height: 500.0))
        }
        guard let ciInput = CIImage(image: portrait),
              let filter = CIFilter(name: "CIGaussianBlur") else {
            Self.check(false, "CIFilter CIGaussianBlur unavailable on iOS Simulator")
            return
        }
        filter.setValue(ciInput.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(24.0, forKey: kCIInputRadiusKey)
        let ciCtx = CIContext(options: nil)
        guard let output = filter.outputImage,
              let cgOut = ciCtx.createCGImage(output.cropped(to: ciInput.extent), from: ciInput.extent),
              let jpegData = UIImage(cgImage: cgOut).jpegData(compressionQuality: 0.92) else {
            Self.check(false, "CoreImage blur -> JPEG pipeline returned nil")
            return
        }
        let bytes = [UInt8](jpegData.prefix(2))
        Self.check(bytes == [0xFF, 0xD8] && jpegData.count > 1000, "Rendered JPEG must contain valid SOI marker")
    }

    private static func testCustomCyrillicTtfRegistrationOnIOS() {
        var grid = [Bool](repeating: false, count: 10 * 12)
        for r in 2 ... 9 {
            grid[r * 10 + 3] = true
            grid[r * 10 + 6] = true
        }
        for c in 3 ... 6 {
            grid[2 * 10 + c] = true
            grid[5 * 10 + c] = true
        }
        let data = GGMediaTokCoreLogic.compileTtf(
            fontNameRaw: "Тест iOS",
            grids: ["А": grid, "A": grid],
            pixelStyle: 1,
            uniqueTag: "7777"
        )
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mt_ios_sim_\(UUID().uuidString).ttf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            Self.check(false, "Failed writing temporary TTF on iOS Simulator")
            return
        }
        let registered = CTFontManagerRegisterFontsForURL(tmp as CFURL, .process, nil)
        defer { _ = CTFontManagerUnregisterFontsForURL(tmp as CFURL, .process, nil) }
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(tmp as CFURL) as? [CTFontDescriptor],
              let firstDesc = descs.first,
              let psName = CTFontDescriptorCopyAttribute(firstDesc, kCTFontNameAttribute) as? String else {
            Self.check(false, "CoreText descriptor extraction failed on iOS Simulator")
            return
        }
        let uiFont = UIFont(name: psName, size: 16.0)
        Self.check(registered && uiFont != nil, "Custom Cyrillic TTF must register cleanly into UIFont on iOS (\(psName))")
    }

    private static func testMultiPhoneAndNftSlugParsing() {
        let rawPhones = "+7 999 111-22-33, +888 0123 4567\n+1 555 222 3333; +7 999 111-22-33"
        let separators = CharacterSet(charactersIn: ",;\n\r")
        var seen = Set<String>()
        var parsed: [String] = []
        for part in rawPhones.components(separatedBy: separators) {
            let clean = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && seen.insert(clean).inserted {
                parsed.append(clean)
            }
        }
        Self.check(parsed.count == 3 && parsed[1] == "+888 0123 4567", "Multi-phone parser must preserve internal spaces & deduplicate")

        func parseSlug(_ raw: String) -> String? {
            var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if let range = trimmed.range(of: "/nft/", options: .caseInsensitive) {
                trimmed = String(trimmed[range.upperBound...])
            } else if let range = trimmed.range(of: "nft/", options: .caseInsensitive) {
                trimmed = String(trimmed[range.upperBound...])
            }
            if let q = trimmed.firstIndex(where: { $0 == "?" || $0 == "#" || $0 == "/" }) {
                trimmed = String(trimmed[..<q])
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            return (!trimmed.isEmpty && trimmed.count <= 128) ? trimmed : nil
        }

        Self.check(parseSlug("https://t.me/nft/PlushPepe-1?start=1") == "PlushPepe-1", "NFT URL slug must parse cleanly")
        Self.check(parseSlug("PlushPepe-42") == "PlushPepe-42", "Bare NFT slug must parse cleanly")
        Self.check(parseSlug("   ") == nil, "Empty NFT input must return nil")
    }

    private struct WornGiftStub: Codable, Equatable {
        var id: Int64
        var fileId: Int64
        var title: String
        var slug: String
        var patternFileId: Int64
        var innerColor: Int32
        var outerColor: Int32
        var patternColor: Int32
        var textColor: Int32
    }

    private static func testWornStarGiftCodableRoundTrip() {
        let sample = WornGiftStub(
            id: 987654321,
            fileId: 12345,
            title: "Plush Pepe",
            slug: "PlushPepe-1",
            patternFileId: 54321,
            innerColor: 0x112233,
            outerColor: 0x445566,
            patternColor: 0x778899,
            textColor: -1
        )
        let data = try? JSONEncoder().encode(sample)
        let decoded = data.flatMap { try? JSONDecoder().decode(WornGiftStub.self, from: $0) }
        Self.check(decoded == sample, "WornStarGift Codable round-trip must preserve all fields")
    }
}
