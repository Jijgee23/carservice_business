import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/widgets/app_dropdown.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_item_controller.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/list/order_list_widgets.dart';
import 'package:carservice_business/features/orders/presentation/widgets/order_status_prompt.dart';

/// Shown on a COMPLETED service line: the server answers any edit or cancel
/// with 422 `ITEM_COMPLETED_LOCKED`. The status can still be reopened while
/// the order is in progress, except on a diagnostic line with a report.
const completedLineLockedHint = 'Дууссан ажлыг засах боломжгүй.';

/// Server: 422 `DIAGNOSTIC_REPORT_LINKED`.
const diagnosticReportLinkedHint =
    'Оношилгоо бөглөгдсөн тул явцыг буцаах боломжгүй.';

/// A COMPLETED non-PART line is immutable even while the order is open. PART
/// lines stay editable until the order itself completes.
bool isLineCompletedLocked(ServiceItem item) =>
    item.kind != ItemKind.PART && item.status == ServiceItemStatus.COMPLETED;

/// A COMPLETED diagnostic line that already has its report can't be reopened:
/// it would leave a linked report on a pending line.
bool isLineStatusLocked(ServiceItem item) =>
    isLineCompletedLocked(item) &&
    item.kind == ItemKind.DIAGNOSTIC &&
    item.diagnosticReportId != null;

/// A DIAGNOSTIC line can only be completed once its report is filled
/// (server: 422 `DIAGNOSTIC_REPORT_REQUIRED`).
bool lineNeedsReport(ServiceItem item) =>
    item.kind == ItemKind.DIAGNOSTIC && item.diagnosticReportId == null;

/// Lines «complete all» moves: tracked work not yet done, leaving out
/// diagnostics still waiting for their report.
List<ServiceItem> completableLines(Iterable<ServiceItem> items) =>
    progressItems(items)
        .where(
          (item) =>
              item.status != ServiceItemStatus.COMPLETED &&
              !lineNeedsReport(item),
        )
        .toList(growable: false);

/// Diagnostic lines still waiting for their report (not cancelled).
List<ServiceItem> reportPendingLines(Iterable<ServiceItem> items) => items
    .where(
      (item) => item.status != ServiceItemStatus.CANCELLED && lineNeedsReport(item),
    )
    .toList(growable: false);

/// Statuses a line's progress menu offers. The server accepts any move
/// between them; CANCELLED has its own endpoint.
const changeableItemStatuses = [
  ServiceItemStatus.PENDING,
  ServiceItemStatus.IN_PROGRESS,
  ServiceItemStatus.COMPLETED,
];

class OrderItemCard extends StatelessWidget {
  const OrderItemCard({
    super.key,
    required this.item,
    required this.locked,
    this.paidLocked = false,
    this.paidLockReason = paidLockHint,
    required this.canEdit,
    required this.canPrice,
    required this.canStatus,
    required this.diagnosticEditable,
    this.pendingStatus,
    this.statusBusy = false,
    this.onEdit,
    this.onCancel,
    this.onStatus,
    this.onDiagnosticCreate,
    this.onDiagnosticFill,
    this.onDiagnosticView,
  });

  final ServiceItem item;
  final bool locked;

  /// Order has a paid payment: money edits and item cancel are refused by the
  /// server (`PAID_PAYMENT_EXISTS`), so cancel is disabled with a hint.
  final bool paidLocked;
  final String paidLockReason;
  final bool canEdit;
  final bool canPrice;
  final bool canStatus;
  final bool diagnosticEditable;

  /// Status the line is being moved to; shown instead of [item]'s until the
  /// server answers.
  final ServiceItemStatus? pendingStatus;

  /// A status change for this line is in flight: its controls are disabled.
  final bool statusBusy;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;
  final ValueChanged<ServiceItemStatus>? onStatus;
  final VoidCallback? onDiagnosticCreate;
  final VoidCallback? onDiagnosticFill;
  final VoidCallback? onDiagnosticView;

  String _money(Money? value, double fallback) =>
      '${value?.raw ?? fallback.toString()}₮';

