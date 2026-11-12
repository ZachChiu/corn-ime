import Cocoa
import UniformTypeIdentifiers

/// 選字框的外觀設定，存在 UserDefaults
struct PanelStyle {
    // 選中的色塊
    var colorA = NSColor(srgbRed: 1.00, green: 0.58, blue: 0.10, alpha: 1) // 漸層起點
    var colorB = NSColor(srgbRed: 0.96, green: 0.22, blue: 0.24, alpha: 1) // 漸層終點
    var glow = 0.6               // 光暈強度 0...1
    // 窗格
    var appearanceMode = 0       // 0 跟隨系統、1 淺色、2 深色
    var transparency = 0.0       // 玻璃的透明度 0（原本的玻璃）...1（完全透明）
    var bgColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.14, alpha: 1) // 底色
    var bgStrength = 0.0         // 底色濃度 0（不用底色）...1（不透明）
    var bgImageOpacity = 0.6     // 背景圖濃度
    // 文字與圖示
    var fontSize = 18.0          // 候選字字級
    var showCat = true           // 顯示圖示

    static let defaults = PanelStyle()
    static var shared = load() { didSet { shared.save() } }

    var appearance: NSAppearance? {
        switch appearanceMode {
        case 1: return NSAppearance(named: .aqua)
        case 2: return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    // MARK: 主題

    /// 主題：一次設定色塊、光暈、窗格外觀、底色、透明度。字級、圖示、背景圖不動
    struct Theme {
        let name: String
        let a: (Double, Double, Double), b: (Double, Double, Double)
        var glow = 0.6
        var mode = 0
        var bg: (Double, Double, Double) = (0.08, 0.09, 0.14)
        var bgStrength = 0.0
        var transparency = 0.0
    }

    static let themes: [Theme] = [
        Theme(name: "玉米（預設）", a: (1.00, 0.58, 0.10), b: (0.96, 0.22, 0.24)),
        Theme(name: "極光", a: (0.10, 0.85, 1.00), b: (0.28, 0.42, 1.00), mode: 2, bg: (0.03, 0.07, 0.16), bgStrength: 0.55),
        Theme(name: "霓虹", a: (0.62, 0.34, 1.00), b: (1.00, 0.30, 0.66), glow: 0.8, mode: 2, bg: (0.09, 0.03, 0.14), bgStrength: 0.6),
        Theme(name: "森林", a: (0.18, 0.80, 0.44), b: (0.05, 0.66, 0.80), mode: 2, bg: (0.03, 0.11, 0.09), bgStrength: 0.5),
        Theme(name: "蜜糖", a: (1.00, 0.74, 0.10), b: (0.98, 0.50, 0.08), glow: 0.5, mode: 1, bg: (1.00, 0.96, 0.86), bgStrength: 0.55),
        Theme(name: "櫻花", a: (1.00, 0.52, 0.70), b: (0.92, 0.36, 0.56), glow: 0.5, mode: 1, bg: (1.00, 0.93, 0.95), bgStrength: 0.55),
        Theme(name: "簡約（系統藍、無光暈）", a: (0.04, 0.52, 1.00), b: (0.04, 0.52, 1.00), glow: 0),
        Theme(name: "石墨（灰階、無光暈）", a: (0.42, 0.44, 0.48), b: (0.42, 0.44, 0.48), glow: 0),
    ]

    mutating func apply(_ t: Theme) {
        func c(_ v: (Double, Double, Double)) -> NSColor { NSColor(srgbRed: v.0, green: v.1, blue: v.2, alpha: 1) }
        colorA = c(t.a); colorB = c(t.b); glow = t.glow
        appearanceMode = t.mode; bgColor = c(t.bg); bgStrength = t.bgStrength; transparency = t.transparency
    }

    // MARK: 圖片（圖示、背景圖）

    /// 使用者自己選的圖示（縮小後存在 UserDefaults）
    static func customIcon() -> NSImage? {
        UserDefaults.standard.data(forKey: "styleIconData").flatMap { NSImage(data: $0) }
    }

    /// 換圖示：縮成 96×96（等比例置中、周圍透明）後存起來。傳 nil 改回預設的貓咪
    static func setCustomIcon(_ image: NSImage?) {
        let data = image.flatMap { resized($0, maxSide: 96, square: true) }
        UserDefaults.standard.set(data, forKey: "styleIconData") // nil 等於刪掉
        CandidateRowsView.catImage = data.flatMap { NSImage(data: $0) } ?? CandidateRowsView.bundledIcon
    }

    /// 窗格的背景圖
    static var bgImage: NSImage? = UserDefaults.standard.data(forKey: "styleBgImageData").flatMap { NSImage(data: $0) }

    /// 換背景圖：長邊縮到 800 以內後存起來。傳 nil 移除
    static func setBgImage(_ image: NSImage?) {
        let data = image.flatMap { resized($0, maxSide: 800, square: false) }
        UserDefaults.standard.set(data, forKey: "styleBgImageData")
        bgImage = data.flatMap { NSImage(data: $0) }
    }

    /// 等比例縮小成 PNG。square：放進正方形畫布、置中、周圍透明
    private static func resized(_ image: NSImage, maxSide: CGFloat, square: Bool) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let w = (image.size.width * scale).rounded(), h = (image.size.height * scale).rounded()
        let cw = square ? maxSide : w, ch = square ? maxSide : h
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cw), pixelsHigh: Int(ch),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: (cw - w) / 2, y: (ch - h) / 2, width: w, height: h),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: 讀寫

    private static func load() -> PanelStyle {
        let u = UserDefaults.standard
        func color(_ key: String, _ fallback: NSColor) -> NSColor {
            guard let v = u.array(forKey: key) as? [Double], v.count == 3 else { return fallback }
            return NSColor(srgbRed: v[0], green: v[1], blue: v[2], alpha: 1)
        }
        func unit(_ key: String, _ fallback: Double) -> Double {
            (u.object(forKey: key) as? Double).map { min(1, max(0, $0)) } ?? fallback
        }
        var s = defaults
        s.colorA = color("styleColorA", s.colorA)
        s.colorB = color("styleColorB", s.colorB)
        s.glow = unit("styleGlow", s.glow)
        s.appearanceMode = min(2, max(0, (u.object(forKey: "styleAppearance") as? Int) ?? 0))
        s.transparency = unit("styleTransparency", s.transparency)
        s.bgColor = color("styleBgColor", s.bgColor)
        s.bgStrength = unit("styleBgStrength", s.bgStrength)
        s.bgImageOpacity = unit("styleBgImageOpacity", s.bgImageOpacity)
        if let v = u.object(forKey: "styleFontSize") as? Double { s.fontSize = min(26, max(14, v)) }
        s.showCat = (u.object(forKey: "styleShowCat") as? Bool) ?? true
        return s
    }

    private func save() {
        let u = UserDefaults.standard
        func rgb(_ c: NSColor) -> [Double] {
            let c = c.usingColorSpace(.sRGB) ?? c
            return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
        }
        u.set(rgb(colorA), forKey: "styleColorA")
        u.set(rgb(colorB), forKey: "styleColorB")
        u.set(glow, forKey: "styleGlow")
        u.set(appearanceMode, forKey: "styleAppearance")
        u.set(transparency, forKey: "styleTransparency")
        u.set(rgb(bgColor), forKey: "styleBgColor")
        u.set(bgStrength, forKey: "styleBgStrength")
        u.set(bgImageOpacity, forKey: "styleBgImageOpacity")
        u.set(fontSize, forKey: "styleFontSize")
        u.set(showCat, forKey: "styleShowCat")
    }
}

