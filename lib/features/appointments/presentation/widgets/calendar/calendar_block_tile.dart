import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';

import 'calendar_status_style.dart';
import 'calendar_time_format.dart';

/// Renders one [CalendarBlock] — shared between the day grid and the
/// agenda list so both surfaces stay visually and semantically consistent.
/// Styled as the design's booking block: navy when confirmed, a pale tint
/// for the other statuses ([calendarStatusStyle]), a red outline for an
/// issue.
///
/// [dense] controls how much visible content a narrow rendering keeps
/// (grid cells can be a few dozen pixels tall); the block's full meaning is
/// never lost even when [dense] drops most of the visible text, because the
/// whole tile is wrapped in a single [Semantics] node carrying the
/// server-built [CalendarBlock.accessibleLabel] verbatim — that string
/// already contains every fact the block conveys (time range, name,
/// status, payment, issue, overflow), see `calendar-day-model.ts`'s
/// `buildAccessibleLabel`. This widget must never rebuild that sentence
/// from parts; it only renders (a subset of) the same facts visually.
class CalendarBlockTile extends StatelessWidget {
  const CalendarBlockTile({
    super.key,
    required this.block,
    this.dense = false,
    this.onTap,
  });

  final CalendarBlock block;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    final style = calendarStatusStyle(context, block.status);
    final timeLabel = calendarBlockTimeLabel(block);
    final issue = block.issue;
    final markerSize = dense ? 12.0 : 14.0;
    // On the solid navy block the tinted warn/danger colours would not
    // read; the markers take the block's text colour there.
    final confirmed = block.status == AppointmentStatus.CONFIRMED;

    final side = issue != null
        ? BorderSide(color: theme.danger, width: 1.5)
        : style.border != null
        ? BorderSide(color: style.border!)
        : BorderSide.none;

    return Semantics(
      label: block.accessibleLabel,
      button: onTap != null,
      excludeSemantics: true,
      child: Material(
        color: style.background,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: side,
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 6 : 8,
              vertical: dense ? 3 : 6,
            ),
            // A grid cell has a fixed height: clip what does not fit
            // instead of overflowing (the semantics label keeps it all).
            child: ClipRect(
              child: UnconstrainedBox(
                constrainedAxis: Axis.horizontal,
                alignment: Alignment.topLeft,
                clipBehavior: Clip.hardEdge,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            block.name,
                            maxLines: dense ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 15 / 12,
                              fontWeight: FontWeight.w600,
                              color: style.foreground,
                            ),
                          ),
                        ),
                        if (block.capacityOverflow)
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: markerSize,
                              color: confirmed ? style.foreground : theme.warn,
                            ),
                          ),
                        if (issue != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Icon(
                              Icons.error_outline_rounded,
                              size: markerSize,
                              color: confirmed
                                  ? style.foreground
                                  : theme.danger,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // Open-ended/unknown-finish work is visually
                        // distinct from a known finish — a dedicated icon,
                        // not just the text, so it still reads at a glance
                        // in a dense cell.
                        if (!block.finishKnown)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Icon(
                              Icons.all_inclusive_rounded,
                              size: markerSize,
                              color: style.secondary,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            timeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: theme.monoFontFamily,
                              fontSize: 11,
                              color: style.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!dense) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          _Fact(
                            label: block.statusLabel,
                            color: style.foreground,
                            strong: true,
                          ),
                          if (block.paymentStatusLabel != null)
                            _Fact(
                              label: block.paymentStatusLabel!,
                              color: style.secondary,
                            ),
                          if (issue != null)
                            _Fact(label: issue.label, color: style.foreground),
                          if (block.capacityOverflow)
                            _Fact(
                              label: 'Багтаамжаас хэтэрсэн',
                              color: style.foreground,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.color, this.strong = false});

  final String label;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontSize: 11,
      fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
      color: color,
    ),
  );
}
