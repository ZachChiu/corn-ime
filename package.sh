#!/bin/bash
# 產生給別人安裝的 dist/CornIME-<版本>.pkg（Intel 與 Apple Silicon 通用）
# 安裝位置：/Library/Input Methods（整台電腦共用，安裝時要輸入管理者密碼）
set -euo pipefail
cd "$(dirname "$0")"

NAME="CornIME"
APP="build/$NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"

./build.sh --no-install

echo "▸ 編譯通用版本（arm64 + x86_64）…"
for arch in arm64 x86_64; do
  swiftc -O -module-name "$NAME" -target "$arch-apple-macos12.0" \
    Sources/Engine/*.swift Sources/App/*.swift \
    -framework Cocoa -framework InputMethodKit -framework Carbon \
    -o "build/$NAME-$arch"
done
lipo -create "build/$NAME-arm64" "build/$NAME-x86_64" -output "$APP/Contents/MacOS/$NAME"
codesign --force --sign "${SIGN_ID:--}" "$APP" >/dev/null

echo "▸ 打包…"
ROOT="build/pkgroot"
SCRIPTS="build/pkgscripts"
mkdir -p "$ROOT" "$SCRIPTS" dist
cp -R "$APP" "$ROOT/"

# 安裝完：用目前登入的使用者身分啟動輸入法並登記（安裝程式本身是 root）
cat > "$SCRIPTS/postinstall" <<'EOF'
#!/bin/bash
APP="/Library/Input Methods/CornIME.app"
U="$(stat -f%Su /dev/console)"
ID="$(id -u "$U")"
pkill -x CornIME 2>/dev/null || true
launchctl asuser "$ID" sudo -u "$U" open -g "$APP" || true
sleep 3
# --register 會等使用者在系統詢問視窗按同意（最多 60 秒）
launchctl asuser "$ID" sudo -u "$U" "$APP/Contents/MacOS/CornIME" --register || true
exit 0
EOF
chmod +x "$SCRIPTS/postinstall"

# 關掉「可搬移」：不關的話，電腦上其他位置有同一個 App 時，安裝程式會改裝到那裡
pkgbuild --analyze --root "$ROOT" build/component.plist >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO build/component.plist

OUT="dist/$NAME-$VERSION.pkg"
pkgbuild --root "$ROOT" --component-plist build/component.plist --scripts "$SCRIPTS" \
  --identifier "com.cornime.inputmethod.pkg" --version "$VERSION" \
  --install-location "/Library/Input Methods" "$OUT" >/dev/null
echo "✓ 已產生 $OUT"

# 給 pkg 檔本身套上專案圖示。圖示存在檔案的延伸屬性裡，直接傳 pkg 會掉，所以另外壓一份 zip 保留它
swift -e 'import AppKit
let a = CommandLine.arguments
exit(NSWorkspace.shared.setIcon(NSImage(contentsOfFile: a[1]), forFile: a[2]) ? 0 : 1)' Resources/AppIcon.icns "$OUT"
ditto -c -k --sequesterRsrc "$OUT" "${OUT%.pkg}.zip"
echo "✓ 已產生 ${OUT%.pkg}.zip（傳給別人用這個，圖示才會保留）"
