import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/secure_licensing.dart';

class ActivationScreen extends StatefulWidget {
  final VoidCallback onActivated;

  const ActivationScreen({super.key, required this.onActivated});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _keyController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String _supportLink = "https://t.me/your_default_support";
  StreamSubscription? _settingsSub;

  @override
  void initState() {
    super.initState();
    _settingsSub = SecureLicensing.getSettingsStream().listen((doc) {
      if (doc.exists && mounted) {
        setState(() {
          _supportLink = (doc.data() as Map<String, dynamic>)['supportLink'] ?? _supportLink;
        });
      }
    });
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    super.dispose();
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Activation Error"),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleActivation() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _errorMessage = 'Please enter your license key');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await SecureLicensing.activate(key);
      if (success) {
        widget.onActivated();
      } else {
        const err = 'Invalid key or unauthorized device';
        setState(() => _errorMessage = err);
        _showErrorDialog(err);
      }
    } catch (e) {
      const err = 'Activation failed. Check your internet.';
      setState(() => _errorMessage = err);
      _showErrorDialog(err);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _launchSupport() {
    String url = _supportLink;
    if (!url.startsWith('http')) {
      url = 'https://t.me/${url.replaceAll('@', '')}';
    }
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: CircleAvatar(radius: 200, backgroundColor: Colors.white.withOpacity(0.05)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.vpn_key_rounded, size: 60, color: Color(0xFFFFC107)),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'License Required',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter your license key to unlock all professional features.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                    child: TextField(
                      controller: _keyController,
                      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'XXXX-XXXX-XXXX',
                        hintStyle: TextStyle(color: Colors.grey.shade400, letterSpacing: 1),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 20),
                        // errorText: _errorMessage, // Removed to use only popup
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _handleActivation,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Text('ACTIVATE NOW', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 40),
                  TextButton(
                    onPressed: _launchSupport,
                    child: const Text('Don\'t have a key? Contact Support', style: TextStyle(color: Colors.white60)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
