import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/data/appointment_repository.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';

/// Presentation state for the server-backed Appointments list — P2-F2.
///
/// Follows `OrderListController`'s idiom exactly: the API is authoritative
/// for filtering, ordering and pagination; this controller never filters a
/// page locally.
///
/// **P2-F2a correction:** the P2-F1 frozen `AppointmentListQuery`
/// (`lib/features/appointments/domain/appointments_repository.dart`) was
/// missing `q`. `P2-B8` added `?q=` server-side, matching the web
/// dashboard's search exactly (account name case-insensitive, account phone
/// case-sensitive, note case-insensitive) and `P2-F2a` wires [setQuery]
/// through to it here. There is deliberately no date-range and no
/// customer/vehicle filter — the web dashboard has neither, and adding them
/// would be parity drift, not parity.
class AppointmentListController extends ChangeNotifier {
  AppointmentListController({
    AppointmentsRepository? repo,
    Duration? searchDebounce,
  }) : _repo = repo ?? RemoteAppointmentsRepository(),
       searchDebounce = searchDebounce ?? defaultSearchDebounce;

  static const int defaultPageSize = 50;

  /// Page size of the default every-date list ([allDates]).
  static const int allDatesPageSize = 10;

  /// Matches `OrderListController.searchDebounce` — the same debounce window
  /// the Orders precedent uses for `q`.
  static const Duration defaultSearchDebounce = Duration(milliseconds: 350);

  /// Injectable so tests need not sleep on the wall clock.
  ///
  /// The suite used to wait `defaultSearchDebounce + 50 ms` of real time and
  /// then assert. That margin held on an idle machine and failed under load —
  /// 2 of 3 full-suite runs failed while another `flutter test` was running,
  /// and widening the margin only moves the threshold rather than removing it.
  /// With `Duration.zero` the timer still fires asynchronously, so the
  /// debounce path is genuinely exercised, but completion depends on event-loop
  /// turns instead of elapsed time.
  final Duration searchDebounce;

  final AppointmentsRepository _repo;
  Timer? _searchTimer;

  /// Exposed so [AppointmentController] (which adds single-appointment
  /// lifecycle mutations) can reuse the same repository instance instead of
  /// constructing a second one.
  AppointmentsRepository get repository => _repo;

  int _generation = 0;
  bool _disposed = false;

  AsyncValue<List<AppointmentSummary>> listState = const AsyncLoading();
  bool loadingMore = false;
  AppError? loadMoreError;
  bool _hasNext = false;
  int _page = 1;
  int _total = 0;

  /// `null` is the default mode: every date, newest `requestedAt` first,
  /// [allDatesPageSize] rows per page (see [_ReverseCursor]). A picked day
  /// switches to that day's list in the server's ascending order.
  DateTime? _selectedDate;
  AppointmentStatus? _statusFilter;
  String? selectedBranchId;
  String _query = '';

  /// "Нээлттэй"/"Хаагдсан" (open/closed) support — P5, now driven by the
  /// filter sheet. The frozen list contract (`AppointmentListQuery`, P2-F1)
  /// accepts exactly one `status`, so a group such as "open" (PENDING or
  /// CONFIRMED) cannot be expressed as a single
  /// server request. When [_statusGroup] is set this controller instead
  /// issues one request per status in the group (each with a generous
  /// `pageSize` covering a full day's list) and merges the results locally,
  /// sorted by `requestedAt`. This is a client-side *merge* of two
  /// authoritative server pages, never a client-side re-filter of a single
  /// page — every row shown still came from the server for that exact
  /// status. Pagination (`loadMore`) is disabled while a status group is
  /// active: a day's appointment count is bounded, so a single wide fetch is
  /// simpler and more honest than trying to keep two independent cursors in
  /// sync.
  Set<AppointmentStatus>? _statusGroup;

  static const int _groupPageSize = 200;

  /// The every-date list's paging state: one cursor per status (a single
  /// one when no status group is active), merged newest-first.
  List<_ReverseCursor> _cursors = const [];

