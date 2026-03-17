import 'package:flutter/material.dart';

class ScanStartCard extends StatelessWidget {
  const ScanStartCard({super.key, required this.onStart, required this.status});
  
  final VoidCallback onStart;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF1A237E), Colors.blue.shade900],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.qr_code_scanner_rounded, size: 80, color: Colors.white),
          ),
          const SizedBox(height: 32),
          const Text(
            'Ready to scan?',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: 240,
            height: 60,
            child: FilledButton.icon(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black,
                elevation: 4,
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 32),
              label: const Text(
                'START SESSION',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.1),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Opacity(
            opacity: 0.6,
            child: Text(
              'Select card type & amount to begin',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
