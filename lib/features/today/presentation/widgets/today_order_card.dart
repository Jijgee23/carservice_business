import 'package:flutter/material.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/list/order_list_widgets.dart';

/// The one primary action a card offers: the next step its order needs.
/// [finishWork] completes the open work lines, [complete] the order itself.
enum TodayCardAction { start, finishWork, pay, complete }

/// A work card for the Today board (tenant-app design "Миний ажлууд"):
/// vehicle, plate · order number and a status pill, the work summary with
/// its progress, then who, when, the payment state and the next step.
class TodayOrderCard extends StatelessWidget {
  const TodayOrderCard({
    super.key,
    required this.order,
    required this.now,
    required this.onTap,
    this.action,
    this.onAction,
    this.onMore,
    this.busy = false,
  });

  final ServiceOrderSummary order;
  final DateTime now;
  final VoidCallback onTap;
  final TodayCardAction? action;
  final VoidCallback? onAction;

  /// Opens the card's other actions; null hides the ⋯ button.
  final VoidCallback? onMore;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final time = _timeLine(context);
    final name = order.vehicle.displayName.trim();
    final progress = order.progress;
    final showProgress =
        order.status == OrderStatus.IN_PROGRESS &&
        progress != null &&
        progress.total > 0;
    final summary = order.servicePreview.join(' · ');
    final (statusLabel, tone) = _status;
    return OpsCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('today_order_${order.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (name.isNotEmpty) ...[
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        // Plate · order number. FittedBox scales the plate
                        // down rather than truncating it on a narrow card:
                        // staff find a car by its plate.
                        SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  plateLabel(
                                    order.vehicle.plate,
                                    order.vehicle.vin,
                                  ),
                                  maxLines: 1,
                                  style: opsMono(
                                    context,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: t.ink,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                Text(
                                  ' · #${order.number}',
                                  maxLines: 1,
                                  style: opsMono(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  OpsPill(statusLabel, tone: tone),
                ],
              ),
              if (summary.isNotEmpty || showProgress) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: summary.isEmpty
                          ? const SizedBox.shrink()
                          : Text(
                              summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 18 / 13,
                                color: t.mutedText,
                              ),
                            ),
                    ),
                    if (showProgress) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${progress.completed}/${progress.total}',
                        style: opsMono(context),
                      ),
                    ],
                  ],
                ),
              ],
              if (showProgress) ...[
                const SizedBox(height: 8),
                OpsProgressBar(value: progress.completed / progress.total),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _InfoRow(
                      icon: Icons.person_outline,
                      text: order.customer.displayName,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _InfoRow(
                      icon: Icons.engineering_outlined,
                      text: order.assignedTo?.fullName ?? 'Хуваарилаагүй',
                      muted: order.assignedTo == null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _InfoRow(
                      icon: time.icon,
                      text: time.text,
                      color: time.color,
                      emphasised: time.color != null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: OrderPaymentChip(status: order.paymentStatus),
                    ),
                  ),
                ],
              ),
              if (action != null || onMore != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (action case final action?)
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: _ActionButton(
                            action: action,
                            busy: busy,
                            onPressed: busy ? null : onAction,
                            orderId: order.id,
                            openWork: order.unfinishedWorkCount ?? 0,
                          ),
                        ),
                      ),
                    if (onMore != null) ...[
                      if (action != null) const SizedBox(width: 8),
                      IconButton.outlined(
                        key: ValueKey('today_more_${order.id}'),
                        tooltip: 'Бусад үйлдэл',
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(48),
                          foregroundColor: t.ink,
                          side: BorderSide(color: t.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: busy ? null : onMore,
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The status pill: waiting (amber), in the shop (accent), done (green).
  (String, OpsTone) get _status => switch (order.status) {
    OrderStatus.SCHEDULED => ('Хүлээгдэж', OpsTone.warn),
    OrderStatus.IN_PROGRESS => ('Засварт', OpsTone.accent),
    OrderStatus.COMPLETED => ('Дууссан', OpsTone.ok),
    OrderStatus.CANCELLED => ('Цуцалсан', OpsTone.neutral),
  };

  ({IconData icon, String text, Color? color}) _timeLine(BuildContext context) {
    final hm = DateFormat('HH:mm');
    switch (order.status) {
      case OrderStatus.SCHEDULED:
        final at = order.scheduledAt?.toLocal();
        if (at == null) {
          return (
            icon: Icons.directions_walk,
            text: 'Шууд ирсэн · ${hm.format(order.createdAt.toLocal())}',
            color: null,
          );
        }
        final today = DateTime(now.year, now.month, now.day);
        if (at.isBefore(today)) {
          return (
            icon: Icons.warning_amber_rounded,
            text: 'Хоцорсон · ${DateFormat('MM/dd HH:mm').format(at)}',
            color: context.opsDanger,
          );
        }
        if (at.isBefore(now)) {
          return (
            icon: Icons.warning_amber_rounded,
            text: 'Хоцорсон · ${hm.format(at)}',
            color: context.opsWarning,
          );
        }
        return (icon: Icons.schedule, text: hm.format(at), color: null);
      case OrderStatus.IN_PROGRESS:
        final started = order.startedAt?.toLocal();
        final elapsed = started == null
            ? null
            : _duration(now.difference(started));
        final finish = order.expectedFinishAt?.toLocal();
        return (
          icon: Icons.timer_outlined,
          text: [
            if (elapsed != null) elapsed,
            if (finish != null) 'дуусах ${hm.format(finish)}',
          ].join(' · ').ifEmpty('Эхэлсэн'),
          color: null,
        );
      case OrderStatus.COMPLETED:
        final at = order.completedAt?.toLocal();
        return (
          icon: Icons.check_circle_outline,
          text: at == null ? 'Дууссан' : 'Дууссан · ${hm.format(at)}',
          color: null,
        );
      case OrderStatus.CANCELLED:
        return (icon: Icons.cancel_outlined, text: 'Цуцалсан', color: null);
    }
  }

  static String _duration(Duration d) {
    if (d.isNegative) return '0 мин';
    final days = d.inDays;
    final h = d.inHours % 24;
    final m = d.inMinutes % 60;
    if (days > 0) return '$days хоног $h ц';
    final totalHours = d.inHours;
    return totalHours > 0 ? '$totalHours ц $m мин' : '$m мин';
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
    this.color,
    this.muted = false,
    this.emphasised = false,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final bool muted;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (muted ? context.opsTextHint : context.opsTextSecondary);
    return Row(
      children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: c,
              fontWeight: emphasised ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.busy,
    required this.onPressed,
    required this.orderId,
    required this.openWork,
  });

  final TodayCardAction action;
  final bool busy;
  final VoidCallback? onPressed;
  final String orderId;

  /// Open work lines, shown on [TodayCardAction.finishWork].
  final int openWork;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (action) {
      TodayCardAction.start => ('Эхлүүлэх', Icons.play_arrow_rounded),
      TodayCardAction.finishWork => (
        openWork > 0 ? 'Ажлуудыг дуусгах ($openWork)' : 'Ажлуудыг дуусгах',
        Icons.done_all_rounded,
      ),
      TodayCardAction.complete => ('Дуусгах', Icons.check_rounded),
      TodayCardAction.pay => ('Төлбөр', Icons.payments_outlined),
    };
    final child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);
    final key = ValueKey('today_action_${action.name}_$orderId');
    // Payment is secondary to doing the work; keep it visually quieter.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    if (action == TodayCardAction.pay) {
      return OutlinedButton.icon(
        key: key,
        style: OutlinedButton.styleFrom(
          shape: shape,
          side: BorderSide(color: CarserviceTheme.of(context).border),
        ),
        onPressed: onPressed,
        icon: child,
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return FilledButton.icon(
      key: key,
      style: FilledButton.styleFrom(
        shape: shape,
        backgroundColor: action == TodayCardAction.complete
            ? context.opsGood
            : null,
      ),
      onPressed: onPressed,
      icon: child,
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
