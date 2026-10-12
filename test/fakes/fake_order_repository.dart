import 'dart:typed_data';

import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';

/// Hand-written fake for [OrdersRepository].
///
/// Deterministic in-memory seed data; no network, no async delay beyond a
/// microtask. Mutating methods (`updateStatus`, item CRUD, payment) mutate
/// the in-memory detail so a controller test can observe the effect of its
/// own action, matching what the real API would report back.
class FakeOrderRepository implements OrdersRepository {
  FakeOrderRepository({
    bool seedPostpaid = false,
    List<ServiceOrderDetail> seedOrders = const [],
  }) : _orders = [_seedOrder(isPostpaid: seedPostpaid), ...seedOrders];

  final List<ServiceOrderDetail> _orders;
  final Map<String, List<ServiceItem>> _itemHistory = {};
  final Map<String, List<OrderPaymentRecord>> _payments = {};
  final Map<String, OrderPayment> _qpayPending = {};

  /// Tests flip this to simulate a tenant without QPay configured.
  bool qpayEnabled = true;

  /// Tests set this to make getQPay fail (status load error).
  bool qpayLoadFails = false;

  /// Amount of the last createQPay call (null = none / omitted).
  String? lastQPayAmount;
  final Set<String> _qpayPaid = {};
  int _paymentSequence = 0;

