# CLAUDE.md — Card Scanner Pro Project Context

## Who I am
- Solo developer based in Algeria (El Oued)
- Building mobile apps with Flutter + Firebase backend
- Dashboard hosted on Firebase Hosting (plain HTML/JS/CSS)
- Monetization: selling license keys to users for the Card Scanner app

## Project overview
Card Scanner Pro is a professional OCR-based mobile app for scanning Algerian prepaid recharge cards (Mobilis, Djezzy, Ooredoo, Algérie Télécom ADSL/4G). Workers scan batches of cards, extract recharge codes via camera OCR, and export structured TXT files compatible with Algerian telecom management software. The app uses a device-bound licensing system managed through a web admin dashboard.

## Architecture

### Mobile app (Flutter/Dart — Android)
- Camera-based OCR scanning using Google ML Kit
- Sessions group batches of scanned cards by operator + amount
- Each scan saves the recharge code + a compressed card photo
- Export: TXT file (for software) + ZIP file (photos + index for reference)
- Local storage: Hive (scan data) + Flutter Secure Storage (activation state)
- Licensing: activates via Cloud Function, real-time streams for revocation
- Search tab: find any previously scanned card by typing part of the code

### Admin dashboard (plain HTML/JS/CSS — Firebase Hosting)
- Firebase Auth (email/password) locked to admin UID only
- Manages licenses: generate, block, unblock, extend, reset device, delete
- User management with admin notes
- Live activity feed (last 100 events)
- Global settings: kill switch, announcements, support link, app update management
- All data rendered with XSS protection (esc() helper)
- Located at a non-guessable URL (not index.html)

### Download page (public — Firebase Hosting)
- index.html serves as the download page
- Reads version info + APK URL from Firestore settings
- Shows install instructions

### Backend (Firebase)
- **Firestore collections**: licenses, users, activity, settings
- **Firebase Auth**: admin dashboard only (single admin email)
- **Cloud Functions (2nd Gen, Node.js 20, europe-west1)**:
  - `activateLicense` — handles all activation logic server-side
  - `checkLicense` — verifies license on every app launch
- **Firebase Hosting**: dashboard + download page + APK file
- **Firestore rules**: admin-write on licenses, read-open for real-time streams

### Security layers
- Cloud Functions for activation (no direct Firestore writes from app)
- Firestore rules: licenses write-locked to admin, reads open for streams
- Dashboard locked to specific admin UID + Firebase Auth
- Firebase self-registration disabled
- APK signed with release keystore + obfuscated
- Crypto-secure license key generation
- Root/jailbreak detection
- XSS protection in dashboard

## Firestore collections schema

### licenses
```
key: string              — license key (e.g. RAK-XXXXXXXX-XX)
status: string           — pending | active | blocked | expired | deleted
deviceId: string         — bound device hardware ID (empty if pending)
deviceModel: string      — e.g. "samsung SM-A715F"
deviceOS: string         — e.g. "Android 13"
createdAt: timestamp
activatedAt: timestamp
expiryDate: timestamp
lastReactivationAt: timestamp
durationDays: number     — for trial keys (e.g. 3)
durationMonths: number   — for subscription keys (e.g. 1, 6, 12)
lifetime: boolean        — true for lifetime keys
```

### settings (single document: "global")
```
killSwitch: boolean
announcement: string
announcementId: string
supportLink: string
latestVersion: string    — e.g. "1.1.0"
minVersion: string       — below this = forced update
apkUrl: string           — download link for APK
updateNotes: string
```

### users (document ID = deviceId)
```
deviceId, deviceModel, deviceOS, currentLicense, lastActive, adminNotes
```

### activity
```
key, action, device, timestamp
```

## Key files

### Mobile app (lib/)
- `main.dart` — entry point, Firebase init, safety check, activation check
- `constants/app_version.dart` — version string (must match pubspec.yaml)
- `services/secure_licensing.dart` — Cloud Function calls, streams, local persistence
- `services/storage_service.dart` — Hive storage, default card types
- `services/ocr_service.dart` — Google ML Kit text recognition + image cropping
- `services/export_service.dart` — TXT/ZIP generation, photo compression
- `screens/app_shell.dart` — main navigation, license stream, kill switch, popups
- `screens/activation_screen.dart` — key entry UI
- `screens/scan_screen.dart` — camera scanning flow with photo backup
- `screens/search_screen.dart` — search cards by recharge code, view photos
- `screens/history_screen.dart` — session list
- `screens/session_details_screen.dart` — card list with share/edit/delete + photo view
- `screens/rescan_screen.dart` — re-scan a card to replace code + photo
- `screens/settings_screen.dart` — card type configuration
- `models/card_type.dart` — name, exportName, digits, amounts
- `models/scan_item.dart` — scanned card data + photoPath
- `models/scan_session.dart` — session metadata + txtPath + zipPath

### Dashboard (card_scanner_dashboard/)
- `index.html` — download page (public)
- `ctrl-panel-9x.html` — admin dashboard (hidden URL)
- `app.js` — dashboard logic, Firebase Auth, admin UID lock, XSS protection
- `style.css` — dashboard styling

### Cloud Functions (functions/)
- `index.js` — activateLicense + checkLicense
- `package.json` — Node.js 20, firebase-admin, firebase-functions

### Config files
- `firebase.json` — hosting + functions + firestore rules config
- `firestore.rules` — security rules
- `android/app/build.gradle.kts` — release signing + obfuscation
- `android/key.properties` — keystore config (NOT in git)

## License scenarios (all handled)
- Pending key + new device → activate, bind device, set expiry
- Same device re-enters same active key → restore locally (no Firestore write)
- Blocked device tries new key → rejected
- Blocked key deleted/expired by admin → device freed, can use new key
- Expired key → deviceId cleared, device freed for new key
- Key active + user enters different key → stays on old key
- Admin extends key → only active keys can be extended
- Admin unblocks → app auto-reactivates instantly
- Kill switch on/off → instant effect via real-time stream
- Offline → app works, checks resume when online

## What I expect from Claude
- Act as senior full-stack developer AND UI/UX designer
- Write production-ready code, not tutorials
- Give me complete files I can drop into my project
- Keep solutions simple — solo dev, no over-engineering
- Security-conscious but practical
- When designing UI: modern, clean, professional
- Firebase project: card-scanner-1338a
- Admin email: rezigahmedkhodir@gmail.com
- Region: europe-west1 (Cloud Functions)
