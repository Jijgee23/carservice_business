import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/money_format.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';

/// Small presentational pieces shared across the Reports screen's sections —
/// P7-F2. Every section on `app/dashboard/reports/page.tsx` renders as a
/// list/card here instead of a wide table, per the slice's phone-readability
/// requirement.

/// `formatTugrik()` on the web, ported: integer amount with thousands
/// separators and a trailing tögrög sign.
String formatTugrik(num amount) => formatMoneyNum(amount.round());

/// `formatDuration()` on the web (`lib/category-duration.ts`), ported:
/// whole hours + remaining minutes, Mongolian short units. Zero/negative
/// renders as `0мин` rather than an empty string.
String formatReportDuration(int minutes) {
  if (minutes <= 0) return '0мин';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours <= 0) return '$restмин';
  if (rest <= 0) return '$hoursц';
  return '$hoursц $restмин';
}

/// A single top-level number tile — the "KPI card" row.
class ReportKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  const ReportKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.paddingMD,
        vertical: AppDimens.paddingSM + 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.textStyles.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: context.textStyles.h2.copyWith(
              color: accent
                  ? context.colors.accent
                  : context.colors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// One card section wrapper: title + optional subtitle + body, matching the
/// `<section>` blocks on the web page (rendered as a full-width card here
/// instead of a two-column grid — the phone has no room for that).
class ReportSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const ReportSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textStyles.h3),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: context.textStyles.caption),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Empty-data placeholder used inside a [ReportSection] — matches the web's
/// "Өгөгдөл алга." fallback.
class ReportSectionEmpty extends StatelessWidget {
  const ReportSectionEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text('Өгөгдөл алга.', style: context.textStyles.caption),
      ),
    );
  }
}

/// A labeled progress bar row — used for status/kind breakdowns.
class ReportBarRow extends StatelessWidget {
  final String label;
  final String trailing;
  final double fraction;
  final Color? barColor;
  const ReportBarRow({
    super.key,
    required this.label,
    required this.trailing,
    required this.fraction,
    this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: context.textStyles.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: context.textStyles.captionMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusFull),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 6,
              backgroundColor: context.colors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(
                barColor ?? context.colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ranked list row — used for top customers/parts/branches/technicians and
/// job-duration rows. `title`/`subtitle` on the left, `value`/`caption` on
/// the right, matching the web's `<li>` rows.
class ReportRankedRow extends StatelessWidget {
  final int rank;
  final String title;
  final String? subtitle;
  final String value;
  final String? caption;
  const ReportRankedRow({
    super.key,
    required this.rank,
    required this.title,
    this.subtitle,
    required this.value,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text('#$rank', style: context.textStyles.caption),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.textStyles.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.textStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: context.textStyles.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: context.textStyles.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A divider-separated list of [ReportRankedRow]s, or the empty placeholder.
class ReportRankedList extends StatelessWidget {
  final List<Widget> rows;
  const ReportRankedList({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const ReportSectionEmpty();
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: context.colors.divider),
          rows[i],
        ],
      ],
    );
  }
}
