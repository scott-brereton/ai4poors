# Ai4Poors

## Build & Run

### Simulator

```bash
xcodebuild build -project Ai4Poors.xcodeproj -scheme Ai4Poors \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug
```

### Physical Device

Replace `YOUR_DEVICE_ID` with your device's UDID (find it in Xcode > Window > Devices and Simulators).

```bash
# Build
xcodebuild build -project Ai4Poors.xcodeproj -scheme Ai4Poors \
  -destination 'platform=iOS,id=YOUR_DEVICE_ID' \
  -configuration Debug -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData

# Install
xcrun devicectl device install app \
  --device YOUR_DEVICECTL_ID \
  build/DerivedData/Build/Products/Debug-iphoneos/Ai4Poors.app

# Launch (replace with your bundle ID from Step 2)
xcrun devicectl device process launch \
  --device YOUR_DEVICECTL_ID \
  your.bundle.id.here
```

If SPM packages fail, re-resolve:
```bash
xcodebuild -resolvePackageDependencies -project Ai4Poors.xcodeproj
```

## Xcode Project

**Do NOT use Ruby xcodeproj gem to modify the pbxproj.** It rewrites UUIDs and can silently drop existing file references. Add files to targets manually in Xcode or by editing the pbxproj directly.

## Important

Before building, update **all** bundle identifiers and the Development Team in `project.yml` (and regenerate with xcodegen) or directly in the Xcode project settings to match your own Apple Developer account.
