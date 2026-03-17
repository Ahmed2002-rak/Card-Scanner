# Card Scanner Pro (Algeria Edition)

A high-performance Flutter application designed for high-speed OCR scanning of recharge cards (Mobilis, Djezzy, Ooredoo, and Algérie Télécom). This project features a robust remote licensing system and a dedicated administrative dashboard.

## 🚀 Features

### Mobile Application (Flutter)
- **High-Speed OCR**: Optimized for 15 and 16-digit codes using Google ML Kit.
- **Precision Cropping**: Interactive camera view with fixed-aspect ratios for different card types.
- **Smart Validation**: 
  - Prevents duplicate scans within the same session.
  - Checksum validation for license keys (offline check).
- **Premium UX**: 
  - Haptic feedback (vibrations) on successful scans.
  - Modern Deep Indigo theme with Material 3 components.
- **Export System**: Generates standardized `.txt` files (e.g., `CRT MOBILIS`, `CRT ADSL`) compatible with Algerian management systems.

### Security & Licensing
- **Device Locking**: Licenses are cryptographically bound to the device hardware ID.
- **Real-time Monitoring**: The app instantly reacts to license blocks or expiration via Firestore Streams.
- **Trial System**: Support for generated 3-Day trial keys to facilitate customer acquisition.
- **Root Detection**: Built-in jailbreak/root detection to prevent unauthorized tampering.

### Admin Dashboard (Web)
- **Firebase Hosted**: Accessible from anywhere at `https://card-scanner-1338a.web.app/`.
- **License Management**:
  - Bulk key generation with customizable prefixes.
  - Duration control: 3-Day Trial, 1 Month, 6 Months, 1 Year, and Lifetime.
  - Instant Block/Unlock/Delete functionality.
- **Live Stats**: Real-time tracking of total, active, and blocked licenses.

## 🛠️ Technology Stack
- **Frontend**: Flutter (Dart)
- **Admin Dashboard**: HTML5, CSS3 (Modern Flexbox/Grid), JavaScript (ES6+).
- **Backend**: Firebase (Cloud Firestore, Firebase Hosting).
- **Local Storage**: Hive (Encrypted for sensitive data).

## 📦 Building the App
To generate the lightweight ARM64 APK:
```bash
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons
```

---
*Created for the Algerian Recharge Card Market - March 2026*
