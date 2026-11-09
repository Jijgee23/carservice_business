import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

// ─── Public API ───────────────────────────────────────────────────────────────

/// How the calendar body is laid out. The user can also switch between the
/// two inside the sheet; this only picks the one it opens on.
enum AppDatePickerView {
  /// Full month grid (6 fixed rows, so the sheet never jumps in height).
  month,

  /// One week strip — quicker for "this/last week" style picks.
  week,
}

/// Modern bottom-sheet date picker — a single date, a date range, or a date
/// with a time of day. The app's only date picker.
///
/// ```dart
/// final day = await AppDatePicker.single(context, initial: DateTime.now());
///
/// final at = await AppDatePicker.dateTime(
///   context,
///   initial: order.scheduledAt,
///   startHour: 0,
///   endHour: 23,
/// );
///
/// final range = await AppDatePicker.range(
///   context,
///   initial: DateTimeRange(start: from, end: to),
///   lastDate: DateTime.now(),
///   view: AppDatePickerView.week,
/// );
/// ```
///
/// Guarantees, so callers need no defensive code:
/// - [single]/[range] results are date-only (local midnight); `range.end` is
///   the last *included* day, never the day after. [dateTime] results carry
///   the picked half-hour slot.
/// - Results always lie within [firstDate]…[lastDate]; days outside are
///   shown but cannot be tapped.
/// - An out-of-bounds `initial` is clamped in, never thrown on.
/// - A range can only be confirmed once both ends are picked; the start is
///   never after the end (a one-day range is start == end).
/// - `null` means the user dismissed or cancelled.
abstract final class AppDatePicker {
  static Future<DateTime?> single(
    BuildContext context, {
    DateTime? initial,
    DateTime? firstDate,
    DateTime? lastDate,
    AppDatePickerView view = AppDatePickerView.month,
    String title = 'Огноо сонгох',
  }) async {
    final bounds = _Bounds.of(firstDate, lastDate);
    final start = initial == null ? null : bounds.clamp(initial);
    final result = await _show(context, AppDateSelection.single(start), bounds, view, title);
    return result?.selection.start;
  }

  static Future<DateTimeRange?> range(
    BuildContext context, {
    DateTimeRange? initial,
    DateTime? firstDate,
    DateTime? lastDate,
    AppDatePickerView view = AppDatePickerView.month,
    String title = 'Хугацаа сонгох',
  }) async {
    final bounds = _Bounds.of(firstDate, lastDate);
    final selection = initial == null
        ? const AppDateSelection.range()
        : AppDateSelection.range(
            start: bounds.clamp(initial.start),
            end: bounds.clamp(initial.end),
          );
    final result = await _show(context, selection, bounds, view, title);
    final picked = result?.selection;
    if (picked == null || !picked.isComplete) return null;
    return DateTimeRange(start: picked.start!, end: picked.end!);
  }

