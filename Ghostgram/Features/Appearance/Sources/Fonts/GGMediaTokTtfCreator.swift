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

    // MARK: - Binary TrueType (.ttf) Compiler (delegated to GGMediaTokCoreLogic)

    static func compileTtf(fontNameRaw: String, grids: [Character: [Bool]], pixelStyle: Int) -> Data {
        return GGMediaTokCoreLogic.compileTtf(fontNameRaw: fontNameRaw, grids: grids, pixelStyle: pixelStyle)
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
        guard self.bounds.width > 0.0, self.bounds.height > 0.0 else {
            return 0
        }
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
            guard let strongSelf = self else {
                try? FileManager.default.removeItem(at: tempURL)
                return
            }
            switch result {
            case let .added(font):
                let alert = UIAlertController(
                    title: "Шрифт «\(font.familyName)» собран!",
                    message: "Файл (\(data.count / 1024) КБ) добавлен и выбран. Перезапустите MediaTok, чтобы применить его везде.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Поделиться .ttf", style: .default, handler: { _ in
                    let share = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                    share.completionWithItemsHandler = { _, _, _, _ in
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                    if let pop = share.popoverPresentationController {
                        pop.sourceView = strongSelf.view
                        pop.sourceRect = CGRect(x: strongSelf.view.bounds.midX, y: strongSelf.view.bounds.midY, width: 0.0, height: 0.0)
                        pop.permittedArrowDirections = []
                    }
                    strongSelf.present(share, animated: true)
                }))
                alert.addAction(UIAlertAction(title: "Готово", style: .cancel, handler: { _ in
                    try? FileManager.default.removeItem(at: tempURL)
                    strongSelf.dismiss(animated: true)
                }))
                strongSelf.present(alert, animated: true)
            case .notAFont:
                try? FileManager.default.removeItem(at: tempURL)
                strongSelf.showAlert(title: "Ошибка", message: "CoreText не смог прочитать собранный шрифт")
            case .tooMany:
                try? FileManager.default.removeItem(at: tempURL)
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
