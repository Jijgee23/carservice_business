import 'dart:async';

import 'package:carservice_business/core/domain/diagnostic.dart'
    show CustomerSummary;
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle_lookup.dart';
import 'package:carservice_business/features/vehicles/presentation/screens/vehicle_create_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../fakes/fake_customer_repository.dart';
import '../../fakes/fake_vehicle_lookup_repository.dart';
import '../../fakes/fake_vehicle_repository.dart';

/// Vehicle create at web parity: plate-first auto-lookup (400ms debounce),
/// info box, owner REQUIRED, owner-from-plate, inline lookup errors, plate-less
/// mode. Fields are located by the screen's `vehicleCreate.*` keys.
User _user(List<String> permissions) => User(
  accessToken: 't',
  refreshToken: 'r',
  id: 'u',
  email: 'u@example.test',
  firstName: 'A',
  lastName: 'B',
  phone: '99001122',
  isOwner: false,
  role: UserRole('role', 'Role', permissions),
  tenant: UserTenant('tenant', 'Tenant'),
);

const _prius = VehicleLookup(
  plate: '1234УБА',
  make: 'Toyota',
  model: 'Prius',
  year: 2015,
  vin: 'JTDKN3DU0A0000001',
  color: 'Цагаан',
  capacity: 1800,
  fuelType: 'Хайбрид',
  owner: LookupOwner(
    firstName: 'Бат',
    lastName: 'Дорж',
    phone: '99••••82',
    kind: 'Хувь хүн',
  ),
  source: 'hur',
);

