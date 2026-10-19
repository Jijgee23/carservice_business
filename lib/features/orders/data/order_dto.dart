import 'package:carservice_business/core/domain/pagination.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/features/orders/domain/order.dart';

// Preserve the Phase-0 import surface for tests and adapters that referenced
// the parser failure from the DTO library.
export 'package:carservice_business/features/orders/domain/order.dart';

typedef JsonMap = Map<String, dynamic>;

JsonMap _map(Object? value, String label) {
  if (value is! Map) throw OrderParseException('$label буруу байна.');
  return Map<String, dynamic>.from(value);
}

String _requiredString(JsonMap json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw OrderParseException('$key талбар буруу байна.');
  }
  return value.trim();
}

String? _optionalString(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw OrderParseException('$key талбар буруу байна.');
  return value.trim();
}

DateTime? _optionalDate(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw OrderParseException('$key огноо буруу байна.');
  }
  return _strictDate(value, key);
}

DateTime _requiredDate(JsonMap json, String key) {
  final value = _optionalDate(json, key);
  if (value == null) throw OrderParseException('$key огноо шаардлагатай.');
  return value;
}

DateTime _strictDate(String raw, String key) {
  // Responses use ISO-8601 instants. Date-only and Dart's permissive parser
  // forms are rejected because they lose timezone/precision semantics.
  final value = raw.trim();
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
  ).hasMatch(value)) {
    throw OrderParseException('$key огноо буруу байна.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw OrderParseException('$key огноо буруу байна.');
  }
  return parsed.toLocal();
}

Money? _optionalMoney(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String ||
      !RegExp(r'^(?:0|[1-9]\d*)(?:\.\d+)?$').hasMatch(value.trim())) {
    throw OrderParseException('$key мөнгөн дүн буруу байна.');
  }
  return Money(value.trim());
}

Money _requiredMoney(JsonMap json, String key) {
  final value = _optionalMoney(json, key);
  if (value == null) throw OrderParseException('$key мөнгөн дүн шаардлагатай.');
  return value;
}

int _requiredInt(JsonMap json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncate()) {
    return value.toInt();
  }
  throw OrderParseException('$key бүхэл тоо буруу байна.');
}

