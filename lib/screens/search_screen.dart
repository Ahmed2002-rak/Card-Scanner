import "dart:io";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "../models/scan_item.dart";
import "../services/storage_service.dart";

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _searchCtrl = TextEditingController();
  final _storage = StorageService();
  List<ScanItem> _results = [];
  bool _hasSearched = false;

  void _search(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    final q = query.replaceAll(RegExp(r"\s"), "").toLowerCase();
    final allItems = <ScanItem>[];

    // Search across ALL sessions
    for (final m in _storage.itemsBox.values) {
      allItems.add(ScanItem.fromMap(m));
    }

    setState(() {
      _hasSearched = true;
      _results =
          allItems
              .where((item) => item.scannedNumber.toLowerCase().contains(q))
              .toList()
            ..sort((a, b) => b.scanDateTime.compareTo(a.scanDateTime));
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Search Cards")),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _search,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "Type any part of the recharge code...",
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _search("");
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
            ),
          ),

          // Results
          Expanded(
            child: !_hasSearched
                ? _buildEmptyState()
                : _results.isEmpty
                ? _buildNoResults()
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = _results[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: item.photoPath != null
                              ? const Icon(Icons.photo_camera_rounded, size: 20)
                              : const Icon(Icons.credit_card_rounded, size: 20),
                        ),
                        title: Text(
                          item.scannedNumber,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: "monospace",
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          "${item.cardName} • ${item.amount} DA • "
                          "${item.scanDateTime.day}/${item.scanDateTime.month}/${item.scanDateTime.year}",
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openDetail(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_rounded, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "Search for any card",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Type any part of a recharge code\nto find the original card photo",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "No cards found",
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, ScanItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _CardDetailPage(item: item)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card Detail Page — photo on top, details below
// ─────────────────────────────────────────────────────────────────────────────
class _CardDetailPage extends StatelessWidget {
  final ScanItem item;
  const _CardDetailPage({required this.item});

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        item.photoPath != null &&
        item.photoPath!.isNotEmpty &&
        File(item.photoPath!).existsSync();

    return Scaffold(
      appBar: AppBar(title: const Text("Card Detail")),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo
            if (hasPhoto)
              GestureDetector(
                onTap: () => _showFullPhoto(context),
                child: Container(
                  height: 300,
                  color: Colors.black,
                  child: Image.file(File(item.photoPath!), fit: BoxFit.contain),
                ),
              )
            else
              Container(
                height: 200,
                color: Colors.grey.shade200,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.no_photography_rounded,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "No photo available",
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),

            if (hasPhoto)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Center(
                  child: Text(
                    "Tap photo to view full screen",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Details card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow(
                        "Recharge Code",
                        item.scannedNumber,
                        mono: true,
                      ),
                      const Divider(height: 24),
                      _detailRow("Card Type", item.cardName),
                      const Divider(height: 24),
                      _detailRow("Amount", "${item.amount} DA"),
                      const Divider(height: 24),
                      _detailRow(
                        "Scanned",
                        "${item.scanDateTime.day}/${item.scanDateTime.month}/${item.scanDateTime.year} "
                            "${item.scanDateTime.hour}:${item.scanDateTime.minute.toString().padLeft(2, '0')}",
                      ),
                      const Divider(height: 24),
                      _detailRow("Session", item.sessionId),
                    ],
                  ),
                ),
              ),
            ),

            // Copy button
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: item.scannedNumber));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Copied: ${item.scannedNumber}")),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text("Copy Recharge Code"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool mono = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: mono ? 18 : 16,
            fontWeight: mono ? FontWeight.bold : FontWeight.w500,
            fontFamily: mono ? "monospace" : null,
            letterSpacing: mono ? 1.5 : null,
          ),
        ),
      ],
    );
  }

  void _showFullPhoto(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              item.scannedNumber,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          body: Center(
            child: InteractiveViewer(child: Image.file(File(item.photoPath!))),
          ),
        ),
      ),
    );
  }
}
