import Foundation
import UIKit
import CoreGraphics
import GGCore
import GGSettingsUI

/// Interactive TrueType (.ttf) Font Creator for MediaTok iOS.
/// Draws Cyrillic, Latin, Digits, and Punctuation glyphs on a 10x12 touch grid
/// (pre-filled via CoreGraphics rasterization from the current/system font),
/// compiles a spec-compliant binary .ttf on device, imports it into GGCustomFonts, and shares it.
enum GGMediaTokTtfCreator {
    static let gridW = 10
    static let gridH = 12

    static let charset: [Character] = {
        var list: [Character] = []
        for scalar in 0x0410 ... 0x042F {
            if let s = UnicodeScalar(scalar) { list.append(Character(s)) }
        }
        list.append("Ё")
        for scalar in 0x0430 ... 0x044F {
            if let s = UnicodeScalar(scalar) { list.append(Character(s)) }
        }
        list.append("ё")
        for scalar in 0x0041 ... 0x005A {
            if let s = UnicodeScalar(scalar) { list.append(Character(s)) }
        }
        for scalar in 0x0061 ... 0x007A {
            if let s = UnicodeScalar(scalar) { list.append(Character(s)) }
        }
        for scalar in 0x0030 ... 0x0039 {
            if let s = UnicodeScalar(scalar) { list.append(Character(s)) }
        }
        for ch in "!?.,:;+-=()[]@#%*\"'/_" {
            list.append(ch)
        }
        return list
    }()

    static func present(context: GGMenuContext) {
        let vc = GGTtfCreatorViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        context.presentNative(nav)
    }

    // MARK: - Rasterizer Template

    static func rasterizeTemplate() -> [Character: [Bool]] {
        var result: [Character: [Bool]] = [:]
        let w = GGMediaTokTtfCreator.gridW
        let h = GGMediaTokTtfCreator.gridH
        let font = UIFont.systemFont(ofSize: 9.2, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for ch in GGMediaTokTtfCreator.charset {
            for i in 0 ..< pixels.count { pixels[i] = 0 }
            pixels.withUnsafeMutableBytes { rawBuf in
                guard let basePtr = rawBuf.baseAddress,
                      let cgCtx = CGContext(
                        data: basePtr,
                        width: w,
                        height: h,
                        bitsPerComponent: 8,
                        bytesPerRow: w * 4,
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      ) else {
                    return
                }
                cgCtx.translateBy(x: 0.0, y: CGFloat(h))
                cgCtx.scaleBy(x: 1.0, y: -1.0)
                UIGraphicsPushContext(cgCtx)
                let str = String(ch) as NSString
                let sz = str.size(withAttributes: attrs)
                let dx = floor((CGFloat(w) - sz.width) / 2.0)
                let dy = floor((CGFloat(h) - sz.height) / 2.0) - 0.5
                str.draw(at: CGPoint(x: dx, y: dy), withAttributes: attrs)
                UIGraphicsPopContext()
            }
            var grid = [Bool](repeating: false, count: w * h)
            for y in 0 ..< h {
                for x in 0 ..< w {
                    let alpha = pixels[(y * w + x) * 4 + 3]
                    grid[y * w + x] = alpha >= 90
                }
            }
            result[ch] = grid
        }
        return result
    }

    // MARK: - Binary TrueType (.ttf) Compiler

    private struct RectI {
        let x1: Int
        let y1: Int
        let x2: Int
        let y2: Int
    }

    private struct CmapSeg {
        var start: UInt16
        var end: UInt16
        let delta: UInt16
    }

    private struct NameRec {
        let pid: UInt16
        let eid: UInt16
        let lid: UInt16
        let nid: UInt16
        let len: UInt16
        let off: UInt16
    }

    private static func appendU16(_ d: inout Data, _ v: UInt16) {
        d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8(v & 0xFF))
    }

    private static func appendS16(_ d: inout Data, _ v: Int16) {
        GGMediaTokTtfCreator.appendU16(&d, UInt16(bitPattern: v))
    }

