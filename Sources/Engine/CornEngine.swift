import Foundation

/// 鍵盤輸入，跟實體按鍵脫鉤，方便測試
enum Key: Equatable {
    case char(Character)
    case space, tab, shiftTab, enter, backspace, escape
    case up, down, left, right, pageUp, pageDown
}

/// 組字區的一段
struct Seg {
    enum Kind { case zh, en, lit, fx }
    var t: Kind
    var raw = ""          // 實際按的鍵
    var bpmf = ""         // 注音
    var done = false      // 注音已打完聲調
    var text = ""         // 英文、符號、已選字的文字
    var open = false      // 英文還在打
    var alt: String? = nil // 這個字也可能是英文：按 Tab 換回這段文字
    var key = ""          // 已選字的讀音
    var auto = false      // 中英之間自動補的空格
    var noAutoSpace = false // 使用者刪掉了這段後面的自動空格，不再補
}

func mkZh(_ raw: String, _ bpmf: String, done: Bool = false) -> Seg {
    var s = Seg(t: .zh); s.raw = raw; s.bpmf = bpmf; s.done = done; return s
}
func mkEn(_ text: String, open: Bool = true) -> Seg {
    var s = Seg(t: .en); s.text = text; s.open = open; return s
}
func mkLit(_ text: String) -> Seg {
    var s = Seg(t: .lit); s.text = text; return s
}
func mkAutoSpace() -> Seg {
    var s = Seg(t: .lit); s.text = " "; s.auto = true; return s
}

/// 畫面上顯示的片段
struct Piece {
    enum Kind { case zh, en, partial, fx, lit }
    var text: String
    var kind: Kind
}

struct CandItem { let text: String; let len: Int; let key: String }
struct CandState { var items: [CandItem]; var sel: Int }

/// 中英混打引擎：注音（大千鍵盤）＋英文自動判斷
final class CornEngine {
    static let zhMap: [Character: String] = [
        "1": "ㄅ", "q": "ㄆ", "a": "ㄇ", "z": "ㄈ", "2": "ㄉ", "w": "ㄊ", "s": "ㄋ", "x": "ㄌ",
        "e": "ㄍ", "d": "ㄎ", "c": "ㄏ", "r": "ㄐ", "f": "ㄑ", "v": "ㄒ", "5": "ㄓ", "t": "ㄔ",
        "g": "ㄕ", "b": "ㄖ", "y": "ㄗ", "h": "ㄘ", "n": "ㄙ", "u": "ㄧ", "j": "ㄨ", "m": "ㄩ",
        "8": "ㄚ", "i": "ㄛ", "k": "ㄜ", ",": "ㄝ", "9": "ㄞ", "o": "ㄟ", "l": "ㄠ", ".": "ㄡ",
        "0": "ㄢ", "p": "ㄣ", ";": "ㄤ", "/": "ㄥ", "-": "ㄦ",
    ]
    static let toneMap: [Character: String] = ["6": "ˊ", "3": "ˇ", "4": "ˋ", "7": "˙"]
    static let punct: [Character: String] = [
        "<": "，", ">": "。", "?": "？", ":": "：", "!": "！", "\"": "、",
        "(": "（", ")": "）", "{": "『", "}": "』", "[": "「", "]": "」", "~": "～",
    ]
    let maxPhrase = 6

    let d: CornData
    private(set) var segs: [Seg] = []
    var cand: CandState? = nil
    var sugSel = 0
    /// 游標後面還有幾段（0 = 游標在最後面）。按 ← → 移動，用來選前面的字
    private(set) var cursorBack = 0

    init(data: CornData) { d = data }

    var isEmpty: Bool { segs.isEmpty && cand == nil }

    func reset() {
        segs = []; cand = nil; sugSel = 0; cursorBack = 0
    }

    // MARK: - 小工具

