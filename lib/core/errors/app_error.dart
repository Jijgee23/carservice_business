enum ErrorKind { network, notFound, unauthorized, forbidden, server, unknown }

/// Server refuses every user-initiated money write (any payment method) while
/// the branch has no open cash session: HTTP 409, this code and message.
abstract final class CashSessionClosedError {
  static const code = 'CASH_SESSION_CLOSED';
  static const message = 'Касс нээгээгүй байна. Эхлээд кассаа нээнэ үү.';
}

/// Reversing a payment whose ledger row is in a closed cash shift: HTTP 409.
abstract final class CashSessionEntryLockedError {
  static const code = 'CASH_SESSION_ENTRY_LOCKED';
  static const message = 'Хаагдсан ээлжийн гүйлгээг буцаах боломжгүй.';
}

class AppError implements Exception {
  final ErrorKind kind;
  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, String>? fieldErrors;

  const AppError(
    this.kind,
    this.message, {
    this.statusCode,
    this.code,
    this.fieldErrors,
  });

  bool get isCashSessionClosed => code == CashSessionClosedError.code;

  String get display => switch (kind) {
    ErrorKind.network => 'Интернет холболт байхгүй',
    ErrorKind.notFound => 'Мэдээлэл олдсонгүй',
    ErrorKind.unauthorized => 'Нэвтрэх шаардлагатай',
    ErrorKind.forbidden => message,
    ErrorKind.server => 'Серверийн алдаа гарлаа',
    ErrorKind.unknown => message,
  };
}
