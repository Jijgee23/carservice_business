import 'package:carservice_business/core/widgets/filter_pill.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/core/widgets/adaptive/tight_height_fallback.dart';

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:carservice_business/features/orders/presentation/widgets/order_status_prompt.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:intl/intl.dart';

import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/widgets/adaptive/breakpoints.dart';
import 'package:carservice_business/core/widgets/adaptive/record_views.dart';
import 'package:carservice_business/core/widgets/list_search_bar.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_controller.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/screens/create_order_screen.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_filter_sheet.dart';
import 'package:carservice_business/features/orders/presentation/widgets/list/order_list_widgets.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key, this.user});

  final User? user;

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  WorkingBranchController? _workingBranchController;
  bool _didLoad = false;

  /// Client-side sort over the loaded page only (`TENANT_UI_UX_PLAN.md`
  /// Phase 5's all-orders table). The orders API has no ordering parameter
  /// — see `OrderFilter.sortBy` — so this never claims to sort beyond what
  /// is already on screen; paging in more rows resets it to arrival order.
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WorkingBranchController? nextWorkingBranchController;
    try {
      nextWorkingBranchController = context.read<WorkingBranchController>();
    } on ProviderNotFoundException {
      // Standalone list tests and embeds do not provide a working-branch
      // controller; the legacy branch filter remains available there.
    }
    if (nextWorkingBranchController != _workingBranchController) {
      _workingBranchController?.removeListener(_onWorkingBranchChanged);
      _workingBranchController = nextWorkingBranchController;
      _workingBranchController?.addListener(_onWorkingBranchChanged);
    }
    _onWorkingBranchChanged();
    if (!_didLoad) {
      _didLoad = true;
      final controller = context.read<OrderController>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.loadOrders();
      });
      _scrollController.addListener(() {
        if (_scrollController.position.extentAfter < 500 && mounted) {
          context.read<OrderController>().loadMore();
        }
      });
    }
  }

  @override
  void dispose() {
    _workingBranchController?.removeListener(_onWorkingBranchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onWorkingBranchChanged() {
    final workingBranchController = _workingBranchController;
    if (!mounted ||
        workingBranchController == null ||
        workingBranchController.isAllBranches) {
      return;
    }
    unawaited(context.read<OrderController>().clearLegacyBranchCriteria());
  }

  bool _canView(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.view') == true ||
      user?.role?.permissions.contains('orders.viewOwn') == true;

  bool _canEdit(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.edit') == true ||
      user?.role?.permissions.contains('orders.editOwn') == true;

  bool _canCreate(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.create') == true;

  bool _canAssign(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.assign') == true;

  Future<void> _toggleSelection(
    OrderController controller,
    String orderId,
    User? user,
  ) async {
    controller.toggleSelection(orderId);
    if (_canAssign(user) && controller.selectedCount > 0) {
      await controller.loadAssignableUsers();
    }
  }

  Future<void> _changeBulkStatus(
    OrderController controller,
    OrderStatus status,
  ) async {
    int? durationMinutes;
    if (status == OrderStatus.IN_PROGRESS) {
      final decision = await promptOrderStatusChange(context, status);
      if (!mounted || decision == null) return;
      durationMinutes = decision.durationMinutes;
    }
    await controller.bulkChangeStatus(status, durationMinutes: durationMinutes);
  }

  Future<void> _openFilters(
    OrderController controller,
    User? user, {
    required bool showBranches,
  }) async {
    // The roster route requires `orders.assign`; others still get "Би".
    if (_canAssign(user) && controller.assignableUsersState is! AsyncData) {
      await controller.loadAssignableUsers();
      if (!mounted) return;
    }
    final users =
        controller.assignableUsersState.valueOrNull ?? const <AssignableUser>[];
    final selection = await showOrderFilterSheet(
      context,
      controller.filter,
      assignableUsers: users,
      currentUserId: user?.id,
      branchId: controller.selectedBranchId,
      showBranches: showBranches,
    );
    if (selection == null || !mounted) return;
    controller.applyFilters(selection.filter, branchId: selection.branchId);
  }

  void _clearFilters(OrderController controller) =>
      controller.applyFilters(OrderFilter.empty, branchId: null);

  Future<void> _openOrder(
    OrderController controller,
    ServiceOrderSummary order,
  ) async {
    await AppNav.toNamed<void>(AppPages.orderDetail, arguments: order.id);
    if (mounted) await controller.refresh();
  }

  Future<void> _createOrder(OrderController controller) async {
    final created = await AppNav.to<ServiceOrderSummary>(
      CreateOrderScreen(repository: context.read<OrdersRepository>()),
    );
    if (created == null || !mounted) return;
    unawaited(controller.refresh());
    // Land on the new order with Today underneath, so back from the detail
    // returns to Today rather than this list.
    AppNav.go('/overview');
    await WidgetsBinding.instance.endOfFrame;
    unawaited(AppNav.push('/orders/${Uri.encodeComponent(created.id)}'));
  }

  /// The persistent panel has no open step to fetch the roster on, and a
  /// branch change resets it — so fetch it once the panel is on screen.
  void _ensureAssignableUsers(OrderController controller, User? user) {
    if (!_canAssign(user) ||
        controller.loadingAssignableUsers ||
        controller.assignableUsersState is! AsyncLoading) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.loadAssignableUsers();
    });
  }

  void _selectVisiblePage(OrderController controller, User? user) {
    controller.selectVisiblePage();
    if (_canAssign(user)) controller.loadAssignableUsers();
  }

  /// A tab root inside the shell's [AdaptiveScaffold], which already owns the
  /// page chrome (branch switcher, search, bell, bottom navigation). So this
  /// is a [Material] surface, not a second [Scaffold]: the list's actions sit
  /// behind a quick-action FAB, and the bulk bar docks under the results.
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<OrderController>();
    final user = widget.user ?? Authenticator.user;
    if (!_canView(user)) {
      return Material(
        color: context.opsBackground,
        child: const Center(child: Text('Засварын хуудас харах эрхгүй')),
      );
    }

    final state = controller.listState;
    final hasRows =
        state is AsyncData<List<ServiceOrderSummary>> && state.value.isNotEmpty;
    final showBulkBar =
        controller.selectedCount > 0 && (_canEdit(user) || _canAssign(user));
    // Owner-only, and only while the header's working branch is "all": a
    // concrete working branch already scopes the list.
    final showBranches =
        user?.isOwner == true && _showLegacyBranchFilter(context);
    final activeFilters =
        controller.filter.activeCount +
        (controller.selectedBranchId != null ? 1 : 0);
    final canCreate = _canCreate(user);
    return Material(
      color: context.opsBackground,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                TightHeightFallback(
                  controls: _controls(
                    controller,
                    user,
                    hasRows,
                    showBranches,
                    activeFilters,
                  ),
                  results: _buildResults(controller, state, user, showBranches),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _QuickActionsFab(
                    actions: [
                      if (canCreate)
                        _QuickAction(
                          key: 'order_create_button',
                          icon: Icons.add_circle_outline_rounded,
                          label: 'Шинэ засварын хуудас',
                          primary: true,
                          onTap: () => _createOrder(controller),
                        ),
                      _QuickAction(
                        key: 'orders_in_progress_nav',
                        icon: Icons.build_circle_outlined,
                        label: 'Хийгдэж буй ажил',
                        onTap: () => AppNav.push('/orders/in-progress'),
                      ),
                      _QuickAction(
                        key: 'orders_postpaid_nav',
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Дараа төлөх засварын хуудас',
                        onTap: () => AppNav.push('/orders/postpaid'),
                      ),
                      _QuickAction(
                        key: 'orders_refresh',
                        icon: Icons.refresh,
                        label: 'Шинэчлэх',
                        onTap: controller.refresh,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showBulkBar)
            BulkSelectionBar(
              count: controller.selectedCount,
              onClear: controller.clearVisibleSelection,
              canChangeStatus: _canEdit(user),
              canAssign: _canAssign(user),
              assignableUsers:
                  controller.assignableUsersState.valueOrNull ??
                  const <AssignableUser>[],
              loadingAssignableUsers: controller.loadingAssignableUsers,
              assignableUsersError: controller.assignableUsersError,
              onStatus: (status) => _changeBulkStatus(controller, status),
              onAssign: (id) => controller.bulkAssign(id),
            ),
        ],
      ),
    );
  }

  List<Widget> _controls(
    OrderController controller,
    User? user,
    bool hasRows,
    bool showBranches,
    int activeFilters,
  ) {
    return [
      ListSearchBar(
        controller: _searchController,
        hintText: 'Дугаар, улсын/арлын дугаар, үйлчлүүлэгч...',
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        activeFilters: activeFilters,
        onChanged: controller.setQuery,
        onFilter: () =>
            _openFilters(controller, user, showBranches: showBranches),
        onClear: () {
          _searchController.clear();
          controller.setQuery('');
        },
      ),
      if (MediaQuery.sizeOf(context).width >= AdaptiveBreakpoints.expanded)
        _QuickFilterChips(
          filter: controller.filter,
          myUserId: user?.id,
          onChanged: controller.setFilter,
          // Tablet table only: sits inline at the end of the chip row.
          trailing: hasRows
              ? TextButton.icon(
                  onPressed: () => _selectVisiblePage(controller, user),
                  icon: const Icon(Icons.select_all),
                  label: const Text('Энэ хуудсыг сонгох'),
                )
              : null,
        ),
      ActiveFilterBar(
        filter: controller.filter,
        onClear: () => _clearFilters(controller),
        assignableUsers:
            controller.assignableUsersState.valueOrNull ??
            const <AssignableUser>[],
        currentUserId: user?.id,
      ),
      if (controller.bulkResult?.failed.isNotEmpty == true)
        _BulkFailureBanner(
          result: controller.bulkResult!,
          labelFor: controller.bulkOrderLabel,
        ),
    ];
  }

  bool _showLegacyBranchFilter(BuildContext context) {
    // The header's working-branch controller is the authoritative scope. The
    // legacy owner-only query filter is only meaningful while that scope is
    // explicitly ALL; showing it for a selected branch would label a
    // branch-scoped list as if it could widen its server scope.
    try {
      return context.watch<WorkingBranchController>().isAllBranches;
    } on ProviderNotFoundException {
      // Standalone tests and legacy embeddings have no working-branch
      // provider. Preserve their existing owner-only filter in that case.
      return true;
    }
  }

  Widget _buildResults(
    OrderController controller,
    AsyncValue<List<ServiceOrderSummary>> state,
    User? user,
    bool showBranches,
  ) {
    void select(String id) => _toggleSelection(controller, id, user);
    return switch (state) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => _ErrorView(
        message: error.display,
        retry: controller.refresh,
      ),
      AsyncData(:final value) when value.isEmpty => Center(
        child: Text(
          controller.query.isNotEmpty || controller.filter.activeCount > 0
              ? 'Шүүлтэд тохирох засварын хуудас байхгүй'
              : 'Засварын хуудас байхгүй байна',
        ),
      ),
      AsyncData(:final value) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AdaptiveBreakpoints.expanded;
          if (!wide) {
            return _PhoneOrders(
              controller: controller,
              orders: value,
              open: _openOrder,
              scroll: _scrollController,
              select: select,
            );
          }
          final table = _TabletOrderList(
            controller: controller,
            orders: _sortedOrders(value),
            open: _openOrder,
            select: select,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            onSort: _onSort,
          );
          if (constraints.maxWidth < AdaptiveBreakpoints.extendedRail) {
            return table;
          }
          _ensureAssignableUsers(controller, user);
          // ≥1200dp: a persistent filter panel replaces the filter sheet
          // (`TENANT_UI_UX_PLAN.md` Phase 5). It applies every edit
          // immediately since it is always visible, unlike the sheet.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrderFilterPanel(
                filter: controller.filter,
                onChanged: controller.setFilter,
                onClear: () => _clearFilters(controller),
                assignableUsers:
                    controller.assignableUsersState.valueOrNull ??
                    const <AssignableUser>[],
                currentUserId: user?.id,
                branchId: controller.selectedBranchId,
                onBranchChanged: showBranches ? controller.setBranch : null,
              ),
              Expanded(child: table),
            ],
          );
        },
      ),
    };
  }

  /// Column indexes here must stay in the same order as `_TabletOrderList`'s
  /// [RecordColumn]s (index 0 is the selection checkbox and is never
  /// sortable).
  List<ServiceOrderSummary> _sortedOrders(List<ServiceOrderSummary> orders) {
    final column = _sortColumnIndex;
    if (column == null) return orders;
    int Function(ServiceOrderSummary, ServiceOrderSummary) cmp =
        switch (column) {
          1 => (a, b) => a.vehicle.plate.compareTo(b.vehicle.plate),
          2 => (a, b) => a.customer.displayName.compareTo(
            b.customer.displayName,
          ),
          3 => (a, b) => a.status.index.compareTo(b.status.index),
          4 => (a, b) => a.paymentStatus.index.compareTo(b.paymentStatus.index),
          5 => (a, b) => (a.assignedTo?.fullName ?? '').compareTo(
            b.assignedTo?.fullName ?? '',
          ),
          6 => (a, b) => (a.scheduledAt ?? a.createdAt).compareTo(
            b.scheduledAt ?? b.createdAt,
          ),
          7 => (a, b) => (a.totalAmount ?? -1).compareTo(b.totalAmount ?? -1),
          _ => (a, b) => 0,
        };
    final sorted = [...orders]..sort(cmp);
    if (!_sortAscending) return sorted.reversed.toList(growable: false);
    return sorted;
  }

  void _onSort(int columnIndex) {
    if (columnIndex == 0) return; // the checkbox column is not sortable.
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = true;
      }
    });
  }
}

