import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/reports/domain/report.dart';
import 'package:carservice_business/features/reports/domain/reports_repository.dart';
import 'package:carservice_business/features/reports/presentation/controllers/report_controller.dart';
import 'package:carservice_business/features/reports/presentation/report_ranges.dart';
import 'package:carservice_business/features/reports/presentation/widgets/report_filter_sheet.dart';
import 'package:carservice_business/features/reports/presentation/widgets/report_income_chart.dart';
import 'package:carservice_business/features/reports/presentation/widgets/report_widgets.dart';

/// The Reports screen — P7-F2. Any authenticated staff member may open it
/// (D-174: no `reports.*` permission exists), matching the web's
/// `requireUser()`-only gate.
///
/// **Not wired to a route** — `lib/app/router.dart`/`app_shell.dart` belong
/// to the later `P7-F4` slice. [onExport] is a test/DI seam for the
/// `share_plus` side effect, matching `ReportDetailScreen.onPdfExport`'s
/// precedent: when null, the real `share_plus` share sheet is used.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, this.repository, this.user, this.onExport});

  final ReportsRepository? repository;
  final User? user;
  final Future<void> Function(List<int> bytes, String filename)? onExport;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ReportController(repo: repository)..load(),
    child: _Body(user: user, onExport: onExport),
  );
}

class _Body extends StatefulWidget {
  const _Body({this.user, this.onExport});

  final User? user;
  final Future<void> Function(List<int> bytes, String filename)? onExport;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  User? get _user => widget.user ?? Authenticator.user;

  Future<void> _openFilters(ReportController controller) async {
    final result = await ReportFilterSheet.show(
      context,
      quickKey: controller.quickKey,
      from: controller.from,
      to: controller.to,
    );
    if (result == null || !mounted) return;
    final from = result.from;
    final to = result.to;
    if (result.key == ReportQuickRange.custom && from != null && to != null) {
      await controller.setCustomRange(from, to);
    } else if (result.key != controller.quickKey) {
      await controller.setQuickRange(result.key);
    }
  }

  Future<void> _export(ReportController controller) async {
    final result = await controller.export();
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        await _share(value);
      case Err(:final error):
        messageError(error.display);
    }
  }

  Future<void> _share(ReportExportFile file) async {
    if (file.bytes.isEmpty) {
      messageError('Тайлангийн файл хоосон байна.');
      return;
    }
    final injected = widget.onExport;
    if (injected != null) {
      await injected(file.bytes, file.filename);
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(file.bytes),
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: file.filename,
            ),
          ],
          fileNameOverrides: [file.filename],
          subject: 'Тайлан',
        ),
      );
    } catch (_) {
      if (mounted) messageError('Тайлан хуваалцахад алдаа гарлаа.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(body: Center(child: Text('Нэвтрэх шаардлагатай')));
    }

    final controller = context.watch<ReportController>();
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Тайлан'),
        actions: [
          // Selected (filled) whenever the period differs from the default
          // "this month"; tapping always opens the filter sheet.
          IconButton(
            key: const ValueKey('report_filter_button'),
            tooltip: 'Шүүлтүүр',
            isSelected: controller.quickKey != ReportQuickRange.thisMonth,
            icon: const Icon(Icons.filter_alt_outlined),
            selectedIcon: const Icon(Icons.filter_alt),
            onPressed: () => _openFilters(controller),
          ),
          IconButton(
            tooltip: 'Excel татах',
            icon: controller.exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            onPressed: controller.exporting ? null : () => _export(controller),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.paddingMD),
          children: [
            _PeriodPill(
              controller: controller,
              onTap: () => _openFilters(controller),
            ),
            const SizedBox(height: 14),
            AsyncStateView<ReportResult>(
              state: controller.state,
              onRetry: controller.load,
              builder: (context, result) =>
                  _ReportContent(range: result.range, data: result.data),
            ),
          ],
        ),
      ),
    );
  }
}

