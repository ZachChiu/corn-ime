import Cocoa
import UniformTypeIdentifiers

/// 梗圖庫：圖檔放在 ~/Library/Application Support/CornIME/Memes，索引是同資料夾的 index.json
final class MemeStore {
    static let shared = MemeStore()

    struct Meme: Codable {
        var id: String          // 檔名
        var keywords: [String]
    }

    private(set) var memes: [Meme] = []
    private var thumbs: [String: NSImage] = [:]
    private let dir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("CornIME/Memes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: dir.appendingPathComponent("index.json")),
           let list = try? JSONDecoder().decode([Meme].self, from: data) {
            memes = list.filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.id).path) }
        }
        publish()
    }

    func url(_ id: String) -> URL { dir.appendingPathComponent(id) }

    func thumbnail(_ id: String) -> NSImage? {
        if let t = thumbs[id] { return t }
        let image = NSImage(contentsOf: url(id))
        thumbs[id] = image
        return image
    }

    /// 把圖檔複製進梗圖庫，預設關鍵字是檔名
    func add(_ source: URL) {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let id = UUID().uuidString + "." + ext
        do {
            try FileManager.default.copyItem(at: source, to: url(id))
        } catch {
            NSLog("CornIME: 加入梗圖失敗 \(error.localizedDescription)")
            return
        }
        memes.append(Meme(id: id, keywords: [source.deletingPathExtension().lastPathComponent]))
        save()
    }

    func remove(at index: Int) {
        guard memes.indices.contains(index) else { return }
        try? FileManager.default.removeItem(at: url(memes[index].id))
        thumbs[memes[index].id] = nil
        memes.remove(at: index)
        save()
    }

    /// 關鍵字用空白、逗號、頓號分隔
    func setKeywords(_ text: String, at index: Int) {
        guard memes.indices.contains(index) else { return }
        memes[index].keywords = text.split(whereSeparator: { " ,，、\t".contains($0) }).map(String.init)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(memes) {
            try? data.write(to: dir.appendingPathComponent("index.json"), options: .atomic)
        }
        publish()
    }

    /// 把關鍵字交給引擎，選字時才比對得到
    private func publish() {
        CornData.shared.memes = memes.flatMap { m in m.keywords.map { (keyword: $0, id: m.id) } }
    }

    // MARK: 貼到目前的 App

    /// 有「輔助使用」權限才能替使用者按 ⌘V
    static var canAutoPaste: Bool { AXIsProcessTrusted() }

    /// 把梗圖放進剪貼簿。有權限時自動按 ⌘V 貼上、之後把剪貼簿還原，回傳 true；
    /// 沒權限時圖留在剪貼簿，回傳 false（由呼叫的人提示使用者自己貼）
    func paste(_ id: String) -> Bool {
        let file = url(id)
        let pb = NSPasteboard.general
        let auto = Self.canAutoPaste
        // 自動貼上會暫時蓋掉剪貼簿，先記下原本的內容
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = !auto ? [] : (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }

        // 同時放檔案和圖片資料：聊天軟體多半收檔案（GIF 才會動），文件類 App 收圖片資料
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        if file.pathExtension.lowercased() == "gif", let data = try? Data(contentsOf: file) {
            item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        } else if let tiff = NSImage(contentsOf: file)?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pb.clearContents()
        pb.writeObjects([item])
        guard auto else { return false }

        // 等 App 把剛送出的文字處理完再按 ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down) // 9 = V
                e?.flags = .maskCommand
                e?.post(tap: .cgAnnotatedSessionEventTap)
            }
            // App 讀完剪貼簿之後還原
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard !saved.isEmpty else { return }
                pb.clearContents()
                pb.writeObjects(saved.map { pairs in
                    let old = NSPasteboardItem()
                    for (t, d) in pairs { old.setData(d, forType: t) }
                    return old
                })
            }
        }
        return true
    }
}

