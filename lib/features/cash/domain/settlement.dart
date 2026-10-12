import 'package:intl/intl.dart';

import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/orders/domain/order.dart';

/// Server error codes of the postpaid settlement («Тооцоо нийлэх») API.
abstract final class SettlementErrorCodes {
  static const amountChanged = 'SETTLEMENT_AMOUNT_CHANGED';
  static const orderInvalid = 'SETTLEMENT_ORDER_INVALID';
}

/// Money helpers: amounts are Decimal strings; sums run on integer cents so
/// the total never drifts with float error.
int moneyToCents(String value) => ((double.tryParse(value) ?? 0) * 100).round();

String centsToMoney(int cents) {
  final whole = cents ~/ 100;
  final frac = (cents % 100).abs();
  if (frac == 0) return '$whole';
  final digits = frac
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0$'), '');
  return '$whole.$digits';
}

/// One postpaid order that can still be settled.
class EligibleOrder {
  final String id;
  final String number;
  final String? plate;
  final DateTime? completedAt;
  final String totalAmount;
  final String paidAmount;
  final String outstanding;
  const EligibleOrder({
    required this.id,
    required this.number,
    this.plate,
    this.completedAt,
    required this.totalAmount,
    required this.paidAmount,
    required this.outstanding,
  });
}

class EligibleOrders {
  final List<EligibleOrder> orders;
  final String total;
  const EligibleOrders({required this.orders, required this.total});
}

/// Body of POST /cash/settlements.
class SettlementDraft {
  final String branchId;
  final String customerId;
  final List<String> orderIds;
  final OrderPaymentMethod method;
  final String? bankId;
  final String? occurredAt;
  final String? note;
  final String? expectedAmount;
  const SettlementDraft({
    required this.branchId,
    required this.customerId,
    required this.orderIds,
    required this.method,
    this.bankId,
    this.occurredAt,
    this.note,
    this.expectedAmount,
  });

  Map<String, Object?> toJson() => {
    'branchId': branchId,
    'customerId': customerId,
    'orderIds': orderIds,
    'method': method.name,
    if (bankId != null) 'bankId': bankId,
    if (occurredAt != null) 'occurredAt': occurredAt,
    if (note != null) 'note': note,
    if (expectedAmount != null) 'expectedAmount': expectedAmount,
  };
}

class SettlementOrderLine {
  final String orderId;
  final String orderNumber;
  final String? plate;
  final String orderTotal;
  final String orderPaymentStatus;
  final String paymentId;
  final String paymentStatus;
  final String amount;
  const SettlementOrderLine({
    required this.orderId,
    required this.orderNumber,
    this.plate,
    required this.orderTotal,
    required this.orderPaymentStatus,
    required this.paymentId,
    required this.paymentStatus,
    required this.amount,
  });
}

class Settlement {
  final String id;
  final CashRef branch;
  final CashRef customer;
  final String amount;
  final OrderPaymentMethod method;

  /// Payment-account id; [bank] is the legacy code, [bankLabel] the name.
  final String? bankId;
  final String? bank;
  final String? bankLabel;
  final DateTime occurredAt;
  final String? note;
  final int orderCount;
  final String? entryId;
  final DateTime createdAt;
  final CashRef? createdBy;
  final DateTime? voidedAt;
  final CashRef? voidedBy;
  final String? voidReason;

  /// Detail only; empty on list rows.
  final List<SettlementOrderLine> orders;

  const Settlement({
    required this.id,
    required this.branch,
    required this.customer,
    required this.amount,
    required this.method,
    this.bankId,
    this.bank,
    this.bankLabel,
    required this.occurredAt,
    this.note,
    this.orderCount = 0,
    this.entryId,
    required this.createdAt,
    this.createdBy,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
    this.orders = const [],
  });

  bool get isVoided => voidedAt != null;
  bool get canVoid => !isVoided;
  double get amountValue => double.tryParse(amount) ?? 0;
}

/// `YYYY-MM-DD` form of a date, as the cash API expects.
String cashDateParam(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

final NumberFormat _cashMoneyFormat = NumberFormat('#,##0.##', 'en_US');

String formatCashAmount(String amount) =>
    '${_cashMoneyFormat.format(double.tryParse(amount) ?? 0)}₮';
