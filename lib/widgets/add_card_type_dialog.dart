import "package:flutter/material.dart";
import "../models/card_type.dart";
import "../services/storage_service.dart";

Future<void> showAddCardTypeDialog(BuildContext context) async {
  final nameCtrl = TextEditingController();
  final amountsCtrl = TextEditingController(text: "500,1000,1500,2000");
  final digitsCtrl = TextEditingController(text: "15");

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Add card type"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: "Exact name (ex: CRT MOBILIS)"),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: amountsCtrl,
            decoration: const InputDecoration(labelText: "Amounts (comma separated)"),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: digitsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Digits length (default 15)"),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Add")),
      ],
    ),
  );

  if (ok != true) return;

  final name = nameCtrl.text.trim();
  final digits = int.tryParse(digitsCtrl.text.trim()) ?? 15;
  final amounts = amountsCtrl.text
      .split(",")
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .toSet()
      .toList()
    ..sort();

  if (name.isEmpty || amounts.isEmpty) return;

  final storage = StorageService();
  final exists = storage.getCardTypes().any((t) => t.name.toLowerCase() == name.toLowerCase());
  if (exists) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name already exists.")));
    return;
  }

  await storage.addCardType(CardType(name: name, digits: digits, amounts: amounts));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Added: $name")));
}
