import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

/// One titled block of the appointment detail screen: a flat bordered panel
/// with a small caps heading, so every section reads the same way.
class AppointmentDetailSection extends StatelessWidget {
  const AppointmentDetailSection({
    super.key,
    this.title,
    this.trailing,
    required this.child,
  });

  final String? title;

  /// Sits at the end of the title row (e.g. a status chip).
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimens.paddingMD),
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        border: Border.all(color: context.opsDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null || trailing != null) ...[
            // A Wrap, so a wide trailing chip drops below the title on a
            // narrow screen or large text instead of overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppDimens.paddingSM,
              runSpacing: AppDimens.paddingXS,
              children: [
                if (title != null)
                  Text(title!.toUpperCase(), style: context.textStyles.label),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppDimens.paddingSM),
          ],
          child,
        ],
      ),
    );
  }
}

/// Lays buttons out two per row at equal width; an odd last one spans the
/// row. Keeps action blocks aligned instead of wrapping ragged.
class AppointmentButtonGrid extends StatelessWidget {
  const AppointmentButtonGrid({super.key, required this.buttons});

  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < buttons.length; i += 2) {
      final pair = i + 1 < buttons.length;
      rows.add(
        Row(
          children: [
            Expanded(child: buttons[i]),
            if (pair) ...[
              const SizedBox(width: AppDimens.paddingSM),
              Expanded(child: buttons[i + 1]),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppDimens.paddingSM),
          rows[i],
        ],
      ],
    );
  }
}

/// The detail screen's action buttons: one height, and side padding tight
/// enough that two fit a phone row without their labels wrapping.
ButtonStyle appointmentOutlinedButtonStyle(
  BuildContext context, {
  bool danger = false,
}) => OutlinedButton.styleFrom(
  minimumSize: _actionButtonSize,
  padding: _actionButtonPadding,
  foregroundColor: danger ? context.opsDanger : null,
  side: danger
      ? BorderSide(color: context.opsDanger.withValues(alpha: 0.6))
      : null,
);

ButtonStyle appointmentFilledButtonStyle() => FilledButton.styleFrom(
  minimumSize: _actionButtonSize,
  padding: _actionButtonPadding,
);

const _actionButtonSize = Size(0, 46);
const _actionButtonPadding = EdgeInsets.symmetric(horizontal: 12);
