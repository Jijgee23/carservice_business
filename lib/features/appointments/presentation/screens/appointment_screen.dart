import 'package:carservice_business/core/widgets/adaptive/tight_height_fallback.dart';

import 'package:carservice_business/core/utils/vehicle_plate.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/service_catalog.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/service_catalog_service.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/adaptive/breakpoints.dart';
import 'package:carservice_business/core/widgets/adaptive/record_views.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/list_search_bar.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/appointment_controller.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/appointment_list_controller.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/calendar_controller.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_calendar_screen.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_detail_screen.dart';
import 'package:carservice_business/features/appointments/presentation/screens/create_appointment_screen.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/appointment_filter_sheet.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/appointment_list_widgets.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Appointments list screen — P2-F2.
///
/// Server-side status/branch/date filtering with generation-guarded
/// list/refresh/load-more (see `AppointmentListController`). Selection is
/// touch-native: long-press enters selection mode, a plain tap toggles a
/// row, and a toolbar "select range" button arms a one-shot pick-the-other-
/// end interaction — deliberately not a transliteration of the web's
/// mouse-drag/right-click range selection. Bulk category shows per-row
/// partial failures then reloads authoritatively from the server; it never
/// patches local rows from the bulk response.
///
/// A permission check here only hides/disables UI — it is not access
/// control. The server independently enforces `appointments.view` /
/// `appointments.edit` on every read and mutation.
///
/// The pre-programme embedded month-calendar toggle that used to live in
/// this screen is removed: its data source (`getMonthCounts`) has no
/// equivalent in the P2-F1 frozen contract, and the real calendar surface is
/// P2-F3's `appointment_calendar_screen.dart`, running in parallel. Owning a
/// second, unsupported calendar view here would both fail to compile against
/// the frozen contract and duplicate P2-F3's scope.
class AppointmentScreen extends StatefulWidget {
  const AppointmentScreen({super.key, this.user});

  final User? user;

  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  // Long-lived, owned by this State and disposed in `dispose()` below — not
  // a short-lived dialog-scoped controller. That distinction matters: a
  // dialog-scoped `TextEditingController` disposed by an awaiting caller
  // caused a real `TextEditingController was used after being disposed`
  // crash elsewhere in this repo (see `create_appointment_controller.dart`
  // history). This one lives exactly as long as the screen does.
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _didLoad = false;

