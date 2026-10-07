import 'package:carservice_business/features/orders/domain/order.dart';

/// Receiving-bank codes and labels. Mirrors the server's `lib/banks.ts`.
class PaymentBank {
  final String code;
  final String label;
  const PaymentBank(this.code, this.label);
}

const List<PaymentBank> kPaymentBanks = [
  PaymentBank('KHAN', 'Хаан банк'),
  PaymentBank('GOLOMT', 'Голомт банк'),
  PaymentBank('TDB', 'Худалдаа хөгжлийн банк'),
  PaymentBank('STATE', 'Төрийн банк'),
  PaymentBank('XAC', 'Хас банк'),
  PaymentBank('CAPITRON', 'Капитрон банк'),
  PaymentBank('ARIG', 'Ариг банк'),
  PaymentBank('BOGD', 'Богд банк'),
  PaymentBank('TRANS', 'Тээвэр хөгжлийн банк'),
  PaymentBank('NIBANK', 'Үндэсний хөрөнгө оруулалтын банк'),
  PaymentBank('CHINGGIS', 'Чингис хаан банк'),
];

/// Label for a stored code; unknown codes display as the raw code.
String paymentBankLabel(String code) {
  for (final bank in kPaymentBanks) {
    if (bank.code == code) return bank.label;
  }
  return code;
}

/// Methods that must carry a receiving bank.
bool paymentMethodNeedsBank(OrderPaymentMethod method) =>
    method == OrderPaymentMethod.BANK_TRANSFER ||
    method == OrderPaymentMethod.CARD;

/// Result of GET /api/v1/banks. [enabledCodes] is already empty->all resolved.
class BankSettings {
  final List<String> enabledCodes;
  const BankSettings(this.enabledCodes);

  List<PaymentBank> get enabled => kPaymentBanks
      .where((bank) => enabledCodes.contains(bank.code))
      .toList(growable: false);
}
