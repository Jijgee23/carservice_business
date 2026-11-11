import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';

/// Monday of [day]'s week, date-only.
DateTime calendarWeekStart(DateTime day) {
  final d = DateUtils.dateOnly(day);
  return d.subtract(Duration(days: d.weekday - 1));
}

/// The design's week picker: seven day buttons (Monday first) in a white
/// rounded strip, ‹ › to page weeks. The selected day is navy; a day with
/// bookings carries an accent dot ([hasBookings], decoration only — absent
/// data draws no dot); Sunday is muted. Shared by the appointments tab and
/// the calendar screen.
class CalendarWeekStrip extends StatelessWidget {
  const CalendarWeekStrip({
    super.key,
    required this.weekOf,
    required this.selected,
    required this.onSelect,
    required this.onPreviousWeek,
    required this.onNextWeek,
    this.hasBookings,
    this.now,
    this.dayKeyPrefix = 'calendar_week_strip_day',
  });

  /// Any day of the week to show.
  final DateTime weekOf;

  /// Null selects no day (e.g. the every-date list).
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final bool Function(DateTime day)? hasBookings;

  /// Injectable for tests; defaults to the wall clock.
  final DateTime? now;

  /// Each day button is keyed `'<prefix>_<yyyy-MM-dd>'`.
  final String dayKeyPrefix;

  static const _short = ['Дав', 'Мяг', 'Лха', 'Пүр', 'Баа', 'Бям', 'Ням'];
  static const _full = [
    'Даваа',
    'Мягмар',
    'Лхагва',
    'Пүрэв',
    'Баасан',
    'Бямба',
    'Ням',
  ];

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final start = calendarWeekStart(weekOf);
    final today = DateUtils.dateOnly(now ?? DateTime.now());
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          _PageButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Өмнөх долоо хоног',
            onPressed: onPreviousWeek,
          ),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayButton(
                key: ValueKey(
                  '${dayKeyPrefix}_${_isoDate(start.add(Duration(days: i)))}',
                ),
                day: start.add(Duration(days: i)),
                shortLabel: _short[i],
                fullLabel: _full[i],
                selected:
                    selected != null &&
                    DateUtils.isSameDay(selected, start.add(Duration(days: i))),
                isToday: DateUtils.isSameDay(
                  today,
                  start.add(Duration(days: i)),
                ),
                dot: hasBookings?.call(start.add(Duration(days: i))) ?? false,
                onTap: () => onSelect(start.add(Duration(days: i))),
              ),
            ),
          _PageButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Дараах долоо хоног',
            onPressed: onNextWeek,
          ),
        ],
      ),
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 30, minHeight: 44),
    color: CarserviceTheme.of(context).mutedText,
    icon: Icon(icon, size: 20),
  );
}

class _DayButton extends StatelessWidget {
  const _DayButton({
    super.key,
    required this.day,
    required this.shortLabel,
    required this.fullLabel,
    required this.selected,
    required this.isToday,
    required this.dot,
    required this.onTap,
  });

  final DateTime day;
  final String shortLabel;
  final String fullLabel;
  final bool selected;
  final bool isToday;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final sunday = day.weekday == DateTime.sunday;
    final dateColor = selected
        ? t.shellBackground
        : isToday
        ? t.accent
        : sunday
        ? t.mutedText3
        : t.ink;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${day.month}-р сарын ${day.day}, $fullLabel'
          '${isToday ? ', өнөөдөр' : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? t.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shortLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: selected
                          ? t.shellBackground.withValues(alpha: 0.75)
                          : t.mutedText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: dateColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dot ? t.accentHi : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The design's pill chip: white with a hairline, navy when selected.
class CalendarFilterChip extends StatelessWidget {
  const CalendarFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    final shape = StadiumBorder(
      side: BorderSide(color: selected ? theme.ink : theme.border),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? theme.ink : theme.panel,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? theme.shellBackground : theme.ink,
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
