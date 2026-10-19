import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/appointment_controller.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_screen.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/appointment_list_widgets.dart';

import '../../fakes/fake_appointment_repository.dart';
import '../../support/hive_test_setup.dart';
import 'package:get/get.dart';

/// Widget coverage for the Phase 5 all-appointments view: the tablet
/// sortable table at `>= AdaptiveBreakpoints.expanded` (840dp), the
/// unchanged phone card layout below it, and the app-bar filter sheet
/// (branch / open-closed / status). The appointment detail always opens as
/// its own full-screen route (no embedded two-pane split) at every width.
void main() {
  setUpAll(openTestHiveBoxes);

  User user({List<String> permissions = const ['appointments.view']}) => User(
    accessToken: 'token',
    refreshToken: 'refresh',
    id: 'user-1',
    email: 'staff@example.test',
    firstName: 'Test',
    lastName: 'Staff',
    phone: '99001122',
    isOwner: false,
    role: UserRole('role', 'role', permissions),
    tenant: UserTenant('tenant', 'Tenant'),
  );

  List<AppointmentSummary> seedAppointments() {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day, 9);
    return [
      AppointmentSummary(
        id: 'appt-1',
        status: AppointmentStatus.PENDING,
        requestedAt: base,
        branch: const AppointmentBranchRef(id: 'branch-1', name: 'Салбар 1'),
        customer: const AppointmentCustomerRef(
          id: 'cust-1',
          fullName: 'Бат',
          phone: '99001122',
        ),
        category: const AppointmentCategoryRef(id: 'cat-1', name: 'Оношилгоо'),
      ),
      AppointmentSummary(
        id: 'appt-2',
        status: AppointmentStatus.CONFIRMED,
        requestedAt: base.add(const Duration(hours: 1)),
        branch: const AppointmentBranchRef(id: 'branch-1', name: 'Салбар 1'),
        customer: const AppointmentCustomerRef(
          id: 'cust-2',
          fullName: 'Сараа',
          phone: '99003344',
        ),
        category: const AppointmentCategoryRef(id: 'cat-2', name: 'Угаалга'),
      ),
      AppointmentSummary(
        id: 'appt-3',
        status: AppointmentStatus.CANCELLED,
        requestedAt: base.add(const Duration(hours: 2)),
        branch: const AppointmentBranchRef(id: 'branch-1', name: 'Салбар 1'),
        customer: const AppointmentCustomerRef(
          id: 'cust-3',
          fullName: 'Доржоо',
          phone: '99005566',
        ),
        category: const AppointmentCategoryRef(id: 'cat-1', name: 'Оношилгоо'),
      ),
    ];
  }

  Future<AppointmentController> pump(
    WidgetTester tester,
    double width, {
    List<AppointmentSummary>? seed,
  }) async {
    Authenticator.user = user();
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeAppointmentRepository(seed: seed ?? seedAppointments());
    final controller = AppointmentController(repo: repo);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light,
        home: ChangeNotifierProvider.value(
          value: controller,
          child: AppointmentScreen(user: user()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    return controller;
  }

  testWidgets('tablet width (>=840dp) renders the sortable table', (
    tester,
  ) async {
    await pump(tester, 1024);

    // Table header renders the record columns, not phone cards. The
    // default every-date list shows the full date in its first column.
    expect(find.text('Огноо'), findsOneWidget);
    expect(find.text('Үйлчлүүлэгч'), findsOneWidget);
    expect(find.text('Бат'), findsOneWidget);
    expect(find.text('Сараа'), findsOneWidget);
    expect(find.byType(AppointmentPhoneCard), findsNothing);

    // No embedded detail pane at any width: the table takes the full body.
    expect(find.text('Дэлгэрэнгүй харахын тулд мөр сонгоно уу'), findsNothing);
  });

  testWidgets('tablet row tap pushes the full-screen detail route', (
    tester,
  ) async {
    await pump(tester, 1024);

    // Tapping a row pushes the same full-screen detail route phones use —
    // the table is no longer in the tree, replaced by the detail app bar.
    await tester.tap(find.text('Бат'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Цаг захиалгын дэлгэрэнгүй'), findsOneWidget);
    // No embedded-pane close affordance — this is a real route with the
    // platform's normal back navigation.
    expect(
      find.byKey(const ValueKey('appointment_detail_close_button')),
      findsNothing,
    );
    expect(find.byType(BackButton), findsOneWidget);

    // Popping the route returns to the table and refreshes the list.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Цаг захиалгын дэлгэрэнгүй'), findsNothing);
    expect(find.text('Бат'), findsOneWidget);
  });

  testWidgets('phone width (<600dp) keeps the card list', (tester) async {
    await pump(tester, 400);

    expect(find.byType(AppointmentPhoneCard), findsWidgets);
    // The tablet table header is not rendered on phone.
    expect(find.text('Дэлгэрэнгүй харахын тулд мөр сонгоно уу'), findsNothing);
  });

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('appointments_filter_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> applyFilters(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('appointment_filter_apply')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('app bar offers a filter button, not a refresh button', (
    tester,
  ) async {
    await pump(tester, 400);

    expect(find.byTooltip('Шинэчлэх'), findsNothing);
    expect(find.byTooltip('Шүүлтүүр'), findsOneWidget);
    // The inline status/quick-filter rows moved into the sheet.
    expect(find.text('Нээлттэй'), findsNothing);

    await openFilters(tester);

    expect(find.text('Нээлттэй / Хаагдсан'), findsOneWidget);
    expect(find.text('Төлөв'), findsOneWidget);
    // Branch filtering is owner-only; this user is staff.
    expect(find.text('Салбар'), findsNothing);
  });

  testWidgets('Нээлттэй in the sheet merges PENDING+CONFIRMED and excludes '
      'CANCELLED', (tester) async {
    final controller = await pump(tester, 1024);

    await openFilters(tester);
    await tester.tap(find.text('Нээлттэй'));
    await tester.pump();
    await applyFilters(tester);

    expect(controller.statusGroup, {
      AppointmentStatus.PENDING,
      AppointmentStatus.CONFIRMED,
    });
    expect(find.text('Бат'), findsOneWidget);
    expect(find.text('Сараа'), findsOneWidget);
    expect(find.text('Доржоо'), findsNothing);

    // Clearing everything in the sheet restores the full list.
    await openFilters(tester);
    await tester.tap(find.text('Бүгдийг арилгах'));
    await tester.pump();
    await applyFilters(tester);
    expect(controller.statusGroup, isNull);
    expect(find.text('Доржоо'), findsOneWidget);
  });

  testWidgets('Хаагдсан narrows the status options to closed statuses', (
    tester,
  ) async {
    final controller = await pump(tester, 1024);

    await openFilters(tester);
    expect(find.text(AppointmentStatus.PENDING.label), findsWidgets);
    await tester.tap(find.text('Хаагдсан'));
    await tester.pump();

    // Open statuses are no longer offered in the sheet's status section.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(AppointmentStatus.PENDING.label),
      ),
      findsNothing,
    );
    await tester.tap(find.text(AppointmentStatus.CANCELLED.label).last);
    await tester.pump();
    await applyFilters(tester);

    // A single status wins over the group it narrows.
    expect(controller.statusFilter, AppointmentStatus.CANCELLED);
    expect(controller.statusGroup, isNull);
    expect(find.text('Доржоо'), findsOneWidget);
    expect(find.text('Бат'), findsNothing);
  });

  testWidgets('large text (2.0x) on phone width renders without overflow', (
    tester,
  ) async {
    Authenticator.user = user();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeAppointmentRepository(seed: seedAppointments());
    final controller = AppointmentController(repo: repo);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: ChangeNotifierProvider.value(
          value: controller,
          child: AppointmentScreen(user: user()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(tester.takeException(), isNull);
  });

  testWidgets('large text (1.5x) on tablet width renders without overflow', (
    tester,
  ) async {
    Authenticator.user = user();
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeAppointmentRepository(seed: seedAppointments());
    final controller = AppointmentController(repo: repo);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: ChangeNotifierProvider.value(
          value: controller,
          child: AppointmentScreen(user: user()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(tester.takeException(), isNull);
  });

  testWidgets('defaults to every date; Өнөөдөр and Бүгд switch the day view', (
    tester,
  ) async {
    final controller = await pump(tester, 390);
    final today = DateTime.now();

    expect(controller.allDates, isTrue);
    expect(find.text('Бүх цаг захиалга'), findsOneWidget);
    // The list spans many days, so each card carries its day.
    expect(find.text(DateFormat('MM/dd').format(today)), findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey('appointments_today_chip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(controller.allDates, isFalse);
    expect(find.text(DateFormat('yyyy/MM/dd').format(today)), findsOneWidget);
    expect(find.text(DateFormat('MM/dd').format(today)), findsNothing);

    await tester.tap(find.byKey(const ValueKey('appointments_all_dates_chip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(controller.allDates, isTrue);
    expect(find.text('Бүх цаг захиалга'), findsOneWidget);
  });
}
