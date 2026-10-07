import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_payment_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_payment_screen.dart';

import '../../fakes/fake_order_repository.dart';

User _user(List<String> permissions) => User(
  accessToken: '',
  refreshToken: '',
  id: 'user-1',
  email: 'test@example.com',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: false,
  role: UserRole('role-1', 'Staff', permissions),
  tenant: UserTenant('tenant-1', 'Tenant'),
);

ServiceOrderDetail _order({
  PaymentStatus paymentStatus = PaymentStatus.UNPAID,
}) => ServiceOrderDetail(
  id: 'order-1',
  number: 'A-0001',
  status: OrderStatus.SCHEDULED,
  paymentStatus: paymentStatus,
  totalAmount: 100.5,
  paidAmount: 0,
  totalAmountMoney: const Money('100.50'),
  paidAmountMoney: const Money('0.00'),
  createdAt: DateTime(2026),
  customer: const CustomerSummary(id: 'c', fullName: 'Customer', phone: '1'),
  vehicle: const VehicleSummary(id: 'v', plate: '1', make: 'A', model: 'B'),
  branch: const BranchSummary(id: 'b', name: 'Branch'),
  items: const [],
  reports: const [],
);

class _WidgetPaymentRepository extends FakeOrderRepository {
  _WidgetPaymentRepository({
    this.malformedQPay = false,
    this.seedPaidLedger = false,
    this.lockedLedger = false,
    this.qpayCheckOutcome,
  }) : super(seedOrders: [_order()]);
  final bool malformedQPay;
  final bool seedPaidLedger;
  final bool lockedLedger;
  final ({bool paid, String? message})? qpayCheckOutcome;
  bool qpayPaidAfterCheck = false;
  bool reversed = false;

  static final _paid = OrderPaymentRecord(
    id: 'payment-1',
    amountMoney: Money('10.25'),
    method: OrderPaymentMethod.CASH,
    status: OrderPaymentRecordStatus.PAID,
    paidAt: null,
    createdAt: DateTime(2026),
  );

  @override
  Future<Result<ServiceOrderDetail>> getOrderDetail(String id) async => Ok(
    _order(
      paymentStatus: qpayPaidAfterCheck
          ? PaymentStatus.PAID
          : PaymentStatus.UNPAID,
    ),
  );

  @override
  Future<Result<List<OrderPaymentRecord>>> getPayments(String orderId) async {
    if (!seedPaidLedger) return super.getPayments(orderId);
    return Ok([
      OrderPaymentRecord(
        id: _paid.id,
        amountMoney: _paid.amountMoney,
        method: _paid.method,
        status: reversed ? OrderPaymentRecordStatus.CANCELLED : _paid.status,
        paidAt: _paid.paidAt,
        createdAt: _paid.createdAt,
        locked: lockedLedger,
      ),
    ]);
  }

  @override
  Future<Result<OrderPaymentTotals>> reversePayment(
    String orderId,
    String paymentId,
  ) async {
    reversed = true;
    return const Ok(
      OrderPaymentTotals(
        totalAmountMoney: Money('100.50'),
        paidAmountMoney: Money('0.00'),
        remainingAmountMoney: Money('100.50'),
        paymentStatus: PaymentStatus.UNPAID,
      ),
    );
  }

  @override
  Future<Result<({bool qpayEnabled, OrderPayment? pending})>> getQPay(
    String orderId,
  ) async {
    if (qpayPaidAfterCheck) {
      return const Ok((qpayEnabled: true, pending: null));
    }
    if (!malformedQPay) return super.getQPay(orderId);
    return Ok((
      qpayEnabled: true,
      pending: OrderPayment(
        id: 'qpay-1',
        amount: 100.50,
        amountMoney: const Money('100.50'),
        qrImage: 'not-valid-base64',
        urls: const [
          QPayBankUrl(
            name: 'Unsafe',
            nameMn: 'Unsafe',
            logo: '',
            description: '',
            link: 'javascript:alert(1)',
          ),
          QPayBankUrl(
            name: 'Missing',
            nameMn: 'Missing',
            logo: '',
            description: '',
            link: '/no-scheme',
          ),
        ],
      ),
    ));
  }

  @override
  Future<Result<({bool paid, String? message})>> checkQPay(
    String orderId,
    String paymentId,
  ) async {
    final outcome = qpayCheckOutcome;
    if (outcome == null) return super.checkQPay(orderId, paymentId);
    if (outcome.paid) qpayPaidAfterCheck = true;
    return Ok(outcome);
  }
}

