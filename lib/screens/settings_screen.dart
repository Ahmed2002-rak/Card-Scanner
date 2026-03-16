import "package:flutter/material.dart";
import "package:hive_flutter/hive_flutter.dart";
import "../services/storage_service.dart";
import "../widgets/add_card_type_dialog.dart";

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();
    final box = Hive.box<Map>("card_types");

    return Scaffold(
      appBar: AppBar(
        title: const Text("App Settings"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 28),
            onPressed: () => showAddCardTypeDialog(context),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Map> b, _) {
          final items = storage.getCardTypes();
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.credit_card_off_rounded, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text("No card configurations yet."),
                  TextButton(
                    onPressed: () => showAddCardTypeDialog(context),
                    child: const Text("Add your first card"),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final type = items[i];
              final dynamic key = b.keyAt(i);

              return Card(
                elevation: 0,
                color: Colors.grey.shade100,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: const Icon(Icons.sim_card_rounded),
                  ),
                  title: Text(type.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Amounts: ${type.amounts.join(', ')} DA\nDigits: ${type.digits}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                    onPressed: () async {
                      final bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Delete configuration?"),
                          content: Text("Are you sure you want to delete ${type.name}?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
                          ],
                        ),
                      );
                      if (confirm == true) await b.delete(key);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
