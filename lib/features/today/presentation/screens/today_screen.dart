import 'package:flutter/material.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/subscription.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/report_detail_screen.dart';
import 'package:carservice_business/features/orders/domain/postpaid_settlement.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_payment_screen.dart';
import 'package:carservice_business/features/orders/presentation/widgets/detail/order_item_widgets.dart';
import 'package:carservice_business/features/orders/presentation/widgets/diagnostic_template_picker_sheet.dart';
import 'package:carservice_business/features/today/presentation/widgets/today_order_actions_sheet.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/widgets/adaptive/breakpoints.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/screens/create_order_screen.dart';
import 'package:carservice_business/features/orders/presentation/widgets/order_status_prompt.dart';
import 'package:carservice_business/features/overview/presentation/screens/home_screen.dart';
import 'package:carservice_business/features/profile/presentation/screens/profile_screen.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/today/presentation/controllers/today_appointments_controller.dart';
import 'package:carservice_business/features/today/presentation/controllers/today_orders_controller.dart';
import 'package:carservice_business/features/today/presentation/widgets/today_appointments_timeline.dart';
import 'package:carservice_business/features/today/presentation/widgets/today_order_card.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// The work-first home: today's orders grouped by lane, each card carrying
/// its order's next step (start, finish the work, take payment, complete)
/// and a ⋯ sheet with the rest (diagnostics, reports, payment). Tablets
/// (≥840dp) show all three lanes side by side; narrower screens switch
/// lanes with a segmented control.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    this.controller,
    this.appointmentsController,
    this.user,
    this.loadSubscription,
    this.sessionOpenLookup,
  });

  /// Test seam. When null the screen owns a controller built on the app's
  /// [OrdersRepository]. The Orders tab's shared list controller is never
  /// used here, so the Today board cannot overwrite its filters.
  final TodayOrdersController? controller;

  /// Test seam for the appointments timeline. When null the screen owns a
  /// controller built on the default [AppointmentsRepository], mirroring
  /// [controller].
  final TodayAppointmentsController? appointmentsController;
  final User? user;

  /// Test seam; defaults to [SubscriptionService.getStatus].
  final Future<SubscriptionStatus?> Function()? loadSubscription;

  /// Test seam for the payment screen's cash-drawer flag; defaults to the
  /// cash API.
  final Future<Result<bool>> Function(String branchId)? sessionOpenLookup;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late final TodayOrdersController _controller =
      widget.controller ??
      TodayOrdersController(repository: context.read<OrdersRepository>());
  late final TodayAppointmentsController _apptController =
      widget.appointmentsController ?? TodayAppointmentsController();
  TodayLane? _lane;
  SubscriptionStatus? _sub;

  /// Phone-only top-level split. Tablets show appointments alongside orders
  /// (landscape) or in a collapsible section (portrait/medium) instead.
  _TodaySection _section = _TodaySection.orders;
  bool _apptSectionExpanded = false;

  User? get _user => widget.user ?? Authenticator.user;

  bool _has(String permission) =>
      _user?.isOwner == true ||
      _user?.role?.permissions.contains(permission) == true;

  bool get _canCreate => _has('orders.create');
  bool get _canViewPayments => _has('payments.view');
  bool get _canViewAppointments => _has('appointments.view');
  bool get _canEditAppointments => _has('appointments.edit');
  bool get _canItemStatus => _has('orders.itemStatus');
  bool get _canFillDiagnostics => _has('diagnostics.create');
  bool get _canViewReports => _has('diagnostics.view');

  bool _canEdit(ServiceOrderSummary order) =>
      _has('orders.edit') ||
      (_user?.role?.permissions.contains('orders.editOwn') == true &&
          order.assignedTo?.id == _user?.id);

  @override
  void initState() {
    super.initState();
    _controller.start();
    if (_canViewAppointments) _apptController.start();
    (widget.loadSubscription ?? SubscriptionService.instance.getStatus)().then((
      sub,
    ) {
      if (mounted) setState(() => _sub = sub);
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    if (widget.appointmentsController == null) _apptController.dispose();
    super.dispose();
  }

  /// The card's next step. An in-progress order finishes its work first,
  /// then takes payment, then completes: the order the server checks
  /// before «Дуусгах» (`ITEMS_NOT_COMPLETED`, `PAYMENT_INCOMPLETE`).
  TodayCardAction? _actionFor(ServiceOrderSummary order) {
    switch (order.status) {
      case OrderStatus.SCHEDULED:
        return _canEdit(order) ? TodayCardAction.start : null;
      case OrderStatus.IN_PROGRESS:
        if ((order.unfinishedWorkCount ?? 0) > 0 &&
            _canEdit(order) &&
            _canItemStatus) {
          return TodayCardAction.finishWork;
        }
        if (_unpaidBlocksCompletion(order) && _canViewPayments) {
          return TodayCardAction.pay;
        }
        return _canEdit(order) ? TodayCardAction.complete : null;
      case OrderStatus.COMPLETED:
        return _canViewPayments && order.paymentStatus != PaymentStatus.PAID
            ? TodayCardAction.pay
            : null;
      case OrderStatus.CANCELLED:
        return null;
    }
  }

  /// The balance stops «Дуусгах» (see [ServiceOrderSummary.completionBlocker]).
  bool _unpaidBlocksCompletion(ServiceOrderSummary order) {
    final balance = order.unpaidBalance;
    if (order.isInternal || balance == null || balance <= 0.004) return false;
    return !order.isPostpaid || !userCanSettlePostpaid(_user);
  }

  /// Whether the card's ⋯ sheet has anything beyond opening the detail.
  bool _hasMore(ServiceOrderSummary order) =>
      order.status == OrderStatus.IN_PROGRESS ||
      (order.status != OrderStatus.CANCELLED &&
          _canViewPayments &&
          !order.isInternal &&
          order.paymentStatus != PaymentStatus.PAID);

  /// Full-screen, above the bottom navigation, like the Orders list cards.
  Future<void> _open(ServiceOrderSummary order) async {
    await AppNav.toNamed<void>(AppPages.orderDetail, arguments: order.id);
    if (mounted) await _controller.load();
  }

  Widget _appointmentsPane() => TodayAppointmentsTimeline(
    controller: _apptController,
    canEditAppointments: _canEditAppointments,
    canCreateOrders: _canCreate,
    onOrderCreated: _open,
  );

  Future<void> _runAction(
    ServiceOrderSummary order,
    TodayCardAction action,
  ) async {
    switch (action) {
      case TodayCardAction.pay:
        return _pay(order);
      case TodayCardAction.finishWork:
        return _finishWork(order);
      case TodayCardAction.start:
      case TodayCardAction.complete:
        break;
    }
    final status = action == TodayCardAction.start
        ? OrderStatus.IN_PROGRESS
        : OrderStatus.COMPLETED;
    final decision = await promptOrderStatusChange(
      context,
      status,
      order: order,
    );
    if (decision == null || !mounted) return;
    final error = await _controller.changeStatus(
      order,
      status,
      durationMinutes: decision.durationMinutes,
    );
    if (!mounted) return;
    if (error != null) {
      messageError(error.display);
    } else if (status == OrderStatus.IN_PROGRESS) {
      messageComplete(
        '${plateLabel(order.vehicle.plate, order.vehicle.vin)} ажил эхэллээ',
      );
      // A started order is worked from its detail; back returns to Today.
      await _open(order);
    } else {
      messageComplete(
        '${plateLabel(order.vehicle.plate, order.vehicle.vin)} дууслаа',
      );
    }
  }

  /// Opens the order's ⋯ sheet and runs what was picked.
  Future<void> _openMenu(ServiceOrderSummary order) async {
    final choice = await AppNav.sheet<TodayMenuChoice>(
      TodayOrderActionsSheet(
        order: order,
        access: TodayMenuAccess(
          lines: _canEdit(order) && _canItemStatus,
          diagnostics: _canEdit(order) && _canFillDiagnostics,
          reports: _canViewReports,
          payments: _canViewPayments,
          complete: _canEdit(order),
        ),
        load: () => _controller.repository.getOrderDetail(order.id),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case TodayFinishWork(:final detail):
        await _finishWork(order, detail: detail);
      case TodayFillDiagnostic(:final detail, :final item):
        await _fillDiagnostic(detail, item);
      case TodayViewReport(:final item):
        await AppNav.to<void>(
          ReportDetailScreen(
            reportId: item.diagnosticReportId!,
            deleteLocked: isLineCompletedLocked(item),
          ),
        );
        if (mounted) await _controller.load();
      case TodayPay():
        await _pay(order);
      case TodayCompleteOrder():
        await _runAction(order, TodayCardAction.complete);
      case TodayOpenDetail():
        await _open(order);
    }
  }

  /// The payment screen with «Төлбөр бүртгэх» already open.
  Future<void> _pay(ServiceOrderSummary order) async {
    await OrderPaymentScreen.open(
      context,
      orderId: order.id,
      user: widget.user,
      openRecord: true,
      repo: _controller.repository,
      sessionOpenLookup: widget.sessionOpenLookup,
    );
    if (mounted) await _controller.load();
  }

  /// Completes the order's open work lines. Diagnostics still waiting for
  /// their report are left out; when only those remain, offers to fill one.
  Future<void> _finishWork(
    ServiceOrderSummary order, {
    ServiceOrderDetail? detail,
  }) async {
    final loaded = detail ?? await _loadDetail(order);
    if (loaded == null || !mounted) return;
    final lines = completableLines(loaded.items);
    final pending = reportPendingLines(loaded.items);
    final plate = plateLabel(order.vehicle.plate, order.vehicle.vin);
    if (lines.isEmpty) {
      if (pending.isNotEmpty && _canFillDiagnostics) {
        final fill = await ConfirmSheet.show(
          context,
          title: 'Оношилгоо бөглөх шаардлагатай',
          message:
              '«${pending.first.description}» оношилгооны тайланг бөглөсний '
              'дараа ажил дуусна.',
          confirmLabel: 'Бөглөх',
          icon: Icons.fact_check_outlined,
          iconColor: context.opsAccent,
        );
        if (fill && mounted) await _fillDiagnostic(loaded, pending.first);
      } else {
        messageComplete('$plate · дуусгах ажил үлдээгүй');
        await _controller.load();
      }
      return;
    }
    final ok = await ConfirmSheet.show(
      context,
      title: 'Бүх ажлыг дуусгах уу?',
      message: [
        '${lines.length} ажлын мөрийг "Дууссан" болгоно.',
        if (pending.isNotEmpty)
          '${pending.length} оношилгооны мөр тайлангүй тул алгасна.',
      ].join('\n'),
      confirmLabel: 'Дуусгах',
      icon: Icons.done_all_rounded,
      iconColor: context.opsGood,
    );
    if (!ok || !mounted) return;
    final result = await _controller.completeLines(order, [
      for (final line in lines) line.id,
    ]);
    if (!mounted) return;
    if (result.firstError case final error?) {
      messageError(
        result.done > 0
            ? '${result.done}/${lines.length} мөр дууссан. ${error.display}'
            : error.display,
      );
    } else {
      messageComplete('$plate · ${result.done} ажил дууслаа');
    }
  }

  Future<ServiceOrderDetail?> _loadDetail(ServiceOrderSummary order) async {
    final result = await _controller.detail(order.id);
    switch (result) {
      case Ok(:final value):
        return value;
      case Err(:final error):
        if (mounted) messageError(error.display);
        return null;
    }
  }

  /// The diagnostic form for [item]; the board reloads after it.
  Future<void> _fillDiagnostic(
    ServiceOrderDetail detail,
    ServiceItem item,
  ) async {
    await openOrderDiagnostic(
      context,
      orderId: detail.id,
      item: item,
      vehicle: detail.vehicle,
      customer: detail.customer,
    );
    if (mounted) await _controller.load();
  }

  Future<void> _create() async {
    final created = await AppNav.to<ServiceOrderSummary>(
      CreateOrderScreen(repository: context.read<OrdersRepository>()),
    );
    if (created != null && mounted) await _open(created);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final wide = width >= AdaptiveBreakpoints.expanded;
          final tier = AdaptiveBreakpoints.ofWidth(width);
          // Tablet landscape: appointments get their own column beside the
          // lanes. Narrower tablets show a collapsible section inline
          // above the board instead (see `showAppointmentsInline` below).
          final showAppointmentsColumn =
              width >= AdaptiveBreakpoints.extendedRail && _canViewAppointments;
          final showAppointmentsInline =
              _canViewAppointments && !showAppointmentsColumn;
          const listFlexValue = 5;
          const detailFlexValue = 3;
          // The board's own column is narrower than the screen once the
          // appointments column takes its share — mirror that math to find
          // out how much room the board actually has.
          final boardWidth = showAppointmentsColumn
              ? width * listFlexValue / (listFlexValue + detailFlexValue)
              : width;
          // Full three-lane board only when it actually has room; once the
          // appointments column squeezes it below ~840dp, fall back to one
          // grouped, scrollable list instead of rendering three ~180dp
          // slivers no one can read.
          final boardWide = wide && boardWidth >= AdaptiveBreakpoints.expanded;
          final header = _Header(
            controller: _controller,
            onCreate: _canCreate ? _create : null,
            subscription: _sub,
          );
          return switch (_controller.state) {
            AsyncLoading() => Column(
              children: [
                header,
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
            AsyncError(:final error) => Column(
              children: [
                header,
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error.display, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const ValueKey('today_retry'),
                          onPressed: _controller.load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Дахин оролдох'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            AsyncData(:final value) => _buildBoard(
              header: header,
              value: value,
              wide: wide,
              tier: tier,
              boardWide: boardWide,
              showAppointmentsColumn: showAppointmentsColumn,
              showAppointmentsInline: showAppointmentsInline,
              listFlexValue: listFlexValue,
              detailFlexValue: detailFlexValue,
            ),
          };
        },
      ),
    );
  }

  Widget _buildBoard({
    required Widget header,
    required TodayBoard value,
    required bool wide,
    required AdaptiveSize tier,
    required bool boardWide,
    required bool showAppointmentsColumn,
    required bool showAppointmentsInline,
    required int listFlexValue,
    required int detailFlexValue,
  }) {
    final boardContent = wide
        ? (boardWide
              ? _WideBoard(
                  header: header,
                  board: value,
                  cardFor: _card,
                  appointments: showAppointmentsInline
                      ? _CollapsibleAppointments(
                          controller: _apptController,
                          expanded: _apptSectionExpanded,
                          onToggle: () => setState(
                            () => _apptSectionExpanded = !_apptSectionExpanded,
                          ),
                          child: _appointmentsPane(),
                        )
                      : null,
                )
              : _GroupedBoard(
                  header: header,
                  board: value,
                  cardFor: _card,
                  appointments: showAppointmentsInline
                      ? _CollapsibleAppointments(
                          controller: _apptController,
                          expanded: _apptSectionExpanded,
                          onToggle: () => setState(
                            () => _apptSectionExpanded = !_apptSectionExpanded,
                          ),
                          child: _appointmentsPane(),
                        )
                      : null,
                ))
        : _NarrowBoard(
            header: header,
            board: value,
            lane: _lane ?? _defaultLane(value),
            onLane: (lane) => setState(() => _lane = lane),
            onRefresh: _controller.load,
            cardFor: _card,
            tier: tier,
            canViewAppointments: _canViewAppointments,
            section: _section,
            onSection: (s) => setState(() => _section = s),
            apptExpanded: _apptSectionExpanded,
            onApptToggle: () =>
                setState(() => _apptSectionExpanded = !_apptSectionExpanded),
            appointmentsPaneBuilder: _canViewAppointments
                ? _appointmentsPane
                : null,
            appointmentsController: _apptController,
          );
    if (!showAppointmentsColumn) return boardContent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: listFlexValue, child: boardContent),
        const VerticalDivider(width: 1),
        Expanded(flex: detailFlexValue, child: _appointmentsPane()),
      ],
    );
  }

  /// Open the lane with work in it: in-progress first, then the queue.
  TodayLane _defaultLane(TodayBoard board) => board.inProgress.isNotEmpty
      ? TodayLane.inProgress
      : board.waiting.isNotEmpty
      ? TodayLane.waiting
      : TodayLane.inProgress;

  Widget _card(ServiceOrderSummary order) {
    final action = _actionFor(order);
    return TodayOrderCard(
      order: order,
      now: _controller.now(),
      onTap: () => _open(order),
      action: action,
      busy: _controller.isBusy(order.id),
      onAction: action == null ? null : () => _runAction(order, action),
      onMore: _hasMore(order) ? () => _openMenu(order) : null,
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.onCreate,
    required this.subscription,
  });

  final TodayOrdersController controller;
  final VoidCallback? onCreate;
  final SubscriptionStatus? subscription;

  static const _weekdays = [
    'Даваа',
    'Мягмар',
    'Лхагва',
    'Пүрэв',
    'Баасан',
    'Бямба',
    'Ням',
  ];

  @override
  Widget build(BuildContext context) {
    // The header can render inside a column narrower than the device (e.g.
    // the grouped board's list share once a detail pane opens), so the
    // compact decision must use the space actually available here, not the
    // full-screen `MediaQuery` width.
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.maxWidth),
    );
  }

  Widget _build(BuildContext context, double availableWidth) {
    final now = controller.now();
    final updated = controller.lastUpdated;
    final sub = subscription;
    // Large text scaling needs the same compact treatment as a narrow phone
    // — the full "updated at" text plus a labelled create button no longer
    // fit the row, so both collapse to their icon-only forms.
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final compact = availableWidth < AdaptiveBreakpoints.compact || largeText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sub != null && sub.needsAttention) ...[
            SubscriptionBanner(
              sub: sub,
              onTap: () => AppNav.to(const ProfileScreen()),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Өнөөдөр', style: context.textStyles.h2),
                    const SizedBox(height: 2),
                    Text(
                      '${_weekdays[now.weekday - 1]}, '
                      '${now.month}-р сарын ${now.day}',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.opsTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (updated != null && !compact)
                Text(
                  controller.refreshError != null
                      ? 'Шинэчилж чадсангүй'
                      : 'Шинэчлэгдсэн ${DateFormat('HH:mm').format(updated)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: controller.refreshError != null
                        ? context.opsDanger
                        : context.opsTextHint,
                  ),
                ),
              IconButton(
                key: const ValueKey('today_refresh'),
                tooltip: 'Шинэчлэх',
                onPressed: controller.refreshing ? null : controller.load,
                icon: controller.refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              if (onCreate != null && compact)
                IconButton.filled(
                  key: const ValueKey('today_create_order'),
                  tooltip: 'Шинэ засварын хуудас',
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                )
              else if (onCreate != null) ...[
                const SizedBox(width: 4),
                FilledButton.icon(
                  key: const ValueKey('today_create_order'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Шинэ засварын хуудас'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Layouts ─────────────────────────────────────────────────────────────────

typedef _CardBuilder = Widget Function(ServiceOrderSummary order);

class _WideBoard extends StatelessWidget {
  const _WideBoard({
    required this.header,
    required this.board,
    required this.cardFor,
    this.appointments,
  });

  final Widget header;
  final TodayBoard board;
  final _CardBuilder cardFor;

  /// Collapsible appointments section for tablet portrait/medium widths
  /// (840–1200dp). Null when appointments aren't visible here — either the
  /// user lacks permission, or the screen is wide enough to give them their
  /// own column instead (see `TodayScreen.build`'s `landscapeAppointments`).
  final Widget? appointments;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        header,
        _BoardNotes(board: board),
        if (appointments != null) appointments!,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final lane in TodayLane.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _LaneColumn(
                        lane: lane,
                        orders: board.lane(lane),
                        cardFor: cardFor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One vertical list of every lane, grouped under section headers with
/// counts, instead of three side-by-side columns. Used whenever the board's
/// own column is too narrow for three lanes to be usable — either because a
/// detail pane is open, or because the screen itself sits between 840 and
/// ~1200dp (`TodayScreen.build`'s `boardWide`).
class _GroupedBoard extends StatelessWidget {
  const _GroupedBoard({
    required this.header,
    required this.board,
    required this.cardFor,
    this.appointments,
  });

  final Widget header;
  final TodayBoard board;
  final _CardBuilder cardFor;
  final Widget? appointments;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header),
        SliverToBoxAdapter(child: _BoardNotes(board: board)),
        if (appointments != null) SliverToBoxAdapter(child: appointments!),
        for (final lane in TodayLane.values) ..._laneSlivers(context, lane),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }

  List<Widget> _laneSlivers(BuildContext context, TodayLane lane) {
    final orders = board.lane(lane);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Semantics(
            header: true,
            child: Row(
              children: [
                _LaneDot(lane: lane),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(lane.label, style: context.textStyles.bodyMedium),
                ),
                _CountBadge(count: orders.length),
              ],
            ),
          ),
        ),
      ),
      if (orders.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EmptyLane(lane: lane),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          sliver: SliverList.separated(
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => cardFor(orders[i]),
          ),
        ),
    ];
  }
}

/// Collapsible "Цаг захиалга" section shown on tablet widths that are too
/// narrow for a permanent appointments column (840–1200dp).
class _CollapsibleAppointments extends StatelessWidget {
  const _CollapsibleAppointments({
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final TodayAppointmentsController controller;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final appointments = switch (controller.state) {
      AsyncData(:final value) =>
        value
            .where((a) => !a.status.isTerminal && a.serviceOrder == null)
            .toList(),
      _ => const [],
    };
    final now = controller.now();
    final upcoming = appointments
        .where((a) => a.requestedAt != null && !a.requestedAt!.isBefore(now))
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.opsDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('today_appointments_toggle'),
              onTap: onToggle,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 18,
                      color: context.opsTextHint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Цаг захиалга · ${appointments.length}',
                            style: context.textStyles.bodyMedium,
                          ),
                          if (!expanded && upcoming != null)
                            Text(
                              'Дараагийнх ${DateFormat('HH:mm').format(upcoming.requestedAt!)} · ${_upcomingLabel(upcoming)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.caption,
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: context.opsTextHint,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) SizedBox(height: 320, child: child),
          ],
        ),
      ),
    );
  }
}

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    required this.lane,
    required this.orders,
    required this.cardFor,
  });

  final TodayLane lane;
  final List<ServiceOrderSummary> orders;
  final _CardBuilder cardFor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.opsDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Semantics(
              header: true,
              child: Row(
                children: [
                  _LaneDot(lane: lane),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lane.label,
                      style: context.textStyles.bodyMedium,
                    ),
                  ),
                  _CountBadge(count: orders.length),
                ],
              ),
            ),
          ),
          Expanded(
            child: orders.isEmpty
                ? _EmptyLane(lane: lane)
                : ListView.separated(
                    key: PageStorageKey('today_lane_${lane.name}'),
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => cardFor(orders[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Phone-only top-level split between the orders board and the appointments
/// timeline. Tablet widths never use this — see `TodayScreen.build`.
enum _TodaySection { orders, appointments }

class _NarrowBoard extends StatelessWidget {
  const _NarrowBoard({
    required this.header,
    required this.board,
    required this.lane,
    required this.onLane,
    required this.onRefresh,
    required this.cardFor,
    required this.tier,
    required this.canViewAppointments,
    required this.section,
    required this.onSection,
    required this.apptExpanded,
    required this.onApptToggle,
    required this.appointmentsPaneBuilder,
    required this.appointmentsController,
  });

  final Widget header;
  final TodayBoard board;
  final TodayLane lane;
  final ValueChanged<TodayLane> onLane;
  final Future<void> Function() onRefresh;
  final _CardBuilder cardFor;
  final AdaptiveSize tier;
  final bool canViewAppointments;
  final _TodaySection section;
  final ValueChanged<_TodaySection> onSection;
  final bool apptExpanded;
  final VoidCallback onApptToggle;

  /// Builds a fresh [TodayAppointmentsTimeline]; null when appointments
  /// aren't visible to this user.
  final Widget Function()? appointmentsPaneBuilder;
  final TodayAppointmentsController appointmentsController;

  @override
  Widget build(BuildContext context) {
    final showTopSplit = canViewAppointments && tier == AdaptiveSize.phone;
    if (showTopSplit && section == _TodaySection.appointments) {
      return Column(
        children: [
          header,
          _SectionSelector(section: section, onSection: onSection),
          Expanded(child: appointmentsPaneBuilder!()),
        ],
      );
    }

    final orders = board.lane(lane);
    final showCollapsibleAppointments =
        canViewAppointments &&
        tier == AdaptiveSize.compactTablet &&
        appointmentsPaneBuilder != null;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          if (showTopSplit)
            SliverToBoxAdapter(
              child: _SectionSelector(section: section, onSection: onSection),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<TodayLane>(
                  key: const ValueKey('today_lane_selector'),
                  showSelectedIcon: false,
                  segments: [
                    for (final l in TodayLane.values)
                      ButtonSegment(
                        value: l,
                        label: Text(
                          '${_shortLabel(l)} ${board.lane(l).length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  selected: {lane},
                  onSelectionChanged: (s) => onLane(s.first),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _BoardNotes(board: board)),
          if (showCollapsibleAppointments)
            SliverToBoxAdapter(
              child: _CollapsibleAppointments(
                controller: appointmentsController,
                expanded: apptExpanded,
                onToggle: onApptToggle,
                child: appointmentsPaneBuilder!(),
              ),
            ),
          if (orders.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyLane(lane: lane),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => cardFor(orders[i]),
              ),
            ),
        ],
      ),
    );
  }

  static String _shortLabel(TodayLane lane) => switch (lane) {
    TodayLane.waiting => 'Хүлээгдэж',
    TodayLane.inProgress => 'Хийгдэж',
    TodayLane.completed => 'Дууссан',
  };
}

/// Phone top-level "Засварын хуудас | Цаг" split (`TENANT_UI_UX_PLAN.md` Phase 4).
class _SectionSelector extends StatelessWidget {
  const _SectionSelector({required this.section, required this.onSection});
  final _TodaySection section;
  final ValueChanged<_TodaySection> onSection;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<_TodaySection>(
          key: const ValueKey('today_section_selector'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _TodaySection.orders,
              label: Text('Засварын хуудас'),
            ),
            ButtonSegment(
              value: _TodaySection.appointments,
              label: Text('Цаг'),
            ),
          ],
          selected: {section},
          onSelectionChanged: (s) => onSection(s.first),
        ),
      ),
    );
  }
}