  // ─── Touch-native selection ─────────────────────────────────────────────
  //
  // Entry is discoverable via long-press on a row (widget-driven — see
  // `appointment_screen.dart`), which both flips [selectionMode] on and
  // selects that row. While in selection mode a plain tap toggles a row.
  // Range-select is the touch-appropriate stand-in for the web's
  // mouse-drag/shift-click: `armRangeSelect()` primes a one-shot "pick the
  // other end" mode from an explicit toolbar button (see
  // `BulkSelectionBar`-equivalent in the screen); the next tap on a row
  // selects every row between the last-selected anchor and that row,
  // inclusive, in the order currently rendered on screen.
  bool selectionMode = false;
  final Set<String> _selectedIds = <String>{};
  String? _rangeAnchorId;
  bool rangeSelectArmed = false;
  AppointmentBulkResult? lastBulkResult;

  DateTime? get selectedDate => _selectedDate;
  bool get allDates => _selectedDate == null;
  AppointmentStatus? get statusFilter => _statusFilter;
  Set<AppointmentStatus>? get statusGroup => _statusGroup;
  String get query => _query;
  bool get hasNext => _hasNext;
  int get total => _total;
  int get page => _page;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;

  /// Compatibility getter for the pre-F1 screen shape: the server page,
  /// unfiltered on the client.
  List<AppointmentSummary> get filtered =>
      listState.valueOrNull ?? const <AppointmentSummary>[];

  // ─── Date navigation ─────────────────────────────────────────────────────

  Future<void> setDate(DateTime d) {
    _selectedDate = DateTime(d.year, d.month, d.day);
    _exitSelection();
    return loadAppointments();
  }

  Future<void> prevDay() =>
      setDate((_selectedDate ?? _today()).subtract(const Duration(days: 1)));
  Future<void> nextDay() =>
      setDate((_selectedDate ?? _today()).add(const Duration(days: 1)));

  Future<void> goToday() {
    final today = _today();
    if (_selectedDate == today) return Future.value();
    return setDate(today);
  }

  /// Back to the default every-date list.
  Future<void> showAllDates() {
    if (_selectedDate == null) return Future.value();
    _selectedDate = null;
    _exitSelection();
    return loadAppointments();
  }

  // ─── Server-side filters ─────────────────────────────────────────────────

  Future<void> setStatusFilter(AppointmentStatus? status) {
    _statusFilter = status;
    _statusGroup = null;
    _exitSelection();
    return loadAppointments();
  }

  Future<void> setBranch(String? branchId) {
    selectedBranchId = branchId;
    _exitSelection();
    return loadAppointments();
  }

  /// Sets/clears the open/closed status group. Passing a non-null
  /// [statuses] clears the single-status filter (they are mutually
  /// exclusive in this UI) and switches [loadAppointments] into merge mode;
  /// `null` restores the ordinary single-status/paged flow.
  Future<void> setStatusGroup(Set<AppointmentStatus>? statuses) {
    _statusGroup = (statuses == null || statuses.isEmpty) ? null : statuses;
    if (_statusGroup != null) _statusFilter = null;
    _exitSelection();
    return loadAppointments();
  }

  /// Applies the filter sheet's branch/status/group choice with a single
  /// reload, instead of chaining [setBranch]/[setStatusFilter]/
  /// [setStatusGroup] and firing one request per setter. A single [status]
  /// wins over [statusGroup]: the sheet only offers statuses inside the
  /// chosen group, so the status is always the narrower of the two.
  Future<void> applyFilters({
    required String? branchId,
    required AppointmentStatus? status,
    required Set<AppointmentStatus>? statusGroup,
  }) {
    selectedBranchId = branchId;
    _statusFilter = status;
    _statusGroup =
        (status != null || statusGroup == null || statusGroup.isEmpty)
        ? null
        : statusGroup;
    _exitSelection();
    return loadAppointments();
  }

  /// Search is debounced here (not in the widget) so every caller gets the
  /// same race protection, matching `OrderListController.setQuery`. Composes
  /// with status/branch/date rather than replacing them; resets pagination
  /// to page 1 via [loadAppointments] once the debounce fires.
  void setQuery(String value) {
    _query = value.trim();
    _exitSelection();
    _searchTimer?.cancel();
    notifyListeners();
    _searchTimer = Timer(searchDebounce, () {
      if (!_disposed) unawaited(loadAppointments());
    });
  }

  // ─── Load / refresh / load-more — generation-guarded, matching
  //     OrderListController exactly ─────────────────────────────────────────

