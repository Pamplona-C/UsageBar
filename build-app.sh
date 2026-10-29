#!/bin/bash
# Compila em release, empacota UsageBar.app (LSUIElement, assinado ad-hoc) e instala em ~/Applications.
# Uso: ./build-app.sh [--no-open]
set -euo pipefail
cd "$(dirname "$0")"

name="UsageBar"
bundle_id="com.gustavopamplona.UsageBar"
version="0.1.0"
install_dir="$HOME/Applications"
app=".build/app/$name.app"

swift build -c release
binary="$(swift build -c release --show-bin-path)/$name"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/$name"
# Os mesmos scripts do terminal, usados pelo botão "Configurar statusline".
cp -R scripts "$app/Contents/Resources/scripts"
rm "$app/Contents/Resources/scripts/make-icon.swift"
swift scripts/make-icon.swift "$app/Contents/Resources/$name.icns"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>pt-BR</string>
  <key>CFBundleDisplayName</key>
  <string>$name</string>
  <key>CFBundleExecutable</key>
  <string>$name</string>
  <key>CFBundleIconFile</key>
  <string>$name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$app"
codesign --verify --strict "$app"

# Fecha a versão em execução antes de trocar o .app.
pkill -x "$name" 2>/dev/null || true
# Espera o processo sair; abrir antes disso falha com erro -600 do LaunchServices.
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$name" >/dev/null || break; sleep 0.3; done
mkdir -p "$install_dir"
rm -rf "$install_dir/$name.app"
ditto "$app" "$install_dir/$name.app"
echo "Instalado em $install_dir/$name.app"

if [ "${1:-}" != "--no-open" ]; then
  open "$install_dir/$name.app"
fi
