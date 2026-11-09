import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/schedules/domain/schedule.dart';
import 'package:carservice_business/features/schedules/presentation/widgets/schedule_legend.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

const _kWeekdayNames = [
  'Даваа',
  'Мягмар',
  'Лхагва',
  'Пүрэв',
  'Баасан',
  'Бямба',
  'Ням',
];

/// Read-only day-detail bottom sheet for My Schedule — tap a calendar day to
/// see its segments and branch names. No edit affordance here at all: My
/// Schedule has no permission-gated write path in this slice.
class ScheduleDayDetailSheet extends StatelessWidget {
  const ScheduleDayDetailSheet({
    super.key,
    required this.date,
    required this.cell,
  });

  final DateTime date;
  final ScheduleCell? cell;

  static Future<void> show(
    BuildContext context, {
    required DateTime date,
    required ScheduleCell? cell,
  }) => AppNav.sheet<void>(
    ScheduleDayDetailSheet(date: date, cell: cell),
    backgroundColor: Colors.transparent,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = cell;
    final working = c?.working ?? false;
    final statusColor = working ? colors.good : colors.textSecondary;
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXL)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${date.year}/${date.month.toString().padLeft(2, '0')}/'
                                  '${date.day.toString().padLeft(2, '0')}',
                                  style: context.textStyles.h3,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_kWeekdayNames[date.weekday - 1]} гараг',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                AppDimens.radiusFull,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  working
                                      ? Icons.check_circle_rounded
                                      : Icons.bedtime_outlined,
                                  size: 16,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  working ? 'Ажиллана' : 'Амарна',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (working && c != null && c.segments.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        for (final s in c.segments) _SegmentCard(segment: s),
                      ],
                      if (c != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheduleSourceColor(context, c.source),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              scheduleSourceLabel(c.source),
                              style: context.textStyles.caption,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      const ScheduleLegend(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({required this.segment});
  final ScheduleSegment segment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            ),
            child: Icon(Icons.schedule_rounded, size: 18, color: colors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${segment.startTime ?? '--:--'}–${segment.endTime ?? '--:--'}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                if (segment.branchName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    segment.branchName!,
                    style: context.textStyles.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (segment.customTime)
            Tooltip(
              message: 'Тусгай цаг',
              child: Icon(Icons.tune_rounded, size: 16, color: colors.textHint),
            ),
        ],
      ),
    );
  }
}
