import 'dart:typed_data';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/features/orders/data/order_dto.dart';
import 'package:carservice_business/features/orders/data/orders_data_source.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';

/// Remote adapter. JSON and Dio are deliberately kept below the repository
/// contract; controllers can depend on [OrdersRepository] or a fake.
class RemoteOrdersRepository implements OrdersRepository {
  RemoteOrdersRepository({OrdersDataSource? dataSource})
    : _dataSource = dataSource ?? RemoteOrdersDataSource();

  final OrdersDataSource _dataSource;

  @override
  Future<Result<PagedResult<ServiceOrderSummary>>> getOrders({
    OrderListQuery? query,
    OrderStatus? status,
    String? vehicleId,
    String? customerId,
    String? branchId,
    String? assignedToId,
    PaymentStatus? paymentStatus,
    bool? postpaid,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? q,
    int page = 1,
    int pageSize = 25,
  }) async {
    final effective =
        query ??
        OrderListQuery(
          status: status,
          vehicleId: vehicleId,
          customerId: customerId,
          branchId: branchId,
          assignedToId: assignedToId,
          paymentStatus: paymentStatus,
          postpaid: postpaid,
          dateFrom: dateFrom,
          dateTo: dateTo,
          q: q,
          page: page,
          pageSize: pageSize,
        );
    try {
      _validatePage(effective.page, effective.pageSize);
      final parsed = OrderPageDto.fromJson(
        await _dataSource.list(_listQuery(effective)),
      );
      return Ok(
        PagedResult(items: parsed.items, pagination: parsed.pagination),
      );
    } catch (error) {
      return Err(_error(error, 'Захиалгын жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<ServiceOrderDetail>> getOrderDetail(String id) async {
    try {
      return Ok(OrderDetailDto.fromJson(await _dataSource.detail(id)).value);
    } catch (error) {
      return Err(_error(error, 'Захиалгын мэдээлэл ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<String>> uploadIntakeFile(
    Uint8List bytes,
    String filename, {
    required bool signature,
  }) async {
    try {
      final raw = await _dataSource.uploadIntake(
        bytes,
        filename,
        signature ? 'image/png' : _imageMime(filename),
      );
      final url = raw is Map ? raw['url'] : null;
      if (url is! String || url.isEmpty) {
        return const Err(
          AppError(ErrorKind.unknown, 'Файл хадгалах хариу буруу байна'),
        );
      }
      return Ok(url);
    } catch (error) {
      return Err(_error(error, 'Файл хадгалж чадсангүй'));
    }
  }

  static String _imageMime(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Future<Result<ServiceOrderSummary>> createOrder({
    required String branchId,
    required String customerId,
    required String vehicleId,
    String? assignedToId,
    DateTime? scheduledAt,
    String? notes,
    String? appointmentId,
    int? estimatedDurationMinutes,
    OrderIntakeDraft? intake,
    bool? isPostpaid,
    bool? isInternal,
  }) async {
    // Server parser (order-create-request.ts) rejects a request carrying
    // both non-null: duration is derived from the appointment when one is
    // linked. Fail fast client-side rather than round-tripping a 422.
    if (appointmentId != null && estimatedDurationMinutes != null) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Цаг захиалгатай үед хугацааг цаг захиалгаас авна.',
        ),
      );
    }
    try {
      final body = <String, dynamic>{
        'branchId': branchId,
        'customerId': customerId,
        'vehicleId': vehicleId,
        if (assignedToId != null) 'assignedToId': assignedToId,
        if (scheduledAt != null)
          'scheduledAt': _businessLocalDateTime(scheduledAt),
        if (notes != null) 'notes': notes,
        if (appointmentId != null) 'appointmentId': appointmentId,
        if (estimatedDurationMinutes != null)
          'estimatedDurationMinutes': estimatedDurationMinutes,
        if (intake != null && !intake.isEmpty) 'intake': intake.toJson(),
        if (isPostpaid != null) 'isPostpaid': isPostpaid,
        if (isInternal != null) 'isInternal': isInternal,
      };
      return Ok(OrderSummaryDto.fromJson(await _dataSource.create(body)).value);
    } catch (error) {
      return Err(_error(error, 'Захиалга үүсгэж чадсангүй'));
    }
  }

  @override
  Future<Result<ServiceOrderDetail>> updateStatus(
    String id,
    OrderStatus status, {
    int? durationMinutes,
  }) async {
    try {
      return Ok(
        OrderDetailDto.fromJson(
          await _dataSource.patch(id, {
            'status': status.name,
            if (durationMinutes != null) 'durationMinutes': durationMinutes,
          }),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Захиалгын төлөв шинэчилж чадсангүй'));
    }
  }

  @override
  Future<Result<ServiceOrderDetail>> updateAssignment(
    String id,
    String assignedToId,
  ) async {
    try {
      return Ok(
        OrderDetailDto.fromJson(
          await _dataSource.patch(id, {'assignedToId': assignedToId}),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Хариуцагч шинэчилж чадсангүй'));
    }
  }

  @override
  Future<Result<void>> deleteOrder(String id) async {
    try {
      await _dataSource.delete(id);
      return const Ok(null);
    } catch (error) {
      return Err(_error(error, 'Захиалга устгаж чадсангүй'));
    }
  }

  @override
  Future<Result<OrderScheduleResult>> reviseExpectedFinish(
    String id,
    DateTime? expectedFinishAt, {
    bool confirmed = false,
  }) async {
    try {
      final json = _map(
        await _dataSource.expectedFinish(id, {
          'expectedFinishAt': expectedFinishAt == null
              ? null
              : _businessLocalDateTime(expectedFinishAt),
          'confirmed': confirmed,
        }),
      );
      return Ok(
        OrderScheduleResult(
          orderId: _string(json, 'orderId'),
          expectedFinishAt: _date(json, 'expectedFinishAt'),
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Дуусах хугацаа шинэчилж чадсангүй'));
    }
  }

  @override
  Future<Result<OrderScheduleResult>> rescheduleOrder(
    String id,
    DateTime scheduledAt, {
    bool confirmed = false,
  }) async {
    try {
      final json = _map(
        await _dataSource.schedule(id, {
          'scheduledAt': _businessLocalDateTime(scheduledAt),
          'confirmed': confirmed,
        }),
      );
      return Ok(
        OrderScheduleResult(
          orderId: _string(json, 'orderId'),
          scheduledAt: _requiredDate(json, 'scheduledAt'),
          previousScheduledAt: _date(json, 'previousScheduledAt'),
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Захиалга шилжүүлж чадсангүй'));
    }
  }

  @override
  Future<Result<ServiceItem>> addItem(
    String orderId, {
    required ItemKind kind,
    required String description,
    required double quantity,
    required double unitPrice,
    String? serviceId,
    String? diagnosticTemplateId,
  }) async {
    return addItemMoney(
      orderId,
      kind: kind,
      description: description,
      quantity: Money(quantity.toString()),
      unitPrice: Money(unitPrice.toString()),
      serviceId: serviceId,
      diagnosticTemplateId: diagnosticTemplateId,
    );
  }

  @override
  Future<Result<ServiceItem>> addItemMoney(
    String orderId, {
    required ItemKind kind,
    required String description,
    required Money quantity,
    required Money unitPrice,
    String? serviceId,
    String? diagnosticTemplateId,
  }) async {
    try {
      final body = <String, dynamic>{
        'kind': kind.name,
        'description': description,
        'quantity': quantity.raw,
        'unitPrice': unitPrice.raw,
        if (serviceId != null) 'serviceId': serviceId,
        if (diagnosticTemplateId != null)
          'diagnosticTemplateId': diagnosticTemplateId,
      };
      return Ok(
        ServiceItemDto.fromJson(
          _map(await _dataSource.addItem(orderId, body))['item'],
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Мөр нэмэж чадсангүй'));
    }
  }

  @override
  Future<Result<ServiceItem>> updateItem(
    String orderId,
    String itemId, {
    ItemKind? kind,
    String? description,
    double? quantity,
    double? unitPrice,
    ServiceItemStatus? status,
  }) async {
    return updateItemMoney(
      orderId,
      itemId,
      kind: kind,
      description: description,
      quantity: quantity == null ? null : Money(quantity.toString()),
      unitPrice: unitPrice == null ? null : Money(unitPrice.toString()),
      status: status,
    );
  }

  @override
  Future<Result<ServiceItem>> updateItemMoney(
    String orderId,
    String itemId, {
    ItemKind? kind,
    String? description,
    Money? quantity,
    Money? unitPrice,
    ServiceItemStatus? status,
  }) async {
    try {
      final body = <String, dynamic>{
        if (kind != null) 'kind': kind.name,
        if (description != null) 'description': description,
        if (quantity != null) 'quantity': quantity.raw,
        if (unitPrice != null) 'unitPrice': unitPrice.raw,
        if (status != null) 'status': status.name,
      };
      return Ok(
        ServiceItemDto.fromJson(
          _map(await _dataSource.patchItem(orderId, itemId, body))['item'],
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Мөр шинэчилж чадсангүй'));
    }
  }

  @override
  Future<Result<void>> removeItem(String orderId, String itemId) async {
    try {
      await _dataSource.deleteItem(orderId, itemId);
      return const Ok(null);
    } catch (error) {
      return Err(_error(error, 'Мөр цуцалж чадсангүй'));
    }
  }

  @override
  Future<Result<void>> cancelItem(String orderId, String itemId) async {
    try {
      await _dataSource.cancelItem(orderId, itemId);
      return const Ok(null);
    } catch (error) {
      return Err(_error(error, 'Мөр цуцалж чадсангүй'));
    }
  }

  @override
  Future<Result<ServiceItem>> changeItemStatus(
    String orderId,
    String itemId,
    ServiceItemStatus status,
  ) async {
    try {
      return Ok(
        ServiceItemDto.fromJson(
          _map(
            await _dataSource.itemStatus(orderId, itemId, {
              'status': status.name,
            }),
          )['item'],
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Мөрийн төлөв шинэчилж чадсангүй'));
    }
  }

  @override
  Future<Result<ServiceItem>> changeItemPrice(
    String orderId,
    String itemId,
    Money unitPrice,
  ) async {
    try {
      return Ok(
        ServiceItemDto.fromJson(
          _map(
            await _dataSource.itemPrice(orderId, itemId, {
              'unitPrice': unitPrice.raw,
            }),
          )['item'],
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Мөрийн үнэ шинэчилж чадсангүй'));
    }
  }

  @override
  Future<Result<OrderItemHistoryPage>> getItemHistory(
    String orderId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      _validatePage(page, pageSize);
      final json = _map(
        await _dataSource.itemHistory(orderId, {
          'page': page,
          'pageSize': pageSize,
        }),
      );
      final items = json['items'];
      if (items is! List) {
        throw const OrderParseException('Мөрийн түүх буруу байна.');
      }
      final actualPage = _positiveInt(json, 'page');
      final actualSize = _positiveInt(json, 'pageSize');
      final total = _int(json, 'total');
      final totalPages = _int(json, 'totalPages');
      return Ok(
        OrderItemHistoryPage(
          items: items
              .map((item) => ServiceItemDto.fromJson(item, history: true).value)
              .toList(growable: false),
          pagination: PaginationMeta(
            page: actualPage,
            pageSize: actualSize,
            total: total,
            totalPages: totalPages,
            hasPrev: actualPage > 1,
            hasNext: actualPage * actualSize < total,
          ),
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Мөрийн түүх ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<List<OrderPaymentRecord>>> getPayments(String orderId) async {
    try {
      final json = _map(await _dataSource.payments(orderId));
      final list = json['payments'];
      if (list is! List) {
        throw const OrderParseException('Төлбөрийн жагсаалт буруу байна.');
      }
      return Ok(list.map(_payment).toList(growable: false));
    } catch (error) {
      return Err(_error(error, 'Төлбөрийн түүх ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<OrderPaymentResult>> createPayment(
    String orderId, {
    required OrderPaymentMethod method,
    required Money amount,
    String? bank,
  }) async {
    try {
      final json = _map(
        await _dataSource.createPayment(orderId, {
          'method': method.name,
          'amount': amount.raw,
          if (bank != null && paymentMethodNeedsBank(method)) 'bank': bank,
        }),
      );
      return Ok(
        OrderPaymentResult(
          payment: _payment(json['payment']),
          totals: _totals(json['order']),
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Төлбөр бүртгэж чадсангүй'));
    }
  }

  @override
  Future<Result<BankSettings>> getBanks() async {
    try {
      final json = _map(await _dataSource.banks());
      final raw = json['enabledBanks'];
      if (raw is! List) {
        throw const OrderParseException('enabledBanks буруу байна.');
      }
      return Ok(BankSettings(raw.whereType<String>().toList(growable: false)));
    } catch (error) {
      return Err(_error(error, 'Банкны жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<OrderPaymentTotals>> reversePayment(
    String orderId,
    String paymentId,
  ) async {
    try {
      return Ok(
        _totals(
          _map(await _dataSource.reversePayment(orderId, paymentId))['order'],
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Төлбөр буцааж чадсангүй'));
    }
  }

  @override
  Future<Result<({bool qpayEnabled, OrderPayment? pending})>> getQPay(
    String orderId,
  ) async {
    try {
      final state = QPayStateDto.fromJson(await _dataSource.qpay(orderId))
          .value;
      return Ok((qpayEnabled: state.qpayEnabled, pending: state.pending));
    } catch (error) {
      return Err(_error(error, 'QPay мэдээлэл ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<OrderPayment>> createQPay(
    String orderId, {
    String? amount,
  }) async {
    try {
      return Ok(
        _qpayPayment(
          _map(
            await _dataSource.createQPay(orderId, amount: amount),
          )['payment'],
        ),
      );
    } catch (error) {
      return Err(_error(error, 'QPay нэхэмжлэл үүсгэж чадсангүй'));
    }
  }

  @override
  Future<Result<({bool paid, String? message})>> checkQPay(
    String orderId,
    String paymentId,
  ) async {
    try {
      final json = _map(
        await _dataSource.checkQPay(orderId, {'paymentId': paymentId}),
      );
      final paid = json['paid'];
      final message = json['message'];
      if (paid is! bool || (message != null && message is! String)) {
        throw const OrderParseException('QPay шалгалтын хариу буруу байна.');
      }
      return Ok((paid: paid, message: message as String?));
    } catch (error) {
      return Err(_error(error, 'QPay төлбөр шалгаж чадсангүй'));
    }
  }

  @override
  Future<Result<void>> cancelQPay(String orderId, String paymentId) async {
    try {
      await _dataSource.cancelQPay(orderId, {'paymentId': paymentId});
      return const Ok(null);
    } catch (error) {
      return Err(_error(error, 'QPay нэхэмжлэл цуцалж чадсангүй'));
    }
  }

  @override
  Future<Result<PostpaidPage>> getPostpaid({PostpaidQuery? query}) async {
    try {
      final effective = query ?? const PostpaidQuery();
      _validatePage(effective.page, effective.pageSize);
      final json = _map(await _dataSource.postpaid(_postpaidQuery(effective)));
      final vehicles = json['vehicles'];
      final orders = json['orders'];
      if (vehicles is! List || orders is! List) {
        throw const OrderParseException('Авлагын хариу буруу байна.');
      }
      return Ok(
        PostpaidPage(
          vehicles: vehicles.map(_postpaidVehicle).toList(growable: false),
          summary: _postpaidSummary(json['summary']),
          orders: orders
              .map((item) => OrderSummaryDto.fromJson(item).value)
              .toList(growable: false),
          pagination: _paginationFromMap(json['pagination']),
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Авлагын жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<List<AssignableUser>>> getAssignableUsers({
    String? branchId,
  }) async {
    try {
      final json = _map(
        await _dataSource.assignableUsers({
          if (branchId != null) 'branchId': branchId,
        }),
      );
      final list = json['users'];
      if (list is! List) {
        throw const OrderParseException('Хариуцагчийн жагсаалт буруу байна.');
      }
      return Ok(
        list
            .map((item) {
              final value = _map(item);
              return AssignableUser(
                id: _string(value, 'id'),
                firstName: _string(value, 'firstName'),
                lastName: _string(value, 'lastName'),
              );
            })
            .toList(growable: false),
      );
    } catch (error) {
      return Err(_error(error, 'Хариуцагчийн жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<BulkOrderResult>> bulkChangeStatus(
    List<String> orderIds,
    OrderStatus status, {
    int? durationMinutes,
  }) async {
    try {
      return Ok(
        BulkOrderResultDto.fromJson(
          await _dataSource.bulkStatus({
            'orderIds': orderIds,
            'status': status.name,
            if (durationMinutes != null) 'durationMinutes': durationMinutes,
          }),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Бөөн төлөвийн өөрчлөлт амжилтгүй'));
    }
  }

  @override
  Future<Result<BulkOrderResult>> bulkAssign(
    List<String> orderIds,
    String assignedToId,
  ) async {
    try {
      return Ok(
        BulkOrderResultDto.fromJson(
          await _dataSource.bulkAssign({
            'orderIds': orderIds,
            'assignedToId': assignedToId,
          }),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Бөөн хариуцагчийн өөрчлөлт амжилтгүй'));
    }
  }
}

/// Compatibility name for the Phase-0 presentation and existing tests.
class OrderRepository extends RemoteOrdersRepository {
  OrderRepository({super.dataSource});
}

Map<String, dynamic> _listQuery(OrderListQuery query) => {
  'page': query.page,
  'pageSize': query.pageSize,
  if (query.status != null) 'status': query.status!.name,
  if (query.branchId != null) 'branchId': query.branchId,
  if (query.assignedToId != null) 'assignedToId': query.assignedToId,
  if (query.paymentStatus != null) 'paymentStatus': query.paymentStatus!.name,
  if (query.postpaid != null) 'postpaid': query.postpaid.toString(),
  if (query.internal != null) 'internal': query.internal! ? 'yes' : 'no',
  if (query.dateFrom != null) 'dateFrom': _dateOnly(query.dateFrom!),
  if (query.dateTo != null) 'dateTo': _dateOnly(query.dateTo!),
  if (query.q != null && query.q!.isNotEmpty) 'q': query.q,
  if (query.vehicleId != null) 'vehicleId': query.vehicleId,
  if (query.customerId != null) 'customerId': query.customerId,
  if (query.plate != null && query.plate!.isNotEmpty) 'plate': query.plate,
};

Map<String, dynamic> _postpaidQuery(PostpaidQuery query) => {
  'page': query.page,
  'pageSize': query.pageSize,
  if (query.vehicleId != null) 'vehicleId': query.vehicleId,
  if (query.paymentStatus != null) 'paymentStatus': query.paymentStatus!.name,
  if (query.dateFrom != null) 'dateFrom': _dateOnly(query.dateFrom!),
  if (query.dateTo != null) 'dateTo': _dateOnly(query.dateTo!),
};

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

Map<String, dynamic> _map(Object? raw) {
  if (raw is! Map) throw const OrderParseException('Хариу буруу байна.');
  return Map<String, dynamic>.from(raw);
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw OrderParseException('$key буруу байна.');
  }
  return value.trim();
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) return value;
  throw OrderParseException('$key буруу байна.');
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(value)) {
    throw OrderParseException('$key огноо буруу байна.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw OrderParseException('$key огноо буруу байна.');
  return parsed.toLocal();
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _date(json, key);
  if (value == null) throw OrderParseException('$key буруу байна.');
  return value;
}

Money _money(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String ||
      !RegExp(r'^(?:0|[1-9]\d*)(?:\.\d+)?$').hasMatch(value)) {
    throw OrderParseException('$key мөнгөн дүн буруу байна.');
  }
  return Money(value);
}

/// Balance-type amounts (`remainingAmount`, `balanceAmount`) are
/// `total − paid` on the server and go negative when an order is overpaid —
/// e.g. an item is cancelled after full payment. Rejecting them failed the
/// whole postpaid page and reported a committed payment reversal as an error.
Money _balance(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String ||
      !RegExp(r'^-?(?:0|[1-9]\d*)(?:\.\d+)?$').hasMatch(value)) {
    throw OrderParseException('$key мөнгөн дүн буруу байна.');
  }
  return Money(value);
}

OrderPaymentRecord _payment(Object? raw) {
  final json = _map(raw);
  final method = _string(json, 'method');
  final status = _string(json, 'status');
  return OrderPaymentRecord(
    id: _string(json, 'id'),
    amountMoney: _money(json, 'amount'),
    method: OrderPaymentMethod.fromString(method),
    status: OrderPaymentRecordStatus.fromString(status),
    paidAt: _date(json, 'paidAt'),
    createdAt: _requiredDate(json, 'createdAt'),
    bank: json['bank'] is String ? json['bank'] as String : null,
    settlementId:
        json['settlementId'] is String &&
            (json['settlementId'] as String).isNotEmpty
        ? json['settlementId'] as String
        : null,
    locked: json['locked'] == true,
  );
}

OrderPaymentTotals _totals(Object? raw) {
  final json = _map(raw);
  final status = json['paymentStatus'];
  if (status is! String) {
    throw const OrderParseException('paymentStatus буруу байна.');
  }
  return OrderPaymentTotals(
    totalAmountMoney: _money(json, 'totalAmount'),
    paidAmountMoney: _money(json, 'paidAmount'),
    remainingAmountMoney: _balance(json, 'remainingAmount'),
    paymentStatus:
        PaymentStatus.tryParse(status) ??
        (throw const OrderParseException('paymentStatus буруу байна.')),
  );
}

OrderPayment _qpayPayment(Object? raw) {
  final json = _map(raw);
  final amount = _money(json, 'amount');
  final urls = json['urls'];
  if (urls != null && urls is! List) {
    throw const OrderParseException('QPay холбоос буруу байна.');
  }
  final urlItems = urls is List ? urls : const <Object?>[];
  return OrderPayment(
    id: _string(json, 'id'),
    amount: amount.asDouble,
    amountMoney: amount,
    qrImage: _optionalText(json, 'qrImage'),
    qrText: _optionalText(json, 'qrText'),
    urls: urlItems
        .map(_parseQPayUrl)
        .whereType<QPayBankUrl>()
        .toList(growable: false),
  );
}

QPayBankUrl? _parseQPayUrl(Object? raw) {
  try {
    final value = _map(raw);
    return QPayBankUrl(
      name: _string(value, 'name'),
      nameMn: _optionalText(value, 'name_mn') ?? _string(value, 'name'),
      logo: _optionalText(value, 'logo') ?? '',
      description: _optionalText(value, 'description') ?? '',
      link: _string(value, 'link'),
    );
  } on OrderParseException {
    // Ignore one malformed provider URL without discarding the valid invoice.
    return null;
  }
}

String? _optionalText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw OrderParseException('$key буруу байна.');
  return value;
}

PostpaidVehicleAggregate _postpaidVehicle(Object? raw) {
  final json = _map(raw);
  return PostpaidVehicleAggregate(
    id: _string(json, 'id'),
    plate: _string(json, 'plate'),
    make: _string(json, 'make'),
    model: _string(json, 'model'),
    customer: json['customer'] == null
        ? null
        : OrderCustomerDto.fromJson(json['customer']).value,
    orderCount: _int(json, 'orderCount'),
    totalAmountMoney: _money(json, 'totalAmount'),
    paidAmountMoney: _money(json, 'paidAmount'),
    balanceAmountMoney: _balance(json, 'balanceAmount'),
  );
}

PostpaidSummary _postpaidSummary(Object? raw) {
  final json = _map(raw);
  return PostpaidSummary(
    orderCount: _int(json, 'orderCount'),
    totalAmountMoney: _money(json, 'totalAmount'),
    paidAmountMoney: _money(json, 'paidAmount'),
    balanceAmountMoney: _balance(json, 'balanceAmount'),
  );
}

PaginationMeta _paginationFromMap(Object? raw) {
  final json = _map(raw);
  final prev = json['hasPrev'];
  final next = json['hasNext'];
  if (prev is! bool || next is! bool) {
    throw const OrderParseException('Хуудаслалт буруу байна.');
  }
  return PaginationMeta(
    page: _positiveInt(json, 'page'),
    pageSize: _positiveInt(json, 'pageSize'),
    total: _int(json, 'total'),
    totalPages: _int(json, 'totalPages'),
    hasPrev: prev,
    hasNext: next,
  );
}

AppError _error(Object error, String fallback) => switch (error) {
  AppError value => value,
  OrderParseException value => AppError(ErrorKind.unknown, value.message),
  _ => AppError(ErrorKind.unknown, fallback),
};

String _businessLocalDateTime(DateTime value) {
  String two(int item) => item.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}T${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

int _positiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value >= 1) return value;
  throw OrderParseException('$key буруу байна.');
}

void _validatePage(int page, int pageSize) {
  if (page < 1 || pageSize < 1) {
    throw const OrderParseException('page/pageSize буруу байна.');
  }
}
