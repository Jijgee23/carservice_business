import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/data/order_dto.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_controller.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_detail_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_detail_screen.dart';
import 'package:carservice_business/features/orders/presentation/widgets/order_status_prompt.dart';

import '../../fakes/fake_order_repository.dart';

Map<String, dynamic> _json({bool? locked}) => {
  'id': 'order-1',
  'number': 'D1-1001',
  'status': 'IN_PROGRESS',
  'paymentStatus': 'PAID',
  'totalAmount': '100.00',
  'paidAmount': '100.00',
  'createdAt': '2026-09-18T03:00:00.000Z',
  'customer': {'id': 'c1', 'fullName': 'Бат', 'phone': '99001122'},
  'vehicle': {'id': 'v1', 'plate': '1234ABC', 'make': 'T', 'model': 'P'},
  'branch': {'id': 'b1', 'name': 'Толгойт'},
  'items': [],
  'reports': [],
  'hasLockedPayment': ?locked,
};

class _JsonRepo extends FakeOrderRepository {
  _JsonRepo(this.json);
  final Map<String, dynamic> json;

  @override
  Future<Result<ServiceOrderDetail>> getOrderDetail(String id) async =>
      Ok(OrderDetailDto.fromJson({'order': json}).value);
}

User _user() => User(
  accessToken: 't',
  refreshToken: 'r',
  id: 'u',
  email: 'u@example.test',
  firstName: 'T',
  lastName: 'U',
  phone: '99001122',
  isOwner: false,
  role: UserRole('r', 'r', const ['orders.view', 'orders.delete']),
  tenant: UserTenant('t', 'T'),
);

Future<void> _pump(WidgetTester tester, Map<String, dynamic> json) async {
  tester.binding.window.physicalSizeTestValue = const Size(1024, 800);
  tester.binding.window.devicePixelRatioTestValue = 1;
  addTearDown(() {
    tester.binding.window.clearPhysicalSizeTestValue();
    tester.binding.window.clearDevicePixelRatioTestValue();
  });
  final repo = _JsonRepo(json);
  final detail = OrderDetailController(repo: repo);
  final legacy = OrderController(repo: repo);
  addTearDown(() {
    detail.dispose();
    legacy.dispose();
  });
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: detail),
          ChangeNotifierProvider.value(value: legacy),
        ],
        child: OrderDetailScreen(orderId: 'order-1', user: _user()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
  await tester.pumpAndSettle();
}

void main() {
  test('hasLockedPayment parses on detail and summary, default false', () {
    expect(
      OrderDetailDto.fromJson({'order': _json(locked: true)})
          .value
          .hasLockedPayment,
      isTrue,
    );
    expect(
      OrderDetailDto.fromJson({'order': _json()}).value.hasLockedPayment,
      isFalse,
    );
    expect(
      OrderSummaryDto.fromJson({'order': _json(locked: true)})
          .value
          .hasLockedPayment,
      isTrue,
    );
    expect(
      OrderSummaryDto.fromJson({'order': _json()}).value.hasLockedPayment,
      isFalse,
    );
    expect(
      ServiceOrderSummary.fromJson(_json(locked: true)).hasLockedPayment,
      isTrue,
    );
    expect(
      ServiceOrderDetail.fromJson(_json(locked: true)).hasLockedPayment,
      isTrue,
    );
    expect(ServiceOrderDetail.fromJson(_json()).hasLockedPayment, isFalse);
  });

  test('paidLockReason follows the parsed flag', () {
    expect(
      paidLockReason(OrderSummaryDto.fromJson(_json(locked: true)).value),
      closedShiftLockHint,
    );
    expect(
      paidLockReason(OrderSummaryDto.fromJson(_json()).value),
      paidLockHint,
    );
  });

  testWidgets('JSON locked flag shows the closed-shift delete hint', (
    tester,
  ) async {
    await _pump(tester, _json(locked: true));
    expect(find.text(closedShiftLockHint), findsOneWidget);
    expect(find.text(paidLockHint), findsNothing);
  });

  testWidgets('JSON without the flag keeps the refund-first hint', (
    tester,
  ) async {
    await _pump(tester, _json());
    expect(find.text(paidLockHint), findsOneWidget);
    expect(find.text(closedShiftLockHint), findsNothing);
  });
}