  /// A day and a time of day, the time in half-hour slots from
  /// [startHour]:00 to [endHour]:00 — scheduling an order or an appointment.
  ///
  /// [initial]'s time snaps to the latest slot at or before it (see
  /// [appSnapToSlot]); with no [initial] the sheet opens on the first slot.
  static Future<DateTime?> dateTime(
    BuildContext context, {
    DateTime? initial,
    DateTime? firstDate,
    DateTime? lastDate,
    int startHour = 8,
    int endHour = 20,
    AppDatePickerView view = AppDatePickerView.month,
    String title = 'Огноо, цаг сонгох',
  }) async {
    assert(
      0 <= startHour && startHour <= endHour && endHour <= 23,
      'AppDatePicker.dateTime: need 0 <= startHour <= endHour <= 23',
    );
    final bounds = _Bounds.of(firstDate, lastDate);
    final slots = appTimeSlots(startHour, endHour);
    final result = await _show(
      context,
      AppDateSelection.single(initial == null ? null : bounds.clamp(initial)),
      bounds,
      view,
      title,
      slots: slots,
      initialTime: initial == null
          ? slots.first
          : appSnapToSlot(TimeOfDay.fromDateTime(initial), slots),
    );
    final day = result?.selection.start;
    final time = result?.time;
    if (day == null || time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  static Future<_PickerResult?> _show(
    BuildContext context,
    AppDateSelection selection,
    _Bounds bounds,
    AppDatePickerView view,
    String title, {
    List<TimeOfDay>? slots,
    TimeOfDay? initialTime,
  }) {
    return AppNav.sheet<_PickerResult>(
      _PickerSheet(
        initial: selection,
        bounds: bounds,
        view: view,
        title: title,
        slots: slots,
        initialTime: initialTime,
      ),
      backgroundColor: Colors.transparent,
    );
  }
}

/// What the sheet pops: the day(s), plus the slot in [AppDatePicker.dateTime].
class _PickerResult {
  const _PickerResult(this.selection, this.time);
  final AppDateSelection selection;
  final TimeOfDay? time;
}

// ─── Selection logic (pure, unit-tested) ─────────────────────────────────────

/// Strips the time part — every date the picker touches goes through this.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d] (Mongolian weeks start on Monday).
DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Half-hour slots from [startHour]:00 to [endHour]:00 inclusive.
List<TimeOfDay> appTimeSlots(int startHour, int endHour) => [
  for (var h = startHour; h <= endHour; h++) ...[
    TimeOfDay(hour: h, minute: 0),
    if (h < endHour) TimeOfDay(hour: h, minute: 30),
  ],
];

/// The latest of [slots] at or before [time]; the first slot when [time] is
/// earlier than all of them, the last when it is past the window.
TimeOfDay appSnapToSlot(TimeOfDay time, List<TimeOfDay> slots) {
  final minutes = time.hour * 60 + time.minute;
  var snapped = slots.first;
  for (final slot in slots) {
    if (slot.hour * 60 + slot.minute <= minutes) snapped = slot;
  }
  return snapped;
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Which end of a range a tap fills.
enum AppRangeEdge { start, end }

/// Immutable picker state. [tap], [focus] and [span] are the only ways it
/// changes, so the start ≤ end invariant lives in exactly one place.
@immutable
class AppDateSelection {
  const AppDateSelection.single(this.start) : isRange = false, end = null, _focusEdge = null;

  const AppDateSelection.range({this.start, this.end}) : isRange = true, _focusEdge = null;

  const AppDateSelection._range(this.start, this.end, this._focusEdge) : isRange = true;

  final bool isRange;
  final DateTime? start;

  /// Always null in single mode.
  final DateTime? end;

  /// Edge the user explicitly chose by tapping a summary box; null = the
  /// default start-then-end flow.
  final AppRangeEdge? _focusEdge;

  /// Single: a day is picked. Range: both ends are picked.
  bool get isComplete => isRange ? start != null && end != null : start != null;

  /// Range mode: the edge the next tap fills, or null when the range is
  /// complete and the next tap simply starts a new one.
  AppRangeEdge? get nextEdge {
    if (!isRange) return null;
    if (_focusEdge != null) return _focusEdge;
    if (start == null) return AppRangeEdge.start;
    if (end == null) return AppRangeEdge.end;
    return null;
  }

  /// Inclusive day count of a complete range; 1 for a single pick.
  int? get dayCount {
    if (!isComplete) return null;
    if (!isRange) return 1;
    // Via UTC so a DST shift can never make this off by one.
    final s = DateTime.utc(start!.year, start!.month, start!.day);
    final e = DateTime.utc(end!.year, end!.month, end!.day);
    return e.difference(s).inDays + 1;
  }

  /// Range mode: make the next tap fill [edge] — lets the user pick the end
  /// date first, or fix just one end of a finished range.
  AppDateSelection focus(AppRangeEdge edge) =>
      isRange ? AppDateSelection._range(start, end, edge) : this;

  AppDateSelection tap(DateTime day) {
    final d = dateOnly(day);
    if (!isRange) return AppDateSelection.single(d);
    switch (_focusEdge) {
      case AppRangeEdge.start:
        // A start after the current end cannot keep that end.
        final keptEnd = end != null && d.isAfter(end!) ? null : end;
        return AppDateSelection._range(d, keptEnd, keptEnd == null ? AppRangeEdge.end : null);
      case AppRangeEdge.end:
        // An end before the current start cannot keep that start.
        final keptStart = start != null && d.isBefore(start!) ? null : start;
        return AppDateSelection._range(keptStart, d, keptStart == null ? AppRangeEdge.start : null);
      case null:
        // Nothing picked yet, or a finished range: this tap starts a new one.
        if (start == null || end != null) {
          return AppDateSelection.range(start: d);
        }
        // Tapping before the start moves the start instead of producing an
        // inverted range.
        if (d.isBefore(start!)) return AppDateSelection.range(start: d);
        return AppDateSelection.range(start: start, end: d);
    }
  }

  /// Range mode: the long-press-and-slide selection from [anchor] to
  /// [current], in whichever order the finger moved.
  AppDateSelection span(DateTime anchor, DateTime current) {
    if (!isRange) return AppDateSelection.single(dateOnly(current));
    final a = dateOnly(anchor);
    final c = dateOnly(current);
    return c.isBefore(a)
        ? AppDateSelection.range(start: c, end: a)
        : AppDateSelection.range(start: a, end: c);
  }

  bool isStart(DateTime d) => start != null && _sameDay(d, start!);

  bool isEnd(DateTime d) => end != null && _sameDay(d, end!);

  /// Strictly between start and end.
  bool isInside(DateTime d) =>
      start != null && end != null && d.isAfter(start!) && d.isBefore(end!);
}

class _Bounds {
  const _Bounds(this.first, this.last);

  factory _Bounds.of(DateTime? first, DateTime? last) {
    final f = dateOnly(first ?? DateTime(2000));
    final l = dateOnly(last ?? DateTime(2100));
    assert(!f.isAfter(l), 'AppDatePicker: firstDate must not be after lastDate');
    return f.isAfter(l) ? _Bounds(l, f) : _Bounds(f, l);
  }

  final DateTime first;
  final DateTime last;

  bool contains(DateTime d) => !d.isBefore(first) && !d.isAfter(last);

  DateTime clamp(DateTime d) {
    final x = dateOnly(d);
    if (x.isBefore(first)) return first;
    if (x.isAfter(last)) return last;
    return x;
  }
}

// ─── Localization ─────────────────────────────────────────────────────────────

const _kWeekdays = ['Да', 'Мя', 'Лх', 'Пү', 'Ба', 'Бя', 'Ня'];

String _ymd(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

String _md(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

String _hm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// ─── Sheet ────────────────────────────────────────────────────────────────────

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.initial,
    required this.bounds,
    required this.view,
    required this.title,
    this.slots,
    this.initialTime,
  });

  final AppDateSelection initial;
  final _Bounds bounds;
  final AppDatePickerView view;
  final String title;

  /// Non-null in [AppDatePicker.dateTime]: the half-hour slots to offer.
  final List<TimeOfDay>? slots;
  final TimeOfDay? initialTime;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late AppDateSelection _sel = widget.initial;
  late AppDatePickerView _view = widget.view;

  /// The day the visible period is built around: its month in month view,
  /// its week in week view. Switching views keeps it, so the user never
  /// loses their place.
  late DateTime _focus = widget.initial.start ?? widget.bounds.clamp(DateTime.now());

  /// +1 when navigating forward, -1 backward — drives the slide direction.
  int _direction = 0;

  /// Month-view header tapped: show the month/year jump grid instead.
  bool _jumping = false;

  /// [AppDatePicker.dateTime] only.
  late TimeOfDay? _time = widget.initialTime;
  final _timeScroll = ScrollController();

  static const _slotExtent = _TimeSlots.chipWidth + _TimeSlots.gap;

  @override
  void initState() {
    super.initState();
    // Open with the picked slot in view, not the window's first one.
    if (widget.slots != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealTime());
    }
  }

  @override
  void dispose() {
    _timeScroll.dispose();
    super.dispose();
  }

  void _revealTime() {
    final slots = widget.slots;
    final time = _time;
    if (!mounted || slots == null || time == null || !_timeScroll.hasClients) {
      return;
    }
    final index = slots.indexOf(time);
    if (index < 0) return;
    final position = _timeScroll.position;
    final target = index * _slotExtent - position.viewportDimension / 2 + _TimeSlots.chipWidth / 2;
    _timeScroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  _Bounds get _bounds => widget.bounds;

  // ─── Periods ───────────────────────────────────────────────────────────────

  DateTime get _periodStart =>
      _view == AppDatePickerView.month ? DateTime(_focus.year, _focus.month, 1) : mondayOf(_focus);

  DateTime get _periodEnd => _view == AppDatePickerView.month
      ? DateTime(_focus.year, _focus.month + 1, 0)
      : DateTime(_periodStart.year, _periodStart.month, _periodStart.day + 6);

  DateTime _shifted(int delta) => _view == AppDatePickerView.month
      ? DateTime(_focus.year, _focus.month + delta, 1)
      : DateTime(_focus.year, _focus.month, _focus.day + 7 * delta);

  bool get _canPrev => _periodStart.isAfter(_bounds.first);

  bool get _canNext => _periodEnd.isBefore(_bounds.last);

  void _go(int delta) {
    if (delta < 0 ? !_canPrev : !_canNext) return;
    setState(() {
      _direction = delta;
      _focus = _shifted(delta);
    });
  }

  void _goToday() {
    final today = _bounds.clamp(DateTime.now());
    setState(() {
      _direction = today.isBefore(_periodStart) ? -1 : 1;
      _focus = today;
      _jumping = false;
    });
  }

  void _setView(AppDatePickerView view) {
    if (view == _view) return;
    setState(() {
      // Land on the week/month that holds the selection when it is in the
      // visible period, so toggling never hides what the user just picked.
      final s = _sel.start;
      if (s != null && !s.isBefore(_periodStart) && !s.isAfter(_periodEnd)) {
        _focus = s;
      }
      _view = view;
      _direction = 0;
      _jumping = false;
    });
  }

  void _tap(DateTime day) {
    if (!_bounds.contains(day)) return;
    setState(() => _sel = _sel.tap(day));
  }

  // ─── Press + drag (range mode only) ────────────────────────────────────────
  //
  // In range mode the grid owns every touch: releasing on the pressed day is
  // a normal tap (same rules as [_tap], including the chosen edge); moving
  // onto another day turns it into a span from the pressed day.

  DateTime? _dragAnchor;
  DateTime? _dragLast;
  bool _spanning = false;

  late final _SpanDrag? _spanDrag = widget.initial.isRange
      ? _SpanDrag(start: _dragStart, update: _dragUpdate, end: _dragEnd)
      : null;

  void _dragStart(DateTime day) {
    _dragAnchor = day;
    _dragLast = day;
    _spanning = false;
  }

  void _dragUpdate(DateTime day) {
    final anchor = _dragAnchor;
    if (anchor == null || day == _dragLast) return;
    _dragLast = day;
    if (!_spanning && day == anchor) return;
    _spanning = true;
    HapticFeedback.selectionClick();
    // Out-of-bounds days snap to the nearest allowed one, so the result can
    // never leave firstDate…lastDate however far the finger travels.
    setState(() => _sel = _sel.span(_bounds.clamp(anchor), _bounds.clamp(day)));
  }

  void _dragEnd() {
    final anchor = _dragAnchor;
    final wasTap = !_spanning;
    _dragAnchor = null;
    _dragLast = null;
    _spanning = false;
    if (anchor != null && wasTap) _tap(anchor);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXL)),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: context.textStyles.h3)),
                  _ViewToggle(value: _view, onChanged: _setView),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SelectionSummary(
                selection: _sel,
                onFocus: (edge) => setState(() => _sel = _sel.focus(edge)),
              ),
            ),
            const SizedBox(height: 10),
            _PeriodHeader(
              label: _periodLabel,
              canPrev: _canPrev,
              canNext: _canNext,
              onPrev: () => _go(-1),
              onNext: () => _go(1),
              onToday: _goToday,
              onLabelTap: _view == AppDatePickerView.month
                  ? () => setState(() => _jumping = !_jumping)
                  : null,
              jumping: _jumping,
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v.abs() < 200 || _jumping) return;
                _go(v < 0 ? 1 : -1);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: _slide,
                    child: _jumping
                        ? _MonthJumpGrid(
                            key: const ValueKey('jump'),
                            focus: _focus,
                            bounds: _bounds,
                            onPick: (month) => setState(() {
                              _direction = 0;
                              _focus = month;
                              _jumping = false;
                            }),
                          )
                        : _view == AppDatePickerView.month
                        ? _MonthGrid(
                            key: ValueKey('m${_periodStart.toIso8601String()}'),
                            month: _periodStart,
                            selection: _sel,
                            bounds: _bounds,
                            onTap: _tap,
                            drag: _spanDrag,
                          )
                        : _WeekStrip(
                            key: ValueKey('w${_periodStart.toIso8601String()}'),
                            monday: _periodStart,
                            selection: _sel,
                            bounds: _bounds,
                            onTap: _tap,
                            drag: _spanDrag,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.slots case final slots?) ...[
              _TimeSlots(
                slots: slots,
                selected: _time,
                controller: _timeScroll,
                onSelect: (time) => setState(() => _time = time),
              ),
              const SizedBox(height: 12),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => AppNav.back(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.divider),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                          ),
                        ),
                        child: const Text('Болих'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        key: const ValueKey('app_date_picker_confirm'),
                        onPressed: _sel.isComplete
                            ? () => AppNav.back(_PickerResult(_sel, _time))
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: CarserviceTheme.of(context).onAccent,
                          disabledBackgroundColor: colors.divider,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                          ),
                        ),
                        child: Text(
                          _confirmLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _periodLabel {
    if (_view == AppDatePickerView.month) {
      return '${_focus.year} оны ${_focus.month}-р сар';
    }
    final s = _periodStart;
    final e = _periodEnd;
    return s.year == e.year ? '${s.year}  ${_md(s)} – ${_md(e)}' : '${_ymd(s)} – ${_ymd(e)}';
  }

  String get _confirmLabel {
    if (_sel.isComplete) {
      if (_sel.isRange) return 'Сонгох · ${_sel.dayCount} хоног';
      final time = _time;
      return time == null ? 'Сонгох' : 'Сонгох · ${_hm(time)}';
    }
    if (_sel.start == null && _sel.end == null) return 'Огноо сонгоно уу';
    return _sel.nextEdge == AppRangeEdge.end ? 'Дуусах огноо сонгоно уу' : 'Эхлэх огноо сонгоно уу';
  }

  Widget _slide(Widget child, Animation<double> animation) {
    // Incoming child slides in from the navigation direction; the outgoing
    // one simply fades, which keeps the transition calm.
    final isIncoming = child.key == _currentKey;
    final offset = Tween<Offset>(
      begin: Offset(isIncoming ? 0.12 * _direction : 0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: offset, child: child),
    );
  }

  Key get _currentKey => _jumping
      ? const ValueKey('jump')
      : ValueKey(
          '${_view == AppDatePickerView.month ? 'm' : 'w'}'
          '${_periodStart.toIso8601String()}',
        );
}