  // Tablet table sort state — kept in this State (not the controller)
  // exactly like `OrderListScreen`'s equivalent: it is screen-local
  // presentation state, not list/filter truth, and this State already
  // survives branch/tab switches under the shell's `StatefulShellRoute`
  // (each branch keeps its own offstage Navigator), so it needs no extra
  // persistence plumbing here.
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.extentAfter < 500 && mounted) {
        context.read<AppointmentController>().loadMore();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No permission: the tab still opens, but on the no-permission view —
    // loading would only 403.
    if (!_didLoad && _canView(_user)) {
      _didLoad = true;
      final controller = context.read<AppointmentController>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.loadAppointments();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  User? get _user => widget.user ?? Authenticator.user;

  bool _canView(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('appointments.view') == true;

  bool _canCreate(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('appointments.create') == true;

  bool _canEdit(User? user) =>
      user?.isOwner == true ||
      user?.role?.permissions.contains('appointments.edit') == true;

  Future<void> _openCreate(
    BuildContext context,
    AppointmentController ctrl,
  ) async {
    final result = await AppNav.to<AppointmentSummary>(
      const CreateAppointmentScreen(),
    );
    if (result != null && mounted) {
      final requestedAt = result.requestedAt;
      // The every-date list stays put; a day view follows the new booking.
      if (requestedAt != null && !ctrl.allDates) {
        await ctrl.setDate(requestedAt);
      } else {
        await ctrl.refresh();
      }
    }
  }

  Future<void> _openCalendar(
    BuildContext context,
    AppointmentController ctrl,
    User? user,
  ) async {
    // Explicit list filter → the shell's working branch → the home branch.
    // The working branch must beat the home branch: calendar requests carry
    // `X-Working-Branch`, and a conflicting `branchId` is a 422. A
    // tenant-wide/ALL selection with no home branch leaves this null, and
    // the calendar renders its dedicated no-branch state.
    final branchId =
        ctrl.selectedBranchId ?? workingBranchIdOf(context) ?? user?.branchId;

    final calendarController = CalendarController(
      repo: ctrl.repository,
      branchId: branchId,
      date: ctrl.selectedDate,
    );
    await AppNav.to<void>(
      AppointmentCalendarScreen(
        controller: calendarController,
        onOpenBlock: (block) => _openCalendarBlock(context, ctrl, block, user),
        onCreateAt: _canCreate(user)
            ? (slotStart) async {
                await AppNav.to<void>(
                  CreateAppointmentScreen(initialDate: slotStart),
                );
                if (context.mounted) await calendarController.refresh();
              }
            : null,
      ),
    );
    calendarController.dispose();
    if (mounted) await ctrl.refresh();
  }

  void _openCalendarBlock(
    BuildContext context,
    AppointmentController ctrl,
    CalendarBlock block,
    User? user,
  ) {
    AppointmentSummary? appointment;
    for (final item in ctrl.filtered) {
      if (item.id == block.appointmentId) {
        appointment = item;
        break;
      }
    }
    if (appointment == null) {
      messageWarning('Энэ цаг захиалгын дэлгэрэнгүйг жагсаалтаас олсонгүй.');
      return;
    }
    _showDetailFor(context, appointment, ctrl, user);
  }

  Future<void> _changeBulkCategory(AppointmentListController ctrl) async {
    final categoriesResult = await ServiceCatalogService.getLaborCategories();
    if (!mounted) return;
    if (categoriesResult case Err(:final error)) {
      messageError(error.display);
      return;
    }
    final categories = (categoriesResult as Ok<List<LaborCategory>>).value;
    if (categories.isEmpty) {
      messageError('Ажлын төрөл тохируулаагүй байна');
      return;
    }
    final picked = await AppNav.sheet<LaborCategory>(
      SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final category in categories)
              ListTile(
                title: Text(category.name),
                onTap: () => AppNav.back(category),
              ),
          ],
        ),
      ),
      showDragHandle: true,
    );
    if (picked == null || !mounted) return;
    final result = await ctrl.bulkChangeCategory(picked.id);
    if (result == null && mounted) {
      // A request-level failure already surfaced via `messageError` inside
      // the controller's underlying repository call chain is not guaranteed
      // here (bulkChangeCategory swallows request-level Err by returning
      // null); tell the user explicitly rather than silently doing nothing.
      messageError('Ажлын төрөл өөрчлөх хүсэлт амжилтгүй боллоо');
    }
  }

  /// A tab root inside the shell's `AdaptiveScaffold`, which already owns the
  /// page chrome (branch switcher, search, bell, bottom navigation). So this
  /// is a [Material] surface, not a second [Scaffold]: the day switcher heads
  /// the page, the create button floats over the list and the selection bar
  /// docks under it.
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppointmentController>();
    final user = _user;
    if (!_canView(user)) {
      return Material(
        color: context.opsBackground,
        child: const NoPermissionView(
          key: ValueKey('appointments_no_permission'),
          message:
              'Танд цаг захиалга харах эрх олгогдоогүй байна. '
              'Эрх авахын тулд байгууллагын админд хандана уу.',
        ),
      );
    }

    final filter = _currentFilter(ctrl);
    // Same rule as the order list: the header's working branch is the scope;
    // a per-list branch filter only makes sense for an owner while it is "all".
    final showBranches =
        user?.isOwner == true && _showLegacyBranchFilter(context);
    return Material(
      color: context.opsBackground,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                TightHeightFallback(
                  controls: [
                    _DayBar(
                      ctrl: ctrl,
                      onCalendar: () => _openCalendar(context, ctrl, user),
                    ),
                    ListSearchBar(
                      controller: _searchController,
                      hintText: 'Үйлчлүүлэгч, утас, тэмдэглэл...',
                      onChanged: ctrl.setQuery,
                      onClear: () {
                        _searchController.clear();
                        ctrl.setQuery('');
                      },
                      filterKey: const ValueKey('appointments_filter_button'),
                      activeFilters: filter.activeCount,
                      onFilter: () => _openFilters(ctrl, filter, showBranches),
                    ),
                    if (ctrl.lastBulkResult?.failed.isNotEmpty == true)
                      AppointmentBulkFailureBanner(
                        result: ctrl.lastBulkResult!,
                      ),
                  ],
                  results: _buildResults(ctrl, ctrl.listState, user, filter),
                ),
                if (_canCreate(user))
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton(
                      key: const ValueKey('appointments_create_fab'),
                      heroTag: 'appointments_create_fab',
                      tooltip: 'Цаг захиалга нэмэх',
                      backgroundColor: context.opsAccent,
                      foregroundColor: context.opsTextOnDark,
                      onPressed: () => _openCreate(context, ctrl),
                      child: const Icon(Icons.add),
                    ),
                  ),
              ],
            ),
          ),
          if (ctrl.selectedCount > 0)
            AppointmentSelectionBar(
              count: ctrl.selectedCount,
              rangeArmed: ctrl.rangeSelectArmed,
              canEdit: _canEdit(user),
              onClear: ctrl.clearSelection,
              onSelectAll: ctrl.selectAllVisible,
              onArmRange: ctrl.armRangeSelect,
              onChangeCategory: () => _changeBulkCategory(ctrl),
            ),
        ],
      ),
    );
  }

  AppointmentFilter _currentFilter(AppointmentListController ctrl) =>
      AppointmentFilter(
        branchId: ctrl.selectedBranchId,
        group: AppointmentStatusGroup.of(ctrl.statusGroup),
        status: ctrl.statusFilter,
      );

  Future<void> _openFilters(
    AppointmentListController ctrl,
    AppointmentFilter current,
    bool showBranches,
  ) async {
    final next = await showAppointmentFilterSheet(
      context,
      current,
      showBranches: showBranches,
    );
    if (next == null || !mounted) return;
    await ctrl.applyFilters(
      branchId: next.branchId,
      status: next.status,
      statusGroup: next.group?.statuses,
    );
  }

  bool _showLegacyBranchFilter(BuildContext context) {
    try {
      return context.watch<WorkingBranchController>().isAllBranches;
    } on ProviderNotFoundException {
      // Standalone tests and legacy embeddings have no working-branch
      // provider. Preserve their existing owner-only filter in that case.
      return true;
    }
  }

  Widget _buildResults(
    AppointmentController ctrl,
    AsyncValue<List<AppointmentSummary>> state,
    User? user,
    AppointmentFilter filter,
  ) {
    return switch (state) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => _ErrorView(
        message: error.display,
        onRetry: ctrl.refresh,
      ),
      AsyncData(:final value) when value.isEmpty => EmptyState(
        message: filter.activeCount > 0
            ? 'Шүүлтэд тохирох цаг захиалга байхгүй'
            : ctrl.allDates
            ? 'Цаг захиалга байхгүй'
            : 'Энэ өдөр цаг захиалга байхгүй',
        icon: Icons.event_busy_outlined,
      ),
      AsyncData(:final value) => LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= AdaptiveBreakpoints.expanded
            ? _TabletAppointmentsView(
                ctrl: ctrl,
                appointments: value,
                user: user,
                sortColumnIndex: _sortColumnIndex,
                sortAscending: _sortAscending,
                onSort: _onSort,
              )
            : _PhoneAppointments(
                ctrl: ctrl,
                appointments: value,
                scroll: _scrollController,
                user: user,
              ),
      ),
    };
  }

  void _onSort(int index) {
    setState(() {
      if (_sortColumnIndex == index) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = index;
        _sortAscending = true;
      }
    });
  }
}

