import "dart:io";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:share_plus/share_plus.dart";

import "../main.dart" show cameras;
import "../models/scan_session.dart";
import "../models/scan_item.dart";
import "../services/storage_service.dart";
import "../services/export_service.dart";
import "rescan_screen.dart";

class SessionDetailsPage extends StatefulWidget {
  const SessionDetailsPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionDetailsPage> createState() => _SessionDetailsPageState();
}

class _SessionDetailsPageState extends State<SessionDetailsPage> {
  final StorageService _storage = StorageService();
  final ExportService _export = ExportService();
  ScanSession? _session;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  void _loadSession() {
    final sessions = _storage.getSessions();
    setState(() {
      _session = sessions.firstWhere((s) => s.sessionId == widget.sessionId);
    });
  }

  /// Regenerate TXT + ZIP after any card edit or delete
  Future<void> _regenerateExports() async {
    if (_session == null) return;
    final items = _storage.getItemsForSession(widget.sessionId);
    if (items.isEmpty) return;

    final txtPath = await _export.exportSessionToTxt(_session!, items);
    final zipPath = await _export.exportSessionToZip(_session!, items);

    final updated = ScanSession(
      sessionId: _session!.sessionId,
      cardName: _session!.cardName,
      amount: _session!.amount,
      digits: _session!.digits,
      isActive: _session!.isActive,
      count: items.length,
      createdAt: _session!.createdAt,
      lastUpdatedAt: DateTime.now(),
      txtPath: txtPath,
      zipPath: zipPath,
    );
    await _storage.saveSession(updated);
    _loadSession();
  }

  /// If TXT/ZIP files are missing or deleted, regenerate them on demand.
  /// This handles: user left app without pressing Done, files got deleted, etc.
  /// Blocks sharing if session is still active (user should finish first).
  Future<bool> _ensureExported(BuildContext context) async {
    if (_session == null) return false;

    // Block sharing while session is still active
    if (_session!.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Finish scanning first — press Done or Cancel in the Scan tab.")),
      );
      return false;
    }