    private static func appendU32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8((v >> 24) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF))
        d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8(v & 0xFF))
    }

    private static func calcChecksum(_ data: Data) -> UInt32 {
        var sum: UInt32 = 0
        let n = data.count
        var i = 0
        while i < n {
            let b0 = UInt32(data[i]) << 24
            let b1 = (i + 1 < n) ? (UInt32(data[i + 1]) << 16) : 0
            let b2 = (i + 2 < n) ? (UInt32(data[i + 2]) << 8) : 0
            let b3 = (i + 3 < n) ? UInt32(data[i + 3]) : 0
            sum = sum &+ (b0 | b1 | b2 | b3)
            i += 4
        }
        return sum
    }

    private static func buildSimpleGlyph(_ rects: [RectI]) -> Data {
        if rects.isEmpty {
            return Data()
        }
        var xMin = Int.max
        var yMin = Int.max
        var xMax = Int.min
        var yMax = Int.min
        for r in rects {
            xMin = min(xMin, min(r.x1, r.x2))
            xMax = max(xMax, max(r.x1, r.x2))
            yMin = min(yMin, min(r.y1, r.y2))
            yMax = max(yMax, max(r.y1, r.y2))
        }
        var out = Data()
        GGMediaTokTtfCreator.appendS16(&out, Int16(rects.count))
        GGMediaTokTtfCreator.appendS16(&out, Int16(xMin))
        GGMediaTokTtfCreator.appendS16(&out, Int16(yMin))
        GGMediaTokTtfCreator.appendS16(&out, Int16(xMax))
        GGMediaTokTtfCreator.appendS16(&out, Int16(yMax))
        for i in 0 ..< rects.count {
            GGMediaTokTtfCreator.appendU16(&out, UInt16(i * 4 + 3))
        }
        GGMediaTokTtfCreator.appendU16(&out, 0)
        out.append(contentsOf: [UInt8](repeating: 1, count: rects.count * 4))
        var prevX = 0
        for r in rects {
            for x in [r.x1, r.x1, r.x2, r.x2] {
                GGMediaTokTtfCreator.appendS16(&out, Int16(x - prevX))
                prevX = x
            }
        }
        var prevY = 0
        for r in rects {
            for y in [r.y1, r.y2, r.y2, r.y1] {
                GGMediaTokTtfCreator.appendS16(&out, Int16(y - prevY))
                prevY = y
            }
        }
        while out.count % 4 != 0 {
            out.append(0)
        }
        return out
    }

    static func compileTtf(fontNameRaw: String, grids: [Character: [Bool]], pixelStyle: Int) -> Data {
        let trimmed = fontNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fontName = trimmed.isEmpty ? "MediaTok Custom" : trimmed
        let cellW = (pixelStyle == 2) ? 82 : 76
        let cellH = 82
        let gap = (pixelStyle == 1) ? 10 : 0
        let slantPerRow = (pixelStyle == 3) ? 14 : 0
        let baselineRow = 9

        var charRects: [UInt16: [RectI]] = [32: []]
        for (ch, grid) in grids {
            guard ch.unicodeScalars.count == 1,
                  let scalar = ch.unicodeScalars.first,
                  scalar.value <= 0xFFFF,
                  scalar.value != 32,
                  grid.count == GGMediaTokTtfCreator.gridW * GGMediaTokTtfCreator.gridH else {
                continue
            }
            var rects: [RectI] = []
            for row in 0 ..< GGMediaTokTtfCreator.gridH {
                let yBottom = (baselineRow - row) * cellH + gap / 2
                let yTop = (baselineRow - row + 1) * cellH - gap / 2
                let slant = (baselineRow - row) * slantPerRow
                var col = 0
                while col < GGMediaTokTtfCreator.gridW {
                    if !grid[row * GGMediaTokTtfCreator.gridW + col] {
                        col += 1
                        continue
                    }
                    let startCol = col
                    if pixelStyle == 1 {
                        rects.append(RectI(x1: 40 + startCol * cellW + gap / 2 + slant, y1: yBottom, x2: 40 + (startCol + 1) * cellW - gap / 2 + slant, y2: yTop))
                        col += 1
                    } else {
                        while col < GGMediaTokTtfCreator.gridW && grid[row * GGMediaTokTtfCreator.gridW + col] {
                            col += 1
                        }
                        rects.append(RectI(x1: 40 + startCol * cellW + slant, y1: yBottom, x2: 40 + col * cellW + slant, y2: yTop))
                    }
                }
            }
            charRects[UInt16(scalar.value)] = rects
        }

        let cps = charRects.keys.filter { $0 != 32 }.sorted()
        var glyphOrder: [UInt16] = [0, 32]
        glyphOrder.append(contentsOf: cps)
        var cpToGid: [UInt16: UInt16] = [32: 1]
        for (idx, cp) in cps.enumerated() {
            cpToGid[cp] = UInt16(idx + 2)
        }
        let numGlyphs = UInt16(glyphOrder.count)

        var glyf = Data()
        var loca = Data()
        var hmtx = Data()
        var maxPoints: UInt16 = 0
        var maxContours: UInt16 = 0

        for gid in 0 ..< Int(numGlyphs) {
            GGMediaTokTtfCreator.appendU32(&loca, UInt32(glyf.count))
            let cp = glyphOrder[gid]
            let rects: [RectI]
            let adv: UInt16
            let lsb: Int16
            if gid == 0 {
                rects = [RectI(x1: 80, y1: 0, x2: 520, y2: 720)]
                adv = 600
                lsb = 80
            } else if cp == 32 {
                rects = []
                adv = 400
                lsb = 0
            } else {
                rects = charRects[cp] ?? []
                if !rects.isEmpty {
                    let xMin = rects.map { min($0.x1, $0.x2) }.min() ?? 0
                    let xMax = rects.map { max($0.x1, $0.x2) }.max() ?? 400
                    adv = UInt16(max(440, xMax + 70))
                    lsb = Int16(xMin)
                } else {
                    adv = 400
                    lsb = 0
                }
            }
            glyf.append(GGMediaTokTtfCreator.buildSimpleGlyph(rects))
            GGMediaTokTtfCreator.appendU16(&hmtx, adv)
            GGMediaTokTtfCreator.appendS16(&hmtx, lsb)
            maxPoints = max(maxPoints, UInt16(rects.count * 4))
            maxContours = max(maxContours, UInt16(rects.count))
        }
        GGMediaTokTtfCreator.appendU32(&loca, UInt32(glyf.count))

        // cmap format 4
        let mappedCps = cpToGid.keys.sorted()
        var segs: [CmapSeg] = []
        for cp in mappedCps {
            let gid = cpToGid[cp] ?? 0
            let delta = UInt16((Int(gid) - Int(cp)) & 0xFFFF)
            if !segs.isEmpty && cp == segs[segs.count - 1].end &+ 1 && delta == segs[segs.count - 1].delta {
                segs[segs.count - 1].end = cp
            } else {
                segs.append(CmapSeg(start: cp, end: cp, delta: delta))
            }
        }
        segs.append(CmapSeg(start: 0xFFFF, end: 0xFFFF, delta: 1))
        let segCount = UInt16(segs.count)
        var pow2: UInt16 = 1
        var es: UInt16 = 0
        while pow2 * 2 <= segCount {
            pow2 *= 2
            es += 1
        }
        let sr = pow2 * 2
        let rs = segCount * 2 - sr

        var fmt4 = Data()
        GGMediaTokTtfCreator.appendU16(&fmt4, 4)
        GGMediaTokTtfCreator.appendU16(&fmt4, 16 + segCount * 8)
        GGMediaTokTtfCreator.appendU16(&fmt4, 0)
        GGMediaTokTtfCreator.appendU16(&fmt4, segCount * 2)
        GGMediaTokTtfCreator.appendU16(&fmt4, sr)
        GGMediaTokTtfCreator.appendU16(&fmt4, es)
        GGMediaTokTtfCreator.appendU16(&fmt4, rs)
        for s in segs { GGMediaTokTtfCreator.appendU16(&fmt4, s.end) }
        GGMediaTokTtfCreator.appendU16(&fmt4, 0)
        for s in segs { GGMediaTokTtfCreator.appendU16(&fmt4, s.start) }
        for s in segs { GGMediaTokTtfCreator.appendU16(&fmt4, s.delta) }
        for _ in segs { GGMediaTokTtfCreator.appendU16(&fmt4, 0) }

        var cmap = Data()
        GGMediaTokTtfCreator.appendU16(&cmap, 0)
        GGMediaTokTtfCreator.appendU16(&cmap, 2)
        GGMediaTokTtfCreator.appendU16(&cmap, 0); GGMediaTokTtfCreator.appendU16(&cmap, 3); GGMediaTokTtfCreator.appendU32(&cmap, 20)
        GGMediaTokTtfCreator.appendU16(&cmap, 3); GGMediaTokTtfCreator.appendU16(&cmap, 1); GGMediaTokTtfCreator.appendU32(&cmap, 20)
        cmap.append(fmt4)

        // name table
        let asciiPs = fontName.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let safePs = asciiPs.isEmpty ? "MediaTokCustom" : asciiPs
        let namePairs: [(UInt16, String)] = [
            (1, fontName), (2, "Regular"), (3, "MediaTok-\(safePs)"),
            (4, fontName), (5, "Version 1.0"), (6, safePs)
        ]
        var recs: [NameRec] = []
        var strBlob = Data()
        for (nid, s) in namePairs {
            var b = Data()
            for scalar in s.unicodeScalars {
                b.append((scalar.value >= 32 && scalar.value <= 126) ? UInt8(scalar.value) : UInt8(63))
            }
            recs.append(NameRec(pid: 1, eid: 0, lid: 0, nid: nid, len: UInt16(b.count), off: UInt16(strBlob.count)))
            strBlob.append(b)
        }
        for (nid, s) in namePairs {
            var b = Data()
            for unit in s.utf16 {
                GGMediaTokTtfCreator.appendU16(&b, unit)
            }
            recs.append(NameRec(pid: 3, eid: 1, lid: 0x0409, nid: nid, len: UInt16(b.count), off: UInt16(strBlob.count)))
            strBlob.append(b)
        }
        recs.sort { ($0.pid, $0.eid, $0.lid, $0.nid) < ($1.pid, $1.eid, $1.lid, $1.nid) }
        var nameTbl = Data()
        GGMediaTokTtfCreator.appendU16(&nameTbl, 0)
        GGMediaTokTtfCreator.appendU16(&nameTbl, UInt16(recs.count))
        GGMediaTokTtfCreator.appendU16(&nameTbl, UInt16(6 + recs.count * 12))
        for r in recs {
            GGMediaTokTtfCreator.appendU16(&nameTbl, r.pid)
            GGMediaTokTtfCreator.appendU16(&nameTbl, r.eid)
            GGMediaTokTtfCreator.appendU16(&nameTbl, r.lid)
            GGMediaTokTtfCreator.appendU16(&nameTbl, r.nid)
            GGMediaTokTtfCreator.appendU16(&nameTbl, r.len)
            GGMediaTokTtfCreator.appendU16(&nameTbl, r.off)
        }
        nameTbl.append(strBlob)

        var head = Data()
        GGMediaTokTtfCreator.appendU32(&head, 0x00010000); GGMediaTokTtfCreator.appendU32(&head, 0x00010000)
        GGMediaTokTtfCreator.appendU32(&head, 0); GGMediaTokTtfCreator.appendU32(&head, 0x5F0F3CF5)
        GGMediaTokTtfCreator.appendU16(&head, 0x000B); GGMediaTokTtfCreator.appendU16(&head, 1000)
        for _ in 0 ..< 4 { GGMediaTokTtfCreator.appendU32(&head, 0) }
        GGMediaTokTtfCreator.appendS16(&head, 0); GGMediaTokTtfCreator.appendS16(&head, -200)
        GGMediaTokTtfCreator.appendS16(&head, 1000); GGMediaTokTtfCreator.appendS16(&head, 900)
        GGMediaTokTtfCreator.appendU16(&head, 0); GGMediaTokTtfCreator.appendU16(&head, 8)
        GGMediaTokTtfCreator.appendS16(&head, 2); GGMediaTokTtfCreator.appendS16(&head, 1); GGMediaTokTtfCreator.appendS16(&head, 0)

        var hhea = Data()
        GGMediaTokTtfCreator.appendU32(&hhea, 0x00010000)
        GGMediaTokTtfCreator.appendS16(&hhea, 850); GGMediaTokTtfCreator.appendS16(&hhea, -200)
        GGMediaTokTtfCreator.appendS16(&hhea, 50); GGMediaTokTtfCreator.appendU16(&hhea, 1000)
        GGMediaTokTtfCreator.appendS16(&hhea, 0); GGMediaTokTtfCreator.appendS16(&hhea, 0)
        GGMediaTokTtfCreator.appendS16(&hhea, 1000); GGMediaTokTtfCreator.appendS16(&hhea, 1)
        for _ in 0 ..< 7 { GGMediaTokTtfCreator.appendS16(&hhea, 0) }
        GGMediaTokTtfCreator.appendU16(&hhea, numGlyphs)

        var maxp = Data()
        GGMediaTokTtfCreator.appendU32(&maxp, 0x00010000)
        GGMediaTokTtfCreator.appendU16(&maxp, numGlyphs)
        GGMediaTokTtfCreator.appendU16(&maxp, maxPoints)
        GGMediaTokTtfCreator.appendU16(&maxp, maxContours)
        GGMediaTokTtfCreator.appendU16(&maxp, 0); GGMediaTokTtfCreator.appendU16(&maxp, 0); GGMediaTokTtfCreator.appendU16(&maxp, 2)
        for _ in 0 ..< 8 { GGMediaTokTtfCreator.appendU16(&maxp, 0) }

        var os2 = Data()
        GGMediaTokTtfCreator.appendU16(&os2, 3); GGMediaTokTtfCreator.appendS16(&os2, 600)
        GGMediaTokTtfCreator.appendU16(&os2, 400); GGMediaTokTtfCreator.appendU16(&os2, 5); GGMediaTokTtfCreator.appendS16(&os2, 0)
        GGMediaTokTtfCreator.appendS16(&os2, 650); GGMediaTokTtfCreator.appendS16(&os2, 600); GGMediaTokTtfCreator.appendS16(&os2, 0); GGMediaTokTtfCreator.appendS16(&os2, 75)
        GGMediaTokTtfCreator.appendS16(&os2, 650); GGMediaTokTtfCreator.appendS16(&os2, 600); GGMediaTokTtfCreator.appendS16(&os2, 0); GGMediaTokTtfCreator.appendS16(&os2, 350)
        GGMediaTokTtfCreator.appendS16(&os2, 50); GGMediaTokTtfCreator.appendS16(&os2, 300); GGMediaTokTtfCreator.appendS16(&os2, 0)
        os2.append(contentsOf: [2, 0, 5, 3, 0, 0, 0, 0, 0, 0])
        GGMediaTokTtfCreator.appendU32(&os2, 0x00000201); GGMediaTokTtfCreator.appendU32(&os2, 0); GGMediaTokTtfCreator.appendU32(&os2, 0); GGMediaTokTtfCreator.appendU32(&os2, 0)
        os2.append(contentsOf: [UInt8]("MTOK".utf8))
        GGMediaTokTtfCreator.appendU16(&os2, 0x0040); GGMediaTokTtfCreator.appendU16(&os2, 32)
        GGMediaTokTtfCreator.appendU16(&os2, mappedCps.last ?? 0x04FF)
        GGMediaTokTtfCreator.appendS16(&os2, 850); GGMediaTokTtfCreator.appendS16(&os2, -200); GGMediaTokTtfCreator.appendS16(&os2, 50)
        GGMediaTokTtfCreator.appendU16(&os2, 900); GGMediaTokTtfCreator.appendU16(&os2, 250)
        GGMediaTokTtfCreator.appendU32(&os2, 0x00000005); GGMediaTokTtfCreator.appendU32(&os2, 0)
        GGMediaTokTtfCreator.appendS16(&os2, 500); GGMediaTokTtfCreator.appendS16(&os2, 720)
        GGMediaTokTtfCreator.appendU16(&os2, 0); GGMediaTokTtfCreator.appendU16(&os2, 32); GGMediaTokTtfCreator.appendU16(&os2, 0)

        var post = Data()
        GGMediaTokTtfCreator.appendU32(&post, 0x00030000); GGMediaTokTtfCreator.appendU32(&post, 0)
        GGMediaTokTtfCreator.appendS16(&post, -100); GGMediaTokTtfCreator.appendS16(&post, 50)
        for _ in 0 ..< 5 { GGMediaTokTtfCreator.appendU32(&post, 0) }

        let tables: [(String, Data)] = [
            ("OS/2", os2), ("cmap", cmap), ("glyf", glyf), ("head", head),
            ("hhea", hhea), ("hmtx", hmtx), ("loca", loca), ("maxp", maxp),
            ("name", nameTbl), ("post", post)
        ].sorted { $0.0 < $1.0 }

        let nt = UInt16(tables.count)
        var tpow2: UInt16 = 1
        var tes: UInt16 = 0
        while tpow2 * 2 <= nt {
            tpow2 *= 2
            tes += 1
        }
        let tsr = tpow2 * 16
        let trs = nt * 16 - tsr

        var full = Data()
        GGMediaTokTtfCreator.appendU32(&full, 0x00010000)
        GGMediaTokTtfCreator.appendU16(&full, nt)
        GGMediaTokTtfCreator.appendU16(&full, tsr)
        GGMediaTokTtfCreator.appendU16(&full, tes)
        GGMediaTokTtfCreator.appendU16(&full, trs)

        var offset = UInt32(12 + Int(nt) * 16)
        var headOffset = 0
        var body = Data()
        for (tag, data) in tables {
            full.append(contentsOf: [UInt8](tag.utf8))
            GGMediaTokTtfCreator.appendU32(&full, GGMediaTokTtfCreator.calcChecksum(data))
            GGMediaTokTtfCreator.appendU32(&full, offset)
            GGMediaTokTtfCreator.appendU32(&full, UInt32(data.count))
            if tag == "head" {
                headOffset = Int(offset)
            }
            body.append(data)
            let pad = (4 - (data.count % 4)) % 4
            if pad > 0 {
                body.append(contentsOf: [UInt8](repeating: 0, count: pad))
            }
            offset += UInt32(data.count + pad)
        }
        full.append(body)
        let adj = UInt32(0xB1B0AFBA) &- GGMediaTokTtfCreator.calcChecksum(full)
        full[headOffset + 8] = UInt8((adj >> 24) & 0xFF)
        full[headOffset + 9] = UInt8((adj >> 16) & 0xFF)
        full[headOffset + 10] = UInt8((adj >> 8) & 0xFF)
        full[headOffset + 11] = UInt8(adj & 0xFF)
        return full
    }
}

