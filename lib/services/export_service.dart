import "dart:io";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "../models/scan_session.dart";
import "../models/scan_item.dart";
import "../utils/date_formatter.dart";

class ExportService {
  // Mapping app names to the required "CRT" format for the text file content
  static const Map<String, String> _exportNameMap = {
    "Mobilis": "CRT MOBILIS",
    "Djezzy": "CRT DJEZZY",
    "Ooredoo": "CRT OREDO",
    "Algérie Télécom ADSL": "CRT ADSL",
    "Algérie Télécom 4G": "CRT 4G",
  };

  Future<String> exportSessionToTxt(
    ScanSession session,
    List<ScanItem> items,
  ) async {
    items.sort((a, b) => a.order.compareTo(b.order));

    // Get the required export name, fallback to original if not in map
    final exportName = _exportNameMap[session.cardName] ?? session.cardName;

    final buffer = StringBuffer();
    for (var m in items) {
      final scanStr = formatDateTime(m.scanDateTime);
      final expStr = formatDateTime(m.expirationDateTime);

      // {order}|{cardName}||{scannedNumber}|{amount}|{expiration}|Désactivé|{scanDate}||
      // Using exportName (e.g. CRT MOBILIS) inside the file as requested
      buffer.write(
        "${m.order}|$exportName||${m.scannedNumber}|${m.amount}|$expStr|Désactivé|$scanStr||\n",
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final safeName = session.cardName.replaceAll(
      RegExp(r"[^a-zA-Z0-9_\-]"),
      "_",
    );
    final filePath = p.join(
      dir.path,
      "${safeName}_${session.amount}_${session.sessionId}.txt",
    );

    await File(filePath).writeAsString(buffer.toString());
    return filePath;
  }
}
