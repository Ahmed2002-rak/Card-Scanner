import 'dart:async';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

import '../main.dart' show cameras;
import '../services/secure_licensing.dart';
import 'history_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'activation_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _isActivated = true;
  StreamSubscription? _licenseSub;
  StreamSubscription? _settingsSub;

  String? _announcement;
  String? _announcementId;
  String _supportLink = "https://t.me/your_default_support";
  bool _isKilled = false;

  @override
  void initState() {
    super.initState();
    _initListeners();
  }

  Future<void> _initListeners() async {
    // 1. Get Device ID
    String deviceId = '';
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      var androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id;
    } else if (Platform.isIOS) {
      var iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor ?? '';
    }

    // 2. Start License Listener (By Device ID)
    if (deviceId.isNotEmpty) {
      _licenseSub = SecureLicensing.getLicenseSnapshotStream(deviceId).listen((doc) {
        if (doc == null || !doc.exists) {
          // If no document for this device, keep _isActivated as it is or false if not activated before
          // Better: don't force false if it's just missing, wait for activation
          return;
        }
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'];
        
        bool isExpired = false;
        if (data['expiryDate'] != null) {
          final expiry = (data['expiryDate'] as Timestamp).toDate();
          if (DateTime.now().isAfter(expiry)) isExpired = true;
        }

        if ((status == 'blocked' || status == 'deleted' || isExpired)) {
          if (mounted) {
            setState(() => _isActivated = false);
            _showRevokedDialog(isExpired ? "Licence Expired" : "Licence Revoked");
          }
        } else if (status == 'active' && !isExpired) {
          if (mounted) setState(() => _isActivated = true);
        }
      }, onError: (e) {
        // If query fails (e.g. no document matches), don't crash
      });
    }

    // 3. Start Settings Listener
    _settingsSub = SecureLicensing.getSettingsStream().listen((doc) {
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        final newAnnounce = data['announcement'];
        final newAnnounceId = data['announcementId'];
        
        setState(() {
          _announcement = newAnnounce;
          _announcementId = newAnnounceId;
          _supportLink = data['supportLink'] ?? _supportLink;
          _isKilled = data['killSwitch'] ?? false;
        });

        // Check for popup requirement
        if (newAnnounce != null && newAnnounce.isNotEmpty) {
          _checkAndShowAnnouncement(newAnnounce, newAnnounceId);
        }
      }
    });
  }

  Future<void> _checkAndShowAnnouncement(String text, String? id) async {
    final shouldShow = await SecureLicensing.shouldShowAnnouncement(id);
    if (shouldShow && mounted) {
      // Show Popup
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.campaign_rounded, color: Colors.indigo),
              SizedBox(width: 10),
              Text("Announcement"),
            ],
          ),
          content: Text(text, style: const TextStyle(fontSize: 16)),
          actions: [
            FilledButton(
              onPressed: () {
                if (id != null) SecureLicensing.markAnnouncementRead(id);
                Navigator.pop(ctx);
              },
              child: const Text("Got it"),
            )
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _licenseSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  void _launchSupport() {
    String url = _supportLink;
    if (!url.startsWith('http')) {
      url = 'https://t.me/${url.replaceAll('@', '')}';
    }
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _showRevokedDialog(String title) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: const Text("Access to the app has been disabled. Please contact support to renew or unlock, or enter a new key."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launchSupport();
            },
            child: const Text("Support"),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Deactivate locally to force ActivationScreen
              SecureLicensing.deactivate();
              setState(() => _isActivated = false);
            },
            child: const Text("Enter New Key"),
          )
        ],
      )
    );
  }

  void _onActivated() {
    setState(() => _isActivated = true);
    _initListeners();
  }

  @override
  Widget build(BuildContext context) {
    if (_isKilled) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.red),
                const SizedBox(height: 24),
                const Text("App Temporarily Disabled", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text("A major update or maintenance is in progress. Please check back later.", textAlign: TextAlign.center),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _launchSupport,
                  icon: const Icon(Icons.headset_mic_rounded),
                  label: const Text("Contact Support"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isActivated) {
      return ActivationScreen(onActivated: _onActivated);
    }

    final pages = [
      ScanTab(cameras: cameras, onGoHistory: () => setState(() => _index = 1), isActivated: _isActivated),
      HistoryTab(isActivated: _isActivated),
      const SettingsTab(),
    ];

    return Scaffold(
      body: SafeArea(
        top: false,
        child: pages[_index],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.qr_code_scanner_rounded), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
