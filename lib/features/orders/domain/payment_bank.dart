import 'package:carservice_business/features/orders/domain/order.dart';

/// A tenant payment account from GET /api/v1/banks `accounts`.
/// [isPos] accounts are the CARD options and [isTransfer] ones the
/// BANK_TRANSFER options. [isCash] accounts (a named cash method such as
/// «Бэлнээр») are neither: cash keeps its own «Бэлэн» row.
class PaymentBank {
  final String id;
  final String label;
  final bool isPos;
  final bool isCash;

  /// The full account number staff read to the customer. Empty for cash and
  /// POS accounts, and from older servers that send only [maskedNumber].
  final String accountNumber;
  final String maskedNumber;
  final String? terminalId;
  final bool isTest;
  const PaymentBank({
    required this.id,
    required this.label,
    this.isPos = false,
    this.isCash = false,
    this.accountNumber = '',
    this.maskedNumber = '',
    this.terminalId,
    this.isTest = false,
  });

  factory PaymentBank.fromJson(Map<String, dynamic> json) => PaymentBank(
    id: json['id'] as String,
    label: json['name'] as String,
    isPos: json['type'] == 'POS',
    isCash: json['type'] == 'CASH',
    accountNumber: (json['accountNumber'] as String?) ?? '',
    maskedNumber: (json['accountNumberMasked'] as String?) ?? '',
    terminalId: json['terminalId'] as String?,
    isTest: json['isTest'] == true,
  );

  /// The number to show: the full one, else the masked one, else null.
  String? get displayNumber => accountNumber.isNotEmpty
      ? accountNumber
      : maskedNumber.isEmpty
      ? null
      : maskedNumber;

  /// A receiving bank account (server type BANK_ACCOUNT).
  bool get isTransfer => !isPos && !isCash;
}

/// Label for a stored account id from the loaded [banks]; unknown ids display as the raw id.
String paymentBankLabelIn(List<PaymentBank> banks, String? id) {
  if (id == null) return '';
  for (final bank in banks) {
    if (bank.id == id) return bank.label;
  }
  return id;
}

/// Methods that must carry a receiving account.
bool paymentMethodNeedsBank(OrderPaymentMethod method) =>
    method == OrderPaymentMethod.BANK_TRANSFER ||
    method == OrderPaymentMethod.CARD;

/// Result of GET /api/v1/banks: active accounts only (the legacy `banks` / `enabledBanks` fields are ignored).
class BankSettings {
  final List<PaymentBank> accounts;
  const BankSettings(this.accounts);

  List<PaymentBank> get transferAccounts =>
      accounts.where((a) => a.isTransfer).toList(growable: false);
  List<PaymentBank> get posAccounts =>
      accounts.where((a) => a.isPos).toList(growable: false);
}
