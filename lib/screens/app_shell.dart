import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  bool _isActivated = true; // Assume true since we passed main.dart check
  StreamSubscription<bool>? _licenseSub;

  @override
  void initState() {
    super.initState();
    _startLicenseListener();
  }

  @override
  void dispose() {
    _licenseSub?.cancel();
    super.dispose();
  }

  void _startLicenseListener() {
    _licenseSub = SecureLicensing.licenseStatusStream.listen((active) {
      if (!active && mounted) {
        setState(() => _isActivated = false);
        // Show immediate alert
        _showRevokedDialog();
      }
    });
  }

  void _showRevokedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Licence Revoked"),
        content: const Text("Your license is no longer active or has expired. Please contact support."),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isActivated = false);
            }, 
            child: const Text("OK")
          )
        ],
      )
    );
  }

  void _onActivated() {
    setState(() {
      _isActivated = true;
      _index = 0;
    });
    _startLicenseListener();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActivated) {
      return ActivationScreen(onActivated: _onActivated);
    }

    final pages = [
      ScanTab(
        cameras: cameras, 
        onGoHistory: () => setState(() => _index = 1), 
        isActivated: _isActivated
      ),
      HistoryTab(isActivated: _isActivated),
      const SettingsTab(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_rounded),
            selectedIcon: Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF1A237E)),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_rounded, color: Color(0xFF1A237E)),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            selectedIcon: Icon(Icons.settings_rounded, color: Color(0xFF1A237E)),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
