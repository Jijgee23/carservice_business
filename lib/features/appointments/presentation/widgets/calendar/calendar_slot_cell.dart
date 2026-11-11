import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';

final _hm = DateFormat('HH:mm');

/// One empty lane/hour cell. Touch-native slot selection: a past cell (or
/// one outside the branch's configured slot capacity) renders as an inert
/// placeholder with no tap target and no "add" affordance at all; a future,
/// in-capacity cell with an [onTap] is the design's dashed "+ Сул цаг"
/// button a caller wires to appointment registration. The distinction is
/// entirely visual/interactive here — [CalendarEmptyCell.tappable] itself is
/// already decided by `calendar_grid_layout.dart` from the model's own
/// range/capacity fields.
class CalendarSlotCell extends StatelessWidget {
  const CalendarSlotCell({
    super.key,
    required this.hourStart,
    required this.tappable,
    this.onTap,
    this.showTime = false,
  });

  final DateTime hourStart;
  final bool tappable;
  final VoidCallback? onTap;

  /// "+ 10:00" instead of "+ Сул цаг" — for a list of slots, where the
  /// cell has no time axis next to it.
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    // No affordance without an action: a free slot the user cannot book
    // (no create permission) stays blank.
    if (!tappable || onTap == null) {
      return const SizedBox.expand();
    }
    final label = 'Захиалга авах: ${_hm.format(hourStart)}';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: CustomPaint(
            // Light: a day has many free slots, they must not shout.
            painter: _DashedBorderPainter(
              color: theme.mutedText3.withValues(alpha: 0.45),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    showTime ? '+ ${_hm.format(hourStart)}' : '+ Сул цаг',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.mutedText3,
                      fontFamily: showTime ? theme.monoFontFamily : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 1.5px dashed rounded outline.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect.deflate(0.75), const Radius.circular(10)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
