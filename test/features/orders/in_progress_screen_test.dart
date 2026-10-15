import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/widgets/list/order_list_widgets.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/in_progress_screen.dart';

import '../../fakes/fake_order_repository.dart';

User _user(List<String> permissions) => User(
  accessToken: 'token',
  refreshToken: 'refresh',
  id: 'user',
  email: 'user@example.test',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: false,
  role: UserRole('role', 'role', permissions),
  tenant: UserTenant('tenant', 'Tenant'),
);

class _ProgressPagingRepository extends FakeOrderRepository {
  @override
  Future<Result<PagedResult<ServiceOrderSummary>>> getOrders({
    OrderListQuery? query,
    OrderStatus? status,
    String? vehicleId,
    String? customerId,
    String? branchId,
    String? assignedToId,
    PaymentStatus? paymentStatus,
    bool? postpaid,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? q,
    int page = 1,
    int pageSize = 25,
  }) async {
    if (page > 1) return const Err(AppError(ErrorKind.network, 'offline'));
    return Ok(
      PagedResult(
        items: [
          ServiceOrderSummary(
            id: 'active-order',
            number: 'A-0001',
            status: OrderStatus.IN_PROGRESS,
            paymentStatus: PaymentStatus.UNPAID,
            createdAt: DateTime(2026, 1, 1),
            customer: CustomerSummary(
              id: 'customer-1',
              fullName: 'Test Customer',
              phone: '99001122',
            ),
            vehicle: VehicleSummary(
              id: 'vehicle-1',
              plate: '1234ABC',
              make: 'Toyota',
              model: 'Prius',
            ),
            branch: BranchSummary(id: 'branch-1', name: 'Test Branch'),
          ),
        ],
        pagination: PaginationMeta(
          page: 1,
          pageSize: 25,
          total: 2,
          totalPages: 2,
          hasPrev: false,
          hasNext: true,
        ),
      ),
    );
  }
}

void main() {
  testWidgets('renders server progress counts without recomputing item kinds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: OrderProgressView(
            progress: OrderProgressSummary(total: 3, completed: 1),
          ),
        ),
      ),
    );
    expect(find.text('1/3 дууссан'), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, closeTo(1 / 3, 0.0001));
  });

  testWidgets('handles null and zero server progress explicitly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OrderProgressView(progress: null)),
      ),
    );
    expect(find.text('Прогресс тодорхойгүй'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: OrderProgressView(
            progress: OrderProgressSummary(total: 0, completed: 0),
          ),
        ),
      ),
    );
    expect(find.text('0/0 · ажил бүртгэгдээгүй'), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0);
  });

  testWidgets('in-progress view affords only view or viewOwn users', (
    tester,
  ) async {
    final controller = OrderController(repo: FakeOrderRepository());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChangeNotifierProvider.value(
          value: controller,
          child: InProgressScreen(user: _user(const [])),
        ),
      ),
    );
    expect(find.text('Засварын хуудас харах эрхгүй'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('in-progress load-more failure exposes a retry action', (
    tester,
  ) async {
    final controller = OrderController(repo: _ProgressPagingRepository());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChangeNotifierProvider.value(
          value: controller,
          child: InProgressScreen(user: _user(const ['orders.view'])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await controller.loadMore();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('in_progress_load_more_retry')),
      findsOneWidget,
    );
    controller.dispose();
  });
}
