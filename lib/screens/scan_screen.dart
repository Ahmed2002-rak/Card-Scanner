import "dart:io";
import "package:camera/camera.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:path_provider/path_provider.dart";

import "../models/scan_session.dart";
import "../models/scan_item.dart";
import "../models/card_type.dart";
import "../services/storage_service.dart";
import "../services/ocr_service.dart";
import "../services/export_service.dart";
import "../widgets/scan_camera_view.dart";
import "../widgets/scan_start_card.dart";

class ScanTab extends StatefulWidget {
  const ScanTab({
    super.key,
    required this.cameras,
    required this.onGoHistory,
    required this.isActivated,
  });

  final List<CameraDescription> cameras;
  final VoidCallback onGoHistory;
  final bool isActivated;

  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> {
  final StorageService _storage = StorageService();
  final OCRService _ocr = OCRService();
  final ExportService _export = ExportService();

  ScanSession? _currentSession;
  bool _sessionActive = false;

  CameraController? _controller;
  bool _initializingCamera = false;
  bool _busy = false;
  bool _torchEnabled = false;
  bool _torchAvailable = false;

  String _status = "Choose card type and amount to start.";
  int _countSaved = 0;
  String? _pendingCode;
  String? _pendingPhotoPath; // Full frame photo path for the current scan
  bool _showNextDoneRetry = false;

  static const double cropWidthFactor = 0.82;
  static const double cropHeightFactor = 0.11;

  @override
  void initState() {
    super.initState();
    _tryAutoResumeActiveSession();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _tryAutoResumeActiveSession() async {
    final active = _storage.getActiveSession();
    if (active == null) return;

    final count = _storage.getItemsForSession(active.sessionId).length;

    setState(() {
      _currentSession = active;
      _sessionActive = true;
      _countSaved = count;
      _status = "Resumed: ${active.cardName} | ${active.amount} DA";
    });

    await _ensureCameraReady();
  }

  Future<void> _ensureCameraReady() async {
    if (widget.cameras.isEmpty) {
      setState(() => _status = "No cameras available.");
      return;
    }
    if (_controller != null && _controller!.value.isInitialized) return;

    setState(() => _initializingCamera = true);
    try {
      final controller = CameraController(
        widget.cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      _torchAvailable = true;
      setState(() => _initializingCamera = false);
    } catch (e) {
      setState(() {
        _initializingCamera = false;
        _status = "Camera error: $e";
      });
    }
  }

  Future<void> _startSession() async {
    final picked = await _pickCardTypeAndAmount();
    if (picked == null) return;

    final now = DateTime.now();
    final sessionId = "sess_${now.millisecondsSinceEpoch}";

    final session = ScanSession(
      sessionId: sessionId,
      cardName: picked.name,
      amount: picked.amount,
      digits: picked.digits,
      isActive: true,
      count: 0,
      createdAt: now,
      lastUpdatedAt: now,
    );

    await _storage.saveSession(session);

    setState(() {
      _currentSession = session;
      _sessionActive = true;
      _countSaved = 0;
      _status = "Scanning ${session.cardName} (${session.amount} DA)";
    });

    await _ensureCameraReady();
  }

  Future<CardSelection?> _pickCardTypeAndAmount() async {
    final types = _storage.getCardTypes();
    if (types.isEmpty) return null;

    return showModalBottomSheet<CardSelection>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        CardType? selectedType;
        int? selectedAmount;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 20,
                right: 20,
                top: 10,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    "New Scanning Session",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text("Select the card type and reload amount."),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<CardType>(
                    value: selectedType,
                    decoration: InputDecoration(
                      labelText: "Operator",
                      prefixIcon: const Icon(Icons.business_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: types
                        .map(
                          (t) =>
                              DropdownMenuItem(value: t, child: Text(t.name)),
                        )
                        .toList(),
                    onChanged: (v) {
                      setModalState(() {
                        selectedType = v;
                        selectedAmount = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedAmount,
                    decoration: InputDecoration(
                      labelText: "Amount (DA)",
                      prefixIcon: const Icon(Icons.monetization_on_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items:
                        selectedType?.amounts
                            .map(
                              (a) => DropdownMenuItem(
                                value: a,
                                child: Text("$a DA"),
                              ),
                            )
                            .toList() ??
                        [],
                    onChanged: selectedType == null
                        ? null
                        : (v) => setModalState(() => selectedAmount = v),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 55,
                    child: FilledButton.icon(
                      onPressed:
                          (selectedType == null || selectedAmount == null)
                          ? null
                          : () => Navigator.pop(
                              ctx,
                              CardSelection(
                                name: selectedType!.name,
                                amount: selectedAmount!,
                                digits: selectedType!.digits,
                              ),
                            ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text(
                        "START SCANNING",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleTorch() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        !_torchAvailable)
      return;
    try {
      final newState = !_torchEnabled;
      await _controller!.setFlashMode(
        newState ? FlashMode.torch : FlashMode.off,
      );
      setState(() => _torchEnabled = newState);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Torch error")));
    }
  }

  Future<void> _scanOnce() async {
    if (!_sessionActive ||
        _busy ||
        _controller == null ||
        !_controller!.value.isInitialized ||
        _currentSession == null)
      return;

    setState(() {
      _busy = true;
      _pendingCode = null;
      _showNextDoneRetry = false;
      _status = "Reading code...";
    });

    try {
      final pic = await _controller!.takePicture();
      _pendingPhotoPath = pic.path; // Keep full frame for photo backup
      final croppedFile = await _ocr.cropCenterForOcr(
        pic.path,
        cropWidthFactor,
        cropHeightFactor,
      );
      final codes = await _ocr.scanImage(croppedFile, _currentSession!.digits);

      if (!mounted) return;

      if (codes.isEmpty) {
        setState(() {
          _status = "No ${_currentSession!.digits}-digit code found.";
          _busy = false;
        });
        return;
      }

      final code = codes.first;
      if (_storage.isCodeAlreadyScanned(_currentSession!.sessionId, code)) {
        setState(() {
          _status = "Duplicate found: $code";
          _pendingCode = code;
          _busy = false;
          _showNextDoneRetry = true;
        });
        return;
      }

      setState(() {
        _pendingCode = code;
        _busy = false;
        _showNextDoneRetry = true;
        _status = "Code Detected: $code";
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _status = "Scan failed: $e";
          _busy = false;
        });
    }
  }

  void _retry() => setState(() {
    _pendingCode = null;
    _pendingPhotoPath = null;
    _showNextDoneRetry = false;
    _status = "Align digits...";
  });

  Future<void> _next() async {
    await _savePendingItem();
  }

  Future<void> _savePendingItem() async {
    if (_currentSession == null || _pendingCode == null) return;

    final order = _countSaved + 1;
    final now = DateTime.now();

    // Compress and save photo in background (non-blocking for UX)
    String? savedPhotoPath;
    if (_pendingPhotoPath != null) {
      savedPhotoPath = await ExportService.saveCardPhoto(
        _pendingPhotoPath!,
        _currentSession!.sessionId,
        order,
      );
    }

    final item = ScanItem(
      sessionId: _currentSession!.sessionId,
      order: order,
      cardName: _currentSession!.cardName,
      amount: _currentSession!.amount,
      scannedNumber: _pendingCode!,
      state: "Inactive",
      scanDateTime: now,
      expirationDateTime: now.add(const Duration(days: 3)),
      photoPath: savedPhotoPath,
    );

    await _storage.addItem(item);

    final updatedSession = ScanSession(
      sessionId: _currentSession!.sessionId,
      cardName: _currentSession!.cardName,
      amount: _currentSession!.amount,
      digits: _currentSession!.digits,
      isActive: true,
      count: order,
      createdAt: _currentSession!.createdAt,
      lastUpdatedAt: now,
    );
    await _storage.saveSession(updatedSession);

    // Vibrate on success
    HapticFeedback.mediumImpact();

    // Show success overlay temporarily
    setState(() {
      _currentSession = updatedSession;
      _countSaved = order;
      _pendingCode = null;
      _pendingPhotoPath = null;
      _showNextDoneRetry = false;
      _status = "Success: Card #$order saved.";
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text("Card Saved Successfully!"),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _done() async {
    if (_pendingCode != null) await _savePendingItem();
    if (_currentSession == null) return;

    final items = _storage.getItemsForSession(_currentSession!.sessionId);
    if (items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Session is empty.")));
      return;
    }

    final path = await _export.exportSessionToTxt(_currentSession!, items);
    final zipPath = await _export.exportSessionToZip(_currentSession!, items);
    final finalSession = ScanSession(
      sessionId: _currentSession!.sessionId,
      cardName: _currentSession!.cardName,
      amount: _currentSession!.amount,
      digits: _currentSession!.digits,
      isActive: false,
      count: items.length,
      createdAt: _currentSession!.createdAt,
      lastUpdatedAt: DateTime.now(),
      txtPath: path,
      zipPath: zipPath,
    );
    await _storage.saveSession(finalSession);

    if (_torchEnabled) await _toggleTorch();

    setState(() {
      _sessionActive = false;
      _currentSession = null;
      _pendingCode = null;
      _pendingPhotoPath = null;
      _showNextDoneRetry = false;
      _countSaved = 0;
      _status = "Session Complete. Total: ${items.length}";
    });

    widget.onGoHistory();
  }

  Future<void> _cancelSession() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("End Session?"),
        content: const Text(
          "Are you sure you want to stop? All scanned cards are saved in history.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Resume"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("End Now"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (_currentSession != null) {
      // Generate export files if there are scanned cards
      String? txtPath;
      String? zipPath;
      final items = _storage.getItemsForSession(_currentSession!.sessionId);
      if (items.isNotEmpty) {
        txtPath = await _export.exportSessionToTxt(_currentSession!, items);
        zipPath = await _export.exportSessionToZip(_currentSession!, items);
      }

      final cancelled = ScanSession(
        sessionId: _currentSession!.sessionId,
        cardName: _currentSession!.cardName,
        amount: _currentSession!.amount,
        digits: _currentSession!.digits,
        isActive: false,
        count: _countSaved,
        createdAt: _currentSession!.createdAt,
        lastUpdatedAt: DateTime.now(),
        txtPath: txtPath,
        zipPath: zipPath,
      );
      await _storage.saveSession(cancelled);
    }
    if (_torchEnabled) await _toggleTorch();
    setState(() {
      _sessionActive = false;
      _currentSession = null;
      _status = "Session ended.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _sessionActive
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    "Card Scanner Pro",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  Text(
                    "${_currentSession?.cardName} | ${_currentSession?.amount} DA",
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              )
            : const Text("Card Scanner Pro"),
        actions: [
          if (_sessionActive)
            IconButton(
              icon: const Icon(
                Icons.stop_circle_rounded,
                color: Colors.redAccent,
                size: 28,
              ),
              onPressed: _cancelSession,
            ),
        ],
      ),
      body: !_sessionActive
          ? ScanStartCard(onStart: _startSession, status: _status)
          : (_controller == null)
          ? const Center(child: CircularProgressIndicator())
          : ScanCameraView(
              initializing: _initializingCamera,
              controller: _controller!,
              status: _status,
              busy: _busy,
              torchEnabled: _torchEnabled,
              torchAvailable: _torchAvailable,
              countSaved: _countSaved,
              pendingCode: _pendingCode,
              showNextDoneRetry: _showNextDoneRetry,
              onScan: _scanOnce,
              onNext: _next,
              onDone: _done,
              onRetry: _retry,
              onToggleTorch: _toggleTorch,
            ),
    );
  }
}

class CardSelection {
  final String name;
  final int amount;
  final int digits;
  CardSelection({
    required this.name,
    required this.amount,
    required this.digits,
  });
}
