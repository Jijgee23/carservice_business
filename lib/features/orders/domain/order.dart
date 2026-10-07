import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/features/orders/domain/order_intake.dart';

export 'package:carservice_business/features/orders/domain/order_intake.dart';

/// Typed failure for malformed or contract-incompatible Orders payloads.
///
/// This lives in domain so legacy model factories remain strict without
/// importing the data layer.
class OrderParseException implements Exception {
  const OrderParseException(this.message);

  final String message;

  @override
  String toString() => 'OrderParseException: $message';
}

/// Lossless representation of a decimal value received from the API.
///
/// JSON money values are strings in the Orders API.  Keeping that string at
/// the domain boundary prevents a binary `double` round trip from changing a
/// payment or invoice amount.  The legacy `asDouble` accessor exists only for
/// the pre-Phase-1 presentation widgets; it is never used for request
/// validation or repository serialization.
class Money {
  final String raw;

  const Money(this.raw);

  String get value => raw;

  double get asDouble => double.parse(raw);

  @override
  String toString() => raw;

  @override
  bool operator ==(Object other) => other is Money && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;
}

typedef ApiMoney = Money;
typedef DecimalValue = Money;

/// Server-authoritative work-item progress included in Orders list rows.
///
/// The API excludes PART and CANCELLED items before calculating these counts.
/// Keeping the value object integer-only avoids introducing rounding into the
/// list contract; presentation may derive a ratio when it needs one.
String _groupThousands(double value) {
  final digits = value.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return buf.toString();
}

class OrderProgressSummary {
  final int total;
  final int completed;

  const OrderProgressSummary({required this.total, required this.completed});

  @override
  bool operator ==(Object other) =>
      other is OrderProgressSummary &&
      other.total == total &&
      other.completed == completed;

  @override
  int get hashCode => Object.hash(total, completed);
}

// ─── Enums ───────────────────────────────────────────────────────────────────

enum OrderStatus {
  SCHEDULED,
  IN_PROGRESS,
  COMPLETED,
  CANCELLED;

  static OrderStatus? tryParse(Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static OrderStatus fromString(String s) =>
      tryParse(s) ?? (throw OrderParseException('status утга буруу байна.'));

  String get label {
    switch (this) {
      case SCHEDULED:
        return 'Товлогдсон';
      case IN_PROGRESS:
        return 'Хийгдэж байна';
      case COMPLETED:
        return 'Дууссан';
      case CANCELLED:
        return 'Цуцлагдсан';
    }
  }

  List<OrderStatus> get nextStatuses {
    switch (this) {
      case SCHEDULED:
        return [IN_PROGRESS, CANCELLED];
      case IN_PROGRESS:
        return [COMPLETED, CANCELLED];
      default:
        return [];
    }
  }

  bool get canAddItems => this != COMPLETED && this != CANCELLED;
  bool get isLocked => this == COMPLETED || this == CANCELLED;
  bool get isActive => this == SCHEDULED || this == IN_PROGRESS;
}

enum PaymentStatus {
  UNPAID,
  PARTIAL,
  PAID;

  static PaymentStatus? tryParse(Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static PaymentStatus fromString(String s) =>
      tryParse(s) ??
      (throw OrderParseException('paymentStatus утга буруу байна.'));

  String get label {
    switch (this) {
      case UNPAID:
        return 'Төлөгдөөгүй';
      case PARTIAL:
        return 'Хагас төлөгдсөн';
      case PAID:
        return 'Төлөгдсөн';
    }
  }
}

enum ItemKind {
  LABOR,
  DIAGNOSTIC,
  PART,
  FEE;

  static ItemKind? tryParse(Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static ItemKind fromString(String s) =>
      tryParse(s) ?? (throw OrderParseException('kind утга буруу байна.'));

  String get label {
    switch (this) {
      case LABOR:
        return 'Ажил';
      case DIAGNOSTIC:
        return 'Оношилгоо';
      case PART:
        return 'Сэлбэг';
      case FEE:
        return 'Хураамж';
    }
  }
}

enum ServiceItemStatus {
  PENDING,
  IN_PROGRESS,
  COMPLETED,
  CANCELLED;

