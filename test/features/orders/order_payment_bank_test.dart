import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_error_codes.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_payment_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_payment_screen.dart';
import 'package:carservice_business/features/orders/presentation/widgets/payment_method_sheet.dart';

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

ServiceOrderDetail _order() => ServiceOrderDetail(
  id: 'order-1',
  number: 'A-0001',
  status: OrderStatus.SCHEDULED,
  paymentStatus: PaymentStatus.UNPAID,
  totalAmount: 100,
  paidAmount: 0,
  totalAmountMoney: const Money('100'),
  paidAmountMoney: const Money('0'),
  createdAt: DateTime(2026),
  customer: const CustomerSummary(id: 'c', fullName: 'Customer', phone: '1'),
  vehicle: const VehicleSummary(id: 'v', plate: '1', make: 'A', model: 'B'),
  branch: const BranchSummary(id: 'b', name: 'Branch'),
  items: const [],
  reports: const [],
);

const _perms = ['payments.view', 'payments.create', 'payments.delete'];

Future<void> _pump(
  WidgetTester tester,
  FakeOrderRepository repo,
  User user,
) async {
  tester.binding.window.physicalSizeTestValue = const Size(400, 1400);
  tester.binding.window.devicePixelRatioTestValue = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ChangeNotifierProvider(
        create: (_) =>
            OrderPaymentController(repo: repo, orderId: 'order-1', user: user),
        child: const OrderPaymentScreen(orderId: 'order-1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _openOption(WidgetTester tester, String optionKey) async {
  final open = find.byKey(const ValueKey('open_payment_sheet'));
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pumpAndSettle();
  final row = find.byKey(ValueKey('pay_opt_$optionKey'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<List<OrderPaymentRecord>> _saved(FakeOrderRepository repo) async =>
    (await repo.getPayments('order-1') as Ok).value as List<OrderPaymentRecord>;

class _SlowBanksRepo extends FakeOrderRepository {
  _SlowBanksRepo() : super(seedOrders: [_order()]);
  final gate = Completer<Result<BankSettings>>();
  @override
  Future<Result<BankSettings>> getBanks() => gate.future;
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().window
        .clearPhysicalSizeTestValue();
    TestWidgetsFlutterBinding.ensureInitialized().window
        .clearDevicePixelRatioTestValue();
  });

  group('controller', () {
    test('bank required for CARD / transfer, ignored for CASH', () async {
      final repo = FakeOrderRepository(seedOrders: [_order()]);
      final controller = OrderPaymentController(
        repo: repo,
        orderId: 'order-1',
        user: _user(_perms),
      );
      await controller.load();

      expect(
        await controller.createManual(
          amount: '10',
          method: OrderPaymentMethod.CARD,
        ),
        isFalse,
      );
      expect(
        controller.lastError?.message,
        OrdersErrorCodes.paymentBankRequiredMessage,
      );
      expect(controller.payments, isEmpty);

      expect(
        await controller.createManual(
          amount: '10',
          method: OrderPaymentMethod.CARD,
          bank: 'KHAN',
        ),
        isTrue,
      );
      expect(
        await controller.createManual(
          amount: '5',
          method: OrderPaymentMethod.CASH,
          bank: 'KHAN',
        ),
        isTrue,
      );
      expect(controller.payments.map((p) => p.bank), ['KHAN', null]);
      controller.dispose();
    });

    test('banks load once and expose only enabled ones', () async {
      final repo = FakeOrderRepository(seedOrders: [_order()])
        ..enabledBankCodes = ['KHAN', 'TDB'];
      final controller = OrderPaymentController(
        repo: repo,
        orderId: 'order-1',
        user: _user(_perms),
      );
      await controller.load();
      await Future<void>.delayed(Duration.zero);
      expect(controller.enabledBanks.map((b) => b.code), ['KHAN', 'TDB']);
      controller.dispose();
    });
  });

  group('screen', () {
    testWidgets('list: groups and order, QPay only when enabled', (
      tester,
    ) async {
      final repo = FakeOrderRepository(seedOrders: [_order()])
        ..enabledBankCodes = ['KHAN', 'TDB'];
      await _pump(tester, repo, _user(_perms));
      final open = find.byKey(const ValueKey('open_payment_sheet'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();

      expect(find.textContaining('Төлбөр бүртгэх'), findsWidgets);
      double y(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
      final order = [
        y('pay_opt_CASH'),
        y('pay_opt_QPAY'),
        y('pay_group_$kTransferGroup'),
        y('pay_opt_BANK_TRANSFER_KHAN'),
        y('pay_opt_BANK_TRANSFER_TDB'),
        y('pay_group_$kCardGroup'),
        y('pay_opt_CARD_KHAN'),
        y('pay_opt_CARD_TDB'),
        y('pay_opt_OTHER'),
      ];
      expect([...order]..sort(), order);
      expect(find.byKey(const ValueKey('pay_opt_CARD_GOLOMT')), findsNothing);
    });

    testWidgets('banks arriving after the sheet opens appear; error retries', (
      tester,
    ) async {
      final repo = _SlowBanksRepo();
      await _pump(tester, repo, _user(_perms));
      final open = find.byKey(const ValueKey('open_payment_sheet'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('pay_banks_loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('pay_opt_CARD_KHAN')), findsNothing);

      repo.gate.complete(const Err(AppError(ErrorKind.unknown, 'x')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('pay_banks_error')), findsOneWidget);
      expect(find.text('Банкны жагсаалт ачаалж чадсангүй'), findsOneWidget);
    });

    testWidgets('banks resolving after the sheet opens add selectable rows', (
      tester,
    ) async {
      final repo = _SlowBanksRepo();
      await _pump(tester, repo, _user(_perms));
      final open = find.byKey(const ValueKey('open_payment_sheet'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('pay_opt_CARD_KHAN')), findsNothing);

      repo.gate.complete(const Ok(BankSettings(['KHAN', 'TDB'])));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('pay_banks_loading')), findsNothing);
      expect(
        find.byKey(const ValueKey('pay_opt_BANK_TRANSFER_KHAN')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pay_opt_CARD_TDB')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pay_opt_CARD_KHAN')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pos_start')), findsOneWidget);
    });

    testWidgets('transfer records BANK_TRANSFER + bank', (tester) async {
      final repo = FakeOrderRepository(seedOrders: [_order()]);
      await _pump(tester, repo, _user(_perms));
      await _openOption(tester, 'BANK_TRANSFER_GOLOMT');
      await tester.enterText(
        find.byKey(const ValueKey('payment_amount_input')),
        '40',
      );
      await tester.tap(find.byKey(const ValueKey('create_manual_payment')));
      await tester.pumpAndSettle();

      final saved = await _saved(repo);
      expect(saved.single.method, OrderPaymentMethod.BANK_TRANSFER);
      expect(saved.single.bank, 'GOLOMT');
      expect(find.byKey(const ValueKey('pay_sheet_title')), findsNothing);
    });

    testWidgets('card: simulator Амжилттай records CARD + bank', (
      tester,
    ) async {
      final repo = FakeOrderRepository(seedOrders: [_order()]);
      await _pump(tester, repo, _user(_perms));
      await _openOption(tester, 'CARD_KHAN');
      await tester.enterText(
        find.byKey(const ValueKey('payment_amount_input')),
        '40',
      );
      await tester.tap(find.byKey(const ValueKey('pos_start')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Туршилтын POS'), findsOneWidget);
      expect(find.textContaining('Хаан банк POS · 40₮'), findsOneWidget);
      expect(await _saved(repo), isEmpty);

      await tester.tap(find.byKey(const ValueKey('pos_success')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      final saved = await _saved(repo);
      expect(saved.single.method, OrderPaymentMethod.CARD);
      expect(saved.single.bank, 'KHAN');
    });

    testWidgets('card: simulator Цуцлах records nothing', (tester) async {
      final repo = FakeOrderRepository(seedOrders: [_order()]);
      await _pump(tester, repo, _user(_perms));
      await _openOption(tester, 'CARD_KHAN');
      await tester.tap(find.byKey(const ValueKey('pos_start')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('pos_cancel')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(await _saved(repo), isEmpty);
      expect(find.byKey(const ValueKey('pos_simulator')), findsNothing);
      expect(find.byKey(const ValueKey('pos_start')), findsOneWidget);
    });

    testWidgets('cash records CASH without a bank', (tester) async {
      final repo = FakeOrderRepository(seedOrders: [_order()]);
      await _pump(tester, repo, _user(_perms));
      await _openOption(tester, 'CASH');
      await tester.enterText(
        find.byKey(const ValueKey('payment_amount_input')),
        '100',
      );
      await tester.tap(find.byKey(const ValueKey('create_manual_payment')));
      await tester.pumpAndSettle();
      final saved = await _saved(repo);
      expect(saved.single.method, OrderPaymentMethod.CASH);
      expect(saved.single.bank, isNull);
    });
  });
}
