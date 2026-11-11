import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';

import 'calendar_block_tile.dart';
import 'calendar_slot_cell.dart';

/// Phone rendering: a chronological agenda. Every fact a block conveys is
/// the same as the tablet grid (same [CalendarBlockTile], same server
/// model) — only the layout differs, matching the slice's "reduce visible
/// content, keep the label" rule at the agenda level too: a phone screen is
/// itself a narrow renderer.
class CalendarAgendaList extends StatelessWidget {
  const CalendarAgendaList({
    super.key,
    required this.model,
    this.onOpenBlock,
    this.onCreateAt,
    this.now,
  });

  final CalendarDayModel model;
  final void Function(CalendarBlock block)? onOpenBlock;
  final void Function(DateTime slotStart)? onCreateAt;

  /// Injectable for tests; defaults to the wall clock.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final nowLocal = now ?? DateTime.now();
    final blocks = [...model.blocks]
      ..sort((a, b) {
        final aStart = a.startAt ?? DateTime(0);
        final bStart = b.startAt ?? DateTime(0);
        return aStart.compareTo(bStart);
      });

    if (blocks.isEmpty) {
      return _EmptyDayAgenda(
        model: model,
        onCreateAt: onCreateAt,
        now: nowLocal,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: blocks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final block = blocks[index];
        return CalendarBlockTile(
          block: block,
          onTap: onOpenBlock == null ? null : () => onOpenBlock!(block),
        );
      },
    );
  }
}

/// A day with no blocks still offers one visible booking affordance per
/// open future capacity slot rather than a bare "no appointments" message —
/// the agenda has nothing else to key touch selection off, so it enumerates
/// the branch's remaining open business hours from [model]'s own range.
class _EmptyDayAgenda extends StatelessWidget {
  const _EmptyDayAgenda({
    required this.model,
    required this.now,
    this.onCreateAt,
  });

  final CalendarDayModel model;
  final DateTime now;
  final void Function(DateTime slotStart)? onCreateAt;

  @override
  Widget build(BuildContext context) {
    final rangeStart = model.rangeStart?.toLocal();
    final rangeEnd = model.rangeEnd?.toLocal();
    final theme = CarserviceTheme.of(context);

    final hours = <DateTime>[];
    if (rangeStart != null &&
        rangeEnd != null &&
        rangeEnd.isAfter(rangeStart)) {
      var cursor = DateTime(
        rangeStart.year,
        rangeStart.month,
        rangeStart.day,
        rangeStart.hour,
      );
      while (cursor.isBefore(rangeEnd)) {
        hours.add(cursor);
        cursor = cursor.add(const Duration(hours: 1));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(AppDimens.paddingMD),
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.paddingLG),
            child: Column(
              children: [
                Icon(
                  Icons.event_available_rounded,
                  color: theme.mutedText3,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  'Энэ өдөр цаг захиалга алга',
                  style: TextStyle(fontSize: 15, color: theme.mutedText),
                ),
              ],
            ),
          ),
        ),
        if (hours.any((h) => h.add(const Duration(hours: 1)).isAfter(now)))
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hour in hours)
                if (hour.add(const Duration(hours: 1)).isAfter(now))
                  SizedBox(
                    width: 96,
                    height: 44,
                    child: CalendarSlotCell(
                      hourStart: hour,
                      tappable: true,
                      showTime: true,
                      onTap: onCreateAt != null
                          ? () => onCreateAt!(hour)
                          : null,
                    ),
                  ),
            ],
          ),
      ],
    );
  }
}
