import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_filter_sheet.dart';

/// Presentation state for the server-backed Orders list.
///
/// The API is authoritative for filtering and ordering. This controller never
/// filters or sorts a page locally: doing so would make totals and pagination
/// lie as soon as a second page exists.
class OrderListController extends ChangeNotifier {
  OrderListController({required this._repo});

  static const int defaultPageSize = 25;
  static const Duration searchDebounce = Duration(milliseconds: 350);

  final OrdersRepository _repo;
  Timer? _searchTimer;
  int _generation = 0;
  bool _disposed = false;

  AsyncValue<List<ServiceOrderSummary>> listState = const AsyncLoading();
  AsyncValue<List<AssignableUser>> assignableUsersState = const AsyncLoading();
  bool loadingMore = false;
  AppError? loadMoreError;
  bool loadingAssignableUsers = false;
  String? assignableUsersError;
  bool _hasNext = false;
  int _page = 1;
  int _total = 0;

  OrderFilter _filter = OrderFilter.empty;
  String _query = '';
  String? selectedBranchId;
  final Set<String> _selectedIds = <String>{};
  BulkOrderResult? lastBulkResult;

  bool get hasNext => _hasNext;
  int get total => _total;
  int get page => _page;
  OrderFilter get filter => _filter;
  String get query => _query;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;
  BulkOrderResult? get bulkResult => lastBulkResult;

  /// Kept as a compatibility getter for the pre-F1 screen. It intentionally
  /// returns the server page unchanged.
  List<ServiceOrderSummary> get filtered =>
      listState.valueOrNull ?? const <ServiceOrderSummary>[];

  Future<void> setBranch(String? branchId) {
    selectedBranchId = branchId;
    if (branchId == null) _clearLegacyBranchFilter();
    _assignableGeneration++;
    loadingAssignableUsers = false;
    assignableUsersState = const AsyncLoading();
    assignableUsersError = null;
    return loadOrders();
  }

  /// Clears branch criteria owned by the legacy branch filter while retaining
  /// every other server-side filter. The working-branch controller is the
  /// authoritative scope once it selects a concrete branch.
  Future<void> clearLegacyBranchCriteria() async {
    final hadCriteria = selectedBranchId != null || _filter.branchId != null;
    if (!hadCriteria) return;
    _clearLegacyBranchFilter();
    _assignableGeneration++;
    loadingAssignableUsers = false;
    assignableUsersState = const AsyncLoading();
    assignableUsersError = null;
    await loadOrders();
  }

  void setFilter(OrderFilter value) {
    _filter = value;
    if (value.branchId != null && value.branchId != selectedBranchId) {
      selectedBranchId = value.branchId;
      _assignableGeneration++;
      loadingAssignableUsers = false;
      assignableUsersState = const AsyncLoading();
      assignableUsersError = null;
    }
    _clearSelection();
    notifyListeners();
    unawaited(loadOrders());
  }

  void clearFilter() => setFilter(OrderFilter.empty);

  /// Applies the filter sheet/panel, which now also owns the branch choice,
  /// with a single reload instead of [setBranch] followed by [setFilter].
  /// Unlike [setFilter], a null [branchId] here clears the branch.
  void applyFilters(OrderFilter value, {required String? branchId}) {
    if (branchId != selectedBranchId) {
      selectedBranchId = branchId;
      _assignableGeneration++;
      loadingAssignableUsers = false;
      assignableUsersState = const AsyncLoading();
      assignableUsersError = null;
    }
    // [selectedBranchId] is the one branch source; a stale filter-level
    // branch would otherwise win over it in the query.
    _filter = value.branchId == null
        ? value
        : OrderFilter(
            statuses: value.statuses,
            paymentStatuses: value.paymentStatuses,
            datePreset: value.datePreset,
            dateFrom: value.dateFrom,
            dateTo: value.dateTo,
            assignedToId: value.assignedToId,
            plate: value.plate,
            postpaid: value.postpaid,
            internal: value.internal,
            sortBy: value.sortBy,
            sortAsc: value.sortAsc,
          );
    _clearSelection();
    notifyListeners();
    unawaited(loadOrders());
  }

