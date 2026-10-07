import 'package:carservice_business/app/shell/shell_chrome.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/adaptive/breakpoints.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/features/cash/data/cash_repository.dart';
import 'package:carservice_business/features/cash/domain/cash_repository.dart';
import 'package:carservice_business/features/cash/presentation/controllers/settlement_flow_controller.dart';
import 'package:carservice_business/features/cash/presentation/screens/settlement_flow_screen.dart';
import 'package:carservice_business/features/customers/data/customer_repository.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/orders/domain/postpaid_settlement.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/controllers/postpaid_controller.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/postpaid/postpaid_widgets.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';

/// The tenant postpaid surface. The [PermissionGate] equivalent here is only
/// a client affordance; the repository/API remains the authority for scope.
class PostpaidScreen extends StatelessWidget {
  const PostpaidScreen({
    super.key,
    this.repository,
    this.controller,
    this.branchController,
    this.user,
    this.cashRepository,
    this.customersRepository,
  }) : assert(repository != null || controller != null);

  final OrdersRepository? repository;
  final PostpaidController? controller;
  final WorkingBranchController? branchController;
  final User? user;

  /// Seams for «Тооцоо нийлэх»; default to the remote repositories.
  final CashRepository? cashRepository;
  final CustomersRepository? customersRepository;

  @override
  Widget build(BuildContext context) {
    final child = _PostpaidView(
      branchController: branchController,
      user: user,
      cashRepository: cashRepository,
      customersRepository: customersRepository,
    );
    if (controller != null) {
      return ChangeNotifierProvider<PostpaidController>.value(
        value: controller!,
        child: child,
      );
    }
    return ChangeNotifierProvider<PostpaidController>(
      create: (_) => PostpaidController(repo: repository!),
      child: child,
    );
  }
}

class _PostpaidView extends StatefulWidget {
  const _PostpaidView({
    this.branchController,
    this.user,
    this.cashRepository,
    this.customersRepository,
  });
  final WorkingBranchController? branchController;
  final User? user;
  final CashRepository? cashRepository;
  final CustomersRepository? customersRepository;

  @override
  State<_PostpaidView> createState() => _PostpaidViewState();
}

class _PostpaidViewState extends State<_PostpaidView> {
  PostpaidController? _controller;
  WorkingBranchController? _branchController;
  String? _lastBranch;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _attachBranchController(widget.branchController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= context.read<PostpaidController>();
    _attachBranchController(
      widget.branchController ??
          Provider.of<WorkingBranchController?>(context, listen: false),
    );
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller!.state is AsyncLoading<PostpaidPage>) {
          unawaited(_controller!.load());
        }
      });
    }
  }

  void _attachBranchController(WorkingBranchController? next) {
    if (next == null || identical(next, _branchController)) return;
    _branchController?.removeListener(_branchChanged);
    _branchController = next;
    _lastBranch = next.selectedBranchId;
    next.addListener(_branchChanged);
  }

  void _branchChanged() {
    final branch = _branchController?.selectedBranchId;
    if (branch == _lastBranch || _controller == null) return;
    _lastBranch = branch;
    unawaited(_controller!.setBranch(branch));
  }

  @override
  void dispose() {
    _branchController?.removeListener(_branchChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PostpaidController>();
    final user = _safeUser(widget.user);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Төлбөрийн үлдэгдэл'),
        actions: [
          if (_canSettle(user))
            TextButton.icon(
              key: const ValueKey('postpaid_settle_button'),
              onPressed: _settle,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Тооцоо нийлэх'),
            ),
          const ShellNotificationBell(),
        ],
      ),
      body: _canView(user)
          ? _PostpaidStateBody(controller: controller)
          : const _PostpaidPermissionDenied(),
    );
  }

  User? _safeUser(User? explicit) {
    if (explicit != null) return explicit;
    try {
      return Authenticator.user;
    } catch (_) {
      return null;
    }
  }

  /// Both permissions are required (server: POSTPAID_SETTLEMENT_FORBIDDEN /
  /// CASH_MANAGE_FORBIDDEN); owner implicit.
  bool _canSettle(User? user) =>
      userCanSettlePostpaid(user) && canSeeView(user, 'cash.manage');

  Future<void> _settle() async {
    final cash = widget.cashRepository ?? RemoteCashRepository();
    final customers = widget.customersRepository ?? RemoteCustomersRepository();
    var branchId = _branchController?.selectedBranchId;
    var options = const <CashBranchOption>[];
    final bc = _branchController;
    if (bc != null) {
      branchId ??= bc.options.lockedBranchId;
      options = [
        for (final b in bc.options.branches) CashBranchOption(b.id, b.name),
      ];
      if (branchId == null && options.length == 1) branchId = options.first.id;
    }
    branchId ??= _safeUser(widget.user)?.branchId;
    final banks = await cash.getBanks();
    if (!mounted) return;
    if (banks is Err<BankSettings>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(banks.error.display),
          action: SnackBarAction(label: 'Дахин оролдох', onPressed: _settle),
        ),
      );
      return;
    }
    final flow = SettlementFlowController(
      repo: cash,
      enabledBanks: banks is Ok<BankSettings> ? banks.value.enabled : const [],
      branchId: branchId,
    );
    final saved = await SettlementFlowScreen.show(
      context,
      controller: flow,
      customers: customers,
      branches: options,
    );
    flow.dispose();
    if (saved != null && mounted) {
      unawaited(_controller?.refresh());
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Тооцоо бүртгэгдлээ')));
    }
  }

  bool _canView(User? user) {
    if (user?.isOwner == true) return true;
    final permissions = user?.role?.permissions ?? const <String>[];
    // viewOwn is a legitimate server-scoped postpaid view. Do not hide it
    // merely because the client-side convenience gate is not full view.
    return permissions.contains('orders.view') ||
        permissions.contains('orders.viewOwn');
  }
}

