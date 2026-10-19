import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/today/presentation/controllers/today_orders_controller.dart';
import 'package:carservice_business/features/today/presentation/screens/today_screen.dart';
import 'package:carservice_business/features/today/presentation/widgets/today_order_card.dart';

import 'today_fixtures.dart';

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

ServiceItem _line(
  String id,
  String description,
  ServiceItemStatus status, {
  ItemKind kind = ItemKind.LABOR,
  String? reportId,
}) => ServiceItem(
  id: id,
  kind: kind,
  description: description,
  quantity: 1,
  unitPrice: 25000,
  total: 25000,
  status: status,
  diagnosticReportId: reportId,
);

const _inProgress = OrderStatus.IN_PROGRESS;

/// w1: work left, unpaid. w2: work done, unpaid. w3: work done, paid.
final _board = {
  _inProgress: [
    todayOrder(
      'w1',
      status: _inProgress,
      progress: const OrderProgressSummary(total: 4, completed: 1),
      total: '100000',
      paid: '0',
    ),
    todayOrder(
      'w2',
      status: _inProgress,
      progress: const OrderProgressSummary(total: 2, completed: 2),
      total: '100000',
      paid: '0',
    ),
    todayOrder(
      'w3',
      status: _inProgress,
      paymentStatus: PaymentStatus.PAID,
      progress: const OrderProgressSummary(total: 2, completed: 2),
      total: '100000',
      paid: '100000',
    ),
  ],
};

ServiceOrderDetail _w1({List<ServiceItem>? items}) => todayOrderDetail(
  'w1',
  status: _inProgress,
  total: '100000',
  paid: '0',
  items:
      items ??
      [
        _line('l1', 'Тос солих', ServiceItemStatus.PENDING),
        _line('l2', 'Тоормос засах', ServiceItemStatus.IN_PROGRESS),
        _line(
          'd1',
          'Хөдөлгүүрийн оношилгоо',
          ServiceItemStatus.PENDING,
          kind: ItemKind.DIAGNOSTIC,
        ),
        _line('l3', 'Дугуй тэнцүүлэх', ServiceItemStatus.COMPLETED),
      ],
);