    static func isDigits(_ w: String) -> Bool {
        !w.isEmpty && w.allSatisfy { $0 >= "0" && $0 <= "9" }
    }
    static func isLowerLetters(_ w: String) -> Bool {
        !w.isEmpty && w.allSatisfy { $0 >= "a" && $0 <= "z" }
    }
    static func isWordLike(_ w: String) -> Bool {
        guard let f = w.first, f.isASCII, f.isLetter else { return false }
        return w.allSatisfy { ($0.isASCII && $0.isLetter) || $0 == "'" || $0 == "-" }
    }
    static func isCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3000...0x9FFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value) }
    }
    static func isAlnum(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }

    // MARK: - 英文

    func isWord(_ w: String) -> Bool { d.en[w.lowercased()] != nil }
    func isWordPrefix(_ w: String) -> Bool { d.enPrefix.contains(w.lowercased()) }
    func wordComplete(_ w: String) -> Bool { isWord(w) || Self.isDigits(w) }

    /// 全打小寫時套用字典的大小寫（chatgpt → ChatGPT、i → I）
    func displayCase(_ w: String) -> String {
        if w != w.lowercased() { return w }
        return d.en[w]?.0 ?? w
    }

    func completions(_ prefix: String, _ n: Int = 5) -> [String] {
        let p = prefix.lowercased()
        guard !p.isEmpty, d.enPrefix.contains(p) else { return [] }
        let keys = d.enKeys
        var lo = 0, hi = keys.count
        while lo < hi {
            let m = (lo + hi) / 2
            if keys[m] < p { lo = m + 1 } else { hi = m }
        }
        var found: [(String, Double)] = []
        var i = lo
        while i < keys.count && keys[i].hasPrefix(p) {
            let k = keys[i]
            if let e = d.en[k] {
                // 已經打完整的字本身不列入，除非大小寫不同（chatgpt → ChatGPT）
                if !(k == p && e.0 == k) { found.append((k, e.1 + (k == p ? 1 : 0))) }
            }
            i += 1
        }
        found.sort { $0.1 > $1.1 }
        let capFirst = prefix.first?.isUppercase ?? false
        return found.prefix(n).map { pair -> String in
            var disp = d.en[pair.0]?.0 ?? pair.0
            if capFirst && disp == pair.0 { disp = disp.prefix(1).uppercased() + String(disp.dropFirst()) }
            return disp
        }
    }

    // MARK: - 狀態

    private var last: Seg? { segs.last }
    private func isPartial(_ s: Seg?) -> Bool { guard let s = s else { return false }; return s.t == .zh && !s.done }
    private func isOpenEn(_ s: Seg?) -> Bool { guard let s = s else { return false }; return s.t == .en && s.open }
    private var lastIsEn: Bool { last?.t == Seg.Kind.en }

    /// 正在打的這段之前，最近的一段是英文嗎？
    private func inEnglishContext() -> Bool {
        var i = segs.count - 2
        while i >= 0 {
            let s = segs[i]
            if s.t == .en { return true }
            if s.t == .lit && !Self.isCJK(s.text) { i -= 1; continue }
            return false
        }
        return false
    }

    func suggestions() -> [String] {
        guard cursorBack == 0, let s = last else { return [] }
        if isOpenEn(s) && Self.isWordLike(s.text) { return completions(s.text) }
        if isPartial(s) && s.raw.count >= 2 && Self.isLowerLetters(s.raw) { return completions(s.raw, 3) }
        return []
    }

    // MARK: - 按鍵

    enum Outcome { case changed, noop, commit(String) }

    /// 處理一個按鍵，回傳要直接送出的文字（若有）
    @discardableResult
    func press(_ key: Key) -> String? {
        if cand != nil { candKey(key); return nil }
        // 游標在中間時：先把游標後面的段落拿開，照「游標在最後面」處理完再接回去，字就會插在游標的位置
        var after: [Seg] = []
        if cursorBack > 0 {
            let c = segs.count - cursorBack
            if c == 0 && key == .space { return nil } // 游標在最前面按空白：沒有字可以選
            after = Array(segs[c...])
            segs.removeSubrange(c...)
            cursorBack = 0
        }
        defer {
            if !after.isEmpty {
                segs.append(contentsOf: after)
                cursorBack = after.count
                normalizeSpaces()
            }
        }
        var out = Outcome.changed
        switch key {
        case .space: out = space()
        case .tab: out = tab()
        case .shiftTab: out = forceZh()
        case .char(let ch):
            if ch.isASCII && ch.isUppercase { upper(ch) }
            else if Self.zhMap[ch] != nil || Self.toneMap[ch] != nil { zhKey(ch) }
            else { symbol(ch) }
        default: out = .noop
        }
        sugSel = 0
        if case .commit(let t) = out {
            if after.isEmpty { return t }
            segs = [mkEn(t, open: false)] // 後面還有字：不單獨送出前半段，留在組字區
        }
        normalizeSpaces()
        return nil
    }

    private func upper(_ ch: Character) {
        let c = String(ch)
        if isOpenEn(last) { segs[segs.count - 1].text += c }
        else if isPartial(last) { segs[segs.count - 1] = mkEn(segs[segs.count - 1].raw + c) }
        else { segs.append(mkEn(c)) }
    }

    private func zhKey(_ k: Character) {
        let ks = String(k)
        let tone = Self.toneMap[k]
        let sym = Self.zhMap[k]

        if d.zhOnly {
            if isOpenEn(last) {
                let i = segs.count - 1
                segs[i].open = false
                segs[i].text = displayCase(segs[i].text)
            }
            zhOnlyKey(k)
            return
        }

        if isOpenEn(last) {
            let i = segs.count - 1
            let text = segs[i].text
            let next = text + ks
            let startsZh = sym != nil && k.isASCII && (k.isLowercase || k.isNumber)
            let hasDigit = text.contains { $0 >= "0" && $0 <= "9" }
            if startsZh && wordComplete(text) && !isWordPrefix(next) && !(hasDigit && k.isNumber) {
                // 英文字已經完整，後面這個鍵接不成英文 → 切回注音
                segs[i].open = false
                // 記住原本的按鍵：後面如果拼不成注音，會連這段一起重新判斷（us06 其實是 ㄋㄧㄢˊ）
                if Self.isLowerLetters(text) { segs[i].raw = text }
                segs[i].text = displayCase(text)
                segs.append(mkZh(ks, sym!))
            } else {
                segs[i].text = next
                rejudge()
            }
            return
        }

        if isPartial(last) {
            let i = segs.count - 1
            if let tone = tone {
                if mergeSplitWord(toneKey: k) { return }
                let full = segs[i].bpmf + tone
                if d.syllables.contains(full) {
                    segs[i].bpmf = full; segs[i].raw += ks; segs[i].done = true
                } else {
                    segs[i] = mkEn(segs[i].raw + ks)
                    rejudge()
                }
                return
            }
            let nb = segs[i].bpmf + sym!
            if d.prefixes.contains(nb) { segs[i].bpmf = nb; segs[i].raw += ks }
            else { segs[i] = mkEn(segs[i].raw + ks) } // 照順序拼不出注音 → 先當英文，等聲調出現再判斷
            return
        }

        if tone != nil || !d.prefixes.contains(sym!) {
            segs.append(mkEn(ks))
            return
        }
        segs.append(mkZh(ks, sym!))
    }

    /// 注音符號在一個字裡的位置：0 聲母、1 介音、2 韻母
    private static func slot(_ c: Character) -> Int {
        if "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ".contains(c) { return 0 }
        if "ㄧㄨㄩ".contains(c) { return 1 }
        return 2
    }

    /// 只打注音模式：不會跳成英文；按錯的鍵替換同位置的符號
    private func zhOnlyKey(_ k: Character) {
        let ks = String(k)
        if let tone = Self.toneMap[k] {
            if isPartial(last) {
                let i = segs.count - 1
                if d.syllables.contains(segs[i].bpmf + tone) {
                    segs[i].bpmf += tone; segs[i].raw += ks; segs[i].done = true
                }
            }
            return
        }
        guard let sym = Self.zhMap[k] else { return }
        guard isPartial(last) else {
            if d.prefixes.contains(sym) { segs.append(mkZh(ks, sym)) }
            return
        }
        let i = segs.count - 1
        let nb = segs[i].bpmf + sym
        if d.prefixes.contains(nb) { segs[i].bpmf = nb; segs[i].raw += ks; return }
        var parts = ["", "", ""]
        for c in segs[i].bpmf { parts[Self.slot(c)] = String(c) }
        if let sc = sym.first { parts[Self.slot(sc)] = sym }
        let rb = parts.joined()
        if d.prefixes.contains(rb) { segs[i].bpmf = rb; segs[i].raw += ks }
    }

    /// Shift+Tab：把正在打的這段強制當注音
    private func forceZh() -> Outcome {
        guard let s = last else { return .noop }
        if s.t == .en {
            var raw = s.text
            if raw.hasSuffix(" ") { raw.removeLast() }
            let allowed = "abcdefghijklmnopqrstuvwxyz0123456789,./;-"
            guard !raw.isEmpty, raw.allSatisfy({ allowed.contains($0) }) else { return .noop }
            let repl: [Seg]
            if let parsed = parseZh(raw, allowLate: true) {
                repl = parsed
            } else {
                let symbols = raw.map { Self.zhMap[$0] ?? Self.toneMap[$0] ?? String($0) }.joined()
                repl = [mkLit(symbols)]
            }
            segs.removeLast()
            segs.append(contentsOf: repl)
            return .changed
        }
        if isPartial(s) {
            segs[segs.count - 1] = mkLit(s.bpmf)
            return .changed
        }
        return .noop
    }

    // MARK: - 把按鍵解析成注音

    /// 聲調鍵對應的聲調；空白是一聲
    private func toneOf(_ k: Character) -> String? {
        if k == " " { return "" }
        return Self.toneMap[k]
    }

    /// 照順序解析。allowLate：容許上一個字的聲調比下一個字的第一個鍵晚按（su3cl3 打成 suc3l3）
    private func parseZh(_ raw: String, allowLate: Bool) -> [Seg]? {
        let keys = Array(raw)
        var out: [Seg] = []
        var cur = "", curRaw = ""
        var i = 0
        while i < keys.count {
            let k = keys[i]
            if let tone = toneOf(k) {
                if cur.isEmpty || !d.syllables.contains(cur + tone) { return nil }
                out.append(mkZh(curRaw + String(k), cur + tone, done: true))
                cur = ""; curRaw = ""; i += 1
                continue
            }
            guard let sym = Self.zhMap[k] else { return nil }
            if d.prefixes.contains(cur + sym) {
                cur += sym; curRaw += String(k); i += 1
                continue
            }
            if allowLate, !cur.isEmpty, i + 1 < keys.count, let t = toneOf(keys[i + 1]),
               d.syllables.contains(cur + t), d.prefixes.contains(sym) {
                out.append(mkZh(curRaw + String(keys[i + 1]), cur + t, done: true))
                cur = sym; curRaw = String(k); i += 2
                continue
            }
            return nil
        }
        if !cur.isEmpty { out.append(mkZh(curRaw, cur)) }
        return out
    }

    /// 一個字的按鍵，不管按的順序，排回「聲母、介音、韻母、聲調」
    private struct Group {
        var bpmf = ""
        var tone: String? = nil
        var raw = ""        // 排回標準順序的按鍵
        var disorder = 0    // 順序亂了幾處
    }

    private func arrange(_ keys: ArraySlice<Character>) -> Group? {
        var syms = ["", "", ""]
        var raws = ["", "", "", ""]
        var order: [Int] = []
        var g = Group()
        for k in keys {
            if let t = toneOf(k) {
                if g.tone != nil { return nil }
                g.tone = t
                raws[3] = String(k)
                order.append(3)
            } else if let sym = Self.zhMap[k], let c = sym.first {
                let s = Self.slot(c)
                if !syms[s].isEmpty { return nil } // 同一個位置按了兩個鍵
                syms[s] = sym
                raws[s] = String(k)
                order.append(s)
            } else {
                return nil
            }
        }
        g.bpmf = syms.joined()
        g.raw = raws.joined()
        var a = 0
        while a < order.count {
            var b = a + 1
            while b < order.count {
                if order[a] > order[b] { g.disorder += 1 }
                b += 1
            }
            a += 1
        }
        return g
    }

    /// 每個字裡的按鍵可以不照順序（us3、s3u 都是 ㄋㄧˇ）。有多種拆法時取順序最不亂的
    private func parseZhAnyOrder(_ raw: String) -> [Seg]? {
        let keys = Array(raw)
        let n = keys.count
        guard n > 0, n <= 40 else { return nil }
        // cost[i]、size[i]：從第 i 個鍵到結尾的最佳拆法（亂序數、第一個字用掉幾個鍵）；-1 表示拆不出來
        var cost = [Int](repeating: -1, count: n + 1)
        var size = [Int](repeating: 0, count: n + 1)
        cost[n] = 0
        var i = n - 1
        while i >= 0 {
            var len = 1
            while len <= 4 && i + len <= n {
                if cost[i + len] >= 0, let g = arrange(keys[i..<(i + len)]) {
                    let ok: Bool
                    if let tone = g.tone {
                        ok = !g.bpmf.isEmpty && d.syllables.contains(g.bpmf + tone)
                    } else {
                        ok = i + len == n && d.prefixes.contains(g.bpmf) // 沒聲調的只能是最後還沒打完的那個字
                    }
                    if ok {
                        let c = cost[i + len] + g.disorder
                        if cost[i] < 0 || c < cost[i] { cost[i] = c; size[i] = len }
                    }
                }
                len += 1
            }
            i -= 1
        }
        guard cost[0] >= 0 else { return nil }
        var out: [Seg] = []
        var p = 0
        while p < n {
            let len = size[p]
            guard len > 0, let g = arrange(keys[p..<(p + len)]) else { return nil }
            if let tone = g.tone { out.append(mkZh(g.raw, g.bpmf + tone, done: true)) }
            else { out.append(mkZh(g.raw, g.bpmf)) }
            p += len
        }
        return out
    }

    /// 把相鄰兩個鍵對調後照順序解析（打太快最常見的錯）。從後面往前試，
    /// 優先採用「剛好拼成完整的字」的結果
    private func parseZhSwapped(_ raw: String) -> [Seg]? {
        var keys = Array(raw)
        var fallback: [Seg]? = nil
        var j = keys.count - 2
        while j >= 0 {
            if keys[j] != keys[j + 1] {
                keys.swapAt(j, j + 1)
                let p = parseZh(String(keys), allowLate: false)
                keys.swapAt(j, j + 1)
                if let p = p {
                    if p.last?.done ?? false { return p }
                    if fallback == nil { fallback = p }
                }
            }
            j -= 1
        }
        return fallback
    }

    /// 按鍵順序亂掉時依序嘗試：照順序 → 每個字裡不管順序 → 相鄰兩個鍵對調 → 聲調晚按
    private func parseZhLoose(_ raw: String) -> [Seg]? {
        if let p = parseZh(raw, allowLate: false) { return p }
        if let p = parseZhAnyOrder(raw) { return p }
        if let p = parseZhSwapped(raw) { return p }
        return parseZh(raw, allowLate: true)
    }

    /// 先被當成英文的一段，出現聲調鍵後如果能還原成注音，就改判回中文
    private func rejudge() {
        guard isOpenEn(last) else { return }
        let i = segs.count - 1
        let t = segs[i].text
        guard t.contains(where: { "3467".contains($0) }) else { return }
        guard !t.contains(where: { $0.isASCII && $0.isUppercase }) else { return }
        if isWordPrefix(t) { return }
        let digits = Self.isDigits(t)
        if !digits, var parsed = parseZhLoose(t) {
            // 只有一個字時記住原本的按鍵，按 Tab 可以改回英文（mp4 → 運 → mp4）
            if parsed.count == 1 && parsed[0].done { parsed[0].alt = t }
            segs.removeLast()
            segs.append(contentsOf: parsed)
            return
        }
        // 錯位可能跨到前一段：前一個已經打好的字（gj4i3 其實是 g4ji3），
        // 或是被當成英文字先斷開的那幾個鍵（us06 其實是 ㄋㄧㄢˊ）
        var p = i - 1
        if p >= 0 && segs[p].auto { p -= 1 }
        guard p >= 0 else { return }
        let prev = segs[p]
        var parsed: [Seg]? = nil
        if prev.t == .zh && prev.done && !digits && !prev.raw.isEmpty {
            // 已經打好的字只容許「相鄰兩鍵對調」這種小修正，免得把對的字改壞
            parsed = parseZhSwapped(prev.raw + t)
        } else if prev.t == .en && !prev.open && !prev.raw.isEmpty {
            parsed = parseZhLoose(prev.raw + t)
        }
        guard let fixed = parsed else { return }
        segs.removeSubrange(p...)
        segs.append(contentsOf: fixed)
    }

    /// 前一段是被當成英文字先斷開的按鍵（us），跟正在打的這個字合起來才是一個完整的注音
    /// （us＋ㄠˇ 其實是 ㄋㄧㄠˇ）。兩種讀法都成立時，取比較常用的那個字。回傳是否已經合併。
    private func mergeSplitWord(toneKey: Character) -> Bool {
        let i = segs.count - 1
        guard i >= 1, isPartial(segs[i]), let tone = toneOf(toneKey) else { return false }
        var p = i - 1
        if segs[p].auto { p -= 1 }
        guard p >= 0 else { return false }
        let prev = segs[p]
        guard prev.t == .en, !prev.open, !prev.raw.isEmpty else { return false }
        let keys = Array(prev.raw + segs[i].raw + String(toneKey))
        guard keys.count <= 4, let g = arrange(keys[...]), g.tone != nil else { return false }
        let merged = g.bpmf + tone
        guard d.syllables.contains(merged) else { return false }
        let alone = segs[i].bpmf + tone
        if d.syllables.contains(alone) && topScore(alone) > topScore(merged) { return false }
        segs.removeSubrange(p...)
        segs.append(mkZh(g.raw, merged, done: true))
        return true
    }

    /// 這個讀音最常用的字的分數
    private func topScore(_ reading: String) -> Double {
        var best = -Double.infinity
        for (_, sc) in d.dict[reading] ?? [] where sc > best { best = sc }
        return best
    }

    /// 一聲的字（空白結尾）按鍵順序亂了（ck 打成 kc），改回注音
    private func disorderedSyllable(_ text: String) -> Seg? {
        let keys = Array(text)
        guard keys.count >= 2, keys.count <= 3 else { return nil }
        guard !wordComplete(text), !inEnglishContext() else { return nil }
        guard let g = arrange(keys[...]), g.tone == nil, d.syllables.contains(g.bpmf) else { return nil }
        var s = mkZh(g.raw + " ", g.bpmf, done: true)
        s.alt = text + " " // 按 Tab 可以改回英文
        return s
    }

    private func symbol(_ ch: Character) {
        let c = String(ch)
        if isOpenEn(last) { segs[segs.count - 1].text += c; return }
        if isPartial(last) { segs[segs.count - 1] = mkEn(segs[segs.count - 1].raw + c); return }
        // 中文脈絡下 Shift+標點 → 全形；英文脈絡下保留半形
        if let p = Self.punct[ch], !lastIsEn { segs.append(mkLit(p)) }
        else { segs.append(mkEn(c)) }
    }

    private func space() -> Outcome {
        guard let s = last else { return .commit(" ") }
        let i = segs.count - 1
        if d.zhOnly && isPartial(s) {
            if d.syllables.contains(s.bpmf) { segs[i].done = true; segs[i].raw += " "; return .changed }
            return .noop
        }
        if isPartial(s) {
            if mergeSplitWord(toneKey: " ") { return .changed }
            let letters: String? = Self.isLowerLetters(s.raw) ? s.raw : nil
            let wordOK = letters.map { isWord($0) } ?? false
            let validZh = d.syllables.contains(s.bpmf)
            if wordOK && (inEnglishContext() || !validZh) {
                segs[i] = mkEn(displayCase(letters!) + " ", open: false)
            } else if validZh {
                segs[i].done = true
                segs[i].raw += " "
                if wordOK { segs[i].alt = displayCase(letters!) + " " } // 之後按 Tab 可改回英文
            } else {
                segs[i] = mkEn(s.raw + " ", open: false)
            }
        } else if isOpenEn(s) {
            if let fixed = disorderedSyllable(s.text) {
                segs[i] = fixed
            } else {
                segs[i].text = displayCase(s.text) + " "
                segs[i].open = false
            }
        } else if s.t == .zh || s.t == .fx {
            openCandidates()
            return .noop
        } else if s.auto {
            segs[i].auto = false // 自己又按了空白：這個空格就當成一般的空格
        } else {
            segs.append(mkEn(" ", open: false))
        }
        // 整段都是英文時，打完空白就直接送出，跟一般英文輸入一樣
        if segs.allSatisfy({ $0.t == .en || ($0.t == .lit && !Self.isCJK($0.text)) }) {
            let text = renderText()
            segs = []
            return .commit(text)
        }
        return .changed
    }

    private func tab() -> Outcome {
        let sug = suggestions()
        if !sug.isEmpty {
            segs[segs.count - 1] = mkEn(sug[min(sugSel, sug.count - 1)])
            return .changed
        }
        // 剛打好的字改回英文：有記下原本的英文就用它，否則還原成當初按的鍵（運 → mp4）
        if let s = last, s.t == .zh, s.done {
            let back = s.alt ?? s.raw
            if !back.isEmpty {
                segs[segs.count - 1] = mkEn(back, open: false)
                return .changed
            }
        }
        return .noop
    }

    /// 刪游標前面的一格：打好的中文整個字刪掉，拼到一半的注音一個符號一個符號刪，
    /// 自動補的空格也可以單獨刪掉
    @discardableResult
    func backspace() -> Bool {
        if cand != nil { cand = nil; return true }
        guard !segs.isEmpty else { return false }
        let i = segs.count - 1 - cursorBack
        guard i >= 0 else { return true }
        let s = segs[i]
        if s.auto {
            // 刪掉自動空格，並記住這個位置不要再補
            segs.remove(at: i)
            if i > 0 { segs[i - 1].noAutoSpace = true }
        } else if isPartial(s) {
            segs[i].bpmf = String(s.bpmf.dropLast())
            segs[i].raw = String(s.raw.dropLast())
            if segs[i].bpmf.isEmpty { segs.remove(at: i) }
        } else if s.t == .en {
            segs[i].text = String(s.text.dropLast())
            segs[i].raw = ""
            segs[i].open = i == segs.count - 1
            if segs[i].text.isEmpty { segs.remove(at: i) }
        } else if s.t == .fx && s.text.count > 1 {
            segs[i].text = String(s.text.dropLast())
            segs[i].key = s.key.split(separator: "-").dropLast().joined(separator: "-")
        } else {
            segs.remove(at: i)
        }
        normalizeSpaces()
        return true
    }

    /// ← → 在組字區裡移動游標（一次一個字或一個英文字），用來選前面的字
    func moveCursor(_ delta: Int) {
        guard cand == nil, !segs.isEmpty else { return }
        let i = segs.count - 1 - cursorBack // 游標前面那一段
        if i >= 0 {
            if isPartial(segs[i]) { return } // 注音拼到一半先不移動
            if segs[i].t == .en { segs[i].open = false }
        }
        cursorBack = min(segs.count, max(0, cursorBack - delta))
    }

    /// 畫面上看到什麼就送出什麼（還沒打聲調的注音會送出注音符號）
    func commitAll() -> String {
        while let s = segs.last, s.auto { segs.removeLast() } // 最後面沒有用到的自動空格不送出
        let t = renderText()
        reset()
        return t
    }

    // MARK: - 中英之間的自動空格

    private func isChinese(_ s: Seg) -> Bool {
        (s.t == .zh && s.done) || (s.t == .fx && Self.isCJK(s.text))
    }

    /// 含有英文字母的英文段（純數字、純符號不算）
    private func isEnglishWord(_ s: Seg) -> Bool {
        s.t == .en && s.text.contains(where: { $0.isASCII && $0.isLetter })
    }

    private func needsSpace(_ a: Seg, _ b: Seg) -> Bool {
        if isChinese(a) && isEnglishWord(b), let c = b.text.first { return Self.isAlnum(c) }
        if isEnglishWord(a) && isChinese(b), let c = a.text.last { return Self.isAlnum(c) }
        return false
    }

    /// 中文和英文相鄰時在中間放一個空格。空格自己是一段，所以可以用 Backspace 刪掉；
    /// 刪掉之後同一個位置不會再補。兩邊不再是「中文＋英文」時自動拿掉。
    private func normalizeSpaces() {
        var c = segs.count - cursorBack // 游標在第幾段之前
        var i = 0
        while i < segs.count {
            if segs[i].auto {
                let isLast = i == segs.count - 1
                // 留在最尾端的先保留（英文剛被刪光），讓使用者可以接著把空格刪掉
                let keep = d.autoSpace && i > 0 && (isLast || needsSpace(segs[i - 1], segs[i + 1]))
                if !keep {
                    segs.remove(at: i)
                    if i < c { c -= 1 }
                    continue
                }
            }
            i += 1
        }
        if d.autoSpace {
            i = 1
            while i < segs.count {
                let a = segs[i - 1], b = segs[i]
                if !a.auto && !b.auto && !a.noAutoSpace && needsSpace(a, b) {
                    segs.insert(mkAutoSpace(), at: i)
                    if i < c { c += 1 }
                    i += 1
                }
                i += 1
            }
        }
        cursorBack = max(0, min(segs.count, segs.count - c))
    }

    // MARK: - 選字

    /// 開選字窗：選游標前面的字（游標預設在最後面）
    func openCandidates() {
        var end = segs.count - cursorBack
        guard end > 0 else { return }
        if segs[end - 1].t == .fx {
            // 已經選過的詞：先還原成一個一個字，才能重新選
            let fx = segs[end - 1]
            var parts = fx.key.split(separator: "-").map { mkZh("", String($0), done: true) }
            guard !parts.isEmpty else { return }
            parts[parts.count - 1].noAutoSpace = fx.noAutoSpace
            segs.replaceSubrange((end - 1)..<end, with: parts)
            end += parts.count - 1
        }
        var start = end
        while start > 0 && segs[start - 1].t == .zh && segs[start - 1].done { start -= 1 }
        let readings = segs[start..<end].map { $0.bpmf }
        guard !readings.isEmpty else { return }
        var items: [CandItem] = []
        var seen = Set<String>()
        for len in stride(from: min(maxPhrase, readings.count), through: 1, by: -1) {
            let key = readings.suffix(len).joined(separator: "-")
            var list: [(String, Double)] = []
            for (p, sc) in d.dict[key] ?? [] { list.append((p, sc + (d.boost[p + "|" + key] ?? 0))) }
            list.sort { $0.1 > $1.1 }
            for (p, _) in list where !seen.contains(p) {
                seen.insert(p)
                items.append(CandItem(text: p, len: len, key: key))
            }
        }
        if !items.isEmpty { cand = CandState(items: items, sel: 0) }
    }

    func candKey(_ key: Key) {
        guard var c = cand else { return }
        let page = c.sel / 9
        switch key {
        case .char(let ch) where ch >= "1" && ch <= "9":
            let idx = page * 9 + Int(String(ch))! - 1
            if idx < c.items.count { pickCandidate(idx) }
            return
        case .space, .right, .pageDown: c.sel = min(c.items.count - 1, (page + 1) * 9)
        case .left, .pageUp: c.sel = max(0, (page - 1) * 9)
        case .down: c.sel = min(c.items.count - 1, c.sel + 1)
        case .up: c.sel = max(0, c.sel - 1)
        case .enter: pickCandidate(c.sel); return
        case .escape, .backspace: cand = nil; return
        default: return
        }
        cand = c
    }

    private func pickCandidate(_ idx: Int) {
        guard let c = cand, idx < c.items.count else { return }
        let it = c.items[idx]
        let end = segs.count - cursorBack
        guard it.len <= end else { cand = nil; return }
        let removed = Array(segs[(end - it.len)..<end])
        var s = Seg(t: .fx)
        s.text = it.text
        s.key = it.key
        s.raw = removed.map { $0.raw }.joined()
        s.noAutoSpace = removed.last?.noAutoSpace ?? false
        segs.replaceSubrange((end - it.len)..<end, with: [s])
        let bk = it.text + "|" + it.key
        d.boost[bk] = min((d.boost[bk] ?? 0) + 3, 12) // 學習使用者的選字
        d.saveBoost()
        cand = nil
        cursorBack = 0 // 選完前面的字，游標回到最後面繼續打
        normalizeSpaces()
    }

    // MARK: - 轉換

    private func convert(_ readings: [String]) -> String {
        let n = readings.count
        guard n > 0 else { return "" }
        var best = [Double](repeating: -Double.infinity, count: n + 1)
        var back = [(Int, String)?](repeating: nil, count: n + 1)
        best[0] = 0
        for i in 1...n {
            for len in 1...min(maxPhrase, i) {
                let key = readings[(i - len)..<i].joined(separator: "-")
                guard let list = d.dict[key] else { continue }
                var top = "", topScore = -Double.infinity
                for (p, sc) in list.prefix(20) {
                    let v = sc + (d.boost[p + "|" + key] ?? 0)
                    if v > topScore { topScore = v; top = p }
                }
                let v = best[i - len] + topScore
                if v > best[i] { best[i] = v; back[i] = (i - len, top) }
            }
            if back[i] == nil {
                best[i] = best[i - 1] - 30
                back[i] = (i - 1, readings[i - 1])
            }
        }
        var out: [String] = []
        var i = n
        while i > 0, let b = back[i] {
            out.insert(b.1, at: 0)
            i = b.0
        }
        return out.joined()
    }

    func pieces() -> [Piece] {
        var res: [Piece] = []
        var run: [String] = []
        for s in segs {
            if s.t == .zh && s.done { run.append(s.bpmf); continue }
            if !run.isEmpty { res.append(Piece(text: convert(run), kind: .zh)); run = [] }
            switch s.t {
            case .zh: res.append(Piece(text: s.bpmf, kind: .partial))
            case .en: res.append(Piece(text: s.text, kind: .en))
            case .fx: res.append(Piece(text: s.text, kind: .fx))
            case .lit: res.append(Piece(text: s.text, kind: .lit))
            }
        }
        if !run.isEmpty { res.append(Piece(text: convert(run), kind: .zh)) }
        return res
    }

    func renderText() -> String {
        pieces().map { $0.text }.joined()
    }

    /// 游標前面的文字長度（UTF-16），給 macOS 畫游標用
    func cursorOffset() -> Int {
        var remain = segs.count - cursorBack
        var prefix = ""
        var run: [String] = []
        for s in segs + [mkLit("")] { // 最後多放一段空的，讓結尾的中文也會結算
            if s.t == .zh && s.done { run.append(s.bpmf); continue }
            if !run.isEmpty {
                let text = convert(run)
                if run.count <= remain { prefix += text } else { prefix += String(text.prefix(max(0, remain))) }
                remain -= run.count
                run = []
            }
            if remain <= 0 { break }
            prefix += (s.t == .zh ? s.bpmf : s.text)
            remain -= 1
        }
        return prefix.utf16.count
    }
}