/// 設定視窗右側的預覽：在一段範例內容上面放選字框、英文建議、模式提示，
/// 透明度、底色、背景圖的效果都看得到
final class PreviewPane: NSView {
    private let candidates = PanelChrome(withinWindow: true)
    private let suggestions = PanelChrome(withinWindow: true)
    private let toast = PanelChrome(withinWindow: true)

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        candidates.list.rows = [
            CandidateRow(number: "1", text: "你好"),
            CandidateRow(number: "2", text: "👋", selected: true),
            CandidateRow(number: "3", text: "妳好"),
            CandidateRow(number: "4", text: "好"),
        ]
        candidates.list.footer = "1/3  空白鍵下一頁"
        suggestions.list.rows = [
            CandidateRow(text: "meeting", hint: "Tab", selected: true),
            CandidateRow(text: "meet"),
            CandidateRow(text: "meetings"),
        ]
        toast.list.compact = true
        toast.list.rows = [CandidateRow(text: "混合")]
        for c in [candidates, suggestions, toast] { addSubview(c) }
    }

    required init?(coder: NSCoder) { fatalError("不支援") }

    /// 設定改了之後呼叫：重新算大小、重畫
    func refresh() {
        var y: CGFloat = 52 // 文件標題的下面
        for c in [candidates, suggestions, toast] {
            let size = c.list.contentSize
            c.frame = NSRect(x: 26, y: y, width: size.width, height: size.height)
            c.refresh()
            y += size.height + 20
        }
    }

    override func layout() {
        super.layout()
        refresh()
    }

    /// 範例內容：一份有標題、內文和一張圖的文件，用來看玻璃和透明度
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let w = bounds.width - 36
        func text(_ s: String, _ font: NSFont, _ color: NSColor, y: CGFloat, height: CGFloat) {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 5
            (s as NSString).draw(in: NSRect(x: 18, y: y, width: w, height: height),
                                 withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        }
        text("週會筆記", .boldSystemFont(ofSize: 18), .labelColor, y: 16, height: 26)
        text("這週把 onboarding 流程的 A/B test 結果整理完，新版的完成率比較高，下週一跟 design team 開會確認要不要全面上線。另外 API 的 rate limit 還沒調整，要先問一下後端。",
             .systemFont(ofSize: 13), .secondaryLabelColor, y: 50, height: 150)
        // 文件裡的一張圖
        let photo = NSBezierPath(roundedRect: NSRect(x: 18, y: 208, width: w, height: 128), xRadius: 8, yRadius: 8)
        NSGradient(colors: [.systemTeal, .systemIndigo])?.draw(in: photo, angle: -35)
        text("待辦：更新 release note、回覆客服轉來的三封信、把 demo 影片傳給 PM。有空的話順便看一下 dashboard 上週的數字為什麼掉。",
             .systemFont(ofSize: 13), .secondaryLabelColor, y: 352, height: bounds.height - 362)
    }
}

