import 'package:flutter/material.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

List<ServiceItem> progressItems(Iterable<ServiceItem> items) => items
    .where(
      (item) =>
          item.kind != ItemKind.PART &&
          item.status != ServiceItemStatus.CANCELLED,
    )
    .toList(growable: false);

double progressFraction(Iterable<ServiceItem> items) {
  final active = progressItems(items);
  if (active.isEmpty) return 0;
  final completed = active
      .where((item) => item.status == ServiceItemStatus.COMPLETED)
      .length;
  return completed / active.length;
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.orderStatusBackground(status),
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      border: Border.all(
        color: context.orderStatusColor(status).withOpacity(.35),
      ),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: context.orderStatusColor(status),
      ),
    ),
  );
}

class OrderPaymentChip extends StatelessWidget {
  const OrderPaymentChip({super.key, required this.status});
  final PaymentStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.paymentStatusBackground(status),
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      border: Border.all(
        color: context.paymentStatusColor(status).withOpacity(.35),
      ),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: context.paymentStatusColor(status),
      ),
    ),
  );
}

/// Renders the server-authoritative summary. It deliberately does not inspect
/// items or recalculate counts on the client.
class OrderProgressView extends StatelessWidget {
  const OrderProgressView({super.key, required this.progress});

  final OrderProgressSummary? progress;

  @override
  Widget build(BuildContext context) {
    if (progress == null) {
      return Text('Прогресс тодорхойгүй', style: context.textStyles.caption);
    }
    final total = progress!.total;
    final completed = progress!.completed;
    final fraction = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total == 0 ? '0/0 · ажил бүртгэгдээгүй' : '$completed/$total дууссан',
          style: context.textStyles.caption,
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: fraction),
      ],
    );
  }
}

/// Phone list card. Plate first (how workshop staff find a car, as on the
/// Today board), a status-coloured edge for scanning a long list, then who,
/// what and when, with the money in the footer.
class OrderPhoneCard extends StatelessWidget {
  const OrderPhoneCard({
    super.key,
    required this.order,
    required this.selected,
    required this.onTap,
    required this.onSelect,
  });
  final ServiceOrderSummary order;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onSelect;

  static final _dateFmt = DateFormat('MM/dd HH:mm');
  static final _moneyFmt = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    final statusColor = context.orderStatusColor(order.status);
    final time = _timeLine();
    return Material(
      color: selected
          ? Color.alphaBlend(
              context.opsAccent.withValues(alpha: 0.06),
              context.opsSurface,
            )
          : context.opsSurface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        side: BorderSide(
          color: selected ? context.opsAccent : context.opsDivider,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: () => onSelect(!selected),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: statusColor, width: 4)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _header(context)),
                    Checkbox(
                      value: selected,
                      onChanged: (value) => onSelect(value ?? false),
                      shape: const CircleBorder(),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: context.opsDivider, width: 1.5),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OrderStatusChip(status: order.status),
                          OrderPaymentChip(status: order.paymentStatus),
                          if (order.isPostpaid) const _PostpaidTag(),
                          if (order.isInternal) const OrderInternalTag(),
                        ],
                      ),
                      if (order.servicePreview.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          order.servicePreview.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Flexible(
                            child: _Meta(
                              icon: Icons.person_outline,
                              text: order.customer.displayName,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: _Meta(
                              icon: Icons.engineering_outlined,
                              text:
                                  order.assignedTo?.fullName ?? 'Хуваарилаагүй',
                              muted: order.assignedTo == null,
                            ),
                          ),
                        ],
                      ),
                      if (order.status == OrderStatus.IN_PROGRESS &&
                          order.progress != null) ...[
                        const SizedBox(height: 10),
                        OrderProgressView(progress: order.progress),
                      ],
                      const SizedBox(height: 12),
                      Divider(height: 1, color: context.opsDivider),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _Meta(icon: time.icon, text: time.text),
                          ),
                          if (order.totalAmount != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${_moneyFmt.format(order.totalAmount!.toInt())}₮',
                              style: context.textStyles.h3.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scales down rather than truncating a long plate on a narrow card.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            plateLabel(order.vehicle.plate, order.vehicle.vin),
            maxLines: 1,
            style: context.textStyles.h2.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (formerPlate(order.plateSnapshot, order.vehicle.plate)
            case final old?)
          Text(
            'хуучин: $old',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.caption.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                order.vehicle.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.caption,
              ),
            ),
            Text(' · ', style: context.textStyles.caption),
            Text('#${order.number}', style: context.textStyles.captionMedium),
          ],
        ),
      ],
    );
  }

  /// The one timestamp that matters for the order's current state.
  ({IconData icon, String text}) _timeLine() {
    String at(DateTime value) => _dateFmt.format(value.toLocal());
    return switch (order.status) {
      OrderStatus.SCHEDULED when order.scheduledAt != null => (
        icon: Icons.schedule,
        text: 'Товлосон ${at(order.scheduledAt!)}',
      ),
      OrderStatus.SCHEDULED => (
        icon: Icons.directions_walk,
        text: 'Шууд ирсэн ${at(order.createdAt)}',
      ),
      OrderStatus.IN_PROGRESS => (
        icon: Icons.timer_outlined,
        text: 'Эхэлсэн ${at(order.startedAt ?? order.createdAt)}',
      ),
      OrderStatus.COMPLETED => (
        icon: Icons.check_circle_outline,
        text: 'Дууссан ${at(order.completedAt ?? order.createdAt)}',
      ),
      OrderStatus.CANCELLED => (
        icon: Icons.cancel_outlined,
        text: 'Цуцалсан · ${at(order.createdAt)}',
      ),
    };
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? context.opsTextHint : context.opsTextSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.caption.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Neutral "Дотоод" badge for internal repairs (list row + detail).
class OrderInternalTag extends StatelessWidget {
  const OrderInternalTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('order_internal_tag'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.opsCardBg,
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      border: Border.all(color: context.opsDivider),
    ),
    child: Text(
      'Дотоод',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: context.opsTextSecondary,
      ),
    ),
  );
}