class _PostpaidStateBody extends StatelessWidget {
  const _PostpaidStateBody({required this.controller});
  final PostpaidController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return switch (state) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => _PostpaidErrorView(
        message: error.display,
        onRetry: controller.retry,
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: controller.refresh,
        child: _PostpaidContent(page: value, controller: controller),
      ),
    };
  }
}

class _PostpaidContent extends StatelessWidget {
  const _PostpaidContent({required this.page, required this.controller});
  final PostpaidPage page;
  final PostpaidController controller;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PostpaidSummaryCard(summary: page.summary),
                const SizedBox(height: 12),
                PostpaidFilterBar(
                  vehicles: page.vehicles,
                  vehicleId: controller.selectedVehicleId,
                  paymentStatus: controller.selectedPaymentStatus,
                  dateFrom: controller.dateFrom,
                  dateTo: controller.dateTo,
                  onVehicleChanged: (value) =>
                      unawaited(controller.setVehicle(value)),
                  onPaymentChanged: (value) =>
                      unawaited(controller.setPaymentStatus(value)),
                  onDateChanged: (range) => unawaited(
                    controller.setDateRange(range?.start, range?.end),
                  ),
                  onClear: () => unawaited(controller.clearFilters()),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tablet =
                    constraints.maxWidth >= AdaptiveBreakpoints.expanded;
                if (tablet) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _VehiclePane(vehicles: page.vehicles)),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: _HistoryPane(controller: controller, page: page),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _VehiclePane(vehicles: page.vehicles),
                    const SizedBox(height: 20),
                    _HistoryPane(controller: controller, page: page),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _VehiclePane extends StatelessWidget {
  const _VehiclePane({required this.vehicles});
  final List<PostpaidVehicleAggregate> vehicles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PostpaidSectionHeading(
          title: 'Тээврийн хэрэгслээр',
          subtitle: 'Серверийн нэгтгэсэн үлдэгдэл',
        ),
        if (vehicles.isEmpty)
          const _PostpaidInlineEmpty(
            message: 'Нэгтгэлтэй тээврийн хэрэгсэл алга',
          )
        else
          ...vehicles.map(
            (vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PostpaidVehicleCard(aggregate: vehicle),
            ),
          ),
      ],
    );
  }
}

class _HistoryPane extends StatelessWidget {
  const _HistoryPane({required this.controller, required this.page});
  final PostpaidController controller;
  final PostpaidPage page;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PostpaidSectionHeading(
          title: 'Захиалгын түүх',
          subtitle: 'Сонгосон төлбөр, огноо, тээврийн хэрэгслийн шүүлтүүр',
        ),
        if (page.orders.isEmpty)
          const _PostpaidInlineEmpty(message: 'Шүүлтэд тохирох захиалга алга')
        else ...[
          for (final order in page.orders)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PostpaidHistoryCard(order: order),
            ),
          if (controller.hasNext) ...[
            const SizedBox(height: 2),
            OutlinedButton.icon(
              onPressed: controller.loadingMore
                  ? null
                  : () => unawaited(controller.loadMore()),
              icon: controller.loadingMore
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: Text(
                controller.loadingMore ? 'Ачаалж байна...' : 'Дараагийн хуудас',
              ),
            ),
          ],
          if (controller.loadMoreError != null)
            _PostpaidLoadMoreError(
              message: controller.loadMoreError!.display,
              onRetry: controller.loadMore,
            ),
        ],
      ],
    );
  }
}

class _PostpaidSectionHeading extends StatelessWidget {
  const _PostpaidSectionHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.textStyles.h3),
        const SizedBox(height: 2),
        Text(subtitle, style: context.textStyles.caption),
      ],
    ),
  );
}

class _PostpaidInlineEmpty extends StatelessWidget {
  const _PostpaidInlineEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => AppCard(
    child: EmptyState(message: message, icon: Icons.receipt_long_outlined),
  );
}

class _PostpaidErrorView extends StatelessWidget {
  const _PostpaidErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: context.opsDanger),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.textStyles.body,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Дахин оролдох'),
          ),
        ],
      ),
    ),
  );
}

class _PostpaidLoadMoreError extends StatelessWidget {
  const _PostpaidLoadMoreError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextButton.icon(
      onPressed: onRetry,
      icon: Icon(Icons.error_outline, color: context.opsDanger),
      label: Text(message),
    ),
  );
}

class _PostpaidPermissionDenied extends StatelessWidget {
  const _PostpaidPermissionDenied();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        'Танд захиалгын төлбөрийн мэдээлэл харах эрх байхгүй байна.',
        textAlign: TextAlign.center,
        style: context.textStyles.body,
      ),
    ),
  );
}