  @override
  Widget build(BuildContext context) {
    final accent = context.itemKindColor(item.kind);
    final qty = item.quantityMoney?.raw ?? item.quantity.toString();
    final price = _money(item.unitPriceMoney, item.unitPrice);
    final total = _money(item.totalMoney, item.total);
    final status = pendingStatus ?? item.status;
    final actions = <Widget>[];
    final lineLocked = isLineCompletedLocked(item);
    final statusLocked = isLineStatusLocked(item);
    final statusControls =
        !locked && canStatus && item.status != ServiceItemStatus.CANCELLED;
    final next = statusControls && !statusLocked ? _nextStep(status) : null;
    if (!locked && (canEdit || canPrice)) {
      actions.add(
        IconButton(
          key: const ValueKey('item_edit_button'),
          tooltip: lineLocked ? completedLineLockedHint : 'Засах',
          onPressed: lineLocked ? null : onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    if (!locked && canEdit && item.status != ServiceItemStatus.CANCELLED) {
      actions.add(
        IconButton(
          key: const ValueKey('item_cancel_button'),
          tooltip: lineLocked
              ? completedLineLockedHint
              : paidLocked && item.total != 0
              ? paidLockReason
              : 'Цуцлах',
          onPressed: lineLocked || (paidLocked && item.total != 0)
              ? null
              : onCancel,
          icon: const Icon(Icons.cancel_outlined, size: 18),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    // Controls get the card's full width: next to the total they would be
    // squeezed on a phone.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withOpacity(.12),
                  borderRadius: BorderRadius.circular(AppDimens.radiusSM),
                ),
                child: Text(
                  item.kind.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.description,
                      style: context.textStyles.captionMedium,
                    ),
                    const SizedBox(height: 3),
                    Text('$qty × $price', style: context.textStyles.caption),
                    if (lineLocked && actions.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        completedLineLockedHint,
                        key: const ValueKey('item_completed_locked_hint'),
                        style: context.textStyles.caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(total, style: context.textStyles.captionMedium),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (statusControls)
                      _ItemStatusMenu(
                        item: item,
                        status: status,
                        busy: statusBusy,
                        lockedReason: statusLocked
                            ? diagnosticReportLinkedHint
                            : null,
                        onSelect: onStatus,
                      )
                    else
                      _ItemStatusPill(status: status),
                    if (next != null)
                      FilledButton.tonalIcon(
                        key: const ValueKey('item_next_status_button'),
                        onPressed: statusBusy || onStatus == null
                            ? null
                            : () => onStatus!(next),
                        icon: Icon(
                          next == ServiceItemStatus.IN_PROGRESS
                              ? Icons.play_arrow_rounded
                              : Icons.check_rounded,
                          size: 16,
                        ),
                        label: Text(
                          next == ServiceItemStatus.IN_PROGRESS
                              ? 'Эхлүүлэх'
                              : 'Дуусгах',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (item.kind == ItemKind.DIAGNOSTIC)
                      if (item.diagnosticReportId != null)
                        TextButton.icon(
                          onPressed: onDiagnosticView,
                          icon: const Icon(Icons.visibility_outlined, size: 15),
                          label: const Text('Тайлан үзэх'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                          ),
                        )
                      else if (diagnosticEditable &&
                          item.diagnosticTemplateId != null)
                        TextButton.icon(
                          onPressed: onDiagnosticFill,
                          icon: const Icon(Icons.playlist_add_check, size: 15),
                          label: const Text('Бөглөх'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                          ),
                        )
                      else if (diagnosticEditable)
                        TextButton.icon(
                          onPressed: onDiagnosticCreate,
                          icon: const Icon(Icons.add_task, size: 15),
                          label: const Text('Оношилгоо үүсгэх'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }

  /// The one-tap step forward. A diagnostic line without its report has none:
  /// its fill/create button is the next step instead.
  ServiceItemStatus? _nextStep(ServiceItemStatus status) => switch (status) {
    ServiceItemStatus.PENDING => ServiceItemStatus.IN_PROGRESS,
    ServiceItemStatus.IN_PROGRESS when !lineNeedsReport(item) =>
      ServiceItemStatus.COMPLETED,
    _ => null,
  };
}

/// The line's status as a pill; tapping it opens every status the line can
/// move to, so any move (forward, back, straight to done) is one choice.
class _ItemStatusMenu extends StatelessWidget {
  const _ItemStatusMenu({
    required this.item,
    required this.status,
    required this.busy,
    required this.lockedReason,
    required this.onSelect,
  });

  final ServiceItem item;
  final ServiceItemStatus status;
  final bool busy;

  /// Set when the status can't change at all; shown as the tooltip.
  final String? lockedReason;
  final ValueChanged<ServiceItemStatus>? onSelect;

  @override
  Widget build(BuildContext context) {
    final interactive = lockedReason == null && !busy && onSelect != null;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: AppDropdown.menuStyle(context),
      menuChildren: [
        for (final option in changeableItemStatuses)
          _ItemStatusMenuItem(
            key: ValueKey('item_status_option_${option.name}'),
            status: option,
            selected: option == status,
            disabledReason:
                option == ServiceItemStatus.COMPLETED && lineNeedsReport(item)
                ? 'Тайлан шаардлагатай'
                : null,
            onPressed: () => onSelect?.call(option),
          ),
      ],
      builder: (context, menu, _) {
        final pill = InkWell(
          key: const ValueKey('item_status_button'),
          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          onTap: interactive
              ? () => menu.isOpen ? menu.close() : menu.open()
              : null,
          child: _ItemStatusPill(
            status: status,
            trailing: busy
                ? const _PillSpinner()
                : lockedReason == null
                ? Icon(
                    menu.isOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: context.itemStatusColor(status),
                  )
                : null,
          ),
        );
        return lockedReason == null
            ? pill
            : Tooltip(message: lockedReason, child: pill);
      },
    );
  }
}

class _ItemStatusMenuItem extends StatelessWidget {
  const _ItemStatusMenuItem({
    super.key,
    required this.status,
    required this.selected,
    required this.disabledReason,
    required this.onPressed,
  });

  final ServiceItemStatus status;
  final bool selected;
  final String? disabledReason;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = context.itemStatusColor(status);
    return MenuItemButton(
      onPressed: selected || disabledReason != null ? null : onPressed,
      style: MenuItemButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // The current status is informational, not greyed out.
        disabledForegroundColor: selected ? context.opsTextPrimary : null,
      ),
      leadingIcon: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      trailingIcon: selected
          ? Icon(Icons.check_rounded, size: 20, color: context.opsAccent)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status.label,
            style: context.textStyles.bodyMedium.copyWith(
              fontWeight: selected ? FontWeight.w700 : null,
            ),
          ),
          if (disabledReason case final reason?)
            Text(reason, style: context.textStyles.caption),
        ],
      ),
    );
  }
}

class _ItemStatusPill extends StatelessWidget {
  const _ItemStatusPill({required this.status, this.trailing});
  final ServiceItemStatus status;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = context.itemStatusColor(status);
    return Container(
      padding: EdgeInsets.fromLTRB(8, 4, trailing == null ? 8 : 4, 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.1),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing case final trailing?) ...[
            const SizedBox(width: 2),
            trailing,
          ],
        ],
      ),
    );
  }
}