/// The active period at a glance, replacing the old inline chip row — tap
/// it (or the app-bar filter) to change it in [ReportFilterSheet].
class _PeriodPill extends StatelessWidget {
  final ReportController controller;
  final VoidCallback onTap;
  const _PeriodPill({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final key = controller.quickKey;
    final label = key == ReportQuickRange.custom
        ? 'Сонгосон хугацаа'
        : reportQuickRangeLabels[key]!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: colors.surface,
        shape: StadiumBorder(side: BorderSide(color: colors.divider)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('report_period_pill'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.date_range_rounded, size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        TextSpan(
                          text:
                              '  ${reportYmd(controller.from)} — ${reportYmd(controller.to)}',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportContent extends StatelessWidget {
  final ReportRange range;
  final ReportData data;
  const _ReportContent({required this.range, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (range.label != null) ...[
          Text(range.label!, style: context.textStyles.caption),
          const SizedBox(height: 12),
        ],

        // ─── KPI cards ───────────────────────────────────────────────────
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.7,
          children: [
            ReportKpiCard(
              label: 'Нийт орлого',
              value: formatTugrik(data.totalRevenue),
              accent: true,
            ),
            ReportKpiCard(
              label: 'Дууссан засварын хуудас',
              value: '${data.completedCount}',
            ),
            ReportKpiCard(
              label: 'Дундаж дүн',
              value: formatTugrik(data.avgTicket),
            ),
            ReportKpiCard(label: 'Идэвхтэй', value: '${data.activeCount}'),
            if (data.internalCost != null)
              ReportKpiCard(
                key: const ValueKey('report_internal_cost'),
                label: 'Дотоод зардал',
                value: formatTugrik(data.internalCost!),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ReportKpiCard(
          label: 'Дундаж гүйцэтгэх хугацаа',
          value: formatReportDuration(data.avgJobDurationMinutes),
        ),
        const SizedBox(height: 14),

        // ─── Income chart ───────────────────────────────────────────────
        ReportSection(
          title: 'Орлогын хандлага',
          subtitle: 'Дууссан засварын хуудасны өдөр тутмын орлого.',
          child: ReportIncomeChart(income: data.income),
        ),
        const SizedBox(height: 14),

        // ─── Status ─────────────────────────────────────────────────────
        ReportSection(
          title: 'Засварын хуудасны статус',
          subtitle: 'Сонгосон хугацааны нийт засварын хуудас.',
          child: data.statusRows.isEmpty
              ? const ReportSectionEmpty()
              : Column(
                  children: [
                    for (final row in data.statusRows)
                      ReportBarRow(
                        label: row.label ?? row.status ?? '—',
                        trailing: '${row.count}',
                        fraction: row.pct / 100,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // ─── Kind ───────────────────────────────────────────────────────
        ReportSection(
          title: 'Орлого — ажил, оношилгоо, сэлбэг',
          subtitle: 'Дууссан засварын хуудасны мөрүүдийн хуваарилалт.',
          child: data.kindRows.isEmpty
              ? const ReportSectionEmpty()
              : Column(
                  children: [
                    for (final row in data.kindRows)
                      ReportBarRow(
                        label: row.label ?? row.kind ?? '—',
                        trailing: '${formatTugrik(row.total)} · ${row.pct}%',
                        fraction: row.pct / 100,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // ─── Branch ─────────────────────────────────────────────────────
        ReportSection(
          title: 'Салбараар',
          subtitle: 'Орлого ба засварын хуудасны тоо.',
          child: () {
            final maxRevenue = data.branchRows.isEmpty
                ? 1.0
                : data.branchRows
                      .map((r) => r.revenue)
                      .fold<double>(0, (a, b) => b > a ? b : a);
            return ReportRankedList(
              rows: [
                for (final row in data.branchRows)
                  ReportBarRow(
                    label: row.name ?? '—',
                    trailing: '${formatTugrik(row.revenue)} · ${row.count}',
                    fraction: maxRevenue == 0 ? 0 : row.revenue / maxRevenue,
                  ),
              ],
            );
          }(),
        ),
        const SizedBox(height: 14),

        // ─── Technician ─────────────────────────────────────────────────
        ReportSection(
          title: 'Мастер / Менежер',
          subtitle: 'Хариуцсан засварын хуудасны орлого.',
          child: () {
            final maxRevenue = data.techRows.isEmpty
                ? 1.0
                : data.techRows
                      .map((r) => r.revenue)
                      .fold<double>(0, (a, b) => b > a ? b : a);
            return ReportRankedList(
              rows: [
                for (final row in data.techRows.take(6))
                  ReportBarRow(
                    label: row.name ?? '—',
                    trailing: '${formatTugrik(row.revenue)} · ${row.count}',
                    fraction: maxRevenue == 0 ? 0 : row.revenue / maxRevenue,
                  ),
              ],
            );
          }(),
        ),
        const SizedBox(height: 14),

        // ─── Job duration ───────────────────────────────────────────────
        ReportSection(
          title: 'Ажлын гүйцэтгэх дундаж хугацаа',
          subtitle:
              'Эхэлсэн-дуусах цаг тэмдэглэгдсэн ажлуудаар (сэлбэгийн төрлөөр).',
          child: ReportRankedList(
            rows: [
              for (var i = 0; i < data.jobDurationRows.length; i++)
                ReportRankedRow(
                  rank: i + 1,
                  title: data.jobDurationRows[i].name ?? '—',
                  subtitle: '${data.jobDurationRows[i].count} удаа',
                  value: formatReportDuration(
                    data.jobDurationRows[i].avgMinutes,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ─── Top customers ──────────────────────────────────────────────
        ReportSection(
          title: 'Топ үйлчлүүлэгчид',
          subtitle: 'Хамгийн их орлого авчирсан.',
          child: ReportRankedList(
            rows: [
              for (var i = 0; i < data.customerRows.length; i++)
                ReportRankedRow(
                  rank: i + 1,
                  title: data.customerRows[i].name ?? '—',
                  subtitle: '${data.customerRows[i].count} засварын хуудас',
                  value: formatTugrik(data.customerRows[i].revenue),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ─── Top parts ──────────────────────────────────────────────────
        ReportSection(
          title: 'Топ сэлбэгүүд',
          subtitle: 'Хамгийн их орлоготой сэлбэг.',
          child: ReportRankedList(
            rows: [
              for (var i = 0; i < data.partRows.length; i++)
                ReportRankedRow(
                  rank: i + 1,
                  title: data.partRows[i].name ?? '—',
                  subtitle: data.partRows[i].sku,
                  value: formatTugrik(data.partRows[i].revenue),
                  caption:
                      '${_qty(data.partRows[i].qty)} ${data.partRows[i].unit ?? ''}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _qty(double qty) => qty == qty.roundToDouble()
      ? qty.toInt().toString()
      : qty.toStringAsFixed(2);
}
