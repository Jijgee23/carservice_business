import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/data/order_dto.dart';
import 'package:carservice_business/features/orders/data/order_repository.dart';
import 'package:carservice_business/features/orders/data/orders_data_source.dart';
import 'package:carservice_business/features/orders/domain/orders_error_codes.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/domain/order_payment_mode.dart';
import 'package:carservice_business/features/orders/domain/postpaid_settlement.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_payment_controller.dart';
import 'package:carservice_business/features/overview/domain/overview.dart';
import 'package:carservice_business/features/reports/domain/report.dart';

import '../../fakes/fake_order_repository.dart';

Map<String, dynamic> _json(Map<String, dynamic> extra) => {
  'id': 'o1',
  'number': 'D1-1',
  'status': 'IN_PROGRESS',
  'paymentStatus': 'UNPAID',
  'totalAmount': '1000.00',
  'paidAmount': '0.00',
  'createdAt': '2026-09-18T03:00:00.000Z',
  'customer': {'id': 'c1', 'fullName': 'Бат', 'phone': '99001122'},
  'vehicle': {'id': 'v1', 'plate': '1234ABC', 'make': 'T', 'model': 'P'},
  'branch': {'id': 'b1', 'name': 'Толгойт'},
  ...extra,
};

User _user() => User(
  accessToken: '',
  refreshToken: '',
  id: 'user-1',
  email: 'test@example.com',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: true,
  role: UserRole('role-1', 'Staff', const []),
  tenant: UserTenant('tenant-1', 'Tenant'),
);

class _CapturingSource implements OrdersDataSource {
  Map<String, dynamic>? listQuery;

