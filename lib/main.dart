import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'screens/activation_screen.dart';
import 'screens/app_shell.dart';
import 'services/storage_service.dart';
import 'services/secure_licensing.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase not initialized.');
  }

  final storage = StorageService();
  await storage.init();

  final isSafe = await SecureLicensing.isDeviceSafe();
  
  // Security Check: Activation Status (Every launch check)
  final isActivated = await SecureLicensing.verifyOnLaunch();

  try {
    cameras = await availableCameras();
  } catch (e) {
    cameras = [];
  }

  runApp(CardScannerApp(
    isActivated: isActivated,
    isSafe: isSafe,
  ));
}

class CardScannerApp extends StatefulWidget {
  final bool isActivated;
  final bool isSafe;

  const CardScannerApp({
    super.key,
    required this.isActivated,
    required this.isSafe,
  });

  @override
  State<CardScannerApp> createState() => _CardScannerAppState();
}

class _CardScannerAppState extends State<CardScannerApp> {
  late bool _isActivated;

  @override
  void initState() {
    super.initState();
    _isActivated = widget.isActivated;
  }

  void _onActivated() {
    setState(() => _isActivated = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card Scanner Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          primary: const Color(0xFF1A237E),
          secondary: const Color(0xFFFFC107),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A237E),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: !widget.isSafe
          ? const Scaffold(body: Center(child: Text('Security violation detected.')))
          : _isActivated
              ? const AppShell()
              : ActivationScreen(onActivated: _onActivated),
    );
  }
}