/// 「梗圖庫…」視窗：加入圖片、設定關鍵字、移除
final class MemeWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let shared = MemeWindow()

    private(set) var window: NSWindow?
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private var grant: NSButton!
    private var store: MemeStore { MemeStore.shared }

    func show() {
        if window == nil { build() }
        table.reloadData()
        refreshStatus()
        NSApp.activate(ignoringOtherApps: true) // 輸入法是背景程式，要先叫到前面視窗才會出現
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    func build() {
        let help = NSTextField(wrappingLabelWithString:
            "打出關鍵字後按空白開選字窗，梗圖會排在第 2 個選項，選了就貼到目前的 App。\n關鍵字要是中文，同音字也會符合；一張圖可以設多個關鍵字，用空白或逗號分開。")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)

        let image = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("image"))
        image.title = "梗圖"
        image.width = 96
        let keywords = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("keywords"))
        keywords.title = "關鍵字（點兩下修改）"
        keywords.width = 380
        table.addTableColumn(image)
        table.addTableColumn(keywords)
        table.rowHeight = 64
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let add = NSButton(title: "加入圖片…", target: self, action: #selector(addImages(_:)))
        let remove = NSButton(title: "移除選取的", target: self, action: #selector(removeSelected(_:)))
        grant = NSButton(title: "開啟自動貼上…", target: self, action: #selector(requestAccess(_:)))
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        status.lineBreakMode = .byTruncatingTail
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [add, remove, spacer, status, grant])

        let stack = NSStackView(views: [help, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "玉米輸入法 — 梗圖庫"
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self
        w.minSize = NSSize(width: 480, height: 320)
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        w.contentView = content
        window = w
    }

    /// 自動貼上的權限狀態
    private func refreshStatus() {
        let ok = MemeStore.canAutoPaste
        status.stringValue = ok ? "自動貼上：已開啟" : "自動貼上未開啟：選了梗圖會複製到剪貼簿，要自己按 ⌘V"
        grant.isHidden = ok
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshStatus() } // 從系統設定回來時更新

    // MARK: 表格

    func numberOfRows(in tableView: NSTableView) -> Int { store.memes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let meme = store.memes[row]
        if tableColumn?.identifier.rawValue == "image" {
            let view = NSImageView()
            view.image = store.thumbnail(meme.id)
            view.imageScaling = .scaleProportionallyUpOrDown
            return view
        }
        let field = NSTextField(string: meme.keywords.joined(separator: " "))
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = "輸入關鍵字"
        field.tag = row
        field.target = self
        field.action = #selector(keywordsEdited(_:))
        // 讓文字在列裡垂直置中
        let cell = NSView()
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func keywordsEdited(_ sender: NSTextField) {
        store.setKeywords(sender.stringValue, at: sender.tag)
    }

    @objc private func addImages(_ sender: Any?) {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.image]
        open.allowsMultipleSelection = true
        open.message = "選擇要加入梗圖庫的圖片（可以一次選多張）"
        guard open.runModal() == .OK, !open.urls.isEmpty else { return }
        for url in open.urls { store.add(url) }
        table.reloadData()
        // 捲到新加的那列並直接開始改關鍵字（預設是檔名）
        let last = store.memes.count - 1
        guard last >= 0 else { return }
        table.scrollRowToVisible(last)
        table.selectRowIndexes([last], byExtendingSelection: false)
        if let cell = table.view(atColumn: 1, row: last, makeIfNecessary: true),
           let field = cell.subviews.first as? NSTextField {
            window?.makeFirstResponder(field)
        }
    }

    @objc private func removeSelected(_ sender: Any?) {
        window?.makeFirstResponder(nil) // 先結束編輯中的關鍵字
        for row in table.selectedRowIndexes.reversed() { store.remove(at: row) }
        table.reloadData()
    }

    @objc private func requestAccess(_ sender: Any?) {
        // 跳出系統的詢問視窗，帶使用者到 系統設定 → 隱私權與安全性 → 輔助使用
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