    final items = _storage.getItemsForSession(widget.sessionId);
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No cards in this session.")),
      );
      return false;
    }

    bool needsRegen = false;

    // Check if TXT is missing or file deleted from disk
    if (_session!.txtPath == null ||
        _session!.txtPath!.isEmpty ||
        !await File(_session!.txtPath!).exists()) {
      needsRegen = true;
    }

    // Check if ZIP is missing or file deleted from disk
    if (_session!.zipPath == null ||
        _session!.zipPath!.isEmpty ||
        !await File(_session!.zipPath!).exists()) {
      needsRegen = true;
    }

    if (needsRegen) {
      await _regenerateExports();
    }

    return true;
  }

  Future<void> _shareTxt(BuildContext context) async {
    if (!await _ensureExported(context)) return;
    final path = _session?.txtPath ?? "";
    if (path.isEmpty || !await File(path).exists()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to generate TXT file.")));
      return;
    }
    await Share.shareXFiles([XFile(path)], text: "Cards export");
  }

  Future<void> _shareZip(BuildContext context) async {
    if (!await _ensureExported(context)) return;
    final path = _session?.zipPath ?? "";
    if (path.isEmpty || !await File(path).exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No photos available for this session.")),
      );
      return;
    }
    await Share.shareXFiles([XFile(path)], text: "Cards photo archive");
  }

  Future<void> _shareBoth(BuildContext context) async {
    if (!await _ensureExported(context)) return;
    final files = <XFile>[];

    final txtPath = _session?.txtPath ?? "";
    if (txtPath.isNotEmpty && await File(txtPath).exists()) {
      files.add(XFile(txtPath));
    }

    final zipPath = _session?.zipPath ?? "";
    if (zipPath.isNotEmpty && await File(zipPath).exists()) {
      files.add(XFile(zipPath));
    }

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No files to share.")));
      return;
    }

    await Share.shareXFiles(files, text: "Cards export");
  }

  Future<void> _deleteItem(ScanItem item) async {
    final itemsBox = _storage.itemsBox;
    dynamic keyToDelete;
    for(var key in itemsBox.keys) {
      final val = itemsBox.get(key);
      if (val?["sessionId"] == item.sessionId && val?["order"] == item.order) {
        keyToDelete = key;
        break;
      }
    }
    if (keyToDelete != null) {
      await itemsBox.delete(keyToDelete);
      await _renumberOrders();
      await _regenerateExports();
    }
  }

  Future<void> _renumberOrders() async {
    final itemsBox = _storage.itemsBox;
    final items = _storage.getItemsForSession(widget.sessionId);
    items.sort((a, b) => a.order.compareTo(b.order));
    
    for (int i = 0; i < items.length; i++) {
      final oldItem = items[i];
      final newItem = ScanItem(
        sessionId: oldItem.sessionId,
        order: i + 1,
        cardName: oldItem.cardName,
        amount: oldItem.amount,
        scannedNumber: oldItem.scannedNumber,
        state: oldItem.state,
        scanDateTime: oldItem.scanDateTime,
        expirationDateTime: oldItem.expirationDateTime,
        photoPath: oldItem.photoPath,
      );
      
      for(var key in itemsBox.keys) {
        final val = itemsBox.get(key);
        if (val?["sessionId"] == oldItem.sessionId && val?["order"] == oldItem.order) {
          await itemsBox.put(key, newItem.toMap());
          break;
        }
      }
    }

    if (_session != null) {
      final updated = ScanSession(
        sessionId: _session!.sessionId,
        cardName: _session!.cardName,
        amount: _session!.amount,
        digits: _session!.digits,
        isActive: _session!.isActive,
        count: items.length,
        createdAt: _session!.createdAt,
        lastUpdatedAt: DateTime.now(),
        txtPath: _session!.txtPath,
        zipPath: _session!.zipPath,
      );
      await _storage.saveSession(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final items = _storage.getItemsForSession(widget.sessionId);
    items.sort((a, b) => a.order.compareTo(b.order));
    final hasZip = _session!.zipPath != null && _session!.zipPath!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text("${_session!.cardName} \u2022 ${_session!.amount} DA"),
        actions: [
          if (hasZip)
            PopupMenuButton<String>(
              icon: const Icon(Icons.share),
              tooltip: "Share",
              onSelected: (v) {
                if (v == "txt") _shareTxt(context);
                if (v == "zip") _shareZip(context);
                if (v == "both") _shareBoth(context);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: "txt", child: Text("Share TXT only")),
                const PopupMenuItem(value: "zip", child: Text("Share Photos ZIP")),
                const PopupMenuItem(value: "both", child: Text("Share Both")),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => _shareTxt(context),
              tooltip: "Share TXT",
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text("No cards in this session."))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final it = items[i];
                final hasPhoto = it.photoPath != null &&
                    it.photoPath!.isNotEmpty &&
                    File(it.photoPath!).existsSync();

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: hasPhoto
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: hasPhoto
                        ? const Icon(Icons.photo_camera_rounded, size: 18)
                        : Text(it.order.toString()),
                  ),
                  title: Text(it.scannedNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(hasPhoto ? "Has photo • Tap icons to manage" : "No photo • Tap icons to manage"),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      if (hasPhoto)
                        IconButton(
                          icon: const Icon(Icons.photo_rounded, size: 20),
                          tooltip: "View photo",
                          onPressed: () => _viewPhoto(context, it),
                        ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: it.scannedNumber));
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copied: ${it.scannedNumber}")));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () async {
                           final result = await Navigator.push<RescanResult?>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RescanPage(
                                cameras: cameras,
                                sessionId: widget.sessionId,
                                oldCode: it.scannedNumber,
                                digits: _session!.digits,
                              ),
                            ),
                          );
                          if (result != null) {
                            // Save new photo if available
                            String? newPhotoPath = it.photoPath;
                            if (result.photoPath != null) {
                              final saved = await ExportService.saveCardPhoto(
                                result.photoPath!, it.sessionId, it.order,
                              );
                              if (saved != null) newPhotoPath = saved;
                            }

                            final itemsBox = _storage.itemsBox;
                            final updatedItem = ScanItem(
                              sessionId: it.sessionId,
                              order: it.order,
                              cardName: it.cardName,
                              amount: it.amount,
                              scannedNumber: result.code,
                              state: it.state,
                              scanDateTime: DateTime.now(),
                              expirationDateTime: DateTime.now().add(const Duration(days: 3)),
                              photoPath: newPhotoPath,
                            );
                            for(var key in itemsBox.keys) {
                              final val = itemsBox.get(key);
                              if (val?["sessionId"] == it.sessionId && val?["order"] == it.order) {
                                await itemsBox.put(key, updatedItem.toMap());
                                break;
                              }
                            }
                            await _regenerateExports();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deleteItem(it),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _viewPhoto(BuildContext context, ScanItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text("Card #${item.order} • ${item.scannedNumber}",
                style: const TextStyle(fontSize: 14)),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(File(item.photoPath!)),
            ),
          ),
        ),
      ),
    );
  }
}
