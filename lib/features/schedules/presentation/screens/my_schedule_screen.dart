import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/features/schedules/domain/schedule.dart';
import 'package:carservice_business/features/schedules/domain/schedules_repository.dart';
import 'package:carservice_business/features/schedules/presentation/controllers/my_schedule_controller.dart';
import 'package:carservice_business/features/schedules/presentation/schedule_dates.dart';
import 'package:carservice_business/features/schedules/presentation/widgets/schedule_day_detail_sheet.dart';
import 'package:carservice_business/features/schedules/presentation/widgets/schedule_legend.dart';

const _kWeekdayHeaders = ['Да', 'Мя', 'Лх', 'Пү', 'Ба', 'Бя', 'Ня'];

/// Real month calendar of the caller's own resolved schedule —
/// `GET /api/v1/me/schedule` — P6-F4. No permission gate: every
/// authenticated user may see their own schedule, and there is no write
/// affordance here at all (parity with `app/dashboard/my-schedule/
/// month-calendar.tsx`).
///
/// Full-screen layout: the month grid stretches its rows to fill whatever
/// height is left under the header and summary, so the whole month is
/// visible at once on any phone or tablet without scrolling. Swipe the grid
/// sideways (or use the arrows) to change month.
class MyScheduleScreen extends StatelessWidget {
  const MyScheduleScreen({super.key, this.repository});

  final SchedulesRepository? repository;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => MyScheduleController(repo: repository)..load(),
    child: const _Body(),
  );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MyScheduleController>();
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Миний хуваарь'),
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Шинэчлэх',
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _MonthHeader(controller: controller),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: switch (controller.state.valueOrNull) {
                final MySchedule s => _SummaryStrip(
                  key: ValueKey('summary_${ymd(controller.month)}'),
                  stats: _MonthStats.of(controller.month, s),
                ),
                null => const SizedBox(height: 8),
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(AppDimens.radiusXL),
                  border: Border.all(color: colors.divider),
                ),
                child: Column(
                  children: [
                    const _WeekdayHeader(),
                    const SizedBox(height: 6),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v.abs() < 250) return;
                          v < 0
                              ? controller.nextMonth()
                              : controller.prevMonth();
                        },
                        child: AsyncStateView<MySchedule>(
                          state: controller.state,
                          onRetry: controller.refresh,
                          builder: (context, mySchedule) => _MonthGrid(
                            month: controller.month,
                            mySchedule: mySchedule,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: ScheduleLegend(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.controller});
  final MyScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final m = controller.month;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${m.year} он',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                Text(
                  '${m.month}-р сар',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          if (!controller.isCurrentMonth)
            TextButton.icon(
              key: const ValueKey('my_schedule_today'),
              onPressed: controller.goToCurrentMonth,
              icon: const Icon(Icons.today_rounded, size: 18),
              label: const Text('Энэ сар'),
            ),
          _RoundIconButton(
            key: const ValueKey('my_schedule_prev_month'),
            icon: Icons.chevron_left_rounded,
            tooltip: 'Өмнөх сар',
            onPressed: controller.prevMonth,
          ),
          const SizedBox(width: 6),
          _RoundIconButton(
            key: const ValueKey('my_schedule_next_month'),
            icon: Icons.chevron_right_rounded,
            tooltip: 'Дараах сар',
            onPressed: controller.nextMonth,
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.surface,
    shape: CircleBorder(side: BorderSide(color: context.colors.divider)),
    clipBehavior: Clip.antiAlias,
    child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon)),
  );
}

// ─── Summary ──────────────────────────────────────────────────────────────────

/// Totals for the in-month days only — leading/trailing days of the grid
/// belong to other months and are not counted.
class _MonthStats {
  const _MonthStats({
    required this.workDays,
    required this.restDays,
    required this.minutes,
  });

  final int workDays;
  final int restDays;
  final int minutes;

  factory _MonthStats.of(DateTime month, MySchedule s) {
    var work = 0;
    var rest = 0;
    var minutes = 0;
    for (var d = 1; d <= daysInMonth(month.year, month.month); d++) {
      final cell = s.cells[ymd(DateTime(month.year, month.month, d))];
      if (cell?.working ?? false) {
        work++;
        for (final seg in cell!.segments) {
          minutes += segmentMinutes(seg) ?? 0;
        }
      } else {
        rest++;
      }
    }
    return _MonthStats(workDays: work, restDays: rest, minutes: minutes);
  }

  String get hoursLabel {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h ц' : '$h ц $m м';
  }
}

