# Card Scanner Pro (Algeria)

A high-performance, professional Flutter application for scanning recharge cards (Mobilis, Djezzy, Ooredoo, ADSL) using Google ML Kit. This project is built with a focus on **Security**, **Speed**, and **Algerian Market Standards**.

## ??? Security & Protection (The 5 Pillars)
The app is protected by a multi-layered security system to prevent unauthorized sharing:
1. **Device-Bound License**: Keys are locked to a single hardware ID.
2. **Cloud Activation**: Verification is handled securely via Firebase Cloud Functions.
3. **Periodic Checks**: Automatic background re-validation of licenses.
4. **Hardware Encryption**: Activation status is hidden in the phone's Keystore.
5. **Root Detection**: Blocks common hacking tools while allowing Developer Mode.

## ? Professional Features
- **Modern UI/UX**: Deep Indigo theme with Material 3 components for a "premium" feel.
- **High-Precision OCR**: Optimized for 15-digit Algerian recharge codes.
- **Active Session Resume**: Never lose a scan. Resume exactly where you left off.
- **Professional Export**: One-tap export to pipe-separated TXT format.
- **Custom App Icon**: Unique brand identity for the "Card Scanner Pro" solution.

## ??? Architecture
- **Service-Oriented Design**: All logic (OCR, Storage, Export, Security) is encapsulated in dedicated services.
- **Secure Persistence**: Uses Hive for fast data and SecureStorage for license keys.
- **Model-First**: Type-safe data handling for sessions, items, and card configurations.

## ??? Getting Started

### Prerequisites
- Flutter SDK (latest)
- Firebase Project (for licensing)
- Android physical device

### Installation & Icon Setup
1. Clone the repo and run lutter pub get.
2. To update the app icon, run:
   `ash
   flutter pub run flutter_launcher_icons:main
   `
3. Build the "Hardened" APK for distribution:
   `ash
   flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols
   `

---
*Developed by Gemini CLI Assistant for professional distribution.*
