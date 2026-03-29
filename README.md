# Card Scanner Pro

A professional OCR scanning app for Algerian prepaid recharge cards. Built with Flutter, powered by Firebase.

## What it does

Workers at telecom shops use this app to scan batches of recharge cards (Mobilis, Djezzy, Ooredoo, Algérie Télécom ADSL/4G), extract the codes automatically via camera OCR, and export structured files for their management software.

## Mobile app features

- **Camera OCR scanning** — point at a card, tap scan, code is extracted instantly using Google ML Kit
- **Session-based workflow** — select operator + amount, scan multiple cards, export when done
- **Photo backup** — every scan silently saves a compressed photo of the card for later reference
- **Search** — find any previously scanned card by typing part of the recharge code, view the original card photo
- **Smart export** — generates TXT file (compatible with Algerian telecom software) + ZIP file (card photos + index)
- **Export name system** — each card type has a display name (e.g. "Algérie Télécom 4G") and an export name (e.g. "CRT 4G") used in the TXT file
- **Duplicate detection** — prevents scanning the same code twice in one session
- **Edit/delete cards** — rescan to replace a code + photo, or delete cards from history
- **Haptic feedback** — vibration on successful scan

## Supported card types (default)

| Display name | Export name | Digits | Amounts (DA) |
|-------------|------------|--------|-------------|
| Mobilis | CRT MOBILIS | 15 | 100, 200, 500, 1000, 2000 |
| Djezzy | CRT DJEZZY | 15 | 100, 200, 500, 1000, 2000 |
| Ooredoo | CRT OREDO | 15 | 100, 200, 500, 1000, 2000 |
| Algérie Télécom ADSL | CRT ADSL | 16 | 500, 1000, 2000, 3000 |
| Algérie Télécom 4G | CRT 4G | 16 | 500, 1000, 1500, 2500, 3500, 6500 |

Users can add custom card types with their own export names from the Settings tab.

## Licensing system

- Device-bound license keys generated from the admin dashboard
- Key types: 3-day trial, 1/6/12 month, lifetime
- Real-time license enforcement — block, revoke, or expire keys instantly
- Kill switch — disable all users immediately in emergencies
- Cloud Functions handle activation server-side

## Admin dashboard

Hosted at Firebase Hosting (hidden URL). Features:
- Generate license keys in bulk with custom prefix and duration
- Block, unblock, reset device, extend, delete licenses
- View all connected devices with admin notes
- Live activity feed (activations, blocks, expirations)
- Global announcement system (push messages to all active apps)
- App update management (optional + forced updates)
- Kill switch for emergency shutdown

## Download page

Public landing page at the root URL. Shows:
- App version (from Firestore settings)
- Download APK button
- What's new section
- Install instructions

## Tech stack

- **Mobile**: Flutter (Dart), Android
- **Backend**: Firebase (Firestore, Auth, Hosting, Cloud Functions)
- **Dashboard**: HTML5, CSS3, vanilla JavaScript (ES6 modules)
- **OCR**: Google ML Kit Text Recognition
- **Local storage**: Hive + Flutter Secure Storage

## Current version

1.1.1 — includes photo backup, search, ZIP export, Cloud Functions activation
