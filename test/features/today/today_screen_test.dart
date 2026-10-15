import 'package:carservice_business/app/router.dart' show AppPages;
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/today/presentation/controllers/today_appointments_controller.dart';
import 'package:carservice_business/features/today/presentation/controllers/today_orders_controller.dart';
import 'package:carservice_business/features/today/presentation/screens/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../fakes/fake_appointment_repository.dart';
import 'today_fixtures.dart';

import 'package:get/get.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

User _user({bool owner = false, List<String> permissions = const []}) => User(
  accessToken: 't',
  refreshToken: 'r',
  id: 'me',
  email: 'me@example.com',
  firstName: 'Me',
  lastName: 'User',
  phone: '',
  isOwner: owner,
  role: owner ? null : UserRole('role', 'Role', permissions),
  tenant: UserTenant('tenant', 'Tenant'),
);

void _viewport(WidgetTester tester, double width, [double height = 900]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

Future<TodayFakeRepository> _pump(
  WidgetTester tester, {
  required User user,
  Map<OrderStatus, List<ServiceOrderSummary>> byStatus = const {},
}) async {
  final repo = TodayFakeRepository(byStatus: byStatus);
  final controller = TodayOrdersController(
    repository: repo,
    clock: () => todayNow,
    autoRefresh: null,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      // Production mounts TodayScreen inside the app shell's Scaffold.
      home: Scaffold(
        body: TodayScreen(
          controller: controller,
          user: user,
          loadSubscription: () async => null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

final _board = {
  OrderStatus.SCHEDULED: [
    todayOrder('w1', plate: '1111УБА', scheduledAt: DateTime(2026, 9, 23, 11)),
  ],
  OrderStatus.IN_PROGRESS: [
    todayOrder(
      'p1',
      plate: '2222УБА',
      status: OrderStatus.IN_PROGRESS,
      startedAt: DateTime(2026, 9, 23, 9, 15),
    ),
  ],
  OrderStatus.COMPLETED: [
    todayOrder(
      'c1',
      plate: '3333УБА',
      status: OrderStatus.COMPLETED,
      completedAt: DateTime(2026, 9, 23, 9, 50),
    ),
  ],
};

void main() {
  testWidgets('tablet width shows all three lanes side by side', (
    tester,
  ) async {
    _viewport(tester, 1280, 800);
    await _pump(tester, user: _user(owner: true), byStatus: _board);

    expect(find.text('Хүлээгдэж буй'), findsOneWidget);
    expect(find.text('Хийгдэж буй'), findsOneWidget);
    expect(find.text('Өнөөдөр дууссан'), findsOneWidget);
    expect(find.text('1111УБА'), findsOneWidget);
    expect(find.text('2222УБА'), findsOneWidget);
    expect(find.text('3333УБА'), findsOneWidget);
    expect(find.byKey(const ValueKey('today_lane_selector')), findsNothing);
    expect(find.text('45 мин'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone width uses a lane selector, opening in-progress first', (
    tester,
  ) async {
    _viewport(tester, 375, 812);
    await _pump(tester, user: _user(owner: true), byStatus: _board);

    expect(find.byKey(const ValueKey('today_lane_selector')), findsOneWidget);
    expect(find.text('2222УБА'), findsOneWidget);
    expect(find.text('1111УБА'), findsNothing);

    await tester.tap(find.text('Хүлээгдэж 1'));
    await tester.pumpAndSettle();
    expect(find.text('1111УБА'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the start confirmation sends nothing', (
    tester,
  ) async {
    _viewport(tester, 1280, 800);
    final repo = await _pump(
      tester,
      user: _user(owner: true),
      byStatus: _board,
    );

    await tester.tap(find.byKey(const ValueKey('today_action_start_w1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Болих'));
    await tester.pumpAndSettle();

    expect(repo.updates, isEmpty);
  });

  testWidgets('editOwn users only get actions on orders assigned to them', (
    tester,
  ) async {
    _viewport(tester, 1280, 800);
    await _pump(
      tester,
      user: _user(permissions: const ['orders.viewOwn', 'orders.editOwn']),
      byStatus: {
        OrderStatus.SCHEDULED: [
          todayOrder(
            'mine',
            assignedTo: const UserSummary(
              id: 'me',
              firstName: 'Me',
              lastName: 'User',
            ),
          ),
          todayOrder('theirs'),
        ],
      },
    );

    expect(
      find.byKey(const ValueKey('today_action_start_mine')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('today_action_start_theirs')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('today_create_order')), findsNothing);
  });

  testWidgets('unpaid completed orders offer Payment only with payments.view', (
    tester,
  ) async {
    _viewport(tester, 1280, 800);
    await _pump(
      tester,
      user: _user(permissions: const ['orders.view']),
      byStatus: _board,
    );
    expect(find.byKey(const ValueKey('today_action_pay_c1')), findsNothing);
  });

  group('order detail always pushes its own route', () {
    Future<TodayFakeRepository> pumpWithRouter(
      WidgetTester tester, {
      required double width,
      required User user,
    }) async {
      _viewport(tester, width, 812);
      final repo = TodayFakeRepository(
        byStatus: _board,
        seedOrders: [todayOrderDetail('w1')],
      );
      final controller = TodayOrdersController(
        repository: repo,
        clock: () => todayNow,
        autoRefresh: null,
      );
      addTearDown(controller.dispose);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Provider<OrdersRepository>.value(
              value: repo,
              child: TodayScreen(
                controller: controller,
                user: user,
                loadSubscription: () async => null,
              ),
            ),
          ),
        ],
      );
      AppNav.attach(router);
      // Order cards open the detail by name, full-screen, with the id as the
      // argument; no `/orders/:id` route here, so the old push would throw.
      AppNav.addPages({
        AppPages.orderDetail: (_, id) => Scaffold(
          appBar: AppBar(title: Text('detail-$id')),
          body: const SizedBox(),
        ),
      });
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets(
      'Start confirms, sends IN_PROGRESS with the 30-min default, then opens '
      'the order; back returns to Today',
      (tester) async {
        final repo = await pumpWithRouter(
          tester,
          width: 1280,
          user: _user(owner: true),
        );

        await tester.tap(find.byKey(const ValueKey('today_action_start_w1')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('order_status_duration_input')),
          findsNothing,
        );
        await tester.tap(find.text('Эхлүүлэх').last);
        await tester.pumpAndSettle();

        expect(repo.updates.single, (
          id: 'w1',
          status: OrderStatus.IN_PROGRESS,
          duration: 30,
        ));
        expect(find.text('detail-w1'), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('detail-w1'), findsNothing);
        expect(find.byKey(const ValueKey('today_order_w1')), findsWidgets);
        // Let the success toast's de-duplication timer expire.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets('tablet width pushes the order detail route', (tester) async {
      final repo = await pumpWithRouter(
        tester,
        width: 1280,
        user: _user(owner: true),
      );

      await tester.tap(find.byKey(const ValueKey('today_order_w1')));
      await tester.pumpAndSettle();

      expect(find.text('detail-w1'), findsOneWidget);
      // The board is no longer on screen — this was a real route push, not
      // a side pane.
      expect(find.text('Хүлээгдэж буй'), findsNothing);
      expect(repo.queries.length, greaterThan(0));
    });

    testWidgets('phone width pushes the order detail route', (tester) async {
      await pumpWithRouter(tester, width: 375, user: _user(owner: true));

      // Phone width shows the segmented lane selector, defaulting to
      // in-progress, so switch to the waiting lane to find the card.
      await tester.tap(find.text('Хүлээгдэж 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today_order_w1')));
      await tester.pumpAndSettle();

      expect(find.text('detail-w1'), findsOneWidget);
    });

    testWidgets('reloads the board after popping back from detail', (
      tester,
    ) async {
      final repo = await pumpWithRouter(
        tester,
        width: 1280,
        user: _user(owner: true),
      );
      final loadsBefore = repo.queries.length;

      await tester.tap(find.byKey(const ValueKey('today_order_w1')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(repo.queries.length, greaterThan(loadsBefore));
      expect(find.text('Хүлээгдэж буй'), findsOneWidget);
    });
  });

  group('compact tablet (<840dp) uses the single-lane selector', () {
    testWidgets('~800dp behaves like phone: one lane at a time', (
      tester,
    ) async {
      _viewport(tester, 800, 1000);
      await _pump(tester, user: _user(owner: true), byStatus: _board);

      expect(find.byKey(const ValueKey('today_lane_selector')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('grouped board fallback when the appointments column squeezes it', () {
    AppointmentSummary appt(String id) => AppointmentSummary(
      id: id,
      status: AppointmentStatus.CONFIRMED,
      requestedAt: DateTime(2026, 9, 23, 12),
      createdAt: DateTime(2026, 9, 22, 9),
      branch: const AppointmentBranchRef(id: 'branch-1'),
      customer: const AppointmentCustomerRef(
        id: 'cust-1',
        fullName: 'Дорж',
        phone: '99001122',
      ),
      vehicle: const AppointmentVehicleRef(
        id: 'veh-1',
        plate: '5555УБА',
        make: 'Toyota',
      ),
      category: const AppointmentCategoryRef(id: 'cat-1', name: 'Засвар'),
    );

    Future<void> pump(WidgetTester tester, {required double width}) async {
      final repo = TodayFakeRepository(byStatus: _board);
      final controller = TodayOrdersController(
        repository: repo,
        clock: () => todayNow,
        autoRefresh: null,
      );
      final apptController = TodayAppointmentsController(
        repository: FakeAppointmentRepository(seed: [appt('a1')]),
        clock: () => todayNow,
        autoRefresh: null,
      );
      addTearDown(controller.dispose);
      addTearDown(apptController.dispose);
      _viewport(tester, width);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          home: TodayScreen(
            controller: controller,
            appointmentsController: apptController,
            user: _user(owner: true),
            loadSubscription: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'the appointments column squeezes the board under 840dp, so lanes '
      'stack in one grouped list instead of three side-by-side columns',
      (tester) async {
        await pump(tester, width: 1280);

        // Lane headers (and their cards) are all present either way; the
        // distinguishing detail is that `_WideBoard`'s per-lane ListViews
        // (keyed `today_lane_<name>`) are absent once lanes stack into a
        // single grouped scrollable list instead.
        expect(find.text('Хүлээгдэж буй'), findsOneWidget);
        expect(find.text('Хийгдэж буй'), findsOneWidget);
        expect(find.text('Өнөөдөр дууссан'), findsOneWidget);
        expect(
          find.byKey(const PageStorageKey('today_lane_waiting')),
          findsNothing,
        );
        expect(find.text('1111УБА'), findsOneWidget);
        expect(find.text('2222УБА'), findsOneWidget);
        expect(find.text('3333УБА'), findsOneWidget);
        expect(find.text('5555УБА'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('appointments timeline wiring (Phase 4)', () {
    AppointmentSummary appt(String id) => AppointmentSummary(
      id: id,
      status: AppointmentStatus.CONFIRMED,
      requestedAt: DateTime(2026, 9, 23, 12),
      createdAt: DateTime(2026, 9, 22, 9),
      branch: const AppointmentBranchRef(id: 'branch-1'),
      customer: const AppointmentCustomerRef(
        id: 'cust-1',
        fullName: 'Дорж',
        phone: '99001122',
      ),
      vehicle: const AppointmentVehicleRef(
        id: 'veh-1',
        plate: '5555УБА',
        make: 'Toyota',
      ),
      category: const AppointmentCategoryRef(id: 'cat-1', name: 'Засвар'),
    );

    Future<void> pump(
      WidgetTester tester, {
      required double width,
      required User user,
      List<AppointmentSummary> seed = const [],
    }) async {
      final repo = TodayFakeRepository(byStatus: _board);
      final controller = TodayOrdersController(
        repository: repo,
        clock: () => todayNow,
        autoRefresh: null,
      );
      final apptController = TodayAppointmentsController(
        repository: FakeAppointmentRepository(seed: seed),
        clock: () => todayNow,
        autoRefresh: null,
      );
      addTearDown(controller.dispose);
      addTearDown(apptController.dispose);
      _viewport(tester, width);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Provider<OrdersRepository>.value(
              value: repo,
              child: TodayScreen(
                controller: controller,
                appointmentsController: apptController,
                user: user,
                loadSubscription: () async => null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('hidden entirely without appointments.view', (tester) async {
      await pump(
        tester,
        width: 1280,
        user: _user(permissions: const ['orders.view']),
        seed: [appt('a1')],
      );
      expect(find.text('5555УБА'), findsNothing);
      expect(
        find.byKey(const ValueKey('today_section_selector')),
        findsNothing,
      );
    });

    testWidgets('tablet landscape (>=1200) shows the timeline beside lanes', (
      tester,
    ) async {
      await pump(
        tester,
        width: 1280,
        user: _user(owner: true),
        seed: [appt('a1')],
      );
      expect(find.text('Хүлээгдэж буй'), findsOneWidget);
      expect(find.text('5555УБА'), findsOneWidget);
    });

    testWidgets(
      'tablet portrait/medium (840-1200) shows a collapsible section',
      (tester) async {
        await pump(
          tester,
          width: 1000,
          user: _user(owner: true),
          seed: [appt('a1')],
        );
        expect(find.text('5555УБА'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('today_appointments_toggle')),
        );
        await tester.pumpAndSettle();
        expect(find.text('5555УБА'), findsOneWidget);
      },
    );

    testWidgets('phone shows a top-level Засварын хуудас | Цаг split', (tester) async {
      await pump(
        tester,
        width: 375,
        user: _user(owner: true),
        seed: [appt('a1')],
      );
      expect(
        find.byKey(const ValueKey('today_section_selector')),
        findsOneWidget,
      );
      expect(find.text('5555УБА'), findsNothing);

      await tester.tap(find.text('Цаг'));
      await tester.pumpAndSettle();
      expect(find.text('5555УБА'), findsOneWidget);
    });
  });

  group('large text (Phase 6)', () {
    Future<void> pumpScaled(
      WidgetTester tester,
      double width,
      double scale,
    ) async {
      _viewport(tester, width);
      final repo = TodayFakeRepository(byStatus: _board);
      final controller = TodayOrdersController(
        repository: repo,
        clock: () => todayNow,
        autoRefresh: null,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: TodayScreen(
            controller: controller,
            user: _user(owner: true),
            loadSubscription: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('2.0x on phone width renders without overflow', (tester) async {
      await pumpScaled(tester, 375, 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2.0x on tablet width renders without overflow', (
      tester,
    ) async {
      await pumpScaled(tester, 1280, 2.0);
      expect(tester.takeException(), isNull);
    });
  });
}
