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

cp Focus.entitlements "$APP_DIR/Resources/"

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
    <string>com.magnus.focus</string>
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
</dict>
</plist>
EOF

# Re-sign with the iCloud entitlements. Prefers a Developer ID certificate
# (for distribution); falls back to Apple Development (works on your own
# machines, which is what we need for CloudKit testing).
SIGN_IDENTITY="${FOCUS_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
fi
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements Focus.entitlements --options runtime Focus.app
else
    echo "No signing cert found — signing ad-hoc (CloudKit will NOT work)."
    codesign --force --deep --sign - --entitlements Focus.entitlements Focus.app
fi

echo ""
echo "Build complete!"
echo ""
echo "  Run directly:  .build/release/Focus"
echo "  Or use app:    open Focus.app"
echo ""
echo "  To install:    cp -r Focus.app /Applications/"
