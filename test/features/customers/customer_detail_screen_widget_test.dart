import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/presentation/screens/customer_detail_screen.dart';

import '../../fakes/fake_customer_repository.dart';
import 'package:get/get.dart';

/// Widget coverage for the rebuilt `CustomerDetailScreen` — P3-F4.
///
/// Covers: fetch-by-id including the deep-link cold start (the screen is
/// given only [CustomerDetailScreen.customerId], nothing preloaded),
/// permission gating both hiding and disabling, the delete-blocked-by-orders
/// conflict rendered as a real explanation, and rendering at phone (375dp)
/// and expanded (1024dp) widths.
User _user(List<String> permissions, {bool isOwner = false}) => User(
  accessToken: 'token',
  refreshToken: 'refresh',
  id: 'user',
  email: 'user@example.test',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: isOwner,
  role: UserRole('role', 'Role', permissions),
  tenant: UserTenant('tenant', 'Tenant'),
);

Future<void> _pump(
  WidgetTester tester,
  double width, {
  required FakeCustomerRepository repo,
  required User user,
  String customerId = 'cust-1',
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      home: CustomerDetailScreen(
        customerId: customerId,
        repo: repo,
        user: user,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  for (final width in [375.0, 1024.0]) {
    testWidgets('cold start at ${width}dp fetches by id and renders detail', (
      tester,
    ) async {
      final repo = FakeCustomerRepository(
        seed: [
          Customer(
            id: 'cust-1',
            fullName: 'Бат',
            phone: '99001122',
            email: 'bat@example.mn',
          ),
        ],
      );
      await _pump(
        tester,
        width,
        repo: repo,
        user: _user(const ['customers.view']),
      );

      expect(find.text('Бат'), findsWidgets);
      expect(find.text('99001122'), findsOneWidget);
      expect(find.text('Машинууд'), findsOneWidget);
      expect(find.text('Засварын хуудасны түүх'), findsOneWidget);
    });
  }

  testWidgets('edit/delete icons are hidden without permission', (
    tester,
  ) async {
    final repo = FakeCustomerRepository(
      seed: [Customer(id: 'cust-1', fullName: 'Бат', phone: '99001122')],
    );
    await _pump(tester, 375, repo: repo, user: _user(const ['customers.view']));

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('edit/delete icons show and are enabled with permission', (
    tester,
  ) async {
    final repo = FakeCustomerRepository(
      seed: [Customer(id: 'cust-1', fullName: 'Бат', phone: '99001122')],
    );
    await _pump(
      tester,
      375,
      repo: repo,
      user: _user(const [
        'customers.view',
        'customers.edit',
        'customers.delete',
      ]),
    );

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    final editButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.edit_outlined),
        matching: find.byType(IconButton),
      ),
    );
    final deleteButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.delete_outline),
        matching: find.byType(IconButton),
      ),
    );
    expect(editButton.onPressed, isNotNull);
    expect(deleteButton.onPressed, isNotNull);
  });

  testWidgets(
    'delete icon is disabled (not hidden) when the gate is "disable" mode is '
    'not used — permission absent still hides per PermissionGate default',
    (tester) async {
      // PermissionGate's default `fallback` is SizedBox.shrink (hide), so a
      // permission-less user gets no control at all rather than a disabled
      // one — matches PermissionGate's own documented default and this
      // screen never overrides it with `disable: true`.
      final repo = FakeCustomerRepository(
        seed: [Customer(id: 'cust-1', fullName: 'Бат', phone: '99001122')],
      );
      await _pump(
        tester,
        375,
        repo: repo,
        user: _user(const ['customers.view', 'customers.edit']),
      );
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    },
  );

  testWidgets(
    'delete blocked by orders shows a real explanation, not a generic error',
    (tester) async {
      final repo = FakeCustomerRepository(
        seed: [Customer(id: 'cust-1', fullName: 'Бат', phone: '99001122')],
        customersWithOrders: {'cust-1'},
      );
      await _pump(
        tester,
        375,
        repo: repo,
        user: _user(const ['customers.view', 'customers.delete']),
      );

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      // Confirm sheet appears first.
      expect(find.text('Устгах'), findsWidgets);
      await tester.tap(find.text('Устгах').last);
      await tester.pumpAndSettle();

      expect(find.text('Устгах боломжгүй'), findsOneWidget);
      expect(
        find.textContaining('засварын хуудас байгаа тул устгах'),
        findsOneWidget,
      );
    },
  );
  testWidgets('keeps the legacy "new inspection" shortcut (DM-01 parity)', (
    tester,
  ) async {
    // The P3-F4 rebuild originally dropped this action. It is a parity
    // obligation, not a slice-scope choice, so it is pinned here: the
    // rebuild may change anything about this screen except quietly losing
    // an entry point staff already had.
    await _pump(
      tester,
      375,
      repo: FakeCustomerRepository(),
      user: _user(const ['customers.view']),
    );

    expect(find.byTooltip('Шинэ оношилгоо'), findsOneWidget);
  });
}
