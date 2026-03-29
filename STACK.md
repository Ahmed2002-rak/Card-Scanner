# Tech Stack Reference

## Flutter packages (pubspec.yaml)

### Core
| Package | Version | Purpose |
|---------|---------|---------|
| `camera` | ^0.10.5 | Camera access for scanning |
| `google_mlkit_text_recognition` | ^0.13.0 | OCR — extracts text from card images |
| `image` | ^4.1.7 | Image processing — crop for OCR, compress for photo backup |
| `hive` / `hive_flutter` | ^2.2.3 | Local storage for scan sessions, items, card types |
| `path` | ^1.9.0 | File path manipulation |
| `path_provider` | ^2.1.2 | Access app documents directory |
| `share_plus` | ^7.2.2 | Share TXT/ZIP files via system share dialog |
| `url_launcher` | ^6.2.1 | Open support links, APK download URL |

### Security & licensing
| Package | Version | Purpose |
|---------|---------|---------|
| `firebase_core` | ^2.32.0 | Firebase initialization |
| `cloud_firestore` | ^4.17.2 | Real-time database — license streams, settings, activity |
| `cloud_functions` | ^4.6.0 | Call activateLicense/checkLicense Cloud Functions |
| `flutter_secure_storage` | ^9.0.0 | Encrypted local storage for activation state |
| `flutter_jailbreak_detection` | ^1.1.1 | Root/jailbreak detection |
| `device_info_plus` | ^10.1.0 | Get hardware device ID for license binding |

### UI
| Package | Version | Purpose |
|---------|---------|---------|
| `cupertino_icons` | ^1.0.8 | iOS-style icons |

### Dev
| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_launcher_icons` | ^0.13.1 | Generate app launcher icon |

## Cloud Functions (functions/package.json)

| Package | Purpose |
|---------|---------|
| `firebase-admin` | Server-side Firestore access (bypasses security rules) |
| `firebase-functions` | HTTP callable function framework |

Runtime: Node.js 20, region: europe-west1

## Dashboard (no package manager — CDN imports)

| Library | Source | Purpose |
|---------|--------|---------|
| Firebase JS SDK 10.4.0 | gstatic.com CDN | Firestore + Auth |
| Font Awesome 6.4.0 | cdnjs CDN | Dashboard icons |
| Inter font | Google Fonts CDN | Typography |

## Firebase services used

| Service | Purpose | Plan |
|---------|---------|------|
| Firestore | Database — licenses, users, activity, settings | Blaze (free tier covers usage) |
| Authentication | Admin dashboard login (email/password) | Free |
| Hosting | Dashboard + download page + APK file | Free tier |
| Cloud Functions | activateLicense + checkLicense | Blaze (free for ~2M calls/month) |

## File structure

```
card_scanner/
├── lib/
│   ├── main.dart
│   ├── constants/
│   │   └── app_version.dart
│   ├── models/
│   │   ├── card_type.dart          — name, exportName, digits, amounts
│   │   ├── scan_item.dart          — scanned card + photoPath
│   │   └── scan_session.dart       — session metadata + txtPath + zipPath
│   ├── screens/
│   │   ├── activation_screen.dart  — license key entry
│   │   ├── app_shell.dart          — navigation, streams, popups
│   │   ├── history_screen.dart     — session list
│   │   ├── scan_screen.dart        — camera scanning + photo backup
│   │   ├── search_screen.dart      — search cards + view photos
│   │   ├── session_details_screen.dart — card list + share + edit + delete
│   │   ├── rescan_screen.dart      — re-scan a card (returns code + photo)
│   │   └── settings_screen.dart    — card type configuration
│   ├── services/
│   │   ├── secure_licensing.dart   — Cloud Function calls, streams, activation
│   │   ├── storage_service.dart    — Hive operations, default card types
│   │   ├── ocr_service.dart        — ML Kit text recognition + cropping
│   │   └── export_service.dart     — TXT/ZIP generation, photo compression
│   ├── utils/
│   │   └── date_formatter.dart     — DD/MM/YYYY HH:mm:ss formatting
│   └── widgets/
│       ├── add_card_type_dialog.dart — add custom card type dialog
│       ├── crop_overlay_painter.dart — scan rectangle overlay
│       ├── scan_camera_view.dart     — camera preview + controls
│       └── scan_start_card.dart      — "ready to scan?" start screen
├── card_scanner_dashboard/
│   ├── index.html                  — download page (public)
│   ├── ctrl-panel-9x.html         — admin dashboard (hidden URL)
│   ├── app.js                      — dashboard logic + Firebase Auth
│   ├── style.css                   — dashboard styles
│   └── app-release.apk            — latest APK for download
├── functions/
│   ├── index.js                    — Cloud Functions (activateLicense, checkLicense)
│   └── package.json               — Node.js dependencies
├── android/
│   ├── app/
│   │   ├── build.gradle.kts       — signing config, minification
│   │   ├── google-services.json   — Firebase config
│   │   ├── proguard-rules.pro     — ProGuard rules for ML Kit + Flutter
│   │   └── src/main/AndroidManifest.xml
│   ├── build.gradle.kts           — root Gradle config
│   └── key.properties             — keystore passwords (NOT in git)
├── firebase.json                   — hosting + functions + rules config
├── firestore.rules                 — Firestore security rules
├── pubspec.yaml                    — Flutter dependencies + version
├── CLAUDE.md                       — project context for Claude AI
├── README.md                       — project presentation
├── DEPLOY.md                       — build + deploy commands
├── SECURITY.md                     — security architecture
└── STACK.md                        — this file
```

## Key tools

| Tool | Purpose |
|------|---------|
| Flutter SDK | Mobile app framework |
| Firebase CLI | Deploy hosting, functions, rules |
| Java keytool | Generate release signing keystore |
| VS Code | IDE |
| PowerShell | Terminal (Windows) |
| Git | Version control (private GitHub repo) |
