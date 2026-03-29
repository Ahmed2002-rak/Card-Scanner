class CardType {
  final String name;
  final String
  exportName; // Name used in the exported TXT file (e.g. "CRT MOBILIS")
  final int digits;
  final List<int> amounts;

  CardType({
    required this.name,
    this.exportName = '',
    required this.digits,
    required this.amounts,
  });

  Map<String, dynamic> toMap() => {
    "name": name,
    "exportName": exportName,
    "digits": digits,
    "amounts": amounts,
  };

  factory CardType.fromMap(Map map) => CardType(
    name: map["name"] ?? "",
    exportName: map["exportName"] ?? "",
    digits: map["digits"] ?? 15,
    amounts: List<int>.from(map["amounts"] ?? []),
  );
}