// ─── Day switcher ────────────────────────────────────────────────────────────

/// ‹ day › in a flat panel: tap the date to pick one, the calendar button
/// opens the day's time grid, and "Бүгд" returns to the default every-date
/// list. In that list the bar offers the date picker and an "Өнөөдөр" chip.
class _DayBar extends StatelessWidget {
  const _DayBar({required this.ctrl, required this.onCalendar});

  final AppointmentListController ctrl;
  final VoidCallback onCalendar;

  static const _weekdays = [
    'Даваа',
    'Мягмар',
    'Лхагва',
    'Пүрэв',
    'Баасан',
    'Бямба',
    'Ням',
  ];
  static final _fmt = DateFormat('yyyy/MM/dd');

  @override
  Widget build(BuildContext context) {
    final d = ctrl.selectedDate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Material(
        color: context.opsSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLG),
          side: BorderSide(color: context.opsDivider),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              if (d != null)
                IconButton(
                  tooltip: 'Өмнөх өдөр',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: ctrl.prevDay,
                ),
              Expanded(
                child: InkWell(
                  key: const ValueKey('appointments_date_picker'),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                  onTap: () => _pickDate(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Text(
                          d == null ? 'Бүх цаг захиалга' : _fmt.format(d),
                          maxLines: 1,
                          style: context.textStyles.h3.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          d == null
                              ? 'Сүүлийнх нь эхэндээ'
                              : '${_weekdays[d.weekday - 1]} гараг',
                          maxLines: 1,
                          style: context.textStyles.caption,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (d != null)
                IconButton(
                  tooltip: 'Дараах өдөр',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: ctrl.nextDay,
                ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: d == null
                    ? ActionChip(
                        key: const ValueKey('appointments_today_chip'),
                        label: const Text('Өнөөдөр'),
                        onPressed: ctrl.goToday,
                        visualDensity: VisualDensity.compact,
                      )
                    : ActionChip(
                        key: const ValueKey('appointments_all_dates_chip'),
                        label: const Text('Бүгд'),
                        onPressed: ctrl.showAllDates,
                        visualDensity: VisualDensity.compact,
                      ),
              ),
              Container(width: 1, height: 28, color: context.opsDivider),
              IconButton(
                key: const ValueKey('appointments_calendar_button'),
                tooltip: 'Хуанли',
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: onCalendar,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await AppDatePicker.single(
      context,
      initial: ctrl.selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) await ctrl.setDate(picked);
  }
}

// ─── Phone / tablet lists ───────────────────────────────────────────────────

class _PhoneAppointments extends StatelessWidget {
  const _PhoneAppointments({
    required this.ctrl,
    required this.appointments,
    required this.scroll,
    required this.user,
  });
  final AppointmentController ctrl;
  final List<AppointmentSummary> appointments;
  final ScrollController scroll;
  final User? user;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: ctrl.refresh,
    child: ListView.separated(
      controller: scroll,
      // Extra bottom room so the last card and the footer clear the FAB.
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: appointments.length + 1,
      separatorBuilder: (_, index) =>
          SizedBox(height: index == appointments.length - 1 ? 4 : 10),
      itemBuilder: (_, index) {
        if (index == appointments.length) {
          return AppointmentListFooter(
            loadingMore: ctrl.loadingMore,
            loadMoreError: ctrl.loadMoreError?.display,
            hasNext: ctrl.hasNext,
            total: ctrl.total,
            onLoadMore: ctrl.loadMore,
          );
        }
        final appt = appointments[index];
        return AppointmentRowGestures(
          controller: ctrl,
          appointment: appt,
          onOpen: () => _showDetailFor(context, appt, ctrl, user),
          child: AppointmentPhoneCard(
            appointment: appt,
            selected: ctrl.isSelected(appt.id),
            selectionMode: ctrl.selectionMode,
            showDate: ctrl.allDates,
          ),
        );
      },
    ),
  );
}

/// Tablet (>= [AdaptiveBreakpoints.expanded]) all-appointments view — P5.
/// Sortable [DataTableView] list. The appointment detail always opens as its
/// own full-screen route (`_showDetailFor`, the same push phones use) rather
/// than an embedded side pane — small tablets (~600-900dp) are this app's
/// primary device, and a two-pane split left too little room for the detail
/// content at that width. Row selection/bulk-action gestures are preserved:
/// a long-press still enters selection mode and a plain tap opens the
/// detail route (or toggles selection while selection mode is on).
class _TabletAppointmentsView extends StatelessWidget {
  const _TabletAppointmentsView({
    required this.ctrl,
    required this.appointments,
    required this.user,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
  });

  final AppointmentController ctrl;
  final List<AppointmentSummary> appointments;
  final User? user;
  final int? sortColumnIndex;
  final bool sortAscending;
  final ValueChanged<int> onSort;

  static final _timeFmt = DateFormat('HH:mm');
  static final _dateTimeFmt = DateFormat('yyyy/MM/dd HH:mm');

  List<AppointmentSummary> _sorted() {
    if (sortColumnIndex == null) return appointments;
    final sorted = [...appointments];
    int cmp(AppointmentSummary a, AppointmentSummary b) =>
        switch (sortColumnIndex) {
          0 => (a.requestedAt ?? DateTime(0)).compareTo(
            b.requestedAt ?? DateTime(0),
          ),
          1 => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
          2 => (a.displayVehicle?.plate ?? '').compareTo(
            b.displayVehicle?.plate ?? '',
          ),
          3 => (a.category?.name ?? '').compareTo(b.category?.name ?? ''),
          4 => a.status.label.compareTo(b.status.label),
          _ => 0,
        };
    sorted.sort(cmp);
    if (!sortAscending) return sorted.reversed.toList(growable: false);
    return sorted;
  }

  List<RecordColumn<AppointmentSummary>> get _columns => [
    RecordColumn(
      label: ctrl.allDates ? 'Огноо' : 'Цаг',
      flex: ctrl.allDates ? 2 : 1,
      builder: (context, appt) => Text(
        appt.requestedAt == null
            ? '—'
            : (ctrl.allDates ? _dateTimeFmt : _timeFmt).format(
                appt.requestedAt!,
              ),
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    ),
    RecordColumn(
      label: 'Үйлчлүүлэгч',
      flex: 3,
      builder: (context, appt) =>
          Text(appt.displayName, overflow: TextOverflow.ellipsis),
    ),
    RecordColumn(
      label: 'Машин',
      flex: 2,
      builder: (context, appt) => Text(
        _vehiclePlateText(appt.displayVehicle),
        overflow: TextOverflow.ellipsis,
      ),
    ),
    RecordColumn(
      label: 'Ажлын төрөл',
      flex: 2,
      builder: (context, appt) =>
          Text(appt.category?.name ?? '—', overflow: TextOverflow.ellipsis),
    ),
    RecordColumn(
      label: 'Төлөв',
      flex: 2,
      builder: (context, appt) => AppointmentStatusChip(status: appt.status),
    ),
  ];

  Widget _buildTable(BuildContext context) {
    final sorted = _sorted();
    return RefreshIndicator(
      onRefresh: ctrl.refresh,
      child: Column(
        children: [
          Expanded(
            child: DataTableView<AppointmentSummary>(
              records: sorted,
              columns: _columns,
              forceTable: true,
              sortColumnIndex: sortColumnIndex,
              sortAscending: sortAscending,
              onSort: onSort,
              onTap: (appt) {
                if (ctrl.rangeSelectArmed) {
                  ctrl.applyRangeSelectTap(appt.id);
                } else if (ctrl.selectionMode) {
                  ctrl.toggleSelection(appt.id);
                } else {
                  _showDetailFor(context, appt, ctrl, user);
                }
              },
              onLongPress: ctrl.selectionMode
                  ? null
                  : (appt) => ctrl.enterSelectionMode(appt.id),
              empty: EmptyState(
                message: ctrl.allDates
                    ? 'Цаг захиалга байхгүй'
                    : 'Энэ өдөр цаг захиалга байхгүй',
                icon: Icons.event_busy_outlined,
              ),
            ),
          ),
          AppointmentListFooter(
            loadingMore: ctrl.loadingMore,
            loadMoreError: ctrl.loadMoreError?.display,
            hasNext: ctrl.hasNext,
            total: ctrl.total,
            onLoadMore: ctrl.loadMore,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _buildTable(context);
}

void _showDetailFor(
  BuildContext context,
  AppointmentSummary appt,
  AppointmentController ctrl,
  User? user,
) {
  unawaited(
    AppNav.to<void>(
      AppointmentDetailScreen(initial: appt, repo: ctrl.repository, user: user),
    ).then((_) {
      if (context.mounted) unawaited(ctrl.refresh());
    }),
  );
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: context.opsDanger),
            const SizedBox(height: 12),
            Text(
              message,
              style: context.textStyles.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Дахин оролдох'),
            ),
          ],
        ),
      ),
    );
  }
}

String _vehiclePlateText(AppointmentVehicleRef? v) =>
    v?.plate == null ? '—' : plateLabel(v!.plate);
