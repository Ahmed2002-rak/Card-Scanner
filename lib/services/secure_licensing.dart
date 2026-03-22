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
  static final _firestore = FirebaseFirestore.instance;

  static Future<bool> isDeviceSafe() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return !(await FlutterJailbreakDetection.jailbroken);
    }
    return true;
  }

  static Future<String?> getStoredKey() async => await _storage.read(key: _licenseKeyStored);

  static Future<bool> verifyOnLaunch() async {
    final key = await getStoredKey();
    if (key == null) return false;

    final isStillValid = await isKeyValidRemote(key);
    if (!isStillValid) {
      // Don't fully deactivate here, let AppShell handle the UI stream
      // but return false to show we are not in a valid state
      return false;
    }
    return true;
  }

  static Stream<DocumentSnapshot> getSettingsStream() {
    return _firestore.collection('settings').doc('global').snapshots();
  }

  /// Verification Logic:
  /// 1. Check if key exists and is not blocked/deleted/expired.
  /// 2. If key is linked to a device, must match current device.
  /// 3. If kill switch is ON, return false.
  static Future<bool> isKeyValidRemote(String key) async {
    try {
      // 1. Check Kill Switch
      final settings = await _firestore.collection('settings').doc('global').get();
      if (settings.exists && settings.data()?['killSwitch'] == true) return false;

      final query = await _firestore
          .collection('licenses')
          .where('key', isEqualTo: key)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) return false;

      final doc = query.docs.first;
      final data = doc.data();
      final deviceId = await _getDeviceId();

      // Basic validity
      if (data['status'] == 'blocked' || data['status'] == 'deleted' || data['status'] == 'expired') return false;
      
      // Expiry check
      if (data['expiryDate'] != null) {
        final expiry = (data['expiryDate'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiry)) {
          // AUTO-EXPIRY LOGIC
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

      // Device ownership check
      // If linked to a device, it MUST be this device
      if (data['deviceId'] != null && data['deviceId'] != "" && data['deviceId'] != deviceId) {
        return false;
      }

      return true;
    } catch (e) {
      // On error (offline), trust local storage if it was previously activated
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

  static Future<String> _getDeviceId() async {
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

  /// Activation Logic:
  /// 1. Key must exist and be valid (not blocked/deleted/expired).
  /// 2. If key is 'pending' (no deviceId), link it to this device.
  /// 3. If key already has a deviceId, it must match this device.
  static Future<bool> activate(String key) async {
    if (!(await isDeviceSafe())) return false;
    final deviceId = await _getDeviceId();
    
    // Get hardware info for dashboard
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
      final query = await _firestore.collection('licenses').where('key', isEqualTo: key).limit(1).get();
      if (query.docs.isEmpty) return false;

      final doc = query.docs.first;
      final data = doc.data();

      // 1. Status Check
      if (data['status'] == 'blocked' || data['status'] == 'deleted' || data['status'] == 'expired') return false;
      
      // 2. Expiry Check
      if (data['expiryDate'] != null) {
        final expiry = (data['expiryDate'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiry)) {
          await doc.reference.update({'status': 'expired'});
          return false;
        }
      }

      // 3. Device Ownership Check
      // If already linked to another device, error.
      if (data['deviceId'] != "" && data['deviceId'] != null && data['deviceId'] != deviceId) {
        return false;
      }

      // 4. Perform Activation / Linking
      final updates = <String, dynamic>{
        'deviceId': deviceId,
        'deviceModel': model,
        'deviceOS': os,
        'status': 'active',
        'lastReactivationAt': FieldValue.serverTimestamp(),
      };

      // Set initial activation dates if first time
      if (data['activatedAt'] == null) {
        updates['activatedAt'] = FieldValue.serverTimestamp();
        if (data['durationDays'] != null) {
          updates['expiryDate'] = Timestamp.fromDate(DateTime.now().add(Duration(days: data['durationDays'])));
        } else if (data['durationMonths'] != null) {
          updates['expiryDate'] = Timestamp.fromDate(DateTime.now().add(Duration(days: data['durationMonths'] * 30)));
        }
      }

      await doc.reference.update(updates);
      
      // 5. Update User Profile
      await _firestore.collection('users').doc(deviceId).set({
        'deviceId': deviceId,
        'deviceModel': model,
        'deviceOS': os,
        'currentLicense': key,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 6. Log Activity (Fire and forget, don't block activation success)
      _firestore.collection('activity').add({
        'key': key,
        'action': 'Activated',
        'device': model,
        'timestamp': FieldValue.serverTimestamp(),
      }).catchError((_) => null);

      // 6. Local Persistence
      await _storage.write(key: _activationKey, value: 'true');
      await _storage.write(key: _licenseKeyStored, value: key);
      
      return true;
    } catch (e) {
      // Only return false if we actually failed to reach the server
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
}