  /// Search is debounced here rather than in a widget so every caller gets the
  /// same race protection and the query is always sent to the server.
  void setQuery(String value) {
    _query = value.trim();
    _clearSelection();
    _searchTimer?.cancel();
    notifyListeners();
    _searchTimer = Timer(searchDebounce, () {
      if (!_disposed) unawaited(loadOrders());
    });
  }

  Future<void> loadOrders() async {
    final requestGeneration = ++_generation;
    _searchTimer?.cancel();
    loadingMore = false;
    loadMoreError = null;
    _page = 1;
    _hasNext = false;
    _clearSelection();
    listState = const AsyncLoading();
    notifyListeners();

    final result = await _fetchPage(1);
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

  Future<void> refresh() => loadOrders();

  Future<void> loadMore() async {
    if (_disposed || loadingMore || !_hasNext) return;
    final requestGeneration = _generation;
    final nextPage = _page + 1;
    loadingMore = true;
    loadMoreError = null;
    notifyListeners();

    final result = await _fetchPage(nextPage);
    if (_disposed || requestGeneration != _generation) return;
    switch (result) {
      case Ok(:final value):
        final current = listState.valueOrNull ?? const <ServiceOrderSummary>[];
        _page = value.pagination.page;
        _hasNext = value.pagination.hasNext;
        _total = value.pagination.total;
        listState = AsyncData([...current, ...value.items]);
      case Err(:final error):
        // Keep the loaded page intact; the footer allows a retry.
        loadMoreError = error;
    }
    loadingMore = false;
    notifyListeners();
  }

  Future<void> loadAssignableUsers() async {
    if (loadingAssignableUsers) return;
    final generation = ++_assignableGeneration;
    final branchId = selectedBranchId;
    loadingAssignableUsers = true;
    assignableUsersError = null;
    assignableUsersState = const AsyncLoading();
    notifyListeners();
    final result = await _repo.getAssignableUsers(branchId: branchId);
    if (_disposed ||
        generation != _assignableGeneration ||
        branchId != selectedBranchId) {
      return;
    }
    loadingAssignableUsers = false;
    assignableUsersState = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => AsyncError(error),
    };
    if (result case Err(:final error)) assignableUsersError = error.display;
    notifyListeners();
  }

  bool isSelected(String orderId) => _selectedIds.contains(orderId);

  void toggleSelection(String orderId) {
    if (!_visibleIds.contains(orderId)) return;
    if (!_selectedIds.add(orderId)) _selectedIds.remove(orderId);
    lastBulkResult = null;
    notifyListeners();
  }

  /// Selects exactly the currently rendered server rows. It does not imply
  /// selecting rows on pages not loaded into the device.
  void selectVisiblePage() {
    _selectedIds
      ..clear()
      ..addAll(_visibleIds);
    lastBulkResult = null;
    notifyListeners();
  }

  void clearVisibleSelection() => _clearSelection(notify: true);

  // Order numbers of the rows in the last bulk request, captured up front so a
  // failure can name "#123" even after the reload drops the row from view.
  final Map<String, String> _bulkNumbers = {};

  void _rememberBulkNumbers(List<String> ids) {
    _bulkNumbers.clear();
    for (final o in listState.valueOrNull ?? const <ServiceOrderSummary>[]) {
      if (ids.contains(o.id)) _bulkNumbers[o.id] = o.number;
    }
  }

  /// Human label ("#number") for an order id from the last bulk request.
  String bulkOrderLabel(String orderId) {
    final number = _bulkNumbers[orderId];
    return number == null ? orderId : '#$number';
  }

