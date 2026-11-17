import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/shell/app_shell.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:carservice_business/features/audit/presentation/screens/audit_list_screen.dart';
import 'package:carservice_business/features/feedback/presentation/screens/feedback_create_screen.dart';
import 'package:carservice_business/features/feedback/presentation/screens/feedback_detail_screen.dart';
import 'package:carservice_business/features/feedback/presentation/screens/feedback_list_screen.dart';
import 'package:carservice_business/features/reports/presentation/screens/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_api_backend.dart';
import '../support/app_harness.dart';
import '../support/hive_test_setup.dart';

/// `P7-F4` — the first real `GoRoute`s for `/reports`, `/audit`,
/// `/feedback`, `/feedback/new` and `/feedback/:id`, exercised through the
/// REAL `buildRouter`, the same way `test/app/people_router_test.dart`
/// exercises `/employees`/`/schedules`.
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
        role: isOwner ? null : UserRole('role-1', 'Ажилтан', permissions),
        tenant: UserTenant('test-tenant', 'Test tenant'),
      );

  Map<String, dynamic> emptyFeedbackPage() => {
    'feedback': <dynamic>[],
    'pagination': {
      'page': 1,
      'pageSize': 50,
      'total': 0,
      'totalPages': 1,
      'hasPrev': false,
      'hasNext': false,
    },
  };

  Map<String, dynamic> emptyAuditPage() => {
    'items': <dynamic>[],
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

  testWidgets('/reports resolves to the reports screen', (tester) async {
    FakeApiBackend.instance.onJson('GET', 'reports', {
      'range': <String, dynamic>{},
      'data': <String, dynamic>{},
    });
    final harness = await boot(tester);

    harness.router.go(AppRoutes.reports);
    await tester.pumpAndSettle();

    expect(harness.location, AppRoutes.reports);
    expect(find.byType(ReportsScreen), findsOneWidget);
  });

  testWidgets('/audit resolves to the audit list screen', (tester) async {
    FakeApiBackend.instance.onJson('GET', 'audit', emptyAuditPage());
    final harness = await boot(
      tester,
      user: signedInUser(isOwner: false, permissions: const ['audit.view']),
    );

    harness.router.go(AppRoutes.audit);
    await tester.pumpAndSettle();

    expect(harness.location, AppRoutes.audit);
    expect(find.byType(AuditListScreen), findsOneWidget);
  });

  testWidgets('/feedback resolves to the feedback list screen', (tester) async {
    FakeApiBackend.instance.onJson('GET', 'feedback', emptyFeedbackPage());
    final harness = await boot(tester);

    harness.router.go(AppRoutes.feedback);
    await tester.pumpAndSettle();

    expect(harness.location, AppRoutes.feedback);
    expect(find.byType(FeedbackListScreen), findsOneWidget);
  });

  testWidgets(
    "/feedback/new is not swallowed by ':id' and opens the create form",
    (tester) async {
      FakeApiBackend.instance.onJson('GET', 'feedback', emptyFeedbackPage());
      final harness = await boot(tester);

      harness.router.go('${AppRoutes.feedback}/new');
      await tester.pumpAndSettle();

      expect(harness.location, '${AppRoutes.feedback}/new');
      expect(find.byType(FeedbackCreateScreen), findsOneWidget);
    },
  );

  testWidgets('/feedback/:id opens the detail screen', (tester) async {
    FakeApiBackend.instance.onJson('GET', 'feedback/fb-1', {
      'feedback': {'id': 'fb-1', 'type': 'BUG'},
      'messages': <dynamic>[],
    });
    FakeApiBackend.instance.onJson('GET', 'feedback', emptyFeedbackPage());
    final harness = await boot(tester);

    harness.router.go('${AppRoutes.feedback}/fb-1');
    await tester.pumpAndSettle();

    expect(harness.location, '${AppRoutes.feedback}/fb-1');
    expect(find.byType(FeedbackDetailScreen), findsOneWidget);
  });

  group('More screen — Удирдлага gating', () {
    dynamic insightGroup() =>
        MoreScreen.groups.firstWhere((g) => g.label == 'Удирдлага');

    test('all three entries carry a route', () {
      final group = insightGroup();
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
          AppRoutes.reports,
          AppRoutes.audit,
          AppRoutes.feedback,
        ]),
      );
    });

    test(
      'any authenticated non-owner sees Тайлан and Санал хүсэлт but not Аудит',
      () {
        final staff = signedInUser(isOwner: false, permissions: const []);
        final visible = insightGroup().entries
            .where((e) => canSeeView(staff, e.permission))
            .toList();
        expect(
          visible.map((e) => e.label),
          containsAll(<String>['Тайлан', 'Санал хүсэлт']),
        );
        expect(visible.map((e) => e.label), isNot(contains('Аудит')));
      },
    );

    test('a non-owner with audit.view also sees Аудит', () {
      final staff = signedInUser(
        isOwner: false,
        permissions: const ['audit.view'],
      );
      final visible = insightGroup().entries
          .where((e) => canSeeView(staff, e.permission))
          .toList();
      expect(visible.map((e) => e.label), hasLength(3));
      expect(visible.map((e) => e.label), contains('Аудит'));
    });

    test('the owner sees all three entries', () {
      final owner = signedInUser(isOwner: true);
      final visible = insightGroup().entries
          .where((e) => canSeeView(owner, e.permission))
          .toList();
      expect(visible, hasLength(3));
    });
  });
}
