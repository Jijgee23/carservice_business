import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/cash/domain/settlement.dart';
import 'package:carservice_business/features/cash/presentation/controllers/settlement_flow_controller.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_payment_controller.dart';
import 'package:carservice_business/features/orders/presentation/controllers/postpaid_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/postpaid_screen.dart';

import '../../fakes/fake_order_repository.dart';
import 'fake_cash_repository.dart';

User _user(List<String> permissions, {bool owner = false}) => User(
  accessToken: 't',
  refreshToken: 'r',
  id: 'u',
  email: 'u@example.test',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: owner,
  branchId: 'b-1',
  role: UserRole('role', 'Role', permissions),
  tenant: UserTenant('tenant', 'Tenant'),
);

SettlementFlowController _flow(FakeCashRepository repo) =>
    SettlementFlowController(
      repo: repo,
      accounts: const [],
      branchId: 'b-1',
      now: DateTime(2026, 10, 5, 10),
    );

Future<void> _pumpPostpaid(WidgetTester tester, User user) async {
  final controller = PostpaidController(
    repo: FakeOrderRepository(seedPostpaid: true),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: PostpaidScreen(
        controller: controller,
        user: user,
        cashRepository: FakeCashRepository(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('settlement flow', () {
    test('selects all by default and the total sums ticked orders', () async {
      final repo = FakeCashRepository()
        ..eligible = [
          eligibleOrder('o1', '100000.1'),
          eligibleOrder('o2', '200000.2'),
          eligibleOrder('o3', '50'),
        ];
      final c = _flow(repo);
      await c.setCustomer(const CashRef('c-1', 'Тест ХК'));
      expect(c.selected.length, 3);
      expect(c.total, '300050.3');
      c.toggle('o3', false);
      expect(c.total, '300000.3');
      c.toggleAll(false);
      expect(c.canSubmit, isFalse);
    });

    test('submit sends only ticked ids with the expected total', () async {
      final repo = FakeCashRepository()
        ..eligible = [eligibleOrder('o1', '100'), eligibleOrder('o2', '200')];
      final c = _flow(repo);
      await c.setCustomer(const CashRef('c-1', 'Тест ХК'));
      c.toggle('o1', false);
      c.setMethod(OrderPaymentMethod.BANK_TRANSFER);
      expect(c.canSubmit, isFalse); // bank required
      c.setBank('acc-khan');
      expect(await c.submit(), isNotNull);
      final d = repo.settlementDrafts.single;
      expect(d.orderIds, ['o2']);
      expect(d.expectedAmount, '200');
      expect(d.bankId, 'acc-khan');
      expect(d.occurredAt, isNull); // today -> server "now"
    });

    test('settlement date is capped at today', () {
      final c = _flow(FakeCashRepository());
      c.setDate(DateTime(2026, 12, 1));
      expect(c.date, DateTime(2026, 10, 5));
    });

    test('amount changed reloads the list and keeps the ticks', () async {
      final repo = FakeCashRepository()
        ..eligible = [eligibleOrder('o1', '100'), eligibleOrder('o2', '200')]
        ..createSettlementErrors.add(
          const AppError(
            ErrorKind.unknown,
            'stale',
            statusCode: 409,
            code: SettlementErrorCodes.amountChanged,
          ),
        );
      final c = _flow(repo);
      await c.setCustomer(const CashRef('c-1', 'Тест ХК'));
      repo.eligible = [eligibleOrder('o1', '150')]; // o2 got paid elsewhere
      expect(await c.submit(), isNull);
      expect(c.notice, settlementAmountChangedNotice);
      expect(c.orders.length, 1);
      expect(c.total, '150');
      expect(c.submitError, isNull);
      expect(await c.submit(), isNotNull);
      expect(repo.settlementDrafts.last.expectedAmount, '150');
    });
  });

  group('permission gating on the postpaid screen', () {
    final button = find.byKey(const ValueKey('postpaid_settle_button'));

    testWidgets('both permissions show the action', (tester) async {
      await _pumpPostpaid(
        tester,
        _user(const [
          'orders.view',
          'orders.closeUnpaidPostpaid',
          'cash.manage',
        ]),
      );
      expect(button, findsOneWidget);
    });

    testWidgets('owner shows the action', (tester) async {
      await _pumpPostpaid(tester, _user(const ['orders.view'], owner: true));
      expect(button, findsOneWidget);
    });

    testWidgets('missing cash.manage hides it', (tester) async {
      await _pumpPostpaid(
        tester,
        _user(const ['orders.view', 'orders.closeUnpaidPostpaid']),
      );
      expect(button, findsNothing);
    });

    testWidgets('missing closeUnpaidPostpaid hides it', (tester) async {
      await _pumpPostpaid(tester, _user(const ['orders.view', 'cash.manage']));
      expect(button, findsNothing);
    });
  });

  group('settlement payment rows', () {
    final row = OrderPaymentRecord(
      id: 'p-1',
      amountMoney: const Money('100'),
      method: OrderPaymentMethod.BANK_TRANSFER,
      status: OrderPaymentRecordStatus.PAID,
      paidAt: DateTime(2026, 10, 3),
      createdAt: DateTime(2026, 10, 3),
      bankId: 'acc-khan',
      bankLabel: 'Хаан банк',
      settlementId: 's-1',
    );

    test('reverse is locked with the reason', () async {
      final controller = OrderPaymentController(
        repo: FakeOrderRepository(),
        orderId: 'order-1',
        user: _user(const ['payments.delete', 'cash.manage'], owner: true),
      );
      expect(row.isSettlement, isTrue);
      expect(controller.reverseBlockedReason(row), contains('тооцоогоор'));
      expect(await controller.reverse(row), isFalse);
    });
  });
}
