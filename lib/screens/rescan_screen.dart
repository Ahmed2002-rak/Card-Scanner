import "dart:io";
import "package:camera/camera.dart";
import "package:flutter/material.dart";
import "../services/ocr_service.dart";
import "../widgets/crop_overlay_painter.dart";

class RescanPage extends StatefulWidget {
  const RescanPage({
    super.key,
    required this.cameras,
    required this.sessionId,
    required this.oldCode,
    required this.digits,
  });

  final List<CameraDescription> cameras;
  final String sessionId;
  final String oldCode;
  final int digits;

  @override
  State<RescanPage> createState() => _RescanPageState();
}

class _RescanPageState extends State<RescanPage> {
  final OCRService _ocr = OCRService();
  CameraController? _controller;
  bool _initializingCamera = false;
  bool _busy = false;

  String _status = "Scan again to replace code.";
  String? _pending;
  bool _showUseRetry = false;

  static const double cropWidthFactor = 0.82;
  static const double cropHeightFactor = 0.11;

  @override
  void initState() {
    super.initState();
    _ensureCameraReady();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _ensureCameraReady() async {
    if (_controller != null && _controller!.value.isInitialized) return;
    setState(() => _initializingCamera = true);

    final back = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await controller.initialize();
    if (!mounted) return;

    setState(() {
      _controller = controller;
      _initializingCamera = false;
    });
  }

  Future<void> _scan() async {
    if (_busy || _controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _busy = true;
      _pending = null;
      _showUseRetry = false;
      _status = "Scanning...";
    });

    try {
      final pic = await _controller!.takePicture();
      final croppedFile = await _ocr.cropCenterForOcr(pic.path, cropWidthFactor, cropHeightFactor);
      final codes = await _ocr.scanImage(croppedFile, widget.digits);
      
      if (!mounted) return;

      if (codes.isEmpty) {
        setState(() {
          _busy = false;
          _status = "No ${widget.digits}-digit code found. Try again.";
        });
        return;
      }

      setState(() {
        _pending = codes.first;
        _busy = false;
        _showUseRetry = true;
        _status = "Result: ${codes.first}";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = "Scan failed: $e";
      });
    }
  }

  void _retry() {
    setState(() {
      _pending = null;
      _showUseRetry = false;
      _status = "Retry scanning...";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Modify card (rescan)")),
      body: _controller == null || _initializingCamera
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(child: CameraPreview(_controller!)),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: CropOverlayPainter(
                        widthFactor: cropWidthFactor,
                        heightFactor: cropHeightFactor,
                      ),
                    ),
                  ),
                ),
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
                    child: Text(
                      "Old: ${widget.oldCode}\n$_status",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_busy) const LinearProgressIndicator(),
                        const SizedBox(height: 10),
                        if (!_showUseRetry)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _scan,
                              icon: const Icon(Icons.document_scanner),
                              label: const Text("Scan"),
                            ),
                          ),
                        if (_showUseRetry)
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _retry,
                                  child: const Text("Retry"),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _pending == null
                                      ? null
                                      : () => Navigator.pop(context, _pending),
                                  child: const Text("Use this"),
                                ),
                              ),
                            ],
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
