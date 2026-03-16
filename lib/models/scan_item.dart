class ScanItem {
  final String sessionId;
  final int order;
  final String cardName;
  final int amount;
  final String scannedNumber;
  final String state;
  final DateTime scanDateTime;
  final DateTime expirationDateTime;

  ScanItem({
    required this.sessionId,
    required this.order,
    required this.cardName,
    required this.amount,
    required this.scannedNumber,
    required this.state,
    required this.scanDateTime,
    required this.expirationDateTime,
  });

  Map<String, dynamic> toMap() => {
    "sessionId": sessionId,
    "order": order,
    "cardName": cardName,
    "amount": amount,
    "scannedNumber": scannedNumber,
    "state": state,
    "scanDateTime": scanDateTime.toIso8601String(),
    "expirationDateTime": expirationDateTime.toIso8601String(),
  };

  factory ScanItem.fromMap(Map map) => ScanItem(
    sessionId: (map["sessionId"] ?? "").toString(),
    order: (map["order"] ?? 0) as int,
    cardName: (map["cardName"] ?? "").toString(),
    amount: (map["amount"] ?? 0) as int,
    scannedNumber: (map["scannedNumber"] ?? "").toString(),
    state: (map["state"] ?? "Inactive").toString(),
    scanDateTime: DateTime.parse((map["scanDateTime"] ?? DateTime.now().toIso8601String()).toString()),
    expirationDateTime: DateTime.parse((map["expirationDateTime"] ?? DateTime.now().toIso8601String()).toString()),
  );
}