// MARK: - Native UIKit Drawing Canvas & ViewController

private final class GGGlyphCanvasView: UIView {
    var grid: [Bool] = [Bool](repeating: false, count: GGMediaTokTtfCreator.gridW * GGMediaTokTtfCreator.gridH) {
        didSet { self.setNeedsDisplay() }
    }
    var onGridChanged: (([Bool]) -> Void)?
    private var paintMode = true

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cw = rect.width / CGFloat(GGMediaTokTtfCreator.gridW)
        let ch = rect.height / CGFloat(GGMediaTokTtfCreator.gridH)

        ctx.setFillColor(UIColor.secondarySystemBackground.cgColor)
        ctx.fill(rect)

        for r in 0 ..< GGMediaTokTtfCreator.gridH {
            for c in 0 ..< GGMediaTokTtfCreator.gridW {
                let cell = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw, height: ch)
                if self.grid[r * GGMediaTokTtfCreator.gridW + c] {
                    ctx.setFillColor(UIColor.systemBlue.cgColor)
                    ctx.fill(cell.insetBy(dx: 1.5, dy: 1.5))
                }
                ctx.setStrokeColor(UIColor.separator.cgColor)
                ctx.setLineWidth(0.8)
                ctx.stroke(cell)
            }
        }
        let baseY = 10.0 * ch
        ctx.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.75).cgColor)
        ctx.setLineWidth(2.0)
        ctx.move(to: CGPoint(x: 0.0, y: baseY))
        ctx.addLine(to: CGPoint(x: rect.width, y: baseY))
        ctx.strokePath()
    }

    private func cellIndex(at point: CGPoint) -> Int {
        let c = max(0, min(GGMediaTokTtfCreator.gridW - 1, Int(point.x / (self.bounds.width / CGFloat(GGMediaTokTtfCreator.gridW)))))
        let r = max(0, min(GGMediaTokTtfCreator.gridH - 1, Int(point.y / (self.bounds.height / CGFloat(GGMediaTokTtfCreator.gridH)))))
        return r * GGMediaTokTtfCreator.gridW + c
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        let idx = self.cellIndex(at: pt)
        self.paintMode = !self.grid[idx]
        self.grid[idx] = self.paintMode
        self.onGridChanged?(self.grid)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        let idx = self.cellIndex(at: pt)
        if self.grid[idx] != self.paintMode {
            self.grid[idx] = self.paintMode
            self.onGridChanged?(self.grid)
        }
    }
}

