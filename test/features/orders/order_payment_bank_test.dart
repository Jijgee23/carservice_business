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

const _twoAccounts = [
  PaymentBank(id: 'acc-khan', label: 'Хаан банк'),
  PaymentBank(id: 'acc-tdb', label: 'Худалдаа хөгжлийн банк'),
  PaymentBank(id: 'pos-khan', label: 'Хаан банк', isPos: true),
  PaymentBank(id: 'pos-tdb', label: 'Худалдаа хөгжлийн банк', isPos: true),
];

const _domainAccounts = [
  PaymentBank(id: 'a1', label: 'Хаан банк', maskedNumber: '••••5678'),
  PaymentBank(
    id: 'p1',
    label: 'Голомт POS',
    isPos: true,
    terminalId: 'TID001',
    isTest: true,
  ),
];

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

/// Opens the payment form and its method list. Without [settle] (a spinner
/// never settles) each sheet gets a start frame and a finished frame.
Future<void> _openMethods(WidgetTester tester, {bool settle = true}) async {
  Future<void> wait() async {
    if (settle) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  final open = find.byKey(const ValueKey('open_payment_sheet'));
  await tester.ensureVisible(open);
  await tester.tap(open);
  await wait();
  await tester.tap(find.byKey(const ValueKey('pay_method_select')));
  await wait();
}

/// Opens the payment form with [optionKey] picked from its method list.
Future<void> _openOption(WidgetTester tester, String optionKey) async {
  await _openMethods(tester);
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

  group('domain', () {
    test('options: BANK_ACCOUNT feeds transfer, POS feeds card, once each', () {
      final options = buildPaymentOptions(
        banks: _domainAccounts,
        includeQPay: false,
      );
      final transfer = options.where((o) => o.group == kTransferGroup).toList();
      final card = options.where((o) => o.group == kCardGroup).toList();
      expect(transfer.map((o) => o.choice.bank), ['a1']);
      expect(card.map((o) => o.choice.bank), ['p1']);
      expect(card.single.label.contains('Туршилт'), isTrue);
    });

    test('a CASH account is not offered as a bank transfer', () {
      final cash = PaymentBank.fromJson({
        'id': 'c1',
        'type': 'CASH',
        'name': 'Бэлнээр',
        'accountNumberMasked': null,
        'terminalId': null,
        'isTest': false,
      });
      expect(cash.isCash, isTrue);
      expect(cash.isTransfer, isFalse);
      final accounts = [cash, ..._domainAccounts];
      final options = buildPaymentOptions(banks: accounts, includeQPay: false);
      expect(options.where((o) => o.choice.bank == 'c1'), isEmpty);
      expect(
        options.where((o) => o.group == kTransferGroup).map((o) => o.bank),
        ['a1'],
      );
      // The built-in cash row stays.
      expect(options.first.choice, const PaymentChoice(OrderPaymentMethod.CASH));
      expect(BankSettings(accounts).transferAccounts.map((a) => a.id), ['a1']);
    });

    test('empty accounts leave only cash and other', () {
      final options = buildPaymentOptions(banks: const [], includeQPay: false);
      expect(options.map((o) => o.choice.method), [
        OrderPaymentMethod.CASH,
        OrderPaymentMethod.OTHER,
      ]);
    });

    test('choice equality ignores the label', () {
      expect(
        const PaymentChoice(OrderPaymentMethod.CARD, 'p1', 'Голомт POS'),
        const PaymentChoice(OrderPaymentMethod.CARD, 'p1'),
      );
    });

    test('paymentBankLabelIn falls back to the raw id', () {
      expect(paymentBankLabelIn(_domainAccounts, 'a1'), 'Хаан банк');
      expect(paymentBankLabelIn(_domainAccounts, 'gone'), 'gone');
      expect(paymentBankLabelIn(_domainAccounts, null), '');
    });

    test('BankSettings splits transfer and POS accounts', () {
      const s = BankSettings(_domainAccounts);
      expect(s.transferAccounts.map((a) => a.id), ['a1']);
      expect(s.posAccounts.map((a) => a.id), ['p1']);
    });

    test('PaymentBank.fromJson maps the GET /banks account shape', () {
      final bank = PaymentBank.fromJson({
        'id': 'p1',
        'type': 'POS',
        'name': 'Голомт POS',
        'accountNumberMasked': null,
        'terminalId': 'TID001',
        'isTest': true,
      });
      expect(bank.isPos, isTrue);
      expect(bank.terminalId, 'TID001');
      expect(bank.isTest, isTrue);
      expect(bank.maskedNumber, '');
      expect(bank.displayNumber, isNull);
    });

    test('a transfer account shows its full number, masked only as fallback', () {
      Map<String, Object?> json({String? full}) => {
        'id': 'a1',
        'type': 'BANK_ACCOUNT',
        'name': 'Хаан банк',
        'accountNumber': full,
        'accountNumberMasked': '••••5678',
        'terminalId': null,
        'isTest': false,
      };
      expect(PaymentBank.fromJson(json(full: '5000125678')).displayNumber, '5000125678');
      // An older server sends only the masked number.
      expect(PaymentBank.fromJson(json()).displayNumber, '••••5678');
    });
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
          bankId: 'acc-khan',
        ),
        isTrue,
      );
      expect(
        await controller.createManual(
          amount: '5',
          method: OrderPaymentMethod.CASH,
          bankId: 'acc-khan',
        ),
        isTrue,
      );
      expect(controller.payments.map((p) => p.bankId), ['acc-khan', null]);
      controller.dispose();
    });

    test('banks load once and expose the active accounts', () async {
      final repo = FakeOrderRepository(seedOrders: [_order()])
        ..accounts = _twoAccounts;
      final controller = OrderPaymentController(
        repo: repo,
        orderId: 'order-1',
        user: _user(_perms),
      );
      await controller.load();
      await Future<void>.delayed(Duration.zero);
      expect(controller.accounts.map((b) => b.id), [
        'acc-khan',
        'acc-tdb',
        'pos-khan',
        'pos-tdb',
      ]);
      controller.dispose();
    });
  });

  group('screen', () {
    testWidgets('list: groups and order; QPay is its own button', (
      tester,
    ) async {
      final repo = FakeOrderRepository(seedOrders: [_order()])
        ..accounts = _twoAccounts;
      await _pump(tester, repo, _user(_perms));
      await _openMethods(tester);

      expect(find.textContaining('Төлбөр бүртгэх'), findsWidgets);
      expect(find.byKey(const ValueKey('pay_opt_QPAY')), findsNothing);
      expect(find.byKey(const ValueKey('create_qpay')), findsOneWidget);
      double y(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
      final order = [
        y('pay_opt_CASH'),
        y('pay_group_$kTransferGroup'),
        y('pay_opt_BANK_TRANSFER_acc-khan'),
        y('pay_opt_BANK_TRANSFER_acc-tdb'),
        y('pay_group_$kCardGroup'),
        y('pay_opt_CARD_pos-khan'),
        y('pay_opt_CARD_pos-tdb'),
        y('pay_opt_OTHER'),
      ];
      expect([...order]..sort(), order);
      expect(
        find.byKey(const ValueKey('pay_opt_CARD_pos-golomt')),
        findsNothing,
      );
    });

    testWidgets('banks arriving after the sheet opens appear; error retries', (
      tester,
    ) async {
      final repo = _SlowBanksRepo();
      await _pump(tester, repo, _user(_perms));
      await _openMethods(tester, settle: false);
      expect(find.byKey(const ValueKey('pay_banks_loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('pay_opt_CARD_pos-khan')), findsNothing);

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
      await _openMethods(tester, settle: false);
      expect(find.byKey(const ValueKey('pay_opt_CARD_pos-khan')), findsNothing);

      repo.gate.complete(const Ok(BankSettings(_twoAccounts)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('pay_banks_loading')), findsNothing);
      expect(
        find.byKey(const ValueKey('pay_opt_BANK_TRANSFER_acc-khan')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pay_opt_CARD_pos-tdb')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('pay_opt_CARD_pos-khan')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('create_manual_payment')),
        findsOneWidget,
      );
    });

    testWidgets('no accounts: empty-state row before «Бусад»', (tester) async {
      final repo = FakeOrderRepository(seedOrders: [_order()])..accounts = [];
      await _pump(tester, repo, _user(_perms));
      await _openMethods(tester);
      expect(find.byKey(const ValueKey('pay_banks_empty')), findsOneWidget);
      expect(find.text('Төлбөрийн сонголт бүртгээгүй байна'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('pay_banks_empty'))).dy <
            tester.getTopLeft(find.byKey(const ValueKey('pay_opt_OTHER'))).dy,
        isTrue,
      );
    });

    testWidgets('transfer records BANK_TRANSFER + bank', (tester) async {
      final repo = FakeOrderRepository(seedOrders: [_order()]);
      await _pump(tester, repo, _user(_perms));
      await _openOption(tester, 'BANK_TRANSFER_acc-golomt');
      await tester.enterText(
        find.byKey(const ValueKey('payment_amount_input')),
        '40',
      );
      await tester.tap(find.byKey(const ValueKey('create_manual_payment')));
      await tester.pumpAndSettle();

      final saved = await _saved(repo);
      expect(saved.single.method, OrderPaymentMethod.BANK_TRANSFER);
      expect(saved.single.bankId, 'acc-golomt');
      expect(find.byKey(const ValueKey('pay_sheet_title')), findsNothing);
    });

    testWidgets('card (POS) records CARD + account directly, no terminal', (
      tester,
    ) async {
      final repo = FakeOrderRepository(seedOrders: [_order()]);
      await _pump(tester, repo, _user(_perms));
      await _openOption(tester, 'CARD_pos-khan');
      await tester.enterText(
        find.byKey(const ValueKey('payment_amount_input')),
        '40',
      );
      await tester.tap(find.byKey(const ValueKey('create_manual_payment')));
      await tester.pumpAndSettle();

      expect(find.text('Туршилтын POS'), findsNothing);
      final saved = await _saved(repo);
      expect(saved.single.method, OrderPaymentMethod.CARD);
      expect(saved.single.bankId, 'pos-khan');
      expect(find.byKey(const ValueKey('pay_sheet_title')), findsNothing);
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
      expect(saved.single.bankId, isNull);
    });
  });
}
