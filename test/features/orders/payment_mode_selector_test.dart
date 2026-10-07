import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/features/orders/domain/order_payment_mode.dart';
import 'package:carservice_business/features/orders/presentation/widgets/payment_mode_selector.dart';

void main() {
  testWidgets('fits 360x640 at 1.3 text scale without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var mode = OrderPaymentMode.regular;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) => PaymentModeSelector(
                  value: mode,
                  onChanged: (m) => setState(() => mode = m),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (final m in OrderPaymentMode.values) {
      expect(find.text(m.label), findsOneWidget);
    }
    await tester.tap(find.text('Дотоод засвар'));
    await tester.pump();
    expect(mode, OrderPaymentMode.internal);
    expect(tester.takeException(), isNull);
  });
}
