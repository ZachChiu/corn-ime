import Foundation
import os

/// 寫到系統紀錄，「主控台」或 ./diag.sh 看得到（標成 public，不然內容會被系統遮成 <private>）
func imeLog(_ message: String) {
    os_log("%{public}@", type: .default, "CornIME: " + message)
}

/// 詞庫與使用者設定。所有輸入視窗共用同一份。
final class CornData {
    static let shared = CornData(
        zhPath: Bundle.main.path(forResource: "zh", ofType: "tsv"),
        enPath: Bundle.main.path(forResource: "en", ofType: "tsv"),
        persist: true
    )

    /// 注音讀音（多字用 - 連接）→ [(詞, 分數)]，分數由高到低
    var dict: [String: [(String, Double)]] = [:]
    /// 合法的完整音節（含聲調）
    var syllables = Set<String>()
    /// 合法的音節開頭（不含聲調），用來判斷「還拼得下去嗎」
    var prefixes = Set<String>()

    /// 小寫英文字 → (顯示用的大小寫, log10 字頻)
    var en: [String: (String, Double)] = [:]
    var enKeys: [String] = []
    var enPrefix = Set<String>()

    /// 使用者選字學習：「詞|讀音」→ 加分
    var boost: [String: Double]
    /// 只打注音：不自動判斷英文
    var zhOnly = false {
        didSet { if persist { UserDefaults.standard.set(zhOnly, forKey: "zhOnlyOn") } }
    }
    /// 英文模式：輕按 Shift 切換，開著時按鍵全部直接交給 App
    var enMode = false
    var autoSpace: Bool {
        didSet { if persist { UserDefaults.standard.set(autoSpace, forKey: "autoSpaceOn") } }
    }
    /// 梗圖庫：關鍵字 → 梗圖代號。由 App 填入，選字時用讀音比對
    var memes: [(keyword: String, id: String)] = []
    /// 每個字有哪些讀音，用來比對梗圖關鍵字（同音字也算符合）
    var charReadings: [Character: Set<String>] = [:]
    private let persist: Bool

    init(zhPath: String?, enPath: String?, persist: Bool) {
        self.persist = persist
        if persist {
            boost = (UserDefaults.standard.dictionary(forKey: "boost") as? [String: Double]) ?? [:]
            autoSpace = (UserDefaults.standard.object(forKey: "autoSpaceOn") as? Bool) ?? true // 預設開啟
            zhOnly = UserDefaults.standard.bool(forKey: "zhOnlyOn")
            // 專案改名前叫 ZingIME：第一次啟動時把當時學到的選字搬過來
            if boost.isEmpty,
               let old = UserDefaults.standard.persistentDomain(forName: "com.zingime.inputmethod.ZingIME"),
               let oldBoost = old["boost"] as? [String: Double] {
                boost = oldBoost
                UserDefaults.standard.set(oldBoost, forKey: "boost")
            }
        } else {
            boost = [:]
            autoSpace = false
        }

        if let p = zhPath, let s = try? String(contentsOfFile: p, encoding: .utf8) {
            for line in s.split(separator: "\n") {
                let f = line.split(separator: "\t")
                guard f.count == 3, let score = Double(f[2]) else { continue }
                dict[String(f[0]), default: []].append((String(f[1]), score))
                if f[1].count == 1, let ch = f[1].first { charReadings[ch, default: []].insert(String(f[0])) }
            }
        } else {
            NSLog("CornIME: 找不到注音詞庫 zh.tsv")
        }
        for reading in dict.keys where !reading.contains("-") {
            syllables.insert(reading)
            let base = Array(reading.filter { !"ˊˇˋ˙".contains($0) })
            guard !base.isEmpty else { continue }
            for i in 1...base.count { prefixes.insert(String(base[0..<i])) }
        }

        if let p = enPath, let s = try? String(contentsOfFile: p, encoding: .utf8) {
            for line in s.split(separator: "\n") {
                let f = line.split(separator: "\t")
                guard f.count == 3, let freq = Double(f[2]) else { continue }
                en[String(f[0])] = (String(f[1]), freq)
            }
        } else {
            NSLog("CornIME: 找不到英文字典 en.tsv")
        }
        enKeys = en.keys.sorted()
        for k in enKeys {
            var cur = ""
            for c in k {
                cur.append(c)
                enPrefix.insert(cur)
            }
        }
    }

    func saveBoost() {
        if persist { UserDefaults.standard.set(boost, forKey: "boost") }
    }
}
