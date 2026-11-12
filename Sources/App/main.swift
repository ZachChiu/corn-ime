import Carbon
import Cocoa
import InputMethodKit

let bundleID = Bundle.main.bundleIdentifier ?? "com.cornime.inputmethod.CornIME"
let oldBundleID = "com.zingime.inputmethod.ZingIME" // 專案改名前的舊版

/// 讀輸入法的一項屬性，轉成文字
func tisText(_ source: TISInputSource, _ key: CFString) -> String {
    guard let raw = TISGetInputSourceProperty(source, key) else { return "（無）" }
    return "\(Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue())"
}

/// 列出系統眼中的輸入法：已啟用的全部，加上跟我們有關的。除錯用
func printInputSources() {
    guard let all = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
        print("  讀不到系統的輸入法清單")
        return
    }
    for source in all {
        let id = tisText(source, kTISPropertyInputSourceID)
        let enabled = tisText(source, kTISPropertyInputSourceIsEnabled)
        let lower = (id + tisText(source, kTISPropertyBundleID)).lowercased()
        guard lower.contains("cornime") || lower.contains("zingime") || enabled == "1" else { continue }
        print("  \(id)｜名稱=\(tisText(source, kTISPropertyLocalizedName))｜已啟用=\(enabled)｜圖示=\(tisText(source, kTISPropertyIconImageURL))")
    }
}

/// 把指定的輸入法從系統設定檔的清單裡拿掉。程式已經刪掉、清單裡只剩空殼（沒有名稱的那一列）時用。
/// 第三方輸入法除了 com.apple.HIToolbox，還會記在 com.apple.inputsources，兩邊都要清。
func scrubInputSourcePrefs(_ ids: [String]) {
    func isOurs(_ text: String) -> Bool {
        for id in ids where text.hasPrefix(id) { return true }
        return false
    }
    for name in ["com.apple.HIToolbox", "com.apple.inputsources"] {
        let domain = name as CFString
        let keys = (CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]) ?? []
        for key in keys {
            let value = CFPreferencesCopyAppValue(key as CFString, domain)
            if let list = value as? [[String: Any]] {
                let kept = list.filter { entry in
                    for v in entry.values {
                        if let text = v as? String, isOurs(text) { return false }
                    }
                    return true
                }
                if kept.count != list.count {
                    CFPreferencesSetAppValue(key as CFString, kept as CFPropertyList, domain)
                    print("從 \(name) 的 \(key) 移除 \(list.count - kept.count) 筆")
                }
            } else if let list = value as? [String] {
                let kept = list.filter { !isOurs($0) }
                if kept.count != list.count {
                    CFPreferencesSetAppValue(key as CFString, kept as CFPropertyList, domain)
                    print("從 \(name) 的 \(key) 移除 \(list.count - kept.count) 筆")
                }
            }
        }
        if !CFPreferencesAppSynchronize(domain) { print("✗ \(name) 寫入失敗：這個設定檔目前的執行環境沒有寫入權限") }
    }
}

// ./diag.sh 用：看系統到底登記了哪些輸入法
if CommandLine.arguments.contains("--list") {
    printInputSources()
    exit(0)
}

// ./build.sh 安裝完會用 --register 執行一次，把輸入法登記到系統並啟用
if CommandLine.arguments.contains("--register") {
    // 改名前的舊版（ZingIME）：先把設定檔裡的空殼清掉（要在碰系統的輸入法清單之前做），再停用
    scrubInputSourcePrefs([oldBundleID])
    let oldProps = [kTISPropertyBundleID as String: oldBundleID] as CFDictionary
    if let old = TISCreateInputSourceList(oldProps, true)?.takeRetainedValue() as? [TISInputSource] {
        for source in old { _ = TISDisableInputSource(source) }
    }

    let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    print("登記輸入法：\(status == 0 ? "成功" : "錯誤碼 \(status)")")
    // 剛登記完系統可能還沒準備好：等一下再啟用，最多試 10 次
    let props = [kTISPropertyBundleID as String: bundleID] as CFDictionary
    var enabledOK = false
    for _ in 0..<10 {
        if let list = TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource] {
            for source in list where TISEnableInputSource(source) == 0 { enabledOK = true }
        }
        if enabledOK { break }
        Thread.sleep(forTimeInterval: 0.3)
    }
    print("啟用輸入法：\(enabledOK ? "成功" : "失敗")")
    // 新版 macOS 的啟用要由系統設定跳出詢問、使用者按同意才生效（小麥注音安裝程式的做法：停留 60 秒）。
    // 這個程式要留著等，太早結束詢問不會完成。
    func isEnabled() -> Bool {
        guard let list = TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource] else { return false }
        return list.contains { tisText($0, kTISPropertyInputSourceIsEnabled) == "1" }
    }
    if !isEnabled() { print("等待系統詢問是否啟用「玉米輸入法」：請在跳出的視窗按同意（最多等 60 秒）") }
    for _ in 0..<60 where !isEnabled() { RunLoop.current.run(until: Date().addingTimeInterval(1)) }
    print("啟用狀態：\(isEnabled() ? "已啟用" : "未啟用。請到 系統設定 → 鍵盤 → 輸入方式 手動加入")")
    print("系統目前看到的輸入法：")
    printInputSources()
    exit(0)
}

// 連線名稱要用「名稱_1_Connection」這種慣用格式：LINE、Teams 這類有沙箱限制的 App 才連得上輸入法
let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String ?? "CornIME_1_Connection"
imeLog("啟動，連線名稱 \(connectionName)")
// 先開 IMKServer，系統才連得上；詞庫接著載入
let server = IMKServer(name: connectionName, bundleIdentifier: bundleID)
imeLog(server == nil ? "無法啟動 IMKServer" : "IMKServer 已啟動")
let cornData = CornData.shared
_ = MemeStore.shared // 載入梗圖庫，把關鍵字交給引擎
imeLog("詞庫載入完成：注音 \(cornData.dict.count) 筆、英文 \(cornData.en.count) 筆；自動空格\(cornData.autoSpace ? "開" : "關")")
NSApplication.shared.run()
