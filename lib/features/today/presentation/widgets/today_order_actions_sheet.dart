import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/detail/order_item_widgets.dart';

/// What was picked in [TodayOrderActionsSheet]. Choices that act on work
/// lines carry the loaded detail, so the board needn't fetch it again.
sealed class TodayMenuChoice {
  const TodayMenuChoice();
}

final class TodayFinishWork extends TodayMenuChoice {
  const TodayFinishWork(this.detail);
  final ServiceOrderDetail detail;
}

final class TodayFillDiagnostic extends TodayMenuChoice {
  const TodayFillDiagnostic(this.detail, this.item);
  final ServiceOrderDetail detail;
  final ServiceItem item;
}

final class TodayViewReport extends TodayMenuChoice {
  const TodayViewReport(this.item);
  final ServiceItem item;
}

final class TodayPay extends TodayMenuChoice {
  const TodayPay();
}

final class TodayCompleteOrder extends TodayMenuChoice {
  const TodayCompleteOrder();
}

final class TodayOpenDetail extends TodayMenuChoice {
  const TodayOpenDetail();
}

/// What the user may do from the sheet; each flag hides its rows.
class TodayMenuAccess {
  const TodayMenuAccess({
    required this.lines,
    required this.diagnostics,
    required this.reports,
    required this.payments,
    required this.complete,
  });

  /// Complete work lines: order edit and `orders.itemStatus`.
  final bool lines;

  /// Fill a diagnostic: order edit and `diagnostics.create`.
  final bool diagnostics;

  /// View a filled report: `diagnostics.view`.
  final bool reports;

  /// Open the payment screen: `payments.view`.
  final bool payments;

  /// Complete the order itself: order edit.
  final bool complete;
}

final _money = NumberFormat('#,##0.##', 'en_US');

/// Every action a Today card offers for its order. It loads the order's
/// detail first: work lines and diagnostics are not on the board's rows.
/// Pops the picked [TodayMenuChoice].
class TodayOrderActionsSheet extends StatefulWidget {
  const TodayOrderActionsSheet({
    super.key,
    required this.order,
    required this.access,
    required this.load,
  });

  final ServiceOrderSummary order;
  final TodayMenuAccess access;
  final Future<Result<ServiceOrderDetail>> Function() load;

  @override
  State<TodayOrderActionsSheet> createState() => _TodayOrderActionsSheetState();
}

class _TodayOrderActionsSheetState extends State<TodayOrderActionsSheet> {
  AsyncValue<ServiceOrderDetail> _detail = const AsyncLoading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _detail = const AsyncLoading());
    final result = await widget.load();
    if (!mounted) return;
    setState(() {
      _detail = switch (result) {
        Ok(:final value) => AsyncData(value),
        Err(:final error) => AsyncError(error),
      };
    });
  }

  void _pick(TodayMenuChoice choice) => AppNav.back(choice);

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plateLabel(order.vehicle.plate, order.vehicle.vin),
                  style: context.textStyles.h3,
                ),
                Text(
                  '${order.vehicle.displayName} · #${order.number}',
                  style: context.textStyles.caption,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: switch (_detail) {
              AsyncLoading() => const Padding(
                key: ValueKey('today_menu_loading'),
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              AsyncError(:final error) => Padding(
                key: const ValueKey('today_menu_error'),
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        error.display,
                        style: context.textStyles.body,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('today_menu_retry'),
                      onPressed: _load,
                      child: const Text('Дахин оролдох'),
                    ),
                  ],
                ),
              ),
              AsyncData(:final value) => ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _rows(context, value),
              ),
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _rows(BuildContext context, ServiceOrderDetail detail) {
    final access = widget.access;
    final inProgress = detail.status == OrderStatus.IN_PROGRESS;
    final completable = completableLines(detail.items);
    final pendingReports = reportPendingLines(detail.items);
    final reports = detail.items.where(
      (item) =>
          item.kind == ItemKind.DIAGNOSTIC &&
          item.status != ServiceItemStatus.CANCELLED &&
          item.diagnosticReportId != null,
    );
    final balance = detail.unpaidBalance;
    return [
      if (inProgress && access.lines && completable.isNotEmpty)
        _ActionRow(
          key: const ValueKey('today_menu_finish'),
          icon: Icons.done_all_rounded,
          color: context.opsGood,
          title: 'Бүх ажлыг дуусгах',
          subtitle: [
            '${completable.length} мөр',
            if (pendingReports.isNotEmpty)
              '${pendingReports.length} оношилгоо тайлангүй',
          ].join(' · '),
          onTap: () => _pick(TodayFinishWork(detail)),
        ),
      if (inProgress && access.diagnostics)
        for (final item in pendingReports)
          _ActionRow(
            key: ValueKey('today_menu_diag_${item.id}'),
            icon: Icons.fact_check_outlined,
            color: context.opsAccent,
            title: 'Оношилгоо бөглөх',
            subtitle: item.description,
            onTap: () => _pick(TodayFillDiagnostic(detail, item)),
          ),
      if (access.reports)
        for (final item in reports)
          _ActionRow(
            key: ValueKey('today_menu_report_${item.id}'),
            icon: Icons.description_outlined,
            title: 'Тайлан үзэх',
            subtitle: item.description,
            onTap: () => _pick(TodayViewReport(item)),
          ),
      if (access.payments &&
          !detail.isInternal &&
          detail.paymentStatus != PaymentStatus.PAID)
        _ActionRow(
          key: const ValueKey('today_menu_pay'),
          icon: Icons.payments_outlined,
          title: 'Төлбөр бүртгэх',
          subtitle: balance == null || balance <= 0
              ? null
              : 'Үлдэгдэл ${_money.format(balance)}₮',
          onTap: () => _pick(const TodayPay()),
        ),
      if (inProgress && access.complete)
        _ActionRow(
          key: const ValueKey('today_menu_complete'),
          icon: Icons.flag_outlined,
          title: 'Засварын хуудас дуусгах',
          onTap: () => _pick(const TodayCompleteOrder()),
        ),
      _ActionRow(
        key: const ValueKey('today_menu_open'),
        icon: Icons.open_in_new_rounded,
        title: 'Дэлгэрэнгүй харах',
        onTap: () => _pick(const TodayOpenDetail()),
      ),
    ];
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.opsTextSecondary;
    return ListTile(
      onTap: onTap,
      minTileHeight: 56,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        ),
        child: Icon(icon, size: 20, color: tint),
      ),
      title: Text(
        title,
        style: context.textStyles.bodyMedium.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.caption,
            ),
      trailing: Icon(Icons.chevron_right_rounded, color: context.opsTextHint),
    );
  }
}
