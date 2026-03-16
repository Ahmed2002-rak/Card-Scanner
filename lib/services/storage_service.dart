import "package:hive_flutter/hive_flutter.dart";
import "../models/card_type.dart";
import "../models/scan_session.dart";
import "../models/scan_item.dart";

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late Box<Map> _cardTypesBox;
  late Box<Map> _sessionsBox;
  late Box<Map> _itemsBox;

  Box<Map> get itemsBox => _itemsBox;
  Box<Map> get sessionsBox => _sessionsBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _cardTypesBox = await Hive.openBox<Map>("card_types");
    _sessionsBox = await Hive.openBox<Map>("scan_sessions");
    _itemsBox = await Hive.openBox<Map>("scan_items");
    await seedDefaultCardTypes();
  }

  // Card Types
  List<CardType> getCardTypes() {
    return _cardTypesBox.values.map((m) => CardType.fromMap(m)).toList();
  }

  Future<void> addCardType(CardType type) async {
    await _cardTypesBox.add(type.toMap());
  }

  Future<void> seedDefaultCardTypes() async {
    if (_cardTypesBox.isNotEmpty) return;
    final defaults = [
      CardType(name: "CRT ADSL", digits: 15, amounts: [500, 1000, 1500, 2000, 3000]),
      CardType(name: "CRT 4G", digits: 15, amounts: [500, 1000, 1500, 2000]),
      CardType(name: "CRT MOBILIS", digits: 15, amounts: [500, 1000, 1500, 2000]),
      CardType(name: "CRT DJEZZY", digits: 15, amounts: [500, 1000, 1500, 2000]),
      CardType(name: "CRT OREDO", digits: 15, amounts: [500, 1000, 1500, 2000]),
    ];
    for (var type in defaults) {
      await addCardType(type);
    }
  }

  // Sessions
  List<ScanSession> getSessions() {
    return _sessionsBox.values.map((m) => ScanSession.fromMap(m)).toList();
  }

  ScanSession? getActiveSession() {
    for (final m in _sessionsBox.values) {
      if (m["isActive"] == true) return ScanSession.fromMap(m);
    }
    return null;
  }

  Future<void> saveSession(ScanSession session) async {
    dynamic key;
    for (int i = 0; i < _sessionsBox.length; i++) {
      if (_sessionsBox.getAt(i)?["sessionId"] == session.sessionId) {
        key = _sessionsBox.keyAt(i);
        break;
      }
    }
    if (key != null) {
      await _sessionsBox.put(key, session.toMap());
    } else {
      await _sessionsBox.add(session.toMap());
    }
  }

  // Items
  List<ScanItem> getItemsForSession(String sessionId) {
    return _itemsBox.values
        .where((m) => m["sessionId"] == sessionId)
        .map((m) => ScanItem.fromMap(m))
        .toList();
  }

  Future<void> addItem(ScanItem item) async {
    await _itemsBox.add(item.toMap());
  }

  bool isCodeAlreadyScanned(String sessionId, String code) {
    return _itemsBox.values.any((m) => m["sessionId"] == sessionId && m["scannedNumber"] == code);
  }
}
