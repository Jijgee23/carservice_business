import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/postpaid_settlement.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_payment_controller.dart';

import '../../fakes/fake_order_repository.dart';

User _user(List<String> permissions, {bool owner = false}) => User(
  accessToken: '',
  refreshToken: '',
  id: 'user-1',
  email: 'test@example.com',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: owner,
  role: UserRole('role-1', 'Staff', permissions),
  tenant: UserTenant('tenant-1', 'Tenant'),
);

ServiceOrderDetail _order(OrderStatus status, {required bool postpaid}) =>
    ServiceOrderDetail(
      id: 'order-1',
      number: 'A-0001',
      status: status,
      paymentStatus: PaymentStatus.UNPAID,
      isPostpaid: postpaid,
      totalAmount: 100,
      paidAmount: 0,
      totalAmountMoney: const Money('100.00'),
      paidAmountMoney: const Money('0.00'),
      createdAt: DateTime(2026),
      customer: const CustomerSummary(id: 'c', fullName: 'C', phone: '1'),
      vehicle: const VehicleSummary(id: 'v', plate: '1', make: 'A', model: 'B'),
      branch: const BranchSummary(id: 'b', name: 'Branch'),
      items: const [],
      reports: const [],
    );

class _Repo extends FakeOrderRepository {
  _Repo(this.detail) : super(seedOrders: [detail]);
  final ServiceOrderDetail detail;
  @override
  Future<Result<ServiceOrderDetail>> getOrderDetail(String id) =>
      Future.value(Ok(detail));
}

const _pay = [
  'payments.view',
  'payments.create',
  'payments.edit',
  'payments.delete',
];

Future<OrderPaymentController> _load(
  OrderStatus status, {
  required bool postpaid,
  List<String> extra = const [],
  bool owner = false,
}) async {
  final c = OrderPaymentController(
    repo: _Repo(_order(status, postpaid: postpaid)),
    orderId: 'order-1',
    user: _user([..._pay, ...extra], owner: owner),
  );
  await c.load();
  addTearDown(c.dispose);
  return c;
}

void _expectAll(OrderPaymentController c, bool allowed) {
  expect(c.canCreate, allowed);
  expect(c.canEdit, allowed);
  expect(c.canDelete, allowed);
  expect(c.settlementLocked, !allowed);
}

void main() {
  test('non-postpaid completed order is not locked', () async {
    _expectAll(await _load(OrderStatus.COMPLETED, postpaid: false), true);
  });

  test('postpaid not completed is not locked', () async {
    _expectAll(await _load(OrderStatus.IN_PROGRESS, postpaid: true), true);
  });

  test('postpaid completed without permission is locked', () async {
    final c = await _load(OrderStatus.COMPLETED, postpaid: true);
    _expectAll(c, false);
    expect(c.canView, isTrue);
    expect(
      await c.createManual(amount: '10', method: OrderPaymentMethod.CASH),
      isFalse,
    );
  });

  test(
    'postpaid completed with orders.closeUnpaidPostpaid is allowed',
    () async {
      final c = await _load(
        OrderStatus.COMPLETED,
        postpaid: true,
        extra: [closeUnpaidPostpaidPermission],
      );
      _expectAll(c, true);
    },
  );

  test('postpaid completed as owner is allowed', () async {
    _expectAll(
      await _load(OrderStatus.COMPLETED, postpaid: true, owner: true),
      true,
    );
  });

  test('userCanSettlePostpaid helper', () {
    expect(userCanSettlePostpaid(null), isFalse);
    expect(userCanSettlePostpaid(_user([])), isFalse);
    expect(
      userCanSettlePostpaid(_user([closeUnpaidPostpaidPermission])),
      isTrue,
    );
    expect(userCanSettlePostpaid(_user([], owner: true)), isTrue);
  });
}
