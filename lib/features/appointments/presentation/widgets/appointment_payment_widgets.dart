import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

/// Payment-section widgets for the appointment detail screen — P2-F5.
///
/// `AppointmentBookingPaymentStatus.unknown` (the P2-F1 defensive sentinel
/// for an unrecognised value) is rendered with the same neutral treatment
/// everywhere here — no color, icon or label implies a real payment state
/// the server never asserted, matching how `unknown` deliberately carries no
/// `nextStatuses`/actions.
Color appointmentPaymentStatusColor(
  BuildContext context,
  AppointmentBookingPaymentStatus status,
) => switch (status) {
  AppointmentBookingPaymentStatus.PAID => context.opsGood,
  AppointmentBookingPaymentStatus.PENDING => context.opsWarning,
  AppointmentBookingPaymentStatus.UNDERPAID => context.opsWarning,
  AppointmentBookingPaymentStatus.FAILED => context.opsDanger,
  AppointmentBookingPaymentStatus.NOT_REQUIRED => context.opsTextSecondary,
  AppointmentBookingPaymentStatus.REFUNDED => context.opsTextSecondary,
  AppointmentBookingPaymentStatus.unknown => context.opsTextSecondary,
};

IconData appointmentPaymentStatusIcon(AppointmentBookingPaymentStatus status) =>
    switch (status) {
      AppointmentBookingPaymentStatus.PAID => Icons.check_circle_outline,
      AppointmentBookingPaymentStatus.PENDING => Icons.schedule_outlined,
      AppointmentBookingPaymentStatus.UNDERPAID => Icons.warning_amber_outlined,
      AppointmentBookingPaymentStatus.FAILED => Icons.error_outline,
      AppointmentBookingPaymentStatus.NOT_REQUIRED =>
        Icons.remove_circle_outline,
      AppointmentBookingPaymentStatus.REFUNDED => Icons.undo,
      AppointmentBookingPaymentStatus.unknown => Icons.help_outline,
    };

class AppointmentPaymentStatusChip extends StatelessWidget {
  const AppointmentPaymentStatusChip({super.key, required this.status});

  final AppointmentBookingPaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = appointmentPaymentStatusColor(context, status);
    return Container(
      key: const ValueKey('appointment_payment_status_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(appointmentPaymentStatusIcon(status), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: context.textStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel with the check/retry/refund actions. Permission gating happens in
/// the screen (hides/disables buttons); this widget only renders whatever
/// callbacks it is given — a null callback renders the button disabled.
class AppointmentPaymentPanel extends StatelessWidget {
  const AppointmentPaymentPanel({
    super.key,
    required this.status,
    required this.busy,
    this.onCheck,
    this.onRetry,
    this.onRefund,
    this.detailMessage,
  });

  final AppointmentBookingPaymentStatus status;
  final bool busy;
  final VoidCallback? onCheck;
  final VoidCallback? onRetry;
  final VoidCallback? onRefund;
  final String? detailMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('appointment_payment_panel'),
      padding: const EdgeInsets.all(AppDimens.paddingMD),
      decoration: BoxDecoration(
        color: context.opsCardBg,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Төлбөр', style: context.textStyles.bodyMedium),
              const Spacer(),
              AppointmentPaymentStatusChip(status: status),
            ],
          ),
          if (detailMessage != null) ...[
            const SizedBox(height: AppDimens.paddingXS),
            Text(detailMessage!, style: context.textStyles.caption),
          ],
          // A refunded fee is terminal: no check / retry / refund is offered.
          if (status != AppointmentBookingPaymentStatus.REFUNDED) ...[
            const SizedBox(height: AppDimens.paddingSM),
            Wrap(
              spacing: AppDimens.paddingSM,
              runSpacing: AppDimens.paddingSM,
              children: [
                if (onCheck != null)
                  OutlinedButton.icon(
                    key: const ValueKey('appointment_payment_check_button'),
                    onPressed: busy ? null : onCheck,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Төлбөр шалгах'),
                  ),
                if (onRetry != null)
                  OutlinedButton.icon(
                    key: const ValueKey('appointment_payment_retry_button'),
                    onPressed: busy ? null : onRetry,
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Дахин үүсгэх'),
                  ),
                if (onRefund != null)
                  OutlinedButton.icon(
                    key: const ValueKey('appointment_payment_refund_button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.opsDanger,
                      side: BorderSide(color: context.opsDanger),
                    ),
                    onPressed: busy ? null : onRefund,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Буцаах'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
