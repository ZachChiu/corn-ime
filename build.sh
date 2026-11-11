#!/bin/bash
# 編譯、安裝並登記「玉米輸入法」（CornIME）
# 用法：./build.sh            編譯並安裝
#       ./build.sh --no-install  只編譯，不安裝
set -euo pipefail
cd "$(dirname "$0")"

NAME="CornIME"
APP="build/$NAME.app"
DEST="$HOME/Library/Input Methods"

echo "▸ 編譯中…"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# 一定要指定最低系統版本，不然 swiftc 可能標成比目前系統還新的版本，macOS 會拒絕啟動
swiftc -O -module-name "$NAME" -target "$(uname -m)-apple-macos12.0" \
  Sources/Engine/*.swift Sources/App/*.swift \
  -framework Cocoa -framework InputMethodKit -framework Carbon \
  -o "$APP/Contents/MacOS/$NAME"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/zh.tsv Resources/en.tsv Resources/tuxedo.tiff "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"   # 各語系的名稱（系統設定的選單用）
xattr -cr "$APP"   # 清掉下載來的隔離標記
# SIGN_ID 可指定鑰匙圈裡的簽章憑證（security find-identity -v -p codesigning）；沒指定就用 ad hoc
codesign --force --sign "${SIGN_ID:--}" "$APP" >/dev/null
echo "▸ 已產生 $APP"

if [[ "${1:-}" == "--no-install" ]]; then exit 0; fi

echo "▸ 安裝到 $DEST"
mkdir -p "$DEST"
pkill -x "$NAME" 2>/dev/null || true
rm -rf "$DEST/$NAME.app"
cp -R "$APP" "$DEST/"

echo "▸ 啟動輸入法…"
open -g "$DEST/$NAME.app" 2> build/open-error.txt || true
sleep 3
# --register 會等使用者在系統詢問視窗按同意（最多 60 秒）
"$DEST/$NAME.app/Contents/MacOS/$NAME" --register 2>&1 | tee build/register.txt

# 專案改名前叫 ZingIME：把舊版移掉。只刪我們自己做的那一個，不會動到同名的其他輸入法
OLD="$DEST/ZingIME.app"
if [[ -d "$OLD" ]]; then
  OLD_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OLD/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$OLD_ID" == "com.zingime.inputmethod.ZingIME" ]]; then
    pkill -x ZingIME 2>/dev/null || true
    rm -rf "$OLD"
    echo "▸ 已移除改名前的舊版（ZingIME）"
  fi
fi

# 讓選單列重新讀取輸入法圖示（這個系統小程式會自己重新啟動）
killall TextInputMenuAgent 2>/dev/null || true

if pgrep -x "$NAME" >/dev/null; then
  echo "✓ 安裝完成。切到「玉米輸入法」就可以打字"
  echo "  已經開著的 App 要重開，才會看到新的輸入法和圖示"
else
  echo "✗ 輸入法程式沒有啟動成功：請執行 ./diag.sh，把狀況存成 diag.txt"
fi
