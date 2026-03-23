import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateStatus — returned by checkForUpdate()
// ─────────────────────────────────────────────────────────────────────────────
class UpdateStatus {
  final bool hasUpdate;
  final bool isForced; // true = block app until user downloads
  final String latestVersion;
  final String apkUrl;
  final String updateNotes;

  const UpdateStatus({
    required this.hasUpdate,
    required this.isForced,
    required this.latestVersion,
    required this.apkUrl,
    required this.updateNotes,
  });

  static const UpdateStatus none = UpdateStatus(
    hasUpdate: false,
    isForced: false,
    latestVersion: '',
    apkUrl: '',
    updateNotes: '',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SecureLicensing
// ─────────────────────────────────────────────────────────────────────────────
class SecureLicensing {
  static const _storage = FlutterSecureStorage();
  static const String _activationKey = 'is_activated';
  static const String _licenseKeyStored = 'current_license_key';
  static const String _lastAnnounceId = 'last_announcement_id';
  static const String _lastExpiryWarnDate = 'last_expiry_warn_date';
  static final _firestore = FirebaseFirestore.instance;

  // ── Device Safety ──────────────────────────────────────────────────────────

  static Future<bool> isDeviceSafe() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return !(await FlutterJailbreakDetection.jailbroken);
    }
    return true;
  }

