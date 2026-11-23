import Foundation
import Accelerate
#if canImport(UIKit)
import UIKit
import CoreGraphics
#endif
#if canImport(Metal) && canImport(MetalPerformanceShadersGraph) && !targetEnvironment(simulator)
import Metal
import MetalPerformanceShaders
import MetalPerformanceShadersGraph
#endif

/// Offline Waifu2x `upconv_7` 7-layer super-resolution neural network (`mt_waifu2x_art_2x.bin` & `mt_waifu2x_photo_2x.bin`).
///
/// Architecture:
/// - Layers 0..5: standard `3x3` valid convolutions (`3->16->32->64->128->128->256`), `LeakyReLU(alpha = 0.1)`.
/// - Layer 6: `4x4 stride=2 pad=3` transposed convolution (`256->3`), converted algebraically at load time into an
///   exact `3x3` valid subpixel convolution (`256->12`, `stride=1, pad=0`) + `2x2` pixel shuffle (`< 1e-7` error).
/// - Runs on Apple GPU/ANE via cached fixed-tile `MPSGraph` (`[1, 3, 174, 174] -> [1, 12, 160, 160]`), with a
///   SIMD `Accelerate` (`vDSP_mmul`) fallback when Metal is unavailable.
public enum MTNeuralWaifu2xStyle: String, Sendable {
    case art = "mt_waifu2x_art_2x"
    case photo = "mt_waifu2x_photo_2x"

    public var displayTitle: String {
        switch self {
        case .art: return "Манга / Арт"
        case .photo: return "Фото"
        }
    }
}

public enum MTNeuralWaifu2xError: LocalizedError {
    case modelNotFound(String)
    case corruptedWeights(String)
    case invalidImage
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .modelNotFound(name):
            return "Не найден встроенный файл нейросети \(name).bin"
        case let .corruptedWeights(reason):
            return "Повреждены веса нейросети Waifu2x (\(reason))"
        case .invalidImage:
            return "Не удалось декодировать пиксели изображения"
        case .cancelled:
            return "Апскейл отменён"
        }
    }
}

public final class MTNeuralWaifu2xModel {
    public struct Conv3x3Layer {
        public let inChannels: Int
        public let outChannels: Int
        public let weights: [Float] // [outChannels, inChannels, 3, 3]
        public let bias: [Float]    // [outChannels]
        public let leakySlope: Float
    }

    public static let tileInnerSize: Int = 160
    public static let tilePad: Int = 7
    public static let tilePaddedSize: Int = 174 // 160 + 2 * 7

    public let layers: [Conv3x3Layer]

    #if canImport(Metal) && canImport(MetalPerformanceShadersGraph) && !targetEnvironment(simulator)
    private struct MPSPipeline {
        let mpsDevice: MPSGraphDevice
        let queue: MTLCommandQueue
        let graph: MPSGraph
        let inputTensor: MPSGraphTensor
        let outputTensor: MPSGraphTensor
    }
    private let mpsLock = NSLock()
    private var cachedMPS: MPSPipeline?
    private var didAttemptMPS: Bool = false
    #endif

    private static let cacheLock = NSLock()
    private static var cachedModels: [MTNeuralWaifu2xStyle: MTNeuralWaifu2xModel] = [:]

    public static func shared(style: MTNeuralWaifu2xStyle) throws -> MTNeuralWaifu2xModel {
        self.cacheLock.lock()
        if let existing = self.cachedModels[style] {
            self.cacheLock.unlock()
            return existing
        }
        self.cacheLock.unlock()

        let url = Bundle.main.url(forResource: style.rawValue, withExtension: "bin", subdirectory: "MediaTokModels")
            ?? Bundle.main.url(forResource: style.rawValue, withExtension: "bin")
        guard let modelURL = url else {
            throw MTNeuralWaifu2xError.modelNotFound(style.rawValue)
        }
        let data = try Data(contentsOf: modelURL)
        let loaded = try MTNeuralWaifu2xModel(data: data)

        self.cacheLock.lock()
        self.cachedModels[style] = loaded
        self.cacheLock.unlock()
        return loaded
    }

