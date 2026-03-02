#!/bin/bash
set -e

echo "Building Lock-In..."
swift build -c release

APP_DIR="LockIn.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp .build/release/LockIn "$APP_DIR/MacOS/"

cat > "$APP_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Lock-In</string>
    <key>CFBundleDisplayName</key>
    <string>Lock-In</string>
    <key>CFBundleIdentifier</key>
    <string>com.lockin.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>LockIn</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

echo ""
echo "Build complete!"
echo ""
echo "  Run directly:  .build/release/LockIn"
echo "  Or use app:    open LockIn.app"
echo ""
echo "  To install:    cp -r LockIn.app /Applications/"
