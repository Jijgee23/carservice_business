import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/widgets/app_dropdown.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/assignee_avatar.dart';
import 'package:carservice_business/features/orders/presentation/widgets/list/order_list_widgets.dart';

/// The navy vehicle header of the design: make/model, year and mileage when
/// known, the plate as a light chip, then customer, branch and arrival.
class OrderDetailSummaryCard extends StatelessWidget {
  const OrderDetailSummaryCard({
    super.key,
    required this.order,
    this.showNumber = true,
  });

  final ServiceOrderDetail order;

  /// Whether to render the "#number" heading. The detail screen's header
  /// already shows it, so it passes `false` to avoid showing it twice.
  final bool showNumber;

  static final _time = DateFormat('HH:mm');
  static final _dayTime = DateFormat('MM/dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final vehicle = order.vehicle;
    final plate = plateLabel(vehicle.plate, vehicle.vin);
    final name = '${vehicle.make} ${vehicle.model}'.trim();
    final mileage = vehicle.mileage ?? order.intake?.mileageKm;
    final facts = [
      if (vehicle.year != null) '${vehicle.year}',
      if (mileage != null) formatMileageKm(mileage),
    ];
    final arrived = order.intake?.recordedAt;
    final customer = order.customer;
    final phone = customer.phone.trim();
    const muted = TextStyle(
      fontSize: 13,
      height: 18 / 13,
      color: OpsDark.muted,
    );

    return OpsHeroCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showNumber) ...[
            Text(
              '#${order.number}',
              key: const ValueKey('order_detail_number'),
              style: opsMono(context, fontSize: 12, color: OpsDark.muted2),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? plate : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        height: 24 / 19,
                        fontWeight: FontWeight.w600,
                        color: OpsDark.ink,
                      ),
                    ),
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(facts.join(' · '), style: muted),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: OpsDark.ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  plate,
                  style: opsMono(
                    context,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: OpsDark.bg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Text.rich(
                TextSpan(
                  text: 'Үйлчлүүлэгч: ',
                  children: [
                    TextSpan(
                      text: customer.displayName,
                      style: const TextStyle(
                        color: OpsDark.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (phone.isNotEmpty && phone != customer.displayName)
                      TextSpan(text: ' · $phone'),
                  ],
                ),
                style: muted,
              ),
              Text(order.branch.name, style: muted),
              if (arrived != null)
                Text(
                  'Ирсэн ${DateUtils.isSameDay(arrived, DateTime.now()) ? _time.format(arrived) : _dayTime.format(arrived)}',
                  style: muted,
                ),
            ],
          ),
          if (order.notes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.notes_outlined,
                    size: 16,
                    color: OpsDark.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.notes!.trim(),
                    style: muted.copyWith(color: OpsDark.ink),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// «Явц» card: a stepper over the order's status sequence (Товлогдсон →
/// Хийгдэж байна → Дууссан), then the "Төлөв" row. When the user may change
/// the status, tapping the row opens a dropdown of the statuses it can move
/// to next; the current status heads the list, checked, for context.
class OrderStatusField extends StatelessWidget {
  const OrderStatusField({
    super.key,
    required this.current,
    required this.enabled,
    required this.onSelect,
  });

  final OrderStatus current;

  /// False without edit permission: the row still shows the status.
  final bool enabled;
  final ValueChanged<OrderStatus> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final options = enabled ? current.nextStatuses : const <OrderStatus>[];
    return OpsCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: OpsSectionLabel('Явц')),
              if (current == OrderStatus.CANCELLED)
                OpsSectionLabel(current.label, color: t.danger),
            ],
          ),
          const SizedBox(height: 14),
          _StatusStepper(current: current),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: t.shellBackground),
          LayoutBuilder(
            builder: (context, constraints) => MenuAnchor(
              alignmentOffset: const Offset(0, 4),
              // Lets the min width below reach the panel; by default
              // MenuAnchor sizes the panel to its widest item.
              crossAxisUnconstrained: false,
              // As wide as the row, like a dropdown.
              style: AppDropdown.menuStyle(
                context,
                width: constraints.maxWidth,
              ),
              menuChildren: [
                _StatusMenuItem(status: current, selected: true),
                for (final status in options)
                  _StatusMenuItem(
                    key: ValueKey('order_status_${status.name}'),
                    status: status,
                    onPressed: () => onSelect(status),
                  ),
              ],
              builder: (context, menu, _) => InkWell(
                key: const ValueKey('order_status_menu'),
                borderRadius: BorderRadius.circular(10),
                onTap: options.isEmpty
                    ? null
                    : () => menu.isOpen ? menu.close() : menu.open(),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Text(
                        'Төлөв',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                      const Spacer(),
                      OrderStatusChip(status: current),
                      if (options.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Icon(
                          menu.isOpen
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: t.mutedText,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal stepper: done steps get a navy tick, the current one the
/// accent dot with a ring, the rest an empty circle. A cancelled order has
/// no current step.
class _StatusStepper extends StatelessWidget {
  const _StatusStepper({required this.current});

  final OrderStatus current;

  static const _steps = [
    OrderStatus.SCHEDULED,
    OrderStatus.IN_PROGRESS,
    OrderStatus.COMPLETED,
  ];

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final finished = current == OrderStatus.COMPLETED;
    final index = _steps.indexOf(current); // -1 when cancelled
    return Semantics(
      label: 'Явц: ${current.label}',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segment = constraints.maxWidth / _steps.length;
            final reached = index < 0 ? 0 : index;
            return Stack(
              children: [
                Positioned(
                  left: segment / 2,
                  right: segment / 2,
                  top: 10,
                  child: Container(height: 2, color: t.border),
                ),
                if (reached > 0)
                  Positioned(
                    left: segment / 2,
                    width: segment * reached,
                    top: 10,
                    child: Container(height: 2, color: t.ink),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      Expanded(
                        child: Column(
                          children: [
                            _StepDot(
                              done: finished || i < index,
                              current: !finished && i == index,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _steps[i].label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 11,
                                height: 14 / 11,
                                fontWeight: !finished && i == index
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: !finished && i == index
                                    ? t.ink
                                    : t.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.done, required this.current});

  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? t.ink
            : current
            ? t.accentHi
            : t.panel,
        border: done || current ? null : Border.all(color: t.border, width: 2),
        boxShadow: [
          if (current)
            BoxShadow(
              color: t.accentHi.withValues(alpha: 0.18),
              spreadRadius: 4,
            ),
        ],
      ),
      child: done ? Icon(Icons.check, size: 12, color: t.panel) : null,
    );
  }
}

class _StatusMenuItem extends StatelessWidget {
  const _StatusMenuItem({
    super.key,
    required this.status,
    this.selected = false,
    this.onPressed,
  });

  final OrderStatus status;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = context.orderStatusColor(status);
    return MenuItemButton(
      onPressed: selected ? null : onPressed,
      style: MenuItemButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // The current status is informational, not greyed out.
        disabledForegroundColor: context.opsTextPrimary,
      ),
      leadingIcon: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      trailingIcon: selected
          ? Icon(Icons.check_rounded, size: 20, color: context.opsAccent)
          : null,
      child: Text(
        status.label,
        style: context.textStyles.bodyMedium.copyWith(
          fontWeight: selected ? FontWeight.w700 : null,
        ),
      ),
    );
  }
}

/// "Хариуцагч" row, styled like [OrderStatusField]: the order's assignee,
/// and — with `orders.assign` — a tap opens a menu of the branch's
/// assignable staff. The current assignee is checked.
class OrderAssignmentSection extends StatelessWidget {
  const OrderAssignmentSection({
    super.key,
    required this.order,
    required this.enabled,
    required this.state,
    required this.loading,
    required this.onChanged,
    this.error,
  });

  final ServiceOrderDetail order;

  /// False without assign permission: the row still shows the assignee.
  final bool enabled;
  final AsyncValue<List<AssignableUser>> state;
  final bool loading;
  final String? error;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final users = enabled
        ? state.valueOrNull ?? const <AssignableUser>[]
        : const <AssignableUser>[];
    final canOpen = users.isNotEmpty;
    final currentId = order.assignedTo?.id;
    final currentName = order.assignedTo?.fullName.trim();
    final hint = !enabled
        ? null
        : error ??
              (!loading && users.isEmpty ? 'Сонгох ажилтан олдсонгүй' : null);

    return LayoutBuilder(
      builder: (context, constraints) => MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        // Lets the min width below reach the panel; by default MenuAnchor
        // sizes the panel to its widest item.
        crossAxisUnconstrained: false,
        // As wide as the row, like a dropdown; long rosters scroll.
        style: AppDropdown.menuStyle(
          context,
          width: constraints.maxWidth,
          maxHeight: 360,
        ),
        menuChildren: [
          for (final user in users)
            _AssigneeMenuItem(
              key: ValueKey('order_assignee_${user.id}'),
              name: user.fullName,
              selected: user.id == currentId,
              onPressed: () => onChanged(user.id),
            ),
        ],
        builder: (context, menu, _) => OpsCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            key: canOpen ? const ValueKey('order_assignment_picker') : null,
            onTap: canOpen
                ? () => menu.isOpen ? menu.close() : menu.open()
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _RowIcon(icon: Icons.engineering_outlined),
                      const SizedBox(width: 12),
                      Text(
                        'Хариуцагч',
                        style: TextStyle(
                          fontSize: 15,
                          color: CarserviceTheme.of(context).ink,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _AssigneeChip(name: currentName),
                        ),
                      ),
                      if (enabled && loading) ...[
                        const SizedBox(width: 8),
                        SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.opsTextSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ] else if (canOpen) ...[
                        const SizedBox(width: 4),
                        Icon(
                          menu.isOpen
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: context.opsTextSecondary,
                        ),
                      ],
                    ],
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      hint,
                      key: error != null
                          ? const ValueKey('order_assignment_error')
                          : null,
                      textAlign: TextAlign.end,
                      style: context.textStyles.caption.copyWith(
                        color: error != null ? context.opsDanger : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar + name pill for the assignee row; `null` reads as unassigned.
class _AssigneeChip extends StatelessWidget {
  const _AssigneeChip({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final assigned = name?.isNotEmpty == true;
    final color = assigned ? context.opsAccent : context.opsTextSecondary;
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AssigneeAvatar(name: name, size: 22),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              assigned ? name! : 'Хариуцагчгүй',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.captionMedium.copyWith(
                color: assigned
                    ? context.opsTextPrimary
                    : context.opsTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssigneeMenuItem extends StatelessWidget {
  const _AssigneeMenuItem({
    super.key,
    required this.name,
    required this.selected,
    required this.onPressed,
  });

  final String name;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
      onPressed: selected ? null : onPressed,
      style: MenuItemButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        // The current assignee is informational, not greyed out.
        disabledForegroundColor: context.opsTextPrimary,
        backgroundColor: selected ? context.opsAccent.withOpacity(.06) : null,
      ),
      leadingIcon: AssigneeAvatar(name: name, size: 32),
      trailingIcon: selected
          ? Icon(Icons.check_rounded, size: 20, color: context.opsAccent)
          : null,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textStyles.bodyMedium.copyWith(
          fontWeight: selected ? FontWeight.w700 : null,
        ),
      ),
    );
  }
}

class OrderScheduleSection extends StatelessWidget {
  const OrderScheduleSection({
    super.key,
    required this.order,
    required this.enabled,
    required this.onExpectedFinish,
    required this.onReschedule,
  });

  final ServiceOrderDetail order;
  final bool enabled;
  final VoidCallback onExpectedFinish;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final format = MaterialLocalizations.of(context).formatMediumDate;
    Widget line(String label, DateTime value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: t.mutedText),
            ),
          ),
          Text(
            format(value),
            style: opsMono(
              context,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: t.ink,
            ),
          ),
        ],
      ),
    );
    final actions = [
      if (enabled && order.status == OrderStatus.IN_PROGRESS)
        TextButton.icon(
          key: const ValueKey('order_expected_finish_button'),
          onPressed: onExpectedFinish,
          icon: const Icon(Icons.flag_outlined, size: 18),
          label: const Text('Дуусах хугацаа'),
          style: TextButton.styleFrom(foregroundColor: t.accent),
        ),
      if (enabled && order.status == OrderStatus.SCHEDULED)
        TextButton.icon(
          key: const ValueKey('order_reschedule_button'),
          onPressed: onReschedule,
          icon: const Icon(Icons.event_repeat_outlined, size: 18),
          label: const Text('Шилжүүлэх'),
          style: TextButton.styleFrom(foregroundColor: t.accent),
        ),
    ];
    return OpsCard(
      padding: EdgeInsets.fromLTRB(16, 14, 16, actions.isEmpty ? 14 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OpsSectionLabel('Хуваарь'),
          if (order.scheduledAt != null) line('Товлосон', order.scheduledAt!),
          if (order.expectedFinishAt != null)
            line('Дуусах тооцоо', order.expectedFinishAt!),
          if (order.scheduledAt == null && order.expectedFinishAt == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Хуваарь тохируулаагүй',
                style: TextStyle(fontSize: 14, color: t.mutedText),
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 8, children: actions),
            ),
        ],
      ),
    );
  }
}

/// Neutral icon tile at the start of a row.
class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: t.shellBackground,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 16, color: t.ink),
    );
  }
}
