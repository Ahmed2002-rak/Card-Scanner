import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'crop_overlay_painter.dart';

class ScanCameraView extends StatelessWidget {
  const ScanCameraView({
    super.key,
    required this.initializing,
    required this.controller,
    required this.status,
    required this.busy,
    required this.torchEnabled,
    required this.torchAvailable,
    required this.countSaved,
    required this.pendingCode,
    required this.showNextDoneRetry,
    required this.onScan,
    required this.onNext,
    required this.onDone,
    required this.onRetry,
    required this.onToggleTorch,
  });

  final bool initializing;
  final CameraController controller;
  final String status;
  final bool busy;
  final bool torchEnabled;
  final bool torchAvailable;

  final int countSaved;
  final String? pendingCode;
  final bool showNextDoneRetry;

  final VoidCallback onScan;
  final VoidCallback onNext;
  final VoidCallback onDone;
  final VoidCallback onRetry;
  final VoidCallback onToggleTorch;

  @override
  Widget build(BuildContext context) {
    if (initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!controller.value.isInitialized) {
      return const Center(child: Text('Camera not ready.'));
    }

    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(controller)),

        // Overlay rectangle
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: CropOverlayPainter(
                widthFactor: 0.82,
                heightFactor: 0.11,
              ),
            ),
          ),
        ),

        // Status + Counter
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scanned: $countSaved',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(status, style: const TextStyle(color: Colors.white)),
                if (pendingCode != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Result: $pendingCode',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Torch button
        if (torchAvailable)
          Positioned(
            right: 16,
            top: 120,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: torchEnabled
                      ? Colors.amber.withOpacity(0.9)
                      : Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    torchEnabled ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                  ),
                  onPressed: onToggleTorch,
                ),
              ),
            ),
          ),

        // Bottom controls
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) const LinearProgressIndicator(),
                const SizedBox(height: 10),

                if (!showNextDoneRetry)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy ? null : onScan,
                      icon: const Icon(Icons.document_scanner),
                      label: Text(busy ? 'Scanning...' : 'Scan'),
                    ),
                  ),

                if (showNextDoneRetry)
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onRetry,
                              child: const Text('Retry'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onNext,
                              child: const Text('Next'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: onDone,
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
