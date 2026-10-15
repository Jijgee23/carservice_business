import 'package:flutter/material.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/core/widgets/app_dropdown.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

final _dateFormat = DateFormat('yyyy.MM.dd');
final _dateTimeFormat = DateFormat('yyyy.MM.dd HH:mm');

/// Formats the already validated decimal text without converting through a
/// binary floating-point value. This preserves exact fractional digits and
/// values beyond IEEE-754's safe integer range.
String formatPostpaidMoney(Money value) {
  var raw = value.raw;
  var sign = '';
  if (raw.startsWith('-')) {
    sign = '-';
    raw = raw.substring(1);
  }
  final parts = raw.split('.');
  final integer = parts.first;
  final fraction = parts.length == 1 ? '' : '.${parts.sublist(1).join('.')}';
  final grouped = integer.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
  return '$sign$grouped$fraction₮';
}

class PostpaidSummaryCard extends StatelessWidget {
  const PostpaidSummaryCard({super.key, required this.summary});
  final PostpaidSummary summary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Нийт үлдэгдэл', style: context.textStyles.h3),
          const SizedBox(height: 4),
          Text(
            'Серверийн бүх цагийн нэгтгэл · цуцлагдсан засварын хуудас ороогүй',
            style: context.textStyles.caption,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              PostpaidMetric(
                label: 'Засварын хуудас',
                value: '${summary.orderCount}',
                icon: Icons.receipt_long_outlined,
                color: context.opsAccent,
              ),
              PostpaidMetric(
                label: 'Нийт',
                value: formatPostpaidMoney(summary.totalAmountMoney),
                icon: Icons.account_balance_wallet_outlined,
                color: context.opsTextPrimary,
              ),
              PostpaidMetric(
                label: 'Төлсөн',
                value: formatPostpaidMoney(summary.paidAmountMoney),
                icon: Icons.check_circle_outline,
                color: context.opsGood,
              ),
              PostpaidMetric(
                label: 'Үлдэгдэл',
                value: formatPostpaidMoney(summary.balanceAmountMoney),
                icon: Icons.pending_actions_outlined,
                color: context.opsWarning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PostpaidMetric extends StatelessWidget {
  const PostpaidMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.textStyles.caption),
              Text(value, style: context.textStyles.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class PostpaidVehicleCard extends StatelessWidget {
  const PostpaidVehicleCard({super.key, required this.aggregate});
  final PostpaidVehicleAggregate aggregate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_car_outlined, color: context.opsAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plateLabel(aggregate.plate),
                  style: context.textStyles.h3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${aggregate.orderCount}',
                    style: context.textStyles.bodyMedium,
                  ),
                  Text('засварын хуудас', style: context.textStyles.caption),
                ],
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${aggregate.make} ${aggregate.model}'.trim(),
            style: context.textStyles.caption,
            overflow: TextOverflow.ellipsis,
          ),
          if (aggregate.customer != null) ...[
            const SizedBox(height: 3),
            Text(
              aggregate.customer!.displayName,
              style: context.textStyles.caption,
            ),
          ],
          const SizedBox(height: 14),
          _VehicleMoneyRow(
            label: 'Нийт',
            value: aggregate.totalAmountMoney,
            color: context.opsTextPrimary,
          ),
          const SizedBox(height: 6),
          _VehicleMoneyRow(
            label: 'Төлсөн',
            value: aggregate.paidAmountMoney,
            color: context.opsGood,
          ),
          const SizedBox(height: 6),
          _VehicleMoneyRow(
            label: 'Үлдэгдэл',
            value: aggregate.balanceAmountMoney,
            color: context.opsWarning,
          ),
        ],
      ),
    );
  }
}

class _VehicleMoneyRow extends StatelessWidget {
  const _VehicleMoneyRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final Money value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: context.textStyles.caption)),
      Text(
        formatPostpaidMoney(value),
        style: context.textStyles.captionMedium.copyWith(color: color),
      ),
    ],
  );
}

class PostpaidHistoryCard extends StatelessWidget {
  const PostpaidHistoryCard({super.key, required this.order});
  final ServiceOrderSummary order;

