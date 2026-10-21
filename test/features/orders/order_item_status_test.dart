import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_controller.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_detail_controller.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_item_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_detail_screen.dart';
import 'package:carservice_business/features/orders/presentation/widgets/detail/order_item_widgets.dart';

import '../../fakes/fake_order_repository.dart';

const _orderId = 'order-lines';

ServiceItem _line(
  String id,
  String description,
  ServiceItemStatus status, {
  ItemKind kind = ItemKind.LABOR,
}) => ServiceItem(
  id: id,
  kind: kind,
  description: description,
  quantity: 1,
  unitPrice: 1000,
  total: 1000,
  status: status,
);

ServiceOrderDetail _order(OrderStatus status) => ServiceOrderDetail(
  id: _orderId,
  number: 'A-0002',
  status: status,
  paymentStatus: PaymentStatus.UNPAID,
  createdAt: DateTime(2026, 1, 9),
  customer: const CustomerSummary(
    id: 'cust-1',
    fullName: 'Бат',
    phone: '99001122',
  ),
  vehicle: const VehicleSummary(
    id: 'veh-1',
    plate: '1234ABC',
    make: 'Toyota',
    model: 'Prius',
  ),
  branch: const BranchSummary(id: 'branch-1', name: 'Толгойт салбар'),
  items: [
    _line('l1', 'Тос солих', ServiceItemStatus.PENDING),
    _line('l2', 'Тоормос засах', ServiceItemStatus.IN_PROGRESS),
    _line(
      'd1',
      'Хөдөлгүүрийн оношилгоо',
      ServiceItemStatus.PENDING,
      kind: ItemKind.DIAGNOSTIC,
    ),
    _line(
      'p1',
      'Тосны шүүлтүүр',
      ServiceItemStatus.PENDING,
      kind: ItemKind.PART,
    ),
    _line('l3', 'Дугуй тэнцүүлэх', ServiceItemStatus.COMPLETED),
  ],
  reports: const [],
);

class _StatusRepository extends FakeOrderRepository {
  _StatusRepository(OrderStatus status) : super(seedOrders: [_order(status)]);

  /// While set, line status requests wait for it.
  Completer<void>? gate;
  final Set<String> refuse = {};
  final List<String> statusCalls = [];
  int detailReads = 0;

  @override
  Future<Result<ServiceOrderDetail>> getOrderDetail(String id) {
    detailReads++;
    return super.getOrderDetail(id);
  }

  @override
  Future<Result<ServiceItem>> changeItemStatus(
    String orderId,
    String itemId,
    ServiceItemStatus status,
  ) async {
    statusCalls.add('$itemId:${status.name}');
    if (gate case final gate?) await gate.future;
    if (refuse.contains(itemId)) {
      return Err(AppError(ErrorKind.server, 'refused $itemId'));
    }
    return super.changeItemStatus(orderId, itemId, status);
  }
}

ServiceItemStatus? _statusOf(OrderDetailController detail, String id) =>
    detail.order?.items.firstWhere((item) => item.id == id).status;

User _user() => User(
  accessToken: 'token',
  refreshToken: 'refresh',
  id: 'user',
  email: 'user@example.test',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: false,
  role: UserRole('role', 'role', const [
    'orders.view',
    'orders.edit',
    'orders.itemStatus',
  ]),
  tenant: UserTenant('tenant', 'Tenant'),
);

Future<OrderDetailController> _pumpScreen(
  WidgetTester tester,
  _StatusRepository repo,
) async {
  tester.binding.window.physicalSizeTestValue = const Size(375, 2400);
  tester.binding.window.devicePixelRatioTestValue = 1;
  addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
  addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);
  final detail = OrderDetailController(repo: repo);
  final legacy = OrderController(repo: repo);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: detail),
          ChangeNotifierProvider.value(value: legacy),
        ],
        child: OrderDetailScreen(orderId: _orderId, user: _user()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() {
    detail.dispose();
    legacy.dispose();
  });
  return detail;
}

Finder _inLine(String description, Finder matching) => find.descendant(
  of: find.ancestor(
    of: find.text(description),
    matching: find.byType(OrderItemCard),
  ),
  matching: matching,
);