Future<TodayFakeRepository> _pump(
  WidgetTester tester, {
  required User user,
  List<ServiceOrderDetail> details = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 2000);
  addTearDown(tester.view.reset);
  final repo = TodayFakeRepository(byStatus: _board, seedOrders: details);
  final controller = TodayOrdersController(
    repository: repo,
    clock: () => todayNow,
    autoRefresh: null,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: TodayScreen(
          controller: controller,
          user: user,
          loadSubscription: () async => null,
          sessionOpenLookup: (_) async => const Ok(true),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<List<ServiceItem>> _items(TodayFakeRepository repo, String id) async =>
    (await repo.getOrderDetail(id) as Ok<ServiceOrderDetail>).value.items;

ServiceItemStatus _status(List<ServiceItem> items, String id) =>
    items.firstWhere((item) => item.id == id).status;

void main() {
  group('card', () {
    testWidgets('finish-work label and the ⋯ button fit a narrow lane', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 190,
                child: TodayOrderCard(
                  order: _board[_inProgress]!.first,
                  now: todayNow,
                  onTap: () {},
                  action: TodayCardAction.finishWork,
                  onAction: () {},
                  onMore: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('today_action_finishWork_w1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today_more_w1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('board', () {
    testWidgets('an in-progress card offers its next step', (tester) async {
      await _pump(tester, user: _user(owner: true));
      expect(find.text('Ажлуудыг дуусгах (3)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today_action_finishWork_w1')),
        findsOneWidget,
      );
      // Work done, balance left: payment before «Дуусгах».
      expect(find.byKey(const ValueKey('today_action_pay_w2')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today_action_complete_w3')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today_more_w1')), findsOneWidget);
    });

    testWidgets('without line permission the card falls back to completing', (
      tester,
    ) async {
      await _pump(
        tester,
        user: _user(permissions: const ['orders.view', 'orders.edit']),
      );
      expect(
        find.byKey(const ValueKey('today_action_finishWork_w1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('today_action_complete_w1')),
        findsOneWidget,
      );
    });

    testWidgets(
      'finish work completes open lines, not a report-less diagnostic',
      (tester) async {
        final repo = await _pump(
          tester,
          user: _user(owner: true),
          details: [_w1()],
        );
        final before = repo.queries.length;

        await tester.tap(
          find.byKey(const ValueKey('today_action_finishWork_w1')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Бүх ажлыг дуусгах уу?'), findsOneWidget);
        expect(
          find.textContaining('1 оношилгооны мөр тайлангүй тул алгасна.'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Дуусгах'));
        await tester.pumpAndSettle();

        final items = await _items(repo, 'w1');
        expect(_status(items, 'l1'), ServiceItemStatus.COMPLETED);
        expect(_status(items, 'l2'), ServiceItemStatus.COMPLETED);
        expect(_status(items, 'd1'), ServiceItemStatus.PENDING);
        // The board reloaded (three lane queries).
        expect(repo.queries.length, before + 3);
        // Let the success toast's de-duplication timer expire.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets('only a report-less diagnostic left: offers to fill it', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        user: _user(owner: true),
        details: [
          _w1(
            items: [
              _line(
                'd1',
                'Хөдөлгүүрийн оношилгоо',
                ServiceItemStatus.PENDING,
                kind: ItemKind.DIAGNOSTIC,
              ),
              _line('l3', 'Дугуй тэнцүүлэх', ServiceItemStatus.COMPLETED),
            ],
          ),
        ],
      );

      await tester.tap(
        find.byKey(const ValueKey('today_action_finishWork_w1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Оношилгоо бөглөх шаардлагатай'), findsOneWidget);
      await tester.tap(find.text('Болих'));
      await tester.pumpAndSettle();
      expect(
        _status(await _items(repo, 'w1'), 'd1'),
        ServiceItemStatus.PENDING,
      );
    });

    testWidgets('the ⋯ sheet lists what the order still needs', (tester) async {
      await _pump(
        tester,
        user: _user(owner: true),
        details: [
          _w1(
            items: [
              _line('l1', 'Тос солих', ServiceItemStatus.PENDING),
              _line(
                'd1',
                'Хөдөлгүүрийн оношилгоо',
                ServiceItemStatus.PENDING,
                kind: ItemKind.DIAGNOSTIC,
              ),
              _line(
                'd2',
                'Явах эд анги',
                ServiceItemStatus.COMPLETED,
                kind: ItemKind.DIAGNOSTIC,
                reportId: 'r2',
              ),
            ],
          ),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('today_more_w1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today_menu_finish')), findsOneWidget);
      expect(find.text('1 мөр · 1 оношилгоо тайлангүй'), findsOneWidget);
      expect(find.byKey(const ValueKey('today_menu_diag_d1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today_menu_report_d2')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today_menu_pay')), findsOneWidget);
      expect(find.text('Үлдэгдэл 100,000₮'), findsOneWidget);
      expect(find.byKey(const ValueKey('today_menu_complete')), findsOneWidget);
      expect(find.byKey(const ValueKey('today_menu_open')), findsOneWidget);
    });

    testWidgets('the ⋯ sheet hides what the user may not do', (tester) async {
      await _pump(
        tester,
        user: _user(permissions: const ['orders.view', 'payments.view']),
        details: [_w1()],
      );

      await tester.tap(find.byKey(const ValueKey('today_more_w1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today_menu_finish')), findsNothing);
      expect(find.byKey(const ValueKey('today_menu_diag_d1')), findsNothing);
      expect(find.byKey(const ValueKey('today_menu_complete')), findsNothing);
      expect(find.byKey(const ValueKey('today_menu_pay')), findsOneWidget);
      expect(find.byKey(const ValueKey('today_menu_open')), findsOneWidget);
    });

    testWidgets('pay opens the payment screen with the record form open', (
      tester,
    ) async {
      await _pump(
        tester,
        user: _user(owner: true),
        details: [
          todayOrderDetail(
            'w2',
            status: _inProgress,
            total: '100000',
            paid: '0',
          ),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('today_action_pay_w2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay_sheet_title')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_amount_input')),
        findsOneWidget,
      );
    });
  });

  group('controller', () {
    test('completeLines completes each line, then reloads the board', () async {
      final repo = TodayFakeRepository(byStatus: _board, seedOrders: [_w1()]);
      final controller = TodayOrdersController(
        repository: repo,
        clock: () => todayNow,
        autoRefresh: null,
      );
      addTearDown(controller.dispose);
      await controller.load();
      final before = repo.queries.length;
      final order = _board[_inProgress]!.first;

      final result = await controller.completeLines(order, ['l1', 'l2']);
      expect(result.done, 2);
      expect(result.failed, 0);
      expect(controller.isBusy('w1'), isFalse);
      expect(repo.queries.length, before + 3);
      final items = await _items(repo, 'w1');
      expect(_status(items, 'l1'), ServiceItemStatus.COMPLETED);
      expect(_status(items, 'l2'), ServiceItemStatus.COMPLETED);
    });
  });
}