// ─── Small pieces ────────────────────────────────────────────────────────────

/// Honest caveats about what the board may not show.
class _BoardNotes extends StatelessWidget {
  const _BoardNotes({required this.board});
  final TodayBoard board;

  @override
  Widget build(BuildContext context) {
    final notes = <String>[
      if (board.laterCount > 0)
        'Дараагийн өдрүүдэд ${board.laterCount} засварын хуудас товлогдсон',
      if (board.truncated) 'Зарим засварын хуудас харагдахгүй байж магадгүй',
      if (board.completedMayBeIncomplete)
        'Дууссан засварын хуудасны жагсаалт дутуу байж магадгүй',
    ];
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: context.opsTextHint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              notes.join(' · '),
              style: TextStyle(fontSize: 12, color: context.opsTextSecondary),
            ),
          ),
          TextButton(
            onPressed: () => AppNav.go('/orders'),
            child: const Text('Бүх засварын хуудас'),
          ),
        ],
      ),
    );
  }
}

class _LaneDot extends StatelessWidget {
  const _LaneDot({required this.lane});
  final TodayLane lane;

  @override
  Widget build(BuildContext context) {
    final status = switch (lane) {
      TodayLane.waiting => OrderStatus.SCHEDULED,
      TodayLane.inProgress => OrderStatus.IN_PROGRESS,
      TodayLane.completed => OrderStatus.COMPLETED,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: context.orderStatusColor(status),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: context.opsCardBg,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      '$count',
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

class _EmptyLane extends StatelessWidget {
  const _EmptyLane({required this.lane});
  final TodayLane lane;

  @override
  Widget build(BuildContext context) {
    final text = switch (lane) {
      TodayLane.waiting => 'Хүлээгдэж буй засварын хуудас алга',
      TodayLane.inProgress => 'Одоогоор хийгдэж буй ажил алга',
      TodayLane.completed => 'Өнөөдөр дууссан засварын хуудас алга',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.opsTextHint),
        ),
      ),
    );
  }
}

String _upcomingLabel(AppointmentSummary a) {
  final p = a.displayVehicle?.plate;
  if (p != null && p.isNotEmpty) return plateLabel(p);
  return a.customer?.fullName ?? 'Цаг захиалга';
}