  static ServiceItemStatus? tryParse(Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static ServiceItemStatus fromString(String value) =>
      tryParse(value) ??
      (throw OrderParseException('status утга буруу байна.'));
}

enum OrderPaymentMethod {
  QPAY,
  CASH,
  BANK_TRANSFER,
  CARD,
  OTHER;

  static OrderPaymentMethod? tryParse(Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static OrderPaymentMethod fromString(String value) =>
      tryParse(value) ??
      (throw OrderParseException('method утга буруу байна.'));
}

enum OrderPaymentRecordStatus {
  PENDING,
  PAID,
  CANCELLED,
  FAILED;

  static OrderPaymentRecordStatus? tryParse(Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static OrderPaymentRecordStatus fromString(String value) =>
      tryParse(value) ??
      (throw OrderParseException('status утга буруу байна.'));
}

class OrderPaymentRecord {
  final String id;
  final Money amountMoney;
  final OrderPaymentMethod method;
  final OrderPaymentRecordStatus status;
  final DateTime? paidAt;
  final DateTime createdAt;

  /// Receiving bank code (BANK_TRANSFER / CARD only); null otherwise.
  final String? bank;

  /// Set when the payment belongs to a postpaid lump-sum settlement
  /// («Нэгдсэн тооцоо»); such rows are reversed via the settlement.
  final String? settlementId;

  /// True when the payment's ledger row sits in a closed cash shift; the
  /// server then refuses to reverse it (CASH_SESSION_ENTRY_LOCKED).
  final bool locked;

  const OrderPaymentRecord({
    required this.id,
    required this.amountMoney,
    required this.method,
    required this.status,
    required this.paidAt,
    required this.createdAt,
    this.bank,
    this.settlementId,
    this.locked = false,
  });

  bool get isSettlement => settlementId != null;
  double get amount => amountMoney.asDouble;
}

class OrderPaymentTotals {
  final Money totalAmountMoney;
  final Money paidAmountMoney;
  final Money remainingAmountMoney;
  final PaymentStatus paymentStatus;

  const OrderPaymentTotals({
    required this.totalAmountMoney,
    required this.paidAmountMoney,
    required this.remainingAmountMoney,
    required this.paymentStatus,
  });

  double get totalAmount => totalAmountMoney.asDouble;
  double get paidAmount => paidAmountMoney.asDouble;
  double get remainingAmount => remainingAmountMoney.asDouble;
}

class OrderPaymentInput {
  final OrderPaymentMethod method;
  final Money amount;

  const OrderPaymentInput({required this.method, required this.amount});
}

class OrderPaymentResult {
  final OrderPaymentRecord payment;
  final OrderPaymentTotals totals;

  const OrderPaymentResult({required this.payment, required this.totals});
}

class QPayState {
  final bool qpayEnabled;
  final OrderPayment? pending;

  const QPayState({required this.qpayEnabled, required this.pending});
}

class QPayCheckResult {
  final bool paid;
  final String? message;

  const QPayCheckResult({required this.paid, this.message});
}

class AssignableUser {
  final String id;
  final String firstName;
  final String lastName;

  const AssignableUser({
    required this.id,
    required this.firstName,
    required this.lastName,
  });

  String get fullName => '$firstName $lastName'.trim();
}

class BulkOrderFailure {
  final String orderId;
  final String code;
  final String message;

  const BulkOrderFailure({
    required this.orderId,
    required this.code,
    required this.message,
  });
}

class BulkOrderResult {
  final List<String> succeeded;
  final List<BulkOrderFailure> failed;

  const BulkOrderResult({required this.succeeded, required this.failed});
}

class OrderScheduleResult {
  final String orderId;
  final DateTime? expectedFinishAt;
  final DateTime? scheduledAt;
  final DateTime? previousScheduledAt;

