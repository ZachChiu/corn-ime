import Carbon
import Foundation

// 把玉米輸入法（CornIME）和改名前的 ZingIME 從系統的輸入法清單裡移除。由 ./uninstall.sh 呼叫。
let ids = ["com.cornime.inputmethod.CornIME", "com.zingime.inputmethod.ZingIME"]

func isOurs(_ text: String) -> Bool {
    for id in ids where text.hasPrefix(id) { return true }
    return false
}

/// 從系統設定檔的清單裡拿掉。第三方輸入法除了 com.apple.HIToolbox，還會記在 com.apple.inputsources
func scrubPrefs() {
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

// 1. 先清設定檔（要在碰系統的輸入法清單之前做，免得舊資料又被寫回去）
scrubPrefs()

// 2. 程式還在的話，用系統的方式停用
for id in ids {
    let props = [kTISPropertyBundleID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource] else { continue }
    for source in list {
        let status = TISDisableInputSource(source)
        print("停用 \(id)：\(status == 0 ? "成功" : "錯誤碼 \(status)")")
    }
}
Thread.sleep(forTimeInterval: 0.5)

// 3. 再清一次，確定沒有殘留，然後通知其他 App 輸入法清單變了
scrubPrefs()
DistributedNotificationCenter.default().post(
    name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil)
print("系統的輸入法清單已清理")
