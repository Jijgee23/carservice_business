import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/shell/app_shell.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:carservice_business/features/employees/presentation/screens/employee_bulk_screen.dart';
import 'package:carservice_business/features/employees/presentation/screens/employee_detail_screen.dart';
import 'package:carservice_business/features/employees/presentation/screens/employee_form_screen.dart';
import 'package:carservice_business/features/employees/presentation/screens/employee_list_screen.dart';
import 'package:carservice_business/features/schedules/presentation/screens/my_schedule_screen.dart';
import 'package:carservice_business/features/schedules/presentation/screens/schedule_grid_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_api_backend.dart';
import '../support/app_harness.dart';
import '../support/hive_test_setup.dart';

/// `P6-F5` — the first real `GoRoute`s for Employees/Roles/Schedules
/// ("Хүмүүс"), exercised through the REAL `buildRouter`, the same way
/// `test/app/services_router_test.dart` exercises `/services`.
///
/// `EmployeeFormScreen._loadOptions`/`BranchService.getBranches` swallow
/// their own request failures into an empty list/`Err` (see
/// `employee_form_screen.dart`/`branch_service.dart`), so these tests never
/// script `roles`/`branches` — `FakeApiBackend`'s "unscripted request fails
/// fast" default is caught by those call sites, not left to surface here.
void main() {
  setUpAll(openTestHiveBoxes);

  setUp(() {
    FakeApiBackend.instance.reset();
    SubscriptionService.instance.invalidate();
  });

  User signedInUser({bool isOwner = true, List<String> permissions = const []}) =>
      User(
        accessToken: 'test-token',
        refreshToken: 'test-refresh',
        id: 'test-user',
        email: 'test@example.com',
        firstName: 'Test',
        lastName: 'User',
        phone: '',
        isOwner: isOwner,
        role: isOwner
            ? null
            : UserRole('role-1', 'Ажилтан', permissions),
        tenant: UserTenant('test-tenant', 'Test tenant'),
      );

  Map<String, dynamic> emptyEmployeePage() => {
    'employees': <dynamic>[],
    'pagination': {
      'page': 1,
      'pageSize': 50,
      'total': 0,
      'totalPages': 1,
      'hasPrev': false,
      'hasNext': false,
    },
  };

  Future<RouterHarness> boot(WidgetTester tester, {User? user}) async {
    Authenticator.user = user ?? signedInUser();
    addTearDown(() => Authenticator.user = null);
    final harness = RouterHarness();
    addTearDown(harness.dispose);
    harness.authController.setAuthState(AuthState.authorized);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    return harness;
  }

  group('employees', () {
    testWidgets('/employees resolves to the list screen', (tester) async {
      FakeApiBackend.instance.onJson('GET', 'employees', emptyEmployeePage());
      final harness = await boot(tester);

      harness.router.go('/employees');
      await tester.pumpAndSettle();

      expect(harness.location, '/employees');
      expect(find.byType(EmployeeListScreen), findsOneWidget);
    });

    testWidgets(
      "/employees/new is not swallowed by ':id' and opens the create form",
      (tester) async {
        FakeApiBackend.instance.onJson(
          'GET',
          'employees',
          emptyEmployeePage(),
        );
        final harness = await boot(tester);

        harness.router.go('/employees/new');
        await tester.pumpAndSettle();

        expect(harness.location, '/employees/new');
        expect(find.byType(EmployeeFormScreen), findsOneWidget);
        expect(find.text('Шинэ ажилтан'), findsOneWidget);
      },
    );

    testWidgets(
      "/employees/bulk is not swallowed by ':id' and opens the bulk screen",
      (tester) async {
        FakeApiBackend.instance.onJson(
          'GET',
          'employees',
          emptyEmployeePage(),
        );
        final harness = await boot(tester);

        harness.router.go('/employees/bulk');
        await tester.pumpAndSettle();

        expect(harness.location, '/employees/bulk');
        expect(find.byType(EmployeeBulkScreen), findsOneWidget);
      },
    );

    testWidgets('/employees/:id opens the detail screen', (tester) async {
      FakeApiBackend.instance.onJson('GET', 'employees/emp-1', {
        'employee': {
          'id': 'emp-1',
          'firstName': 'Бат',
          'lastName': 'Дорж',
          'isActive': true,
        },
      });
      FakeApiBackend.instance.onJson('GET', 'employees', emptyEmployeePage());
      final harness = await boot(tester);

      harness.router.go('/employees/emp-1');
      await tester.pumpAndSettle();

      expect(harness.location, '/employees/emp-1');
      expect(find.byType(EmployeeDetailScreen), findsOneWidget);
    });

    testWidgets(
      '/employees/:id/edit fetches the employee then opens the form',
      (tester) async {
        FakeApiBackend.instance.onJson('GET', 'employees/emp-1', {
          'employee': {
            'id': 'emp-1',
            'firstName': 'Бат',
            'lastName': 'Дорж',
            'isActive': true,
          },
        });
        FakeApiBackend.instance.onJson(
          'GET',
          'employees',
          emptyEmployeePage(),
        );
        final harness = await boot(tester);

        harness.router.go('/employees/emp-1/edit');
        await tester.pumpAndSettle();

        expect(harness.location, '/employees/emp-1/edit');
        expect(find.byType(EmployeeFormScreen), findsOneWidget);
        expect(find.text('Ажилтан засах'), findsOneWidget);
      },
    );
  });

  group('schedules', () {
    testWidgets('/schedules resolves to the schedule grid', (tester) async {
      final harness = await boot(tester);

      harness.router.go('/schedules');
      await tester.pumpAndSettle();

      expect(harness.location, '/schedules');
      expect(find.byType(ScheduleGridScreen), findsOneWidget);
    });

    testWidgets('/my-schedule resolves to the my-schedule screen', (
      tester,
    ) async {
      final harness = await boot(tester);

      harness.router.go('/my-schedule');
      await tester.pumpAndSettle();

      expect(harness.location, '/my-schedule');
      expect(find.byType(MyScheduleScreen), findsOneWidget);
    });
  });

  group('More screen — Хүмүүс gating', () {
    _NavigationGroupLike peopleGroup() =>
        MoreScreen.groups.firstWhere((g) => g.label == 'Ажилтан');

    test('all three entries carry a route (roles are system-managed)', () {
      final group = peopleGroup();
      expect(group.entries, hasLength(3));
      for (final entry in group.entries) {
        expect(
          entry.route,
          isNotNull,
          reason: '${entry.label} should have a route wired',
        );
      }
      expect(
        group.entries.map((e) => e.route),
        containsAll(<String>[
          AppRoutes.employees,
          AppRoutes.schedules,
          AppRoutes.mySchedule,
        ]),
      );
    });

    test('owner sees all three entries', () {
      final owner = signedInUser(isOwner: true);
      final visible = peopleGroup().entries
          .where((e) => canSeeView(owner, e.permission))
          .toList();
      expect(visible, hasLength(3));
    });

    test(
      'non-owner without employees.view only sees "Миний хуваарь"',
      () {
        final staff = signedInUser(isOwner: false, permissions: const []);
        final visible = peopleGroup().entries
            .where((e) => canSeeView(staff, e.permission))
            .toList();
        expect(visible.map((e) => e.label), ['Миний хуваарь']);
      },
    );

    test(
      'non-owner with employees.view sees employees/schedule but not roles',
      () {
        final staff = signedInUser(
          isOwner: false,
          permissions: const ['employees.view'],
        );
        final visible = peopleGroup().entries
            .where((e) => canSeeView(staff, e.permission))
            .toList();
        expect(
          visible.map((e) => e.label),
          containsAll(<String>['Ажилтнууд', 'Ажлын хуваарь', 'Миний хуваарь']),
        );
        expect(visible.map((e) => e.label), isNot(contains('Эрхүүд')));
      },
    );
  });
}

/// Structural mirror of `app_shell.dart`'s private `_NavigationGroup` — this
/// test file cannot reference the private type directly across the library
/// boundary, so it types `MoreScreen.groups`' element via `dynamic` access
/// through this typedef-free helper instead. `MoreScreen.groups` itself is
/// public (`static const`), so its runtime type is accessible even though
/// its declared element type is private to `app_shell.dart`.
typedef _NavigationGroupLike = dynamic;