  const OrderScheduleResult({
    required this.orderId,
    this.expectedFinishAt,
    this.scheduledAt,
    this.previousScheduledAt,
  });
}

class OrderItemHistoryPage {
  final List<ServiceItem> items;
  final PaginationMeta pagination;

  const OrderItemHistoryPage({required this.items, required this.pagination});
}

class PostpaidVehicleAggregate {
  final String id;
  final String plate;
  final String make;
  final String model;
  final CustomerSummary? customer;
  final int orderCount;
  final Money totalAmountMoney;
  final Money paidAmountMoney;
  final Money balanceAmountMoney;

  const PostpaidVehicleAggregate({
    required this.id,
    required this.plate,
    required this.make,
    required this.model,
    required this.customer,
    required this.orderCount,
    required this.totalAmountMoney,
    required this.paidAmountMoney,
    required this.balanceAmountMoney,
  });
}

class PostpaidSummary {
  final int orderCount;
  final Money totalAmountMoney;
  final Money paidAmountMoney;
  final Money balanceAmountMoney;

  const PostpaidSummary({
    required this.orderCount,
    required this.totalAmountMoney,
    required this.paidAmountMoney,
    required this.balanceAmountMoney,
  });
}

class PostpaidPage {
  final List<PostpaidVehicleAggregate> vehicles;
  final PostpaidSummary summary;
  final List<ServiceOrderSummary> orders;
  final PaginationMeta pagination;

  const PostpaidPage({
    required this.vehicles,
    required this.summary,
    required this.orders,
    required this.pagination,
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _legacyString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw OrderParseException('$key талбар буруу байна.');
  }
  return value.trim();
}

String? _legacyOptionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw OrderParseException('$key талбар буруу байна.');
  return value.trim();
}

DateTime _legacyDate(Map<String, dynamic> json, String key) {
  final value = _legacyString(json, key);
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
  ).hasMatch(value)) {
    throw OrderParseException('$key огноо буруу байна.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw OrderParseException('$key огноо буруу байна.');
  return parsed.toLocal();
}

DateTime? _legacyOptionalDate(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _legacyDate(json, key);
}

OrderProgressSummary? _legacyProgress(Map<String, dynamic> json) {
  if (!json.containsKey('progress')) return null;
  final value = _legacyMap(json, 'progress');
  final total = value['total'];
  final completed = value['completed'];
  if (total is! int ||
      completed is! int ||
      total < 0 ||
      completed < 0 ||
      completed > total) {
    throw const OrderParseException('progress талбар буруу байна.');
  }
  return OrderProgressSummary(total: total, completed: completed);
}

Map<String, dynamic> _legacyMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) throw OrderParseException('$key талбар буруу байна.');
  return Map<String, dynamic>.from(value);
}

String _legacyDecimal(Map<String, dynamic> json, String key) {
  final value = _legacyString(json, key);
  if (!RegExp(r'^(?:0|[1-9]\d*)(?:\.\d+)?$').hasMatch(value)) {
    throw OrderParseException('$key мөнгөн дүн буруу байна.');
  }
  return value;
}

double _parseDecimalRequired(dynamic v) {
  if (v is! String) throw const OrderParseException('мөнгөн дүн буруу байна.');
  final parsed = double.tryParse(v);
  if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
    throw const OrderParseException('мөнгөн дүн буруу байна.');
  }
  return parsed;
}

// ─── OrderPayment ─────────────────────────────────────────────────────────────

class QPayBankUrl {
  final String name;
  final String nameMn;
  final String logo;
  final String description;
  final String link;

  const QPayBankUrl({
    required this.name,
    required this.nameMn,
    required this.logo,
    required this.description,
    required this.link,
  });