  Future<void> loadAppointments() async {
    final requestGeneration = ++_generation;
    _searchTimer?.cancel();
    loadingMore = false;
    loadMoreError = null;
    _page = 1;
    _hasNext = false;
    listState = const AsyncLoading();
    notifyListeners();

    if (allDates) {
      final cursors = _cursors = [
        for (final status in _statusGroup ?? {_statusFilter})
          _ReverseCursor((page) => _fetchAllDatesPage(status, page)),
      ];
      final result = await _takeNewest(cursors, allDatesPageSize);
      if (_disposed || requestGeneration != _generation) return;
      switch (result) {
        case Ok(:final value):
          _applyCursors(cursors);
          listState = AsyncData(_appendUnique(const [], value));
        case Err(:final error):
          listState = AsyncError(error);
      }
      notifyListeners();
      return;
    }

    final group = _statusGroup;
    final result = group == null
        ? await _fetchPage(1)
        : await _fetchGroup(group);
    if (_disposed || requestGeneration != _generation) return;
    switch (result) {
      case Ok(:final value):
        _page = value.pagination.page;
        _hasNext = value.pagination.hasNext;
        _total = value.pagination.total;
        listState = AsyncData(value.items);
      case Err(:final error):
        listState = AsyncError(error);
    }
    notifyListeners();
  }

  Future<void> refresh() => loadAppointments();

  Future<void> loadMore() async {
    // No cursor to advance in a day's merged status-group mode — see
    // [_statusGroup]. The every-date list keeps one cursor per status.
    if (_statusGroup != null && !allDates) return;
    if (_disposed || loadingMore || !_hasNext) return;
    final requestGeneration = _generation;
    final nextPage = _page + 1;
    loadingMore = true;
    loadMoreError = null;
    notifyListeners();

    if (allDates) {
      final cursors = _cursors;
      final result = await _takeNewest(cursors, allDatesPageSize);
      if (_disposed || requestGeneration != _generation) return;
      switch (result) {
        case Ok(:final value):
          final current = listState.valueOrNull ?? const <AppointmentSummary>[];
          _applyCursors(cursors);
          _page = nextPage;
          listState = AsyncData(_appendUnique(current, value));
        case Err(:final error):
          // The cursors keep what they already fetched, so a retry resumes.
          loadMoreError = error;
      }
      loadingMore = false;
      notifyListeners();
      return;
    }

    final result = await _fetchPage(nextPage);
    if (_disposed || requestGeneration != _generation) return;
    switch (result) {
      case Ok(:final value):
        final current = listState.valueOrNull ?? const <AppointmentSummary>[];
        _page = value.pagination.page;
        _hasNext = value.pagination.hasNext;
        _total = value.pagination.total;
        listState = AsyncData([...current, ...value.items]);
      case Err(:final error):
        // Keep the loaded page intact; the footer allows a retry, matching
        // `OrderListController.loadMore`.
        loadMoreError = error;
    }
    loadingMore = false;
    notifyListeners();
  }

  // ─── Selection ───────────────────────────────────────────────────────────

  bool isSelected(String id) => _selectedIds.contains(id);

  /// Discoverable long-press entry point: flips selection mode on (if not
  /// already) and selects [id] as the range anchor.
  void enterSelectionMode(String id) {
    if (!_visibleIds.contains(id)) return;
    selectionMode = true;
    rangeSelectArmed = false;
    _selectedIds.add(id);
    _rangeAnchorId = id;
    lastBulkResult = null;
    notifyListeners();
  }