  @override
  Future<Object?> list(Map<String, dynamic> query) async {
    listQuery = query;
    return {
      'items': <Object?>[],
      'pagination': {'page': 1, 'pageSize': 25, 'total': 0, 'totalPages': 0},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('DTO', () {
    test('isInternal parsed on summary and detail, default false', () {
      expect(OrderSummaryDto.fromJson(_json({})).value.isInternal, isFalse);
      expect(
        OrderSummaryDto.fromJson(_json({'isInternal': true})).value.isInternal,
        isTrue,
      );
      final d = OrderDetailDto.fromJson(
        _json({'items': [], 'reports': [], 'isInternal': true}),
      ).value;
      expect(d.isInternal, isTrue);
    });

    test('legacy fromJson parses isInternal', () {
      expect(
        ServiceOrderSummary.fromJson(_json({'isInternal': true})).isInternal,
        isTrue,
      );
    });
  });

  test('completionBlocker has no payment blocker for internal orders', () {
    final internal = OrderSummaryDto.fromJson(_json({'isInternal': true}))
        .value;
    final normal = OrderSummaryDto.fromJson(_json({})).value;
    expect(normal.completionBlocker(), contains('төлөгдөөгүй'));
    expect(internal.completionBlocker(), isNull);
  });

  test('error codes carry contract messages', () {
    expect(
      OrdersErrorCodes.internalPostpaidConflict,
      'ORDER_INTERNAL_POSTPAID_CONFLICT',
    );
    expect(OrdersErrorCodes.internalNoPayment, 'ORDER_INTERNAL_NO_PAYMENT');
    expect(OrdersErrorCodes.internalHasPayments, 'ORDER_INTERNAL_HAS_PAYMENTS');
    expect(
      OrdersErrorCodes.internalPostpaidConflictMessage,
      'Дотоод засвар болон дараа тооцоо зэрэг байж болохгүй.',
    );
    expect(
      OrdersErrorCodes.internalNoPaymentMessage,
      'Дотоод засварт төлбөр бүртгэхгүй.',
    );
    expect(
      OrdersErrorCodes.internalHasPaymentsMessage,
      'Төлбөр бүртгэгдсэн засварын хуудсыг дотоод засвар болгох боломжгүй.',
    );
  });

  group('OrderPaymentMode mapping', () {
    test('mode <-> flags, never both flags', () {
      for (final m in OrderPaymentMode.values) {
        expect(
          OrderPaymentMode.fromFlags(
            isPostpaid: m.isPostpaid,
            isInternal: m.isInternal,
          ),
          m,
        );
        expect(m.isPostpaid && m.isInternal, isFalse);
      }
      expect(OrderPaymentMode.regular.isPostpaid, isFalse);
      expect(OrderPaymentMode.regular.isInternal, isFalse);
      expect(OrderPaymentMode.postpaid.isPostpaid, isTrue);
      expect(OrderPaymentMode.internal.isInternal, isTrue);
    });

    test('vehicle default and internal is kept on vehicle change', () {
      expect(OrderPaymentMode.forVehicle(true), OrderPaymentMode.postpaid);
      expect(OrderPaymentMode.forVehicle(false), OrderPaymentMode.regular);
      expect(
        OrderPaymentMode.regular.afterVehicleChange(true),
        OrderPaymentMode.postpaid,
      );
      expect(
        OrderPaymentMode.postpaid.afterVehicleChange(false),
        OrderPaymentMode.regular,
      );
      expect(
        OrderPaymentMode.internal.afterVehicleChange(true),
        OrderPaymentMode.internal,
      );
    });
  });

  group('payment lock', () {
    Future<OrderPaymentController> load({required bool internal}) async {
      final repo = FakeOrderRepository(
        seedOrders: [
          ServiceOrderDetail(
            id: 'order-2',
            number: 'A-2',
            status: OrderStatus.IN_PROGRESS,
            paymentStatus: PaymentStatus.UNPAID,
            isInternal: internal,
            createdAt: DateTime(2026),
            customer: const CustomerSummary(id: 'c', fullName: 'C', phone: '1'),
            vehicle: const VehicleSummary(
              id: 'v',
              plate: '1',
              make: 'A',
              model: 'B',
            ),
            branch: const BranchSummary(id: 'b', name: 'B'),
            items: const [],
            reports: const [],
          ),
        ],
      );
      final c = OrderPaymentController(
        repo: repo,
        orderId: 'order-2',
        user: _user(),
      );
      await c.load();
      addTearDown(c.dispose);
      return c;
    }

    test('internal order blocks all payment actions', () async {
      final c = await load(internal: true);
      expect(c.internalLocked, isTrue);
      expect(c.canCreate, isFalse);
      expect(c.canEdit, isFalse);
      expect(c.canDelete, isFalse);
      expect(internalOrderPaymentNote, contains('Дотоод засвар'));
    });

    test('regular order is not internal-locked', () async {
      final c = await load(internal: false);
      expect(c.internalLocked, isFalse);
      expect(c.canCreate, isTrue);
    });
  });

  group('filter query param', () {
    test('internal=yes|no, omitted when null', () async {
      final source = _CapturingSource();
      final repo = RemoteOrdersRepository(dataSource: source);
      await repo.getOrders(query: const OrderListQuery(internal: true));
      expect(source.listQuery!['internal'], 'yes');
      await repo.getOrders(query: const OrderListQuery(internal: false));
      expect(source.listQuery!['internal'], 'no');
      await repo.getOrders(query: const OrderListQuery());
      expect(source.listQuery!.containsKey('internal'), isFalse);
    });

    test('fake repo filters by internal and createOrder sends flag', () async {
      final repo = FakeOrderRepository();
      await repo.createOrder(
        branchId: 'b',
        customerId: 'c',
        vehicleId: 'v',
        isInternal: true,
      );
      expect(repo.lastIsInternal, isTrue);
      final r = await repo.getOrders(
        query: const OrderListQuery(internal: true),
      );
      expect(((r as Ok).value.items as List).length, 1);
    });
  });

  test('overview and report parse internalCost defensively', () {
    expect(Overview.fromJson({}).internalCost, isNull);
    expect(Overview.fromJson({'internalCost': '1500.50'}).internalCost, 1500.5);
    expect(ReportData.fromJson({}).internalCost, isNull);
    expect(ReportData.fromJson({'internalCost': '200'}).internalCost, 200);
  });
}
