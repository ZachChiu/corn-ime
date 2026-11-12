import Cocoa

/// 選字窗裡的一列
struct CandidateRow {
    var number = ""      // 選字用的數字，沒有就不顯示
    var text: String
    var hint = ""        // 右側的按鍵提示（例如 Tab）
    var selected = false
}

/// 一列一列畫出候選字：選中的那列是圓角色塊
final class CandidateRowsView: NSView {
    var rows: [CandidateRow] = []
    var footer = ""
    /// 模式提示用：字小、列矮
    var compact = false

    private var font: NSFont { compact ? .systemFont(ofSize: 13, weight: .medium) : .systemFont(ofSize: 18) }
    private let small = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private var rowHeight: CGFloat { compact ? 20 : 30 }
    private let footerHeight: CGFloat = 22
    private var edge: CGFloat { compact ? 2 : 5 }   // 色塊到視窗邊緣
    private let inset: CGFloat = 9      // 文字到色塊邊緣
    private let gap: CGFloat = 12       // 文字到右側提示

    override var isFlipped: Bool { true }

    private func width(_ s: String, _ f: NSFont) -> CGFloat {
        s.isEmpty ? 0 : ceil((s as NSString).size(withAttributes: [.font: f]).width)
    }

    private var numberWidth: CGFloat {
        rows.contains { !$0.number.isEmpty } ? width("8", small) + 9 : 0
    }

    var contentSize: NSSize {
        let widest = rows.map { r in
            width(r.text, font) + (r.hint.isEmpty ? 0 : gap + width(r.hint, small))
        }.max() ?? 0
        let w = max(widest + numberWidth, width(footer, small)) + (edge + inset) * 2
        let h = CGFloat(rows.count) * rowHeight + edge * 2 + (footer.isEmpty ? 0 : footerHeight)
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
            if r.selected {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: edge, y: y, width: bounds.width - edge * 2, height: rowHeight),
                             xRadius: 7, yRadius: 7).fill()
            }
            let main: NSColor = r.selected ? .white : .labelColor
            let dim: NSColor = r.selected ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
            let x = edge + inset
            put(r.number, small, dim, x: x, rowY: y, height: rowHeight)
            put(r.text, font, main, x: x + numberWidth, rowY: y, height: rowHeight)
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

/// 浮在游標下方的小視窗：中文選字、英文建議、模式提示都用它
final class CandidatePanel {
    static let shared = CandidatePanel()

    private let panel: NSPanel
    private let box: NSVisualEffectView
    private let list = CandidateRowsView()
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
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        box = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        box.material = .menu
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 11
        box.layer?.cornerCurve = .continuous
        box.layer?.masksToBounds = true
        box.layer?.borderWidth = 0.5
        box.autoresizingMask = [.width, .height]

        list.autoresizingMask = [.width, .height]
        list.frame = box.bounds
        box.addSubview(list)
        panel.contentView = box
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
        list.needsDisplay = true
        let size = list.contentSize
        box.layer?.cornerRadius = list.compact ? 7 : 11
        let w = size.width, h = size.height

        var origin = NSPoint(x: caret.minX, y: caret.minY - h - 6)
        let screen = NSScreen.screens.first { $0.frame.contains(caret.origin) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            if origin.y < f.minY { origin.y = caret.maxY + 6 }
            origin.x = min(max(origin.x, f.minX), f.maxX - w)
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: w, height: h), display: true)
        // 邊框顏色跟著目前的深淺色外觀
        box.effectiveAppearance.performAsCurrentDrawingAppearance {
            box.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        panel.invalidateShadow()
        panel.orderFrontRegardless()
    }
}