/// 「設定…」視窗：輸入方式的開關和外觀。左邊調整，右邊預覽立刻更新；選字框下次出現時套用
final class SettingsWindow: NSObject {
    static let shared = SettingsWindow()

    private(set) var window: NSWindow?
    private let themes = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let wellA = NSColorWell(), wellB = NSColorWell(), bgWell = NSColorWell()
    private let glow = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let clear = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let bgStrength = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let bgImageOpacity = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let size = NSSlider(value: 18, minValue: 14, maxValue: 26, target: nil, action: nil)
    private let cat = NSButton(checkboxWithTitle: "在選字框裡顯示圖示", target: nil, action: nil)
    private let enMode = NSButton(checkboxWithTitle: "英文模式（輕按 Shift 切換）", target: nil, action: nil)
    private let zhOnly = NSButton(checkboxWithTitle: "只打注音（不自動判斷英文）", target: nil, action: nil)
    private let autoSpace = NSButton(checkboxWithTitle: "中英之間自動空格", target: nil, action: nil)
    private var removeBg: NSButton!
    private var valueLabels: [(NSSlider, NSTextField, (Double) -> String)] = []
    private let preview = PreviewPane(frame: .zero)

    func show() {
        if window == nil { build() }
        sync()
        NSApp.activate(ignoringOtherApps: true) // 輸入法是背景程式，要先叫到前面視窗才會出現
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    func build() {
        themes.addItem(withTitle: "選擇主題…")
        themes.addItems(withTitles: PanelStyle.themes.map { $0.name })
        themes.target = self
        themes.action = #selector(pickTheme(_:))
        mode.addItems(withTitles: ["跟隨系統", "淺色", "深色"])
        for c in [enMode, zhOnly, autoSpace] {
            c.target = self
            c.action = #selector(inputChanged(_:))
        }
        for c in [mode, wellA, wellB, bgWell, glow, clear, bgStrength, bgImageOpacity, size, cat] as [NSControl] {
            c.target = self
            c.action = #selector(changed(_:))
        }

        func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }
        func header(_ s: String) -> NSTextField {
            let l = label(s)
            l.font = .boldSystemFont(ofSize: 13)
            return l
        }
        /// 滑桿加上右邊的數值
        func slider(_ s: NSSlider, _ format: @escaping (Double) -> String) -> NSView {
            s.isContinuous = true
            s.widthAnchor.constraint(equalToConstant: 170).isActive = true
            let value = label("")
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            value.textColor = .secondaryLabelColor
            value.widthAnchor.constraint(equalToConstant: 44).isActive = true
            valueLabels.append((s, value, format))
            return NSStackView(views: [s, value])
        }
        func well(_ w: NSColorWell) -> NSColorWell {
            w.widthAnchor.constraint(equalToConstant: 56).isActive = true
            w.heightAnchor.constraint(equalToConstant: 24).isActive = true
            return w
        }
        let percent: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

        removeBg = NSButton(title: "移除", target: self, action: #selector(removeBgImage(_:)))
        let bgButtons = NSStackView(views: [
            NSButton(title: "選擇圖片…", target: self, action: #selector(chooseBgImage(_:))), removeBg,
        ])
        let iconButtons = NSStackView(views: [
            NSButton(title: "選擇圖片…", target: self, action: #selector(chooseIcon(_:))),
            NSButton(title: "用預設的貓咪", target: self, action: #selector(resetIcon(_:))),
        ])
        let reset = NSButton(title: "全部還原預設", target: self, action: #selector(resetDefaults(_:)))

        let empty = NSGridCell.emptyContentView
        let rows: [[NSView]] = [
            [header("輸入"), empty],
            [empty, enMode],
            [empty, zhOnly],
            [empty, autoSpace],
            [header("主題"), empty],
            [label("套用主題"), themes],
            [header("選中的項目"), empty],
            [label("漸層起點"), well(wellA)],
            [label("漸層終點"), well(wellB)],
            [label("光暈"), slider(glow, percent)],
            [header("窗格"), empty],
            [label("外觀"), mode],
            [label("透明度"), slider(clear, percent)],
            [label("底色"), well(bgWell)],
            [label("底色濃度"), slider(bgStrength, percent)],
            [label("背景圖"), bgButtons],
            [label("背景圖濃度"), slider(bgImageOpacity, percent)],
            [header("文字與圖示"), empty],
            [label("字級"), slider(size) { "\(Int($0)) pt" }],
            [label("圖示"), iconButtons],
            [empty, cat],
            [empty, reset],
        ]
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 9
        grid.columnSpacing = 12
        for (i, row) in rows.enumerated() where row[1] === empty && row[0] !== empty {
            // 分區標題：靠左、跨兩欄、上面多留一點空間
            grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: i, length: 1))
            grid.cell(atColumnIndex: 0, rowIndex: i).xPlacement = .leading
            if i > 0 { grid.row(at: i).topPadding = 8 }
        }
        grid.row(at: rows.count - 1).topPadding = 8

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "玉米輸入法 — 設定"
        w.isReleasedWhenClosed = false
        w.level = .floating
        let content = NSView()
        for v in [grid, preview] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            preview.leadingAnchor.constraint(equalTo: grid.trailingAnchor, constant: 24),
            preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            preview.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            preview.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            preview.widthAnchor.constraint(equalToConstant: 300),
            preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 470), // 最大字級時三個範例的高度
        ])
        w.contentView = content
        window = w
    }

