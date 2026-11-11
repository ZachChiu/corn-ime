import Cocoa

/// 浮在游標下方的小視窗：中文選字、英文建議、模式提示都用它
final class CandidatePanel {
    static let shared = CandidatePanel()

    private let panel: NSPanel
    private let label: NSTextField
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

        let box = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        box.material = .popover
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.masksToBounds = true
        box.autoresizingMask = [.width, .height]

        label = NSTextField(labelWithString: "")
        label.maximumNumberOfLines = 0
        box.addSubview(label)
        panel.contentView = box
    }

    func show(_ text: NSAttributedString, near caret: NSRect) {
        toastToken += 1
        place(text, near: caret)
    }

    /// 短暫顯示一段提示（例如切換模式）
    func toast(_ message: String, near caret: NSRect) {
        toastToken += 1
        let token = toastToken
        let attr = NSAttributedString(string: message, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        place(attr, near: caret)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, self.toastToken == token else { return }
            self.hide()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func place(_ text: NSAttributedString, near caret: NSRect) {
        label.attributedStringValue = text
        let size = label.fittingSize
        let w = ceil(size.width) + 20, h = ceil(size.height) + 12
        label.frame = NSRect(x: 10, y: 6, width: ceil(size.width), height: ceil(size.height))

        var origin = NSPoint(x: caret.minX, y: caret.minY - h - 4)
        let screen = NSScreen.screens.first { $0.frame.contains(caret.origin) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            if origin.y < f.minY { origin.y = caret.maxY + 4 }
            origin.x = min(max(origin.x, f.minX), f.maxX - w)
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: w, height: h), display: true)
        panel.orderFrontRegardless()
    }
}
