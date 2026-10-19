import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/widgets/detail/order_item_widgets.dart';
import 'package:carservice_business/features/orders/presentation/widgets/order_status_prompt.dart';

ServiceItem _item(
  ServiceItemStatus status, {
  ItemKind kind = ItemKind.LABOR,
  String? reportId,
}) => ServiceItem(
  id: 'i1',
  kind: kind,
  description: 'Line',
  quantity: 1,
  unitPrice: 100,
  total: 100,
  status: status,
  diagnosticReportId: reportId,
);

Future<void> _pump(
  WidgetTester tester,
  ServiceItem item, {
  bool paidLocked = false,
  String paidLockReason = paidLockHint,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: OrderItemCard(
          item: item,
          locked: false,
          paidLocked: paidLocked,
          paidLockReason: paidLockReason,
          canEdit: true,
          canPrice: true,
          canStatus: true,
          diagnosticEditable: false,
          onEdit: () {},
          onCancel: () {},
          onStatus: (_) {},
        ),
      ),
    ),
  );
}

bool _enabled(WidgetTester tester, String key) {
  final w = tester.widget(find.byKey(ValueKey(key)));
  if (w is IconButton) return w.onPressed != null;
  if (w is InkWell) return w.onTap != null;
  throw StateError('unexpected $w');
}

void main() {
  testWidgets('paid line cancel disabled with refund or closed-shift reason', (
    tester,
  ) async {
    await _pump(tester, _item(ServiceItemStatus.IN_PROGRESS), paidLocked: true);
    expect(_enabled(tester, 'item_cancel_button'), isFalse);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('item_cancel_button')))
          .tooltip,
      paidLockHint,
    );
    await _pump(
      tester,
      _item(ServiceItemStatus.IN_PROGRESS),
      paidLocked: true,
      paidLockReason: closedShiftLockHint,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('item_cancel_button')))
          .tooltip,
      closedShiftLockHint,
    );
  });

  testWidgets('COMPLETED service line disables edit and cancel, keeps reopen', (
    tester,
  ) async {
    await _pump(tester, _item(ServiceItemStatus.COMPLETED));
    expect(_enabled(tester, 'item_edit_button'), isFalse);
    expect(_enabled(tester, 'item_status_button'), isTrue);
    expect(_enabled(tester, 'item_cancel_button'), isFalse);
    expect(find.text(completedLineLockedHint), findsOneWidget);
  });

  testWidgets('open service line keeps actions enabled', (tester) async {
    await _pump(tester, _item(ServiceItemStatus.IN_PROGRESS));
    expect(_enabled(tester, 'item_edit_button'), isTrue);
    expect(_enabled(tester, 'item_status_button'), isTrue);
    expect(_enabled(tester, 'item_cancel_button'), isTrue);
    expect(find.text(completedLineLockedHint), findsNothing);
  });

  testWidgets('PART line is not locked by line status', (tester) async {
    await _pump(
      tester,
      _item(ServiceItemStatus.COMPLETED, kind: ItemKind.PART),
    );
    expect(_enabled(tester, 'item_edit_button'), isTrue);
    expect(_enabled(tester, 'item_cancel_button'), isTrue);
  });

  testWidgets('COMPLETED diagnostic line with a report cannot be reopened', (
    tester,
  ) async {
    await _pump(
      tester,
      _item(
        ServiceItemStatus.COMPLETED,
        kind: ItemKind.DIAGNOSTIC,
        reportId: 'r1',
      ),
    );
    expect(_enabled(tester, 'item_status_button'), isFalse);
    expect(_enabled(tester, 'item_edit_button'), isFalse);
  });
}
