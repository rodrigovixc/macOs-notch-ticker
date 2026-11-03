#!/bin/sh
# Compila e monta "StockNotch.app" nesta pasta.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="StockNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/StockNotch "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>StockNotch</string>
    <key>CFBundleIdentifier</key><string>io.github.rodrigovixc.stocknotch</string>
    <key>CFBundleName</key><string>StockNotch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <!-- App em português: datas e textos do sistema (menus, botões) saem em pt-BR. -->
    <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
    <key>CFBundleLocalizations</key><array><string>pt-BR</string></array>
</dict>
</plist>
EOF
# Assinatura local (ad-hoc): roda neste Mac; para outros Macs precisa da conta Apple Developer.
codesign --force --sign - "$APP"
echo "Pronto: $APP"