  Future<BulkOrderResult?> bulkChangeStatus(
    OrderStatus status, {
    int? durationMinutes,
  }) async {
    final ids = _selectedInVisibleOrder;
    if (ids.isEmpty || !_serverStatuses.contains(status)) return null;
    _rememberBulkNumbers(ids);
    final operationGeneration = _generation;
    final result = await _repo.bulkChangeStatus(
      ids,
      status,
      durationMinutes: durationMinutes,
    );
    if (_disposed) return result.valueOrNull;
    if (operationGeneration != _generation) return result.valueOrNull;
    switch (result) {
      case Ok(:final value):
        final reload = loadOrders();
        final reloadGeneration = _generation;
        await reload;
        if (_disposed || reloadGeneration != _generation) return value;
        lastBulkResult = value;
        notifyListeners();
        return value;
      case Err(:final error):
        // A request-level failure is distinct from per-order partial failures;
        // surface it through the app's established toast convention.
        // The selected rows remain selected so the user can retry the same
        // operation without losing context.
        messageError(error.display);
        return null;
    }
  }

  Future<BulkOrderResult?> bulkAssign(String assignedToId) async {
    final ids = _selectedInVisibleOrder;
    if (ids.isEmpty) return null;
    _rememberBulkNumbers(ids);
    final operationGeneration = _generation;
    final result = await _repo.bulkAssign(ids, assignedToId);
    if (_disposed) return result.valueOrNull;
    if (operationGeneration != _generation) return result.valueOrNull;
    switch (result) {
      case Ok(:final value):
        final reload = loadOrders();
        final reloadGeneration = _generation;
        await reload;
        if (_disposed || reloadGeneration != _generation) return value;
        lastBulkResult = value;
        notifyListeners();
        return value;
      case Err(:final error):
        messageError(error.display);
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

  OrderListQuery _queryFor(int page) {
    final status = _filter.serverStatus;
    final payment = _filter.serverPaymentStatus;
    return OrderListQuery(
      status: status,
      branchId: _filter.branchId ?? selectedBranchId,
      assignedToId: _filter.assignedToId,
      paymentStatus: payment,
      postpaid: _filter.postpaid,
      internal: _filter.internal,
      dateFrom: _filter.effectiveDateFrom,
      dateTo: _filter.effectiveDateTo,
      plate: _filter.plate,
      q: _query.isEmpty ? null : _query,
      page: page,
      pageSize: defaultPageSize,
    );
  }

  Future<Result<PagedResult<ServiceOrderSummary>>> _fetchPage(int page) {
    final query = _queryFor(page);
    // Pass both the canonical query object and legacy named arguments. The
    // latter keeps older test doubles/consumers observable while F1 adapters
    // use the validated query object as the source of truth.
    return _repo.getOrders(
      query: query,
      status: query.status,
      branchId: query.branchId,
      assignedToId: query.assignedToId,
      paymentStatus: query.paymentStatus,
      postpaid: query.postpaid,
      dateFrom: query.dateFrom,
      dateTo: query.dateTo,
      customerId: query.customerId,
      vehicleId: query.vehicleId,
      q: query.q,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  void _clearLegacyBranchFilter() {
    selectedBranchId = null;
    if (_filter.branchId == null) return;
    final current = _filter;
    _filter = OrderFilter(
      statuses: current.statuses,
      paymentStatuses: current.paymentStatuses,
      datePreset: current.datePreset,
      dateFrom: current.dateFrom,
      dateTo: current.dateTo,
      assignedToId: current.assignedToId,
      plate: current.plate,
      postpaid: current.postpaid,
      internal: current.internal,
      sortBy: current.sortBy,
      sortAsc: current.sortAsc,
    );
  }

  List<String> get _visibleIds =>
      (listState.valueOrNull ?? const <ServiceOrderSummary>[])
          .map((order) => order.id)
          .toList(growable: false);

  List<String> get _selectedInVisibleOrder =>
      _visibleIds.where(_selectedIds.contains).toList(growable: false);

  void _clearSelection({bool notify = false}) {
    if (_selectedIds.isEmpty && lastBulkResult == null) return;
    _selectedIds.clear();
    lastBulkResult = null;
    if (notify) notifyListeners();
  }

  static const _serverStatuses = <OrderStatus>{
    OrderStatus.SCHEDULED,
    OrderStatus.IN_PROGRESS,
    OrderStatus.COMPLETED,
    OrderStatus.CANCELLED,
  };
  int _assignableGeneration = 0;
}
