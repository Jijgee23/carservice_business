import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/selection/selection_bar.dart';
import 'package:carservice_business/features/schedules/data/schedule_repository.dart';
import 'package:carservice_business/features/schedules/domain/schedule.dart';
import 'package:carservice_business/features/schedules/domain/schedules_repository.dart';
import 'package:carservice_business/features/schedules/presentation/controllers/schedule_edit_controller.dart';
import 'package:carservice_business/features/schedules/presentation/controllers/schedule_grid_controller.dart';
import 'package:carservice_business/features/schedules/presentation/schedule_dates.dart';
import 'package:carservice_business/features/schedules/presentation/widgets/schedule_edit_sheet.dart';
import 'package:carservice_business/features/schedules/presentation/widgets/schedule_legend.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Employee×day schedule grid — P6-F4. Requires `employees.view` at the
/// surface level (D-163 convention, matching `EmployeeListScreen`); the cell
/// edit sheet and bulk-edit selection mode are additionally hidden unless
/// the loaded [ScheduleGrid.canEdit] is true (`employees.schedule`), since
/// that is a distinct, server-resolved permission this screen never guesses.
///
/// **Not wired to a route** — `lib/app/router.dart`/`app_shell.dart` are
/// `P6-F5`'s. Intended route: `/schedules`, gated on `employees.view`.
class ScheduleGridScreen extends StatelessWidget {
  const ScheduleGridScreen({super.key, this.repository, this.user});

  final SchedulesRepository? repository;
  final User? user;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ScheduleGridController(repo: repository),
    child: _Body(user: user),
  );
}

class _Body extends StatefulWidget {
  const _Body({this.user});
  final User? user;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _didLoad = false;
  final _searchController = TextEditingController();