OrderProgressSummary? _optionalProgress(JsonMap json) {
  if (!json.containsKey('progress')) return null;
  final value = _map(json['progress'], 'progress');
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

bool _requiredBool(JsonMap json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw OrderParseException('$key boolean буруу байна.');
}

T _enum<T>(Object? value, T? Function(Object?) parse, String key) {
  final result = parse(value);
  if (result == null) throw OrderParseException('$key утга буруу байна.');
  return result;
}

class OrderCustomerDto {
  const OrderCustomerDto(this.value);
  final CustomerSummary value;

  factory OrderCustomerDto.fromJson(Object? raw) {
    final json = _map(raw, 'customer');
    return OrderCustomerDto(
      CustomerSummary(
        id: _requiredString(json, 'id'),
        fullName: _optionalString(json, 'fullName'),
        phone: _requiredString(json, 'phone'),
        email: _optionalString(json, 'email'),
      ),
    );
  }
}

CustomerSummary _customer(Object? raw) => OrderCustomerDto.fromJson(raw).value;

VehicleSummary _vehicle(Object? raw) {
  final json = _map(raw, 'vehicle');
  return VehicleSummary(
    id: _requiredString(json, 'id'),
    plate: _requiredString(json, 'plate'),
    make: _requiredString(json, 'make'),
    model: _requiredString(json, 'model'),
    year: json['year'] == null ? null : _requiredInt(json, 'year'),
    vin: _optionalString(json, 'vin'),
    mileage: json['mileage'] == null ? null : _requiredInt(json, 'mileage'),
  );
}

BranchSummary _branch(Object? raw) {
  final json = _map(raw, 'branch');
  return BranchSummary(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
  );
}

UserSummary? _user(Object? raw) {
  if (raw == null) return null;
  final json = _map(raw, 'assignedTo');
  return UserSummary(
    id: _requiredString(json, 'id'),
    firstName: _requiredString(json, 'firstName'),
    lastName: _requiredString(json, 'lastName'),
  );
}

class ServiceItemDto {
  const ServiceItemDto(this.value);
  final ServiceItem value;

  factory ServiceItemDto.fromJson(Object? raw, {bool history = false}) {
    final json = _map(raw, 'item');
    final quantityMoney = _requiredMoney(json, 'quantity');
    final unitPriceMoney = _requiredMoney(json, 'unitPrice');
    final totalMoney = _requiredMoney(json, 'total');
    final status = _enum(json['status'], ServiceItemStatus.tryParse, 'status');
    return ServiceItemDto(
      ServiceItem(
        id: _requiredString(json, 'id'),
        kind: _enum(json['kind'], ItemKind.tryParse, 'kind'),
        description: _requiredString(json, 'description'),
        quantity: quantityMoney.asDouble,
        unitPrice: unitPriceMoney.asDouble,
        total: totalMoney.asDouble,
        serviceId: _optionalString(json, 'serviceId'),
        status: status,
        startedAt: _optionalDate(json, 'startedAt'),
        completedAt: _optionalDate(json, 'completedAt'),
        cancelledAt: _optionalDate(json, 'cancelledAt'),
        cancelledById: _optionalString(json, 'cancelledById'),
        cancelledBy: _user(json['cancelledBy']),
        diagnosticTemplateId: _optionalString(json, 'diagnosticTemplateId'),
        diagnosticReportId: _optionalString(json, 'diagnosticReportId'),
        quantityMoney: quantityMoney,
        unitPriceMoney: unitPriceMoney,
        totalMoney: totalMoney,
      ),
    );
  }
}

ServiceOrderSummary _summary(Object? raw) {
  final json = _map(raw, 'order');
  final total = _optionalMoney(json, 'totalAmount');
  final paid = _optionalMoney(json, 'paidAmount');
  return ServiceOrderSummary(
    id: _requiredString(json, 'id'),
    number: _requiredString(json, 'number'),
    status: _enum(json['status'], OrderStatus.tryParse, 'status'),
    paymentStatus: _enum(
      json['paymentStatus'],
      PaymentStatus.tryParse,
      'paymentStatus',
    ),
    scheduledAt: _optionalDate(json, 'scheduledAt'),
    startedAt: _optionalDate(json, 'startedAt'),
    completedAt: _optionalDate(json, 'completedAt'),
    totalAmount: total?.asDouble,
    paidAmount: paid?.asDouble,
    totalAmountMoney: total,
    paidAmountMoney: paid,
    expectedFinishAt: _optionalDate(json, 'expectedFinishAt'),
    estimatedDurationMinutes: json['estimatedDurationMinutes'] == null
        ? null
        : _requiredInt(json, 'estimatedDurationMinutes'),
    progress: _optionalProgress(json),
    // The first open work lines (GET /orders); lenient, it is display-only.
    servicePreview: switch (json['servicePreview']) {
      final List values => values.whereType<String>().toList(growable: false),
      _ => const <String>[],
    },
    notes: _optionalString(json, 'notes'),
    createdAt: _requiredDate(json, 'createdAt'),
    customer: _customer(json['customer']),
    vehicle: _vehicle(json['vehicle']),
    branch: _branch(json['branch']),
    assignedTo: _user(json['assignedTo']),
    isPostpaid: !json.containsKey('isPostpaid')
        ? false
        : _requiredBool(json, 'isPostpaid'),
    hasLockedPayment: json['hasLockedPayment'] == true,
    isInternal: json['isInternal'] == true,
    paidInFullBeforeCompletion: json['paidInFullBeforeCompletion'] == true,
    plateSnapshot: json['plateSnapshot'] is String
        ? json['plateSnapshot'] as String
        : null,
    vinSnapshot: json['vinSnapshot'] is String
        ? json['vinSnapshot'] as String
        : null,
  );
}

class OrderSummaryDto {
  const OrderSummaryDto(this.value);
  final ServiceOrderSummary value;
  factory OrderSummaryDto.fromJson(Object? raw) {
    final json = _map(raw, 'order response');
    return OrderSummaryDto(
      _summary(json['order'] is Map ? json['order'] : json),
    );
  }
}

OrderReportSummary _report(Object? raw) {
  final json = _map(raw, 'report');
  final template = _map(json['template'], 'template');
  final type = _enum(
    template['type'],
    (value) => value is String
        ? DiagnosticType.values.where((item) => item.name == value).firstOrNull
        : null,
    'template.type',
  );
  return OrderReportSummary(
    id: _requiredString(json, 'id'),
    createdAt: _requiredDate(json, 'createdAt'),
    template: ReportTemplateSummary(
      id: _requiredString(template, 'id'),
      name: _requiredString(template, 'name'),
      type: type,
    ),
  );
}

class OrderDetailDto {
  const OrderDetailDto(this.value);
  final ServiceOrderDetail value;

  factory OrderDetailDto.fromJson(Object? raw) {
    final outer = _map(raw, 'order response');
    final json = _map(outer['order'] is Map ? outer['order'] : outer, 'order');
    final base = _summary(json);
    final rawItems = json['items'];
    final rawReports = json['reports'];
    if (rawItems is! List || rawReports is! List) {
      throw const OrderParseException('Засварын хуудасны мөр/тайлан буруу байна.');
    }
    return OrderDetailDto(
      ServiceOrderDetail(
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
        isPostpaid: base.isPostpaid,
        hasLockedPayment: base.hasLockedPayment,
        isInternal: base.isInternal,
        paidInFullBeforeCompletion: base.paidInFullBeforeCompletion,
        plateSnapshot: base.plateSnapshot,
        vinSnapshot: base.vinSnapshot,
        items: rawItems
            .map((item) => ServiceItemDto.fromJson(item).value)
            .toList(growable: false),
        reports: rawReports.map(_report).toList(growable: false),
        paidAt: _optionalDate(json, 'paidAt'),
        updatedAt: _optionalDate(json, 'updatedAt'),
        intake: _intake(json['intake']),
      ),
    );
  }
}

/// Хүлээн авалт нь туслах блок тул буруу бүтэцтэй бол захиалгын ачааллыг
/// унагаахгүй: блок бүхэлдээ `null`, буруу зураг алгасагдана.
OrderIntake? _intake(Object? raw) {
  if (raw is! Map) return null;
  try {
    final json = Map<String, dynamic>.from(raw);
    final photos = <OrderIntakePhoto>[];
    final rawPhotos = json['photos'];
    if (rawPhotos is List) {
      for (final p in rawPhotos) {
        try {
          final photo = _map(p, 'intake photo');
          photos.add(
            OrderIntakePhoto(
              id: _requiredString(photo, 'id'),
              url: _requiredString(photo, 'url'),
            ),
          );
        } on OrderParseException {
          continue;
        }
      }
    }
    return OrderIntake(
      notes: _optionalString(json, 'notes'),
      photos: photos,
      signatureUrl: _optionalString(json, 'signatureUrl'),
      recordedAt: _requiredDate(json, 'recordedAt'),
      recordedBy: _optionalString(json, 'recordedBy'),
      mileageKm: json['mileageKm'] is num && (json['mileageKm'] as num).isFinite
          ? (json['mileageKm'] as num).toInt()
          : null,
    );
  } on OrderParseException catch (e) {
    if (kDebugMode) debugPrint('intake parse skipped: $e');
    return null;
  }
}

PaginationMeta _pagination(Object? raw) {
  final json = _map(raw, 'pagination');
  final page = _requiredInt(json, 'page');
  final pageSize = _requiredInt(json, 'pageSize');
  final total = _requiredInt(json, 'total');
  final totalPages = _requiredInt(json, 'totalPages');
  if (page < 1 || pageSize < 1 || total < 0 || totalPages < 0) {
    throw const OrderParseException('Хуудаслалтын мэдээлэл буруу байна.');
  }
  return PaginationMeta(
    page: page,
    pageSize: pageSize,
    total: total,
    totalPages: totalPages,
    hasPrev: _requiredBool(json, 'hasPrev'),
    hasNext: _requiredBool(json, 'hasNext'),
  );
}

class OrderPageDto {
  const OrderPageDto(this.items, this.pagination);
  final List<ServiceOrderSummary> items;
  final PaginationMeta pagination;

  factory OrderPageDto.fromJson(Object? raw) {
    final json = _map(raw, 'orders response');
    final list = json['orders'];
    if (list is! List) {
      throw const OrderParseException('Засварын хуудасны жагсаалт буруу байна.');
    }
    return OrderPageDto(
      list
          .map((item) => OrderSummaryDto.fromJson(item).value)
          .toList(growable: false),
      _pagination(json['pagination']),
    );
  }
}

typedef OrdersPageDto = OrderPageDto;
typedef OrderListPageDto = OrderPageDto;
typedef OrderDto = OrderSummaryDto;
typedef OrderDetailResponseDto = OrderDetailDto;

OrderPayment _qpayPayment(Object? raw) {
  final json = _map(raw, 'qpay payment');
  final amount = _requiredMoney(json, 'amount');
  final urls = json['urls'];
  if (urls != null && urls is! List) {
    throw const OrderParseException('QPay банкны холбоос буруу байна.');
  }
  final urlItems = urls is List ? urls : const <Object?>[];
  return OrderPayment(
    id: _requiredString(json, 'id'),
    amount: amount.asDouble,
    amountMoney: amount,
    qrImage: _optionalString(json, 'qrImage'),
    qrText: _optionalString(json, 'qrText'),
    urls: urlItems
        .map(_parseQPayUrl)
        .whereType<QPayBankUrl>()
        .toList(growable: false),
  );
}

QPayBankUrl? _parseQPayUrl(Object? raw) {
  try {
    final value = _map(raw, 'qpay url');
    return QPayBankUrl(
      name: _requiredString(value, 'name'),
      nameMn:
          _optionalString(value, 'name_mn') ?? _requiredString(value, 'name'),
      logo: _optionalString(value, 'logo') ?? '',
      description: _optionalString(value, 'description') ?? '',
      link: _requiredString(value, 'link'),
    );
  } on OrderParseException {
    // QPay may include an unusable bank entry while the invoice itself is
    // still valid. Keep strict validation for entries that survive parsing,
    // but discard only the malformed entry.
    return null;
  }
}

class QPayStateDto {
  const QPayStateDto(this.value);
  final QPayState value;
  factory QPayStateDto.fromJson(Object? raw) {
    final json = _map(raw, 'qpay response');
    final enabled = json['qpayEnabled'];
    if (enabled is! bool) {
      throw const OrderParseException('qpayEnabled буруу байна.');
    }
    return QPayStateDto(
      QPayState(
        qpayEnabled: enabled,
        pending: json['pending'] == null ? null : _qpayPayment(json['pending']),
      ),
    );
  }
}

class BulkOrderResultDto {
  const BulkOrderResultDto(this.value);
  final BulkOrderResult value;
  factory BulkOrderResultDto.fromJson(Object? raw) {
    final json = _map(raw, 'bulk response');
    final succeeded = json['succeeded'];
    final failed = json['failed'];
    if (succeeded is! List || failed is! List) {
      throw const OrderParseException('Бөөн өөрчлөлтийн хариу буруу байна.');
    }
    return BulkOrderResultDto(
      BulkOrderResult(
        succeeded: succeeded
            .map((id) {
              if (id is! String || id.trim().isEmpty) {
                throw const OrderParseException('succeeded буруу байна.');
              }
              return id;
            })
            .toList(growable: false),
        failed: failed
            .map((item) {
              final value = _map(item, 'bulk failure');
              return BulkOrderFailure(
                orderId: _requiredString(value, 'orderId'),
                code: _requiredString(value, 'code'),
                message: _requiredString(value, 'message'),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
