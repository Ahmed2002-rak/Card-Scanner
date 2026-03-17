import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class SecureLicensing {
  static const _storage = FlutterSecureStorage();
  static const String _activationKey = 'is_activated';
  static const String _lastCheckKey = 'last_check';
  static final _firestore = FirebaseFirestore.instance;

  static Future<bool> isDeviceSafe() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return !(await FlutterJailbreakDetection.jailbroken);
    }
    return true;
  }

  // UPDATED: Now checks every time, but returns quickly if offline
  static Future<bool> verifyOnLaunch() async {
    final isStillValid = await isActivatedRemote();
    if (!isStillValid) {
      await deactivate();
      return false;
    }
    return true;
  }

  // Real-time listener for instant blocking
  static Stream<bool> get licenseStatusStream async* {
    final deviceId = await _getDeviceId();
    yield* _firestore
        .collection('licenses')
        .where('deviceId', isEqualTo: deviceId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return false;
      final data = snapshot.docs.first.data();
      
      // Check block status
      if (data['status'] == 'blocked') return false;
      
      // Check expiry
      if (data['expiryDate'] != null) {
        final expiry = (data['expiryDate'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiry)) return false;
      }
      
      return data['status'] == 'active';
    });
  }

  static Future<bool> isActivatedRemote() async {
    final deviceId = await _getDeviceId();
    if (deviceId.isEmpty) return false;
    
    try {
      final query = await _firestore
          .collection('licenses')
          .where('deviceId', isEqualTo: deviceId)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) return false;

      final data = query.docs.first.data();
      if (data['status'] == 'blocked') return false;

      if (data['expiryDate'] != null) {
        final expiry = (data['expiryDate'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiry)) return false;
      }

      return data['status'] == 'active';
    } catch (e) {
      // If offline, trust local storage
      return await isActivated();
    }
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

  static Future<bool> activate(String key) async {
    if (!(await isDeviceSafe())) return false;
    final deviceId = await _getDeviceId();

    try {
      final query = await _firestore
          .collection('licenses')
          .where('key', isEqualTo: key)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return false;
      final doc = query.docs.first;
      final data = doc.data();

      if (data['status'] == 'blocked') return false;
      if (data['expiryDate'] != null) {
        final expiry = (data['expiryDate'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiry)) return false;
      }

      if (data['deviceId'] != "" && data['deviceId'] != deviceId) return false;

      final updates = <String, dynamic>{
        'deviceId': deviceId,
        'status': 'active',
        'lastReactivationAt': FieldValue.serverTimestamp(),
      };

      if (data['activatedAt'] == null) {
        updates['activatedAt'] = FieldValue.serverTimestamp();
        if (data['durationDays'] != null) {
          final expiry = DateTime.now().add(Duration(days: data['durationDays']));
          updates['expiryDate'] = Timestamp.fromDate(expiry);
        } else if (data['durationMonths'] != null) {
          final expiry = DateTime.now().add(Duration(days: data['durationMonths'] * 30));
          updates['expiryDate'] = Timestamp.fromDate(expiry);
        }
      }

      await doc.reference.update(updates);
      await _storage.write(key: _activationKey, value: 'true');
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
    await _storage.delete(key: _lastCheckKey);
  }
}
