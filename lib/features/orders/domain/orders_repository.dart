import 'dart:typed_data';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';

class OrderListQuery {
  final OrderStatus? status;
  final String? branchId;
  final String? assignedToId;
  final PaymentStatus? paymentStatus;
  final bool? postpaid;

  /// `internal=yes|no` server filter (null = both).
  final bool? internal;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? q;
  final String? vehicleId;
  final String? customerId;

  /// Case-insensitive substring of the vehicle plate (server `plate`).
  final String? plate;
  final int page;
  final int pageSize;

  const OrderListQuery({
    this.status,
    this.branchId,
    this.assignedToId,
    this.paymentStatus,
    this.postpaid,
    this.internal,
    this.dateFrom,
    this.dateTo,
    this.q,
    this.vehicleId,
    this.customerId,
    this.plate,
    this.page = 1,
    this.pageSize = 25,
  });
}

class PostpaidQuery {
  final String? vehicleId;
  final PaymentStatus? paymentStatus;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int page;
  final int pageSize;

  const PostpaidQuery({
    this.vehicleId,
    this.paymentStatus,
    this.dateFrom,
    this.dateTo,
    this.page = 1,
    this.pageSize = 25,
  });
}

abstract interface class OrdersRepository {
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
  });

  Future<Result<ServiceOrderDetail>> getOrderDetail(String id);

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
  });

  /// Хүлээн авалтын зураг/гарын үсгийг түр хадгалж (`kind=intake`) серверийн
  /// харьцангуй URL буцаана.
  Future<Result<String>> uploadIntakeFile(
    Uint8List bytes,
    String filename, {
    required bool signature,
  });

  Future<Result<ServiceOrderDetail>> updateStatus(
    String id,
    OrderStatus status, {
    int? durationMinutes,
  });

  Future<Result<ServiceOrderDetail>> updateAssignment(
    String id,
    String assignedToId,
  );
  Future<Result<void>> deleteOrder(String id);
  Future<Result<OrderScheduleResult>> reviseExpectedFinish(
    String id,
    DateTime? expectedFinishAt, {
    bool confirmed = false,
  });
  Future<Result<OrderScheduleResult>> rescheduleOrder(
    String id,
    DateTime scheduledAt, {
    bool confirmed = false,
  });

  Future<Result<ServiceItem>> addItem(
    String orderId, {
    required ItemKind kind,
    required String description,
    required double quantity,
    required double unitPrice,
    String? serviceId,
    String? diagnosticTemplateId,
  });

  /// Lossless counterparts used by the Phase-1 item editor. The `double`
  /// overload above remains solely for the legacy screen compatibility seam.
  Future<Result<ServiceItem>> addItemMoney(
    String orderId, {
    required ItemKind kind,
    required String description,
    required Money quantity,
    required Money unitPrice,
    String? serviceId,
    String? diagnosticTemplateId,
  });

  Future<Result<ServiceItem>> updateItem(
    String orderId,
    String itemId, {
    ItemKind? kind,
    String? description,
    double? quantity,
    double? unitPrice,
    ServiceItemStatus? status,
  });

  Future<Result<ServiceItem>> updateItemMoney(
    String orderId,
    String itemId, {
    ItemKind? kind,
    String? description,
    Money? quantity,
    Money? unitPrice,
    ServiceItemStatus? status,
  });

  Future<Result<void>> removeItem(String orderId, String itemId);
  Future<Result<void>> cancelItem(String orderId, String itemId);
  Future<Result<ServiceItem>> changeItemStatus(
    String orderId,
    String itemId,
    ServiceItemStatus status,
  );
  Future<Result<ServiceItem>> changeItemPrice(
    String orderId,
    String itemId,
    Money unitPrice,
  );
  Future<Result<OrderItemHistoryPage>> getItemHistory(
    String orderId, {
    int page = 1,
    int pageSize = 20,
  });

  Future<Result<List<OrderPaymentRecord>>> getPayments(String orderId);
  Future<Result<OrderPaymentResult>> createPayment(
    String orderId, {
    required OrderPaymentMethod method,
    required Money amount,
    String? bank,
  });
  Future<Result<BankSettings>> getBanks();
  Future<Result<OrderPaymentTotals>> reversePayment(
    String orderId,
    String paymentId,
  );

  Future<Result<({bool qpayEnabled, OrderPayment? pending})>> getQPay(
    String orderId,
  );
  Future<Result<OrderPayment>> createQPay(String orderId, {String? amount});
  Future<Result<({bool paid, String? message})>> checkQPay(
    String orderId,
    String paymentId,
  );
  Future<Result<void>> cancelQPay(String orderId, String paymentId);

  Future<Result<PostpaidPage>> getPostpaid({PostpaidQuery? query});
  Future<Result<List<AssignableUser>>> getAssignableUsers({String? branchId});
  Future<Result<BulkOrderResult>> bulkChangeStatus(
    List<String> orderIds,
    OrderStatus status, {
    int? durationMinutes,
  });
  Future<Result<BulkOrderResult>> bulkAssign(
    List<String> orderIds,
    String assignedToId,
  );
}
