#!/bin/bash
# 打不出字時跑這個：把最近 5 分鐘的狀況存成 diag.txt
cd "$(dirname "$0")"
{
  echo "== 時間"; date
  echo "== macOS"; sw_vers -productVersion
  echo "== open 的錯誤訊息"; cat build/open-error.txt 2>/dev/null
  echo "== 程式有沒有在跑"; pgrep -lx CornIME || echo "沒有在跑"
  echo "== 安裝的版本"; ls -la "$HOME/Library/Input Methods/CornIME.app/Contents/MacOS"
  echo "== 登記時的訊息"; cat build/register.txt 2>/dev/null
  echo "== 已加入清單的輸入法"; defaults read com.apple.HIToolbox AppleEnabledInputSources
  echo "== 系統眼中的輸入法"; "$HOME/Library/Input Methods/CornIME.app/Contents/MacOS/CornIME" --list 2>&1
  echo "== com.apple.inputsources"; defaults read com.apple.inputsources 2>&1
  echo "== 輸入法資料夾"; ls -la "$HOME/Library/Input Methods"
  echo "== 目前選的輸入法"; defaults read com.apple.HIToolbox AppleSelectedInputSources
  echo "== 當機報告"; ls -t "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -i cornime | head -3
  f=$(ls -t "$HOME/Library/Logs/DiagnosticReports/"*CornIME* 2>/dev/null | head -1)
  if [ -n "$f" ]; then cp "$f" crash.txt; echo "已複製最新的當機報告到 crash.txt"; fi
  echo "== 最近 30 分鐘內所有 App 的當機報告"
  n=0
  find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -type f -mmin -30 2>/dev/null | while read -r r; do
    n=$((n + 1)); echo "$r"
    cp "$r" "crash-$n.txt" 2>/dev/null
  done
  echo "== CornIME 的紀錄"
  log show --last 5m --style compact --predicate 'process == "CornIME" OR eventMessage CONTAINS[c] "cornime"' | tail -150
  echo "== 系統輸入法元件的紀錄"
  log show --last 5m --style compact --predicate 'subsystem CONTAINS[c] "inputmethod" OR senderImagePath CONTAINS[c] "InputMethodKit"' | tail -60
} > diag.txt 2>&1
echo "完成，已存成 diag.txt"
