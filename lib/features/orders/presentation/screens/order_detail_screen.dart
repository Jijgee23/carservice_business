import 'package:carservice_business/core/utils/price_input.dart';
import 'package:carservice_business/app/shell/shell_chrome.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/core/services/service_catalog_service.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_payment_screen.dart';
import 'package:carservice_business/core/domain/service_catalog.dart'
    hide DiagnosticTemplateSummary, DiagnosticType, StockLevel;
import 'package:carservice_business/core/domain/service_catalog.dart'
    as catalog
    show DiagnosticTemplateSummary;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/cash/data/cash_repository.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_detail_controller.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_payment_controller.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_item_controller.dart';
import 'package:carservice_business/features/orders/presentation/widgets/detail/order_detail_widgets.dart';
import 'package:carservice_business/features/orders/presentation/widgets/detail/order_item_widgets.dart';
import 'package:carservice_business/features/orders/presentation/widgets/diagnostic_template_picker_sheet.dart';
import 'package:carservice_business/features/orders/domain/postpaid_settlement.dart';
import 'package:carservice_business/features/orders/presentation/widgets/list/order_list_widgets.dart';
import 'package:carservice_business/features/orders/presentation/widgets/order_status_prompt.dart';
import 'package:carservice_business/features/orders/presentation/widgets/intake/order_intake_view.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/new_inspection_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/report_detail_screen.dart';
import 'package:carservice_business/features/diagnostics/data/diagnostic_repository.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