  factory QPayBankUrl.fromJson(Map<String, dynamic> j) => QPayBankUrl(
    name: _legacyString(j, 'name'),
    nameMn: _legacyOptionalString(j, 'name_mn') ?? _legacyString(j, 'name'),
    logo: _legacyOptionalString(j, 'logo') ?? '',
    description: _legacyOptionalString(j, 'description') ?? '',
    link: _legacyString(j, 'link'),
  );
}

class OrderPayment {
  final String id;
  final String? qrImage;
  final String? qrText;
  final double amount;
  final Money amountMoney;
  final List<QPayBankUrl> urls;

  OrderPayment({
    required this.id,
    this.qrImage,
    this.qrText,
    required this.amount,
    Money? amountMoney,
    this.urls = const [],
  }) : amountMoney = amountMoney ?? Money(amount.toString());

  factory OrderPayment.fromJson(Map<String, dynamic> j) {
    final urls = j['urls'];
    if (urls != null && urls is! List) {
      throw const OrderParseException('urls талбар буруу байна.');
    }
    return OrderPayment(
      id: _legacyString(j, 'id'),
      qrImage: _legacyOptionalString(j, 'qrImage'),
      qrText: _legacyOptionalString(j, 'qrText'),
      amount: _parseDecimalRequired(_legacyDecimal(j, 'amount')),
      amountMoney: Money(_legacyDecimal(j, 'amount')),
      urls: (urls ?? const <dynamic>[])
          .map((raw) {
            if (raw is! Map) {
              throw const OrderParseException('QPay url буруу байна.');
            }
            final value = Map<String, dynamic>.from(raw);
            return QPayBankUrl(
              name: _legacyString(value, 'name'),
              nameMn:
                  _legacyOptionalString(value, 'name_mn') ??
                  _legacyString(value, 'name'),
              logo: _legacyOptionalString(value, 'logo') ?? '',
              description: _legacyOptionalString(value, 'description') ?? '',
              link: _legacyString(value, 'link'),
            );
          })
          .toList(growable: false),
    );
  }
}

// ─── ServiceItem ──────────────────────────────────────────────────────────────

class ServiceItem {
  final String id;
  final ItemKind kind;
  final String description;
  final double quantity;
  final double unitPrice;
  final double total;
  final String? serviceId;
  final ServiceItemStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelledById;
  final UserSummary? cancelledBy;
  final String? diagnosticTemplateId;
  final String? diagnosticReportId;
  final Money? quantityMoney;
  final Money? unitPriceMoney;
  final Money? totalMoney;

  const ServiceItem({
    required this.id,
    required this.kind,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.serviceId,
    this.status = ServiceItemStatus.PENDING,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelledById,
    this.cancelledBy,
    this.diagnosticTemplateId,
    this.diagnosticReportId,
    this.quantityMoney,
    this.unitPriceMoney,
    this.totalMoney,
  });

  factory ServiceItem.fromJson(Map<String, dynamic> j) {
    final quantity = _legacyDecimal(j, 'quantity');
    final unitPrice = _legacyDecimal(j, 'unitPrice');
    final total = _legacyDecimal(j, 'total');
    final status =
        ServiceItemStatus.tryParse(j['status']) ??
        (throw const OrderParseException('status утга буруу байна.'));
    return ServiceItem(
      id: _legacyString(j, 'id'),
      kind: ItemKind.fromString(_legacyString(j, 'kind')),
      description: _legacyString(j, 'description'),
      quantity: _parseDecimalRequired(quantity),
      unitPrice: _parseDecimalRequired(unitPrice),
      total: _parseDecimalRequired(total),
      serviceId: _legacyOptionalString(j, 'serviceId'),
      status: status,
      startedAt: _legacyOptionalDate(j, 'startedAt'),
      completedAt: _legacyOptionalDate(j, 'completedAt'),
      cancelledAt: _legacyOptionalDate(j, 'cancelledAt'),
      cancelledById: _legacyOptionalString(j, 'cancelledById'),
      diagnosticTemplateId: _legacyOptionalString(j, 'diagnosticTemplateId'),
      diagnosticReportId: _legacyOptionalString(j, 'diagnosticReportId'),
      quantityMoney: Money(quantity),
      unitPriceMoney: Money(unitPrice),
      totalMoney: Money(total),
    );
  }
}

// ─── OrderReportSummary ────────────────────────────────────────────────────────

class OrderReportSummary {
  final String id;
  final DateTime createdAt;
  final ReportTemplateSummary template;

