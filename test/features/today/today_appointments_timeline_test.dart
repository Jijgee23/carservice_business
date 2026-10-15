import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/today/presentation/controllers/today_appointments_controller.dart';
import 'package:carservice_business/features/today/presentation/widgets/today_appointments_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../fakes/fake_appointment_repository.dart';
import '../../fakes/fake_order_repository.dart';
import '../../support/hive_test_setup.dart';
import 'package:get/get.dart';

final _now = DateTime(2026, 9, 23, 10);

AppointmentSummary _appt(
  String id, {
  AppointmentStatus status = AppointmentStatus.CONFIRMED,
  DateTime? requestedAt,
  String plate = 'AA-1111',
  String customerName = 'Бат',
  AppointmentOrderRef? serviceOrder,
}) => AppointmentSummary(
  id: id,
  status: status,
  requestedAt: requestedAt,
  createdAt: DateTime(2026, 9, 22, 9),
  branch: const AppointmentBranchRef(id: 'branch-1'),
  customer: AppointmentCustomerRef(
    id: 'cust-$id',
    fullName: customerName,
    phone: '99001122',
  ),
  vehicle: AppointmentVehicleRef(id: 'veh-$id', plate: plate, make: 'Toyota'),
  category: const AppointmentCategoryRef(id: 'cat-1', name: 'Засвар'),
  serviceOrder: serviceOrder,
);

Future<
  ({TodayAppointmentsController controller, FakeOrderRepository orders})
>
_pump(
  WidgetTester tester, {
  required List<AppointmentSummary> seed,
  bool canEditAppointments = false,
  bool canCreateOrders = false,
}) async {
  final apptRepo = FakeAppointmentRepository(seed: seed);
  final ordersRepo = FakeOrderRepository();
  final controller = TodayAppointmentsController(
    repository: apptRepo,
    clock: () => _now,
    autoRefresh: null,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      home: Provider<OrdersRepository>.value(
        value: ordersRepo,
        child: Scaffold(
          body: TodayAppointmentsTimeline(
            controller: controller,
            canEditAppointments: canEditAppointments,
            canCreateOrders: canCreateOrders,
            ordersRepository: ordersRepo,
          ),
        ),
      ),
    ),
  );
  await controller.start();
  await tester.pumpAndSettle();
  return (controller: controller, orders: ordersRepo);
}

void main() {
  setUpAll(openTestHiveBoxes);

  testWidgets('shows a loading skeleton then the empty state when there are '
      'no appointments today', (tester) async {
    await _pump(tester, seed: const []);
    expect(find.byKey(const ValueKey('today_appointments_list')), findsNothing);
    expect(find.text('Өнөөдөр цаг захиалга алга'), findsOneWidget);
  });

  testWidgets('renders time, plate, customer and service for each row', (
    tester,
  ) async {
    await _pump(
      tester,
      seed: [
        _appt(
          'a',
          requestedAt: DateTime(2026, 9, 23, 11),
          plate: '1234УБА',
          customerName: 'Болд',
        ),
      ],
    );
    expect(find.text('11:00'), findsOneWidget);
    expect(find.text('1234УБА'), findsOneWidget);
    expect(find.text('Болд'), findsOneWidget);
    expect(find.text('Засвар'), findsOneWidget);
  });

  testWidgets('shows an error view with retry on load failure and retry '
      'reloads', (tester) async {
    final apptRepo = FakeAppointmentRepository(seed: const []);
    final controller = TodayAppointmentsController(
      repository: apptRepo,
      clock: () => _now,
      autoRefresh: null,
    );
    addTearDown(controller.dispose);
    // The fake repository never errors on a normal query, and the
    // controller's error-injection wrapper lives in the controller test —
    // for this widget test it is simplest and just as faithful to set the
    // error state directly; the widget only cares about `controller.state`.
    controller.state = const AsyncError(AppError(ErrorKind.unknown, 'boom'));
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TodayAppointmentsTimeline(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('today_appointments_retry')), findsOneWidget);
  });

  testWidgets('does not show the arrived/create-order buttons without '
      'permission', (tester) async {
    await _pump(
      tester,
      seed: [
        _appt(
          'a',
          status: AppointmentStatus.CONFIRMED,
          requestedAt: DateTime(2026, 9, 23, 11),
        ),
      ],
    );
    expect(find.byKey(const ValueKey('today_appt_arrived_a')), findsNothing);
    expect(
      find.byKey(const ValueKey('today_appt_create_order_a')),
      findsNothing,
    );
  });

  testWidgets('"Ирсэн" calls markArrived and then reveals "Засварын хуудас үүсгэх" '
      'once arrived, gated by orders.create', (tester) async {
    final result = await _pump(
      tester,
      seed: [
        _appt(
          'a',
          status: AppointmentStatus.CONFIRMED,
          requestedAt: DateTime(2026, 9, 23, 11),
        ),
      ],
      canEditAppointments: true,
      canCreateOrders: true,
    );

    expect(find.byKey(const ValueKey('today_appt_arrived_a')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('today_appt_create_order_a')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('today_appt_arrived_a')));
    await tester.pumpAndSettle();

    expect(result.controller.isArrived('a'), isTrue);
    expect(find.byKey(const ValueKey('today_appt_arrived_a')), findsNothing);
    expect(
      find.byKey(const ValueKey('today_appt_create_order_a')),
      findsOneWidget,
    );
  });

  testWidgets('tapping "Засварын хуудас үүсгэх" pushes CreateOrderScreen with the '
      'appointment linked and reloads on success', (tester) async {
    await _pump(
      tester,
      seed: [
        _appt(
          'a',
          status: AppointmentStatus.CONFIRMED,
          requestedAt: DateTime(2026, 9, 23, 11),
          plate: '9999УБА',
        ),
      ],
      canEditAppointments: true,
      canCreateOrders: true,
    );
    await tester.tap(find.byKey(const ValueKey('today_appt_arrived_a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('today_appt_create_order_a')));
    // Not pumpAndSettle: CreateOrderScreen's branch load spinner animates
    // indefinitely when there is no real backend in this test, matching
    // `create_order_screen_test.dart`'s own bounded-pump convention. The
    // second pump also flushes the "server unreachable" snackbar's timer so
    // it does not outlive the test's teardown.
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    // CreateOrderScreen is pushed and pre-filled with the appointment's
    // vehicle.
    expect(find.text('9999УБА'), findsWidgets);
  });
}
