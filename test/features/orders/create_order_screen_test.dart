import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/features/orders/presentation/screens/create_order_screen.dart';

import '../../fakes/fake_order_repository.dart';
import '../../support/hive_test_setup.dart';

import 'package:get/get.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      home: CreateOrderScreen(repository: FakeOrderRepository()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  setUpAll(openTestHiveBoxes);

  testWidgets('cancelling the duration dialog leaves the duration unset', (
    tester,
  ) async {
    await _pump(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('create_order_duration_row')),
    );
    await tester.tap(find.byKey(const ValueKey('create_order_duration_row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('create_order_duration_input')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('create_order_duration_input')),
      '90',
    );
    await tester.tap(find.text('Болих'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('90 мин'), findsNothing);
    expect(find.text('Хугацаа сонгоно уу'), findsOneWidget);
  });

  testWidgets('confirming the duration dialog sets the estimated duration', (
    tester,
  ) async {
    await _pump(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('create_order_duration_row')),
    );
    await tester.tap(find.byKey(const ValueKey('create_order_duration_row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const ValueKey('create_order_duration_input')),
      '90',
    );
    await tester.tap(find.text('Сонгох'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('90 мин'), findsOneWidget);

    // No lingering "disposed TextEditingController" assertion after the
    // dialog's exit transition finishes — pump past it explicitly.
    await tester.pump(const Duration(milliseconds: 300));
  });

  group('vehicle first', () {
    const owner = CustomerSummary(id: 'c1', fullName: 'Бат', phone: '99001122');
    const owned = VehicleSummary(
      id: 'v1',
      plate: '1234УБА',
      make: 'Toyota',
      model: 'Prius',
      customerId: 'c1',
      customer: owner,
    );
    const ownerless = VehicleSummary(
      id: 'v2',
      plate: '5678УНА',
      make: 'Honda',
      model: 'Fit',
    );

    Future<List<String>> pumpWithSearch(WidgetTester tester) async {
      final queries = <String>[];
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          home: CreateOrderScreen(
            repository: FakeOrderRepository(),
            vehicleSearch: (q) async {
              queries.add(q);
              return const [owned, ownerless];
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      return queries;
    }

    Future<void> search(WidgetTester tester, String q) async {
      await tester.enterText(
        find.byKey(const ValueKey('create_order_vehicle_search')),
        q,
      );
      await tester.pump(const Duration(milliseconds: 401));
      await tester.pump();
    }

    testWidgets('the vehicle comes first and brings its owner', (tester) async {
      final queries = await pumpWithSearch(tester);
      // Vehicle search leads; the customer search is still there below.
      expect(
        find.byKey(const ValueKey('create_order_vehicle_search')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('create_order_customer_search')),
        findsOneWidget,
      );

      await search(tester, '1234');
      expect(queries, ['1234']);
      expect(
        find.byKey(const ValueKey('create_order_found_vehicle_v1')),
        findsOneWidget,
      );
      expect(find.text('Toyota Prius · Бат'), findsOneWidget);
      expect(find.text('Honda Fit · Эзэмшигчгүй'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('create_order_found_vehicle_v1')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('create_order_selected_vehicle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('create_order_vehicle_owner')),
        findsOneWidget,
      );
      expect(find.text('Харилцагч · машины эзэмшигч'), findsOneWidget);
      expect(find.text('Бат'), findsWidgets);
      // The owner can't be swapped on its own.
      expect(
        find.byKey(const ValueKey('create_order_customer_search')),
        findsNothing,
      );

      // Clearing the vehicle takes its owner with it.
      await tester.tap(
        find.byKey(const ValueKey('create_order_clear_vehicle')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('create_order_vehicle_owner')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('create_order_vehicle_search')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('create_order_customer_search')),
        findsOneWidget,
      );
    });

    testWidgets('a vehicle without an owner is not taken', (tester) async {
      await pumpWithSearch(tester);
      await search(tester, '5678');

      await tester.tap(
        find.byKey(const ValueKey('create_order_found_vehicle_v2')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('create_order_selected_vehicle')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('create_order_vehicle_notice')),
        findsOneWidget,
      );
      expect(find.textContaining('эзэмшигч бүртгэгдээгүй'), findsOneWidget);

      // A new search clears the note.
      await search(tester, '1234');
      expect(
        find.byKey(const ValueKey('create_order_vehicle_notice')),
        findsNothing,
      );
    });
  });
}