  // ── Device ID ──────────────────────────────────────────────────────────────

  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      return (await deviceInfo.androidInfo).id;
    } else if (Platform.isIOS) {
      return (await deviceInfo.iosInfo).identifierForVendor ?? 'unknown_ios';
    }
    return '';
  }

  static Future<String> _getDeviceId() async => getDeviceId();

  // ── Local Persistence ──────────────────────────────────────────────────────

  static Future<bool> isActivated() async =>
      (await _storage.read(key: _activationKey)) == 'true';

  static Future<String?> getStoredKey() async =>
      _storage.read(key: _licenseKeyStored);

  static Future<void> deactivate() async {
    await _storage.delete(key: _activationKey);
    await _storage.delete(key: _licenseKeyStored);
  }

  // ── Firestore Streams ──────────────────────────────────────────────────────

  static Stream<DocumentSnapshot> getSettingsStream() =>
      _firestore.collection('settings').doc('global').snapshots();

  static Stream<DocumentSnapshot?> getLicenseSnapshotStream(String deviceId) {
    return _firestore
        .collection('licenses')
        .where('deviceId', isEqualTo: deviceId)
        .limit(1)
        .snapshots()
        .map((q) => q.docs.isNotEmpty ? q.docs.first : null);
  }

  // ── Remote Verification ────────────────────────────────────────────────────

  static Future<bool> verifyOnLaunch() async {
    final key = await getStoredKey();
    if (key == null) return false;
    return isKeyValidRemote(key);
  }

  static Future<bool> isKeyValidRemote(String key) async {
    try {
      final settings = await _firestore
          .collection('settings')
          .doc('global')
          .get();
      if (settings.exists && settings.data()?['killSwitch'] == true) {
        return false;
      }

      final query = await _firestore
          .collection('licenses')
          .where('key', isEqualTo: key)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return false;

      final doc = query.docs.first;
      final data = doc.data();
      final deviceId = await _getDeviceId();

      if (data['status'] == 'blocked' ||
          data['status'] == 'deleted' ||
          data['status'] == 'expired')
        return false;

      if (data['expiryDate'] != null) {
        final expiry = (data['expiryDate'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiry)) {
          await doc.reference.update({'status': 'expired'});
          await _firestore.collection('activity').add({
            'key': key,
            'action': 'Expired',
            'device': data['deviceModel'] ?? 'Unknown',
            'timestamp': FieldValue.serverTimestamp(),
          });
          return false;
        }
      }

      if (data['deviceId'] != null &&
          data['deviceId'] != '' &&
          data['deviceId'] != deviceId)
        return false;

      return true;
    } catch (_) {
      return isActivated(); // offline fallback
    }
  }

  // ── Activation ─────────────────────────────────────────────────────────────

  static Future<bool> activate(String key) async {
    if (!(await isDeviceSafe())) return false;
    final deviceId = await _getDeviceId();

    String model = 'Unknown', os = 'Unknown';
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      model = '${info.manufacturer} ${info.model}';
      os = 'Android ${info.version.release}';
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      model = info.utsname.machine ?? 'iPhone';
      os = 'iOS ${info.systemVersion}';
    }

    try {
      final query = await _firestore
          .collection('licenses')
          .where('key', isEqualTo: key)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return false;

      final doc = query.docs.first;
      final data = doc.data();

      if (data['status'] == 'blocked' ||
          data['status'] == 'deleted' ||
          data['status'] == 'expired')
        return false;

      if (data['expiryDate'] != null) {
        final expiry = (data['expiryDate'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiry)) {
          await doc.reference.update({'status': 'expired'});
          return false;
        }
      }

      if (data['deviceId'] != '' &&
          data['deviceId'] != null &&
          data['deviceId'] != deviceId)
        return false;

      final updates = <String, dynamic>{
        'deviceId': deviceId,
        'deviceModel': model,
        'deviceOS': os,
        'status': 'active',
        'lastReactivationAt': FieldValue.serverTimestamp(),
      };

      if (data['activatedAt'] == null) {
        updates['activatedAt'] = FieldValue.serverTimestamp();
        if (data['durationDays'] != null) {
          updates['expiryDate'] = Timestamp.fromDate(
            DateTime.now().add(Duration(days: data['durationDays'] as int)),
          );
        } else if (data['durationMonths'] != null) {
          updates['expiryDate'] = Timestamp.fromDate(
            DateTime.now().add(
              Duration(days: (data['durationMonths'] as int) * 30),
            ),
          );
        }
      }

      await doc.reference.update(updates);

      await _firestore.collection('users').doc(deviceId).set({
        'deviceId': deviceId,
        'deviceModel': model,
        'deviceOS': os,
        'currentLicense': key,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _firestore
          .collection('activity')
          .add({
            'key': key,
            'action': 'Activated',
            'device': model,
            'timestamp': FieldValue.serverTimestamp(),
          })
          .catchError((_) => null);

      await _storage.write(key: _activationKey, value: 'true');
      await _storage.write(key: _licenseKeyStored, value: key);

      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Announcement ───────────────────────────────────────────────────────────

  static Future<bool> shouldShowAnnouncement(String? newId) async {
    if (newId == null || newId.isEmpty) return false;
    return (await _storage.read(key: _lastAnnounceId)) != newId;
  }

  static Future<void> markAnnouncementRead(String id) async =>
      _storage.write(key: _lastAnnounceId, value: id);

  // ── Expiry Warning (once per day) ──────────────────────────────────────────

  static Future<bool> shouldShowExpiryWarning(int daysLeft) async {
    if (daysLeft >= 7) return false;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastShown = await _storage.read(key: _lastExpiryWarnDate);
    return lastShown != today;
  }

  static Future<void> markExpiryWarningShown() async {
    await _storage.write(
      key: _lastExpiryWarnDate,
      value: DateTime.now().toIso8601String().substring(0, 10),
    );
  }

  // ── Update Check ───────────────────────────────────────────────────────────
  //
  // Reads from Firestore settings/global:
  //   latestVersion (String) — newest available version e.g. "1.2.0"
  //   minVersion    (String) — oldest allowed version;  below = forced update
  //   apkUrl        (String) — direct download link for latest APK
  //   updateNotes   (String) — what changed, shown to user

  static Future<UpdateStatus> checkForUpdate(String currentVersion) async {
    try {
      final snap = await _firestore.collection('settings').doc('global').get();
      if (!snap.exists) return UpdateStatus.none;

      final data = snap.data()!;
      final latestVersion = (data['latestVersion'] ?? '') as String;
      final minVersion = (data['minVersion'] ?? '') as String;
      final apkUrl = (data['apkUrl'] ?? '') as String;
      final updateNotes = (data['updateNotes'] ?? '') as String;

      if (latestVersion.isEmpty) return UpdateStatus.none;

      final needsUpdate = _compareVersions(currentVersion, latestVersion) < 0;
      if (!needsUpdate) return UpdateStatus.none;

      final isForced =
          minVersion.isNotEmpty &&
          _compareVersions(currentVersion, minVersion) < 0;

      return UpdateStatus(
        hasUpdate: true,
        isForced: isForced,
        latestVersion: latestVersion,
        apkUrl: apkUrl,
        updateNotes: updateNotes,
      );
    } catch (_) {
      return UpdateStatus.none;
    }
  }

  /// Returns true if currentVersion is below minVersion (forced update needed).
  /// Called from app_shell's settings stream for real-time enforcement.
  static bool checkVersionForced(String currentVersion, String minVersion) {
    return _compareVersions(currentVersion, minVersion) < 0;
  }

  /// Returns -1 if v1 < v2, 0 if equal, 1 if v1 > v2.
  static int _compareVersions(String v1, String v2) {
    try {
      List<int> parse(String v) =>
          v.trim().split('.').map((s) => int.tryParse(s) ?? 0).toList()
            ..addAll(List.filled((3 - v.split('.').length).clamp(0, 3), 0));
      final a = parse(v1), b = parse(v2);
      for (int i = 0; i < 3; i++) {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Remote Config (scalability) ────────────────────────────────────────────
  //
  // The dashboard can add any key to settings/global.remoteConfig
  // and the app reads it here without needing an update.
  //
  // Example Firestore field:
  //   remoteConfig: { "maxScansPerDay": 50, "showWatermark": false }
  //
  // Usage in Flutter:
  //   final limit = await SecureLicensing.getRemoteConfig('maxScansPerDay', 100);

  static Future<T> getRemoteConfig<T>(String key, T defaultValue) async {
    try {
      final snap = await _firestore.collection('settings').doc('global').get();
      if (!snap.exists) return defaultValue;
      final config = snap.data()?['remoteConfig'];
      if (config is Map && config.containsKey(key)) {
        return config[key] as T;
      }
      return defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }
}
