#!/usr/bin/env bash
# Builds dist/MD Writer.app (web editor bundle + release Swift binary).
set -euo pipefail
cd "$(dirname "$0")/.."

(cd web && bun install --frozen-lockfile && bun run build)
swift build -c release

app="dist/MD Writer.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/MDWriter" "$app/Contents/MacOS/MDWriter"
cp -R Resources/web "$app/Contents/Resources/web"
cp -R skills "$app/Contents/Resources/skills"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
