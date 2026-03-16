import "package:flutter/material.dart";
import "package:hive_flutter/hive_flutter.dart";
import "../services/storage_service.dart";
import "../models/scan_session.dart";
import "session_details_screen.dart";

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();
    final sessionsBox = Hive.box<Map>("scan_sessions");

    return Scaffold(
      appBar: AppBar(title: const Text("History")),
      body: ValueListenableBuilder(
        valueListenable: sessionsBox.listenable(),
        builder: (context, Box<Map> b, _) {
          final sessions = storage.getSessions().reversed.toList();
          if (sessions.isEmpty) {
            return const Center(
              child: Text("No sessions yet. Go to Scan and start."),
            );
          }

          return ListView.separated(
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = sessions[i];
              return ListTile(
                title: Text(
                  "${s.cardName} • ${s.amount} DA${s.isActive ? " (active)" : ""}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text("${s.createdAt.toLocal().toString().split(".")[0]} • ${s.count} cards"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionDetailsPage(sessionId: s.sessionId),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
