# iPad Setup

One-time steps to get the iPad app on your device and synced with the Mac via CloudKit.

## 1. Apple Developer Portal

Go to https://developer.apple.com/account → **Certificates, Identifiers & Profiles**.

### Register bundle IDs
Under **Identifiers** → **+** (top right). Pick **App IDs** → **App**.

- **Mac** (already exists in code as `com.focus.app`): if not yet registered,
  register `com.focus.app`. Description: "Focus Mac".
- **iPad**: register `com.focus.app.iPad`. Description: "Focus iPad".

For **each** of the two App IDs, scroll to **Capabilities** and tick **iCloud**.
Use the default **Include CloudKit support** option.

### Create CloudKit container

Left sidebar → **CloudKit Containers** → **+**.

- Description: "Focus"
- Container ID: `iCloud.com.focus.app` (must match exactly)

Then go back to each App ID, click on iCloud → **Configure**, and assign
`iCloud.com.focus.app` to both `com.focus.app` (Mac) and `com.focus.app.iPad`.

## 2. Local tools

```bash
brew install xcodegen
cd FocusPad
xcodegen           # generates FocusPad.xcodeproj
open FocusPad.xcodeproj
```

## 3. Xcode signing (iPad target)

1. Click the **FocusPad** project in the navigator → **FocusPad** target → **Signing & Capabilities**.
2. Tick **Automatically manage signing**.
3. **Team**: select your developer team.
4. Confirm **Bundle Identifier** reads `com.focus.app.iPad`.
5. Confirm the **iCloud** capability row is present and **CloudKit** is checked,
   with `iCloud.com.focus.app` in the containers list. If not, click **+ Capability** → **iCloud** → tick **CloudKit** → add the container.

## 4. Run on your iPad

1. Plug iPad into Mac with a cable (or use wireless debugging if set up).
2. Trust the Mac on the iPad when prompted.
3. Top of Xcode: pick **FocusPad** scheme + your iPad as the target device.
4. Hit Run (⌘R).
5. First time: on the iPad, **Settings → General → VPN & Device Management → trust your developer certificate**.

## 5. Mac signing (for sync to work)

The Mac side needs the same Developer ID signing + iCloud entitlement.
`build.sh` will use whatever Developer ID certificate is in your keychain.
After enrolling, Xcode adds the cert automatically when you sign in via
**Xcode → Settings → Accounts**.

Then rebuild + reinstall:

```bash
./build.sh
pkill -x Focus
rm -rf /Applications/Focus.app
cp -r Focus.app /Applications/
open /Applications/Focus.app
```

If you see `Signing with: Developer ID Application: <Your Name> (TEAMID)` in
the build output, you're good. If you see "No Developer ID found", the cert
isn't in your keychain — sign into Xcode and let it install one.

## 6. Sanity check sync

1. On the Mac, log a problem. Wait 10-20 seconds.
2. On the iPad, pull-to-refresh the Problems tab — your Mac entry should appear.
3. Add a homework problem on iPad. It should show up on Mac after a moment.

If sync isn't happening:
- Both devices logged into the same iCloud account?
- iCloud Drive enabled on both?
- Mac signing showed Developer ID, not ad-hoc?

## Toggling CloudKit off (debug)

If you need to test local-only:
```bash
defaults write com.focus.app cloudKitSyncEnabled -bool false
```
Restore:
```bash
defaults delete com.focus.app cloudKitSyncEnabled
```
