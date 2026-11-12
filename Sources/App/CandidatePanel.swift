import Cocoa

/// 選字窗裡的一列
struct CandidateRow {
    var number = ""      // 選字用的數字，沒有就不顯示
    var text: String
    var hint = ""        // 右側的按鍵提示（例如 Tab）
    var selected = false
    var image: NSImage? = nil   // 梗圖的縮圖
}

/// 一列一列畫出候選字：選中的那列是圓角色塊
final class CandidateRowsView: NSView {
    var rows: [CandidateRow] = []
    var footer = ""
    /// 模式提示用：字小、列矮
    var compact = false

    private var style: PanelStyle { PanelStyle.shared }
    private var font: NSFont { compact ? .systemFont(ofSize: 13, weight: .medium) : .systemFont(ofSize: style.fontSize) }
    private let small = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
    /// 編號、提示的顏色：跟漸層起點同色系，淺色外觀調深、深色外觀調淺，兩邊都看得清楚
    private var accentText: NSColor {
        let base = style.colorA
        return NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? (base.blended(withFraction: 0.25, of: .white) ?? base)
                : (base.blended(withFraction: 0.25, of: .black) ?? base)
        }
    }
    private var rowHeight: CGFloat { compact ? 20 : ceil(style.fontSize) + 12 }
    private let footerHeight: CGFloat = 22
    private var edge: CGFloat { compact ? 2 : 5 }   // 色塊到視窗邊緣
    private let inset: CGFloat = 9      // 文字到色塊邊緣
    private let gap: CGFloat = 12       // 文字到右側提示

    /// 選字框裡的圖示：使用者自己選的圖，沒選就用輸入法的貓咪圖示。
    /// 選字時在選中那列的右邊，模式提示時在文字左邊
    static var catImage: NSImage? = PanelStyle.customIcon() ?? bundledIcon
    static let bundledIcon = Bundle.main.url(forResource: "tuxedo", withExtension: "tiff").flatMap { NSImage(contentsOf: $0) }
    private var cat: NSImage? { style.showCat ? Self.catImage : nil }
    private var catSize: CGFloat { compact ? 15 : min(22, rowHeight - 8) }
    /// 這一列要留給貓咪的寬度
    private func catSpace(_ r: CandidateRow) -> CGFloat {
        cat != nil && r.hint.isEmpty ? catSize + (compact ? 5 : gap) : 0
    }

    // 梗圖那一列比較高，文字前面畫縮圖
    private let thumbHeight: CGFloat = 36
    private func height(_ r: CandidateRow) -> CGFloat { r.image == nil ? rowHeight : max(rowHeight, thumbHeight + 8) }
    private func thumbSize(_ r: CandidateRow) -> NSSize {
        guard let size = r.image?.size, size.height > 0 else { return .zero }
        return NSSize(width: min(80, thumbHeight * size.width / size.height), height: thumbHeight)
    }
    private func thumbSpace(_ r: CandidateRow) -> CGFloat { r.image == nil ? 0 : thumbSize(r).width + (r.text.isEmpty ? 0 : 10) }

    override var isFlipped: Bool { true }

    private func width(_ s: String, _ f: NSFont) -> CGFloat {
        s.isEmpty ? 0 : ceil((s as NSString).size(withAttributes: [.font: f]).width)
    }

    private var numberWidth: CGFloat {
        rows.contains { !$0.number.isEmpty } ? width("8", small) + 9 : 0
    }

    var contentSize: NSSize {
        let widest = rows.map { r in
            width(r.text, font) + (r.hint.isEmpty ? 0 : gap + width(r.hint, small)) + catSpace(r) + thumbSpace(r)
        }.max() ?? 0
        let w = max(widest + numberWidth, width(footer, small)) + (edge + inset) * 2
        let h = rows.map { height($0) }.reduce(0, +) + edge * 2 + (footer.isEmpty ? 0 : footerHeight)
        return NSSize(width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        func put(_ s: String, _ f: NSFont, _ color: NSColor, x: CGFloat, rowY: CGFloat, height: CGFloat) {
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
            let size = (s as NSString).size(withAttributes: attrs)
            (s as NSString).draw(at: NSPoint(x: x, y: rowY + (height - size.height) / 2), withAttributes: attrs)
        }

        var y = edge
        for r in rows {
            let rowHeight = height(r)
            if r.selected {
                let pill = NSBezierPath(roundedRect: NSRect(x: edge, y: y, width: bounds.width - edge * 2, height: rowHeight),
                                        xRadius: 7, yRadius: 7)
                // 先畫一層帶光暈的底，再蓋上漸層
                if style.glow > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    let glow = NSShadow()
                    glow.shadowColor = style.colorA.withAlphaComponent(style.glow)
                    glow.shadowBlurRadius = 9
                    glow.set()
                    style.colorA.setFill()
                    pill.fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                NSGradient(starting: style.colorA, ending: style.colorB)?.draw(in: pill, angle: 0)
            }
            let main: NSColor = r.selected ? .white : .labelColor
            let dim: NSColor = r.selected ? NSColor.white.withAlphaComponent(0.8) : accentText
            var x = edge + inset
            if let cat = cat, r.hint.isEmpty, compact || r.selected {
                // 模式提示：貓在文字左邊；選字：貓在選中那列的右邊
                let cx = compact ? x : bounds.width - edge - inset - catSize
                cat.draw(in: NSRect(x: cx, y: y + (rowHeight - catSize) / 2, width: catSize, height: catSize),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            if compact { x += catSpace(r) }
            put(r.number, small, dim, x: x, rowY: y, height: rowHeight)
            x += numberWidth
            if let image = r.image {
                let size = thumbSize(r)
                let rect = NSRect(x: x, y: y + (rowHeight - size.height) / 2, width: size.width, height: size.height)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).addClip()
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
                x += thumbSpace(r)
            }
            put(r.text, font, main, x: x, rowY: y, height: rowHeight)
            if !r.hint.isEmpty {
                put(r.hint, small, dim, x: bounds.width - edge - inset - width(r.hint, small), rowY: y, height: rowHeight)
            }
            y += rowHeight
        }
        if !footer.isEmpty {
            put(footer, small, .secondaryLabelColor, x: edge + inset, rowY: y, height: footerHeight)
        }
    }
}

/// 選字框的整個外觀：玻璃背景、底色、背景圖、候選字，由下往上疊。
/// 游標旁的選字框和設定視窗裡的預覽共用這一份，兩邊看到的才會一樣
final class PanelChrome: NSView {
    let list = CandidateRowsView()
    private let effect: NSView          // 玻璃（舊系統是毛玻璃）
    private let fill = NSView()         // 底色與背景圖，裁成圓角
    private let tint = CALayer()
    private let picture = CALayer()
    private let setRadius: (CGFloat) -> Void

    /// withinWindow：預覽用，玻璃透出的是同一個視窗裡的內容
    init(withinWindow: Bool) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            effect = glass
            setRadius = { glass.cornerRadius = $0 }
        } else {
            let fx = NSVisualEffectView()
            fx.material = .menu
            fx.blendingMode = withinWindow ? .withinWindow : .behindWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerCurve = .continuous
            fx.layer?.masksToBounds = true
            fx.layer?.borderWidth = 0.5
            effect = fx
            setRadius = { fx.layer?.cornerRadius = $0 }
        }
        super.init(frame: .zero)
        wantsLayer = true // 每一層都用圖層，疊放順序才固定（底色和背景圖在文字下面）
        fill.wantsLayer = true
        fill.layer?.masksToBounds = true
        fill.layer?.cornerCurve = .continuous
        picture.contentsGravity = .resizeAspectFill
        picture.masksToBounds = true
        fill.layer?.addSublayer(tint)
        fill.layer?.addSublayer(picture)
        // 背景和文字分成不同層：調背景的透明度時文字不會跟著變淡
        for v in [effect, fill, list] {
            v.frame = bounds
            v.autoresizingMask = [.width, .height]
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError("不支援") }

    /// 套用目前的外觀設定
    func refresh() {
        let s = PanelStyle.shared
        appearance = s.appearance // nil = 跟隨系統
        let r: CGFloat = list.compact ? 9 : 12
        setRadius(r)
        effect.alphaValue = 1 - s.transparency
        CATransaction.begin()
        CATransaction.setDisableActions(true) // 不要淡入淡出
        fill.layer?.cornerRadius = r
        tint.frame = fill.bounds
        picture.frame = fill.bounds
        tint.backgroundColor = s.bgColor.withAlphaComponent(s.bgStrength).cgColor
        picture.contents = PanelStyle.bgImage
        picture.opacity = Float(s.bgImageOpacity)
        CATransaction.commit()
        if effect is NSVisualEffectView {
            // 邊框顏色跟著目前的深淺色外觀
            effectiveAppearance.performAsCurrentDrawingAppearance {
                effect.layer?.borderColor = NSColor.separatorColor.cgColor
            }
        }
        list.needsDisplay = true
    }

    override func layout() {
        super.layout()
        refresh()
    }
}

