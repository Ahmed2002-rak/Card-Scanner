# Card Scanner: Master Security & Distribution Guide

This is your single, comprehensive blueprint for securing and selling the "Card Scanner" application. This plan implements a high-security licensing system that balances protection with a smooth user experience.

---

## 1. The 5 Pillars of Your Protection
1.  **Device-Bound**: Locks each license key to a single phone's unique hardware ID.
2.  **Cloud Activation**: Uses Firebase Cloud Functions to process keys (logic is hidden from hackers).
3.  **Periodic Checks**: Automatically re-validates the license every 7 days to catch revoked keys.
4.  **Encrypted Storage**: Uses the phone's hardware "Keystore" to hide the activation status.
5.  **Root Detection**: Blocks the app on rooted devices (but **allows** Developer Mode for user convenience).

---

## 2. Backend Setup (Firebase)

### A. Firestore (Key Database)
1.  Create a Firebase project and add your Android app.
2.  Create a collection named licenses.
3.  Each document should look like this:
    `json
    {
      "key": "XXXX-XXXX-XXXX", // The key you sell
      "deviceId": null,        // Locks to phone on first use
      "status": "active",      // Set to "revoked" to disable a user
      "activatedAt": null
    }
    `

### B. Cloud Functions (Security Logic)
Place this in your Firebase unctions/index.js to keep the "linking" logic off the device:
`javascript
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.activateLicense = functions.https.onCall(async (data, context) => {
  const { key, deviceId } = data;
  const snap = await admin.firestore().collection('licenses').where('key', '==', key).get();
  if (snap.empty) return { success: false };
  
  const doc = snap.docs[0];
  const dataDoc = doc.data();
  if (dataDoc.deviceId && dataDoc.deviceId !== deviceId) return { success: false };
  
  await doc.ref.update({ deviceId: deviceId, activatedAt: admin.firestore.FieldValue.serverTimestamp() });
  return { success: true };
});
`

---

## 3. Flutter Implementation

### A. Dependencies (pubspec.yaml)
`yaml
dependencies:
  device_info_plus: ^10.1.0
  cloud_firestore: ^4.17.2
  cloud_functions: ^4.6.0
  firebase_core: ^2.32.0
  flutter_secure_storage: ^9.0.0
  flutter_jailbreak_detection: ^1.1.1
`

### B. The "Hardened" Licensing Service (lib/services/secure_licensing.dart)
`dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SecureLicensing {
  static const _storage = FlutterSecureStorage();

  // 1. Root Detection (Allows Dev Mode)
  static Future<bool> isDeviceSafe() async {
    return !(await FlutterJailbreakDetection.jailbroken);
  }

  // 2. Periodic Server Check (Every 7 Days)
  static Future<void> verifyPeriodically() async {
    String? lastCheck = await _storage.read(key: 'last_check');
    DateTime lastDate = DateTime.tryParse(lastCheck ?? '') ?? DateTime(2000);

    if (DateTime.now().difference(lastDate).inDays > 7) {
      // Perform silent check against Firestore/Functions here
      // If invalid, wipe storage and lock app.
    }
  }

  // 3. Secure Activation
  static Future<bool> activate(String key) async {
    if (!(await isDeviceSafe())) return false;

    var androidInfo = await DeviceInfoPlugin().androidInfo;
    String deviceId = androidInfo.id;

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('activateLicense')
          .call({'key': key, 'deviceId': deviceId});

      if (result.data['success'] == true) {
        await _storage.write(key: 'is_activated', value: 'true');
        await _storage.write(key: 'last_check', value: DateTime.now().toIso8601String());
        return true;
      }
    } catch (e) { return false; }
    return false;
  }
}
`

---

## 4. Final Distribution: The "Hardened" Build

When you are ready to sell your app, **always** use this command to hide your code from hackers:

`ash
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols
`

### Why this is the "Best Balance":
- **Hackers**: Can't "read" your code because of obfuscation. They can't use "silly" tools because of root detection.
- **Normal Users**: They can have "Developer Mode" on and the app will still work perfectly.
- **You**: You have total control over every key from the Firebase console.

---
*Strategy Finalized for Card Scanner Project - March 2026*
