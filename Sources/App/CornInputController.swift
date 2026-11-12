import Cocoa
import InputMethodKit

/// 每個輸入視窗（App 裡的文字框）各有一個 controller
@objc(CornInputController)
final class CornInputController: IMKInputController {
    private let engine = CornEngine(data: CornData.shared)
    private var shiftAlone = false
    private var loggedKeys = 0 // 只記前幾個按鍵，方便除錯

    // 跟「已經送出去的文字」之間的自動空格用
    /// 最後送出（或在英文模式下打出）的那個字。App 不告訴我們游標前面是什麼字時（例如終端機）靠它判斷
    private var tail: Character? = nil
    /// 使用者剛把中文後面的空格刪掉：下一次不要再自動補
    private var skipAutoSpace = false
    private var lastKeyTime: TimeInterval = 0

    private static let noReplace = NSRange(location: NSNotFound, length: NSNotFound)

    // 要收 flagsChanged 才能偵測「輕按 Shift」
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        engine.reset()
        tail = nil
        skipAutoSpace = false
        let client = sender as? IMKTextInput
        let app = client?.bundleIdentifier() ?? "不明的 App"
        imeLog("activateServer → " + app + (CornData.shared.enMode ? "（英文模式）" : ""))
        // 英文模式是全部 App 共用的：切到別的 App 時提醒一下，免得以為輸入法壞了
        if CornData.shared.enMode, let client = client {
            CandidatePanel.shared.toast("英文（輕按 Shift 切回混合）", near: caretRect(client))
        }
    }

    override func deactivateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput, !engine.isEmpty { commit(client) }
        CandidatePanel.shared.hide()
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput, !engine.isEmpty else { return }
        commit(client)
    }

    // MARK: - 按鍵

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, let client = sender as? IMKTextInput else {
            imeLog("handle：拿不到輸入視窗")
            return false
        }

        if event.type == .flagsChanged {
            if event.keyCode == 56 || event.keyCode == 60 { // 左右 Shift
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.shift) {
                    shiftAlone = flags.intersection([.command, .control, .option]).isEmpty
                } else if shiftAlone {
                    shiftAlone = false
                    toggleMode(client)
                }
            } else {
                shiftAlone = false
            }
            return false
        }

        guard event.type == .keyDown else { return false }
        shiftAlone = false

        if CornData.shared.enMode {
            // 英文模式：按鍵全部直接交給 App，跟一般英文鍵盤一樣
            if !engine.isEmpty { commit(client) }
            if loggedKeys < 40 { loggedKeys += 1; imeLog("英文模式，按鍵 keyCode=\(event.keyCode) 直接交給 App") }
            passthrough(event, client, english: true)
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            if !engine.isEmpty { commit(client) }
            passthrough(event, client, english: false)
            return false
        }

        let key: Key
        switch event.keyCode {
        case 36, 76: key = .enter
        case 48: key = flags.contains(.shift) ? .shiftTab : .tab
        case 49: key = .space
        case 51: key = .backspace
        case 53: key = .escape
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        case 116: key = .pageUp
        case 121: key = .pageDown
        default:
            guard let chars = event.characters, chars.count == 1, let ch = chars.first,
                  let ascii = ch.asciiValue, ascii >= 0x21, ascii < 0x7F else {
                // 其他鍵（Home、End、功能鍵、非 ASCII）：先送出組字再交給 App
                if !engine.isEmpty { commit(client) }
                if loggedKeys < 40 {
                    loggedKeys += 1
                    imeLog("按鍵 keyCode=\(event.keyCode) 沒有對應的字元（characters 長度 \(event.characters?.count ?? -1)），直接交給 App")
                }
                passthrough(event, client, english: false)
                return false
            }
            key = .char(ch)
        }
        let handled = process(key, client: client)
        if !handled { passthrough(event, client, english: false) }
        if loggedKeys < 40 {
            loggedKeys += 1
            imeLog("按鍵 keyCode=\(event.keyCode) 已處理=\(handled) 組字長度=\(engine.renderText().count)")
        }
        return handled
    }

    private func process(_ key: Key, client: IMKTextInput) -> Bool {
        if engine.cand != nil {
            if case .char(let ch) = key, !(ch >= "1" && ch <= "9") {
                engine.cand = nil // 選字窗開著時繼續打字：關掉選字窗照常處理
            } else {
                engine.candKey(key)
                update(client)
                return true
            }
        }

        if engine.isEmpty {
            // 沒在組字：除了一般字元，其他鍵都交給 App 本身
            guard case .char = key else { return false }
        }

        switch key {
        case .backspace:
            engine.backspace()
        case .enter:
            commit(client)
            return true
        case .escape:
            engine.reset()
        case .left:
            engine.moveCursor(-1) // 游標往前移，之後按 ↓ 或空白可以選前面的字
        case .right:
            engine.moveCursor(1)
        case .pageUp, .pageDown:
            return true
        case .up, .down:
            let sug = engine.suggestions()
            if !sug.isEmpty {
                let n = sug.count
                engine.sugSel = (engine.sugSel + (key == .down ? 1 : -1) + n) % n
            } else if key == .down {
                engine.openCandidates()
            }
        default:
            if let text = engine.press(key) { insert(text, client) }
        }
        update(client)
        return true
    }

    // MARK: - 畫面

    private func insert(_ text: String, _ client: IMKTextInput) {
        var out = text
        if CornData.shared.autoSpace && !skipAutoSpace, let first = text.first,
           let prev = charBefore(client) ?? tail {
            // 跟前面已經送出的文字之間也補空格：中文後面接英文，或英文後面接中文
            if (Self.isHan(prev) && Self.isLetter(first)) || (Self.isLetter(prev) && Self.isHan(first)) {
                out = " " + text
            }
        }
        skipAutoSpace = false
        client.insertText(out, replacementRange: Self.noReplace)
        tail = out.last
    }

    // MARK: - 跟已經送出的文字之間的自動空格

    private static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) }
    }

    private static func isLetter(_ c: Character) -> Bool {
        c.isASCII && c.isLetter
    }

    /// 游標前面第 back 個字（1 = 緊鄰游標）。有些 App 不提供，回傳 nil
    private func charBefore(_ client: IMKTextInput, back: Int = 1) -> Character? {
        var loc = client.selectedRange().location
        let marked = client.markedRange()
        if marked.location != NSNotFound && marked.length > 0 { loc = marked.location }
        guard loc != NSNotFound, loc >= back else { return nil }
        guard let s = client.attributedSubstring(from: NSRange(location: loc - back, length: 1))?.string else { return nil }
        return s.first
    }

    /// 按鍵直接交給 App 之前呼叫：英文模式下，中文後面打英文先補一個空格；
    /// 並記住游標前面的狀況，供下一次判斷
    private func passthrough(_ event: NSEvent, _ client: IMKTextInput, english: Bool) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = flags.intersection([.command, .control, .option]).isEmpty
        let quick = event.timestamp - lastKeyTime < 0.7 // 連續打字中
        lastKeyTime = event.timestamp

        if event.keyCode == 51 && plain { // Backspace
            // 正要刪掉的是中文後面的空格 → 這個位置不要再自動補
            if charBefore(client) == " ", let before = charBefore(client, back: 2), Self.isHan(before) {
                skipAutoSpace = true
            }
            tail = nil
            return
        }

        guard english, plain, let chars = event.characters, chars.count == 1,
              let ch = chars.first, Self.isLetter(ch) else {
            tail = nil
            skipAutoSpace = false
            return
        }
        // 連續打英文時前一個字就是剛打的字母，不用再問 App
        let known = quick && (tail.map { Self.isLetter($0) } ?? false)
        if !known && CornData.shared.autoSpace && !skipAutoSpace,
           let prev = charBefore(client) ?? tail, Self.isHan(prev) {
            client.insertText(" ", replacementRange: Self.noReplace)
        }
        skipAutoSpace = false
        tail = ch
    }

    private func commit(_ client: IMKTextInput) {
        let text = engine.commitAll()
        if !text.isEmpty { insert(text, client) }
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: Self.noReplace)
        CandidatePanel.shared.hide()
    }

    private func caretRect(_ client: IMKTextInput) -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        if rect.origin == .zero && rect.size == .zero {
            // 有些 App 不回報游標位置：改放在滑鼠游標旁邊，選字窗才不會跑到畫面外看不到
            let mouse = NSEvent.mouseLocation
            rect = NSRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
        }
        return rect
    }

    private func update(_ client: IMKTextInput) {
        let text = engine.renderText()
        let marked = NSAttributedString(string: text, attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        client.setMarkedText(marked, selectionRange: NSRange(location: engine.cursorOffset(), length: 0),
                             replacementRange: Self.noReplace)

        if let popup = popupRows() {
            CandidatePanel.shared.show(popup.rows, footer: popup.footer, near: caretRect(client))
        } else {
            CandidatePanel.shared.hide()
        }
    }

    /// 選字窗要顯示的內容：中文選字（有數字、分頁）或英文建議（選中的那列提示 Tab）
    private func popupRows() -> (rows: [CandidateRow], footer: String)? {
        if let c = engine.cand {
            let page = c.sel / 9
            let items = c.items[(page * 9)..<min(c.items.count, page * 9 + 9)]
            let rows = items.enumerated().map { offset, it in
                CandidateRow(number: String(offset + 1), text: it.text, selected: page * 9 + offset == c.sel)
            }
            let pages = (c.items.count + 8) / 9
            return (rows, pages > 1 ? "\(page + 1)/\(pages)  空白鍵下一頁" : "")
        }
        let sug = engine.suggestions()
        guard !sug.isEmpty else { return nil }
        let sel = min(engine.sugSel, sug.count - 1)
        let rows = sug.enumerated().map { i, w in
            CandidateRow(text: w, hint: i == sel ? "Tab" : "", selected: i == sel)
        }
        return (rows, "")
    }

    /// 輕按 Shift：在中文（中英混打）和英文模式之間切換
    private func toggleMode(_ client: IMKTextInput) {
        if !engine.isEmpty { commit(client) }
        CornData.shared.enMode.toggle()
        CandidatePanel.shared.toast(CornData.shared.enMode ? "英文" : "混合", near: caretRect(client))
    }

    // MARK: - 選單列的輸入法選單

    override func menu() -> NSMenu! {
        let m = NSMenu()
        let en = NSMenuItem(title: "英文模式（輕按 Shift 切換）", action: #selector(toggleEnMode(_:)), keyEquivalent: "")
        en.state = CornData.shared.enMode ? .on : .off
        m.addItem(en)
        let zh = NSMenuItem(title: "只打注音（不自動判斷英文）", action: #selector(toggleZhOnly(_:)), keyEquivalent: "")
        zh.state = CornData.shared.zhOnly ? .on : .off
        m.addItem(zh)
        let sp = NSMenuItem(title: "中英之間自動空格", action: #selector(toggleAutoSpace(_:)), keyEquivalent: "")
        sp.state = CornData.shared.autoSpace ? .on : .off
        m.addItem(sp)
        return m
    }

    @objc func toggleEnMode(_ sender: Any?) {
        CornData.shared.enMode.toggle()
    }

    @objc func toggleZhOnly(_ sender: Any?) {
        CornData.shared.zhOnly.toggle()
    }

    @objc func toggleAutoSpace(_ sender: Any?) {
        CornData.shared.autoSpace.toggle()
    }
}
