import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/plate_registration.dart';
import 'package:carservice_business/core/utils/result.dart';
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

  testWidgets('cancelling the duration dialog leaves the duration unset', (tester) async {
    await _pump(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('create_order_duration_row')));
    await tester.tap(find.byKey(const ValueKey('create_order_duration_row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('create_order_duration_input')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('create_order_duration_input')), '90');
    await tester.tap(find.text('Болих'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('90 мин'), findsNothing);
    expect(find.text('Хугацаа сонгоно уу'), findsOneWidget);
  });

  testWidgets('confirming the duration dialog sets the estimated duration', (tester) async {
    await _pump(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('create_order_duration_row')));
    await tester.tap(find.byKey(const ValueKey('create_order_duration_row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byKey(const ValueKey('create_order_duration_input')), '90');
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
    const ownerless = VehicleSummary(id: 'v2', plate: '5678УНА', make: 'Honda', model: 'Fit');

    final registerCalls = <String>[];

    /// «+ бүртгэх»: nothing found by plate until make/model are given; then
    /// registered without an owner (no customer picked).
    Future<Result<PlateRegistration>> register({
      required String plate,
      String? customerId,
      String? make,
      String? model,
    }) async {
      registerCalls.add('$plate|${customerId ?? '-'}|${make ?? '-'}|${model ?? '-'}');
      if (make == null || model == null) {
        return const Ok(
          PlateNeedsDetails('Машины мэдээлэл олдсонгүй — марк, загвараа оруулна уу.'),
        );
      }
      return Ok(
        PlateRegistered(
          VehicleSummary(id: 'v9', plate: plate, make: make, model: model, customerId: customerId),
        ),
      );
    }

    Future<List<String>> pumpWithSearch(WidgetTester tester) async {
      final queries = <String>[];
      registerCalls.clear();
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
            vehicleRegister: register,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      return queries;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('vehicle_picker_field')));
      await settle(tester);
    }

    Future<void> search(WidgetTester tester, String q) async {
      await tester.enterText(find.byKey(const ValueKey('vehicle_picker_search')), q);
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pump();
    }

    testWidgets('the vehicle comes first and brings its owner', (tester) async {
      final queries = await pumpWithSearch(tester);
      // Vehicle picker leads; the customer search is still there below.
      expect(find.byKey(const ValueKey('create_order_vehicle_picker')), findsOneWidget);
      expect(find.byKey(const ValueKey('create_order_customer_search')), findsOneWidget);

      // The dropdown opens with options listed, then searches as typed.
      await openPicker(tester);
      await search(tester, '1234');
      expect(queries, ['', '1234']);
      expect(find.byKey(const ValueKey('vehicle_picker_option_v1')), findsOneWidget);
      expect(find.text('Toyota Prius · Бат'), findsOneWidget);
      // A vehicle with no owner isn't offered when no customer is picked.
      expect(find.byKey(const ValueKey('vehicle_picker_option_v2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('vehicle_picker_option_v1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('vehicle_picker_selected')), findsOneWidget);
      expect(find.byKey(const ValueKey('create_order_vehicle_owner')), findsOneWidget);
      expect(find.text('Харилцагч · машины эзэмшигч'), findsOneWidget);
      expect(find.text('Бат'), findsWidgets);
      // The owner can't be swapped on its own.
      expect(find.byKey(const ValueKey('create_order_customer_search')), findsNothing);

      // Clearing the vehicle takes its owner with it.
      await tester.tap(find.byKey(const ValueKey('vehicle_picker_clear')));
      await tester.pump();
      expect(find.byKey(const ValueKey('create_order_vehicle_owner')), findsNothing);
      expect(find.byKey(const ValueKey('vehicle_picker_selected')), findsNothing);
      expect(find.byKey(const ValueKey('create_order_customer_search')), findsOneWidget);
    });

    testWidgets('an unlisted plate registers from the search, ownerless', (tester) async {
      await pumpWithSearch(tester);
      await openPicker(tester);

      await search(tester, '9999 уба');
      expect(find.text('+ 9999УБА — машин бүртгэх'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vehicle_picker_create')));
      await settle(tester);

      // Nothing found by plate: make and model inline, then register.
      expect(find.byKey(const ValueKey('vehicle_picker_details')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('vehicle_picker_make')), 'Toyota');
      await tester.enterText(find.byKey(const ValueKey('vehicle_picker_model')), 'Aqua');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('vehicle_picker_register_details')));
      await settle(tester);

      expect(registerCalls, ['9999УБА|-|-|-', '9999УБА|-|Toyota|Aqua']);
      expect(find.byKey(const ValueKey('vehicle_picker_details')), findsNothing);
      expect(find.byKey(const ValueKey('vehicle_picker_selected')), findsOneWidget);
      expect(find.text('Эзэмшигчгүй — сонгосон үйлчлүүлэгчид холбогдоно'), findsOneWidget);
      // No owner to take: the customer is still picked by hand.
      expect(find.byKey(const ValueKey('create_order_vehicle_owner')), findsNothing);
      expect(find.byKey(const ValueKey('create_order_customer_search')), findsOneWidget);
    });
  });
}