/// One row of the quick-action menu.
class _QuickAction {
  const _QuickAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final String key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Accent-coloured icon and label, for the main action.
  final bool primary;
}

/// "⋯" FAB holding the list's actions. The menu opens as a dialog route on
/// the root navigator so its blur covers the whole shell (header and bottom
/// navigation included), and it redraws this FAB as a close button in
/// exactly the same spot, so the button appears to turn into ×.
class _QuickActionsFab extends StatelessWidget {
  const _QuickActionsFab({required this.actions});
  final List<_QuickAction> actions;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final picked = await AppNav.generalDialog<_QuickAction>(
      barrierDismissible: true,
      barrierLabel: 'Хаах',
      barrierColor: Colors.transparent,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      // The menu animates its own blur, card and close button.
      transitionBuilder: (_, _, _, child) => child,
      pageBuilder: (_, animation, _) => _QuickActionsMenu(
        anchor: anchor,
        actions: actions,
        animation: animation,
      ),
    );
    // Run after the menu has closed, so pushed routes land on this tab's
    // navigator rather than above the dialog.
    if (picked != null && context.mounted) picked.onTap();
  }

  @override
  Widget build(BuildContext context) => FloatingActionButton(
    key: const ValueKey('orders_actions_fab'),
    heroTag: 'order_list_fab',
    tooltip: 'Үйлдлүүд',
    backgroundColor: context.opsAccent,
    foregroundColor: context.opsTextOnDark,
    onPressed: () => _open(context),
    child: const Icon(Icons.more_horiz_rounded),
  );
}

