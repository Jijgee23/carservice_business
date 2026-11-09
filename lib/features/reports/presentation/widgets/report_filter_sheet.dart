import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/features/reports/presentation/report_ranges.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// The applied report period. [from]/[to] are only meaningful for
/// [ReportQuickRange.custom]; a quick range is resolved by the controller.
class ReportFilterResult {
  const ReportFilterResult(this.key, {this.from, this.to});

  final ReportQuickRange key;
  final DateTime? from;
  final DateTime? to;
}

/// Period filter for the Reports screen — the quick ranges plus a custom
/// range from [AppDatePicker.range]. Edits stay local until "Хэрэглэх", so
/// dismissing the sheet leaves the loaded report untouched; "Цэвэрлэх"
/// resets to the screen's default (this month).
class ReportFilterSheet extends StatefulWidget {
  const ReportFilterSheet({
    super.key,
    required this.quickKey,
    required this.from,
    required this.to,
  });

  final ReportQuickRange quickKey;
  final DateTime from;
  final DateTime to;

  static Future<ReportFilterResult?> show(
    BuildContext context, {
    required ReportQuickRange quickKey,
    required DateTime from,
    required DateTime to,
  }) {
    return AppNav.sheet<ReportFilterResult>(
      ReportFilterSheet(quickKey: quickKey, from: from, to: to),
      backgroundColor: Colors.transparent,
    );
  }

  @override
  State<ReportFilterSheet> createState() => _ReportFilterSheetState();
}

class _ReportFilterSheetState extends State<ReportFilterSheet> {
  late ReportQuickRange _key = widget.quickKey;

  /// Only set once a custom range exists (loaded or freshly picked), so
  /// "custom" can never be applied without real bounds.
  late DateTimeRange? _custom = widget.quickKey == ReportQuickRange.custom
      ? DateTimeRange(
          start: reportDateOnly(widget.from),
          end: reportDateOnly(widget.to),
        )
      : null;

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final seed =
        _custom ??
        () {
          final b = reportQuickBounds(_key, now);
          return DateTimeRange(
            start: reportDateOnly(b.from),
            end: reportDateOnly(b.to),
          );
        }();
    final picked = await AppDatePicker.range(
      context,
      initial: seed,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _custom = picked;
      _key = ReportQuickRange.custom;
    });
  }

  void _apply() {
    final custom = _custom;
    AppNav.back(
      _key == ReportQuickRange.custom && custom != null
          ? ReportFilterResult(_key, from: custom.start, to: custom.end)
          : ReportFilterResult(_key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
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
                  margin: const EdgeInsets.only(bottom: 14),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Шүүлтүүр', style: context.textStyles.h3),
                  TextButton(
                    onPressed: () =>
                        setState(() => _key = ReportQuickRange.thisMonth),
                    child: const Text('Цэвэрлэх'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Хугацаа', style: context.textStyles.captionMedium),
                      const SizedBox(height: 8),
                      for (final key in reportQuickRangeChipOrder)
                        _RangeOption(
                          key: ValueKey('report_filter_${key.name}'),
                          label: reportQuickRangeLabels[key]!,
                          detail: _boundsLabel(reportQuickBounds(key, now)),
                          selected: _key == key,
                          onTap: () => setState(() => _key = key),
                        ),
                      _RangeOption(
                        key: const ValueKey('report_filter_custom'),
                        label: reportQuickRangeLabels[ReportQuickRange.custom]!,
                        detail: _custom == null
                            ? 'Эхлэх, дуусах огноо сонгоно'
                            : '${reportYmd(_custom!.start)} — ${reportYmd(_custom!.end)}',
                        selected: _key == ReportQuickRange.custom,
                        trailing: Icons.date_range_rounded,
                        onTap: _pickCustom,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  key: const ValueKey('report_filter_apply'),
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: CarserviceTheme.of(context).onAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    ),
                  ),
                  child: const Text('Хэрэглэх'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _boundsLabel(ReportDateBounds b) =>
      '${reportYmd(b.from)} — ${reportYmd(b.to)}';
}

/// One selectable period row: label, its concrete dates, and a radio mark.
class _RangeOption extends StatelessWidget {
  const _RangeOption({
    super.key,
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: 0.08)
            : colors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          side: BorderSide(
            color: selected ? colors.accent : colors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? colors.accent : colors.textHint,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  Icon(trailing, size: 20, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