void main() {
  group('OrderItemController line status', () {
    late _StatusRepository repo;
    late OrderDetailController detail;
    late OrderItemController items;

    setUp(() async {
      repo = _StatusRepository(OrderStatus.IN_PROGRESS);
      detail = OrderDetailController(repo: repo);
      await detail.load(_orderId);
      items = OrderItemController(
        repo: repo,
        orderId: _orderId,
        detailController: detail,
      );
    });

    tearDown(() {
      items.dispose();
      detail.dispose();
    });

    test('shows the target at once and drops it after the reload', () async {
      repo.gate = Completer<void>();
      final change = items.changeStatus('l1', ServiceItemStatus.COMPLETED);

      expect(items.pendingStatusOf('l1'), ServiceItemStatus.COMPLETED);
      expect(items.isStatusBusy('l1'), isTrue);
      final duplicate = await items.changeStatus(
        'l1',
        ServiceItemStatus.IN_PROGRESS,
      );
      expect(duplicate, isA<Err<ServiceItem>>());

      repo.gate!.complete();
      expect(await change, isA<Ok<ServiceItem>>());
      expect(repo.statusCalls, ['l1:COMPLETED']);
      expect(items.pendingStatusOf('l1'), isNull);
      expect(_statusOf(detail, 'l1'), ServiceItemStatus.COMPLETED);
    });

    test('a refused change falls back to the server status', () async {
      repo.refuse.add('l1');
      final result = await items.changeStatus(
        'l1',
        ServiceItemStatus.COMPLETED,
      );

      expect(result, isA<Err<ServiceItem>>());
      expect(items.pendingStatusOf('l1'), isNull);
      expect(_statusOf(detail, 'l1'), ServiceItemStatus.PENDING);
    });

    test('completeAll sends one request per line and reloads once', () async {
      final readsBefore = repo.detailReads;
      final result = await items.completeAll(['l1', 'l2']);

      expect(repo.statusCalls, ['l1:COMPLETED', 'l2:COMPLETED']);
      expect(repo.detailReads - readsBefore, 1);
      expect(result.done, 2);
      expect(result.failed, 0);
      expect(_statusOf(detail, 'l1'), ServiceItemStatus.COMPLETED);
      expect(_statusOf(detail, 'l2'), ServiceItemStatus.COMPLETED);
    });

    test('completeAll keeps going past a refusal and reports it', () async {
      repo.refuse.add('l1');
      final result = await items.completeAll(['l1', 'l2']);

      expect(result.done, 1);
      expect(result.failed, 1);
      expect(result.firstError?.message, 'refused l1');
      expect(items.pendingStatusOf('l1'), isNull);
      expect(_statusOf(detail, 'l1'), ServiceItemStatus.PENDING);
      expect(_statusOf(detail, 'l2'), ServiceItemStatus.COMPLETED);
    });
  });

  group('order detail line status', () {
    testWidgets('next-step button finishes a line in one tap', (tester) async {
      final repo = _StatusRepository(OrderStatus.IN_PROGRESS);
      final detail = await _pumpScreen(tester, repo);
      expect(find.text('1/4 дууссан'), findsOneWidget);

      repo.gate = Completer<void>();
      await tester.tap(
        _inLine('Тоормос засах', find.widgetWithText(FilledButton, 'Дуусгах')),
      );
      await tester.pump();
      // Optimistic: progress moves and the line spins before the server answers.
      expect(find.text('2/4 дууссан'), findsOneWidget);
      expect(
        _inLine('Тоормос засах', find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(_statusOf(detail, 'l2'), ServiceItemStatus.COMPLETED);
      expect(find.text('2/4 дууссан'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('status chip jumps a pending line straight to done', (
      tester,
    ) async {
      final repo = _StatusRepository(OrderStatus.IN_PROGRESS);
      final detail = await _pumpScreen(tester, repo);

      await tester.tap(
        _inLine('Тос солих', find.byKey(const ValueKey('item_status_button'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('item_status_option_COMPLETED')),
      );
      await tester.pumpAndSettle();

      expect(repo.statusCalls, ['l1:COMPLETED']);
      expect(_statusOf(detail, 'l1'), ServiceItemStatus.COMPLETED);
    });

    testWidgets('a diagnostic line without a report cannot be completed', (
      tester,
    ) async {
      final repo = _StatusRepository(OrderStatus.IN_PROGRESS);
      await _pumpScreen(tester, repo);

      await tester.tap(
        _inLine(
          'Хөдөлгүүрийн оношилгоо',
          find.byKey(const ValueKey('item_status_button')),
        ),
      );
      await tester.pumpAndSettle();
      final complete = tester.widget<MenuItemButton>(
        find.descendant(
          of: find.byKey(const ValueKey('item_status_option_COMPLETED')),
          matching: find.byType(MenuItemButton),
        ),
      );
      expect(complete.onPressed, isNull);
      expect(find.text('Тайлан шаардлагатай'), findsOneWidget);
    });

    testWidgets('starting a line on a scheduled order starts the order first', (
      tester,
    ) async {
      final repo = _StatusRepository(OrderStatus.SCHEDULED);
      final detail = await _pumpScreen(tester, repo);
      // Bulk complete is for in-progress orders only.
      expect(
        find.byKey(const ValueKey('items_complete_all_button')),
        findsNothing,
      );

      await tester.tap(
        _inLine('Тос солих', find.widgetWithText(FilledButton, 'Эхлүүлэх')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ажил эхлүүлэх үү?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Эхлүүлэх'));
      await tester.pumpAndSettle();

      expect(detail.order?.status, OrderStatus.IN_PROGRESS);
      expect(repo.statusCalls, ['l1:IN_PROGRESS']);
      expect(_statusOf(detail, 'l1'), ServiceItemStatus.IN_PROGRESS);
    });

    testWidgets('backing out of the start prompt leaves the line alone', (
      tester,
    ) async {
      final repo = _StatusRepository(OrderStatus.SCHEDULED);
      final detail = await _pumpScreen(tester, repo);

      await tester.tap(
        _inLine('Тос солих', find.widgetWithText(FilledButton, 'Эхлүүлэх')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Болих'));
      await tester.pumpAndSettle();

      expect(detail.order?.status, OrderStatus.SCHEDULED);
      expect(repo.statusCalls, isEmpty);
    });

    testWidgets('complete all skips diagnostic lines without a report', (
      tester,
    ) async {
      final repo = _StatusRepository(OrderStatus.IN_PROGRESS);
      final detail = await _pumpScreen(tester, repo);

      await tester.tap(find.byKey(const ValueKey('items_complete_all_button')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 оношилгооны мөр тайлангүй тул алгасна.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Дуусгах'));
      await tester.pumpAndSettle();

      expect(repo.statusCalls, ['l1:COMPLETED', 'l2:COMPLETED']);
      expect(_statusOf(detail, 'd1'), ServiceItemStatus.PENDING);
      expect(find.text('3/4 дууссан'), findsOneWidget);
      // One line left and it needs its report: nothing more to bulk-complete.
      expect(
        find.byKey(const ValueKey('items_complete_all_button')),
        findsNothing,
      );
    });
  });
}