void main() {
  late FakeVehicleRepository vehicles;
  late FakeCustomerRepository customers;
  late FakeVehicleLookupRepository lookup;

  setUp(() {
    vehicles = FakeVehicleRepository(seed: []);
    customers = FakeCustomerRepository(seed: []);
    lookup = FakeVehicleLookupRepository(vehicles: vehicles);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    CustomerSummary? customer,
    List<String> permissions = const ['customers.create'],
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: VehicleCreateScreen(
          vehiclesRepository: vehicles,
          customersRepository: customers,
          lookupRepository: lookup,
          initialCustomer: customer,
          user: _user(permissions),
        ),
      ),
    );
  }

  Finder key(String k) => find.byKey(Key('vehicleCreate.$k'));

  /// Types [plate] and closes the plate keypad («Бэлэн»), as staff do
  /// before going on with the form.
  Future<void> typePlate(WidgetTester tester, String plate) async {
    await tester.enterText(key('plate'), plate);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  bool submitEnabled(WidgetTester tester) =>
      tester.widget<ElevatedButton>(key('submit')).onPressed != null;

  const owner = CustomerSummary(id: 'c1', fullName: 'Бат', phone: '99001122');

  testWidgets('standard plate auto-looks up after the 400ms debounce and shows '
      'the info box', (tester) async {
    lookup.lookupResult = const Ok(_prius);
    await pumpScreen(tester);

    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 399));
    expect(lookup.lookupPlates, isEmpty);

    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(lookup.lookupPlates, ['1234УБА']);
    expect(key('infoBox'), findsOneWidget);
    expect(find.text('HUR-аас татсан мэдээлэл'), findsOneWidget);
    expect(find.text('Toyota'), findsOneWidget);
    expect(find.text('Prius'), findsOneWidget);
    // Lookup filled make/model, so the manual fields are not shown.
    expect(key('make'), findsNothing);
    // Spinner cleared.
    expect(key('lookupSpinner'), findsNothing);

    // Expandable extra details.
    expect(find.text('Өнгө'), findsNothing);
    await tester.tap(key('toggleDetails'));
    await tester.pump();
    expect(find.text('Өнгө'), findsOneWidget);
    expect(find.text('1800 см³'), findsOneWidget);
  });

  testWidgets('a plate typed on the plate keypad looks up like typing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.reset);
    lookup.lookupResult = const Ok(_prius);
    await pumpScreen(tester);

    await tester.tap(key('plate'));
    await tester.pumpAndSettle(); // the keypad opens
    for (final char in '1234УБА'.split('')) {
      await tester.tap(find.byKey(ValueKey('plate_key_$char')));
      await tester.pump();
    }
    expect(
      tester.widget<EditableText>(find.byType(EditableText).first).controller.text,
      '1234УБА',
    );
    await tester.pump(const Duration(milliseconds: 401));
    await tester.pump();
    expect(lookup.lookupPlates, ['1234УБА']);
  });

  testWidgets('global source is titled "Системийн бүртгэлээс"', (tester) async {
    lookup.lookupResult = const Ok(
      VehicleLookup(make: 'Honda', model: 'Fit', source: 'global'),
    );
    await pumpScreen(tester);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.text('Системийн бүртгэлээс'), findsOneWidget);
  });

  testWidgets(
    'non-standard plate does not auto-lookup and shows manual fields',
    (tester) async {
      await pumpScreen(tester);
      await typePlate(tester, 'ТРАНЗИТ1');
      await tester.pump(const Duration(milliseconds: 600));
      expect(lookup.lookupPlates, isEmpty);
      expect(key('make'), findsOneWidget);
      expect(find.textContaining('Стандарт бус дугаар'), findsOneWidget);
    },
  );

  testWidgets('changing the plate clears the previous lookup data', (
    tester,
  ) async {
    lookup.lookupResult = const Ok(_prius);
    await pumpScreen(tester);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(key('infoBox'), findsOneWidget);

    await typePlate(tester, '1234УБ');
    expect(key('infoBox'), findsNothing);
    // Lookup-prefilled values were wiped from the manual controllers too.
    expect(
      tester.widget<TextFormField>(key('make')).controller?.text ?? '',
      isEmpty,
    );
  });

  testWidgets('submit is disabled until an owner is chosen', (tester) async {
    lookup.lookupResult = const Ok(
      VehicleLookup(make: 'Toyota', model: 'Prius', source: 'hur'),
    );
    await pumpScreen(tester);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(submitEnabled(tester), isFalse);
    expect(key('ownerRequired'), findsOneWidget);
  });

  testWidgets('submit enables once the server-matched owner is preselected', (
    tester,
  ) async {
    final c = (await customers.createCustomer(
      fullName: 'Бат',
      phone: '99001122',
    )).valueOrNull!.customer;
    lookup.lookupResult = Ok(
      VehicleLookup(
        make: 'Toyota',
        model: 'Prius',
        source: 'hur',
        matchedCustomerId: c.id,
      ),
    );
    await pumpScreen(tester);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(key('ownerRequired'), findsNothing);
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('"register owner" calls from-plate and selects the customer', (
    tester,
  ) async {
    lookup.lookupResult = const Ok(_prius);
    lookup.ownerResult = const Ok(owner);
    await pumpScreen(tester);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(key('ownerInfo'), findsOneWidget);
    expect(find.textContaining('99••••82'), findsOneWidget);
    await tester.tap(key('registerOwner'));
    await tester.pumpAndSettle();

    expect(lookup.ownerPlates, ['1234УБА']);
    expect(key('registerOwner'), findsNothing);
    expect(key('ownerRequired'), findsNothing);
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('"register owner" is hidden without customers.create', (
    tester,
  ) async {
    lookup.lookupResult = const Ok(_prius);
    await pumpScreen(tester, permissions: const ['vehicles.create']);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(key('ownerInfo'), findsOneWidget);
    expect(key('registerOwner'), findsNothing);
  });

  testWidgets('"register owner" failure is shown inline', (tester) async {
    lookup.lookupResult = const Ok(_prius);
    lookup.ownerResult = const Err(
      AppError(
        ErrorKind.notFound,
        'Олдсонгүй',
        statusCode: 404,
        code: 'OWNER_NOT_FOUND',
      ),
    );
    await pumpScreen(tester);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(key('registerOwner'));
    await tester.pumpAndSettle();

    expect(key('registerError'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('429 shows an inline error, falls back to manual entry and '
      'clears the spinner', (tester) async {
    lookup.lookupResult = const Err(
      AppError(
        ErrorKind.unknown,
        'rate',
        statusCode: 429,
        code: 'RATE_LIMITED',
      ),
    );
    await pumpScreen(tester);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(key('lookupError'), findsOneWidget);
    expect(find.textContaining('Хэт олон хүсэлт'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(key('lookupSpinner'), findsNothing);
    expect(key('make'), findsOneWidget);
  });

  testWidgets('a lookup superseded by a plate edit never applies', (
    tester,
  ) async {
    final gate = Completer<Result<VehicleLookup>>();
    lookup.lookupGate = gate;
    await pumpScreen(tester);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450)); // in flight
    expect(lookup.lookupPlates, ['1234УБА']);
    expect(key('lookupSpinner'), findsOneWidget);

    await typePlate(tester, '9999'); // edit while in flight
    expect(key('lookupSpinner'), findsNothing);
    gate.complete(const Ok(_prius)); // stale result arrives late
    await tester.pump();
    await tester.pump();
    expect(key('infoBox'), findsNothing);
    expect(key('lookupSpinner'), findsNothing);
  });

  testWidgets('register-owner result is ignored if the plate changed '
      'in flight', (tester) async {
    lookup.lookupResult = const Ok(_prius);
    final gate = Completer<Result<CustomerSummary>>();
    lookup.ownerGate = gate;
    await pumpScreen(tester);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(key('registerOwner'));
    await tester.pump();
    expect(lookup.ownerPlates, ['1234УБА']);

    await typePlate(tester, '1234УБ');
    gate.complete(const Ok(owner));
    await tester.pumpAndSettle();
    expect(key('ownerRequired'), findsOneWidget); // owner NOT selected
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('field errors for hidden fields on the fromLookup path show in '
      'the general banner', (tester) async {
    lookup.lookupResult = const Ok(
      VehicleLookup(make: 'Toyota', model: 'Prius', vin: 'X', source: 'hur'),
    );
    lookup.fromLookupError = const Err(
      AppError(
        ErrorKind.unknown,
        'Хүсэлт буруу.',
        statusCode: 422,
        fieldErrors: {'vin': 'VIN буруу байна.'},
      ),
    );
    await pumpScreen(tester, customer: owner);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.ensureVisible(key('submit'));
    await tester.tap(key('submit'));
    await tester.pumpAndSettle();

    expect(find.text('VIN буруу байна.'), findsOneWidget);
  });

  testWidgets('plate-less mode skips lookup, requires VIN, and can go back', (
    tester,
  ) async {
    await pumpScreen(tester, customer: owner);
    await tester.ensureVisible(key('noPlate'));
    await tester.tap(key('noPlate'));
    await tester.pump();

    expect(key('plate'), findsNothing);
    expect(key('make'), findsOneWidget);
    expect(lookup.lookupPlates, isEmpty);

    await tester.enterText(key('make'), 'Toyota');
    await tester.enterText(key('model'), 'Prius');
    await tester.pump();
    expect(submitEnabled(tester), isFalse); // VIN missing

    await tester.enterText(key('vin'), 'JTDKN3DU0A0000001');
    await tester.pump();
    expect(submitEnabled(tester), isTrue);

    await tester.tap(key('backToPlate'));
    await tester.pump();
    expect(key('plate'), findsOneWidget);
    expect(key('make'), findsNothing);
  });

  testWidgets('saving with a complete lookup uses the fromLookup create path', (
    tester,
  ) async {
    lookup.lookupResult = const Ok(
      VehicleLookup(
        make: 'Toyota',
        model: 'Prius',
        year: 2015,
        vin: 'JTDKN3DU0A0000001',
        source: 'hur',
      ),
    );
    await pumpScreen(tester, customer: owner);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    await tester.ensureVisible(key('submit'));
    await tester.tap(key('submit'));
    await tester.pumpAndSettle();

    expect(lookup.fromLookupCreates, hasLength(1));
    expect(lookup.fromLookupCreates.single['plate'], '1234УБА');
    expect(lookup.fromLookupCreates.single['customerId'], 'c1');
    expect(lookup.fromLookupCreates.single['make'], 'Toyota');
    expect((await vehicles.getVehicles()).valueOrNull!.items, hasLength(1));
  });

  testWidgets(
    'manual save goes through the plain create path (no fromLookup)',
    (tester) async {
      await pumpScreen(tester, customer: owner);
      await typePlate(tester, '1234УБА');
      await tester.pump(const Duration(milliseconds: 450)); // 404 -> manual
      await tester.pump();
      await tester.enterText(key('make'), 'Toyota');
      await tester.enterText(key('model'), 'Prius');
      await tester.pump();

      await tester.ensureVisible(key('submit'));
      await tester.tap(key('submit'));
      await tester.pumpAndSettle();

      expect(lookup.fromLookupCreates, isEmpty);
      expect((await vehicles.getVehicles()).valueOrNull!.items, hasLength(1));
    },
  );

  testWidgets('a repository 422 with fieldErrors binds to the field', (
    tester,
  ) async {
    await pumpScreen(tester, customer: owner);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.enterText(key('make'), 'Toyota');
    await tester.enterText(key('model'), 'Prius');
    await tester.enterText(key('year'), '1800');
    await tester.pump();

    await tester.ensureVisible(key('submit'));
    await tester.tap(key('submit'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Жил буруу.'), findsOneWidget);
    expect((await vehicles.getVehicles()).valueOrNull!.items, isEmpty);
  });

  testWidgets('plan limit (422 without fieldErrors) shows a general message', (
    tester,
  ) async {
    vehicles = FakeVehicleRepository(seed: [], maxVehicles: 0);
    lookup = FakeVehicleLookupRepository(vehicles: vehicles);
    await pumpScreen(tester, customer: owner);
    await typePlate(tester, '1234УБА');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.enterText(key('make'), 'Toyota');
    await tester.enterText(key('model'), 'Prius');
    await tester.pump();

    await tester.ensureVisible(key('submit'));
    await tester.tap(key('submit'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Машины хязгаарт хүрсэн байна.'), findsOneWidget);
  });
}
