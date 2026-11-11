#!/bin/bash
# 把玉米輸入法（CornIME）和改名前的 ZingIME 從系統裡清乾淨，不用登出。
# 用法：./uninstall.sh          清掉程式、系統清單裡的登記和快取（保留學到的選字）
#       ./uninstall.sh --all    連學到的選字和設定也刪掉
# 清完想重裝：./build.sh
set -uo pipefail
cd "$(dirname "$0")"
DEST="$HOME/Library/Input Methods"

# 舊名字 ZingIME 跟另一個輸入法同名：只處理我們自己做的那一個
OLD="$DEST/ZingIME.app"
OLD_IS_OURS=no
if [[ -d "$OLD" ]]; then
  OLD_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OLD/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$OLD_ID" == "com.zingime.inputmethod.ZingIME" ]] && OLD_IS_OURS=yes
fi

echo "▸ 從系統的輸入法清單移除"
mkdir -p build
if swiftc -O -target "$(uname -m)-apple-macos12.0" Tools/cleanup.swift -framework Carbon -o build/cleanup; then
  ./build/cleanup
else
  echo "✗ 清理工具編譯失敗，請把上面的錯誤訊息貼給 Claude"
  exit 1
fi

echo "▸ 停掉輸入法程式並刪除"
pkill -x CornIME 2>/dev/null
rm -rf "$DEST/CornIME.app"
if [[ "$OLD_IS_OURS" == yes ]]; then
  pkill -x ZingIME 2>/dev/null
  rm -rf "$OLD"
fi

echo "▸ 清掉系統的輸入法快取（系統會自己重建）"
CACHE="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)"
[[ -n "$CACHE" ]] && rm -f "$CACHE"com.apple.IntlDataCache.le*
rm -f "$HOME/Library/Caches/"com.apple.IntlDataCache.le* 2>/dev/null

echo "▸ 重新啟動系統設定和選單列的輸入法選單"
killall "System Settings" 2>/dev/null
killall TextInputMenuAgent 2>/dev/null
killall TextInputSwitcher 2>/dev/null

if [[ "${1:-}" == "--all" ]]; then
  echo "▸ 刪除學到的選字和設定"
  defaults delete com.cornime.inputmethod.CornIME 2>/dev/null
  defaults delete com.zingime.inputmethod.ZingIME 2>/dev/null
fi

echo
echo "✓ 清理完成。目前系統清單裡的輸入法："
defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -E '"Bundle ID"|"KeyboardLayout Name"|"Input Mode"' | sed 's/^ */  /'
echo "  要重新安裝請執行 ./build.sh"
