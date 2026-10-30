# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`HelloWorldBLEScanner`: a native SwiftUI + CoreBluetooth iPhone app (iOS 26.0 deployment target, Swift 6 language mode, no third-party dependencies) that lists nearby and connected BLE devices. Bundle ID `test.project.BLEScanner`. The original spec is in `requirements.md`. User-facing docs (signing setup, secrets, installation) are in `README.md` and written in German, and the UI strings are German too.

## Building

The checkout lives on Windows, so there's no local Xcode. **GitHub Actions is the only build path** (`.github/workflows/build-ios.yml`, runner `macos-26`, newest stable Xcode ≥ 26). Treat changes as unverified until a workflow run passes. Read failures with `gh run view <id> --log-failed`.

The command the CI runs (useful on a Mac):

```bash
xcodebuild -project HelloWorldBLEScanner.xcodeproj -scheme HelloWorldBLEScanner -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' archive -archivePath build/HelloWorldBLEScanner.xcarchive CODE_SIGNING_ALLOWED=NO
```

There are no tests. BLE can't run in the Simulator, so functional testing needs a physical iPhone.

## Xcode project

`project.pbxproj` was written by hand and uses `objectVersion = 77` with a `PBXFileSystemSynchronizedRootGroup` for `HelloWorldBLEScanner/`. Every file in that folder joins the target automatically, so **adding or removing Swift files needs no pbxproj edit**. Object IDs follow the `A1000000000000000000000X` pattern. Info.plist is generated (`GENERATE_INFOPLIST_FILE`), so plist keys such as `NSBluetoothAlwaysUsageDescription` are `INFOPLIST_KEY_*` build settings and are duplicated in the Debug and Release target configs. The shared scheme in `xcshareddata/` is required for CI.

## Architecture

- `BluetoothViewModel` is `@MainActor @Observable`. It owns a lazily created `CBCentralManager` (main queue, created on the first scan so the permission prompt is deferred). The delegate methods are `nonisolated`. They extract Sendable values and enter `MainActor.assumeIsolated`. Keep that pattern, because the main-queue manager is what makes it safe.
- Devices are stored as `[UUID: BLEDevice]`. Scan updates are throttled to once per second per device, and devices go stale after 30 s. Connected devices come from `retrieveConnectedPeripherals(withServices:)` over a fixed list of common service UUIDs, because iOS cannot list all connected peripherals.

## CI signing

If the secrets `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `BUILD_PROVISION_PROFILE_BASE64` and `KEYCHAIN_PASSWORD` are present, the workflow builds a temporary keychain and installs the profile. It derives the profile name, UUID, team and export method (`release-testing`/`debugging`/`app-store-connect`) from the decoded `.mobileprovision`, fills `ci/ExportOptions.plist.template` via PlistBuddy and exports a signed IPA. `TEAM_ID` is optional and only cross-checked. Without the secrets, the workflow falls back to an unsigned archive packaged as `Payload/*.app` → `.ipa`, so CI stays green. As of 2026-10 the user has no paid Apple Developer Program membership, so only the unsigned path can actually run.