class _QuickActionsMenu extends StatelessWidget {
  const _QuickActionsMenu({
    required this.anchor,
    required this.actions,
    required this.animation,
  });

  /// The FAB's global rect: the menu card sits above it, right edges
  /// aligned, and the close button covers it.
  final Rect anchor;
  final List<_QuickAction> actions;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      children: [
        // Frosted backdrop over the whole app. It ignores pointers, so a tap
        // anywhere outside the menu reaches the dialog barrier and closes it.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: curved,
              builder: (context, _) => BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 8 * curved.value,
                  sigmaY: 8 * curved.value,
                ),
                child: ColoredBox(
                  color: context.opsBackground.withValues(
                    alpha: 0.45 * curved.value,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: size.width - anchor.right,
          bottom: size.height - anchor.top + 12,
          child: Align(
            alignment: Alignment.bottomRight,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                alignment: Alignment.bottomRight,
                scale: Tween(begin: 0.9, end: 1.0).animate(curved),
                child: _QuickActionsCard(
                  actions: actions,
                  onPick: (action) => AppNav.back(action),
                ),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: anchor,
          child: FloatingActionButton(
            heroTag: null,
            tooltip: 'Хаах',
            backgroundColor: context.opsAccent,
            foregroundColor: context.opsTextOnDark,
            onPressed: () => AppNav.back(),
            child: RotationTransition(
              turns: Tween(begin: -0.125, end: 0.0).animate(curved),
              child: const Icon(Icons.close),
            ),
          ),
        ),
      ],
    );
  }
}