DateTime clampOrderDatePickerInitial(
  DateTime value, {
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final date = DateTime(value.year, value.month, value.day);
  final first = DateTime(firstDate.year, firstDate.month, firstDate.day);
  final last = DateTime(lastDate.year, lastDate.month, lastDate.day);
  if (date.isBefore(first)) return first;
  if (date.isAfter(last)) return last;
  return date;
}

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  final User? user;

  const OrderDetailScreen({super.key, required this.orderId, this.user});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderItemController? _itemController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_itemController != null) return;
    final detail = context.read<OrderDetailController>();
    _itemController = OrderItemController(
      repo: detail.repo,
      orderId: widget.orderId,
      detailController: detail,
      listController: detail.listController,
    );
  }

  @override
  void dispose() {
    _itemController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<OrderDetailController>();
      controller.load(widget.orderId);
      if (_canAssign(widget.user ?? Authenticator.user)) {
        controller.loadAssignableUsers();
      }
    });
  }

  bool _canView(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.view') == true ||
      user?.role?.permissions.contains('orders.viewOwn') == true;

  bool _canEdit(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.edit') == true ||
      user?.role?.permissions.contains('orders.editOwn') == true;

  bool _canAssign(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.assign') == true;

  bool _canDelete(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.delete') == true;

  bool _canViewPayments(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('payments.view') == true;

  bool _canItemHistory(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.itemHistory') == true;

  bool _canItemPrice(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.itemPrice') == true;

  bool _canItemStatus(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('orders.itemStatus') == true;

  bool _canEditItem(User? user, ServiceOrderDetail order) {
    if (user?.isOwner == true ||
        user?.role?.permissions.contains('orders.edit') == true) {
      return true;
    }
    return user?.role?.permissions.contains('orders.editOwn') == true &&
        order.assignedTo?.id == user?.id;
  }

  Future<void> _changeStatus(OrderStatus status) async {
    final controller = context.read<OrderDetailController>();
    final decision = await promptOrderStatusChange(
      context,
      status,
      order: controller.order,
    );
    if (decision == null || !mounted) return;
    final result = await controller.updateStatus(
      status,
      durationMinutes: decision.durationMinutes,
    );
    if (!mounted) return;
    if (result case Err(:final error)) messageError(error.display);
  }

  Future<void> _assign(String userId) async {
    final result = await context.read<OrderDetailController>().updateAssignment(
      userId,
    );
    if (!mounted) return;
    if (result case Err(:final error)) messageError(error.display);
  }

  Future<void> _setExpectedFinish() async {
    final order = context.read<OrderDetailController>().order;
    if (order == null) return;
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day - 1);
    final lastDate = DateTime(now.year, now.month, now.day + 365);
    final base = order.expectedFinishAt ?? now;
    final initialDate = clampOrderDatePickerInitial(
      base,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    final next = await AppDatePicker.dateTime(
      context,
      initial: DateTime(
        initialDate.year,
        initialDate.month,
        initialDate.day,
        base.hour,
        base.minute,
      ),
      firstDate: firstDate,
      lastDate: lastDate,
      startHour: 0,
      endHour: 23,
    );
    if (next == null || !mounted) return;
    var result = await context
        .read<OrderDetailController>()
        .reviseExpectedFinish(next);
    if (!mounted) return;
    if (result case Err(:final error)
        when OrderDetailController.requiresConfirmation(error)) {
      final confirm = await ConfirmSheet.show(
        context,
        title: 'Хугацаанаас хэтрэх үү?',
        message: error.message,
        confirmLabel: 'Үргэлжлүүлэх',
      );
      if (!confirm || !mounted) return;
      result = await context.read<OrderDetailController>().reviseExpectedFinish(
        next,
        confirmed: true,
      );
    }
    if (!mounted) return;
    if (result case Err(:final error)) messageError(error.display);
  }

  Future<void> _reschedule() async {
    final order = context.read<OrderDetailController>().order;
    if (order == null) return;
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year, now.month, now.day + 365);
    final base = order.scheduledAt ?? now;
    final initialDate = clampOrderDatePickerInitial(
      base,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    final next = await AppDatePicker.dateTime(
      context,
      initial: DateTime(
        initialDate.year,
        initialDate.month,
        initialDate.day,
        base.hour,
        base.minute,
      ),
      firstDate: firstDate,
      lastDate: lastDate,
      startHour: 0,
      endHour: 23,
    );
    if (next == null || !mounted) return;
    var result = await context.read<OrderDetailController>().rescheduleOrder(
      next,
    );
    if (!mounted) return;
    if (result case Err(:final error)
        when OrderDetailController.requiresConfirmation(error)) {
      final confirm = await ConfirmSheet.show(
        context,
        title: 'Ажлын цагаас гадуур байна',
        message: error.message,
        confirmLabel: 'Үргэлжлүүлэх',
      );
      if (!confirm || !mounted) return;
      result = await context.read<OrderDetailController>().rescheduleOrder(
        next,
        confirmed: true,
      );
    }
    if (!mounted) return;
    if (result case Err(:final error)) messageError(error.display);
  }

  Future<void> _delete() async {
    if (context.read<OrderDetailController>().order?.hasPaidPayment == true) {
      messageError(
        paidLockReason(context.read<OrderDetailController>().order!),
      );
      return;
    }
    final confirm = await ConfirmSheet.show(
      context,
      title: 'Засварын хуудсыг устгах уу?',
      message: 'Энэ үйлдлийг буцаах боломжгүй.',
      confirmLabel: 'Устгах',
      isDangerous: true,
    );
    if (!confirm || !mounted) return;
    final result = await context.read<OrderDetailController>().deleteOrder();
    if (!mounted) return;
    if (result case Ok()) {
      if (context.canPop()) AppNav.back();
    } else if (result case Err(:final error)) {
      messageError(error.display);
    }
  }

  Future<void> _openPayment() async {
    await OrderPaymentScreen.open(
      context,
      orderId: widget.orderId,
      user: widget.user,
    );
    if (mounted) await context.read<OrderDetailController>().refresh();
  }

  Future<void> _addItem() async {
    final provider = _itemController;
    if (provider == null) return;
    await AppNav.to(
      ItemFormScreen(
        orderId: widget.orderId,
        provider: provider,
        canEditFields: true,
        // Сервер `orders.itemPrice`-гүйд илгээсэн үнийг үл тоож, каталогийн
        // үнийг ашигладаг — UI-д ч үнэ засахыг хаана.
        canEditPrice: _canItemPrice(widget.user ?? Authenticator.user),
      ),
    );
  }

  Future<void> _editItem(ServiceItem item) async {
    final provider = _itemController;
    if (provider == null) return;
    final user = widget.user ?? Authenticator.user;
    final order = context.read<OrderDetailController>().order;
    if (order == null) return;
    await AppNav.to(
      ItemFormScreen(
        orderId: widget.orderId,
        provider: provider,
        editItem: item,
        canEditFields: _canEditItem(user, order),
        canEditPrice: _canEditItem(user, order) && _canItemPrice(user),
        paidLocked: order.hasPaidPayment,
        paidLockReason: paidLockReason(order),
      ),
    );
  }

  Future<void> _openNewInspection({required ServiceItem item}) async {
    final order = context.read<OrderDetailController>().order;
    if (order == null) return;
    await openOrderDiagnostic(
      context,
      orderId: order.id,
      item: item,
      vehicle: order.vehicle,
      customer: order.customer,
    );
    if (mounted) {
      await context.read<OrderDetailController>().refresh();
    }
  }

  Future<void> _cancelItem(ServiceItem item) async {
    final ok = await ConfirmSheet.show(
      context,
      title: 'Мөр цуцлах уу?',
      message: '"${item.description}" мөрийг цуцлах уу? Түүхэнд хадгалагдана.',
      confirmLabel: 'Цуцлах',
      icon: Icons.cancel_outlined,
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    final result = await _itemController?.cancel(item.id);
    if (!mounted) return;
    if (result case Err(:final error)) {
      messageError(error.display);
    }
  }

  Future<void> _changeItemStatus(
    ServiceItem item,
    ServiceItemStatus status,
  ) async {
    if (status == ServiceItemStatus.COMPLETED && lineNeedsReport(item)) {
      messageError('Оношилгооны тайлан бөглөсний дараа дуусгана уу.');
      return;
    }
    if (!await _ensureOrderStarted()) return;
    final result = await _itemController?.changeStatus(item.id, status);
    if (!mounted) return;
    if (result case Err(:final error)) {
      messageError(error.display);
    }
  }

  /// Line progress only moves on an IN_PROGRESS order (server:
  /// `ORDER_STATUS_INVALID`). On a SCHEDULED order a line change first asks
  /// to start the order, with the same prompt as the "Төлөв" row.
  Future<bool> _ensureOrderStarted() async {
    final controller = context.read<OrderDetailController>();
    final order = controller.order;
    if (order == null || order.status != OrderStatus.SCHEDULED) return true;
    final decision = await promptOrderStatusChange(
      context,
      OrderStatus.IN_PROGRESS,
      order: order,
    );
    if (decision == null || !mounted) return false;
    final result = await controller.updateStatus(
      OrderStatus.IN_PROGRESS,
      durationMinutes: decision.durationMinutes,
    );
    if (!mounted) return false;
    if (result case Err(:final error)) {
      messageError(error.display);
      return false;
    }
    return true;
  }

  Future<void> _completeAllItems(
    List<ServiceItem> items, {
    required int skipped,
  }) async {
    final ok = await ConfirmSheet.show(
      context,
      title: 'Бүх ажлыг дуусгах уу?',
      message: [
        '${items.length} ажлын мөрийг "Дууссан" болгоно.',
        if (skipped > 0) '$skipped оношилгооны мөр тайлангүй тул алгасна.',
      ].join('\n'),
      confirmLabel: 'Дуусгах',
      icon: Icons.done_all_rounded,
      iconColor: context.opsGood,
    );
    if (!ok || !mounted) return;
    final result = await _itemController?.completeAll([
      for (final item in items) item.id,
    ]);
    if (!mounted || result == null) return;
    if (result.firstError case final error?) {
      messageError(
        result.done > 0
            ? '${result.done}/${items.length} мөр дууссан. ${error.display}'
            : error.display,
      );
    }
  }

  Future<void> _showItemHistory() async {
    final controller = _itemController;
    if (controller == null) return;
    await AppNav.sheet<void>(
      ChangeNotifierProvider.value(
        value: controller,
        child: OrderItemHistorySheet(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrderDetailController>();
    final user = widget.user ?? Authenticator.user;
    if (!_canView(user)) {
      return const Scaffold(
        body: Center(child: Text('Засварын хуудас харах эрхгүй')),
      );
    }

    switch (provider.detailState) {
      case AsyncLoading():
        return Scaffold(appBar: AppBar(), body: const AppLoading());
      case AsyncError(:final error):
        return Scaffold(
          appBar: AppBar(),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmptyState(message: error.display, icon: Icons.error_outline),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: provider.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Дахин оролдох'),
                ),
              ],
            ),
          ),
        );
      case AsyncData(:final value):
        return _buildDetail(context, value, provider, user);
    }
  }

  Widget _buildDetail(
    BuildContext context,
    ServiceOrderDetail o,
    OrderDetailController provider,
    User? user,
  ) {
    final numFmt = NumberFormat('#,###');
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm');
    final locked = o.status.isLocked;
    final itemEdit = _canEditItem(user, o);
    final activeItems = o.items
        .where((item) => item.status != ServiceItemStatus.CANCELLED)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plateLabel(o.vehicle.plate, o.vehicle.vin),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              [
                '#${o.number}',
                if (formerPlate(o.plateSnapshot, o.vehicle.plate)
                    case final old?)
                  'хуучин: $old',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.refresh,
          ),
          const ShellNotificationBell(),
        ],
      ),
      body: _detailList(
        context,
        o,
        provider,
        user,
        numFmt,
        dateFmt,
        locked,
        itemEdit,
        activeItems,
      ),
    );
  }

  Widget _itemsCard(
    BuildContext context,
    ServiceOrderDetail o,
    User? user,
    bool locked,
    bool itemEdit,
    List<ServiceItem> activeItems,
  ) {
    final items = _itemController!;
    ServiceItemStatus statusOf(ServiceItem item) =>
        items.pendingStatusOf(item.id) ?? item.status;
    final canLineStatus = itemEdit && _canItemStatus(user);
    final tracked = progressItems(o.items);
    final open = tracked
        .where((item) => statusOf(item) != ServiceItemStatus.COMPLETED)
        .toList(growable: false);
    // Diagnostic lines without a report can't be completed; the bulk action
    // leaves them out and says so.
    final completable = o.status == OrderStatus.IN_PROGRESS && canLineStatus
        ? open
              .where(
                (item) =>
                    !lineNeedsReport(item) && !items.isStatusBusy(item.id),
              )
              .toList(growable: false)
        : const <ServiceItem>[];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Ажлын мөрүүд', style: context.textStyles.h3),
              ),
              if (_canItemHistory(user))
                TextButton.icon(
                  onPressed: _showItemHistory,
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Түүх'),
                ),
              if (o.status.canAddItems && itemEdit)
                TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Нэмэх'),
                ),
            ],
          ),
          if (tracked.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OrderProgressView(
                    key: const ValueKey('items_progress'),
                    progress: OrderProgressSummary(
                      total: tracked.length,
                      completed: tracked.length - open.length,
                    ),
                  ),
                ),
                if (completable.length >= 2) ...[
                  const SizedBox(width: 12),
                  TextButton.icon(
                    key: const ValueKey('items_complete_all_button'),
                    onPressed: () => _completeAllItems(
                      completable,
                      skipped: open.where(lineNeedsReport).length,
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text('Бүгдийг дуусгах'),
                  ),
                ],
              ],
            ),
          ],
          if (activeItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Ажлын мөр байхгүй',
                style: context.textStyles.caption,
              ),
            )
          else ...[
            const Divider(height: 16),
            for (final kind in ItemKind.values)
              if (activeItems.any((item) => item.kind == kind)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text(
                    kind.label,
                    style: context.textStyles.caption.copyWith(
                      color: context.itemKindColor(kind),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...activeItems
                    .where((item) => item.kind == kind)
                    .map(
                      (item) => OrderItemCard(
                        item: item,
                        locked: locked,
                        paidLocked: o.hasPaidPayment,
                        paidLockReason: paidLockReason(o),
                        canEdit: o.status.canAddItems && itemEdit,
                        canPrice:
                            o.status.canAddItems &&
                            itemEdit &&
                            _canItemPrice(user),
                        // A SCHEDULED order is started first when a line
                        // moves (_ensureOrderStarted), so that needs the
                        // order status permission too.
                        canStatus:
                            (o.status == OrderStatus.IN_PROGRESS ||
                                (o.status == OrderStatus.SCHEDULED &&
                                    _canEdit(user))) &&
                            item.kind != ItemKind.PART &&
                            canLineStatus,
                        pendingStatus: items.pendingStatusOf(item.id),
                        statusBusy: items.isStatusBusy(item.id),
                        diagnosticEditable:
                            o.status == OrderStatus.IN_PROGRESS && itemEdit,
                        onEdit: () => _editItem(item),
                        onCancel: () => _cancelItem(item),
                        onStatus: (status) => _changeItemStatus(item, status),
                        onDiagnosticCreate: item.kind == ItemKind.DIAGNOSTIC
                            ? () => _openNewInspection(item: item)
                            : null,
                        onDiagnosticFill: item.kind == ItemKind.DIAGNOSTIC
                            ? () => _openNewInspection(item: item)
                            : null,
                        onDiagnosticView: item.diagnosticReportId == null
                            ? null
                            : () => AppNav.to(
                                ReportDetailScreen(
                                  reportId: item.diagnosticReportId!,
                                  deleteLocked: isLineCompletedLocked(item),
                                ),
                              ),
                      ),
                    ),
              ],
            Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Нийт дүн', style: context.textStyles.bodyMedium),
                Text(
                  _moneyText(o.totalAmountMoney),
                  style: context.textStyles.h3.copyWith(
                    color: context.opsAccent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailList(
    BuildContext context,
    ServiceOrderDetail o,
    OrderDetailController provider,
    User? user,
    NumberFormat numFmt,
    DateFormat dateFmt,
    bool locked,
    bool itemEdit,
    List<ServiceItem> activeItems,
  ) {
    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        children: [
          if (provider.detailRefreshError case final error?) ...[
            _DetailRefreshWarning(
              message: error.display,
              onRetry: provider.refresh,
            ),
            const SizedBox(height: 14),
          ],

          // ─── Locked banner ───────────────────────────────────────────
          if (locked) ...[
            _LockedBanner(status: o.status),
            const SizedBox(height: 14),
          ],

          // ─── Summary ─────────────────────────────────────────────────
          OrderDetailSummaryCard(
            order: o,
            // The app bar already shows "#<number>"; keep it to one place.
            showNumber: false,
          ),
          const SizedBox(height: 14),

          if (o.isInternal) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: OrderInternalTag(),
            ),
            const SizedBox(height: 14),
          ],
          // ─── Status ──────────────────────────────────────────────────
          OrderStatusField(
            current: o.status,
            enabled: _canEdit(user),
            onSelect: _changeStatus,
          ),
          const SizedBox(height: 14),
          // ─── Items ───────────────────────────────────────────────────
          ListenableBuilder(
            listenable: _itemController!,
            builder: (context, _) =>
                _itemsCard(context, o, user, locked, itemEdit, activeItems),
          ),
          const SizedBox(height: 14),
          // ─── Payment ──────────────────────────────────────────────────
          if (_canViewPayments(user) && o.isInternal) ...[
            AppCard(
              key: const ValueKey('order_internal_payment_note'),
              child: Text(
                internalOrderPaymentNote,
                style: context.textStyles.caption,
              ),
            ),
            const SizedBox(height: 14),
          ] else if (_canViewPayments(user)) ...[
            _PaymentTile(
              key: const ValueKey('order_payment_entry'),
              order: o,
              numFmt: numFmt,
              onTap: _openPayment,
            ),
            const SizedBox(height: 14),
          ],
          OrderAssignmentSection(
            order: o,
            enabled: _canAssign(user),
            state: provider.assignableUsersState,
            loading: provider.loadingAssignableUsers,
            error: provider.assignableUsersError,
            onChanged: _assign,
          ),
          const SizedBox(height: 14),
          OrderScheduleSection(
            order: o,
            enabled: _canEdit(user) && !locked,
            onExpectedFinish: _setExpectedFinish,
            onReschedule: _reschedule,
          ),
          const SizedBox(height: 14),

          // ─── Хүлээн авах (унших-зөвхөн; байхгүй бол нуугдана) ────────
          if (o.intake != null) ...[
            OrderIntakeTile(intake: o.intake),
            const SizedBox(height: 14),
          ],

          // ─── Linked reports ──────────────────────────────────────────
          _DiagnosticsSection(
            order: o,
            dateFmt: dateFmt,
            locked: locked || o.status != OrderStatus.IN_PROGRESS || !itemEdit,
            onOpenReport: (id) => AppNav.to(
              ReportDetailScreen(
                reportId: id,
                deleteLocked: o.items.any(
                  (i) => i.diagnosticReportId == id && isLineCompletedLocked(i),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ─── Delete ──────────────────────────────────────────────────
          // Last on the page, away from the everyday actions above.
          if (_canDelete(user)) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                key: const ValueKey('order_detail_delete'),
                onPressed: o.hasPaidPayment ? null : _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.opsDanger,
                  side: BorderSide(color: context.opsDanger),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                  ),
                ),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text(
                  'Засварын хуудас устгах',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (o.hasPaidPayment)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  paidLockReason(o),
                  textAlign: TextAlign.center,
                  style: context.textStyles.caption,
                ),
              ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DetailRefreshWarning extends StatelessWidget {
  const _DetailRefreshWarning({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('order_detail_refresh_warning'),
      padding: const EdgeInsets.all(AppDimens.paddingMD),
      decoration: BoxDecoration(
        color: context.opsWarning.withValues(alpha: 0.12),
        border: Border.all(color: context.opsWarning.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.sync_problem_outlined,
            color: context.opsWarning,
            size: AppDimens.iconMD,
          ),
          const SizedBox(width: AppDimens.paddingSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Шинэ мэдээллийг татаж чадсангүй',
                  style: context.textStyles.bodyMedium,
                ),
                const SizedBox(height: AppDimens.paddingXS),
                Text(
                  '$message. Доорх мэдээлэл хуучирсан байж болзошгүй.',
                  style: context.textStyles.caption,
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('order_detail_refresh_retry'),
            onPressed: onRetry,
            tooltip: 'Дахин оролдох',
            icon: const Icon(Icons.refresh),
            color: context.opsWarning,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ─── Locked banner ────────────────────────────────────────────────────────────

class _LockedBanner extends StatelessWidget {
  final OrderStatus status;
  const _LockedBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final isCompleted = status == OrderStatus.COMPLETED;
    final bg = isCompleted
        ? context.opsGood.withOpacity(0.12)
        : context.opsDanger.withOpacity(0.12);
    final fg = isCompleted ? context.opsGood : context.opsDanger;
    final title = isCompleted
        ? 'Засварын хуудас дууссан'
        : 'Засварын хуудас цуцлагдсан';
    final sub = isCompleted
        ? 'Дууссан засварын хуудсанд өөрчлөлт хийх боломжгүй.'
        : 'Цуцлагдсан засварын хуудсанд өөрчлөлт хийх боломжгүй.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: fg.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_outline_rounded, size: 17, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.textStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: context.textStyles.label.copyWith(
                    color: fg.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final PaymentStatus status;
  const _PaymentChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.paymentStatusBackground(status),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        border: Border.all(
          color: context.paymentStatusColor(status).withOpacity(0.35),
        ),
      ),
      child: Text(
        status.label,
        style: context.textStyles.label.copyWith(
          fontWeight: FontWeight.w600,
          color: context.paymentStatusColor(status),
        ),
      ),
    );
  }
}

// ─── Payment summary tile ──────────────────────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  final ServiceOrderDetail order;
  final NumberFormat numFmt;
  final VoidCallback onTap;
  const _PaymentTile({
    super.key,
    required this.order,
    required this.numFmt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Keep payment display on the lossless Money representation. The legacy
    // double fields would round-trip through binary floating point and the old
    // integer formatting silently truncated fractional amounts.
    final totals = order.paymentTotals;
    final total = totals?.totalAmountMoney ?? order.totalAmountMoney;
    final paid = totals?.paidAmountMoney ?? order.paidAmountMoney;
    final remaining =
        totals?.remainingAmountMoney ??
        (total == null || paid == null
            ? null
            : Money(_subtractMoneyStrings(total.raw, paid.raw)));
    final status = totals?.paymentStatus ?? order.paymentStatus;
    final isPaid = status == PaymentStatus.PAID;
    final hasRemaining =
        remaining != null && _subtractMoneyStrings(remaining.raw, '0') != '0';

    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Icon(Icons.payments_outlined, size: 18, color: context.opsAccent),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Төлбөр', style: context.textStyles.h3),
                        const SizedBox(width: 8),
                        _PaymentChip(status: status),
                      ],
                    ),
                    SizedBox(height: 3),
                    Text(
                      isPaid
                          ? '${_moneyText(total)} · Бүрэн төлөгдсөн'
                          : hasRemaining
                          ? 'Үлдэгдэл: ${_moneyText(remaining)}'
                          : _moneyText(total),
                      style: context.textStyles.caption.copyWith(
                        color: isPaid
                            ? context.opsGood
                            : hasRemaining
                            ? context.opsDanger
                            : context.opsTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: context.opsTextHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _moneyText(Money? money) => money == null ? '—' : '${money.raw}₮';

String _subtractMoneyStrings(String left, String right) {
  final a = _moneyParts(left);
  final b = _moneyParts(right);
  final scale = a.$2.length > b.$2.length ? a.$2.length : b.$2.length;
  final multiplier = BigInt.from(10).pow(scale);
  final av = BigInt.parse(a.$1) * multiplier + _fractionDigits(a.$2, scale);
  final bv = BigInt.parse(b.$1) * multiplier + _fractionDigits(b.$2, scale);
  final result = av - bv;
  if (result <= BigInt.zero) return '0';
  final raw = result.toString().padLeft(scale + 1, '0');
  if (scale == 0) return raw;
  final split = raw.length - scale;
  return '${raw.substring(0, split)}.${raw.substring(split)}'.replaceFirst(
    RegExp(r'\.0+$'),
    '',
  );
}

(String, String) _moneyParts(String value) {
  final pieces = value.split('.');
  return (pieces.first, pieces.length == 1 ? '' : pieces.last);
}

// ─── Add item bottom sheet ─────────────────────────────────────────────────────

// ─── Item form screen (add + edit) ────────────────────────────────────────────

class ItemFormScreen extends StatefulWidget {
  final String orderId;
  final OrderItemController provider;
  final ServiceItem? editItem;
  final bool canEditFields;
  final bool canEditPrice;

  /// The order has a paid payment: the server refuses price/qty/kind changes
  /// (`PAID_PAYMENT_EXISTS`), so those inputs are read-only in edit mode.
  final bool paidLocked;
  final String paidLockReason;
  const ItemFormScreen({
    super.key,
    required this.orderId,
    required this.provider,
    this.canEditFields = true,
    this.canEditPrice = true,
    this.paidLocked = false,
    this.paidLockReason = paidLockHint,
    this.editItem,
  });

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  // Search (add mode only)
  final _searchCtrl = TextEditingController();
  List<CatalogService> _allResults = [];
  ServiceKind? _kindFilter;
  String? _laborCategoryFilter;
  bool _searching = false;
  String? _selectedServiceId;
  // Оношилгоо нь Service биш DiagnosticTemplate — сонгосон бол serviceId биш
  // diagnosticTemplateId-аар илгээнэ (сервер DIAGNOSTIC service-ийг хүлээж авдаггүй).
  final Set<String> _templateIds = {};
  int _fetchSeq = 0;
  String? _selectedTemplateId;
  bool _serviceSelected = false;
  String? _validationError;

  // Form
  ItemKind _kind = ItemKind.LABOR;
  final _descCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  bool _saving = false;

  bool get _isEdit => widget.editItem != null;
  bool get _moneyLocked => _isEdit && widget.paidLocked;
  bool get _effectiveCanEditPrice => widget.canEditPrice && !_moneyLocked;

  List<LaborCategory> get _laborCategories {
    final seen = <String>{};
    final result = <LaborCategory>[];
    for (final svc in _allResults) {
      if (svc.type == ServiceKind.LABOR &&
          svc.laborCategory != null &&
          seen.add(svc.laborCategory!.id)) {
        result.add(svc.laborCategory!);
      }
    }
    return result;
  }

  List<CatalogService> get _filtered {
    var list = _kindFilter == null
        ? _allResults
        : _allResults.where((s) => s.type == _kindFilter).toList();
    if (_laborCategoryFilter != null) {
      list = list
          .where((s) => s.laborCategory?.id == _laborCategoryFilter)
          .toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final item = widget.editItem!;
      _kind = item.kind;
      _descCtrl.text = item.description;
      _qtyCtrl.text = item.quantityMoney?.raw ?? item.quantity.toString();
      _priceCtrl.text = formatPriceInput(
        item.unitPriceMoney?.raw ?? item.unitPrice.toString(),
      );
      _selectedServiceId = item.serviceId;
    } else {
      _loadAll();
      _searchCtrl.addListener(_onSearch);
    }
  }

  @override
  void dispose() {
    if (!_isEdit) _searchCtrl.removeListener(_onSearch);
    _searchCtrl.dispose();
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() => _fetch('');

  void _onSearch() => _fetch(_searchCtrl.text.trim());

  Future<void> _fetch(String q) async {
    setState(() => _searching = true);
    final seq = ++_fetchSeq;
    // Аль нэг нь алдаа шидвэл нөгөөг нь харуулж, spinner-ийг заавал зогсооно.
    final servicesF = ServiceCatalogService.getServices(q: q)
        .catchError((Object e, StackTrace st) {
          if (kDebugMode) debugPrint('ItemForm services load failed: $e\n$st');
          return <CatalogService>[];
        });
    final templatesF = ServiceCatalogService.getTemplates(q: q)
        .catchError((Object e, StackTrace st) {
          if (kDebugMode) debugPrint('ItemForm templates load failed: $e\n$st');
          return <catalog.DiagnosticTemplateSummary>[];
        });
    final services = await servicesF;
    final templates = await templatesF;
    if (mounted && seq == _fetchSeq) {
      setState(() {
        _templateIds
          ..clear()
          ..addAll(templates.map((t) => t.id));
        _allResults = [
          ...services.where((s) => s.type != ServiceKind.DIAGNOSTIC),
          ...templates.map(
            (t) => CatalogService(
              id: t.id,
              type: ServiceKind.DIAGNOSTIC,
              name: t.name,
              price: t.price ?? 0,
              description: t.description,
              isActive: t.isActive,
            ),
          ),
        ];
        _searching = false;
      });
    }
  }

  ItemKind _toItemKind(ServiceKind k) {
    switch (k) {
      case ServiceKind.GOODS:
        return ItemKind.PART;
      case ServiceKind.DIAGNOSTIC:
        return ItemKind.DIAGNOSTIC;
      case ServiceKind.LABOR:
        return ItemKind.LABOR;
    }
  }

  void _selectService(CatalogService svc) {
    final isTemplate = _templateIds.contains(svc.id);
    setState(() {
      _selectedServiceId = isTemplate ? null : svc.id;
      _selectedTemplateId = isTemplate ? svc.id : null;
      _kind = _toItemKind(svc.type);
      _descCtrl.text = svc.name;
      _priceCtrl.text = formatPriceInput(svc.price.toString());
      if (_qtyCtrl.text.isEmpty) _qtyCtrl.text = '1';
      _serviceSelected = true;
    });
    FocusScope.of(context).unfocus();
  }

  void _clearService() {
    setState(() {
      _selectedServiceId = null;
      _selectedTemplateId = null;
      _serviceSelected = false;
      _searchCtrl.clear();
      _descCtrl.clear();
      _priceCtrl.clear();
      _qtyCtrl.text = '1';
      _kind = ItemKind.LABOR;
    });
    _loadAll();
  }

  Future<void> _save() async {
    final desc = _descCtrl.text.trim();
    final quantityResult = ItemMoneyValidation.quantity(_qtyCtrl.text);
    final priceResult = ItemMoneyValidation.price(_priceCtrl.text);
    if (desc.isEmpty) {
      setState(() => _validationError = 'Тайлбар оруулна уу.');
      return;
    }
    if (!quantityResult.isValid || !priceResult.isValid) {
      setState(() {
        _validationError = quantityResult.error ?? priceResult.error;
      });
      return;
    }
    final qty = quantityResult.value!;
    final price = priceResult.value!;
    if (_isEdit && !widget.canEditFields && !_effectiveCanEditPrice) return;
    // Үнэ оруулах эрхгүй бол гараар (каталоггүй) мөр нэмэх боломжгүй.
    if (!_isEdit &&
        !widget.canEditPrice &&
        _selectedServiceId == null &&
        _selectedTemplateId == null) {
      setState(
        () => _validationError = 'Каталогоос үйлчилгээ/сэлбэг сонгоно уу — гараар үнэ оруулах эрх байхгүй.',
      );
      return;
    }
    setState(() => _validationError = null);
    setState(() => _saving = true);
    Result<ServiceItem>? result;
    if (!_isEdit) {
      result = await widget.provider.add(
        kind: _kind,
        description: desc,
        quantity: qty,
        unitPrice: price,
        serviceId: _selectedServiceId,
        diagnosticTemplateId: _selectedTemplateId,
      );
    } else {
      final item = widget.editItem!;
      if (widget.canEditFields) {
        result = await widget.provider.edit(
          itemId: item.id,
          kind: _kind,
          description: desc,
          quantity: qty,
          unitPrice: _effectiveCanEditPrice ? price : null,
        );
      }
      final oldPrice = item.unitPriceMoney?.raw ?? item.unitPrice.toString();
      if (!widget.canEditFields &&
          _effectiveCanEditPrice &&
          price.raw != oldPrice) {
        result = await widget.provider.changePrice(item.id, price);
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (result case Ok()) {
      if (!_isEdit && widget.provider.lastAddMerged) {
        messageComplete('Тоо нэмэгдлээ');
      }
      AppNav.back(true);
    } else if (result case Err(:final error)) {
      messageError(error.display);
    }
  }

  @override
  Widget build(BuildContext context) {
    final numFmt = NumberFormat('#,###');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Мөр засах' : 'Мөр нэмэх'),
        actions: const [ShellNotificationBell()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Service search (add mode only) ─────────────────────
            if (!_isEdit) ...[
              if (!_serviceSelected) ...[
                // Search field
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Үйлчилгээ хайх...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    // Fixed box: AppLoading's Center would otherwise expand
                    // across the whole field and squeeze the typed text out
                    // of view.
                    suffixIcon: _searching
                        ? const SizedBox.square(
                            dimension: 48,
                            child: AppLoading(size: 14),
                          )
                        : _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              _loadAll();
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Kind filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _KindFilterChip(
                        label: 'Бүгд',
                        active: _kindFilter == null,
                        onTap: () => setState(() {
                          _kindFilter = null;
                          _laborCategoryFilter = null;
                        }),
                      ),
                      ...ServiceKind.values.map(
                        (k) => _KindFilterChip(
                          label: k.label,
                          active: _kindFilter == k,
                          color: context.itemKindColor(_toItemKind(k)),
                          onTap: () => setState(() {
                            _kindFilter = _kindFilter == k ? null : k;
                            _laborCategoryFilter = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                // Labor category chips (LABOR kind сонгогдсон + категори байвал)
                if (_kindFilter == ServiceKind.LABOR &&
                    _laborCategories.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _KindFilterChip(
                          label: 'Бүгд',
                          active: _laborCategoryFilter == null,
                          onTap: () =>
                              setState(() => _laborCategoryFilter = null),
                        ),
                        ..._laborCategories.map(
                          (cat) => _KindFilterChip(
                            label: cat.name,
                            active: _laborCategoryFilter == cat.id,
                            onTap: () => setState(
                              () => _laborCategoryFilter =
                                  _laborCategoryFilter == cat.id
                                  ? null
                                  : cat.id,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // Results list
                if (_filtered.isNotEmpty)
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final svc = _filtered[i];
                        final ik = _toItemKind(svc.type);
                        return InkWell(
                          onTap: () => _selectService(svc),
                          borderRadius: i == 0
                              ? const BorderRadius.vertical(
                                  top: Radius.circular(AppDimens.radiusLG),
                                )
                              : i == _filtered.length - 1
                              ? const BorderRadius.vertical(
                                  bottom: Radius.circular(AppDimens.radiusLG),
                                )
                              : BorderRadius.zero,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context
                                        .itemKindColor(ik)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(
                                      AppDimens.radiusSM,
                                    ),
                                  ),
                                  child: Text(
                                    ik.label,
                                    style: context.textStyles.label.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: context.itemKindColor(ik),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        svc.name,
                                        style: context.textStyles.bodyMedium,
                                      ),
                                      if (svc.laborCategory != null)
                                        Text(
                                          svc.laborCategory!.name,
                                          style: context.textStyles.caption,
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '${numFmt.format(svc.price.toInt())}₮',
                                  style: context.textStyles.captionMedium
                                      .copyWith(color: context.opsAccent),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: context.opsTextHint,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else if (!_searching)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Үр дүн олдсонгүй',
                        style: context.textStyles.caption,
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'эсвэл гар аргаар бөглөх',
                        style: context.textStyles.caption.copyWith(
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
              ] else ...[
                // Selected service badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.opsAccent.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    border: Border.all(
                      color: context.opsAccent.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: context.opsAccent,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _descCtrl.text,
                          style: context.textStyles.bodyMedium.copyWith(
                            color: context.opsAccent,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _clearService,
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: context.opsAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],

            // ── Kind selector ────────────────────────────────────────
            Text('Мөрийн төрөл', style: context.textStyles.label),
            SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ItemKind.values.map((k) {
                  final active = k == _kind;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _moneyLocked
                          ? null
                          : () => setState(() {
                              _kind = k;
                              _selectedServiceId = null;
                            }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? context.itemKindColor(k).withOpacity(0.12)
                              : context.opsSurface,
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusFull,
                          ),
                          border: Border.all(
                            color: active
                                ? context.itemKindColor(k)
                                : context.opsDivider,
                          ),
                        ),
                        child: Text(
                          k.label,
                          style: context.textStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: active
                                ? context.itemKindColor(k)
                                : context.opsTextSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Form fields ──────────────────────────────────────────
            AppTextField(
              label: 'Тайлбар *',
              hint: 'Тосны шилжүүлэлт...',
              controller: _descCtrl,
              readOnly: !widget.canEditFields,
            ),
            const SizedBox(height: 12),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _validationError!,
                  style: context.textStyles.body.copyWith(
                    color: context.opsDanger,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Тоо *',
                    hint: '1',
                    controller: _qtyCtrl,
                    readOnly: !widget.canEditFields || _moneyLocked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    label: 'Нэгж үнэ (₮) *',
                    hint: '0',
                    controller: _priceCtrl,
                    readOnly: !_effectiveCanEditPrice,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [PriceInputFormatter()],
                  ),
                ),
              ],
            ),
            if (_moneyLocked) ...[
              const SizedBox(height: 8),
              Text(
                'Төлбөр төлөгдсөн тул төрөл, тоо, үнийг өөрчлөх боломжгүй. ${widget.paidLockReason}',
                style: context.textStyles.caption,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: _isEdit ? 'Хадгалах' : 'Нэмэх',
                onPressed: _saving ? null : _save,
                loading: _saving,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _KindFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;
  const _KindFilterChip({
    required this.label,
    required this.active,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.opsAccent;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? c.withOpacity(0.12) : context.opsSurface,
            borderRadius: BorderRadius.circular(AppDimens.radiusFull),
            border: Border.all(color: active ? c : context.opsDivider),
          ),
          child: Text(
            label,
            style: context.textStyles.label.copyWith(
              fontWeight: FontWeight.w600,
              color: active ? c : context.opsTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Diagnostics section ─────────────────────────────────────────────────────

class _DiagnosticsSection extends StatelessWidget {
  final ServiceOrderDetail order;
  final DateFormat dateFmt;
  final bool locked;
  final void Function(String reportId) onOpenReport;
  const _DiagnosticsSection({
    required this.order,
    required this.dateFmt,
    required this.locked,
    required this.onOpenReport,
  });

  @override
  Widget build(BuildContext context) {
    final reports = order.reports;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                Icon(
                  Icons.assignment_outlined,
                  size: 18,
                  color: context.opsAccent,
                ),
                const SizedBox(width: 8),
                Text('Оношилгоо', style: context.textStyles.h3),
                const SizedBox(width: 8),
                if (reports.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.opsAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                    ),
                    child: Text(
                      '${reports.length}',
                      style: context.textStyles.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.opsAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Body ─────────────────────────────────────────────────────
          if (reports.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Тайлан бүртгээгүй байна.',
                  style: context.textStyles.body.copyWith(
                    color: context.opsTextSecondary,
                  ),
                ),
              ),
            )
          else
            ...reports.asMap().entries.map((entry) {
              final i = entry.key;
              final r = entry.value;
              final type = r.template.type;
              return Column(
                children: [
                  InkWell(
                    onTap: () => onOpenReport(r.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          // Type badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: context.diagnosticTypeBackground(type),
                              borderRadius: BorderRadius.circular(
                                AppDimens.radiusFull,
                              ),
                            ),
                            child: Text(
                              type.label,
                              style: context.textStyles.label.copyWith(
                                fontWeight: FontWeight.w600,
                                color: context.diagnosticTypeColor(type),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Name + date
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.template.name,
                                  style: context.textStyles.captionMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateFmt.format(r.createdAt),
                                  style: context.textStyles.caption,
                                ),
                              ],
                            ),
                          ),
                          // Chevron
                          Text(
                            'Үзэх →',
                            style: context.textStyles.label.copyWith(
                              color: context.opsAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (i < reports.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              );
            }),
        ],
      ),
    );
  }
}

// scale == 0 үед бутархай хоосон — BigInt.parse('') шиддэг.
BigInt _fractionDigits(String digits, int scale) {
  final padded = digits.padRight(scale, '0');
  return padded.isEmpty ? BigInt.zero : BigInt.parse(padded);
}