class _PostpaidTag extends StatelessWidget {
  const _PostpaidTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.opsCardBg,
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      border: Border.all(color: context.opsDivider),
    ),
    child: Text(
      'Дараа төлөх',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: context.opsTextSecondary,
      ),
    ),
  );
}

class BulkSelectionBar extends StatelessWidget {
  const BulkSelectionBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.onStatus,
    required this.onAssign,
    required this.canChangeStatus,
    required this.canAssign,
    this.assignableUsers = const [],
    this.loadingAssignableUsers = false,
    this.assignableUsersError,
  });
  final int count;
  final VoidCallback onClear;
  final ValueChanged<OrderStatus> onStatus;
  final ValueChanged<String> onAssign;
  final bool canChangeStatus;
  final bool canAssign;
  final List<AssignableUser> assignableUsers;
  final bool loadingAssignableUsers;
  final String? assignableUsersError;

  @override
  Widget build(BuildContext context) => Material(
    color: context.opsSurface,
    elevation: 4,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text('$count сонгосон', style: context.textStyles.bodyMedium),
            const Spacer(),
            if (canChangeStatus)
              PopupMenuButton<OrderStatus>(
                key: const ValueKey('bulk_status_button'),
                tooltip: 'Төлөв өөрчлөх',
                icon: const Icon(Icons.sync_alt),
                onSelected: onStatus,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: OrderStatus.SCHEDULED,
                    child: Text('Товлосон'),
                  ),
                  PopupMenuItem(
                    value: OrderStatus.IN_PROGRESS,
                    child: Text('Хийгдэж байна'),
                  ),
                  PopupMenuItem(
                    value: OrderStatus.COMPLETED,
                    child: Text('Дууссан'),
                  ),
                  PopupMenuItem(
                    value: OrderStatus.CANCELLED,
                    child: Text('Цуцлагдсан'),
                  ),
                ],
              ),
            if (canAssign)
              if (loadingAssignableUsers)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (assignableUsersError != null)
                Tooltip(
                  message: assignableUsersError!,
                  child: const Icon(
                    Icons.error_outline,
                    key: ValueKey('bulk_assign_error'),
                  ),
                )
              else
                PopupMenuButton<String>(
                  key: const ValueKey('bulk_assign_button'),
                  tooltip: 'Хариуцагч сонгох',
                  icon: const Icon(Icons.person_outline),
                  onSelected: onAssign,
                  itemBuilder: (_) => [
                    ...assignableUsers.map(
                      (user) => PopupMenuItem<String>(
                        value: user.id,
                        child: Text(user.fullName),
                      ),
                    ),
                  ],
                ),
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close),
              tooltip: 'Сонголт цэвэрлэх',
            ),
          ],
        ),
      ),
    ),
  );
}
