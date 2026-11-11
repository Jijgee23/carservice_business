import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';

import 'calendar_block_tile.dart';
import 'calendar_grid_layout.dart';
import 'calendar_slot_cell.dart';

final _hm = DateFormat('HH:mm');

/// The day grid: a mono hour gutter and one column per lane ("ажлын байр",
/// the branch's parallel booking capacity), one row per hour of the
/// branch's business day, the accent "now" line on today. Lanes share the
/// width; below [laneColumnWidth] each, the grid scrolls sideways.
/// Positioning comes entirely from [buildCalendarGridLayout] (pure display
/// geometry over the server's already-resolved [CalendarBlock] fields);
/// this widget draws what that layout says and nothing else.
class CalendarDayGrid extends StatelessWidget {
  const CalendarDayGrid({
    super.key,
    required this.model,
    this.onOpenBlock,
    this.onCreateAt,
    this.rowHeight = 72,
    this.laneColumnWidth = 96,
    this.now,
  });

  final CalendarDayModel model;
  final void Function(CalendarBlock block)? onOpenBlock;
  final void Function(DateTime slotStart)? onCreateAt;
  final double rowHeight;

  /// Narrowest a lane column gets before the grid scrolls sideways.
  final double laneColumnWidth;

  /// Injectable for tests; defaults to the wall clock.
  final DateTime? now;

  static const _gutter = 44.0;
  static const _hPad = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    final nowLocal = now ?? DateTime.now();
    final layout = buildCalendarGridLayout(model, now: nowLocal);
    final totalHeight = layout.hours.length * rowHeight;
    final firstHour = layout.hours.first.start;
    final nowMinutes = nowLocal.difference(firstHour).inMinutes;
    final nowOffset =
        DateUtils.isSameDay(nowLocal, firstHour) &&
            nowMinutes >= 0 &&
            nowMinutes <= layout.hours.length * 60
        ? nowMinutes / 60 * rowHeight
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final lanes = layout.lanes.length;
        final available = constraints.maxWidth - 2 * _hPad - _gutter;
        final laneWidth = math.max(laneColumnWidth, available / lanes);
        final gridWidth = _gutter + laneWidth * lanes;

        final grid = SizedBox(
          width: gridWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Lane headers.
              Padding(
                padding: const EdgeInsets.only(left: _gutter, bottom: 8),
                child: Row(
                  children: [
                    for (final lane in layout.lanes)
                      SizedBox(
                        width: laneWidth,
                        child: Text(
                          lane.laneIndex < model.slotCapacity
                              ? 'АЖЛЫН БАЙР ${lane.laneIndex + 1}'
                              : 'ХЭТЭРСЭН ${lane.laneIndex + 1}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: theme.monoFontFamily,
                            fontSize: 11,
                            letterSpacing: 0.3,
                            color: lane.laneIndex < model.slotCapacity
                                ? theme.mutedText
                                : theme.warn,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: totalHeight + 1,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Hour lines across gutter and lanes, label under each.
                    for (var row = 0; row < layout.hours.length; row++)
                      Positioned(
                        top: row * rowHeight,
                        left: 0,
                        right: 0,
                        height: rowHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: theme.border),
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _hm.format(layout.hours[row].start),
                                style: TextStyle(
                                  fontFamily: theme.monoFontFamily,
                                  fontSize: 10,
                                  color: theme.mutedText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    for (final lane in layout.lanes)
                      Positioned(
                        top: 0,
                        left: _gutter + lane.laneIndex * laneWidth,
                        width: laneWidth,
                        height: totalHeight,
                        child: Stack(
                          children: [
                            for (final empty in lane.emptyCells)
                              Positioned(
                                top: empty.rowIndex * rowHeight + 4,
                                left: 2,
                                right: 2,
                                height: rowHeight - 8,
                                child: CalendarSlotCell(
                                  hourStart: empty.hourStart,
                                  tappable: empty.tappable,
                                  onTap: empty.tappable && onCreateAt != null
                                      ? () => onCreateAt!(empty.hourStart)
                                      : null,
                                ),
                              ),
                            for (final laneBlock in lane.blocks)
                              Positioned(
                                top: laneBlock.rowIndex * rowHeight + 2,
                                left: 2,
                                right: 2,
                                height: laneBlock.spanRows * rowHeight - 4,
                                child: CalendarBlockTile(
                                  block: laneBlock.block,
                                  dense: laneBlock.spanRows <= 1,
                                  onTap: onOpenBlock == null
                                      ? null
                                      : () => onOpenBlock!(laneBlock.block),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (nowOffset != null) ...[
                      Positioned(
                        top: nowOffset - 1,
                        left: _gutter - 6,
                        right: 0,
                        height: 2,
                        child: IgnorePointer(
                          child: ColoredBox(color: theme.accentHi),
                        ),
                      ),
                      Positioned(
                        top: nowOffset - 5,
                        left: _gutter - 6,
                        child: IgnorePointer(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: theme.accentHi,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: nowOffset - 8,
                        left: 0,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accentHi,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _hm.format(nowLocal),
                              style: TextStyle(
                                fontFamily: theme.monoFontFamily,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(_hPad, 4, _hPad, 32),
          child: gridWidth > constraints.maxWidth - 2 * _hPad
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: grid,
                )
              : grid,
        );
      },
    );
  }
}
