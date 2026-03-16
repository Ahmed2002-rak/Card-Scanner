import "dart:io";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "../models/scan_session.dart";
import "../models/scan_item.dart";
import "../utils/date_formatter.dart";

class ExportService {
  Future<String> exportSessionToTxt(ScanSession session, List<ScanItem> items) async {
    final cardName = session.cardName;
    final amount = session.amount;

    items.sort((a, b) => a.order.compareTo(b.order));

    final lines = items.map((m) {
      final scanStr = formatDateTime(m.scanDateTime);
      final expStr = formatDateTime(m.expirationDateTime);
      // {order}|{cardName}||{scannedNumber}|{amount}|{expiration}|Désactivé|{scanDate}||
      return "${m.order}|$cardName||${m.scannedNumber}|$amount|$expStr|${m.state}|$scanStr||";
    }).join("\n");

    final dir = await getApplicationDocumentsDirectory();
    final safeName = cardName.replaceAll(RegExp(r"[^a-zA-Z0-9_\-]"), "_");
    final filePath = p.join(dir.path, "${safeName}_${amount}_${session.sessionId}.txt");

    await File(filePath).writeAsString(lines);
    return filePath;
  }
}
