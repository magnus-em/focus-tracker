# CloudKit sync — one-time setup needed

## TL;DR

CloudKit sync currently fails with this exact server error:

```
"Permission Failure" (10/2007); server message = "Invalid bundle ID for container"
```

This means: the CloudKit container `iCloud.com.magnus.focus` exists in Apple's
infrastructure but is not associated with the bundle IDs `com.magnus.focus`
(Mac) or `com.magnus.focus.iPad` (iPad) at Apple's server level.

You — and only you — can fix this, because it requires logging in to Apple
Developer Portal with your account. Takes about **1 minute**.

## The fix (Option A — fastest)

1. Open **Xcode**.
2. Open `FocusPad/FocusPad.xcodeproj`.
3. Select the **FocusPad** target → **Signing & Capabilities** tab.
4. You should see a "iCloud" capability section. If you do:
   - Check that **CloudKit** is checked.
   - Under "Containers" there should be `iCloud.com.magnus.focus`.
   - If the box has a warning icon → click it. Xcode will fix the Apple-side
     association in a few seconds.
5. If you do not see iCloud at all:
   - Click `+ Capability` → add **iCloud**.
   - Check **CloudKit**.
   - Click `+` under Containers, add `iCloud.com.magnus.focus`.
6. Repeat the same for the **Mac** project at the repo root (open
   `Focus.xcodeproj` after running `xcodegen` there if needed).
7. Build the apps from Xcode once (just hit ▶). Xcode will sync the App ID ↔
   container association with Apple's dev portal during this build.

That's it. Sync will start working immediately.

## The fix (Option B — web)

If you don't want to open Xcode:

1. Go to https://developer.apple.com/account/resources/identifiers
2. Filter by **App IDs**.
3. Find **com.magnus.focus** → click → **Configure** next to iCloud →
   ensure **CloudKit** is checked → click **Edit** under iCloud → ensure
   `iCloud.com.magnus.focus` is **checked**.
4. Save.
5. Repeat for **com.magnus.focus.iPad**.
6. If the container `iCloud.com.magnus.focus` is missing from the dropdown:
   - Go to https://developer.apple.com/account/resources/identifiers → filter
     by **iCloud Containers** → click **+** → Description: "Focus", Identifier:
     `iCloud.com.magnus.focus` → register.
   - Then redo steps 3-5 to associate it with both App IDs.
7. Rebuild both apps with `xcodebuild -allowProvisioningUpdates` — they'll
   pick up new provisioning profiles automatically.

## Why this happened

When you set up the project with `xcodegen` + manual `.entitlements` files,
the provisioning profile got generated with the container identifier listed,
BUT the server-side App-ID-to-Container association at Apple's portal was
never created. Xcode's UI normally handles step 2 automatically when you
click the iCloud capability; CLI-only workflows skip it.

The provisioning profile lets your app *ask* for the container. The server-
side association is what makes the container *accept* requests from that
bundle ID.

## What to expect after the fix

- Mac and iPad both signed into the same iCloud account will see the same
  data.
- First sync after the fix may take a few seconds while CloudKit creates
  the zone + uploads existing local data.
- On the iPad, open **Settings → Sync → Refresh Sync Status**. It should
  say "Signed in" with a green dot.

## If it still fails after Option A/B

The Mac was using a clean SwiftData store I rebuilt this morning. The
original is backed up at:

```
~/Library/Application Support/Focus/swiftdata_backup_1779122546/
```

If you need to restore it: quit Focus, `cp` the three `default.store*` files
from there back to `~/Library/Application Support/`, restart Focus.

## Data integrity right now

Verified locally (`sqlite3` query against the SwiftData store):

- 55 work sessions
- 4 problems
- 4 day records
- 4 scratch items

All your data is safe. The only thing currently not working is the iCloud
mirror that pushes it across devices.

## For App Store distribution

The exact same setup applies. Each end-user authenticates with their own
iCloud account; CloudKit's `.private(...)` database keeps users' data fully
isolated. You (the developer) cannot see anyone's data unless they
explicitly share it.

Once the App ID ↔ container association is fixed once, it's permanent.
Future users downloading the app from the App Store will get sync working
out of the box.
