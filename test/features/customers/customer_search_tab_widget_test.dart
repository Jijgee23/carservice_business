import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_list_controller.dart';
import 'package:carservice_business/features/customers/presentation/screens/customer_search_tab.dart';

import '../../fakes/fake_customer_repository.dart';

/// Widget coverage for `CustomerSearchTab` (P3-F2) at the three breakpoints
/// the tenant app supports: phone (375dp), the compact-tablet tier
/// (700dp) and full tablet (1024dp). The tab has no responsive branching of
/// its own (a single-column list at every width, matching the legacy tab),
/// so these tests mainly confirm it renders correctly and stays usable —
/// not that layout changes — at each width.
/// The tab gates its broadcast action on `customers.notify`, and
/// `PermissionGate` otherwise falls back to `Authenticator.user`, which needs
/// a live Hive box no widget test opens. Tests therefore inject a user, the
/// same way `CustomerDetailScreen`'s tests do.
User _user(List<String> permissions) => User(
  accessToken: 'token',
  refreshToken: 'refresh',
  id: 'user',
  email: 'user@example.test',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: false,
  role: UserRole('role', 'Role', permissions),
  tenant: UserTenant('tenant', 'Tenant'),
);

Future<void> _pump(
  WidgetTester tester,
  double width,
  CustomerListController controller, {
  User? user,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: CustomerSearchTab(
          controller: controller,
          user: user ?? _user(const ['customers.view', 'customers.notify']),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Customer _cust(String id, {String? fullName, String phone = '99001122'}) =>
    Customer(id: id, fullName: fullName ?? id, phone: phone);

void main() {
  for (final width in [375.0, 700.0, 1024.0]) {
    testWidgets('renders the customer list at ${width}dp', (tester) async {
      final repo = FakeCustomerRepository(
        seed: [
          _cust('c1', fullName: 'Бат'),
          _cust('c2', fullName: 'Болд', phone: '99002233'),
        ],
      );
      final controller = CustomerListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );

      await _pump(tester, width, controller);

      expect(find.text('Бат'), findsOneWidget);
      expect(find.text('Болд'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      controller.dispose();
    });

    testWidgets(
      'shows the empty state distinctly from an error at ${width}dp',
      (tester) async {
        final repo = FakeCustomerRepository(seed: const []);
        final controller = CustomerListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );

        await _pump(tester, width, controller);

        expect(find.text('Үйлчлүүлэгч алга'), findsOneWidget);
        expect(find.text('Дахин оролдох'), findsNothing);
        controller.dispose();
      },
    );
  }

  testWidgets('typing filters the list via the debounced controller', (
    tester,
  ) async {
    final repo = FakeCustomerRepository(
      seed: [
        _cust('c1', fullName: 'Бат'),
        _cust('c2', fullName: 'Болд', phone: '99002233'),
      ],
    );
    final controller = CustomerListController(
      repo: repo,
      searchDebounce: Duration.zero,
    );

    await _pump(tester, 375, controller);
    expect(find.text('Бат'), findsOneWidget);
    expect(find.text('Болд'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Болд');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Бат'), findsNothing);
    // Two matches now: the typed text in the search field and the one
    // remaining result card.
    expect(find.text('Болд'), findsNWidgets(2));
    controller.dispose();
  });
  testWidgets('cards show each fact once and mark organizations', (
    tester,
  ) async {
    final controller = CustomerListController(
      repo: FakeCustomerRepository(
        seed: const [
          Customer(id: 'walk-in', phone: '99887766'),
          Customer(
            id: 'org',
            fullName: 'Ганбаатар',
            phone: '95556677',
            isOrganization: true,
            orgName: 'Тэнгэр Тээвэр ХХК',
            orgRegnum: '6123456',
          ),
        ],
      ),
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    await _pump(tester, 375, controller);

    // A phone-only walk-in: the phone is the title, not repeated below it.
    expect(find.text('99887766'), findsOneWidget);
    expect(find.text('Нэр бүртгэгдээгүй'), findsOneWidget);

    expect(find.text('Тэнгэр Тээвэр ХХК'), findsOneWidget);
    expect(find.text('Байгууллага'), findsNWidgets(2)); // filter pill + badge
    expect(find.text('РД 6123456'), findsOneWidget);
    expect(find.text('Ганбаатар'), findsOneWidget);
    expect(find.text('95556677'), findsOneWidget);
  });

  testWidgets('broadcast action is hidden without customers.notify', (
    tester,
  ) async {
    final controller = CustomerListController(
      repo: FakeCustomerRepository(),
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    await _pump(tester, 375, controller, user: _user(const ['customers.view']));

    expect(find.byTooltip('Зар мэдээ илгээх'), findsNothing);
  });

  testWidgets('broadcast action is shown with customers.notify', (
    tester,
  ) async {
    final controller = CustomerListController(
      repo: FakeCustomerRepository(),
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      375,
      controller,
      user: _user(const ['customers.view', 'customers.notify']),
    );

    expect(find.byTooltip('Зар мэдээ илгээх'), findsOneWidget);
  });
  testWidgets('the whole surface is gated on customers.view', (tester) async {
    final controller = CustomerListController(
      repo: FakeCustomerRepository(),
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    await _pump(tester, 375, controller, user: _user(const []));

    expect(
      find.text('Танд үйлчлүүлэгчийн жагсаалт харах эрх байхгүй байна.'),
      findsOneWidget,
    );
  });
}