  const OrderReportSummary({
    required this.id,
    required this.createdAt,
    required this.template,
  });

  factory OrderReportSummary.fromJson(Map<String, dynamic> j) =>
      OrderReportSummary(
        id: _legacyString(j, 'id'),
        createdAt: _legacyDate(j, 'createdAt'),
        template: ReportTemplateSummary.fromJson(_legacyMap(j, 'template')),
      );
}

// ─── ServiceOrderSummary ──────────────────────────────────────────────────────

class ServiceOrderSummary {
  final String id;
  final String number;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final double? totalAmount;
  final double? paidAmount;
  final String? notes;
  final DateTime createdAt;
  final CustomerSummary customer;
  final VehicleSummary vehicle;
  final BranchSummary branch;
  final UserSummary? assignedTo;
  final bool isPostpaid;

  /// A paid payment sits in a closed cash shift (server flag; false when an
  /// older server omits it). Cancel/edit are then refused (PAID_PAYMENT_LOCKED).
  final bool hasLockedPayment;

  /// Internal repair ("Дотоод засвар"): no payment, booked as internal cost.
  final bool isInternal;
  final bool paidInFullBeforeCompletion;
  final String? plateSnapshot;
  final String? vinSnapshot;
  final Money? totalAmountMoney;
  final Money? paidAmountMoney;
  final DateTime? expectedFinishAt;
  final int? estimatedDurationMinutes;
  final OrderProgressSummary? progress;
  final List<String> servicePreview;

  const ServiceOrderSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.paymentStatus,
    this.scheduledAt,
    this.startedAt,
    this.completedAt,
    this.totalAmount,
    this.paidAmount,
    this.notes,
    required this.createdAt,
    required this.customer,
    required this.vehicle,
    required this.branch,
    this.assignedTo,
    this.isPostpaid = false,
    this.hasLockedPayment = false,
    this.isInternal = false,
    this.paidInFullBeforeCompletion = false,
    this.plateSnapshot,
    this.vinSnapshot,
    this.totalAmountMoney,
    this.paidAmountMoney,
    this.expectedFinishAt,
    this.estimatedDurationMinutes,
    this.progress,
    this.servicePreview = const [],
  });

  /// Non-PART, non-cancelled items that are not COMPLETED yet. `null` when the
  /// row carries no progress data (the server is then the only judge).
  int? get unfinishedWorkCount {
    final p = progress;
    if (p == null) return null;
    final left = p.total - p.completed;
    return left < 0 ? 0 : left;
  }

  /// Outstanding balance, or `null` when unknown.
  double? get unpaidBalance {
    final total = totalAmountMoney?.asDouble ?? totalAmount;
    if (total == null) return null;
    // A missing paid amount with a known total means nothing was paid yet.
    final paid = paidAmountMoney?.asDouble ?? paidAmount ?? 0;
    return total - paid;
  }

  /// True when the order has a paid (or partly paid) payment. The server then
  /// refuses price/qty/kind edits, item cancel and order cancel/delete with
  /// `PAID_PAYMENT_EXISTS` until the payment is refunded.
  bool get hasPaidPayment => paymentStatus != PaymentStatus.UNPAID;