  @override
  Widget build(BuildContext context) {
    final date = order.scheduledAt ?? order.createdAt;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${order.number}',
                  style: context.textStyles.bodyMedium,
                ),
              ),
              PostpaidPaymentChip(status: order.paymentStatus),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.directions_car_outlined,
                size: 16,
                color: context.opsTextSecondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${plateLabel(order.vehicle.plate, order.vehicle.vin)} · ${order.vehicle.displayName}',
                  style: context.textStyles.captionMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 16,
                color: context.opsTextSecondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  order.customer.displayName,
                  style: context.textStyles.caption,
                ),
              ),
              Text(
                _dateTimeFormat.format(date),
                style: context.textStyles.caption,
              ),
            ],
          ),
          if (order.totalAmountMoney != null ||
              order.paidAmountMoney != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (order.totalAmountMoney != null) ...[
                  Text('Нийт ', style: context.textStyles.caption),
                  Text(
                    formatPostpaidMoney(order.totalAmountMoney!),
                    style: context.textStyles.captionMedium,
                  ),
                ],
                const Spacer(),
                if (order.paidAmountMoney != null) ...[
                  Text('Төлсөн ', style: context.textStyles.caption),
                  Text(
                    formatPostpaidMoney(order.paidAmountMoney!),
                    style: context.textStyles.captionMedium,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class PostpaidPaymentChip extends StatelessWidget {
  const PostpaidPaymentChip({super.key, required this.status});
  final PaymentStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: context.paymentStatusBackground(status),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status.label,
      style: context.textStyles.captionMedium.copyWith(
        color: context.paymentStatusColor(status),
      ),
    ),
  );
}

class PostpaidFilterBar extends StatelessWidget {
  const PostpaidFilterBar({
    super.key,
    required this.vehicles,
    required this.vehicleId,
    required this.paymentStatus,
    required this.dateFrom,
    required this.dateTo,
    required this.onVehicleChanged,
    required this.onPaymentChanged,
    required this.onDateChanged,
    required this.onClear,
  });

  final List<PostpaidVehicleAggregate> vehicles;
  final String? vehicleId;
  final PaymentStatus? paymentStatus;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final ValueChanged<String?> onVehicleChanged;
  final ValueChanged<PaymentStatus?> onPaymentChanged;
  final ValueChanged<DateTimeRange?> onDateChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final validVehicleId = vehicles.any((vehicle) => vehicle.id == vehicleId)
        ? vehicleId
        : null;
    final dateLabel = dateFrom == null && dateTo == null
        ? 'Огноо'
        : '${dateFrom == null ? '...' : _dateFormat.format(dateFrom!)} – '
              '${dateTo == null ? '...' : _dateFormat.format(dateTo!)}';
    return AppCard(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: AppDropdown<String?>(
              value: validVehicleId,
              label: 'Тээврийн хэрэгсэл',
              items: [
                const AppDropdownItem<String?>(value: null, label: 'Бүгд'),
                ...vehicles.map(
                  (vehicle) => AppDropdownItem<String?>(
                    value: vehicle.id,
                    label: plateLabel(vehicle.plate),
                  ),
                ),
              ],
              onChanged: onVehicleChanged,
            ),
          ),
          SizedBox(
            width: 190,
            child: AppDropdown<PaymentStatus?>(
              value: paymentStatus,
              label: 'Төлбөр',
              items: [
                const AppDropdownItem<PaymentStatus?>(
                  value: null,
                  label: 'Бүгд',
                ),
                ...PaymentStatus.values.map(
                  (status) => AppDropdownItem<PaymentStatus?>(
                    value: status,
                    label: status.label,
                  ),
                ),
              ],
              onChanged: onPaymentChanged,
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final range = await AppDatePicker.range(
                context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initial: dateFrom == null || dateTo == null
                    ? null
                    : DateTimeRange(start: dateFrom!, end: dateTo!),
              );
              if (range != null) onDateChanged(range);
            },
            icon: const Icon(Icons.date_range_outlined, size: 18),
            label: Text(dateLabel),
          ),
          TextButton(onPressed: onClear, child: const Text('Цэвэрлэх')),
        ],
      ),
    );
  }
}
