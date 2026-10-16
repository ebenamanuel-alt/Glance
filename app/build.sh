#!/bin/bash
# Builds "Glance.app" from every .swift file in this folder.
set -e
cd "$(dirname "$0")"
APP="Glance.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
echo "Building..."
swiftc -O -parse-as-library *.swift \
  -framework SwiftUI -framework AppKit -framework CoreMotion -framework ApplicationServices \
  -o "$APP/Contents/MacOS/Glance"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Glance</string>
  <key>CFBundleDisplayName</key><string>Glance</string>
  <key>CFBundleIdentifier</key><string>com.ebenamanuel.glance</string>
  <key>CFBundleExecutable</key><string>Glance</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMotionUsageDescription</key><string>Glance uses your AirPods' head tracking to tell which screen you're looking at.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Done: $APP"
