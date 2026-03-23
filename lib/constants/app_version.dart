// ─────────────────────────────────────────────────────────────────────────────
// APP VERSION — update this file AND pubspec.yaml every time you release a new APK.
//
// Rules:
//   Patch bump (1.0.0 → 1.0.1): bug fixes — optional update shown to users
//   Minor bump (1.0.0 → 1.1.0): new features — optional update shown to users
//   Major bump (1.0.0 → 2.0.0): breaking change — FORCED update, old version blocked
//
// After updating this file, also update in Firestore settings/global:
//   latestVersion  → this version string
//   minVersion     → lowest version you still allow (keep old value unless forcing)
//   apkUrl         → new Firebase Hosting APK URL
//   updateNotes    → what changed in plain language for your users
// ─────────────────────────────────────────────────────────────────────────────

const String kAppVersion = '1.0.0';
