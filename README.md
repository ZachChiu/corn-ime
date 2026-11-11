# 玉米輸入法（CornIME）

> 這個專案原本叫 ZingIME。`./build.sh` 會自動移除舊版，並沿用當時學到的選字。

用注音打字，遇到英文直接打，不用切換輸入法。全部用 Swift 寫，不需要 Xcode 專案，用終端機的 `swiftc` 編譯。

## 安裝

```bash
cd corn-ime
./test.sh     # 先測試判斷邏輯，應該顯示「全部通過」
./build.sh    # 編譯並安裝到 ~/Library/Input Methods
```

`./build.sh` 會自動把「玉米輸入法」加到輸入法清單，跑完切過去就能打字，不用登出。更新時重跑 `./build.sh` 即可。

圖示是 `Resources/tuxedo.tiff`（32×32 彩色，由 `Resources/icon-source.png` 裁切縮小而來）。`Resources/cat.tiff` 是沒在用的像素風黑白版，想換回去時把 Info.plist 和 build.sh 裡的檔名改掉即可。換圖示後，已經開著的 App 要重開才會顯示新的。

## 按鍵

| 按鍵 | 作用 |
| --- | --- |
| 注音鍵 | 標準大千鍵盤，聲調用 空白 6 3 4 7 |
| 英文字母 | 拼不成注音時自動變英文 |
| Tab | 接受英文建議；剛打好的中文字改回英文（例如 因 → up、運 → mp4） |
| ↑ ↓ | 切換英文建議；沒有建議時 ↓ 開中文選字 |
| 空白 | 中文打完後再按一次開選字窗，數字鍵選字 |
| ← → | 在還沒送出的字之間移動游標，再按 ↓ 或空白選游標前面的字 |
| Backspace | 刪游標前面的一格；中英之間自動補的空格也可以單獨刪掉，刪掉後不會再補 |
| 輕按 Shift | 切換中文（中英混打）和英文模式 |
| Shift+Tab | 被誤判成英文的這段強制改回注音；拼不成字就打出注音符號本身 |
| Enter | 照畫面上的樣子送出（還沒打聲調的注音會送出注音符號，例如ㄒㄧㄠ） |
| Esc | 取消組字 |

選單列的輸入法選單裡可以開關「英文模式」、「只打注音」和「中英之間自動空格」（預設開啟）。選過的字會記住，下次優先出現。

自動空格也會看游標前面已經送出的字：前面是中文、接著打英文（包括用 Shift 切到英文模式打的），會先補一個空格；反過來也一樣。把那個空格刪掉後再打，就不會再補。少數 App（例如終端機）不提供游標前面的文字，這時只認得輸入法自己剛送出的字。

打太快時一個字裡的按鍵順序不用完全正確：`us3`、`s3u` 都會變成「你」。

## 程式結構

- `Sources/Engine/CornEngine.swift`：中英判斷、注音解析、打太快的錯位修正、選字，只用 Foundation
- `Sources/Engine/CornData.swift`：載入詞庫、使用者學習與設定
- `Sources/App/CornInputController.swift`：接 macOS 的 InputMethodKit，處理按鍵和組字區
- `Sources/App/CandidatePanel.swift`：游標下方的選字／建議小視窗
- `Sources/App/main.swift`：啟動輸入法伺服器；`--register` 用來登記到系統
- `Tests/main.swift`：引擎的命令列測試

## 疑難排解

- **某些 App（LINE、Teams）切不過去或只能打英文**：這類 App 有沙箱限制，Info.plist 的 `InputMethodConnectionName` 要維持 `名稱_1_Connection` 的格式。
- **打不出字**：在這個資料夾執行 `./diag.sh`，會把最近的系統紀錄存成 `diag.txt`。先在新開的 App 裡試，安裝前就開著的 App 可能要重開。
- **切過去完全打不出字**：打開「主控台」搜尋 `CornIME`，看到 `requires conditional` 代表編譯時沒指定最低系統版本（build.sh 的 `-target`）。
- **改了程式沒反應**：`pkill CornIME`，再切換一次輸入法。
- **看執行紀錄**：打開「主控台」App，搜尋 `CornIME`。
- **移除／清乾淨重裝**：執行 `./uninstall.sh`，會刪掉程式、把它從系統的輸入法清單和快取裡清掉，不用登出。加 `--all` 連學到的選字也刪。要重裝再跑 `./build.sh`。
