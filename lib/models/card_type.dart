class CardType {
  final String name;
  final int digits;
  final List<int> amounts;

  CardType({required this.name, required this.digits, required this.amounts});

  Map<String, dynamic> toMap() => {
    "name": name,
    "digits": digits,
    "amounts": amounts,
  };

  factory CardType.fromMap(Map map) => CardType(
    name: map["name"] ?? "",
    digits: map["digits"] ?? 15,
    amounts: List<int>.from(map["amounts"] ?? []),
  );
}