    /// 把目前的設定填進各個控制項，並更新預覽
    func sync() {
        let s = PanelStyle.shared
        mode.selectItem(at: s.appearanceMode)
        wellA.color = s.colorA
        wellB.color = s.colorB
        bgWell.color = s.bgColor
        glow.doubleValue = s.glow
        clear.doubleValue = s.transparency
        bgStrength.doubleValue = s.bgStrength
        bgImageOpacity.doubleValue = s.bgImageOpacity
        size.doubleValue = s.fontSize
        cat.state = s.showCat ? .on : .off
        enMode.state = CornData.shared.enMode ? .on : .off
        zhOnly.state = CornData.shared.zhOnly ? .on : .off
        autoSpace.state = CornData.shared.autoSpace ? .on : .off
        refresh()
    }

    /// 數值標籤、可不可以按、預覽
    private func refresh() {
        for (s, label, format) in valueLabels { label.stringValue = format(s.doubleValue) }
        let hasBg = PanelStyle.bgImage != nil
        removeBg.isEnabled = hasBg
        bgImageOpacity.isEnabled = hasBg
        preview.refresh()
    }

    @objc private func changed(_ sender: Any?) {
        size.doubleValue = size.doubleValue.rounded()
        var s = PanelStyle.shared
        s.appearanceMode = mode.indexOfSelectedItem
        s.colorA = wellA.color
        s.colorB = wellB.color
        s.bgColor = bgWell.color
        s.glow = glow.doubleValue
        s.transparency = clear.doubleValue
        s.bgStrength = bgStrength.doubleValue
        s.bgImageOpacity = bgImageOpacity.doubleValue
        s.fontSize = size.doubleValue
        s.showCat = cat.state == .on
        PanelStyle.shared = s
        themes.selectItem(at: 0) // 手動調過就不算是某個主題
        refresh()
    }

