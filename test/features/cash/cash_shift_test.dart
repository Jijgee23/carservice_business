import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/features/cash/data/cash_shift_dto.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';
import 'package:carservice_business/features/cash/presentation/controllers/cash_shift_list_controller.dart';
import 'package:carservice_business/features/cash/presentation/screens/cash_shift_detail_screen.dart';
import 'package:carservice_business/features/cash/presentation/screens/cash_shift_list_screen.dart';
import 'package:carservice_business/features/orders/presentation/widgets/no_cash_session_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fake_cash_shift_repository.dart';

User user(List<String> permissions, {bool isOwner = false}) => User(
  accessToken: 't',
  refreshToken: 'r',
  id: 'u',
  email: 'u@example.test',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: isOwner,
  branchId: 'b-1',
  role: UserRole('role', 'Role', permissions),
  tenant: UserTenant('tenant', 'Tenant'),
);

final manager = user(const ['cash.manage']);

Future<void> pump(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(GetMaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

void main() {
  group('parsing', () {
    test('parses a session payload with breakdown', () {
      final s = parseCashShift({
        'id': 'sh-1',
        'status': 'OPEN',
        'branch': {'id': 'b-1', 'name': 'Төв'},
        'openedAt': '2026-11-11T01:30:00.000Z',
        'openedBy': {'id': 'u-1', 'name': 'Бат'},
        'openingCash': '50000',
        'closedAt': null,
        'closedBy': null,
        'countedCash': null,
        'expectedCash': '120000',
        'difference': null,
        'note': null,
        'cashIn': '80000',
        'cashOut': '10000',
        'entryCount': 3,
        'totalEntryCount': 4,
        'byMethod': [
          {
            'method': 'CARD',
            'bank': 'acc',
            'bankLabel': 'POS',
            'income': '40000',
            'expense': '0',
            'net': '40000',
            'count': 1,
            'expected': '40000',
            'counted': null,
            'difference': null,
          },
        ],
      });
      expect(s.isOpen, isTrue);
      expect(s.branch.name, 'Төв');
      expect(s.expectedCash, '120000');
      expect(s.byMethod.single.bankLabel, 'POS');
      expect(s.totalEntryCount, 4);
    });

    test('parses current (none) and the paged list', () {
      expect(
        parseCurrentCashShift({'branchId': 'b-1', 'session': null}).shift,
        isNull,
      );
      final page = parseCashShiftPage({
        'sessions': [],
        'pagination': {
          'page': 1,
          'pageSize': 30,
          'total': 0,
          'totalPages': 1,
          'hasPrev': false,
          'hasNext': false,
        },
      }, pageSize: 30);
      expect(page.items, isEmpty);
      expect(page.pagination.hasNext, isFalse);
    });

    test('cashDifference works on cents with a sign', () {
      expect(cashDifference('115,000', '120000'), '-5000');
      expect(cashDifference('120000.5', '120000'), '0.50');
      expect(cashDifference('99.75', '100'), '-0.25');
      expect(cashDifference('', '100'), isNull);
    });
  });

  group('CashShiftListController', () {
    test('pinned working branch scopes the current shift', () async {
      final repo = FakeCashShiftRepository(current: shift());
      final c = CashShiftListController(
        repo: repo,
        branchRepo: FakeWorkingBranchRepository(),
        store: MemoryBranchStore('b-2'),
      );
      await c.load();
      expect(c.pinnedBranchId, 'b-2');
      expect(c.canPickBranch, isFalse);
      expect(repo.currentBranches, ['b-2']);
      // The server scopes by header; no branchId filter is sent.
      expect(repo.listQueries.single.branchId, isNull);
      expect(c.currentState?.valueOrNull?.id, 'sh-1');
    });

    test('«all» scope: no current card until a branch is picked', () async {
      final repo = FakeCashShiftRepository(
        shifts: [shift(), shift(id: 'sh-2', branchId: 'b-2', open: false)],
      );
      final c = CashShiftListController(
        repo: repo,
        branchRepo: FakeWorkingBranchRepository(),
        store: MemoryBranchStore('ALL'),
      );
      await c.load();
      expect(c.canPickBranch, isTrue);
      expect(c.currentState, isNull);
      expect(c.listState.valueOrNull, hasLength(2));

      await c.setBranch('b-2');
      expect(repo.listQueries.last.branchId, 'b-2');
      expect(repo.currentBranches, ['b-2']);
      expect(c.listState.valueOrNull?.single.id, 'sh-2');

      await c.setStatus('OPEN');
      expect(repo.listQueries.last.status, 'OPEN');
      expect(c.listState.valueOrNull, isEmpty);
    });
  });

  group('CashShiftListScreen', () {
    testWidgets('without cash.manage shows the lock state', (tester) async {
      await pump(
        tester,
        CashShiftListScreen(
          repository: FakeCashShiftRepository(),
          branchRepository: FakeWorkingBranchRepository(),
          branchStore: MemoryBranchStore('b-1'),
          user: user(const ['payments.create']),
        ),
      );
      expect(
        find.text('Танд кассыг удирдах эрх байхгүй байна.'),
        findsOneWidget,
      );
    });

    testWidgets('opens a shift from the empty current card', (tester) async {
      final repo = FakeCashShiftRepository();
      await pump(
        tester,
        CashShiftListScreen(
          repository: repo,
          branchRepository: FakeWorkingBranchRepository(),
          branchStore: MemoryBranchStore('b-1'),
          user: manager,
        ),
      );
      expect(find.byKey(const ValueKey('cash_shift_none_open')), findsOneWidget);
      expect(find.byKey(const ValueKey('cash_shift_empty')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cash_shift_open_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open_cash_shift_sheet')), findsOneWidget);
      // Branch fixed by the pinned scope: no picker.
      expect(find.byKey(const ValueKey('open_shift_branch')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('open_shift_amount')),
        '50000',
      );
      await tester.tap(find.byKey(const ValueKey('open_shift_submit')));
      await tester.pumpAndSettle();

      expect(repo.opened.single.$1, 'b-1');
      expect(repo.opened.single.$2, '50000');
      expect(find.byKey(const ValueKey('open_cash_shift_sheet')), findsNothing);
      expect(find.byKey(const ValueKey('cash_shift_current')), findsOneWidget);
      // Let the success toast's dedupe timer run out.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('server error stays in the open sheet', (tester) async {
      final repo = FakeCashShiftRepository()
        ..openError = const AppError(
          ErrorKind.unknown,
          'Энэ салбарт касс аль хэдийн нээгдсэн байна.',
          statusCode: 409,
          code: 'CASH_SESSION_ALREADY_OPEN',
        );
      await pump(
        tester,
        CashShiftListScreen(
          repository: repo,
          branchRepository: FakeWorkingBranchRepository(),
          branchStore: MemoryBranchStore('b-1'),
          user: manager,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cash_shift_open_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open_shift_submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('Энэ салбарт касс аль хэдийн нээгдсэн байна.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('open_cash_shift_sheet')), findsOneWidget);
    });

    testWidgets('close flow shows the live difference and submits', (
      tester,
    ) async {
      final repo = FakeCashShiftRepository(
        current: shift(),
        shifts: [shift()],
      );
      await pump(
        tester,
        CashShiftListScreen(
          repository: repo,
          branchRepository: FakeWorkingBranchRepository(),
          branchStore: MemoryBranchStore('b-1'),
          user: manager,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cash_shift_close_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('close_cash_shift_sheet')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('close_shift_expected')),
          matching: find.text('120,000₮'),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('close_shift_counted')),
        '115000',
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('close_shift_difference')),
          matching: find.text('-5,000₮'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('close_shift_submit')));
      await tester.pumpAndSettle();
      expect(repo.closed.single, ('sh-1', '115000', ''));
      expect(find.byKey(const ValueKey('cash_shift_none_open')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('close requires the counted amount', (tester) async {
      final repo = FakeCashShiftRepository(current: shift());
      await pump(
        tester,
        CashShiftListScreen(
          repository: repo,
          branchRepository: FakeWorkingBranchRepository(),
          branchStore: MemoryBranchStore('b-1'),
          user: manager,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cash_shift_close_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('close_shift_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Тоолсон дүнг оруулна уу.'), findsOneWidget);
      expect(repo.closed, isEmpty);
    });
  });

  testWidgets('detail shows figures, breakdown and entries', (tester) async {
    final repo = FakeCashShiftRepository(
      shifts: [shift(open: false, countedCash: '115000', difference: '-5000')],
    );
    await pump(
      tester,
      CashShiftDetailScreen(shiftId: 'sh-1', repository: repo, user: manager),
    );
    expect(find.byKey(const ValueKey('cash_shift_detail_header')), findsOneWidget);
    expect(find.text('Хаагдсан'), findsOneWidget);
    expect(find.text('-5,000₮'), findsOneWidget);
    expect(find.text('Засварын төлбөр'), findsOneWidget);
    expect(find.textContaining('Хаан POS'), findsOneWidget);
    // Closed: no close action.
    expect(find.byKey(const ValueKey('cash_shift_detail_close')), findsNothing);
  });

  group('NoCashSessionWarning', () {
    Widget host(Widget child) =>
        Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child));

    testWidgets('no «Ээлж нээх» without cash.manage', (tester) async {
      await pump(
        tester,
        host(
          NoCashSessionWarning(
            branchId: 'b-1',
            user: user(const ['payments.create']),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('no_cash_session_warning')), findsOneWidget);
      expect(find.byKey(const ValueKey('no_cash_session_open')), findsNothing);
    });

    testWidgets('no «Ээлж нээх» without a branch', (tester) async {
      await pump(tester, host(NoCashSessionWarning(user: manager)));
      expect(find.byKey(const ValueKey('no_cash_session_open')), findsNothing);
    });

    testWidgets('opens the shift for the branch and refreshes the flag', (
      tester,
    ) async {
      final repo = FakeCashShiftRepository();
      var refreshed = 0;
      await pump(
        tester,
        host(
          NoCashSessionWarning(
            branchId: 'b-9',
            user: manager,
            repository: repo,
            onOpened: () async => refreshed++,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('no_cash_session_open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('open_shift_amount')),
        '0',
      );
      await tester.tap(find.byKey(const ValueKey('open_shift_submit')));
      await tester.pumpAndSettle();
      expect(repo.opened.single.$1, 'b-9');
      expect(refreshed, 1);
    });

    testWidgets('dismissing the sheet does not refresh', (tester) async {
      var refreshed = 0;
      await pump(
        tester,
        host(
          NoCashSessionWarning(
            branchId: 'b-1',
            user: user(const [], isOwner: true),
            repository: FakeCashShiftRepository(),
            onOpened: () async => refreshed++,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('no_cash_session_open')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(refreshed, 0);
    });
  });
}
