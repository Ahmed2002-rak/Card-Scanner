# Security Architecture

## Overview

The system uses 6 layers of protection:
1. Cloud Functions for server-side activation (no direct writes from app)
2. Firestore security rules (admin-only writes on licenses)
3. Firebase Auth (dashboard locked to single admin account)
4. Device-bound licensing (one key = one phone)
5. APK signing + obfuscation (tamper protection)
6. Root/jailbreak detection

## Cloud Functions (server-side activation)

Two functions deployed to europe-west1 (2nd Gen, Node.js 20):

### activateLicense
Input: `{ key, deviceId, deviceModel, deviceOS }`
Output: `{ success, message, expiryDate }`

Logic (in order):
1. Check if device has a BLOCKED key → reject (prevents blocked user from using new key)
2. Find license by key → not found = reject
3. Check status → blocked/deleted/expired = reject
4. Check expiry date → if past, mark expired + clear deviceId + reject
5. Check deviceId mismatch → wrong device = reject
6. Same device + already active → return success (reinstall scenario, no write)
7. Pending key → bind device, set active, calculate expiry, log activity

### checkLicense
Input: `{ key, deviceId }`
Output: `{ valid, message }`

Logic:
1. Check kill switch → if on, reject all
2. Find license → not found = reject
3. Check status → blocked/deleted/expired = reject
4. Check expiry → auto-expire server-side if past
5. Check deviceId mismatch → reject

Cloud Functions use the Firebase Admin SDK which bypasses Firestore rules entirely. This is why the app can't write to licenses but the functions can.

## Firestore security rules

```
licenses    — read: anyone (for real-time streams) | write: admin only
settings    — read: anyone (app needs kill switch) | write: admin only
activity    — read: admin | create: anyone | delete: admin
users       — read: admin | create: anyone | update: scoped fields | delete: admin
```

Key design decisions:
- Licenses are read-open so the app can use real-time Firestore streams to detect blocks, revocations, and expiry instantly. This is critical for the instant-revocation feature.
- Licenses are write-locked to admin. The mobile app CANNOT write to licenses — all activation goes through Cloud Functions.
- The activity collection allows anyone to create entries (app logs activations) but only admin can read or delete.

## Dashboard authentication

- Uses Firebase Auth (email/password) with signInWithEmailAndPassword
- onAuthStateChanged checks `user.uid === ADMIN_UID` — not just "is logged in"
- Non-admin accounts are force-logged-out with "Access denied" message
- Firebase self-registration is DISABLED in Firebase Console settings
- Dashboard HTML is at a non-guessable URL (ctrl-panel-9x.html), not index.html

## License key generation

- Uses crypto.getRandomValues() (cryptographically secure, not Math.random)
- Format: `PREFIX-XXXXXXXXXXXX-CC` (12 random chars + 2-digit checksum)
- Generated client-side in dashboard (admin-authenticated, writes directly to Firestore)

## Device binding

- Device ID: Android's hardware ID via device_info_plus (`androidInfo.id`)
- On first activation: Cloud Function binds deviceId to the license document
- Subsequent activations from different devices are rejected
- On expiry: deviceId is cleared so the device can activate a new key
- On delete: admin clears deviceId via dashboard
- On reset: admin clears deviceId, key goes back to pending

## APK protection

- Signed with a release keystore (not debug keys)
- Obfuscated with `--obfuscate --split-debug-info=build/symbols`
- ProGuard/R8 minification + shrinking enabled
- Root/jailbreak detection via flutter_jailbreak_detection (blocks rooted devices)

## XSS protection (dashboard)

All user-provided data rendered in the dashboard goes through an `esc()` function:
```javascript
function esc(str) {
    const d = document.createElement('div');
    d.textContent = str ?? '';
    return d.innerHTML;
}
```
This escapes HTML characters in license keys, device names, admin notes, and activity entries before inserting into the DOM.

## Security headers (Firebase Hosting)

Configured in firebase.json:
- X-Content-Type-Options: nosniff
- X-Frame-Options: DENY
- Referrer-Policy: strict-origin-when-cross-origin

## What an attacker CAN'T do
- Write to any Firestore collection (blocked by rules)
- Activate a key without going through Cloud Function validation
- Access the dashboard without the admin email + password + correct UID
- Create a new Firebase Auth account (registration disabled)
- Build a fake APK that installs over yours (different signing key)
- Read decompiled code easily (obfuscated)

## What an attacker CAN do (accepted risks)
- Read license keys via Firestore REST API (but can't activate them without Cloud Function)
- Use the app offline indefinitely if activated once (accepted — users need internet to share files anyway)
- Bypass root detection with Magisk Hide (low risk — most users won't bother)
- Spoof device ID after factory reset (low risk — requires admin reset)