    /// 輸入方式的三個開關：立刻生效
    @objc private func inputChanged(_ sender: Any?) {
        CornData.shared.enMode = enMode.state == .on
        CornData.shared.zhOnly = zhOnly.state == .on
        CornData.shared.autoSpace = autoSpace.state == .on
    }

    @objc private func pickTheme(_ sender: Any?) {
        let i = themes.indexOfSelectedItem - 1
        guard PanelStyle.themes.indices.contains(i) else { return }
        var s = PanelStyle.shared
        s.apply(PanelStyle.themes[i])
        PanelStyle.shared = s
        sync()
    }

    private func pickImage(_ message: String) -> NSImage? {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.image]
        open.allowsMultipleSelection = false
        open.message = message
        guard open.runModal() == .OK, let url = open.url else { return nil }
        return NSImage(contentsOf: url)
    }

    @objc private func chooseIcon(_ sender: Any?) {
        guard let image = pickImage("選一張圖片當作選字框裡的圖示（建議用正方形、去背的圖）") else { return }
        PanelStyle.setCustomIcon(image)
        refresh()
    }

    @objc private func resetIcon(_ sender: Any?) {
        PanelStyle.setCustomIcon(nil)
        refresh()
    }

    @objc private func chooseBgImage(_ sender: Any?) {
        guard let image = pickImage("選一張圖片當作選字框的背景") else { return }
        PanelStyle.setBgImage(image)
        refresh()
    }

    @objc private func removeBgImage(_ sender: Any?) {
        PanelStyle.setBgImage(nil)
        refresh()
    }

    /// 全部還原：設定值、圖示、背景圖
    @objc private func resetDefaults(_ sender: Any?) {
        PanelStyle.shared = PanelStyle.defaults
        PanelStyle.setCustomIcon(nil)
        PanelStyle.setBgImage(nil)
        themes.selectItem(at: 0)
        sync()
    }
}
