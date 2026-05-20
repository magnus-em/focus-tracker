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

cat > "$APP_DIR/Info.plist" <<'EOF'
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

# Embed the Mac provisioning profile (required because the entitlements
# request iCloud + CloudKit + APNS, which are restricted entitlements).
# Run xcodebuild against Focus.xcodeproj first so Xcode regenerates a
# fresh profile that covers the *current* entitlements file — otherwise
# we end up with a stale profile from a previous container/aps-environment
# config and launchd refuses to spawn ("Unsatisfied entitlements").
# We build into /tmp to avoid iCloud-Drive xattrs corrupting codesign.
XCBUILD_DD="/tmp/FocusDerivedData"
PROFILE="$XCBUILD_DD/Build/Products/Debug/Focus.app/Contents/embedded.provisionprofile"
if [ ! -f "$PROFILE" ] || [ Focus.entitlements -nt "$PROFILE" ]; then
    echo "Regenerating provisioning profile via xcodebuild..."
    rm -rf "$XCBUILD_DD"
    xcodebuild -project Focus.xcodeproj -scheme Focus -configuration Debug \
        -derivedDataPath "$XCBUILD_DD" -allowProvisioningUpdates build >/dev/null
fi
if [ -f "$PROFILE" ]; then
    cp "$PROFILE" "$APP_DIR/embedded.provisionprofile"
fi

# Prefer xcodebuild's auto-generated .xcent for signing — it includes
# `com.apple.application-identifier` and `com.apple.developer.team-identifier`,
# which CloudKit REQUIRES to hand out a container proxy. Our bare
# Focus.entitlements file in source control omits those (they're per-team
# values that xcodebuild derives from the provisioning profile).
# Without them: every CK operation fails with
#   CKError "Missing Entitlement" — "Trying to initialize a container
#   without an application ID."
XCENT="$XCBUILD_DD/Build/Intermediates.noindex/Focus.build/Debug/Focus.build/Focus.app.xcent"
SIGN_ENTITLEMENTS="Focus.entitlements"
if [ -f "$XCENT" ]; then
    SIGN_ENTITLEMENTS="$XCENT"
    echo "Using xcodebuild-generated entitlements (has application-identifier)."
fi

# Re-sign with the iCloud entitlements. We need the cert from team
# MUR9TJXP6S (Magnus Melbourne / Yale account) — that's the team the
# iCloud container is associated with. The gmail-account cert sits in
# team 6PCPURKU8T which can't use the container.
SIGN_IDENTITY="${FOCUS_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development: Magnus Melbourne" | head -1 | sed -E 's/.*"(.*)"/\1/')
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
fi

# Strip xattrs that iCloud Drive adds to files under ~/Documents — they
# break codesigning with "resource fork ... not allowed".
ditto --norsrc --noextattr --noacl Focus.app /tmp/Focus.app.staged
rm -rf Focus.app
mv /tmp/Focus.app.staged Focus.app

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$SIGN_ENTITLEMENTS" --options runtime Focus.app
else
    echo "No signing cert found — signing ad-hoc (CloudKit will NOT work)."
    codesign --force --deep --sign - --entitlements "$SIGN_ENTITLEMENTS" Focus.app
fi

echo ""
echo "Build complete!"
echo ""
echo "  Run directly:  .build/release/Focus"
echo "  Or use app:    open Focus.app"
echo ""
echo "  To install:    cp -r Focus.app /Applications/"
