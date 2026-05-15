#!/bin/bash
set -e

if [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "Building Focus..."
swift build -c release

APP_DIR="Focus.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp .build/release/Focus "$APP_DIR/MacOS/"

# Regenerate and embed app icon
swift make_icon.swift > /dev/null
iconutil -c icns /tmp/AppIcon.iconset -o "$APP_DIR/Resources/AppIcon.icns"

cat > "$APP_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Focus</string>
    <key>CFBundleDisplayName</key>
    <string>Focus</string>
    <key>CFBundleIdentifier</key>
    <string>com.focus.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Focus</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Focus uses your microphone to record a daily voice oath for your commitment.</string>
</dict>
</plist>
EOF

echo ""
echo "Build complete!"
echo ""
echo "  Run directly:  .build/release/Focus"
echo "  Or use app:    open Focus.app"
echo ""
echo "  To install:    cp -r Focus.app /Applications/"
