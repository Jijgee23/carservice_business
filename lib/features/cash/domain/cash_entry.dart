/// Thrown by the cash DTO parsers on a malformed server payload.
class CashParseException implements Exception {
  final String message;
  const CashParseException(this.message);
  @override
  String toString() => message;
}

/// Id + display name of a branch / customer / user referenced by cash data.
class CashRef {
  final String id;
  final String name;
  const CashRef(this.id, this.name);
}
