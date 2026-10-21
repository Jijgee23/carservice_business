import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';
import 'package:carservice_business/features/orders/presentation/widgets/payment_method_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(393, 852);

const _banks = [
  PaymentBank(
    id: 'acc-khan',
    label: 'Хаан банк',
    accountNumber: '5000121234',
    maskedNumber: '5000 **** 1234',
  ),
  PaymentBank(id: 'pos-khan', label: 'Хаан банк', isPos: true, terminalId: 'T1'),
];

PaymentMethodSheet _record({List<PaymentBank> banks = _banks}) =>
    PaymentMethodSheet(
      title: 'Төлбөр бүртгэх',
      balance: '150000.00',
      banks: banks,
      defaultAmount: '150000',
      onRecord: (_, _) async => false,
    );

/// Opens [show] from a button so the sheet runs in a real modal route.
Future<BuildContext> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext context) show,
) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext host;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) {
          host = context;
          return Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => show(context),
                child: const Text('open'),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  return host;
}

double _sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byType(PaymentMethodSheet)).height;

void main() {
  testWidgets('the header shows the outstanding balance, formatted', (
    tester,
  ) async {
    await _open(
      tester,
      (c) => PaymentMethodSheet.showRecord(c, builder: _record),
    );
    expect(find.text('Төлбөр бүртгэх'), findsOneWidget);
    expect(find.text('Үлдэгдэл 150,000₮'), findsOneWidget);
    // Transfer rows carry the full account number, POS rows the TID.
    await tester.tap(find.byKey(const ValueKey('pay_method_select')));
    await tester.pumpAndSettle();
    expect(find.text('5000121234'), findsOneWidget);
    expect(find.text('5000 **** 1234'), findsNothing);
    expect(find.text('TID T1'), findsOneWidget);
  });

  testWidgets('the sheet is as tall as its content, capped at 92%', (
    tester,
  ) async {
    await _open(
      tester,
      (c) => PaymentMethodSheet.showRecord(c, builder: _record),
    );
    final formHeight = _sheetHeight(tester);
    expect(formHeight, lessThan(_screen.height * 0.92));

    Navigator.of(tester.element(find.byType(PaymentMethodSheet))).pop();
    await tester.pumpAndSettle();
    await _open(
      tester,
      (c) => PaymentMethodSheet.showRecord(
        c,
        builder: () => _record(
          banks: [
            for (var i = 0; i < 20; i++)
              PaymentBank(id: 'acc-$i', label: 'Банк $i'),
          ],
        ),
      ),
    );
    // The bank list lives in the method picker, so the form keeps its size.
    expect(_sheetHeight(tester), formHeight);
    await tester.tap(find.byKey(const ValueKey('pay_method_select')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PaymentMethodSheet).last).height,
      lessThanOrEqualTo(_screen.height * 0.92),
    );
  });

  testWidgets('the record button stays above the keyboard', (tester) async {
    await _open(
      tester,
      (c) => PaymentMethodSheet.showRecord(c, builder: _record),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('create_manual_payment'));
    expect(
      tester.getBottomLeft(button).dy,
      lessThanOrEqualTo(_screen.height - 336),
    );
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker mode marks the choice and returns it', (tester) async {
    PaymentChoice? picked;
    await _open(tester, (c) async {
      picked = await PaymentMethodSheet.pick(
        c,
        banks: _banks,
        current: const PaymentChoice(OrderPaymentMethod.CASH),
      );
    });

    await tester.tap(find.byKey(const ValueKey('pay_opt_CARD_pos-khan')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pay_opt_CARD_pos-khan')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('pay_pick_confirm')));
    await tester.pumpAndSettle();
    expect(
      picked,
      const PaymentChoice(OrderPaymentMethod.CARD, 'pos-khan'),
    );
  });

  group('record form', () {
    TextField amountField(WidgetTester tester) => tester.widget<TextField>(
      find.byKey(const ValueKey('payment_amount_input')),
    );

    testWidgets('amount, methods and the action share one form', (
      tester,
    ) async {
      final recorded = <(PaymentChoice, String)>[];
      await _open(
        tester,
        (c) => PaymentMethodSheet.showRecord(
          c,
          builder: () => PaymentMethodSheet(
            title: 'Төлбөр бүртгэх',
            balance: '150000',
            banks: _banks,
            defaultAmount: '150000',
            validateAmount: (a) =>
                double.parse(a.isEmpty ? '0' : a) <= 0 ? 'Дүнгээ оруулна уу.' : null,
            onRecord: (choice, amount) async {
              recorded.add((choice, amount));
              return true;
            },
          ),
        ),
      );

      // Defaults to the unpaid balance; cash is preselected.
      expect(amountField(tester).controller!.text, '150,000');
      expect(find.widgetWithText(FilledButton, 'Бүртгэх'), findsOneWidget);

      // The method field opens the list; a tap picks and closes it.
      Future<void> pick(String key) async {
        await tester.tap(find.byKey(const ValueKey('pay_method_select')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('pay_opt_$key')));
        await tester.pumpAndSettle();
      }

      await pick('CARD_pos-khan');
      expect(find.byType(PaymentMethodSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('pay_sheet_back')), findsNothing);
      expect(find.text('Хаан банк · POS'), findsOneWidget);
      // POS is only the method: it records like the others.
      expect(find.widgetWithText(FilledButton, 'Бүртгэх'), findsOneWidget);

      await pick('BANK_TRANSFER_acc-khan');
      await tester.enterText(find.byKey(const ValueKey('payment_amount_input')), '0');
      await tester.tap(find.byKey(const ValueKey('create_manual_payment')));
      await tester.pump();
      expect(find.text('Дүнгээ оруулна уу.'), findsOneWidget);
      expect(recorded, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('payment_amount_input')), '5000');
      await tester.tap(find.byKey(const ValueKey('create_manual_payment')));
      await tester.pumpAndSettle();
      expect(recorded.single.$1, const PaymentChoice(OrderPaymentMethod.BANK_TRANSFER, 'acc-khan'));
      expect(recorded.single.$2, '5000');
      expect(find.byType(PaymentMethodSheet), findsNothing);
    });

    testWidgets('more than the unpaid balance cannot be typed', (tester) async {
      await _open(
        tester,
        (c) => PaymentMethodSheet.showRecord(
          c,
          builder: () => PaymentMethodSheet(
            title: 'Төлбөр бүртгэх',
            banks: _banks,
            defaultAmount: '150000',
            maxAmount: '150000',
            validateAmount: (a) =>
                double.parse(a) > 150000 ? 'Дүн үлдэгдлээс их байж болохгүй.' : null,
            onRecord: (_, _) async => false,
          ),
        ),
      );
      final input = find.byKey(const ValueKey('payment_amount_input'));

      await tester.enterText(input, '150001');
      await tester.pump();
      expect(amountField(tester).controller!.text, '150,000');
      expect(find.text('Дүн үлдэгдлээс их байж болохгүй.'), findsOneWidget);

      // A smaller amount goes through and clears the message.
      await tester.enterText(input, '90000');
      await tester.pump();
      expect(amountField(tester).controller!.text, '90,000');
      expect(find.text('Дүн үлдэгдлээс их байж болохгүй.'), findsNothing);
    });

    testWidgets('the clear button empties the amount, ready to type', (
      tester,
    ) async {
      await _open(tester, (c) => PaymentMethodSheet.showRecord(c, builder: _record));
      final clear = find.byKey(const ValueKey('payment_amount_clear'));
      expect(clear, findsOneWidget);

      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(amountField(tester).controller!.text, isEmpty);
      expect(amountField(tester).focusNode!.hasFocus, isTrue);
      expect(clear, findsNothing);

      await tester.enterText(find.byKey(const ValueKey('payment_amount_input')), '25');
      await tester.pump();
      expect(clear, findsOneWidget);
    });

    testWidgets('QPay creates from the form and shows the invoice until it is gone', (
      tester,
    ) async {
      final pending = ValueNotifier(false);
      String? created;
      await _open(
        tester,
        (c) => PaymentMethodSheet.showRecord(
          c,
          builder: () => PaymentMethodSheet(
            title: 'Төлбөр бүртгэх',
            banks: _banks,
            defaultAmount: '150000',
            includeQPay: true,
            listenable: pending,
            onRecord: (_, _) async => false,
            qpay: QPaySheetHooks(
              pending: () => pending.value,
              canCreate: () => true,
              create: (amount) async {
                created = amount;
                pending.value = true;
                return true;
              },
              noteBuilder: (_) => pending.value ? const Text('pending note') : null,
              viewBuilder: (_) => const Text('qr view'),
            ),
          ),
        ),
      );

      // QPay is its own button beside the method's, not a method.
      expect(find.byKey(const ValueKey('create_manual_payment')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('create_qpay')));
      await tester.pumpAndSettle();
      expect(created, '150000');
      expect(find.text('qr view'), findsOneWidget);
      expect(find.byKey(const ValueKey('pay_sheet_back')), findsOneWidget);

      // Back to the form: the invoice is still there to reopen.
      await tester.tap(find.byKey(const ValueKey('pay_sheet_back')));
      await tester.pumpAndSettle();
      expect(find.text('pending note'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('view_qpay')));
      await tester.pumpAndSettle();
      expect(find.text('qr view'), findsOneWidget);

      // Cancelled elsewhere: the form comes back by itself.
      pending.value = false;
      await tester.pumpAndSettle();
      expect(find.text('qr view'), findsNothing);
      expect(find.byKey(const ValueKey('create_qpay')), findsOneWidget);
      expect(find.byKey(const ValueKey('pay_sheet_back')), findsNothing);
    });
  });
}
