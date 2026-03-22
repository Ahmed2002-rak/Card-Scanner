import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class SecureLicensing {
  static const _storage = FlutterSecureStorage();
  static const String _activationKey = 'is_activated';
  static const String _licenseKeyStored = 'current_license_key';
  static const String _lastAnnounceId = 'last_announcement_id';
  // ✅ NEW: stores the date (YYYY-MM-DD) the expiry warning was last shown
  static const String _lastExpiryWarnDate = 'last_expiry_warn_date';
  static final _firestore = FirebaseFirestore.instance;

  static Future<bool> isDeviceSafe() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return !(await FlutterJailbreakDetection.jailbroken);
    }
    return true;
  }

  static Future<String?> getStoredKey() async =>
      await _storage.read(key: _licenseKeyStored);

  static Future<bool> verifyOnLaunch() async {
    final key = await getStoredKey();
    if (key == null) return false;
    final isStillValid = await isKeyValidRemote(key);
    if (!isStillValid) return false;
    return true;
  }

  static Stream<DocumentSnapshot> getSettingsStream() {
    return _firestore.collection('settings').doc('global').snapshots();
  }

  // Private wrapper used internally by activate() and isKeyValidRemote()
  static Future<String> _getDeviceId() async => await getDeviceId();

  static Future<bool> isKeyValidRemote(String key) async {
    try {
      final settings = await _firestore
          .collection('settings')
          .doc('global')
          .get();
      if (settings.exists && settings.data()?['killSwitch'] == true)
        return false;

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
          data['deviceId'] != "" &&
          data['deviceId'] != deviceId) {
        return false;
      }

      return true;
    } catch (e) {
      return await isActivated();
    }
  }

  static Stream<DocumentSnapshot?> getLicenseSnapshotStream(String deviceId) {
    return _firestore
        .collection('licenses')
        .where('deviceId', isEqualTo: deviceId)
        .limit(1)
        .snapshots()
        .map((q) => q.docs.isNotEmpty ? q.docs.first : null);
  }

  static Future<String> getDeviceId() async {
    String deviceId = '';
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      var androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id;
    } else if (Platform.isIOS) {
      var iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor ?? 'unknown_ios';
    }
    return deviceId;
  }

  static Future<bool> activate(String key) async {
    if (!(await isDeviceSafe())) return false;
    final deviceId = await _getDeviceId();

    String model = "Unknown";
    String os = "Unknown";
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      var info = await deviceInfo.androidInfo;
      model = "${info.manufacturer} ${info.model}";
      os = "Android ${info.version.release}";
    } else if (Platform.isIOS) {
      var info = await deviceInfo.iosInfo;
      model = info.utsname.machine ?? "iPhone";
      os = "iOS ${info.systemVersion}";
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

      if (data['deviceId'] != "" &&
          data['deviceId'] != null &&
          data['deviceId'] != deviceId) {
        return false;
      }

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
            DateTime.now().add(Duration(days: data['durationDays'])),
          );
        } else if (data['durationMonths'] != null) {
          updates['expiryDate'] = Timestamp.fromDate(
            DateTime.now().add(Duration(days: data['durationMonths'] * 30)),
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
    } catch (e) {
      return false;
    }
  }

  static Future<bool> isActivated() async {
    String? value = await _storage.read(key: _activationKey);
    return value == 'true';
  }

  static Future<void> deactivate() async {
    await _storage.delete(key: _activationKey);
    await _storage.delete(key: _licenseKeyStored);
  }

  static Future<bool> shouldShowAnnouncement(String? newId) async {
    if (newId == null || newId.isEmpty) return false;
    String? lastId = await _storage.read(key: _lastAnnounceId);
    return lastId != newId;
  }

  static Future<void> markAnnouncementRead(String id) async {
    await _storage.write(key: _lastAnnounceId, value: id);
  }

  // ✅ NEW: Expiry warning — once per day when fewer than 7 days remain.
  // daysLeft is the number of full days until expiry (can be 0 = expires today).
  static Future<bool> shouldShowExpiryWarning(int daysLeft) async {
    if (daysLeft >= 7) return false;
    final today = DateTime.now().toIso8601String().substring(
      0,
      10,
    ); // YYYY-MM-DD
    final lastShown = await _storage.read(key: _lastExpiryWarnDate);
    return lastShown != today;
  }

  static Future<void> markExpiryWarningShown() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _storage.write(key: _lastExpiryWarnDate, value: today);
  }
}