class _PillSpinner extends StatelessWidget {
  const _PillSpinner();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(3),
    child: SizedBox(
      width: 10,
      height: 10,
      child: CircularProgressIndicator(strokeWidth: 1.5),
    ),
  );
}

class OrderItemHistorySheet extends StatefulWidget {
  const OrderItemHistorySheet({super.key, required this.controller});
  final OrderItemController controller;

  @override
  State<OrderItemHistorySheet> createState() => _OrderItemHistorySheetState();
}

class _OrderItemHistorySheetState extends State<OrderItemHistorySheet> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrderItemController>().historyState;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: switch (state) {
          AsyncLoading() => const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          ),
          AsyncError(:final error) => SizedBox(
            height: 180,
            child: Center(child: Text(error.display)),
          ),
          AsyncData(:final value) => _buildRows(context, value.items),
        },
      ),
    );
  }

  Widget _buildRows(BuildContext context, List<ServiceItem> items) {
    final controller = context.read<OrderItemController>();
    final date = DateFormat('yyyy-MM-dd HH:mm');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.historyNextError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    controller.historyNextError!,
                    style: TextStyle(color: context.opsDanger),
                  ),
                ),
                TextButton(
                  onPressed:
                      controller.isLoadingHistory ||
                          controller.isLoadingNextHistory
                      ? null
                      : () {
                          controller.loadNextHistory();
                        },
                  child: const Text('Дахин оролдох'),
                ),
              ],
            ),
          ),
        if (items.isEmpty)
          const SizedBox(
            height: 140,
            child: Center(child: Text('Цуцлагдсан мөр байхгүй.')),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = items[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.description),
                  subtitle: Text(
                    '${item.kind.label} · ${item.cancelledAt == null ? '—' : date.format(item.cancelledAt!)}'
                    '${item.cancelledBy == null ? (item.cancelledById == null ? '' : ' · ${item.cancelledById}') : ' · ${item.cancelledBy!.fullName}'}\n'
                    'Тоо: ${item.quantityMoney?.raw ?? item.quantity} · '
                    'Нэгж: ${item.unitPriceMoney?.raw ?? item.unitPrice}₮ · '
                    'Нийт: ${item.totalMoney?.raw ?? item.total}₮',
                  ),
                  isThreeLine: true,
                  trailing:
                      controller.historyHasNext && index == items.length - 1
                      ? TextButton(
                          onPressed:
                              controller.isLoadingHistory ||
                                  controller.isLoadingNextHistory
                              ? null
                              : () {
                                  controller.loadNextHistory();
                                },
                          child: const Text('Дараах'),
                        )
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }
}
