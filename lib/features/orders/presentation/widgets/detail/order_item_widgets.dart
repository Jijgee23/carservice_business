import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/money_format.dart';
import 'package:carservice_business/core/widgets/app_dropdown.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
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

/// A line amount: the lossless [Money] when the API sent one, else the
/// legacy double.
String _itemMoney(Money? value, double fallback) =>
    value == null ? formatMoneyNum(fallback) : formatMoney(value.raw);

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

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final isPart = item.kind == ItemKind.PART;
    final qty = item.quantityMoney?.raw ?? item.quantity.toString();
    final price = _itemMoney(item.unitPriceMoney, item.unitPrice);
    final total = _itemMoney(item.totalMoney, item.total);
    final status = pendingStatus ?? item.status;
    final done = status == ServiceItemStatus.COMPLETED;
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
          color: t.mutedText,
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
          color: t.mutedText,
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    final controls = <Widget>[
      if (statusControls)
        _ItemStatusMenu(
          item: item,
          status: status,
          busy: statusBusy,
          lockedReason: statusLocked ? diagnosticReportLinkedHint : null,
          onSelect: onStatus,
        )
      // Read-only: the check box already says pending / done; only work in
      // progress gets a pill, as in the design.
      else if (!isPart && status == ServiceItemStatus.IN_PROGRESS)
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
                : Icons.check,
            size: 16,
          ),
          label: Text(
            next == ServiceItemStatus.IN_PROGRESS ? 'Эхлүүлэх' : 'Дуусгах',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: OpsTone.accent.background(t),
            foregroundColor: t.accent,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      if (item.kind == ItemKind.DIAGNOSTIC)
        if (item.diagnosticReportId != null)
          _LineTextButton(
            onPressed: onDiagnosticView,
            icon: Icons.visibility_outlined,
            label: 'Тайлан үзэх',
          )
        else if (diagnosticEditable && item.diagnosticTemplateId != null)
          _LineTextButton(
            onPressed: onDiagnosticFill,
            icon: Icons.playlist_add_check,
            label: 'Бөглөх',
          )
        else if (diagnosticEditable)
          _LineTextButton(
            onPressed: onDiagnosticCreate,
            icon: Icons.add_task,
            label: 'Оношилгоо үүсгэх',
          ),
    ];

    // The design's checklist row: check box, the work, its amount. Parts are
    // plain rows (quantity × price) without a box, their edit/cancel inline.
    // A work line's controls get the row's full width under the text: next
    // to the total they would be squeezed on a phone.
    final inlineActions = isPart && controls.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isPart) ...[
                _LineCheck(status: status),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: status == ServiceItemStatus.IN_PROGRESS
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: done ? t.mutedText : t.ink,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: t.mutedText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          // Within «Ажлууд» a plain labour line needs no tag.
                          if (item.kind == ItemKind.DIAGNOSTIC ||
                              item.kind == ItemKind.FEE)
                            TextSpan(
                              text: '${item.kind.label} · ',
                              style: TextStyle(
                                color: context.itemKindColor(item.kind),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          TextSpan(
                            text: '$qty × $price',
                            style: opsMono(context, fontSize: 12),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: 12, color: t.mutedText),
                    ),
                    if (lineLocked && actions.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        completedLineLockedHint,
                        key: const ValueKey('item_completed_locked_hint'),
                        style: TextStyle(fontSize: 12, color: t.mutedText),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                total,
                style: opsMono(
                  context,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: done ? t.mutedText : t.ink,
                ),
              ),
              if (inlineActions && actions.isNotEmpty) ...[
                const SizedBox(width: 4),
                ...actions,
              ],
            ],
          ),
          if (controls.isNotEmpty || (actions.isNotEmpty && !inlineActions))
            Padding(
              padding: EdgeInsets.only(left: isPart ? 0 : 36, top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: controls,
                    ),
                  ),
                  ...actions,
                ],
              ),
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
    final t = CarserviceTheme.of(context);
    final tone = switch (status) {
      ServiceItemStatus.IN_PROGRESS => OpsTone.accent,
      ServiceItemStatus.COMPLETED => OpsTone.ok,
      _ => OpsTone.neutral,
    };
    final color = tone.foreground(t);
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: EdgeInsets.fromLTRB(10, 4, trailing == null ? 10 : 6, 4),
      decoration: BoxDecoration(
        color: tone == OpsTone.neutral ? t.panel2 : tone.background(t),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        border: tone == OpsTone.neutral ? Border.all(color: t.border) : null,
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
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
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

/// The line's check box: navy tick when done, accent ring while in progress,
/// grey ring while waiting.
class _LineCheck extends StatelessWidget {
  const _LineCheck({required this.status});
  final ServiceItemStatus status;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final done = status == ServiceItemStatus.COMPLETED;
    return Semantics(
      label: status.label,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: done ? t.ink : null,
          borderRadius: BorderRadius.circular(7),
          border: done
              ? null
              : Border.all(
                  color: status == ServiceItemStatus.IN_PROGRESS
                      ? t.accentHi
                      : t.mutedText3,
                  width: 2,
                ),
        ),
        child: done ? Icon(Icons.check, size: 14, color: t.panel) : null,
      ),
    );
  }
}

class _LineTextButton extends StatelessWidget {
  const _LineTextButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 15),
    // Style on the Text: a button textStyle would drop the theme font.
    label: Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    style: TextButton.styleFrom(
      foregroundColor: CarserviceTheme.of(context).accent,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(0, 34),
    ),
  );
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
                    'Нэгж: ${_itemMoney(item.unitPriceMoney, item.unitPrice)} · '
                    'Нийт: ${_itemMoney(item.totalMoney, item.total)}',
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