// ─── Pieces ───────────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.value, required this.onChanged});

  final AppDatePickerView value;
  final ValueChanged<AppDatePickerView> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget segment(AppDatePickerView view, String label) {
      final selected = view == value;
      return GestureDetector(
        key: ValueKey('app_date_picker_view_${view.name}'),
        onTap: () => onChanged(view),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimens.radiusFull),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(AppDatePickerView.month, 'Сар'),
          segment(AppDatePickerView.week, '7 хоног'),
        ],
      ),
    );
  }
}

/// Start/end (or single date) boxes. In range mode the box the next tap
/// will fill is outlined, so the user always knows what a tap does.
/// Start/end (or single date) boxes. In range mode the box the next tap
/// will fill is outlined, and tapping a box makes it the one to fill — so
/// the end date can be picked first.
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.selection, required this.onFocus});

  final AppDateSelection selection;
  final ValueChanged<AppRangeEdge> onFocus;

  @override
  Widget build(BuildContext context) {
    if (!selection.isRange) {
      return _SummaryBox(label: 'Огноо', value: selection.start, active: true);
    }
    final next = selection.nextEdge;
    return Row(
      children: [
        Expanded(
          child: _SummaryBox(
            key: const ValueKey('app_date_picker_edge_start'),
            label: 'Эхлэх',
            value: selection.start,
            active: next == AppRangeEdge.start,
            onTap: () => onFocus(AppRangeEdge.start),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded, size: 18, color: context.colors.textHint),
        ),
        Expanded(
          child: _SummaryBox(
            key: const ValueKey('app_date_picker_edge_end'),
            label: 'Дуусах',
            value: selection.end,
            active: next == AppRangeEdge.end,
            onTap: () => onFocus(AppRangeEdge.end),
          ),
        ),
      ],
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    super.key,
    required this.label,
    required this.value,
    required this.active,
    this.onTap,
  });

  final String label;
  final DateTime? value;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: active ? colors.accent.withValues(alpha: 0.08) : colors.background,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: active ? colors.accent : colors.divider, width: active ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: colors.textSecondary)),
          const SizedBox(height: 2),
          Text(
            value == null ? '—' : _ymd(value!),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: value == null ? colors.textHint : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
      child: box,
    );
  }
}

