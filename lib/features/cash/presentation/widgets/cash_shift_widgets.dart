import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/business_time.dart';
import 'package:carservice_business/core/utils/money_format.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';

/// "11/11 09:30" in business time.
String formatShiftTime(DateTime? instant) => instant == null
    ? '—'
    : DateFormat('MM/dd HH:mm').format(toBusinessTime(instant));

/// "2026.11.11 09:30" in business time.
String formatShiftDateTime(DateTime? instant) => instant == null
    ? '—'
    : DateFormat('yyyy.MM.dd HH:mm').format(toBusinessTime(instant));

/// Difference with an explicit sign: "+5,000₮", "-1,200₮", "0₮".
String formatSignedMoney(String? value) {
  if (value == null) return '—';
  final n = num.tryParse(value);
  if (n == null) return formatMoney(value);
  if (n > 0) return '+${formatMoney(value)}';
  return formatMoney(value);
}

/// Tone of a close difference: 0 ok, a shortage danger, a surplus warn.
Color differenceColor(BuildContext context, String? value) {
  final n = num.tryParse(value ?? '');
  if (n == null) return context.colors.textSecondary;
  if (n == 0) return context.colors.good;
  return n < 0 ? context.colors.danger : context.colors.warning;
}

class ShiftStatusPill extends StatelessWidget {
  const ShiftStatusPill({super.key, required this.isOpen});
  final bool isOpen;

  @override
  Widget build(BuildContext context) => OpsPill(
    isOpen ? 'Нээлттэй' : 'Хаагдсан',
    tone: isOpen ? OpsTone.ok : OpsTone.neutral,
    icon: isOpen ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
  );
}

/// Label / value row used across the shift cards and sheets.
class ShiftFigure extends StatelessWidget {
  const ShiftFigure({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.textStyles.caption.copyWith(fontSize: 13),
          ),
        ),
        Text(
          value,
          style: opsMono(
            context,
            fontSize: bold ? 15 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? context.colors.textPrimary,
          ),
        ),
      ],
    ),
  );
}

/// Inline error box for sheets/forms (server message).
class ShiftErrorText extends StatelessWidget {
  const ShiftErrorText(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('cash_shift_error'),
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: context.colors.dangerBg,
      borderRadius: BorderRadius.circular(AppDimens.radiusSM),
    ),
    child: Text(
      message,
      style: TextStyle(color: context.colors.danger, fontSize: 13),
    ),
  );
}

/// Grab handle + title row of the shift sheets.
class ShiftSheetHeader extends StatelessWidget {
  const ShiftSheetHeader({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Center(
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 12),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      Text(title, style: context.textStyles.h3),
      if (subtitle != null) ...[
        const SizedBox(height: 2),
        Text(subtitle!, style: context.textStyles.caption),
      ],
      const SizedBox(height: 16),
    ],
  );
}

/// Summary card of one shift: list rows and the current-shift card.
class CashShiftSummary extends StatelessWidget {
  const CashShiftSummary({super.key, required this.shift});
  final CashShift shift;

  @override
  Widget build(BuildContext context) {
    final s = shift;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShiftFigure(label: 'Эхний үлдэгдэл', value: formatMoney(s.openingCash)),
        if (s.cashIn != null)
          ShiftFigure(label: 'Бэлэн орлого', value: formatMoney(s.cashIn)),
        if (s.cashOut != null)
          ShiftFigure(label: 'Бэлэн зарлага', value: formatMoney(s.cashOut)),
        ShiftFigure(
          label: s.isOpen ? 'Байх ёстой (одоо)' : 'Байх ёстой',
          value: formatMoney(s.expectedCash),
          bold: true,
        ),
        if (!s.isOpen) ...[
          ShiftFigure(label: 'Тоолсон', value: formatMoney(s.countedCash)),
          ShiftFigure(
            label: 'Зөрүү',
            value: formatSignedMoney(s.difference),
            valueColor: differenceColor(context, s.difference),
            bold: true,
          ),
        ],
      ],
    );
  }
}