  static ServiceOrderDetail _seedOrder({
    String id = 'order-1',
    OrderStatus status = OrderStatus.SCHEDULED,
    PaymentStatus paymentStatus = PaymentStatus.UNPAID,
    bool isPostpaid = false,
    bool isInternal = false,
  }) {
    return ServiceOrderDetail(
      id: id,
      number: 'A-0001',
      status: status,
      paymentStatus: paymentStatus,
      isPostpaid: isPostpaid,
      isInternal: isInternal,
      scheduledAt: DateTime(2026, 1, 10),
      createdAt: DateTime(2026, 1, 9),
      customer: const CustomerSummary(
        id: 'cust-1',
        fullName: 'Бат',
        phone: '99001122',
      ),
      vehicle: const VehicleSummary(
        id: 'veh-1',
        plate: '1234ABC',
        make: 'Toyota',
        model: 'Prius',
      ),
      branch: const BranchSummary(id: 'branch-1', name: 'Толгойт салбар'),
      items: const [],
      reports: const [],
    );
  }

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
    lastListQuery = effective;
    if (effective.page < 1 || effective.pageSize < 1) {
      return const Err(AppError(ErrorKind.unknown, 'Хуудаслалт буруу байна'));
    }
    final filtered = _orders.where((o) {
      if (effective.status != null && o.status != effective.status) {
        return false;
      }
      if (effective.vehicleId != null && o.vehicle.id != effective.vehicleId) {
        return false;
      }
      if (effective.customerId != null &&
          o.customer.id != effective.customerId) {
        return false;
      }
      if (effective.branchId != null && o.branch.id != effective.branchId) {
        return false;
      }
      if (effective.assignedToId != null &&
          o.assignedTo?.id != effective.assignedToId) {
        return false;
      }
      if (effective.paymentStatus != null &&
          o.paymentStatus != effective.paymentStatus) {
        return false;
      }
      if (effective.postpaid != null && o.isPostpaid != effective.postpaid) {
        return false;
      }
      if (effective.internal != null && o.isInternal != effective.internal) {
        return false;
      }
      final date = o.scheduledAt;
      if (effective.dateFrom != null &&
          (date == null || date.isBefore(effective.dateFrom!))) {
        return false;
      }
      if (effective.dateTo != null) {
        final end = DateTime(
          effective.dateTo!.year,
          effective.dateTo!.month,
          effective.dateTo!.day,
          23,
          59,
          59,
          999,
        );
        if (date == null || date.isAfter(end)) return false;
      }
      if (effective.q != null && effective.q!.isNotEmpty) {
        final needle = effective.q!.toLowerCase();
        final customer = '${o.customer.fullName ?? ''} ${o.customer.phone}'
            .toLowerCase();
        final vehicle =
            '${o.vehicle.plate} ${o.vehicle.make} ${o.vehicle.model}'
                .toLowerCase();
        if (!o.number.toLowerCase().contains(needle) &&
            !customer.contains(needle) &&
            !vehicle.contains(needle)) {
          return false;
        }
      }
      return true;
    }).toList();
    final start = (effective.page - 1) * effective.pageSize;
    final pageItems = start >= filtered.length
        ? <ServiceOrderSummary>[]
        : filtered.skip(start).take(effective.pageSize).toList(growable: false);
    final totalPages = filtered.isEmpty
        ? 0
        : (filtered.length / effective.pageSize).ceil();
    return Ok(
      PagedResult(
        items: pageItems,
        pagination: PaginationMeta(
          page: effective.page,
          pageSize: effective.pageSize,
          total: filtered.length,
          totalPages: totalPages,
          hasPrev: effective.page > 1,
          hasNext: effective.page < totalPages,
        ),
      ),
    );
  }

  @override
  Future<Result<ServiceOrderDetail>> getOrderDetail(String id) async {
    final found = _orders.where((o) => o.id == id).firstOrNull;
    if (found == null) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    return Ok(found);
  }

  /// Last `isPostpaid` passed to [createOrder] (null when omitted).
  bool? lastIsPostpaid;

  /// Last `isInternal` passed to [createOrder] (null when omitted).
  bool? lastIsInternal;

  /// Last query passed to [getOrders] (to assert the server filter).
  OrderListQuery? lastListQuery;

  /// Last `intake` passed to [createOrder] (null when none).
  OrderIntakeDraft? lastIntake;

  /// Files accepted by [uploadIntakeFile], in call order.
  final List<({String filename, bool signature})> uploadedIntakeFiles = [];

  /// When set, [uploadIntakeFile] fails with this error.
  AppError? uploadIntakeFailure;

  @override
  Future<Result<String>> uploadIntakeFile(
    Uint8List bytes,
    String filename, {
    required bool signature,
  }) async {
    if (uploadIntakeFailure != null) return Err(uploadIntakeFailure!);
    uploadedIntakeFiles.add((filename: filename, signature: signature));
    return Ok('/uploads/orders/intake/fake-${uploadedIntakeFiles.length}.png');
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
    lastIsInternal = isInternal;
    lastIntake = intake;
    lastIsPostpaid = isPostpaid;
    // Mirrors the server parser (order-create-request.ts): mutually
    // exclusive, so the fake cannot accept a payload the real API rejects.
    if (appointmentId != null && estimatedDurationMinutes != null) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Цаг захиалгатай үед хугацааг цаг захиалгаас авна.',
        ),
      );
    }
    final created = _copyWith(
      _seedOrder(id: 'order-${_orders.length + 1}'),
      branch: BranchSummary(id: branchId, name: 'Fake branch'),
      customer: CustomerSummary(
        id: customerId,
        fullName: 'Fake customer',
        phone: '',
      ),
      vehicle: VehicleSummary(id: vehicleId, plate: '', make: '', model: ''),
      scheduledAt: scheduledAt,
      setScheduledAt: true,
      notes: notes,
      assignedTo: assignedToId == null
          ? null
          : const UserSummary(
              id: 'user-1',
              firstName: 'Fake',
              lastName: 'User',
            ),
      setAssignedTo: true,
      isInternal: isInternal,
    );
    _orders.add(created);
    return Ok(created);
  }

  @override
  Future<Result<ServiceOrderDetail>> updateStatus(
    String id,
    OrderStatus status, {
    int? durationMinutes,
  }) async {
    final index = _orders.indexWhere((o) => o.id == id);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    final current = _orders[index];
    final startedAt = status == OrderStatus.IN_PROGRESS
        ? (current.startedAt ?? DateTime(2026, 1, 10))
        : current.startedAt;
    final expectedFinishAt = durationMinutes == null
        ? current.expectedFinishAt
        : (startedAt?.add(Duration(minutes: durationMinutes)));
    final updated = _copyWith(
      current,
      status: status,
      startedAt: startedAt,
      completedAt: status == OrderStatus.COMPLETED
          ? DateTime(2026, 1, 10)
          : current.completedAt,
      expectedFinishAt: expectedFinishAt,
      estimatedDurationMinutes:
          durationMinutes ?? current.estimatedDurationMinutes,
    );
    _orders[index] = updated;
    return Ok(updated);
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
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    final item = ServiceItem(
      id: 'item-${_orders[index].items.length + 1}',
      kind: kind,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      total: quantity * unitPrice,
      serviceId: serviceId,
      diagnosticTemplateId: diagnosticTemplateId,
      quantityMoney: Money(quantity.toString()),
      unitPriceMoney: Money(unitPrice.toString()),
      totalMoney: Money((quantity * unitPrice).toString()),
    );
    _orders[index] = _copyWith(
      _orders[index],
      items: [..._orders[index].items, item],
    );
    return Ok(item);
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
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    final total = _multiplyMoney(quantity, unitPrice);
    final item = ServiceItem(
      id: 'item-${_orders[index].items.length + 1}',
      kind: kind,
      description: description,
      quantity: quantity.asDouble,
      unitPrice: unitPrice.asDouble,
      total: total.asDouble,
      serviceId: serviceId,
      diagnosticTemplateId: diagnosticTemplateId,
      quantityMoney: quantity,
      unitPriceMoney: unitPrice,
      totalMoney: total,
    );
    _orders[index] = _copyWith(
      _orders[index],
      items: [..._orders[index].items, item],
    );
    return Ok(item);
  }

  @override
  Future<Result<void>> removeItem(String orderId, String itemId) =>
      _cancelItem(orderId, itemId);

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
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    final itemIndex = _orders[index].items.indexWhere((i) => i.id == itemId);
    if (itemIndex == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Мөр олдсонгүй'));
    }
    final current = _orders[index].items[itemIndex];
    final updated = ServiceItem(
      id: current.id,
      kind: kind ?? current.kind,
      description: description ?? current.description,
      quantity: quantity ?? current.quantity,
      unitPrice: unitPrice ?? current.unitPrice,
      total: (quantity ?? current.quantity) * (unitPrice ?? current.unitPrice),
      serviceId: current.serviceId,
      status: status ?? current.status,
      startedAt: current.startedAt,
      completedAt: current.completedAt,
      cancelledAt: current.cancelledAt,
      cancelledById: current.cancelledById,
      cancelledBy: current.cancelledBy,
      diagnosticTemplateId: current.diagnosticTemplateId,
      diagnosticReportId: current.diagnosticReportId,
      quantityMoney: quantity == null
          ? current.quantityMoney
          : Money(quantity.toString()),
      unitPriceMoney: unitPrice == null
          ? current.unitPriceMoney
          : Money(unitPrice.toString()),
      totalMoney: Money(
        ((quantity ?? current.quantity) * (unitPrice ?? current.unitPrice))
            .toString(),
      ),
    );
    final items = [..._orders[index].items];
    items[itemIndex] = updated;
    _orders[index] = _copyWith(_orders[index], items: items);
    return Ok(updated);
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
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    final itemIndex = _orders[index].items.indexWhere((i) => i.id == itemId);
    if (itemIndex == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Мөр олдсонгүй'));
    }
    final current = _orders[index].items[itemIndex];
    final nextQuantity =
        quantity ?? current.quantityMoney ?? Money(current.quantity.toString());
    final nextUnitPrice =
        unitPrice ??
        current.unitPriceMoney ??
        Money(current.unitPrice.toString());
    final total = _multiplyMoney(nextQuantity, nextUnitPrice);
    final updated = ServiceItem(
      id: current.id,
      kind: kind ?? current.kind,
      description: description ?? current.description,
      quantity: nextQuantity.asDouble,
      unitPrice: nextUnitPrice.asDouble,
      total: total.asDouble,
      serviceId: current.serviceId,
      status: status ?? current.status,
      startedAt: current.startedAt,
      completedAt: current.completedAt,
      cancelledAt: current.cancelledAt,
      cancelledById: current.cancelledById,
      cancelledBy: current.cancelledBy,
      diagnosticTemplateId: current.diagnosticTemplateId,
      diagnosticReportId: current.diagnosticReportId,
      quantityMoney: nextQuantity,
      unitPriceMoney: nextUnitPrice,
      totalMoney: total,
    );
    final items = [..._orders[index].items]..[itemIndex] = updated;
    _orders[index] = _copyWith(_orders[index], items: items);
    return Ok(updated);
  }

  @override
  Future<Result<({bool qpayEnabled, OrderPayment? pending})>> getQPay(
    String orderId,
  ) async {
    if (!_orders.any((order) => order.id == orderId)) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    if (qpayLoadFails) {
      return const Err(AppError(ErrorKind.unknown, 'QPay алдаа'));
    }
    return Ok((qpayEnabled: qpayEnabled, pending: _qpayPending[orderId]));
  }

  @override
  Future<Result<OrderPayment>> createQPay(
    String orderId, {
    String? amount,
  }) async {
    if (!_orders.any((order) => order.id == orderId)) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    lastQPayAmount = amount;
    final payment = OrderPayment(
      id: 'qpay-$orderId',
      amount: _paymentTotals(orderId).remainingAmount,
      amountMoney: _paymentTotals(orderId).remainingAmountMoney,
    );
    _qpayPending[orderId] = payment;
    return Ok(payment);
  }

  @override
  Future<Result<({bool paid, String? message})>> checkQPay(
    String orderId,
    String paymentId,
  ) async {
    if (!_orders.any((order) => order.id == orderId)) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    if (_qpayPending[orderId]?.id != paymentId) {
      return const Err(AppError(ErrorKind.notFound, 'QPay төлбөр олдсонгүй'));
    }
    return Ok((paid: _qpayPaid.contains(orderId), message: null));
  }

  @override
  Future<Result<void>> cancelQPay(String orderId, String paymentId) async {
    if (!_orders.any((order) => order.id == orderId)) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    if (_qpayPending[orderId]?.id != paymentId) {
      return const Err(AppError(ErrorKind.notFound, 'QPay төлбөр олдсонгүй'));
    }
    _qpayPending.remove(orderId);
    return const Ok(null);
  }

  @override
  Future<Result<ServiceOrderDetail>> updateAssignment(
    String id,
    String? assignedToId,
  ) async {
    final index = _orders.indexWhere((o) => o.id == id);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    final current = _orders[index];
    final updated = _copyWith(
      current,
      assignedTo: assignedToId == null
          ? null
          : const UserSummary(
              id: 'user-1',
              firstName: 'Fake',
              lastName: 'User',
            ),
      setAssignedTo: true,
    );
    _orders[index] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<void>> deleteOrder(String id) async {
    final index = _orders.indexWhere((o) => o.id == id);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    _orders.removeAt(index);
    return const Ok(null);
  }

  @override
  Future<Result<OrderScheduleResult>> reviseExpectedFinish(
    String id,
    DateTime? expectedFinishAt, {
    bool confirmed = false,
  }) async => _scheduleExpectedFinish(id, expectedFinishAt);

  @override
  Future<Result<OrderScheduleResult>> rescheduleOrder(
    String id,
    DateTime scheduledAt, {
    bool confirmed = false,
  }) async => _scheduleOrder(id, scheduledAt);

  @override
  Future<Result<void>> cancelItem(String orderId, String itemId) =>
      _cancelItem(orderId, itemId);

  Future<Result<void>> _cancelItem(String orderId, String itemId) async {
    final orderIndex = _orders.indexWhere((o) => o.id == orderId);
    if (orderIndex == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    final itemIndex = _orders[orderIndex].items.indexWhere(
      (i) => i.id == itemId,
    );
    if (itemIndex == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Мөр олдсонгүй'));
    }
    final item = _orders[orderIndex].items[itemIndex];
    if (item.status == ServiceItemStatus.CANCELLED) return const Ok(null);
    final items = [..._orders[orderIndex].items];
    items[itemIndex] = ServiceItem(
      id: item.id,
      kind: item.kind,
      description: item.description,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      total: item.total,
      serviceId: item.serviceId,
      status: ServiceItemStatus.CANCELLED,
      startedAt: item.startedAt,
      completedAt: item.completedAt,
      cancelledAt: DateTime(2026, 1, 10),
      cancelledById: 'fake-user',
      cancelledBy: const UserSummary(
        id: 'fake-user',
        firstName: 'Fake',
        lastName: 'User',
      ),
      diagnosticTemplateId: item.diagnosticTemplateId,
      diagnosticReportId: item.diagnosticReportId,
      quantityMoney: item.quantityMoney,
      unitPriceMoney: item.unitPriceMoney,
      totalMoney: item.totalMoney,
    );
    _orders[orderIndex] = _copyWith(_orders[orderIndex], items: items);
    _recordItemHistory(orderId, items[itemIndex]);
    return const Ok(null);
  }

  @override
  Future<Result<ServiceItem>> changeItemStatus(
    String orderId,
    String itemId,
    ServiceItemStatus status,
  ) async {
    if (status == ServiceItemStatus.CANCELLED) {
      return const Err(
        AppError(ErrorKind.unknown, 'Цуцлалт тусгай үйлдлээр хийгдэнэ'),
      );
    }
    final order = _orders.where((item) => item.id == orderId).firstOrNull;
    final item = order?.items.where((value) => value.id == itemId).firstOrNull;
    if (item?.status == ServiceItemStatus.CANCELLED) {
      return const Err(
        AppError(ErrorKind.unknown, 'Цуцлагдсан мөрийг өөрчлөх боломжгүй'),
      );
    }
    return updateItem(orderId, itemId, status: status);
  }

  @override
  Future<Result<ServiceItem>> changeItemPrice(
    String orderId,
    String itemId,
    Money unitPrice,
  ) => updateItemMoney(orderId, itemId, unitPrice: unitPrice);

  @override
  Future<Result<OrderItemHistoryPage>> getItemHistory(
    String orderId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (page < 1 || pageSize < 1) {
      return const Err(AppError(ErrorKind.unknown, 'Хуудаслалт буруу байна'));
    }
    final items = List<ServiceItem>.unmodifiable(
      (_itemHistory[orderId] ?? const <ServiceItem>[]).where(
        (item) => item.status == ServiceItemStatus.CANCELLED,
      ),
    );
    final start = (page - 1) * pageSize;
    final selected = start >= items.length
        ? const <ServiceItem>[]
        : items.skip(start).take(pageSize).toList(growable: false);
    final totalPages = items.isEmpty ? 0 : (items.length / pageSize).ceil();
    return Ok(
      OrderItemHistoryPage(
        items: selected,
        pagination: PaginationMeta(
          page: page,
          pageSize: pageSize,
          total: items.length,
          totalPages: totalPages,
          hasPrev: page > 1,
          hasNext: page < totalPages,
        ),
      ),
    );
  }

  @override
  Future<Result<List<OrderPaymentRecord>>> getPayments(String orderId) async {
    if (!_orders.any((order) => order.id == orderId)) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    return Ok(List.unmodifiable(_payments[orderId] ?? const []));
  }

  @override
  Future<Result<OrderPaymentResult>> createPayment(
    String orderId, {
    required OrderPaymentMethod method,
    required Money amount,
    String? bankId,
  }) async {
    if (!_orders.any((order) => order.id == orderId)) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    final needsBank = paymentMethodNeedsBank(method);
    final payment = OrderPaymentRecord(
      id: 'payment-${++_paymentSequence}',
      amountMoney: amount,
      method: method,
      status: OrderPaymentRecordStatus.PAID,
      paidAt: DateTime(2026),
      createdAt: DateTime(2026),
      bankId: needsBank ? bankId : null,
      bankLabel: needsBank && bankId != null
          ? paymentBankLabelIn(accounts, bankId)
          : null,
    );
    (_payments[orderId] ??= <OrderPaymentRecord>[]).add(payment);
    final totals = _paymentTotals(orderId);
    final orderIndex = _orders.indexWhere((order) => order.id == orderId);
    _orders[orderIndex] = _copyWith(
      _orders[orderIndex],
      paymentStatus: totals.paymentStatus,
      paidAmount: totals.paidAmount,
    );
    return Ok(OrderPaymentResult(payment: payment, totals: totals));
  }

  /// Payment accounts the fake offers; tests may narrow it.
  List<PaymentBank> accounts = const [
    PaymentBank(id: 'acc-khan', label: 'Хаан банк'),
    PaymentBank(id: 'acc-golomt', label: 'Голомт банк'),
    PaymentBank(id: 'acc-tdb', label: 'Худалдаа хөгжлийн банк'),
    PaymentBank(id: 'pos-khan', label: 'Хаан банк', isPos: true),
    PaymentBank(id: 'pos-tdb', label: 'Худалдаа хөгжлийн банк', isPos: true),
  ];

  @override
  Future<Result<BankSettings>> getBanks() async => Ok(BankSettings(accounts));

  @override
  Future<Result<OrderPaymentTotals>> reversePayment(
    String orderId,
    String paymentId,
  ) async {
    final payments = _payments[orderId];
    if (payments == null) {
      return const Err(AppError(ErrorKind.notFound, 'Төлбөр олдсонгүй'));
    }
    final index = payments.indexWhere((payment) => payment.id == paymentId);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Төлбөр олдсонгүй'));
    }
    final current = payments[index];
    if (current.status != OrderPaymentRecordStatus.CANCELLED) {
      payments[index] = OrderPaymentRecord(
        id: current.id,
        amountMoney: current.amountMoney,
        method: current.method,
        status: OrderPaymentRecordStatus.CANCELLED,
        paidAt: current.paidAt,
        createdAt: current.createdAt,
        bank: current.bank,
        bankId: current.bankId,
        bankLabel: current.bankLabel,
      );
    }
    final totals = _paymentTotals(orderId);
    final orderIndex = _orders.indexWhere((order) => order.id == orderId);
    _orders[orderIndex] = _copyWith(
      _orders[orderIndex],
      paymentStatus: totals.paymentStatus,
      paidAmount: totals.paidAmount,
    );
    return Ok(totals);
  }

  @override
  Future<Result<PostpaidPage>> getPostpaid({PostpaidQuery? query}) async {
    final effective = query ?? const PostpaidQuery();
    if (effective.page < 1 || effective.pageSize < 1) {
      return const Err(AppError(ErrorKind.unknown, 'Хуудаслалт буруу байна'));
    }
    final allPostpaid = _orders
        .where((order) => order.isPostpaid)
        .toList(growable: false);
    final historyOrders = allPostpaid
        .where((order) {
          if (effective.vehicleId != null &&
              order.vehicle.id != effective.vehicleId) {
            return false;
          }
          if (effective.paymentStatus != null &&
              order.paymentStatus != effective.paymentStatus) {
            return false;
          }
          final date = order.scheduledAt;
          if (effective.dateFrom != null &&
              (date == null || date.isBefore(effective.dateFrom!))) {
            return false;
          }
          if (effective.dateTo != null &&
              (date == null ||
                  date.isAfter(
                    DateTime(
                      effective.dateTo!.year,
                      effective.dateTo!.month,
                      effective.dateTo!.day,
                      23,
                      59,
                      59,
                      999,
                    ),
                  ))) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final aggregateOrders = allPostpaid
        .where((order) => order.status != OrderStatus.CANCELLED)
        .toList(growable: false);
    final start = (effective.page - 1) * effective.pageSize;
    final pageOrders = start >= historyOrders.length
        ? const <ServiceOrderSummary>[]
        : historyOrders
              .skip(start)
              .take(effective.pageSize)
              .toList(growable: false);
    final totalPages = historyOrders.isEmpty
        ? 0
        : (historyOrders.length / effective.pageSize).ceil();
    final total = aggregateOrders.fold<Money>(
      const Money('0'),
      (sum, order) =>
          _addMoney(sum, order.totalAmountMoney ?? _ordersTotal(order)),
    );
    final paid = aggregateOrders.fold<Money>(
      const Money('0'),
      (sum, order) => _addMoney(
        sum,
        order.paidAmountMoney ?? Money((order.paidAmount ?? 0).toString()),
      ),
    );
    final grouped = <String, List<ServiceOrderDetail>>{};
    for (final order in allPostpaid) {
      (grouped[order.vehicle.id] ??= <ServiceOrderDetail>[]).add(order);
    }
    final vehicles = grouped.values
        .map((orders) {
          final first = orders.first;
          final activeOrders = orders
              .where((order) => order.status != OrderStatus.CANCELLED)
              .toList(growable: false);
          final vehicleTotal = activeOrders.fold<Money>(
            const Money('0'),
            (sum, order) =>
                _addMoney(sum, order.totalAmountMoney ?? _ordersTotal(order)),
          );
          final vehiclePaid = activeOrders.fold<Money>(
            const Money('0'),
            (sum, order) => _addMoney(
              sum,
              order.paidAmountMoney ??
                  Money((order.paidAmount ?? 0).toString()),
            ),
          );
          return PostpaidVehicleAggregate(
            id: first.vehicle.id,
            plate: first.vehicle.plate,
            make: first.vehicle.make,
            model: first.vehicle.model,
            customer: first.customer,
            orderCount: activeOrders.length,
            totalAmountMoney: vehicleTotal,
            paidAmountMoney: vehiclePaid,
            balanceAmountMoney: _subtractMoney(vehicleTotal, vehiclePaid),
          );
        })
        .toList(growable: false);
    return Ok(
      PostpaidPage(
        vehicles: vehicles,
        summary: PostpaidSummary(
          orderCount: aggregateOrders.length,
          totalAmountMoney: total,
          paidAmountMoney: paid,
          balanceAmountMoney: _subtractMoney(total, paid),
        ),
        orders: pageOrders,
        pagination: PaginationMeta(
          page: effective.page,
          pageSize: effective.pageSize,
          total: historyOrders.length,
          totalPages: totalPages,
          hasPrev: effective.page > 1,
          hasNext: effective.page < totalPages,
        ),
      ),
    );
  }

  @override
  Future<Result<List<AssignableUser>>> getAssignableUsers({
    String? branchId,
  }) async => const Ok([
    AssignableUser(id: 'user-1', firstName: 'Fake', lastName: 'User'),
  ]);

  @override
  Future<Result<BulkOrderResult>> bulkChangeStatus(
    List<String> orderIds,
    OrderStatus status, {
    int? durationMinutes,
  }) async {
    final succeeded = <String>[];
    final failed = <BulkOrderFailure>[];
    for (final id in orderIds) {
      final result = await updateStatus(
        id,
        status,
        durationMinutes: durationMinutes,
      );
      if (result is Ok) {
        succeeded.add(id);
      } else {
        failed.add(
          BulkOrderFailure(
            orderId: id,
            code: 'NOT_FOUND',
            message: 'Захиалга олдсонгүй',
          ),
        );
      }
    }
    return Ok(BulkOrderResult(succeeded: succeeded, failed: failed));
  }

  @override
  Future<Result<BulkOrderResult>> bulkAssign(
    List<String> orderIds,
    String? assignedToId,
  ) async {
    final succeeded = <String>[];
    final failed = <BulkOrderFailure>[];
    for (final id in orderIds) {
      final result = await updateAssignment(id, assignedToId);
      if (result is Ok) {
        succeeded.add(id);
      } else {
        failed.add(
          BulkOrderFailure(
            orderId: id,
            code: 'NOT_FOUND',
            message: 'Захиалга олдсонгүй',
          ),
        );
      }
    }
    return Ok(BulkOrderResult(succeeded: succeeded, failed: failed));
  }

  ServiceOrderDetail _copyWith(
    ServiceOrderDetail o, {
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    double? paidAmount,
    List<ServiceItem>? items,
    UserSummary? assignedTo,
    bool setAssignedTo = false,
    DateTime? scheduledAt,
    bool setScheduledAt = false,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? expectedFinishAt,
    bool setExpectedFinishAt = false,
    int? estimatedDurationMinutes,
    String? notes,
    BranchSummary? branch,
    CustomerSummary? customer,
    VehicleSummary? vehicle,
    bool? isPostpaid,
    bool? isInternal,
  }) {
    return ServiceOrderDetail(
      id: o.id,
      number: o.number,
      status: status ?? o.status,
      paymentStatus: paymentStatus ?? o.paymentStatus,
      scheduledAt: setScheduledAt
          ? scheduledAt
          : (scheduledAt ?? o.scheduledAt),
      startedAt: startedAt ?? o.startedAt,
      completedAt: completedAt ?? o.completedAt,
      totalAmount: o.totalAmount,
      paidAmount: paidAmount ?? o.paidAmount,
      notes: notes ?? o.notes,
      createdAt: o.createdAt,
      customer: customer ?? o.customer,
      vehicle: vehicle ?? o.vehicle,
      branch: branch ?? o.branch,
      assignedTo: setAssignedTo ? assignedTo : o.assignedTo,
      isPostpaid: isPostpaid ?? o.isPostpaid,
      hasLockedPayment: o.hasLockedPayment,
      isInternal: isInternal ?? o.isInternal,
      items: items ?? o.items,
      reports: o.reports,
      paidAt: o.paidAt,
      updatedAt: o.updatedAt,
      expectedFinishAt: setExpectedFinishAt
          ? expectedFinishAt
          : (expectedFinishAt ?? o.expectedFinishAt),
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? o.estimatedDurationMinutes,
      totalAmountMoney: o.totalAmountMoney,
      paidAmountMoney: o.paidAmountMoney,
      payments: o.payments,
      paymentTotals: o.paymentTotals,
    );
  }

  Future<Result<OrderScheduleResult>> _scheduleExpectedFinish(
    String id,
    DateTime? expectedFinishAt,
  ) async {
    final index = _orders.indexWhere((o) => o.id == id);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    _orders[index] = _copyWith(
      _orders[index],
      expectedFinishAt: expectedFinishAt,
      setExpectedFinishAt: true,
    );
    return Ok(
      OrderScheduleResult(orderId: id, expectedFinishAt: expectedFinishAt),
    );
  }

  Future<Result<OrderScheduleResult>> _scheduleOrder(
    String id,
    DateTime scheduledAt,
  ) async {
    final index = _orders.indexWhere((o) => o.id == id);
    if (index == -1) {
      return const Err(AppError(ErrorKind.notFound, 'Захиалга олдсонгүй'));
    }
    final previous = _orders[index].scheduledAt;
    _orders[index] = _copyWith(_orders[index], scheduledAt: scheduledAt);
    return Ok(
      OrderScheduleResult(
        orderId: id,
        scheduledAt: scheduledAt,
        previousScheduledAt: previous,
      ),
    );
  }

  void _recordItemHistory(String orderId, ServiceItem item) {
    (_itemHistory[orderId] ??= <ServiceItem>[]).add(item);
  }

  OrderPaymentTotals _paymentTotals(String orderId) {
    final order = _orders.firstWhere((item) => item.id == orderId);
    final total = order.totalAmountMoney ?? _ordersTotal(order);
    final paid = (_payments[orderId] ?? const <OrderPaymentRecord>[])
        .where((payment) => payment.status == OrderPaymentRecordStatus.PAID)
        .fold<Money>(
          const Money('0'),
          (sum, payment) => _addMoney(sum, payment.amountMoney),
        );
    final remaining = _subtractMoney(total, paid);
    final status = _compareMoney(paid, Money('0')) == 0
        ? PaymentStatus.UNPAID
        : _compareMoney(remaining, Money('0')) <= 0
        ? PaymentStatus.PAID
        : PaymentStatus.PARTIAL;
    return OrderPaymentTotals(
      totalAmountMoney: total,
      paidAmountMoney: paid,
      remainingAmountMoney: remaining,
      paymentStatus: status,
    );
  }

  Money _ordersTotal(ServiceOrderDetail order) => order.items.fold<Money>(
    const Money('0'),
    (sum, item) =>
        _addMoney(sum, item.totalMoney ?? Money(item.total.toString())),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Money _multiplyMoney(Money left, Money right) {
  final leftParts = left.raw.split('.');
  final rightParts = right.raw.split('.');
  final leftScale = leftParts.length == 2 ? leftParts[1].length : 0;
  final rightScale = rightParts.length == 2 ? rightParts[1].length : 0;
  final product =
      BigInt.parse(
        '${leftParts[0]}${leftParts.length == 2 ? leftParts[1] : ''}',
      ) *
      BigInt.parse(
        '${rightParts[0]}${rightParts.length == 2 ? rightParts[1] : ''}',
      );
  final scale = leftScale + rightScale;
  var digits = product.toString().padLeft(scale + 1, '0');
  if (scale == 0) return Money(digits);
  final split = digits.length - scale;
  digits = '${digits.substring(0, split)}.${digits.substring(split)}';
  return Money(digits);
}

Money _addMoney(Money left, Money right) {
  final scale = [_scale(left), _scale(right)].reduce((a, b) => a > b ? a : b);
  final value = _integerValue(left, scale) + _integerValue(right, scale);
  return _formatInteger(value, scale);
}

Money _subtractMoney(Money left, Money right) {
  final scale = [_scale(left), _scale(right)].reduce((a, b) => a > b ? a : b);
  final value = _integerValue(left, scale) - _integerValue(right, scale);
  if (value <= BigInt.zero) return const Money('0');
  return _formatInteger(value, scale);
}

int _scale(Money value) =>
    value.raw.contains('.') ? value.raw.split('.').last.length : 0;

BigInt _integerValue(Money value, int scale) {
  final parts = value.raw.split('.');
  final fraction = parts.length == 2
      ? parts.last.padRight(scale, '0')
      : ''.padRight(scale, '0');
  final digits = '${parts.first}$fraction';
  return BigInt.parse(digits);
}

Money _formatInteger(BigInt value, int scale) {
  if (scale == 0) return Money(value.toString());
  var digits = value.toString().padLeft(scale + 1, '0');
  final split = digits.length - scale;
  return Money('${digits.substring(0, split)}.${digits.substring(split)}');
}

int _compareMoney(Money left, Money right) {
  final scale = [_scale(left), _scale(right)].reduce((a, b) => a > b ? a : b);
  final a = _integerValue(left, scale);
  final b = _integerValue(right, scale);
  return a.compareTo(b);
}