private final class GGLivePixelPreviewView: UIView {
    var grids: [Character: [Bool]] = [:] {
        didSet { self.setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor.tertiarySystemBackground.cgColor)
        ctx.fill(rect)
        ctx.setFillColor(UIColor.label.cgColor)

        let cell: CGFloat = 2.6
        var x: CGFloat = 10.0
        let y0: CGFloat = 6.0
        for ch in "Привет MediaTok 123" {
            if ch == " " {
                x += cell * 4.5
                continue
            }
            guard let g = self.grids[ch] else { continue }
            var maxCol = 0
            for r in 0 ..< GGMediaTokTtfCreator.gridH {
                for c in 0 ..< GGMediaTokTtfCreator.gridW {
                    if g[r * GGMediaTokTtfCreator.gridW + c] {
                        ctx.fill(CGRect(x: x + CGFloat(c) * cell, y: y0 + CGFloat(r) * cell, width: cell, height: cell))
                        if c > maxCol { maxCol = c }
                    }
                }
            }
            x += CGFloat(max(4, maxCol + 2)) * cell
            if x > rect.width - 14.0 { break }
        }
    }
}

private final class GGTtfCreatorViewController: UIViewController {
    private var grids: [Character: [Bool]] = GGMediaTokTtfCreator.rasterizeTemplate()
    private var edited: Set<Character> = []
    private var currentChar: Character = "А"
    private var charButtons: [Character: UIButton] = [:]