  /// Plain tap while [selectionMode] is active.
  void toggleSelection(String id) {
    if (!selectionMode || !_visibleIds.contains(id)) return;
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
      _rangeAnchorId = id;
    }
    lastBulkResult = null;
    notifyListeners();
  }

  /// Primes the one-shot "pick the other end" affordance — the touch
  /// equivalent of a shift-click. The next [toggleSelection]-eligible tap
  /// (routed through [applyRangeSelectTap]) selects the contiguous run of
  /// currently-rendered rows between the anchor and the tapped row.
  void armRangeSelect() {
    if (!selectionMode || _rangeAnchorId == null) return;
    rangeSelectArmed = true;
    notifyListeners();
  }

  void cancelRangeSelect() {
    if (!rangeSelectArmed) return;
    rangeSelectArmed = false;
    notifyListeners();
  }

  /// Row tap handler while [rangeSelectArmed] is true. Selects every
  /// visible row between the stored anchor and [id], inclusive, then
  /// disarms. Falls back to a normal [toggleSelection] if there is no
  /// anchor.
  void applyRangeSelectTap(String id) {
    final anchor = _rangeAnchorId;
    rangeSelectArmed = false;
    if (anchor == null || !_visibleIds.contains(id)) {
      toggleSelection(id);
      return;
    }
    final ids = _visibleIds;
    final start = ids.indexOf(anchor);
    final end = ids.indexOf(id);
    if (start < 0 || end < 0) {
      toggleSelection(id);
      return;
    }
    final lo = start <= end ? start : end;
    final hi = start <= end ? end : start;
    _selectedIds.addAll(ids.sublist(lo, hi + 1));
    _rangeAnchorId = id;
    lastBulkResult = null;
    notifyListeners();
  }

  /// Selects exactly the currently rendered server rows — never rows on a
  /// page not loaded into the device, matching the Orders precedent.
  void selectAllVisible() {
    selectionMode = true;
    _selectedIds
      ..clear()
      ..addAll(_visibleIds);
    lastBulkResult = null;
    notifyListeners();
  }

  void clearSelection() => _exitSelection(notify: true);

  // ─── Bulk category ───────────────────────────────────────────────────────

  /// `POST /appointments/bulk/category`. Per-row partial failure is
  /// preserved in [lastBulkResult] for the UI to render; the local list is
  /// never patched from the bulk response — on any outcome (including a
  /// request-level failure) an authoritative reload follows, per this
  /// slice's known-trap #2 (never let a discarded mutation result get
  /// silently overwritten by a later error, and never trust a client-side
  /// patch over the server).
  Future<AppointmentBulkResult?> bulkChangeCategory(String categoryId) async {
    final ids = _selectedInVisibleOrder;
    if (ids.isEmpty) return null;
    final operationGeneration = _generation;
    final result = await _repo.bulkChangeCategory(ids, categoryId);
    if (_disposed) return result.valueOrNull;
    if (operationGeneration != _generation) return result.valueOrNull;
    switch (result) {
      case Ok(:final value):
        _exitSelection();
        final reload = loadAppointments();
        final reloadGeneration = _generation;
        await reload;
        if (_disposed || reloadGeneration != _generation) return value;
        lastBulkResult = value;
        notifyListeners();
        return value;
      case Err():
        // A request-level failure (as opposed to per-row partial failure) is
        // surfaced by the caller via the returned Result; selection is kept
        // so the user can retry without losing context.
        return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _searchTimer?.cancel();
    super.dispose();
  }

  AppointmentListQuery _queryFor(int page) => AppointmentListQuery(
    status: _statusFilter,
    branchId: selectedBranchId,
    date: _selectedDate,
    q: _query.isEmpty ? null : _query,
    page: page,
    pageSize: defaultPageSize,
  );

  Future<Result<PagedResult<AppointmentSummary>>> _fetchPage(int page) =>
      _repo.getAppointments(query: _queryFor(page));

  Future<Result<PagedResult<AppointmentSummary>>> _fetchAllDatesPage(
    AppointmentStatus? status,
    int page,
  ) => _repo.getAppointments(
    query: AppointmentListQuery(
      status: status,
      branchId: selectedBranchId,
      q: _query.isEmpty ? null : _query,
      page: page,
      pageSize: allDatesPageSize,
    ),
  );

  /// Takes the [count] newest rows across [cursors]. Each cursor is first
  /// filled to [count] rows (or until it runs out), so a cursor's unfetched
  /// rows — all older than its buffered ones — can never be newer than a
  /// row taken here.
  static Future<Result<List<AppointmentSummary>>> _takeNewest(
    List<_ReverseCursor> cursors,
    int count,
  ) async {
    final errors = await Future.wait([for (final c in cursors) c.fill(count)]);
    final error = errors.nonNulls.firstOrNull;
    if (error != null) return Err(error);
    final taken = <AppointmentSummary>[];
    while (taken.length < count) {
      _ReverseCursor? next;
      for (final c in cursors) {
        if (c.buffer.isEmpty) continue;
        if (next == null ||
            _newestFirst(c.buffer.first, next.buffer.first) < 0) {
          next = c;
        }
      }
      if (next == null) break;
      taken.add(next.buffer.removeAt(0));
    }
    return Ok(taken);
  }

  void _applyCursors(List<_ReverseCursor> cursors) {
    _hasNext = cursors.any((c) => c.hasMore);
    _total = cursors.fold(0, (sum, c) => sum + c.total);
  }

  /// Rows can shift between server pages while paging (a booking added or
  /// cancelled meanwhile), so a row may come back twice — keep the first.
  static List<AppointmentSummary> _appendUnique(
    List<AppointmentSummary> current,
    List<AppointmentSummary> more,
  ) {
    final seen = {for (final a in current) a.id};
    return [...current, ...more.where((a) => seen.add(a.id))];
  }

  static int _newestFirst(AppointmentSummary a, AppointmentSummary b) {
    final da = a.requestedAt;
    final db = b.requestedAt;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  }

  /// Issues one request per status in [statuses] (see [_statusGroup]) and
  /// merges the results, sorted by `requestedAt` ascending (nulls last,
  /// matching the server's own day-list ordering). The first request-level
  /// error wins — a partial merge presented as if it were complete would be
  /// worse than a clear error, matching this controller's existing
  /// generation-guarded error handling elsewhere.
  Future<Result<PagedResult<AppointmentSummary>>> _fetchGroup(
    Set<AppointmentStatus> statuses,
  ) async {
    final results = await Future.wait([
      for (final status in statuses)
        _repo.getAppointments(
          query: AppointmentListQuery(
            status: status,
            branchId: selectedBranchId,
            date: _selectedDate,
            q: _query.isEmpty ? null : _query,
            page: 1,
            pageSize: _groupPageSize,
          ),
        ),
    ]);
    final merged = <AppointmentSummary>[];
    var total = 0;
    for (final result in results) {
      switch (result) {
        case Ok(:final value):
          merged.addAll(value.items);
          total += value.pagination.total;
        case Err(:final error):
          return Err(error);
      }
    }
    merged.sort((a, b) {
      final da = a.requestedAt;
      final db = b.requestedAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return Ok(
      PagedResult(
        items: merged,
        pagination: PaginationMeta(
          page: 1,
          pageSize: _groupPageSize,
          total: total,
          totalPages: 1,
          hasPrev: false,
          hasNext: false,
        ),
      ),
    );
  }

  List<String> get _visibleIds =>
      (listState.valueOrNull ?? const <AppointmentSummary>[])
          .map((a) => a.id)
          .toList(growable: false);

  List<String> get _selectedInVisibleOrder =>
      _visibleIds.where(_selectedIds.contains).toList(growable: false);

  void _exitSelection({bool notify = false}) {
    final hadState =
        selectionMode || _selectedIds.isNotEmpty || lastBulkResult != null;
    selectionMode = false;
    rangeSelectArmed = false;
    _rangeAnchorId = null;
    _selectedIds.clear();
    lastBulkResult = null;
    if (notify && hadState) notifyListeners();
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

/// Pages one list query newest-first. `GET /appointments` only sorts by
/// `requestedAt` ascending, so this learns the page count from page 1, then
/// walks the pages from the last one backwards, reversing each.
class _ReverseCursor {
  _ReverseCursor(this._fetch);

  final Future<Result<PagedResult<AppointmentSummary>>> Function(int page)
  _fetch;

  /// Fetched rows not yet shown, newest first.
  final buffer = <AppointmentSummary>[];
  int total = 0;

  /// Next ascending page to fetch: `null` before the first fill, `0` once
  /// every page has been fetched.
  int? _nextPage;

  bool get hasMore => buffer.isNotEmpty || _nextPage != 0;

  /// Fetches until [buffer] holds at least [count] rows or the query runs
  /// out. On error the rows fetched so far stay, so a retry resumes.
  Future<AppError?> fill(int count) async {
    if (_nextPage == null) {
      switch (await _fetch(1)) {
        case Err(:final error):
          return error;
        case Ok(:final value):
          total = value.pagination.total;
          final lastPage = value.pagination.totalPages;
          if (lastPage <= 1) {
            buffer.addAll(value.items.reversed);
            _nextPage = 0;
          } else {
            _nextPage = lastPage;
          }
      }
    }
    while (buffer.length < count && _nextPage! > 0) {
      switch (await _fetch(_nextPage!)) {
        case Err(:final error):
          return error;
        case Ok(:final value):
          total = value.pagination.total;
          buffer.addAll(value.items.reversed);
          _nextPage = _nextPage! - 1;
      }
    }
    return null;
  }
}
