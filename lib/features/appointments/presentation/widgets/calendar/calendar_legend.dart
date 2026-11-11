import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';

import 'calendar_status_style.dart';

/// Renders [CalendarDayModel.legend] — and only that list. The server
/// already restricts it to statuses/issues actually present that day (see
/// `buildCalendarDayModel`'s `statusSeen`/`issueSeen` maps); this widget
/// must never invent, reorder-by-importance, or add an entry the model did
/// not send, or the "only what's present today" guarantee is broken on the
/// client side even though the server got it right.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend({super.key, required this.entries});

  final List<CalendarLegendEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = CarserviceTheme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final entry in entries)
          switch (entry) {
            CalendarLegendStatus(:final status, :final label) => _LegendItem(
              color: calendarStatusColor(context, status),
              label: label,
              icon: calendarStatusIcon(status),
            ),
            CalendarLegendIssue(:final label) => _LegendItem(
              color: theme.danger,
              label: label,
              icon: Icons.error_outline_rounded,
            ),
          },
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.icon,
  });

  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: CarserviceTheme.of(context).mutedText,
          ),
        ),
      ],
    ),
  );
}