  /// Why "Дуусгах" would be rejected (`ITEMS_NOT_COMPLETED` /
  /// `PAYMENT_INCOMPLETE`), or `null` when nothing is known to block it.
  ///
  /// A postpaid order with a balance may be closed only by a user holding
  /// `orders.closeUnpaidPostpaid` (owner implicit): [canCloseUnpaidPostpaid].
  String? completionBlocker({bool canCloseUnpaidPostpaid = false}) {
    final reasons = <String>[];
    final unfinished = unfinishedWorkCount;
    if (unfinished != null && unfinished > 0) {
      reasons.add('$unfinished ажил дуусаагүй');
    }
    final balance = unpaidBalance;
    if (!isPostpaid && !isInternal && balance != null && balance > 0.004) {
      reasons.add('${_groupThousands(balance)}₮ төлөгдөөгүй');
    }
    if (isPostpaid &&
        !canCloseUnpaidPostpaid &&
        balance != null &&
        balance > 0.004) {
      reasons.add(
        'Дараа тооцоот: төлбөр дутуу — зөвхөн эрхтэй хэрэглэгч хаана',
      );
    }
    return reasons.isEmpty ? null : reasons.join(', ');
  }

  factory ServiceOrderSummary.fromJson(Map<String, dynamic> j) {
    final totalRaw = j['totalAmount'];
    final paidRaw = j['paidAmount'];
    final total = totalRaw == null ? null : _legacyDecimal(j, 'totalAmount');
    final paid = paidRaw == null ? null : _legacyDecimal(j, 'paidAmount');
    final customer = _legacyMap(j, 'customer');
    final vehicle = _legacyMap(j, 'vehicle');
    final branch = _legacyMap(j, 'branch');
    return ServiceOrderSummary(
      id: _legacyString(j, 'id'),
      number: _legacyString(j, 'number'),
      status: OrderStatus.fromString(_legacyString(j, 'status')),
      paymentStatus: PaymentStatus.fromString(
        _legacyString(j, 'paymentStatus'),
      ),
      scheduledAt: _legacyOptionalDate(j, 'scheduledAt'),
      startedAt: _legacyOptionalDate(j, 'startedAt'),
      completedAt: _legacyOptionalDate(j, 'completedAt'),
      totalAmount: total == null ? null : _parseDecimalRequired(total),
      paidAmount: paid == null ? null : _parseDecimalRequired(paid),
      notes: _legacyOptionalString(j, 'notes'),
      createdAt: _legacyDate(j, 'createdAt'),
      customer: CustomerSummary.fromJson(customer),
      vehicle: VehicleSummary.fromJson(vehicle),
      branch: BranchSummary.fromJson(branch),
      assignedTo: j['assignedTo'] == null
          ? null
          : UserSummary.fromJson(_legacyMap(j, 'assignedTo')),
      isPostpaid: !j.containsKey('isPostpaid')
          ? false
          : (j['isPostpaid'] is bool
                ? j['isPostpaid'] as bool
                : (throw const OrderParseException('isPostpaid буруу байна.'))),
      hasLockedPayment: j['hasLockedPayment'] == true,
      isInternal: j['isInternal'] == true,
      paidInFullBeforeCompletion: j['paidInFullBeforeCompletion'] == true,
      plateSnapshot: j['plateSnapshot'] is String
          ? j['plateSnapshot'] as String
          : null,
      vinSnapshot: j['vinSnapshot'] is String
          ? j['vinSnapshot'] as String
          : null,
      totalAmountMoney: total == null ? null : Money(total),
      paidAmountMoney: paid == null ? null : Money(paid),
      progress: _legacyProgress(j),
      servicePreview: switch (j['servicePreview']) {
        final List values => values.whereType<String>().toList(growable: false),
        _ => const <String>[],
      },
      expectedFinishAt: _legacyOptionalDate(j, 'expectedFinishAt'),
      estimatedDurationMinutes: j['estimatedDurationMinutes'] == null
          ? null
          : (j['estimatedDurationMinutes'] is int &&
                    (j['estimatedDurationMinutes'] as int) >= 0
                ? j['estimatedDurationMinutes'] as int
                : (throw const OrderParseException(
                    'estimatedDurationMinutes буруу байна.',
                  ))),
    );
  }
}

// ─── ServiceOrderDetail ───────────────────────────────────────────────────────

class ServiceOrderDetail extends ServiceOrderSummary {
  final List<ServiceItem> items;
  final List<OrderReportSummary> reports;
  final DateTime? paidAt;
  final DateTime? updatedAt;
  final List<OrderPaymentRecord> payments;
  final OrderPaymentTotals? paymentTotals;
  final OrderIntake? intake;

