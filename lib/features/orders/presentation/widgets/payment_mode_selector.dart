import 'package:flutter/material.dart';
import 'package:carservice_business/features/orders/domain/order_payment_mode.dart';

/// Three-segment payment-mode control; labels wrap to two lines so it fits
/// 360dp phones and larger text scales.
class PaymentModeSelector extends StatelessWidget {
  const PaymentModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final OrderPaymentMode value;
  final ValueChanged<OrderPaymentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<OrderPaymentMode>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
        ),
        segments: [
          for (final m in OrderPaymentMode.values)
            ButtonSegment(
              value: m,
              label: Text(
                m.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}
