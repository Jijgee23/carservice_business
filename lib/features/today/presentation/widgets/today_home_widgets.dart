import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';

// The first tab's building blocks (tenant-app design, "Нүүр"): the navy
// day-at-a-glance card, the quick-action tiles and the section header.
// Shared by the Today board and the general overview.

const _weekdays = [
  'Даваа',
  'Мягмар',
  'Лхагва',
  'Пүрэв',
  'Баасан',
  'Бямба',
  'Ням',
];

/// "Даваа, 11-р сарын 9".
String homeDateLabel(DateTime now) =>
    '${_weekdays[now.weekday - 1]}, ${now.month}-р сарын ${now.day}';

/// One big number on [TodayHeroCard]; a null [value] renders as "—".
class TodayHeroStat {
  const TodayHeroStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final int? value;

  /// Draws the number in the accent (the work in the shop right now).
  final bool highlight;
}

/// One share of [TodayHeroCard]'s bar, drawn in proportion to [count].
class TodayHeroSegment {
  const TodayHeroSegment(this.count, this.color);

  final int count;
  final Color color;
}

/// Navy card: a mono day label, an optional pill (the working branch),
/// up to three counts and a proportional bar.
class TodayHeroCard extends StatelessWidget {
  const TodayHeroCard({
    super.key,
    required this.label,
    required this.stats,
    this.badge,
    this.segments = const [],
  });

  final String label;
  final String? badge;
  final List<TodayHeroStat> stats;
  final List<TodayHeroSegment> segments;

  @override
  Widget build(BuildContext context) {
    final badge = this.badge;
    return OpsHeroCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: OpsSectionLabel(label, color: OpsDark.muted2)),
              if (badge != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: OpsDark.line,
                      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: opsMono(context, fontSize: 11, color: OpsDark.ink),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Stat(stats[i])),
              ],
            ],
          ),
          if (segments.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SegmentBar(segments),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.stat);

  final TodayHeroStat stat;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.value?.toString() ?? '—',
            maxLines: 1,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              height: 1.15,
              color: stat.highlight ? OpsDark.accentHi : OpsDark.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: OpsDark.muted),
          ),
        ],
      ),
    );
  }
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar(this.segments);

  final List<TodayHeroSegment> segments;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        child: SizedBox(
          height: 6,
          child: ColoredBox(
            color: OpsDark.line,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in segments)
                  if (s.count > 0)
                    Expanded(
                      flex: s.count,
                      child: ColoredBox(color: s.color),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tile of [HomeQuickActions]: an existing feature the user may open.
class HomeQuickAction {
  const HomeQuickAction({
    this.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key? key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// A row of 56px rounded icon tiles with a label under each.
class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key, required this.actions});

  final List<HomeQuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _QuickTile(actions[i])),
        ],
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile(this.action);

  final HomeQuickAction action;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: action.key,
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: t.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.border),
                ),
                child: Icon(action.icon, size: 22, color: t.ink),
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Миний ажлууд · Бүгд": a 17px title with trailing actions.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.trailing = const [],
  });

  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: CarserviceTheme.of(context).ink,
              ),
            ),
          ),
        ),
        ...trailing,
      ],
    );
  }
}

/// The accent "Бүгд" link of a [HomeSectionHeader].
class HomeSeeAllButton extends StatelessWidget {
  const HomeSeeAllButton({
    super.key,
    required this.onPressed,
    this.label = 'Бүгд',
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: CarserviceTheme.of(context).accent,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
  );
}