  const ServiceOrderDetail({
    required super.id,
    required super.number,
    required super.status,
    required super.paymentStatus,
    super.scheduledAt,
    super.startedAt,
    super.completedAt,
    super.totalAmount,
    super.paidAmount,
    super.notes,
    required super.createdAt,
    required super.customer,
    required super.vehicle,
    required super.branch,
    super.assignedTo,
    super.isPostpaid,
    super.hasLockedPayment,
    super.isInternal,
    super.paidInFullBeforeCompletion,
    super.plateSnapshot,
    super.vinSnapshot,
    super.totalAmountMoney,
    super.paidAmountMoney,
    super.expectedFinishAt,
    super.estimatedDurationMinutes,
    super.progress,
    required this.items,
    required this.reports,
    this.paidAt,
    this.updatedAt,
    this.payments = const [],
    this.paymentTotals,
    this.intake,
  });

  @override
  int? get unfinishedWorkCount => items
      .where(
        (i) =>
            i.kind != ItemKind.PART &&
            i.status != ServiceItemStatus.CANCELLED &&
            i.status != ServiceItemStatus.COMPLETED,
      )
      .length;

  @override
  double? get unpaidBalance {
    // Order total minus paid from the order fields (paymentTotals may be
    // stale); fall back to paymentTotals only when the total is unknown.
    final fromOrder = super.unpaidBalance;
    if (fromOrder != null) return fromOrder;
    return paymentTotals?.remainingAmountMoney.asDouble;
  }

  @override
  bool get hasPaidPayment =>
      payments.any((p) => p.status == OrderPaymentRecordStatus.PAID) ||
      super.hasPaidPayment;

  factory ServiceOrderDetail.fromJson(Map<String, dynamic> j) {
    final base = ServiceOrderSummary.fromJson(j);
    return ServiceOrderDetail(
      id: base.id,
      number: base.number,
      status: base.status,
      paymentStatus: base.paymentStatus,
      scheduledAt: base.scheduledAt,
      startedAt: base.startedAt,
      completedAt: base.completedAt,
      totalAmount: base.totalAmount,
      paidAmount: base.paidAmount,
      totalAmountMoney: base.totalAmountMoney,
      paidAmountMoney: base.paidAmountMoney,
      expectedFinishAt: base.expectedFinishAt,
      estimatedDurationMinutes: base.estimatedDurationMinutes,
      progress: base.progress,
      notes: base.notes,
      createdAt: base.createdAt,
      customer: base.customer,
      vehicle: base.vehicle,
      branch: base.branch,
      assignedTo: base.assignedTo,
      hasLockedPayment: base.hasLockedPayment,
      items: _legacyList(j, 'items')
          .map((e) {
            if (e is! Map) {
              throw const OrderParseException('items талбар буруу байна.');
            }
            return ServiceItem.fromJson(Map<String, dynamic>.from(e));
          })
          .toList(growable: false),
      reports: _legacyList(j, 'reports')
          .map((e) {
            if (e is! Map) {
              throw const OrderParseException('reports талбар буруу байна.');
            }
            final report = Map<String, dynamic>.from(e);
            return OrderReportSummary.fromJson(report);
          })
          .toList(growable: false),
      paidAt: _legacyOptionalDate(j, 'paidAt'),
      updatedAt: _legacyOptionalDate(j, 'updatedAt'),
    );
  }
}

List<dynamic> _legacyList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw OrderParseException('$key талбар буруу байна.');
  return value;
}
