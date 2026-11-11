import 'package:carservice_business/core/utils/result.dart';

/// `PaymentAccountDto` (`lib/payment-account-service.ts`): a tenant-defined
/// payment method — «Бэлэн» (one per tenant, created automatically),
/// bank account («Данс») or POS terminal.
enum PaymentAccountType {
  cash('CASH', 'Бэлэн'),
  bankAccount('BANK_ACCOUNT', 'Данс'),
  pos('POS', 'POS');

  const PaymentAccountType(this.wire, this.label);
  final String wire;
  final String label;

  static PaymentAccountType? tryParse(Object? value) {
    for (final t in values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}

class PaymentAccount {
  final String id;
  final PaymentAccountType type;
  final String name;

  /// Full number; null for CASH.
  final String? accountNumber;
  final String? terminalId;
  final String? merchantId;
  final bool isTest;
  final bool isActive;

  const PaymentAccount({
    required this.id,
    required this.type,
    required this.name,
    this.accountNumber,
    this.terminalId,
    this.merchantId,
    this.isTest = false,
    this.isActive = true,
  });

  bool get isCash => type == PaymentAccountType.cash;
  bool get isPos => type == PaymentAccountType.pos;

  /// Same as the web's `paymentAccountHint`: «TID …» for POS when set,
  /// otherwise the account number.
  String? get hint {
    final tid = terminalId?.trim();
    if (isPos && tid != null && tid.isNotEmpty) return 'TID $tid';
    final number = accountNumber?.replaceAll(RegExp(r'\s+'), '') ?? '';
    return number.isEmpty ? null : number;
  }

  factory PaymentAccount.fromJson(Map<String, dynamic> json) {
    final type = PaymentAccountType.tryParse(json['type']);
    final id = json['id'];
    if (type == null || id is! String || id.isEmpty) {
      throw const FormatException('Төлбөрийн арга буруу байна.');
    }
    String? opt(Object? v) => v is String && v.isNotEmpty ? v : null;
    return PaymentAccount(
      id: id,
      type: type,
      name: opt(json['name']) ?? type.label,
      accountNumber: opt(json['accountNumber']),
      terminalId: opt(json['terminalId']),
      merchantId: opt(json['merchantId']),
      isTest: json['isTest'] == true,
      isActive: json['isActive'] != false,
    );
  }
}

/// Bank-name suggestions of the web form (`BANK_NAME_SUGGESTIONS`).
const paymentAccountNameSuggestions = <String>[
  'Хаан банк',
  'Голомт банк',
  'Худалдаа хөгжлийн банк',
  'Төрийн банк',
  'Хас банк',
  'Капитрон банк',
  'Ариг банк',
  'Богд банк',
  'Тээвэр хөгжлийн банк',
  'Үндэсний хөрөнгө оруулалтын банк',
  'Чингис хаан банк',
];

/// Editable fields. On create `type` is BANK_ACCOUNT or POS; on update it is
/// immutable and not sent. CASH accepts only `name`.
class PaymentAccountDraft {
  final PaymentAccountType type;
  final String name;
  final String? accountNumber;
  final String? terminalId;
  final String? merchantId;
  final bool isTest;

  const PaymentAccountDraft({
    required this.type,
    required this.name,
    this.accountNumber,
    this.terminalId,
    this.merchantId,
    this.isTest = false,
  });

  Map<String, dynamic> toCreateJson() => {
    'type': type.wire,
    'name': name.trim(),
    'accountNumber': accountNumber?.trim() ?? '',
    if (type == PaymentAccountType.pos) ...{
      'terminalId': _blankToNull(terminalId),
      'merchantId': _blankToNull(merchantId),
      'isTest': isTest,
    },
  };

  Map<String, dynamic> toUpdateJson() => {
    'name': name.trim(),
    if (type != PaymentAccountType.cash)
      'accountNumber': accountNumber?.trim() ?? '',
    if (type == PaymentAccountType.pos) ...{
      'terminalId': _blankToNull(terminalId),
      'merchantId': _blankToNull(merchantId),
      'isTest': isTest,
    },
  };

  static String? _blankToNull(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}

/// Contract over `/api/v1/payment-accounts*` — every call needs
/// `cash.manage`. Server errors keep `code`/`fieldErrors`:
/// `PAYMENT_ACCOUNT_INVALID` (422, field errors), `PAYMENT_ACCOUNT_DUPLICATE`
/// (409), `PAYMENT_ACCOUNT_IN_USE` (409 on delete — deactivate instead),
/// `PAYMENT_ACCOUNT_NOT_FOUND` (404).
abstract interface class PaymentAccountsRepository {
  /// `GET /payment-accounts?includeInactive=1`.
  Future<Result<List<PaymentAccount>>> list({bool includeInactive = true});

  /// `POST /payment-accounts`.
  Future<Result<PaymentAccount>> create(PaymentAccountDraft draft);

  /// `PATCH /payment-accounts/[id]` with the editable fields.
  Future<Result<PaymentAccount>> update(String id, PaymentAccountDraft draft);

  /// `PATCH /payment-accounts/[id] {isActive}`.
  Future<Result<PaymentAccount>> setActive(String id, bool isActive);

  /// `DELETE /payment-accounts/[id]`.
  Future<Result<void>> delete(String id);
}
