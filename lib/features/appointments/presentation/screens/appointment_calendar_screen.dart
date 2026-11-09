import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/breakpoints.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/calendar_controller.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/calendar/calendar_agenda_list.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/calendar/calendar_day_grid.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/calendar/calendar_legend.dart';

final _dateFmt = DateFormat('yyyy.MM.dd (EEE)', 'mn');

/// Calendar surface — P2-F3. Tablet (>= [AdaptiveBreakpoints.compact]) shows
/// the day grid, phone shows the agenda; both render the same
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

/// View-switcher modes — P5. "Day" is the existing grid/agenda (auto-picked
/// by breakpoint, unchanged). "List" forces the agenda rendering regardless
/// of width — useful on a tablet when a flat chronological list is more
/// useful than the lane grid. "Week" is a lightweight 7-day overview built
/// from [CalendarController.monthCounts] (the same decoration-only counts
/// already used for the date-nav dot) rather than a full per-hour week grid:
/// the day-grid TRUTH model (`CalendarDayModel`) is fetched per single day
/// only, so a true hour-by-hour week grid would mean fetching and rendering
/// 7x the schedule data this screen has never needed before. Tapping a day
/// in the week strip jumps the controller to that date and switches back to
/// Day, which already renders the full authoritative view for it.
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
        return Scaffold(
          backgroundColor: theme.shellBackground,
          appBar: AppBar(
            title: const Text('Хуанли'),
            actions: [
              IconButton(
                tooltip: 'Шинэчлэх',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: widget.controller.refresh,
              ),
            ],
          ),
          body: Column(
            children: [
              _DateNav(controller: widget.controller),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.paddingMD,
                  vertical: AppDimens.paddingXS,
                ),
                child: _ViewModeSwitcher(
                  key: const ValueKey('appointment_calendar_view_switcher'),
                  mode: _viewMode,
                  onChanged: (mode) => setState(() => _viewMode = mode),
                ),
              ),
              Expanded(
                child: _viewMode == _CalendarViewMode.week
                    ? _WeekView(
                        controller: widget.controller,
                        onSelectDay: (day) {
                          widget.controller.setDate(day);
                          setState(() => _viewMode = _CalendarViewMode.day);
                        },
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final size = AdaptiveBreakpoints.ofWidth(
                            constraints.maxWidth,
                          );
                          return AsyncStateView<CalendarDayModel>(
                            state: widget.controller.state,
                            error: (context, error) => _ErrorView(
                              message: error.display,
                              // The dedicated "no branch selected" error carries a
                              // prompt, not a transient failure — offering a retry
                              // button for it would just repeat the same error.
                              onRetry: error.code == 'NO_BRANCH_SELECTED'
                                  ? null
                                  : widget.controller.refresh,
                            ),
                            builder: (context, model) => Column(
                              children: [
                                if (model.legend.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppDimens.paddingMD,
                                      vertical: AppDimens.paddingSM,
                                    ),
                                    child: CalendarLegend(
                                      entries: model.legend,
                                    ),
                                  ),
                                if (model.hasCapacityOverflow)
                                  _OverflowBanner(model: model),
                                Expanded(
                                  child:
                                      _viewMode == _CalendarViewMode.list ||
                                          size == AdaptiveSize.phone
                                      ? CalendarAgendaList(
                                          key: ValueKey(
                                            'agenda-${model.dateKey}',
                                          ),
                                          model: model,
                                          onOpenBlock: widget.onOpenBlock,
                                          onCreateAt: widget.onCreateAt,
                                        )
                                      : CalendarDayGrid(
                                          key: ValueKey(
                                            'grid-${model.dateKey}',
                                          ),
                                          model: model,
                                          onOpenBlock: widget.onOpenBlock,
                                          onCreateAt: widget.onCreateAt,
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ViewModeSwitcher extends StatelessWidget {
  const _ViewModeSwitcher({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final _CalendarViewMode mode;
  final ValueChanged<_CalendarViewMode> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<_CalendarViewMode>(
    segments: const [
      ButtonSegment(
        value: _CalendarViewMode.day,
        label: Text('Өдөр'),
        icon: Icon(Icons.view_day_outlined, size: 16),
      ),
      ButtonSegment(
        value: _CalendarViewMode.week,
        label: Text('Долоо хоног'),
        icon: Icon(Icons.view_week_outlined, size: 16),
      ),
      ButtonSegment(
        value: _CalendarViewMode.list,
        label: Text('Жагсаалт'),
        icon: Icon(Icons.view_list_outlined, size: 16),
      ),
    ],
    selected: {mode},
    showSelectedIcon: false,
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}

/// Lightweight 7-day (Monday-start) overview — see [_CalendarViewMode] for
/// why this is counts-only rather than a full per-hour week grid. Uses
/// [CalendarController.monthCounts], the same decoration-only source as the
/// date-nav dot, so it inherits the exact same "absent means zero, never
/// re-derived" rule.
class _WeekView extends StatelessWidget {
  const _WeekView({required this.controller, required this.onSelectDay});

  final CalendarController controller;
  final ValueChanged<DateTime> onSelectDay;

  static const _weekdayLabels = ['Да', 'Мя', 'Лх', 'Пү', 'Ба', 'Бя', 'Ня'];

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    final anchor = controller.date;
    final monday = anchor.subtract(Duration(days: (anchor.weekday - 1) % 7));
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final now = DateTime.now();

    return ListView.separated(
      padding: const EdgeInsets.all(AppDimens.paddingMD),
      itemCount: days.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppDimens.paddingSM),
      itemBuilder: (context, index) {
        final day = days[index];
        final count = controller.countFor(day);
        final isSelected =
            day.year == anchor.year &&
            day.month == anchor.month &&
            day.day == anchor.day;
        final isToday =
            day.year == now.year &&
            day.month == now.month &&
            day.day == now.day;
        return InkWell(
          key: ValueKey('calendar_week_day_${day.toIso8601String()}'),
          onTap: () => onSelectDay(day),
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.paddingMD,
              vertical: AppDimens.paddingSM,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.accent.withValues(alpha: 0.1)
                  : theme.panel,
              border: Border.all(
                color: isSelected ? theme.accent : theme.border,
              ),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    _weekdayLabels[day.weekday % 7],
                    style: context.textStyles.captionMedium,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${day.year}.${day.month.toString().padLeft(2, '0')}.${day.day.toString().padLeft(2, '0')}'
                    '${isToday ? ' (Өнөөдөр)' : ''}',
                    style: context.textStyles.body,
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                    ),
                    child: Text(
                      '$count',
                      style: context.textStyles.caption.copyWith(
                        color: theme.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Text('—', style: context.textStyles.caption),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DateNav extends StatelessWidget {
  const _DateNav({required this.controller});

  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panel,
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.paddingSM,
          vertical: AppDimens.paddingXS,
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: controller.goToPreviousDay,
              tooltip: 'Өмнөх өдөр',
            ),
            Expanded(
              child: Center(
                child: InkWell(
                  onTap: controller.goToToday,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.paddingSM,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _safeDateLabel(controller.date),
                          style: context.textStyles.h3,
                        ),
                        _MonthCountDot(controller: controller),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: controller.goToNextDay,
              tooltip: 'Дараах өдөр',
            ),
          ],
        ),
      ),
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
            color: theme.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          ),
          child: Text(
            '$count',
            style: context.textStyles.caption.copyWith(
              color: theme.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: AppDimens.paddingMD,
        vertical: AppDimens.paddingXS,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.paddingSM,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.warn.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: theme.warn),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Энэ өдөр салбарын багтаамжаас хэтэрсэн цаг захиалга байна.',
              style: context.textStyles.caption.copyWith(color: theme.warn),
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
            Icon(Icons.event_busy_rounded, size: 48, color: theme.mutedText2),
            const SizedBox(height: AppDimens.paddingSM),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.textStyles.body,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppDimens.paddingMD),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Дахин оролдох'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
