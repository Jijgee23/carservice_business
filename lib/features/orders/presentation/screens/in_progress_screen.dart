import 'package:carservice_business/app/shell/shell_chrome.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_filter_sheet.dart';
import 'package:carservice_business/features/orders/presentation/widgets/list/order_list_widgets.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Active-work board. The status predicate is sent to the API; cancelled
/// orders therefore cannot leak into this view from another loaded page.
class InProgressScreen extends StatefulWidget {
  const InProgressScreen({super.key, this.user});

  final User? user;

  @override
  State<InProgressScreen> createState() => _InProgressScreenState();
}

class _InProgressScreenState extends State<InProgressScreen> {
  final _scrollController = ScrollController();
  bool _loaded = false;

  bool _canView(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.view') == true ||
      user?.role?.permissions.contains('orders.viewOwn') == true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _scrollController.addListener(() {
      if (_scrollController.position.extentAfter < 400 && mounted) {
        context.read<OrderController>().loadMore();
      }
    });
    final user = widget.user ?? Authenticator.user;
    if (!_canView(user)) return;
    final controller = context.read<OrderController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.setFilter(
        const OrderFilter(statuses: {OrderStatus.IN_PROGRESS}),
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user ?? Authenticator.user;
    if (!_canView(user)) {
      return const Scaffold(body: Center(child: Text('Засварын хуудас харах эрхгүй')));
    }
    final controller = context.watch<OrderController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Хийгдэж буй ажил'),
        actions: [
          IconButton(
            key: const ValueKey('in_progress_refresh'),
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: const ValueKey('in_progress_postpaid_nav'),
            tooltip: 'Дараа төлөх засварын хуудас',
            onPressed: () => AppNav.push('/orders/postpaid'),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          const ShellNotificationBell(),
        ],
      ),
      body: switch (controller.listState) {
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        AsyncError(:final error) => Center(child: Text(error.display)),
        AsyncData(:final value) when value.isEmpty => const Center(
          child: Text('Идэвхтэй ажил алга'),
        ),
        AsyncData(:final value) => _ProgressList(
          controller: controller,
          orders: value,
          scrollController: _scrollController,
        ),
      },
    );
  }
}

class _ProgressList extends StatelessWidget {
  const _ProgressList({
    required this.controller,
    required this.orders,
    required this.scrollController,
  });

  final OrderController controller;
  final List<ServiceOrderSummary> orders;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: controller.refresh,
    child: ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: orders.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        if (index == orders.length) {
          if (controller.loadMoreError != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton.icon(
                key: const ValueKey('in_progress_load_more_retry'),
                onPressed: controller.loadMore,
                icon: const Icon(Icons.refresh),
                label: Text(
                  'Дахин оролдох: ${controller.loadMoreError!.display}',
                ),
              ),
            );
          }
          if (controller.loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return const SizedBox(height: 24);
        }
        final order = orders[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.build_circle_outlined),
            title: Text(
              '#${order.number} · ${plateLabel(order.vehicle.plate, order.vehicle.vin)}',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.customer.displayName),
                const SizedBox(height: 8),
                OrderProgressView(progress: order.progress),
              ],
            ),
            trailing: const OrderStatusChip(status: OrderStatus.IN_PROGRESS),
          ),
        );
      },
    ),
  );
}
