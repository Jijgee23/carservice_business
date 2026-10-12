import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/cash/domain/settlement.dart';
import 'package:carservice_business/features/orders/domain/order.dart';

Map<String, dynamic> _map(Object? value, String what) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw CashParseException('$what буруу байна.');
}

String _str(Object? value, String what) {
  if (value is String && value.isNotEmpty) return value;
  throw CashParseException('$what буруу байна.');
}

String? _optStr(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

String _money(Object? value, String what) {
  if (value is String && double.tryParse(value) != null) return value;
  if (value is num) return value.toString();
  throw CashParseException('$what буруу байна.');
}

DateTime _date(Object? value, String what) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) throw CashParseException('$what буруу байна.');
  return parsed.toLocal();
}

DateTime? _optDate(Object? value) =>
    value == null ? null : _date(value, 'огноо');

CashRef? _ref(Object? value) {
  if (value is! Map) return null;
  final id = _optStr(value['id']);
  if (id == null) return null;
  return CashRef(id, _optStr(value['name']) ?? id);
}

EligibleOrders parseEligibleOrders(Object? raw) {
  final json = _map(raw, 'response');
  final list = json['orders'];
  if (list is! List) throw const CashParseException('orders буруу байна.');
  final orders = list
      .map((item) {
        final o = _map(item, 'order');
        final id = _str(o['id'], 'order.id');
        return EligibleOrder(
          id: id,
          number: _optStr(o['number']) ?? id,
          plate: _optStr(o['plate']),
          completedAt: _optDate(o['completedAt']),
          totalAmount: _money(o['totalAmount'], 'totalAmount'),
          paidAmount: _money(o['paidAmount'] ?? '0', 'paidAmount'),
          outstanding: _money(o['outstanding'], 'outstanding'),
        );
      })
      .toList(growable: false);
  return EligibleOrders(
    orders: orders,
    total: _money(json['total'] ?? '0', 'total'),
  );
}

SettlementOrderLine _line(Object? raw) {
  final l = _map(raw, 'order');
  final orderId = _str(l['orderId'], 'orderId');
  return SettlementOrderLine(
    orderId: orderId,
    orderNumber: _optStr(l['orderNumber']) ?? orderId,
    plate: _optStr(l['plate']),
    orderTotal: _money(l['orderTotal'] ?? '0', 'orderTotal'),
    orderPaymentStatus: _optStr(l['orderPaymentStatus']) ?? '',
    paymentId: _optStr(l['paymentId']) ?? '',
    paymentStatus: _optStr(l['paymentStatus']) ?? 'PAID',
    amount: _money(l['amount'], 'amount'),
  );
}

Settlement parseSettlement(Object? raw) {
  final json = _map(raw, 'settlement');
  final method = OrderPaymentMethod.tryParse(json['method']);
  if (method == null) throw const CashParseException('method буруу байна.');
  final branch = _ref(json['branch']);
  final customer = _ref(json['customer']);
  if (branch == null) throw const CashParseException('branch буруу байна.');
  if (customer == null) {
    throw const CashParseException('customer буруу байна.');
  }
  final lines = json['orders'];
  return Settlement(
    id: _str(json['id'], 'id'),
    branch: branch,
    customer: customer,
    amount: _money(json['amount'], 'amount'),
    method: method,
    bankId: _optStr(json['bankId']),
    bank: _optStr(json['bank']),
    bankLabel: _optStr(json['bankLabel']),
    occurredAt: _date(json['occurredAt'], 'occurredAt'),
    note: _optStr(json['note']),
    orderCount:
        (json['orderCount'] as num?)?.toInt() ??
        (lines is List ? lines.length : 0),
    entryId: _optStr(json['entryId']),
    createdAt: _date(json['createdAt'], 'createdAt'),
    createdBy: _ref(json['createdBy']),
    voidedAt: _optDate(json['voidedAt']),
    voidedBy: _ref(json['voidedBy']),
    voidReason: _optStr(json['voidReason']),
    orders: lines is List ? lines.map(_line).toList(growable: false) : const [],
  );
}

Settlement parseSettlementEnvelope(Object? raw) =>
    parseSettlement(_map(raw, 'response')['settlement']);
