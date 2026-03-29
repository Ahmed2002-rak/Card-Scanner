import "dart:io";
import "dart:typed_data";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:image/image.dart" as img;
import "../models/scan_session.dart";
import "../models/scan_item.dart";
import "../utils/date_formatter.dart";
import "storage_service.dart";

class ExportService {
  // Fallback mapping for old data that doesn't have exportName on the card type
  static const Map<String, String> _exportNameMap = {
    "Mobilis": "CRT MOBILIS",
    "Djezzy": "CRT DJEZZY",
    "Ooredoo": "CRT OREDO",
    "Algérie Télécom ADSL": "CRT ADSL",
    "Algérie Télécom 4G": "CRT 4G",
  };

  /// Builds the base filename: CardType_AmountDA_DD-MM-YYYY_HHhMM
  String _buildBaseFilename(ScanSession session) {
    final safeName = session.cardName.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "_");
    final d = session.createdAt;
    final date = "${_pad2(d.day)}-${_pad2(d.month)}-${d.year}";
    final time = "${_pad2(d.hour)}h${_pad2(d.minute)}";
    return "${safeName}_${session.amount}DA_${date}_$time";
  }

  String _pad2(int v) => v.toString().padLeft(2, '0');

  /// Get the export name for TXT file content
  String _getExportName(String cardName) {
    final storage = StorageService();
    final cardTypes = storage.getCardTypes();
    final match = cardTypes.where((t) => t.name == cardName);
    if (match.isNotEmpty && match.first.exportName.isNotEmpty) {
      return match.first.exportName;
    }
    return _exportNameMap[cardName] ?? cardName;
  }

  /// Export session as TXT (same content as V1, new filename)
  Future<String> exportSessionToTxt(
    ScanSession session,
    List<ScanItem> items,
  ) async {
    items.sort((a, b) => a.order.compareTo(b.order));
    final exportName = _getExportName(session.cardName);

    final buffer = StringBuffer();
    for (var m in items) {
      final scanStr = formatDateTime(m.scanDateTime);
      final expStr = formatDateTime(m.expirationDateTime);
      buffer.write(
        "${m.order}|$exportName||${m.scannedNumber}|${m.amount}|$expStr|Désactivé|$scanStr||\n",
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final baseName = _buildBaseFilename(session);
    final filePath = p.join(dir.path, "$baseName.txt");

    await File(filePath).writeAsString(buffer.toString());
    return filePath;
  }

  /// Export session as ZIP with card photos
  Future<String?> exportSessionToZip(
    ScanSession session,
    List<ScanItem> items,
  ) async {
    items.sort((a, b) => a.order.compareTo(b.order));

    // Only create ZIP if there are photos
    final itemsWithPhotos = items
        .where((i) => i.photoPath != null && i.photoPath!.isNotEmpty)
        .toList();
    if (itemsWithPhotos.isEmpty) return null;

    final dir = await getApplicationDocumentsDirectory();
    final baseName = _buildBaseFilename(session);
    final zipDir = Directory(p.join(dir.path, "zip_temp_$baseName"));

    // Clean up any previous temp dir
    if (await zipDir.exists()) await zipDir.delete(recursive: true);
    await zipDir.create(recursive: true);

    // Build index.txt inside the zip folder
    final indexBuffer = StringBuffer();
    indexBuffer.writeln("Order | Recharge Code");
    indexBuffer.writeln("------|--------------");

    int photoCount = 0;
    for (var item in items) {
      indexBuffer.writeln("${item.order}     | ${item.scannedNumber}");

      // Copy photo if it exists
      if (item.photoPath != null && item.photoPath!.isNotEmpty) {
        final photoFile = File(item.photoPath!);
        if (await photoFile.exists()) {
          final destName = "${item.scannedNumber}_${item.order}.jpg";
          await photoFile.copy(p.join(zipDir.path, destName));
          photoCount++;
        }
      }
    }

    await File(
      p.join(zipDir.path, "index.txt"),
    ).writeAsString(indexBuffer.toString());

    if (photoCount == 0) {
      await zipDir.delete(recursive: true);
      return null;
    }

    // Create ZIP using dart:io (tar-like approach with ZipEncoder)
    final zipPath = p.join(dir.path, "$baseName.zip");
    await _createZipFromDir(zipDir, zipPath);

    // Clean up temp dir
    await zipDir.delete(recursive: true);

    return zipPath;
  }

  /// Create a ZIP file from a directory using the archive package
  Future<void> _createZipFromDir(Directory sourceDir, String zipPath) async {
    // Use simple concatenation approach since archive package may not be available
    // We'll use a process-based approach or manual ZIP creation
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    await for (final entity in sourceDir.list()) {
      if (entity is File) {
        encoder.addFile(entity, p.basename(entity.path));
      }
    }
    encoder.close();
  }

  /// Compress and save a card photo to permanent storage
  /// Returns the saved file path
  static Future<String?> saveCardPhoto(
    String sourcePath,
    String sessionId,
    int order,
  ) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Resize if too large (max 1200px wide) and compress to ~200KB
      img.Image resized = decoded;
      if (decoded.width > 1200) {
        resized = img.copyResize(decoded, width: 1200);
      }

      final compressed = Uint8List.fromList(
        img.encodeJpg(resized, quality: 60),
      );

      final dir = await getApplicationDocumentsDirectory();
      final photoDir = Directory(p.join(dir.path, "card_photos"));
      if (!await photoDir.exists()) await photoDir.create(recursive: true);

      final photoPath = p.join(photoDir.path, "${sessionId}_$order.jpg");
      await File(photoPath).writeAsBytes(compressed);

      return photoPath;
    } catch (e) {
      return null;
    }
  }
}

