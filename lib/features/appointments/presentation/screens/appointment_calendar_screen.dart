import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/calendar_controller.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/calendar/calendar_agenda_list.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/calendar/calendar_day_grid.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/calendar/calendar_legend.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/calendar/calendar_week_strip.dart';

final _dateFmt = DateFormat('yyyy.MM.dd (EEE)', 'mn');

/// Calendar surface — P2-F3, styled after the tenant-app design (Цаг
/// захиалга): header, week strip with booking dots, view chips, then the
/// lane day grid (every width) or the agenda list. Both render the same
/// [CalendarController] state built entirely from the server's
/// `GET /appointments/calendar` day-grid TRUTH model. This screen owns only
/// day/branch navigation chrome, the legend and loading/empty/error states —
/// never any schedule computation.
///
/// [onOpenBlock] and [onCreateAt] are left as optional callbacks rather than
/// hard-wired navigation: appointment detail (`P2-F5`) and staff
/// registration (`P2-F4`) are separate, not-yet-integrated slices, and
/// wiring `go_router` routes is `lib/app/router.dart`, a file this slice
/// does not own.
class AppointmentCalendarScreen extends StatefulWidget {
  const AppointmentCalendarScreen({
    super.key,
    required this.controller,
    this.onOpenBlock,
    this.onCreateAt,
  });

  final CalendarController controller;
  final void Function(CalendarBlock block)? onOpenBlock;
  final void Function(DateTime slotStart)? onCreateAt;

  @override
  State<AppointmentCalendarScreen> createState() =>
      _AppointmentCalendarScreenState();
}

/// View modes. "Day" is the lane grid. "List" is the chronological agenda
/// — a flat list when that reads better than lanes. "Week" is a lightweight
/// 7-day overview built from [CalendarController.monthCounts] (the same
/// decoration-only counts as the strip's dots) rather than a full per-hour
/// week grid: the day-grid TRUTH model (`CalendarDayModel`) is fetched per
/// single day only, so a true hour-by-hour week grid would mean fetching and
/// rendering 7x the schedule data. Tapping a day in the week overview jumps
/// the controller to that date and switches back to Day, which already
/// renders the full authoritative view for it.
enum _CalendarViewMode { day, week, list }

class _AppointmentCalendarScreenState extends State<AppointmentCalendarScreen> {
  bool _didLoad = false;
  _CalendarViewMode _viewMode = _CalendarViewMode.day;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoad) {
      _didLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final theme = CarserviceTheme.of(context);
        final controller = widget.controller;
        return Scaffold(
          backgroundColor: theme.shellBackground,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _Header(controller: controller),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CalendarWeekStrip(
                    weekOf: controller.date,
                    selected: controller.date,
                    onSelect: controller.setDate,
                    onPreviousWeek: () => controller.setDate(
                      controller.date.subtract(const Duration(days: 7)),
                    ),
                    onNextWeek: () => controller.setDate(
                      controller.date.add(const Duration(days: 7)),
                    ),
                    hasBookings: (day) => controller.countFor(day) > 0,
                  ),
                ),
                const SizedBox(height: 12),
                _ViewModeChips(
                  key: const ValueKey('appointment_calendar_view_switcher'),
                  mode: _viewMode,
                  onChanged: (mode) => setState(() => _viewMode = mode),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _viewMode == _CalendarViewMode.week
                      ? _WeekView(
                          controller: controller,
                          onSelectDay: (day) {
                            controller.setDate(day);
                            setState(() => _viewMode = _CalendarViewMode.day);
                          },
                        )
                      : AsyncStateView<CalendarDayModel>(
                          state: controller.state,
                          error: (context, error) => _ErrorView(
                            message: error.display,
                            // The dedicated "no branch selected" error
                            // carries a prompt, not a transient failure —
                            // offering a retry button for it would just
                            // repeat the same error.
                            onRetry: error.code == 'NO_BRANCH_SELECTED'
                                ? null
                                : controller.refresh,
                          ),
                          builder: (context, model) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (model.legend.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    8,
                                  ),
                                  child: CalendarLegend(entries: model.legend),
                                ),
                              if (model.hasCapacityOverflow)
                                _OverflowBanner(model: model),
                              // The grid alone would read as "loading";
                              // the agenda carries its own empty state.
                              if (_viewMode == _CalendarViewMode.day &&
                                  model.blocks.isEmpty)
                                const _EmptyDayNote(),
                              Expanded(
                                child: _viewMode == _CalendarViewMode.list
                                    ? CalendarAgendaList(
                                        key: ValueKey(
                                          'agenda-${model.dateKey}',
                                        ),
                                        model: model,
                                        onOpenBlock: widget.onOpenBlock,
                                        onCreateAt: widget.onCreateAt,
                                      )
                                    : CalendarDayGrid(
                                        key: ValueKey('grid-${model.dateKey}'),
                                        model: model,
                                        onOpenBlock: widget.onOpenBlock,
                                        onCreateAt: widget.onCreateAt,
                                      ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ← | "Хуанли" + the day (with its booking count) | today, refresh.
class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    final canPop = Navigator.of(context).canPop();
    return Row(
      children: [
        if (canPop) ...[
          OpsCircleButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Буцах',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Хуанли',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.22,
                  color: theme.ink,
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _safeDateLabel(controller.date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: theme.mutedText),
                    ),
                  ),
                  _MonthCountDot(controller: controller),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OpsCircleButton(
          icon: Icons.today_rounded,
          tooltip: 'Өнөөдөр',
          onPressed: controller.goToToday,
        ),
        const SizedBox(width: 8),
        OpsCircleButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Шинэчлэх',
          onPressed: controller.refresh,
        ),
      ],
    );
  }

  String _safeDateLabel(DateTime date) {
    try {
      return _dateFmt.format(date);
    } catch (_) {
      return DateFormat('yyyy.MM.dd').format(date);
    }
  }
}

