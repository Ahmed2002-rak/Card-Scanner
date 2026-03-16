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

  Future<void> _shareTxt(BuildContext context) async {
    final path = _session?.txtPath ?? "";
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No TXT exported yet.")));
      return;
    }
    final f = File(path);
    if (!await f.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("TXT file not found.")));
      return;
    }
    await Share.shareXFiles([XFile(f.path)], text: "Cards export");
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
      _loadSession();
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
      );
      await _storage.saveSession(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final items = _storage.getItemsForSession(widget.sessionId);
    items.sort((a, b) => a.order.compareTo(b.order));

    return Scaffold(
      appBar: AppBar(
        title: Text("${_session!.cardName} • ${_session!.amount} DA"),
        actions: [
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
                return ListTile(
                  leading: CircleAvatar(child: Text(it.order.toString())),
                  title: Text(it.scannedNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("Tap icons to copy / modify / delete"),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: it.scannedNumber));
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copied: ${it.scannedNumber}")));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                           final newCode = await Navigator.push<String?>(
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
                          if (newCode != null) {
                            final itemsBox = _storage.itemsBox;
                            final updatedItem = ScanItem(
                              sessionId: it.sessionId,
                              order: it.order,
                              cardName: it.cardName,
                              amount: it.amount,
                              scannedNumber: newCode,
                              state: it.state,
                              scanDateTime: DateTime.now(),
                              expirationDateTime: DateTime.now().add(const Duration(days: 3)),
                            );
                            for(var key in itemsBox.keys) {
                              final val = itemsBox.get(key);
                              if (val?["sessionId"] == it.sessionId && val?["order"] == it.order) {
                                await itemsBox.put(key, updatedItem.toMap());
                                break;
                              }
                            }
                            setState(() {});
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteItem(it),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