  User? get _user => widget.user ?? Authenticator.user;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoad) {
      _didLoad = true;
      final controller = context.read<ScheduleGridController>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.load();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (!canSeeView(user, 'employees.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Хуваарь')),
        body: const EmptyState(
          message: 'Танд ажилтны хуваарь харах эрх байхгүй байна.',
          icon: Icons.lock_outline,
        ),
      );
    }

    final controller = context.watch<ScheduleGridController>();
    final selection = controller.selection;

    return AnimatedBuilder(
      animation: selection,
      builder: (context, _) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: const Text('Хуваарь'),
          actions: [
            if (controller.canEdit && !selection.isActive)
              PermissionGate(
                permission: 'employees.schedule',
                user: user,
                child: IconButton(
                  key: const ValueKey('schedule_grid_select_mode'),
                  icon: const Icon(Icons.checklist_rtl),
                  tooltip: 'Бөөнөөр засах',
                  onPressed: controller.enterSelectionMode,
                ),
              ),
            IconButton(
              onPressed: controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(196),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NavRow(controller: controller),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _SearchField(
                    controller: _searchController,
                    onChanged: controller.setQuery,
                  ),
                ),
                const SizedBox(height: 6),
                _BranchChipRow(controller: controller),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: ScheduleLegend(),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
        body: AsyncStateView<ScheduleGrid>(
          state: controller.gridState,
          isEmpty: (g) => g.rows.isEmpty,
          empty: const EmptyState(
            message: 'Ажилтан олдсонгүй',
            icon: Icons.people_outline,
          ),
          onRetry: controller.refresh,
          builder: (context, grid) =>
              _Grid(controller: controller, grid: grid, user: user),
        ),
        bottomNavigationBar: selection.isActive
            ? SelectionActionBar(
                key: const ValueKey('schedule_grid_selection_bar'),
                count: selection.count,
                onClear: controller.exitSelectionMode,
                actions: [
                  SelectionAction(
                    label: 'Засах',
                    icon: Icons.edit,
                    onPressed: selection.isEmpty
                        ? null
                        : () => _openBulkEdit(
                            context,
                            controller,
                            grid: controller.grid!,
                          ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _openBulkEdit(
    BuildContext context,
    ScheduleGridController controller, {
    required ScheduleGrid grid,
  }) async {
    final cellCount = controller.selection.count;
    if (cellCount == 0) return;
    final weekdays = controller.orderedDistinctWeekdaysForSelection();
    final weekdayLabel =
        'Сонгосон гараг(ууд)т байнга (${weekdays.map((w) => w.label).join(', ')})';

    final applied = await AppNav.sheet<int?>(
      ChangeNotifierProvider(
        create: (_) => ScheduleEditController(repo: controller.repository),
        child: Builder(
          builder: (sheetContext) => ScheduleEditSheetBody(
            title: '$cellCount нүд засах',
            branches: grid.branches,
            weekdayLabel: weekdayLabel,
            dateScopeLabel: 'Зөвхөн сонгосон өдрүүдэд',
            onSave: () async {
              final editController = sheetContext
                  .read<ScheduleEditController>();
              final targets = controller.bulkTargets(editController.scope);
              final result = await editController.submitBulk(targets);
              if (result != null && sheetContext.mounted) {
                AppNav.back(result);
              }
            },
          ),
        ),
      ),
    );
    if (applied != null && context.mounted) {
      controller.exitSelectionMode();
      await controller.refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$applied нүд шинэчлэгдлээ.')));
      }
    }
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.controller});
  final ScheduleGridController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        IconButton(
          key: const ValueKey('schedule_grid_prev'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.chevron_left),
          onPressed: controller.prevPeriod,
        ),
        TextButton(
          key: const ValueKey('schedule_grid_today'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: controller.goToday,
          child: const Text('Өнөөдөр', style: TextStyle(fontSize: 12)),
        ),
        IconButton(
          key: const ValueKey('schedule_grid_next'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.chevron_right),
          onPressed: controller.nextPeriod,
        ),
        const Spacer(),
        SizedBox(
          height: 32,
          child: SegmentedButton<String>(
            key: const ValueKey('schedule_grid_view_toggle'),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: 'week',
                label: Text('7х', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: 'month',
                label: Text('Сар', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: {controller.view},
            onSelectionChanged: (s) => controller.setView(s.first),
          ),
        ),
      ],
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    key: const ValueKey('schedule_grid_search'),
    controller: controller,
    onChanged: onChanged,
    decoration: const InputDecoration(
      hintText: 'Ажилтан хайх...',
      prefixIcon: Icon(Icons.search),
      isDense: true,
    ),
  );
}

class _BranchChipRow extends StatelessWidget {
  const _BranchChipRow({required this.controller});
  final ScheduleGridController controller;

  @override
  Widget build(BuildContext context) {
    final grid = controller.grid;
    final branches = grid?.branches ?? const [];
    final counts = grid?.countByBranch ?? const {};
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _Chip(
            label: 'Бүгд',
            selected: controller.branchId == null,
            onTap: () => controller.setBranch(null),
          ),
          const SizedBox(width: 6),
          for (final b in branches) ...[
            _Chip(
              label: '${b.name ?? b.id} (${counts[b.id] ?? 0})',
              selected: controller.branchId == b.id,
              onTap: () => controller.setBranch(b.id),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? context.colors.accent.withValues(alpha: 0.14) : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        border: Border.all(
          color: selected ? context.colors.accent : context.colors.divider,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          color: selected
              ? context.colors.accent
              : context.colors.textSecondary,
        ),
      ),
    ),
  );
}

// ─── Grid ───────────────────────────────────────────────────────────────

const double _employeeColWidth = 120;
const double _dayColWidth = 96;
const double _rowHeight = 64;

class _Grid extends StatelessWidget {
  const _Grid({
    required this.controller,
    required this.grid,
    required this.user,
  });
  final ScheduleGridController controller;
  final ScheduleGrid grid;
  final User? user;

  @override
  Widget build(BuildContext context) {
    final dayScroll = ScrollController();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sticky employee column.
        SizedBox(
          width: _employeeColWidth,
          child: Column(
            children: [
              Container(height: 32, alignment: Alignment.center),
              for (final row in grid.rows)
                Container(
                  key: ValueKey('schedule_grid_employee_${row.id}'),
                  height: _rowHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: context.colors.divider),
                    ),
                  ),
                  child: Text(
                    row.name ?? row.id,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.caption,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: dayScroll,
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(
                  children: [
                    for (final date in grid.dates)
                      Container(
                        width: _dayColWidth,
                        height: 32,
                        alignment: Alignment.center,
                        child: Text(
                          _dayHeader(date),
                          style: context.textStyles.caption,
                        ),
                      ),
                  ],
                ),
                for (final row in grid.rows)
                  Row(
                    children: [
                      for (final date in grid.dates)
                        _Cell(
                          key: ValueKey('schedule_grid_cell_${row.id}_$date'),
                          controller: controller,
                          userId: row.id,
                          date: date,
                          cell: row.cells[date],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _dayHeader(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return date;
    return '${parts[1]}/${parts[2]}';
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.controller,
    required this.userId,
    required this.date,
    required this.cell,
  });

  final ScheduleGridController controller;
  final String userId;
  final String date;
  final ScheduleCell? cell;

  @override
  Widget build(BuildContext context) {
    final selection = controller.selection;
    final key = ScheduleGridController.cellKey(userId, date);
    final selected =
        selection.isSelected(key) ||
        (selection.isRangeActive && selection.rangePreview.contains(key));
    final working = cell?.working ?? false;
    return GestureDetector(
      onTap: () {
        if (selection.isActive) {
          controller.onRangeTap(userId, date);
        } else {
          _openCellEdit(context);
        }
      },
      onLongPress: () => controller.toggleCell(userId, date),
      child: Container(
        width: _dayColWidth,
        height: _rowHeight,
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.accent.withValues(alpha: 0.18)
              : working
              ? context.colors.goodBg
              : context.colors.background,
          borderRadius: BorderRadius.circular(AppDimens.radiusSM),
          border: Border.all(
            color: selected ? context.colors.accent : context.colors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheduleSourceColor(
                      context,
                      cell?.source ?? ScheduleSource.unknown,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    working ? 'Ажиллана' : 'Амарна',
                    style: const TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (working && cell != null && cell!.segments.isNotEmpty)
              Text(
                '${cell!.segments.first.startTime ?? ''}-${cell!.segments.first.endTime ?? ''}',
                style: const TextStyle(fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCellEdit(BuildContext context) async {
    if (!controller.canEdit) return;
    final grid = controller.grid;
    if (grid == null) return;
    final parsedDate = DateTime.tryParse(date);
    final wd = parsedDate == null ? null : weekdayOf(parsedDate);
    final saved = await AppNav.sheet<bool>(
      ChangeNotifierProvider(
        create: (_) => ScheduleEditController(
          repo: controller.repository,
          working: cell?.working ?? true,
          segments: (cell?.segments.isNotEmpty ?? false)
              ? cell!.segments
                    .map(
                      (s) => EditableSegment(
                        branchId: s.branchId,
                        startTime: s.startTime ?? '09:00',
                        endTime: s.endTime ?? '18:00',
                      ),
                    )
                    .toList()
              : null,
        ),
        child: Builder(
          builder: (sheetContext) => ScheduleEditSheetBody(
            weekdayLabel: wd == null ? null : '${wd.label} гараг бүр',
            branches: grid.branches,
            onSave: () async {
              final editController = sheetContext
                  .read<ScheduleEditController>();
              final ok = await editController.submitCell(
                userId: userId,
                date: editController.scope == ScheduleScope.date ? date : null,
                weekday: editController.scope == ScheduleScope.weekday
                    ? wd
                    : null,
              );
              if (ok && sheetContext.mounted) {
                AppNav.back(true);
              }
            },
            onReset: () async {
              final editController = sheetContext
                  .read<ScheduleEditController>();
              final ok = await editController.resetCell(
                userId: userId,
                date: editController.scope == ScheduleScope.date ? date : null,
                weekday: editController.scope == ScheduleScope.weekday
                    ? wd
                    : null,
              );
              if (ok && sheetContext.mounted) {
                AppNav.back(true);
              }
            },
          ),
        ),
      ),
    );
    if (saved == true) await controller.refresh();
  }
}