/// Өдөр / Долоо хоног / Жагсаалт as the design's filter chips.
class _ViewModeChips extends StatelessWidget {
  const _ViewModeChips({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final _CalendarViewMode mode;
  final ValueChanged<_CalendarViewMode> onChanged;

  static const _labels = {
    _CalendarViewMode.day: 'Өдөр',
    _CalendarViewMode.week: 'Долоо хоног',
    _CalendarViewMode.list: 'Жагсаалт',
  };

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final entry in _labels.entries) ...[
          if (entry.key != _CalendarViewMode.day) const SizedBox(width: 6),
          CalendarFilterChip(
            label: entry.value,
            selected: mode == entry.key,
            onTap: () => onChanged(entry.key),
          ),
        ],
      ],
    ),
  );
}

/// Lightweight 7-day (Monday-start) overview — see [_CalendarViewMode] for
/// why this is counts-only rather than a full per-hour week grid. Uses
/// [CalendarController.monthCounts], the same decoration-only source as the
/// strip's dots, so it inherits the exact same "absent means zero, never
/// re-derived" rule.
class _WeekView extends StatelessWidget {
  const _WeekView({required this.controller, required this.onSelectDay});

  final CalendarController controller;
  final ValueChanged<DateTime> onSelectDay;

  static const _weekdayLabels = [
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
    final theme = CarserviceTheme.of(context);
    final anchor = controller.date;
    final monday = calendarWeekStart(anchor);
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final now = DateTime.now();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: days.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final day = days[index];
        final count = controller.countFor(day);
        final isSelected = DateUtils.isSameDay(day, anchor);
        final isToday = DateUtils.isSameDay(day, now);
        return OpsCard(
          key: ValueKey('calendar_week_day_${day.toIso8601String()}'),
          onTap: () => onSelectDay(day),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          borderColor: isSelected ? theme.ink : null,
          borderWidth: isSelected ? 2 : 1,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_weekdayLabels[day.weekday - 1]}'
                      '${isToday ? ' · Өнөөдөр' : ''}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isToday ? theme.accent : theme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.year}.${day.month.toString().padLeft(2, '0')}.'
                      '${day.day.toString().padLeft(2, '0')}',
                      style: opsMono(context),
                    ),
                  ],
                ),
              ),
              if (count > 0)
                OpsPill('$count захиалга', tone: OpsTone.accent)
              else
                Text('—', style: TextStyle(color: theme.mutedText)),
            ],
          ),
        );
      },
    );
  }
}

/// The selected day's appointment count, sourced from
/// [CalendarController.monthCounts] (`getMonthCounts` — P2-F1b), never
/// re-derived from the day grid. Renders nothing for a day absent from the
/// map (zero appointments, or counts not yet loaded/failed to load) — a
/// missing entry is not "zero appointments, shown as a dot", it is simply
/// undecorated, matching the repository contract's "absent means zero"
/// rule and this feature's "dots are decoration, never truth" invariant.
class _MonthCountDot extends StatelessWidget {
  const _MonthCountDot({required this.controller});

  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    final count = controller.countFor(controller.date);
    if (count <= 0) return const SizedBox.shrink();
    final theme = CarserviceTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Semantics(
        label: 'Энэ өдөр $count цаг захиалга',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: OpsTone.accent.background(theme),
            borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontFamily: theme.monoFontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDayNote extends StatelessWidget {
  const _EmptyDayNote();

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 16,
            color: theme.mutedText3,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Энэ өдөр цаг захиалга алга',
              style: TextStyle(fontSize: 13, color: theme.mutedText),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverflowBanner extends StatelessWidget {
  const _OverflowBanner({required this.model});

  final CalendarDayModel model;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: OpsTone.warn.background(theme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: theme.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Энэ өдөр салбарын багтаамжаас хэтэрсэн цаг захиалга байна.',
              style: TextStyle(fontSize: 13, color: theme.warn),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.paddingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded, size: 48, color: theme.mutedText3),
            const SizedBox(height: AppDimens.paddingSM),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: theme.mutedText),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppDimens.paddingMD),
              OpsSecondaryButton(
                onPressed: onRetry,
                icon: Icons.refresh_rounded,
                label: 'Дахин оролдох',
                height: 44,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
