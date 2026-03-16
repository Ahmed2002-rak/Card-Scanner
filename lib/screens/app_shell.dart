import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../main.dart' show cameras;
import 'history_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _goToHistory() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    final pages = [
      ScanTab(cameras: cameras, onGoHistory: _goToHistory),
      const HistoryTab(),
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