/// Length of one `HH:mm–HH:mm` segment in minutes; an end before the start
/// is an overnight shift. Null when either time is missing or malformed.
int? segmentMinutes(ScheduleSegment seg) {
  int? parse(String? t) {
    final parts = t?.split(':');
    if (parts == null || parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  final start = parse(seg.startTime);
  final end = parse(seg.endTime);
  if (start == null || end == null) return null;
  return end >= start ? end - start : end + 24 * 60 - start;
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({super.key, required this.stats});
  final _MonthStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.work_outline_rounded,
              label: 'Ажлын өдөр',
              value: '${stats.workDays}',
              color: colors.good,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatTile(
              icon: Icons.weekend_outlined,
              label: 'Амралт',
              value: '${stats.restDays}',
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatTile(
              icon: Icons.schedule_rounded,
              label: 'Нийт цаг',
              value: stats.hoursLabel,
              color: colors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDimens.radiusSM),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grid ─────────────────────────────────────────────────────────────────────

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Center(
            child: Text(
              _kWeekdayHeaders[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: i >= 5
                    ? context.colors.danger.withValues(alpha: 0.75)
                    : context.colors.textSecondary,
              ),
            ),
          ),
        ),
    ],
  );
}

/// Rows share the available height equally (5 or 6 weeks), so the month
/// always fills the screen exactly — no scrolling, no empty band.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.mySchedule});
  final DateTime month;
  final MySchedule mySchedule;

  @override
  Widget build(BuildContext context) {
    final cells = monthGrid(month);
    final rows = cells.length ~/ 7;
    final today = dateOnly(DateTime.now());
    return Column(
      key: const ValueKey('my_schedule_month_grid'),
      children: [
        for (var r = 0; r < rows; r++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _DayTile(
                      date: cells[r * 7 + c].date,
                      inMonth: cells[r * 7 + c].inMonth,
                      isToday: cells[r * 7 + c].date == today,
                      cell: mySchedule.cells[ymd(cells[r * 7 + c].date)],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.date,
    required this.inMonth,
    required this.isToday,
    this.cell,
  });

  final DateTime date;
  final bool inMonth;
  final bool isToday;
  final ScheduleCell? cell;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = cell;
    final working = c?.working ?? false;
    final segments = working ? c!.segments : const <ScheduleSegment>[];
    final first = segments.isEmpty ? null : segments.first;

    return Opacity(
      opacity: inMonth ? 1 : 0.38,
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: Material(
          color: working
              ? colors.good.withValues(alpha: 0.10)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            side: isToday
                ? BorderSide(color: colors.accent, width: 1.6)
                : BorderSide(
                    color: working
                        ? colors.good.withValues(alpha: 0.25)
                        : colors.divider.withValues(alpha: 0.6),
                  ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('my_schedule_day_${ymd(date)}'),
            onTap: () =>
                ScheduleDayDetailSheet.show(context, date: date, cell: c),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, 4, 4),
              child: LayoutBuilder(
                builder: (context, box) {
                  // Tall cells (tablets, tall phones) show start and end on
                  // separate lines; short ones compress to "09–18".
                  final roomy = box.maxHeight >= 70;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: _DayNumber(
                                day: date.day,
                                isToday: isToday,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Spacer(),
                          if (c != null)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: scheduleSourceColor(context, c.source),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      if (working)
                        _TimeLabel(
                          first: first,
                          extra: segments.length - 1,
                          roomy: roomy,
                        )
                      else if (box.maxHeight >= 44)
                        Text(
                          'Амрах',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9.5,
                            color: colors.textHint,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({required this.day, required this.isToday});
  final int day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Text(
      '$day',
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
        color: isToday
            ? CarserviceTheme.of(context).onAccent
            : colors.textPrimary,
      ),
    );
    if (!isToday) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(AppDimens.radiusSM),
      ),
      child: text,
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({
    required this.first,
    required this.extra,
    required this.roomy,
  });

  final ScheduleSegment? first;
  final int extra;
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: colors.good,
      height: 1.2,
    );
    final s = first;
    if (s == null) {
      return Text('Ажил', maxLines: 1, style: style);
    }
    final start = s.startTime ?? '--:--';
    final end = s.endTime ?? '--:--';
    final more = extra > 0 ? ' +$extra' : '';
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomLeft,
      child: roomy
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(start, style: style),
                Text(
                  '$end$more',
                  style: style.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            )
          : Text('${_short(start)}–${_short(end)}$more', style: style),
    );
  }

  /// "09:00" → "09", "09:30" keeps its minutes.
  static String _short(String t) =>
      t.endsWith(':00') ? t.substring(0, t.length - 3) : t;
}