    private let nameField = UITextField()
    private let styleControl = UISegmentedControl(items: ["Плотный", "Пиксель", "Жирный", "Курсив"])
    private let previewView = GGLivePixelPreviewView()
    private let canvasView = GGGlyphCanvasView()
    private let charScroll = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Создать шрифт (.ttf)"
        self.view.backgroundColor = .systemBackground

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Собрать .ttf", style: .done, target: self, action: #selector(self.buildTapped))

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12.0),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16.0),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -20.0),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32.0)
        ])

        self.nameField.borderStyle = .roundedRect
        self.nameField.text = "Мой Шрифт"
        self.nameField.placeholder = "Название шрифта"
        stack.addArrangedSubview(self.nameField)

        self.styleControl.selectedSegmentIndex = 0
        stack.addArrangedSubview(self.styleControl)

        self.previewView.grids = self.grids
        self.previewView.layer.cornerRadius = 8.0
        self.previewView.clipsToBounds = true
        self.previewView.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        stack.addArrangedSubview(self.previewView)

        self.charScroll.showsHorizontalScrollIndicator = true
        self.charScroll.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
        let charStack = UIStackView()
        charStack.axis = .horizontal
        charStack.spacing = 4.0
        charStack.translatesAutoresizingMaskIntoConstraints = false
        self.charScroll.addSubview(charStack)
        NSLayoutConstraint.activate([
            charStack.topAnchor.constraint(equalTo: self.charScroll.topAnchor),
            charStack.leadingAnchor.constraint(equalTo: self.charScroll.leadingAnchor),
            charStack.trailingAnchor.constraint(equalTo: self.charScroll.trailingAnchor),
            charStack.bottomAnchor.constraint(equalTo: self.charScroll.bottomAnchor),
            charStack.heightAnchor.constraint(equalTo: self.charScroll.heightAnchor)
        ])

        for (idx, ch) in GGMediaTokTtfCreator.charset.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(String(ch), for: .normal)
            btn.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16.0)
            btn.layer.cornerRadius = 6.0
            btn.tag = idx
            btn.widthAnchor.constraint(equalToConstant: 36.0).isActive = true
            btn.addTarget(self, action: #selector(self.charSelected(_:)), for: .touchUpInside)
            self.charButtons[ch] = btn
            charStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(self.charScroll)

        let canvasContainer = UIView()
        self.canvasView.translatesAutoresizingMaskIntoConstraints = false
        self.canvasView.layer.cornerRadius = 8.0
        self.canvasView.clipsToBounds = true
        canvasContainer.addSubview(self.canvasView)
        NSLayoutConstraint.activate([
            self.canvasView.centerXAnchor.constraint(equalTo: canvasContainer.centerXAnchor),
            self.canvasView.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            self.canvasView.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),
            self.canvasView.widthAnchor.constraint(equalToConstant: 250.0),
            self.canvasView.heightAnchor.constraint(equalToConstant: 300.0)
        ])
        stack.addArrangedSubview(canvasContainer)

        self.canvasView.grid = self.grids[self.currentChar] ?? [Bool](repeating: false, count: GGMediaTokTtfCreator.gridW * GGMediaTokTtfCreator.gridH)
        self.canvasView.onGridChanged = { [weak self] newGrid in
            guard let strongSelf = self else { return }
            strongSelf.grids[strongSelf.currentChar] = newGrid
            strongSelf.edited.insert(strongSelf.currentChar)
            strongSelf.previewView.grids = strongSelf.grids
            strongSelf.updateCharStyles()
        }

        let toolsStack = UIStackView()
        toolsStack.axis = .horizontal
        toolsStack.distribution = .fillEqually
        toolsStack.spacing = 6.0
        for (title, sel) in [
            ("Очистить", #selector(self.clearTapped)),
            ("Зеркало", #selector(self.mirrorTapped)),
            ("Жирнее", #selector(self.boldTapped)),
            ("Сброс всех", #selector(self.resetAllTapped))
        ] {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.backgroundColor = .secondarySystemBackground
            b.layer.cornerRadius = 8.0
            b.heightAnchor.constraint(equalToConstant: 34.0).isActive = true
            b.addTarget(self, action: sel, for: .touchUpInside)
            toolsStack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(toolsStack)

        let hint = UILabel()
        hint.numberOfLines = 0
        hint.font = UIFont.systemFont(ofSize: 12.0)
        hint.textColor = .secondaryLabel
        hint.text = "Рисуй пальцем по клеткам (красная линия — низ строки). Все 139 букв А–Я, A–Z, 0–9 предзаполнены шаблоном — перерисуй нужные и нажми «Собрать .ttf»!"
        stack.addArrangedSubview(hint)

        self.updateCharStyles()
    }

    private func updateCharStyles() {
        for (ch, btn) in self.charButtons {
            if ch == self.currentChar {
                btn.backgroundColor = .systemBlue
                btn.setTitleColor(.white, for: .normal)
            } else if self.edited.contains(ch) {
                btn.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.25)
                btn.setTitleColor(.label, for: .normal)
            } else {
                btn.backgroundColor = .secondarySystemBackground
                btn.setTitleColor(.label, for: .normal)
            }
        }
    }

    @objc private func charSelected(_ sender: UIButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < GGMediaTokTtfCreator.charset.count else { return }
        self.currentChar = GGMediaTokTtfCreator.charset[idx]
        self.canvasView.grid = self.grids[self.currentChar] ?? [Bool](repeating: false, count: GGMediaTokTtfCreator.gridW * GGMediaTokTtfCreator.gridH)
        self.updateCharStyles()
    }

    @objc private func clearTapped() {
        let blank = [Bool](repeating: false, count: GGMediaTokTtfCreator.gridW * GGMediaTokTtfCreator.gridH)
        self.grids[self.currentChar] = blank
        self.edited.insert(self.currentChar)
        self.canvasView.grid = blank
        self.previewView.grids = self.grids
        self.updateCharStyles()
    }

    @objc private func mirrorTapped() {
        var g = self.grids[self.currentChar] ?? [Bool](repeating: false, count: GGMediaTokTtfCreator.gridW * GGMediaTokTtfCreator.gridH)
        for r in 0 ..< GGMediaTokTtfCreator.gridH {
            for c in 0 ..< (GGMediaTokTtfCreator.gridW / 2) {
                let a = r * GGMediaTokTtfCreator.gridW + c
                let b = r * GGMediaTokTtfCreator.gridW + (GGMediaTokTtfCreator.gridW - 1 - c)
                g.swapAt(a, b)
            }
        }
        self.grids[self.currentChar] = g
        self.edited.insert(self.currentChar)
        self.canvasView.grid = g
        self.previewView.grids = self.grids
        self.updateCharStyles()
    }

    @objc private func boldTapped() {
        let orig = self.grids[self.currentChar] ?? [Bool](repeating: false, count: GGMediaTokTtfCreator.gridW * GGMediaTokTtfCreator.gridH)
        var g = orig
        for r in 0 ..< GGMediaTokTtfCreator.gridH {
            for c in 0 ..< (GGMediaTokTtfCreator.gridW - 1) {
                if orig[r * GGMediaTokTtfCreator.gridW + c] {
                    g[r * GGMediaTokTtfCreator.gridW + c + 1] = true
                }
            }
        }
        self.grids[self.currentChar] = g
        self.edited.insert(self.currentChar)
        self.canvasView.grid = g
        self.previewView.grids = self.grids
        self.updateCharStyles()
    }

    @objc private func resetAllTapped() {
        self.grids = GGMediaTokTtfCreator.rasterizeTemplate()
        self.edited.removeAll()
        self.canvasView.grid = self.grids[self.currentChar] ?? [Bool](repeating: false, count: GGMediaTokTtfCreator.gridW * GGMediaTokTtfCreator.gridH)
        self.previewView.grids = self.grids
        self.updateCharStyles()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func buildTapped() {
        self.view.endEditing(true)
        let name = self.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalName = name.isEmpty ? "MediaTok Custom" : name
        let data = GGMediaTokTtfCreator.compileTtf(fontNameRaw: finalName, grids: self.grids, pixelStyle: self.styleControl.selectedSegmentIndex)
        let safeFile = finalName.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let fileName = (safeFile.isEmpty ? "custom_font" : safeFile) + ".ttf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            self.showAlert(title: "Ошибка", message: "Не удалось записать .ttf файл")
            return
        }

        GGCustomFonts.importFont(at: tempURL) { [weak self] result in
            guard let strongSelf = self else { return }
            switch result {
            case let .added(font):
                let alert = UIAlertController(
                    title: "Шрифт «\(font.familyName)» собран!",
                    message: "Файл (\(data.count / 1024) КБ) добавлен и выбран. Перезапустите MediaTok, чтобы применить его везде.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Поделиться .ttf", style: .default, handler: { _ in
                    let share = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                    if let pop = share.popoverPresentationController {
                        pop.sourceView = strongSelf.view
                        pop.sourceRect = CGRect(x: strongSelf.view.bounds.midX, y: strongSelf.view.bounds.midY, width: 0.0, height: 0.0)
                        pop.permittedArrowDirections = []
                    }
                    strongSelf.present(share, animated: true)
                }))
                alert.addAction(UIAlertAction(title: "Готово", style: .cancel, handler: { _ in
                    strongSelf.dismiss(animated: true)
                }))
                strongSelf.present(alert, animated: true)
            case .notAFont:
                strongSelf.showAlert(title: "Ошибка", message: "CoreText не смог прочитать собранный шрифт")
            case .tooMany:
                strongSelf.showAlert(title: "Лимит", message: GGStrings.Appearance.Font.tooMany)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.present(alert, animated: true)
    }
}