/// The menu itself: one panel of equal rows. [IntrinsicWidth] sizes the card
/// to its widest label so every row shares one width; each row is a single
/// line with the same minimum height.
class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.actions, required this.onPick});
  final List<_QuickAction> actions;
  final ValueChanged<_QuickAction> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.opsSurface,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        side: BorderSide(color: context.opsDivider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 240),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, action) in actions.indexed) ...[
                if (i > 0) Divider(height: 1, color: context.opsDivider),
                _QuickActionRow(action: action, onTap: () => onPick(action)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({required this.action, required this.onTap});
  final _QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = action.primary ? context.opsAccent : context.opsTextPrimary;
    return InkWell(
      key: ValueKey(action.key),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                action.icon,
                size: 22,
                color: action.primary
                    ? context.opsAccent
                    : context.opsTextSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodyMedium.copyWith(
                    color: color,
                    fontWeight: action.primary ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saved quick filters (`TENANT_UI_UX_PLAN.md` Phase 5), shown as a
/// persistent tablet chip row. Each chip toggles one field of [OrderFilter];
/// toggling one on preserves whatever else is already active (they combine),
/// toggling it off clears only that field. Only filters the server query can
/// already express are offered here — "Миний" needs a signed-in user id.
enum _QuickFilter { today, open, unpaid, mine }

class _QuickFilterChips extends StatelessWidget {
  const _QuickFilterChips({
    required this.filter,
    required this.myUserId,
    required this.onChanged,
    this.trailing,
  });

  final OrderFilter filter;
  final String? myUserId;
  final ValueChanged<OrderFilter> onChanged;
  final Widget? trailing;

  static const _openStatuses = {OrderStatus.SCHEDULED, OrderStatus.IN_PROGRESS};

  bool _active(_QuickFilter qf) => switch (qf) {
    _QuickFilter.today => filter.datePreset == DatePreset.today,
    _QuickFilter.open =>
      filter.statuses.isNotEmpty &&
          filter.statuses.containsAll(_openStatuses) &&
          filter.statuses.length == _openStatuses.length,
    _QuickFilter.unpaid =>
      filter.paymentStatuses.length == 1 &&
          filter.paymentStatuses.contains(PaymentStatus.UNPAID),
    _QuickFilter.mine => myUserId != null && filter.assignedToId == myUserId,
  };

  void _toggle(_QuickFilter qf) {
    final active = _active(qf);
    final next = switch (qf) {
      _QuickFilter.today => OrderFilter(
        statuses: filter.statuses,
        paymentStatuses: filter.paymentStatuses,
        datePreset: active ? DatePreset.all : DatePreset.today,
        assignedToId: filter.assignedToId,
        plate: filter.plate,
        postpaid: filter.postpaid,
        internal: filter.internal,
      ),
      _QuickFilter.open => OrderFilter(
        statuses: active ? const {} : _openStatuses,
        paymentStatuses: filter.paymentStatuses,
        datePreset: filter.datePreset,
        assignedToId: filter.assignedToId,
        dateFrom: filter.dateFrom,
        dateTo: filter.dateTo,
        plate: filter.plate,
        postpaid: filter.postpaid,
        internal: filter.internal,
      ),
      _QuickFilter.unpaid => OrderFilter(
        statuses: filter.statuses,
        paymentStatuses: active ? const {} : const {PaymentStatus.UNPAID},
        datePreset: filter.datePreset,
        assignedToId: filter.assignedToId,
        dateFrom: filter.dateFrom,
        dateTo: filter.dateTo,
        plate: filter.plate,
        postpaid: filter.postpaid,
        internal: filter.internal,
      ),
      _QuickFilter.mine => OrderFilter(
        statuses: filter.statuses,
        paymentStatuses: filter.paymentStatuses,
        datePreset: filter.datePreset,
        assignedToId: active ? null : myUserId,
        dateFrom: filter.dateFrom,
        dateTo: filter.dateTo,
        plate: filter.plate,
        postpaid: filter.postpaid,
        internal: filter.internal,
      ),
    };
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    // This row spans the same width as the results area, so it mirrors the
    // results' own table-vs-cards breakpoint: the select-page action only
    // shows while the tablet table (with its checkboxes) is what's rendered.
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Row(
          children: [
            Expanded(child: _chips(context)),
            if (constraints.maxWidth >= AdaptiveBreakpoints.expanded) ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _chips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      children: [
        _chip(
          context,
          'Өнөөдөр',
          _QuickFilter.today,
          key: 'orders_quick_filter_today',
        ),
        _chip(
          context,
          'Нээлттэй',
          _QuickFilter.open,
          key: 'orders_quick_filter_open',
        ),
        _chip(
          context,
          'Төлбөр дутуу',
          _QuickFilter.unpaid,
          key: 'orders_quick_filter_unpaid',
        ),
        if (myUserId != null)
          _chip(
            context,
            'Миний',
            _QuickFilter.mine,
            key: 'orders_quick_filter_mine',
          ),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    _QuickFilter qf, {
    required String key,
  }) {
    return FilterPill(
      key: ValueKey(key),
      label: label,
      selected: _active(qf),
      onTap: () => _toggle(qf),
    );
  }
}

class _PhoneOrders extends StatelessWidget {
  const _PhoneOrders({
    required this.controller,
    required this.orders,
    required this.open,
    required this.scroll,
    required this.select,
  });
  final OrderController controller;
  final List<ServiceOrderSummary> orders;
  final Future<void> Function(OrderController, ServiceOrderSummary) open;
  final ScrollController scroll;
  final ValueChanged<String> select;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: controller.refresh,
    child: ListView.separated(
      controller: scroll,
      // Extra bottom room so the last card and the footer clear the FAB.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: orders.length + 1,
      separatorBuilder: (_, index) =>
          SizedBox(height: index == orders.length - 1 ? 4 : 10),
      itemBuilder: (_, index) {
        if (index == orders.length) return _ListFooter(controller: controller);
        final order = orders[index];
        return OrderPhoneCard(
          order: order,
          selected: controller.isSelected(order.id),
          onTap: () => open(controller, order),
          onSelect: (_) => select(order.id),
        );
      },
    ),
  );
}

/// The tablet/pane list column, now a real sortable table
/// (`TENANT_UI_UX_PLAN.md` Phase 5) backed by [DataTableView]. Used both
/// stand-alone (list only) and at [AdaptiveBreakpoints.expanded] and wider —
/// [DataTableView.forceTable] is set because this slot can render inside a
/// column narrower than the phone/tablet threshold even though the screen
/// overall is tablet width.
class _TabletOrderList extends StatelessWidget {
  const _TabletOrderList({
    required this.controller,
    required this.orders,
    required this.open,
    required this.select,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
  });
  final OrderController controller;
  final List<ServiceOrderSummary> orders;
  final Future<void> Function(OrderController, ServiceOrderSummary) open;
  final ValueChanged<String> select;
  final int? sortColumnIndex;
  final bool sortAscending;
  final ValueChanged<int> onSort;

  static final _dateFmt = DateFormat('MM/dd HH:mm');
  static final _moneyFmt = NumberFormat('#,###');

  List<RecordColumn<ServiceOrderSummary>> _columns(BuildContext context) => [
    RecordColumn<ServiceOrderSummary>(
      label: '',
      flex: 1,
      builder: (context, order) => Semantics(
        label: controller.isSelected(order.id) ? 'Сонгогдсон' : 'Сонгох',
        child: Checkbox(
          value: controller.isSelected(order.id),
          onChanged: (_) => select(order.id),
        ),
      ),
    ),
    RecordColumn<ServiceOrderSummary>(
      label: 'Дугаар',
      flex: 3,
      builder: (context, order) => Text(
        plateLabel(order.vehicle.plate, order.vehicle.vin),
        overflow: TextOverflow.ellipsis,
        style: context.textStyles.bodyMedium,
      ),
    ),
    RecordColumn<ServiceOrderSummary>(
      label: 'Үйлчлүүлэгч',
      flex: 4,
      builder: (context, order) => Text(
        order.customer.displayName,
        overflow: TextOverflow.ellipsis,
        style: context.textStyles.caption,
      ),
    ),
    RecordColumn<ServiceOrderSummary>(
      label: 'Статус',
      flex: 3,
      builder: (context, order) => OrderStatusChip(status: order.status),
    ),
    RecordColumn<ServiceOrderSummary>(
      label: 'Төлбөр',
      flex: 3,
      builder: (context, order) =>
          OrderPaymentChip(status: order.paymentStatus),
    ),
    RecordColumn<ServiceOrderSummary>(
      label: 'Хариуцагч',
      flex: 3,
      builder: (context, order) => Text(
        order.assignedTo?.fullName ?? 'Хуваарилаагүй',
        overflow: TextOverflow.ellipsis,
        style: context.textStyles.caption.copyWith(
          color: order.assignedTo == null ? context.opsTextHint : null,
        ),
      ),
    ),
    RecordColumn<ServiceOrderSummary>(
      label: 'Огноо',
      flex: 3,
      builder: (context, order) => Text(
        _dateFmt.format((order.scheduledAt ?? order.createdAt).toLocal()),
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    ),
    RecordColumn<ServiceOrderSummary>(
      label: 'Дүн',
      flex: 2,
      numeric: true,
      builder: (context, order) => Text(
        order.totalAmount == null
            ? '—'
            : '${_moneyFmt.format(order.totalAmount!.toInt())}₮',
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: controller.refresh,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Expanded(
          child: DataTableView<ServiceOrderSummary>(
            forceTable: true,
            records: orders,
            columns: _columns(context),
            sortColumnIndex: sortColumnIndex,
            sortAscending: sortAscending,
            onSort: onSort,
            onTap: (order) => open(controller, order),
          ),
        ),
        _ListFooter(controller: controller),
      ],
    ),
  );
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.controller});
  final OrderController controller;
  @override
  Widget build(BuildContext context) {
    if (controller.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (controller.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: TextButton.icon(
          onPressed: controller.loadMore,
          icon: const Icon(Icons.refresh),
          label: Text('Дахин оролдох: ${controller.loadMoreError!.display}'),
        ),
      );
    }
    if (controller.hasNext) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: TextButton.icon(
          onPressed: controller.loadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('Дараагийн хуудас'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          'Нийт ${controller.total} засварын хуудас',
          style: context.textStyles.caption,
        ),
      ),
    );
  }
}

class _BulkFailureBanner extends StatelessWidget {
  const _BulkFailureBanner({required this.result, required this.labelFor});
  final BulkOrderResult result;
  final String Function(String orderId) labelFor;
  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Зарим мөрийн үйлдэл амжилтгүй болсон'),
        for (final failure in result.failed)
          Text(
            '${labelFor(failure.orderId)}: ${failure.code} — ${failure.message}',
          ),
      ],
    ),
    leading: Icon(Icons.warning_amber_rounded, color: context.opsWarning),
    actions: const [SizedBox.shrink()],
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Дахин оролдох'),
        ),
      ],
    ),
  );
}