/// 浮在游標下方的小視窗：中文選字、英文建議、模式提示都用它
final class CandidatePanel {
    static let shared = CandidatePanel()

    private let panel: NSPanel
    private let chrome = PanelChrome(withinWindow: false)
    private var list: CandidateRowsView { chrome.list }
    private var toastToken = 0

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        if #available(macOS 26.0, *) { panel.hasShadow = false } // 玻璃自己有邊緣光影，視窗陰影會是方的
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none // 出現時不要有彈開的動畫
        panel.contentView = chrome
    }

    func show(_ rows: [CandidateRow], footer: String = "", near caret: NSRect) {
        toastToken += 1
        list.compact = false
        place(rows, footer, near: caret)
    }

    /// 短暫顯示一段提示（例如切換模式）
    func toast(_ message: String, near caret: NSRect) {
        toastToken += 1
        let token = toastToken
        list.compact = true
        place([CandidateRow(text: message)], "", near: caret)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, self.toastToken == token else { return }
            self.hide()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func place(_ rows: [CandidateRow], _ footer: String, near caret: NSRect) {
        list.rows = rows
        list.footer = footer
        let size = list.contentSize
        let w = size.width, h = size.height

        var origin = NSPoint(x: caret.minX, y: caret.minY - h - 6)
        let screen = NSScreen.screens.first { $0.frame.contains(caret.origin) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            if origin.y < f.minY { origin.y = caret.maxY + 6 }
            origin.x = min(max(origin.x, f.minX), f.maxX - w)
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: w, height: h), display: true)
        chrome.refresh()
        panel.invalidateShadow()
        panel.orderFrontRegardless()
    }
}
