import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_item_controller.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
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
    final actions = <Widget>[];
    final lineLocked = isLineCompletedLocked(item);
    final statusLocked = isLineStatusLocked(item);
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
    if (!locked && canStatus && item.status != ServiceItemStatus.CANCELLED) {
      actions.add(
        PopupMenuButton<ServiceItemStatus>(
          key: const ValueKey('item_status_button'),
          tooltip: statusLocked ? diagnosticReportLinkedHint : 'Төлөв',
          enabled: !statusLocked,
          icon: const Icon(Icons.swap_vert_rounded, size: 19),
          onSelected: onStatus,
          itemBuilder: (_) => _nextStatuses(item).map((status) {
            return PopupMenuItem(
              value: status,
              child: Text(_statusLabel(status)),
            );
          }).toList(),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
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
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.description,
                      style: context.textStyles.captionMedium,
                    ),
                    _StatusBadge(status: item.status),
                  ],
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
                if (item.kind == ItemKind.DIAGNOSTIC) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
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
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(total, style: context.textStyles.captionMedium),
              if (actions.isNotEmpty) Wrap(spacing: 0, children: actions),
            ],
          ),
        ],
      ),
    );
  }

  static List<ServiceItemStatus> _nextStatuses(ServiceItem item) {
    return switch (item.status) {
      ServiceItemStatus.PENDING => const [ServiceItemStatus.IN_PROGRESS],
      ServiceItemStatus.IN_PROGRESS => const [ServiceItemStatus.COMPLETED],
      // A finished line can be reopened while the order is IN_PROGRESS; edits
      // and cancel stay locked (ITEM_COMPLETED_LOCKED). A diagnostic line with
      // a report is excluded upstream (statusLocked).
      ServiceItemStatus.COMPLETED => const [
        ServiceItemStatus.IN_PROGRESS,
        ServiceItemStatus.PENDING,
      ],
      ServiceItemStatus.CANCELLED => const [],
    };
  }

  static String _statusLabel(ServiceItemStatus status) => switch (status) {
    ServiceItemStatus.PENDING => 'Хүлээгдэж буй',
    ServiceItemStatus.IN_PROGRESS => 'Хийгдэж байна',
    ServiceItemStatus.COMPLETED => 'Дууссан',
    ServiceItemStatus.CANCELLED => 'Цуцлагдсан',
  };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final ServiceItemStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ServiceItemStatus.COMPLETED => context.opsGood,
      ServiceItemStatus.CANCELLED => context.opsDanger,
      ServiceItemStatus.IN_PROGRESS => context.opsAccent,
      ServiceItemStatus.PENDING => context.opsTextSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(.1),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      ),
      child: Text(
        OrderItemCard._statusLabel(status),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
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
