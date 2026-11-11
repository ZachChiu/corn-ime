import Foundation

// 引擎的命令列測試：./test.sh
let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let data = CornData(zhPath: dir + "/zh.tsv", enPath: dir + "/en.tsv", persist: false)
var failed = 0

/// ␣ = 空白、⇥ = Tab、⇤ = Shift+Tab、⌫ = Backspace、← → = 移動游標、↓ = 開選字窗
func check(_ keys: String, _ expected: String, autoSpace: Bool = false) {
    data.autoSpace = autoSpace
    data.boost = [:]
    let e = CornEngine(data: data)
    var out = ""
    for ch in keys {
        switch ch {
        case "⌫": e.backspace()
        case "←": e.moveCursor(-1)
        case "→": e.moveCursor(1)
        case "↓":
            if e.suggestions().isEmpty { e.openCandidates() }
        default:
            let k: Key
            switch ch {
            case " ", "␣": k = .space
            case "⇥": k = .tab
            case "⇤": k = .shiftTab
            default: k = .char(ch)
            }
            if let c = e.press(k) { out += c }
        }
    }
    out += e.renderText()
    let ok = out == expected
    if !ok { failed += 1 }
    print(ok ? "✓" : "✗", keys.padding(toLength: 28, withPad: " ", startingAt: 0), "→", out, ok ? "" : "（預期：\(expected)）")
}

print("— 基本")
check("ji3rup wu0 ul4meeting", "我今天要meeting")
check("hello world ", "hello world ")
check("ji3m/4chatgptvu,3code", "我用ChatGPT寫code")
check("up ", "因")
check("up ⇥", "up ")
check("2026su06", "2026年")
check("I am fine ", "I am fine ")
check("5k4ek7app2k7UIcp3cl3d04", "這個app的UI很好看")
check("meet⇥", "meeting")
check("su3cl3", "你好")
check("vul⇤", "ㄒㄧㄠ")
check("1qaz⇤", "ㄅㄆㄇㄈ")
check("rup wu0 2k7deadline", "今天的deadline")
check("isji3", "is我")

print("— 打太快、按鍵順序亂掉")
check("suc3l3", "你好")   // 聲調比下一個字的第一個鍵晚按
check("us3cl3", "你好")   // 前兩個鍵按反
check("s3ucl3", "你好")   // 聲調按太早
check("su3lc3", "你好")
check("su3c3l", "你好")
check("gj4i3", "是我")    // 錯位跨到前一個字
check("j3isu3", "我你")
check("jiu3l4", "我要")
check("slu3", "鳥")
check("lus3", "鳥")
check("usl3", "鳥")       // 前兩個鍵剛好是英文字 us
check("us06", "年")
check("uv;3", "想")
check("ji38w ", "我他")   // 一聲（空白結尾）的字
check("us ", "us ")       // 真的英文字不受影響
check("mp4⇥", "mp4")      // Tab：剛打好的字改回英文
check("su3⇥⇤", "你")      // Shift+Tab：再改回注音

print("— 中英之間自動空格")
check("ji3m/4chatgptvu,3code", "我用 ChatGPT 寫 code", autoSpace: true)
check("5k4ek7app2k7UIcp3cl3d04", "這個 app 的 UI 很好看", autoSpace: true)
check("2026su06", "2026年", autoSpace: true)
check("ji3A", "我 A", autoSpace: true)
check("ji3A⌫", "我 ", autoSpace: true)
check("ji3A⌫⌫", "我", autoSpace: true)      // 空格可以單獨刪掉
check("ji3A⌫⌫A", "我A", autoSpace: true)    // 刪掉後不會再補
check("ji3A⌫su3", "我你", autoSpace: true)
check("appji3⌫⌫ji3", "app我", autoSpace: true)
check("hello su3", "hello 你", autoSpace: true)

print("— 選前面的字")
check("su3cl3←↓2", "妳好")
check("su3cl3←↓2ji3", "妳好我")
check("su3cl3← 2", "妳好")
check("su3cl3←⌫", "好")
check("su3cl3↓1", "你好")

print(failed == 0 ? "\n全部通過" : "\n\(failed) 項失敗")
exit(failed == 0 ? 0 : 1)