Future<void> _pumpPayment(
  WidgetTester tester, {
  required User user,
  required ThemeData theme,
  double width = 375,
  double height = 800,
  _WidgetPaymentRepository? repository,
}) async {
  tester.binding.window.physicalSizeTestValue = Size(width, height);
  tester.binding.window.devicePixelRatioTestValue = 1;
  final repo = repository ?? _WidgetPaymentRepository();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: ChangeNotifierProvider(
        create: (_) =>
            OrderPaymentController(repo: repo, orderId: 'order-1', user: user),
        child: const OrderPaymentScreen(orderId: 'order-1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _openOption(WidgetTester tester, String optionKey) async {
  final open = find.byKey(const ValueKey('open_payment_sheet'));
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('pay_opt_$optionKey')));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().window
        .clearPhysicalSizeTestValue();
    TestWidgetsFlutterBinding.ensureInitialized().window
        .clearDevicePixelRatioTestValue();
  });

  testWidgets(
    'displays exact fractional Money strings and compact/wide light/dark layouts',
    (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final width in [375.0, 1024.0]) {
          await _pumpPayment(
            tester,
            user: _user(const [
              'payments.view',
              'payments.create',
              'payments.edit',
              'payments.delete',
            ]),
            theme: theme,
            width: width,
          );
          expect(find.text('100.50₮'), findsNWidgets(2));
          expect(find.text('0.00₮'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  testWidgets('permission affordances are independent', (tester) async {
    await _pumpPayment(
      tester,
      user: _user(const ['payments.view']),
      theme: AppTheme.light,
    );
    expect(find.byKey(const ValueKey('payment_amount_input')), findsNothing);
    await _openOption(tester, 'QPAY');
    expect(find.byKey(const ValueKey('pay_opt_CASH')), findsNothing);
    expect(find.byKey(const ValueKey('create_qpay')), findsNothing);
    expect(find.text('QPay нэхэмжлэл үүсгэх эрхгүй байна.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    await _pumpPayment(
      tester,
      user: _user(const ['payments.view', 'payments.create']),
      theme: AppTheme.light,
    );
    await _openOption(tester, 'CASH');
    expect(find.byKey(const ValueKey('payment_amount_input')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pay_sheet_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pay_opt_QPAY')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create_qpay')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'not-configured QPay shows the row with a message, no QR button',
    (tester) async {
      final repo = _WidgetPaymentRepository()..qpayEnabled = false;
      await _pumpPayment(
        tester,
        user: _user(const ['payments.view', 'payments.create']),
        theme: AppTheme.light,
        repository: repo,
      );
      await _openOption(tester, 'QPAY');
      expect(find.text(qpayNotConfiguredMessage), findsOneWidget);
      expect(find.byKey(const ValueKey('create_qpay')), findsNothing);
      expect(find.byKey(const ValueKey('qpay_amount_input')), findsNothing);
    },
  );

  testWidgets(
    'failed QPay status load shows retry, not the not-configured text',
    (tester) async {
      final repo = _WidgetPaymentRepository()..qpayLoadFails = true;
      await _pumpPayment(
        tester,
        user: _user(const ['payments.view', 'payments.create']),
        theme: AppTheme.light,
        repository: repo,
      );
      await _openOption(tester, 'QPAY');
      expect(find.text(qpayLoadFailedMessage), findsOneWidget);
      expect(find.text(qpayNotConfiguredMessage), findsNothing);
      repo.qpayLoadFails = false;
      await tester.tap(find.byKey(const ValueKey('qpay_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('qpay_amount_input')), findsOneWidget);
    },
  );

  testWidgets('QPay amount defaults to remaining, validates, and is sent', (
    tester,
  ) async {
    final repo = _WidgetPaymentRepository();
    await _pumpPayment(
      tester,
      user: _user(const ['payments.view', 'payments.create']),
      theme: AppTheme.light,
      height: 1100,
      repository: repo,
    );
    await _openOption(tester, 'QPAY');
    final input = find.byKey(const ValueKey('qpay_amount_input'));
    expect(tester.widget<TextField>(input).controller!.text, '100.50');

    await tester.enterText(input, '0');
    await tester.tap(find.byKey(const ValueKey('create_qpay')));
    await tester.pump();
    expect(find.text(qpayAmountRequiredMessage), findsOneWidget);
    expect(repo.lastQPayAmount, isNull);

    await tester.enterText(input, '100.51');
    await tester.tap(find.byKey(const ValueKey('create_qpay')));
    await tester.pump();
    expect(find.text(qpayAmountExceedsMessage), findsOneWidget);
    expect(repo.lastQPayAmount, isNull);

    await tester.enterText(input, '4000');
    expect(tester.widget<TextField>(input).controller!.text, '4,000');

    await tester.enterText(input, '40');
    await tester.tap(find.byKey(const ValueKey('create_qpay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(repo.lastQPayAmount, '40');
  });

  testWidgets('malformed QR and unsafe bank links render a safe fallback', (
    tester,
  ) async {
    await _pumpPayment(
      tester,
      user: _user(const ['payments.view', 'payments.edit', 'payments.delete']),
      theme: AppTheme.dark,
      repository: _WidgetPaymentRepository(malformedQPay: true),
    );
    await _openOption(tester, 'QPAY');
    expect(find.textContaining('QR зураг боломжгүй байна'), findsOneWidget);
    expect(find.text('Unsafe'), findsNothing);
    expect(find.text('Missing'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reverse is disabled with reason when payment is locked', (
    tester,
  ) async {
    final repo = _WidgetPaymentRepository(
      seedPaidLedger: true,
      lockedLedger: true,
    );
    await _pumpPayment(
      tester,
      user: _user(const ['payments.view', 'payments.delete']),
      theme: AppTheme.light,
      repository: repo,
    );
    final reverse = tester.widget<IconButton>(
      find.byKey(const ValueKey('reverse_payment_payment-1')),
    );
    expect(reverse.onPressed, isNull);
    expect(reverse.tooltip, CashSessionEntryLockedError.message);
    expect(repo.reversed, isFalse);
  });

  testWidgets('paid ledger rows expose reversal only with delete permission', (
    tester,
  ) async {
    final repo = _WidgetPaymentRepository(seedPaidLedger: true);
    await _pumpPayment(
      tester,
      user: _user(const ['payments.view', 'payments.delete']),
      theme: AppTheme.light,
      repository: repo,
    );
    expect(
      find.byKey(const ValueKey('reverse_payment_payment-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('reverse_payment_payment-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(repo.reversed, isTrue);
    expect(find.textContaining('Буцаасан'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    await _pumpPayment(
      tester,
      user: _user(const ['payments.view']),
      theme: AppTheme.light,
      repository: _WidgetPaymentRepository(seedPaidLedger: true),
    );
    expect(
      find.byKey(const ValueKey('reverse_payment_payment-1')),
      findsNothing,
    );
  });

  testWidgets(
    'pending QPay check and cancel controls are independently gated',
    (tester) async {
      Future<void> pumpWith(List<String> permissions) => _pumpPayment(
        tester,
        user: _user(permissions),
        theme: AppTheme.light,
        repository: _WidgetPaymentRepository(malformedQPay: true),
      );

      await pumpWith(const ['payments.view']);
      await _openOption(tester, 'QPAY');
      expect(
        (tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('check_qpay')),
        )).onPressed,
        isNull,
      );
      expect(
        (tester.widget<TextButton>(find.byKey(const ValueKey('cancel_qpay'))))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());

      await pumpWith(const ['payments.view', 'payments.edit']);
      await _openOption(tester, 'QPAY');
      expect(
        (tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('check_qpay')),
        )).onPressed,
        isNotNull,
      );
      expect(
        (tester.widget<TextButton>(find.byKey(const ValueKey('cancel_qpay'))))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());

      await pumpWith(const ['payments.view', 'payments.delete']);
      await _openOption(tester, 'QPAY');
      expect(
        (tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('check_qpay')),
        )).onPressed,
        isNull,
      );
      expect(
        (tester.widget<TextButton>(find.byKey(const ValueKey('cancel_qpay'))))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'paid QPay feedback remains visible after authoritative paid refresh',
    (tester) async {
      final repo = _WidgetPaymentRepository(
        qpayCheckOutcome: (paid: true, message: null),
      );
      await _pumpPayment(
        tester,
        user: _user(const [
          'payments.view',
          'payments.create',
          'payments.edit',
        ]),
        theme: AppTheme.light,
        // Taller: the fixed bank-picker slot pushes the QPay card down.
        height: 1100,
        repository: repo,
      );

      await _openOption(tester, 'QPAY');
      await tester.tap(find.byKey(const ValueKey('create_qpay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final checkButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('check_qpay')),
      );
      checkButton.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle(); // sheet closes once the order is paid

      expect(find.byKey(const ValueKey('qpay_check_feedback')), findsOneWidget);
      expect(find.text('QPay төлбөр амжилттай баталгаажлаа.'), findsOneWidget);
      expect(find.byKey(const ValueKey('check_qpay')), findsNothing);
    },
  );
}