/// "Цаг" row of [AppDatePicker.dateTime]: the picked time, then the
/// half-hour slots as a horizontally scrolling strip.
class _TimeSlots extends StatelessWidget {
  const _TimeSlots({
    required this.slots,
    required this.selected,
    required this.controller,
    required this.onSelect,
  });

  static const chipWidth = 64.0;
  static const gap = 6.0;

  final List<TimeOfDay> slots;
  final TimeOfDay? selected;
  final ScrollController controller;
  final ValueChanged<TimeOfDay> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onAccent = CarserviceTheme.of(context).onAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Цаг',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              if (selected case final time?)
                Text(
                  _hm(time),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: slots.length,
            separatorBuilder: (_, _) => const SizedBox(width: gap),
            itemBuilder: (context, i) {
              final slot = slots[i];
              final isSelected = slot == selected;
              return SizedBox(
                width: chipWidth,
                child: Material(
                  color: isSelected ? colors.accent : colors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    side: BorderSide(color: isSelected ? colors.accent : colors.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('app_date_picker_time_${_hm(slot)}'),
                    onTap: () => onSelect(slot),
                    child: Center(
                      child: Text(
                        _hm(slot),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? onAccent : colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({
    required this.label,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onLabelTap,
    required this.jumping,
  });

  final String label;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback? onLabelTap;
  final bool jumping;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('app_date_picker_prev'),
            tooltip: 'Өмнөх',
            onPressed: canPrev && !jumping ? onPrev : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Center(
              child: InkWell(
                onTap: onLabelTap,
                borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      if (onLabelTap != null)
                        Icon(
                          jumping ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                          color: colors.textSecondary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('app_date_picker_today'),
            tooltip: 'Өнөөдөр',
            onPressed: onToday,
            icon: const Icon(Icons.today_rounded, size: 20),
          ),
          IconButton(
            key: const ValueKey('app_date_picker_next'),
            tooltip: 'Дараах',
            onPressed: canNext && !jumping ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Text(
            _kWeekdays[i],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: i >= 5
                  ? context.colors.danger.withValues(alpha: 0.7)
                  : context.colors.textHint,
            ),
          ),
        ),
    ],
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    super.key,
    required this.month,
    required this.selection,
    required this.bounds,
    required this.onTap,
    required this.drag,
  });

  final DateTime month;
  final AppDateSelection selection;
  final _Bounds bounds;
  final ValueChanged<DateTime> onTap;
  final _SpanDrag? drag;

  @override
  Widget build(BuildContext context) {
    // Always 6 rows (42 days) starting on the Monday on/before the 1st, so
    // the sheet height is constant and ranges read across month edges.
    final gridStart = mondayOf(month);
    DateTime dayAt(DateTime from, int offset) => DateTime(from.year, from.month, from.day + offset);
    return Column(
      children: [
        const _WeekdayHeader(),
        const SizedBox(height: 4),
        _SpanDragArea(
          drag: drag,
          firstDay: gridStart,
          rows: 6,
          rowHeight: 44,
          child: Column(
            children: [
              for (var row = 0; row < 6; row++)
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _DayCell(
                          day: dayAt(gridStart, row * 7 + col),
                          muted: dayAt(gridStart, row * 7 + col).month != month.month,
                          selection: selection,
                          bounds: bounds,
                          onTap: onTap,
                          height: 44,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    super.key,
    required this.monday,
    required this.selection,
    required this.bounds,
    required this.onTap,
    required this.drag,
  });

  final DateTime monday;
  final AppDateSelection selection;
  final _Bounds bounds;
  final ValueChanged<DateTime> onTap;
  final _SpanDrag? drag;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      children: [
        const _WeekdayHeader(),
        const SizedBox(height: 6),
        _SpanDragArea(
          drag: drag,
          firstDay: monday,
          rows: 1,
          rowHeight: 64,
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _DayCell(
                    day: DateTime(monday.year, monday.month, monday.day + i),
                    muted: false,
                    selection: selection,
                    bounds: bounds,
                    onTap: onTap,
                    height: 64,
                    showMonth: true,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SpanDrag {
  const _SpanDrag({required this.start, required this.update, required this.end});

  final ValueChanged<DateTime> start;
  final ValueChanged<DateTime> update;
  final VoidCallback end;
}

/// Press a day and drag: every day under the finger extends the range from
/// the pressed day — no hold needed. Days are found by geometry (the grid is
/// a fixed 7 × [rows] layout of [rowHeight] rows), so the finger may leave a
/// cell's circle, or the grid itself, without breaking the drag — it just
/// snaps to the nearest row/column.
///
/// The recognizer claims the pointer on touch-down, so the sheet's own
/// drag-to-dismiss and the month swipe never steal a selection drag. Taps
/// still work: [_SpanDrag.end] turns a press released on the same day into a
/// tap.
class _SpanDragArea extends StatelessWidget {
  const _SpanDragArea({
    required this.drag,
    required this.firstDay,
    required this.rows,
    required this.rowHeight,
    required this.child,
  });

  final _SpanDrag? drag;
  final DateTime firstDay;
  final int rows;
  final double rowHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final drag = this.drag;
    if (drag == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        DateTime dayAt(Offset p) {
          final col = (p.dx / (constraints.maxWidth / 7)).floor().clamp(0, 6);
          final row = (p.dy / rowHeight).floor().clamp(0, rows - 1);
          return DateTime(firstDay.year, firstDay.month, firstDay.day + row * 7 + col);
        }

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _EagerPanRecognizer: GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
              _EagerPanRecognizer.new,
              (r) {
                r.dragStartBehavior = DragStartBehavior.down;
                r.onStart = (d) => drag.start(dayAt(d.localPosition));
                r.onUpdate = (d) => drag.update(dayAt(d.localPosition));
                r.onEnd = (_) => drag.end();
                r.onCancel = drag.end;
              },
            ),
          },
          child: child,
        );
      },
    );
  }
}

/// A pan recognizer that wins the gesture arena on touch-down instead of
/// after the pan slop — the drag starts with the first pixel of movement.
class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolvePointer(event.pointer, GestureDisposition.accepted);
  }
}

/// One tappable day. The range band is drawn per cell: full width inside the
/// range, the right half on the start day, the left half on the end day —
/// so a range reads as one continuous pill across a row.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.muted,
    required this.selection,
    required this.bounds,
    required this.onTap,
    required this.height,
    this.showMonth = false,
  });

  final DateTime day;

  /// Adjacent-month day in the month grid — still tappable, just faded.
  final bool muted;
  final AppDateSelection selection;
  final _Bounds bounds;
  final ValueChanged<DateTime> onTap;
  final double height;
  final bool showMonth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onAccent = CarserviceTheme.of(context).onAccent;
    final enabled = bounds.contains(day);
    final isStart = selection.isStart(day);
    final isEnd = selection.isEnd(day);
    final isEdge = isStart || isEnd;
    final inside = selection.isInside(day);
    final isToday = _sameDay(day, DateTime.now());
    final completeRange =
        selection.isRange && selection.isComplete && !_sameDay(selection.start!, selection.end!);
    final band = colors.accent.withValues(alpha: 0.14);

    final Color textColor;
    if (isEdge) {
      textColor = onAccent;
    } else if (!enabled) {
      textColor = colors.textHint.withValues(alpha: 0.45);
    } else if (inside) {
      textColor = colors.accent;
    } else if (muted) {
      textColor = colors.textHint;
    } else {
      textColor = colors.textPrimary;
    }

    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (inside) Positioned.fill(top: 4, bottom: 4, child: ColoredBox(color: band)),
          if (completeRange && (isStart || isEnd))
            Positioned.fill(
              top: 4,
              bottom: 4,
              child: FractionallySizedBox(
                alignment: isStart ? Alignment.centerRight : Alignment.centerLeft,
                widthFactor: 0.5,
                child: ColoredBox(color: band),
              ),
            ),
          Semantics(
            button: true,
            enabled: enabled,
            selected: isEdge,
            label: _ymd(day),
            child: InkWell(
              key: ValueKey('app_date_picker_day_${_ymd(day)}'),
              onTap: enabled ? () => onTap(day) : null,
              customBorder: const StadiumBorder(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: showMonth ? 42 : 38,
                height: height - 8,
                decoration: BoxDecoration(
                  color: isEdge ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(showMonth ? 14 : 19),
                  border: isToday && !isEdge ? Border.all(color: colors.accent, width: 1.5) : null,
                  boxShadow: isEdge
                      ? [
                          BoxShadow(
                            color: colors.accent.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: showMonth ? 16 : 14,
                        fontWeight: isEdge || isToday ? FontWeight.w700 : FontWeight.w500,
                        color: textColor,
                        decoration: enabled ? null : TextDecoration.lineThrough,
                        decorationColor: textColor,
                      ),
                    ),
                    if (showMonth)
                      Text(
                        '${day.month}-р сар',
                        style: TextStyle(
                          fontSize: 9,
                          color: isEdge ? onAccent.withValues(alpha: 0.85) : colors.textHint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Month/year jump: year arrows plus a 4×3 month grid. Months fully outside
/// the bounds are disabled.
class _MonthJumpGrid extends StatefulWidget {
  const _MonthJumpGrid({
    super.key,
    required this.focus,
    required this.bounds,
    required this.onPick,
  });

  final DateTime focus;
  final _Bounds bounds;
  final ValueChanged<DateTime> onPick;

  @override
  State<_MonthJumpGrid> createState() => _MonthJumpGridState();
}

class _MonthJumpGridState extends State<_MonthJumpGrid> {
  late int _year = widget.focus.year;

  bool _monthEnabled(int year, int month) {
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    return !last.isBefore(widget.bounds.first) && !first.isAfter(widget.bounds.last);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onAccent = CarserviceTheme.of(context).onAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _year > widget.bounds.first.year ? () => setState(() => _year--) : null,
                icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
              ),
              Text(
                '$_year',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              IconButton(
                onPressed: _year < widget.bounds.last.year ? () => setState(() => _year++) : null,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
              ),
            ],
          ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.1,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (var m = 1; m <= 12; m++)
                Builder(
                  builder: (context) {
                    final enabled = _monthEnabled(_year, m);
                    final selected = _year == widget.focus.year && m == widget.focus.month;
                    return InkWell(
                      onTap: enabled ? () => widget.onPick(DateTime(_year, m, 1)) : null,
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? colors.accent : colors.background,
                          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                        ),
                        child: Text(
                          '$m-р сар',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? onAccent
                                : enabled
                                ? colors.textPrimary
                                : colors.textHint.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
