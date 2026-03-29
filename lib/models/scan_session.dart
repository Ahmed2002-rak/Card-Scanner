class ScanSession {
  final String sessionId;
  final String cardName;
  final int amount;
  final int digits;
  final bool isActive;
  final int count;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;
  final String? txtPath;
  final String? zipPath; // ZIP with photos (V1.1+)

  ScanSession({
    required this.sessionId,
    required this.cardName,
    required this.amount,
    required this.digits,
    required this.isActive,
    required this.count,
    required this.createdAt,
    required this.lastUpdatedAt,
    this.txtPath,
    this.zipPath,
  });

  Map<String, dynamic> toMap() => {
    "sessionId": sessionId,
    "cardName": cardName,
    "amount": amount,
    "digits": digits,
    "isActive": isActive,
    "count": count,
    "createdAt": createdAt.toIso8601String(),
    "lastUpdatedAt": lastUpdatedAt.toIso8601String(),
    "txtPath": txtPath,
    "zipPath": zipPath,
  };

  factory ScanSession.fromMap(Map map) => ScanSession(
    sessionId: (map["sessionId"] ?? "").toString(),
    cardName: (map["cardName"] ?? "").toString(),
    amount: (map["amount"] ?? 0) as int,
    digits: (map["digits"] ?? 15) as int,
    isActive: (map["isActive"] ?? false) as bool,
    count: (map["count"] ?? 0) as int,
    createdAt: DateTime.parse(
      (map["createdAt"] ?? DateTime.now().toIso8601String()).toString(),
    ),
    lastUpdatedAt: DateTime.parse(
      (map["lastUpdatedAt"] ?? DateTime.now().toIso8601String()).toString(),
    ),
    txtPath: map["txtPath"]?.toString(),
    zipPath: map["zipPath"]?.toString(),
  );
}