/// Simple ZIP file encoder using dart's archive capabilities
class ZipFileEncoder {
  late RandomAccessFile _raf;
  final List<_ZipEntry> _entries = [];

  void create(String path) {
    _raf = File(path).openSync(mode: FileMode.write);
  }

  void addFile(File file, String name) {
    final data = file.readAsBytesSync();
    final offset = _raf.positionSync();

    // Local file header
    _raf.writeFromSync([0x50, 0x4B, 0x03, 0x04]); // signature
    _raf.writeFromSync(_uint16(20)); // version needed
    _raf.writeFromSync(_uint16(0)); // flags
    _raf.writeFromSync(_uint16(0)); // compression (store)
    _raf.writeFromSync(_uint16(0)); // mod time
    _raf.writeFromSync(_uint16(0)); // mod date
    _raf.writeFromSync(_uint32(_crc32(data))); // crc32
    _raf.writeFromSync(_uint32(data.length)); // compressed size
    _raf.writeFromSync(_uint32(data.length)); // uncompressed size
    final nameBytes = name.codeUnits;
    _raf.writeFromSync(_uint16(nameBytes.length)); // name length
    _raf.writeFromSync(_uint16(0)); // extra length
    _raf.writeFromSync(nameBytes);
    _raf.writeFromSync(data);

    _entries.add(
      _ZipEntry(
        name: name,
        offset: offset,
        size: data.length,
        crc: _crc32(data),
      ),
    );
  }

  void close() {
    final centralStart = _raf.positionSync();

    for (final entry in _entries) {
      final nameBytes = entry.name.codeUnits;
      _raf.writeFromSync([0x50, 0x4B, 0x01, 0x02]); // central dir signature
      _raf.writeFromSync(_uint16(20)); // version made by
      _raf.writeFromSync(_uint16(20)); // version needed
      _raf.writeFromSync(_uint16(0)); // flags
      _raf.writeFromSync(_uint16(0)); // compression
      _raf.writeFromSync(_uint16(0)); // mod time
      _raf.writeFromSync(_uint16(0)); // mod date
      _raf.writeFromSync(_uint32(entry.crc));
      _raf.writeFromSync(_uint32(entry.size));
      _raf.writeFromSync(_uint32(entry.size));
      _raf.writeFromSync(_uint16(nameBytes.length));
      _raf.writeFromSync(_uint16(0)); // extra length
      _raf.writeFromSync(_uint16(0)); // comment length
      _raf.writeFromSync(_uint16(0)); // disk number
      _raf.writeFromSync(_uint16(0)); // internal attrs
      _raf.writeFromSync(_uint32(0)); // external attrs
      _raf.writeFromSync(_uint32(entry.offset));
      _raf.writeFromSync(nameBytes);
    }

    final centralEnd = _raf.positionSync();

    // End of central directory
    _raf.writeFromSync([0x50, 0x4B, 0x05, 0x06]);
    _raf.writeFromSync(_uint16(0)); // disk number
    _raf.writeFromSync(_uint16(0)); // central dir disk
    _raf.writeFromSync(_uint16(_entries.length));
    _raf.writeFromSync(_uint16(_entries.length));
    _raf.writeFromSync(_uint32(centralEnd - centralStart));
    _raf.writeFromSync(_uint32(centralStart));
    _raf.writeFromSync(_uint16(0)); // comment length

    _raf.closeSync();
  }

  List<int> _uint16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  List<int> _uint32(int v) => [
    v & 0xFF,
    (v >> 8) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 24) & 0xFF,
  ];

  int _crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}

class _ZipEntry {
  final String name;
  final int offset;
  final int size;
  final int crc;
  _ZipEntry({
    required this.name,
    required this.offset,
    required this.size,
    required this.crc,
  });
}
