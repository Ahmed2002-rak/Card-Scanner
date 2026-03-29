# Deploy & Build Guide

## Quick deploy (the commands you run most often)

### Build APK + upload + deploy hosting
```powershell
flutter build apk --release --obfuscate --split-debug-info=build/symbols --split-per-abi
copy "D:\card_scanner\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "D:\card_scanner\card_scanner_dashboard\app-release.apk"
firebase deploy --only hosting --project card-scanner-1338a
```

### Deploy Firestore rules only
```powershell
firebase deploy --only firestore:rules --project card-scanner-1338a
```

### Deploy Cloud Functions only
```powershell
firebase deploy --only functions --project card-scanner-1338a
```

### Deploy everything at once
```powershell
firebase deploy --project card-scanner-1338a
```

### Clean build (when build fails with cache errors)
```powershell
flutter clean
flutter pub get
flutter build apk --release --obfuscate --split-debug-info=build/symbols --split-per-abi
```

## Version update checklist

When releasing a new version:

1. Update version in `lib/constants/app_version.dart`:
   ```dart
   const String kAppVersion = '1.2.0';
   ```

2. Update version in `pubspec.yaml`:
   ```yaml
   version: 1.2.0+3
   ```
   (increment the +N build number each time)

3. Build, copy, deploy (the 3 commands above)

4. Update Firestore settings (Firebase Console → Firestore → settings/global):
   - `latestVersion`: "1.2.0"
   - `minVersion`: keep as-is for optional update, set to "1.2.0" for forced update
   - `updateNotes`: describe what changed
   - `apkUrl`: keep as `https://card-scanner-1338a.web.app/app-release.apk`

## Build outputs

After building with `--split-per-abi`, APKs are in:
```
build/app/outputs/flutter-apk/
├── app-arm64-v8a-release.apk    ← Modern phones (95% of users) ~30MB
├── app-armeabi-v7a-release.apk  ← Old 32-bit phones ~24MB
└── app-x86_64-release.apk      ← Emulators only (ignore)
```

## Signing

Keystore file: `D:\card_scanner\card-scanner-release.jks`
Config file: `android/key.properties` (NOT in git)

To generate a new keystore (only if lost):
```powershell
& "C:\Program Files\Java\jre1.8.0_31\bin\keytool.exe" -genkey -v -keystore "D:\card_scanner\card-scanner-release.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias card_scanner
```

## Firebase CLI

Login:
```powershell
firebase login
```

Check current project:
```powershell
firebase use
```

Set project:
```powershell
firebase use card-scanner-1338a
```

## Cloud Functions logs

View recent function logs:
```powershell
firebase functions:log --project card-scanner-1338a
```

## URLs

- Download page: `https://card-scanner-1338a.web.app`
- Admin dashboard: `https://card-scanner-1338a.web.app/ctrl-panel-9x.html`
- Firebase Console: `https://console.firebase.google.com/project/card-scanner-1338a`

## Files NOT to commit to git

These are in `.gitignore`:
```
android/key.properties
*.jks
build/symbols/
functions/node_modules/
```
