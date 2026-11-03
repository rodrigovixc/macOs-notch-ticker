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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <!-- Português ou inglês, escolhido nos Ajustes: o app grava AppleLanguages e os menus do sistema
         seguem no próximo início. Sem as duas línguas aqui, o macOS ignoraria a escolha. -->
    <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
    <key>CFBundleLocalizations</key><array><string>pt-BR</string><string>en</string></array>
</dict>
</plist>
EOF

# Ícone: gera o .icns em todos os tamanhos a partir de Assets/AppIcon.png (1024×1024).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET" "$APP/Contents/Resources"
for t in 16 32 128 256 512; do
    sips -z $t $t Assets/AppIcon.png --out "$ICONSET/icon_${t}x${t}.png" >/dev/null
    sips -z $((t * 2)) $((t * 2)) Assets/AppIcon.png --out "$ICONSET/icon_${t}x${t}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Assinatura local (ad-hoc): roda neste Mac; para outros Macs precisa da conta Apple Developer.
codesign --force --sign - "$APP"
echo "Pronto: $APP"