    @inline(__always)
    public static func halfBitsToFloat(_ h: UInt16) -> Float {
        let sign = UInt32(h & 0x8000) << 16
        let exp = UInt32((h >> 10) & 0x1F)
        let mant = UInt32(h & 0x03FF)
        if exp == 0 {
            if mant == 0 {
                return Float(bitPattern: sign)
            }
            let val = Float(mant) * (1.0 / 16777216.0)
            return (h & 0x8000) != 0 ? -val : val
        } else if exp == 31 {
            return Float(bitPattern: sign | 0x7F800000 | (mant << 13))
        }
        let bits = sign | ((exp + 112) << 23) | (mant << 13)
        return Float(bitPattern: bits)
    }

    public init(data: Data) throws {
        guard data.count > 32 else {
            throw MTNeuralWaifu2xError.corruptedWeights("слишком малый размер файла")
        }

        func readU32(_ bytes: UnsafeRawBufferPointer, _ offset: inout Int) throws -> UInt32 {
            guard offset + 4 <= bytes.count else {
                throw MTNeuralWaifu2xError.corruptedWeights("неожиданный конец заголовка")
            }
            let b0 = UInt32(bytes[offset])
            let b1 = UInt32(bytes[offset + 1]) << 8
            let b2 = UInt32(bytes[offset + 2]) << 16
            let b3 = UInt32(bytes[offset + 3]) << 24
            offset += 4
            return b0 | b1 | b2 | b3
        }

        func readF16Array(_ bytes: UnsafeRawBufferPointer, _ offset: inout Int, count: Int) throws -> [Float] {
            let byteCount = count * 2
            guard count >= 0, offset + byteCount <= bytes.count else {
                throw MTNeuralWaifu2xError.corruptedWeights("неожиданный конец тензора")
            }
            var out = [Float](repeating: 0.0, count: count)
            for i in 0 ..< count {
                let lo = UInt16(bytes[offset + i * 2])
                let hi = UInt16(bytes[offset + i * 2 + 1]) << 8
                out[i] = MTNeuralWaifu2xModel.halfBitsToFloat(lo | hi)
            }
            offset += byteCount
            return out
        }

        var parsedLayers: [Conv3x3Layer] = []
        try data.withUnsafeBytes { raw in
            guard raw.count >= 8,
                  raw[0] == 0x4D, raw[1] == 0x54, raw[2] == 0x57, raw[3] == 0x32 else {
                throw MTNeuralWaifu2xError.corruptedWeights("неверная сигнатура MTW2")
            }
            var pos = 4
            let numLayers = Int(try readU32(raw, &pos))
            guard numLayers == 7 else {
                throw MTNeuralWaifu2xError.corruptedWeights("ожидалось 7 слоёв, получено \(numLayers)")
            }
            parsedLayers.reserveCapacity(7)

            for idx in 0 ..< numLayers {
                let isDeconv = try readU32(raw, &pos)
                let d0 = Int(try readU32(raw, &pos))
                let d1 = Int(try readU32(raw, &pos))
                let kH = Int(try readU32(raw, &pos))
                let kW = Int(try readU32(raw, &pos))
                let biasLen = Int(try readU32(raw, &pos))
                let wCount = d0 * d1 * kH * kW
                let ws = try readF16Array(raw, &pos, count: wCount)
                let bs = try readF16Array(raw, &pos, count: biasLen)

                if isDeconv == 0 {
                    guard idx < 6, kH == 3, kW == 3, biasLen == d0 else {
                        throw MTNeuralWaifu2xError.corruptedWeights("неверная форма слоя L\(idx)")
                    }
                    parsedLayers.append(Conv3x3Layer(
                        inChannels: d1,
                        outChannels: d0,
                        weights: ws,
                        bias: bs,
                        leakySlope: 0.1
                    ))
                } else {
                    // Layer 6: [inC=256, outC=3, 4, 4] stride=2 pad=3 -> exact [outC=12, inC=256, 3, 3] subpixel conv!
                    guard idx == 6, d0 == 256, d1 == 3, kH == 4, kW == 4, biasLen == 3 else {
                        throw MTNeuralWaifu2xError.corruptedWeights("неверная форма выходного слоя L6")
                    }
                    let inC = d0
                    let outRGB = d1
                    let subOutC = outRGB * 4 // 12
                    var subW = [Float](repeating: 0.0, count: subOutC * inC * 9)
                    var subB = [Float](repeating: 0.0, count: subOutC)
                    for oc in 0 ..< outRGB {
                        for ry in 0 ..< 2 {
                            for rx in 0 ..< 2 {
                                let sc = oc * 4 + ry * 2 + rx
                                subB[sc] = bs[oc]
                                for ic in 0 ..< inC {
                                    let srcBase = (ic * outRGB + oc) * 16
                                    let dstBase = (sc * inC + ic) * 9
                                    for u in 0 ..< 3 {
                                        let dy = 3 + ry - 2 * u
                                        if dy >= 0 && dy < 4 {
                                            for v in 0 ..< 3 {
                                                let dx = 3 + rx - 2 * v
                                                if dx >= 0 && dx < 4 {
                                                    subW[dstBase + u * 3 + v] = ws[srcBase + dy * 4 + dx]
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    parsedLayers.append(Conv3x3Layer(
                        inChannels: inC,
                        outChannels: subOutC,
                        weights: subW,
                        bias: subB,
                        leakySlope: 1.0
                    ))
                }
            }
        }
        self.layers = parsedLayers
    }

    #if canImport(Metal) && canImport(MetalPerformanceShadersGraph) && !targetEnvironment(simulator)
    private func mpsPipelineIfAvailable() -> MPSPipeline? {
        self.mpsLock.lock()
        defer { self.mpsLock.unlock() }
        if self.didAttemptMPS {
            return self.cachedMPS
        }
        self.didAttemptMPS = true

        guard let mtlDevice = MTLCreateSystemDefaultDevice(),
              MPSSupportsMTLDevice(mtlDevice),
              let queue = mtlDevice.makeCommandQueue() else {
            return nil
        }
        let mpsDevice = MPSGraphDevice(mtlDevice: mtlDevice)
        let graph = MPSGraph()
        let pSize = NSNumber(value: Self.tilePaddedSize)
        let inputPlaceholder = graph.placeholder(
            shape: [1, 3, pSize, pSize],
            dataType: .float32,
            name: "waifu2x_input"
        )

        var cur: MPSGraphTensor = inputPlaceholder
        for (idx, layer) in self.layers.enumerated() {
            guard let desc = MPSGraphConvolution2DOpDescriptor(
                strideInX: 1,
                strideInY: 1,
                dilationRateInX: 1,
                dilationRateInY: 1,
                groups: 1,
                paddingLeft: 0,
                paddingRight: 0,
                paddingTop: 0,
                paddingBottom: 0,
                paddingStyle: .explicit,
                dataLayout: .NCHW,
                weightsLayout: .OIHW
            ) else {
                return nil
            }
            let wData = layer.weights.withUnsafeBufferPointer { Data(buffer: $0) }
            let bData = layer.bias.withUnsafeBufferPointer { Data(buffer: $0) }
            let wTensor = graph.constant(
                wData,
                shape: [NSNumber(value: layer.outChannels), NSNumber(value: layer.inChannels), 3, 3],
                dataType: .float32
            )
            let bTensor = graph.constant(
                bData,
                shape: [1, NSNumber(value: layer.outChannels), 1, 1],
                dataType: .float32
            )
            let conv = graph.convolution2D(cur, weights: wTensor, descriptor: desc, name: "conv_\(idx)")
            let biased = graph.addition(conv, bTensor, name: "bias_\(idx)")
            if layer.leakySlope < 0.999 {
                cur = graph.leakyReLU(with: biased, alpha: Double(layer.leakySlope), name: "lrelu_\(idx)")
            } else {
                cur = biased
            }
        }

        let built = MPSPipeline(
            mpsDevice: mpsDevice,
            queue: queue,
            graph: graph,
            inputTensor: inputPlaceholder,
            outputTensor: cur
        )
        self.cachedMPS = built
        return built
    }
    #endif

    /// Runs all 7 layers on CPU via `Accelerate` (`vDSP_mmul`) for arbitrary padded tile `(inH, inW)` (`>= 16`).
    /// Returns `[12, inH - 14, inW - 14]` subpixel tensor.
    public func forwardCPU(paddedRGB: [Float], height: Int, width: Int) -> [Float] {
        var cur = paddedRGB
        var curH = height
        var curW = width
        for layer in self.layers {
            let outH = curH - 2
            let outW = curW - 2
            let spatial = outH * outW
            let patchLen = layer.inChannels * 9
            var col = [Float](repeating: 0.0, count: patchLen * spatial)

            cur.withUnsafeBufferPointer { curBuf in
                col.withUnsafeMutableBufferPointer { colBuf in
                    guard let curBase = curBuf.baseAddress, let colBase = colBuf.baseAddress else { return }
                    let rowBytes = outW * MemoryLayout<Float>.size
                    for ic in 0 ..< layer.inChannels {
                        let chOffset = ic * curH * curW
                        for u in 0 ..< 3 {
                            for v in 0 ..< 3 {
                                let patchIdx = (ic * 3 + u) * 3 + v
                                let dstPatch = colBase + patchIdx * spatial
                                for y in 0 ..< outH {
                                    let srcRow = curBase + chOffset + (y + u) * curW + v
                                    memcpy(dstPatch + y * outW, srcRow, rowBytes)
                                }
                            }
                        }
                    }
                }
            }

            var out = [Float](repeating: 0.0, count: layer.outChannels * spatial)
            layer.weights.withUnsafeBufferPointer { wBuf in
                col.withUnsafeBufferPointer { colBuf in
                    out.withUnsafeMutableBufferPointer { outBuf in
                        guard let wPtr = wBuf.baseAddress,
                              let cPtr = colBuf.baseAddress,
                              let oPtr = outBuf.baseAddress else { return }
                        vDSP_mmul(
                            wPtr, 1,
                            cPtr, 1,
                            oPtr, 1,
                            vDSP_Length(layer.outChannels),
                            vDSP_Length(spatial),
                            vDSP_Length(patchLen)
                        )
                    }
                }
            }

            let slope = layer.leakySlope
            out.withUnsafeMutableBufferPointer { outBuf in
                guard let oPtr = outBuf.baseAddress else { return }
                for oc in 0 ..< layer.outChannels {
                    var bVal = layer.bias[oc]
                    let chPtr = oPtr + oc * spatial
                    vDSP_vsadd(chPtr, 1, &bVal, chPtr, 1, vDSP_Length(spatial))
                    if slope < 0.999 {
                        for i in 0 ..< spatial {
                            let v = chPtr[i]
                            if v < 0.0 {
                                chPtr[i] = v * slope
                            }
                        }
                    }
                }
            }

            cur = out
            curH = outH
            curW = outW
        }
        return cur
    }

    private func runFixedTile(paddedRGB: [Float]) -> [Float] {
        #if canImport(Metal) && canImport(MetalPerformanceShadersGraph) && !targetEnvironment(simulator)
        let inner = Self.tileInnerSize
        let subCount = 12 * inner * inner
        if let pipe = self.mpsPipelineIfAvailable() {
            var gpuResult: [Float]?
            autoreleasepool {
                let inData = paddedRGB.withUnsafeBufferPointer { Data(buffer: $0) }
                let pSize = NSNumber(value: Self.tilePaddedSize)
                let feedData = MPSGraphTensorData(
                    device: pipe.mpsDevice,
                    data: inData,
                    shape: [1, 3, pSize, pSize],
                    dataType: .float32
                )
                let outputs = pipe.graph.run(
                    with: pipe.queue,
                    feeds: [pipe.inputTensor: feedData],
                    targetTensors: [pipe.outputTensor],
                    targetOperations: nil
                )
                if let outTensorData = outputs[pipe.outputTensor] {
                    var buf = [Float](repeating: 0.0, count: subCount)
                    buf.withUnsafeMutableBytes { rawBuf in
                        if let base = rawBuf.baseAddress {
                            outTensorData.mpsndarray().readBytes(base, strideBytes: nil)
                        }
                    }
                    gpuResult = buf
                }
            }
            if let gpuResult {
                return gpuResult
            }
        }
        #endif
        return self.forwardCPU(paddedRGB: paddedRGB, height: Self.tilePaddedSize, width: Self.tilePaddedSize)
    }

    @inline(__always)
    private static func reflectIndex(_ idx: Int, _ limit: Int) -> Int {
        if limit <= 1 { return 0 }
        var c = idx
        while c < 0 || c >= limit {
            if c < 0 {
                c = -c
            }
            if c >= limit {
                c = 2 * limit - 2 - c
            }
        }
        return c
    }

    #if canImport(UIKit)
    public static func normalizeOrientation(_ image: UIImage) -> UIImage {
        let pxW = max(1.0, (image.size.width * image.scale).rounded())
        let pxH = max(1.0, (image.size.height * image.scale).rounded())
        if image.imageOrientation == .up && image.scale == 1.0 && image.cgImage != nil {
            return image
        }
        let target = CGSize(width: pxW, height: pxH)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    public static func resizeProportionally(_ image: UIImage, maxSide: Int) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = cg.width
        let h = cg.height
        let longest = max(w, h)
        guard longest > maxSide, maxSide > 0 else { return image }
        let ratio = CGFloat(maxSide) / CGFloat(longest)
        let target = CGSize(
            width: max(1.0, (CGFloat(w) * ratio).rounded()),
            height: max(1.0, (CGFloat(h) * ratio).rounded())
        )
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Upscales `image` by `2x` using this Waifu2x `upconv_7` model.
    public func upscale2x(
        image: UIImage,
        isCancelled: () -> Bool,
        onTileProgress: (_ completed: Int, _ total: Int) -> Void
    ) throws -> UIImage {
        let upright = Self.normalizeOrientation(image)
        guard let cgImage = upright.cgImage else {
            throw MTNeuralWaifu2xError.invalidImage
        }
        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 0, srcH > 0 else {
            throw MTNeuralWaifu2xError.invalidImage
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var srcRGBA = [UInt8](repeating: 0, count: srcW * srcH * 4)
        let drewOK: Bool = srcRGBA.withUnsafeMutableBytes { rawBuf in
            guard let base = rawBuf.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: srcW,
                      height: srcH,
                      bitsPerComponent: 8,
                      bytesPerRow: srcW * 4,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ) else {
                return false
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))
            return true
        }
        guard drewOK else {
            throw MTNeuralWaifu2xError.invalidImage
        }

        // Unpremultiply RGB into [0, 1] so semi-transparent sticker/manga edges stay clean.
        let pixelCount = srcW * srcH
        var rPlane = [Float](repeating: 0, count: pixelCount)
        var gPlane = [Float](repeating: 0, count: pixelCount)
        var bPlane = [Float](repeating: 0, count: pixelCount)
        var hasTransparency = false
        let inv255: Float = 1.0 / 255.0
        for i in 0 ..< pixelCount {
            let aByte = srcRGBA[i * 4 + 3]
            if aByte == 0 {
                hasTransparency = true
                rPlane[i] = 1.0
                gPlane[i] = 1.0
                bPlane[i] = 1.0
            } else if aByte < 255 {
                hasTransparency = true
                let a = Float(aByte) * inv255
                rPlane[i] = min(1.0, (Float(srcRGBA[i * 4]) * inv255) / a)
                gPlane[i] = min(1.0, (Float(srcRGBA[i * 4 + 1]) * inv255) / a)
                bPlane[i] = min(1.0, (Float(srcRGBA[i * 4 + 2]) * inv255) / a)
            } else {
                rPlane[i] = Float(srcRGBA[i * 4]) * inv255
                gPlane[i] = Float(srcRGBA[i * 4 + 1]) * inv255
                bPlane[i] = Float(srcRGBA[i * 4 + 2]) * inv255
            }
        }

        let dstW = srcW * 2
        let dstH = srcH * 2
        var dstRGBA = [UInt8](repeating: 255, count: dstW * dstH * 4)

        let inner = Self.tileInnerSize
        let pad = Self.tilePad
        let padded = Self.tilePaddedSize
        let tilesX = (srcW + inner - 1) / inner
        let tilesY = (srcH + inner - 1) / inner
        let totalTiles = max(1, tilesX * tilesY)
        var doneTiles = 0

        var tileInput = [Float](repeating: 0.0, count: 3 * padded * padded)
        let planeStride = padded * padded

        for ty in 0 ..< tilesY {
            for tx in 0 ..< tilesX {
                if isCancelled() {
                    throw MTNeuralWaifu2xError.cancelled
                }
                let x0 = tx * inner
                let y0 = ty * inner
                let validW = min(inner, srcW - x0)
                let validH = min(inner, srcH - y0)

                for py in 0 ..< padded {
                    let sy = Self.reflectIndex(y0 + py - pad, srcH)
                    let srcRow = sy * srcW
                    let dstRow = py * padded
                    for px in 0 ..< padded {
                        let sx = Self.reflectIndex(x0 + px - pad, srcW)
                        let sIdx = srcRow + sx
                        let dIdx = dstRow + px
                        tileInput[dIdx] = rPlane[sIdx]
                        tileInput[planeStride + dIdx] = gPlane[sIdx]
                        tileInput[2 * planeStride + dIdx] = bPlane[sIdx]
                    }
                }

                let subOut = self.runFixedTile(paddedRGB: tileInput)
                let subSpatial = inner * inner

                for qy in 0 ..< validH {
                    for ry in 0 ..< 2 {
                        let oy = (y0 + qy) * 2 + ry
                        let dstRowOffset = oy * dstW * 4
                        for qx in 0 ..< validW {
                            let qIdx = qy * inner + qx
                            for rx in 0 ..< 2 {
                                let ox = (x0 + qx) * 2 + rx
                                let subOffset = ry * 2 + rx
                                let rVal = max(0.0, min(1.0, subOut[(0 * 4 + subOffset) * subSpatial + qIdx]))
                                let gVal = max(0.0, min(1.0, subOut[(1 * 4 + subOffset) * subSpatial + qIdx]))
                                let bVal = max(0.0, min(1.0, subOut[(2 * 4 + subOffset) * subSpatial + qIdx]))

                                let outIdx = dstRowOffset + ox * 4
                                if hasTransparency {
                                    // Bilinear alpha sampling
                                    let fx = max(0.0, min(Float(srcW - 1), (Float(ox) + 0.5) * 0.5 - 0.5))
                                    let fy = max(0.0, min(Float(srcH - 1), (Float(oy) + 0.5) * 0.5 - 0.5))
                                    let ax0 = Int(fx)
                                    let ay0 = Int(fy)
                                    let ax1 = min(srcW - 1, ax0 + 1)
                                    let ay1 = min(srcH - 1, ay0 + 1)
                                    let wx = fx - Float(ax0)
                                    let wy = fy - Float(ay0)
                                    let a00 = Float(srcRGBA[(ay0 * srcW + ax0) * 4 + 3])
                                    let a10 = Float(srcRGBA[(ay0 * srcW + ax1) * 4 + 3])
                                    let a01 = Float(srcRGBA[(ay1 * srcW + ax0) * 4 + 3])
                                    let a11 = Float(srcRGBA[(ay1 * srcW + ax1) * 4 + 3])
                                    let aInterp = (a00 * (1.0 - wx) + a10 * wx) * (1.0 - wy) + (a01 * (1.0 - wx) + a11 * wx) * wy
                                    let aNorm = max(0.0, min(1.0, aInterp * inv255))
                                    dstRGBA[outIdx] = UInt8((rVal * aNorm * 255.0).rounded())
                                    dstRGBA[outIdx + 1] = UInt8((gVal * aNorm * 255.0).rounded())
                                    dstRGBA[outIdx + 2] = UInt8((bVal * aNorm * 255.0).rounded())
                                    dstRGBA[outIdx + 3] = UInt8(max(0.0, min(255.0, aInterp.rounded())))
                                } else {
                                    dstRGBA[outIdx] = UInt8((rVal * 255.0).rounded())
                                    dstRGBA[outIdx + 1] = UInt8((gVal * 255.0).rounded())
                                    dstRGBA[outIdx + 2] = UInt8((bVal * 255.0).rounded())
                                    dstRGBA[outIdx + 3] = 255
                                }
                            }
                        }
                    }
                }

                doneTiles += 1
                onTileProgress(doneTiles, totalTiles)
            }
        }

        let outCG: CGImage? = dstRGBA.withUnsafeMutableBytes { rawBuf in
            guard let base = rawBuf.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: dstW,
                      height: dstH,
                      bitsPerComponent: 8,
                      bytesPerRow: dstW * 4,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ) else {
                return nil
            }
            return ctx.makeImage()
        }
        guard let finalCG = outCG else {
            throw MTNeuralWaifu2xError.invalidImage
        }
        return UIImage(cgImage: finalCG, scale: 1.0, orientation: .up)
    }

    public static func upscale(
        image: UIImage,
        style: MTNeuralWaifu2xStyle,
        factor: Int,
        maxOutputSide: Int = 4096,
        isCancelled: () -> Bool,
        onProgress: (_ progress: Float, _ statusText: String) -> Void
    ) throws -> UIImage {
        let model = try Self.shared(style: style)
        let normalized = Self.normalizeOrientation(image)
        if factor <= 2 {
            let prepped = Self.resizeProportionally(normalized, maxSide: maxOutputSide / 2)
            return try model.upscale2x(image: prepped, isCancelled: isCancelled) { done, total in
                let p = Float(done) / Float(max(1, total))
                onProgress(p, "Waifu2x GPU (\(style.displayTitle)): тайл \(done)/\(total)")
            }
        } else {
            // 4x Ultra = two neural 2x passes capped cleanly at 4096 px max side.
            let prepped1 = Self.resizeProportionally(normalized, maxSide: maxOutputSide / 4)
            let pass1 = try model.upscale2x(image: prepped1, isCancelled: isCancelled) { done, total in
                let p = 0.25 * (Float(done) / Float(max(1, total)))
                onProgress(p, "Проход 1/2 (2×): тайл \(done)/\(total)")
            }
            let prepped2 = Self.resizeProportionally(pass1, maxSide: maxOutputSide / 2)
            let pass2 = try model.upscale2x(image: prepped2, isCancelled: isCancelled) { done, total in
                let p = 0.25 + 0.75 * (Float(done) / Float(max(1, total)))
                onProgress(p, "Проход 2/2 (4K): тайл \(done)/\(total)")
            }
            return pass2
        }
    }
    #endif
}
