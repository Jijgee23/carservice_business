import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_repository.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';

/// Presentation state for the server-backed Vehicles list — P3-F3.
///
/// Mirrors `AppointmentListController`'s generation-guarded
/// load/loadMore/debounced-search shape exactly
/// (`features/appointments/presentation/controllers/appointment_list_controller.dart`),
/// which is also what the sibling `P3-F2` customer list is built on. The API
/// is authoritative for filtering, ordering and pagination; this controller
/// never filters a page locally, and it never invents a query parameter
/// outside the frozen `VehicleListQuery` allow-list
/// (`q, customerId, assigned, postpaid, page, pageSize` — anything else is a
/// 400 per `P3-F1`'s contract doc).
class VehicleListController extends ChangeNotifier {
  VehicleListController({VehiclesRepository? repo, Duration? searchDebounce})
    : _repo = repo ?? RemoteVehiclesRepository(),
      searchDebounce = searchDebounce ?? defaultSearchDebounce;

  static const int defaultPageSize = 50;

  /// Matches `AppointmentListController.defaultSearchDebounce` /
  /// `OrderListController.searchDebounce` — same window across every list in
  /// the app so search feels consistent.
  static const Duration defaultSearchDebounce = Duration(milliseconds: 350);

  /// Injectable so tests need not sleep on the wall clock — see
  /// `AppointmentListController`'s doc comment for why `Duration.zero` still
  /// genuinely exercises the debounce path under test.
  final Duration searchDebounce;

  final VehiclesRepository _repo;
  Timer? _searchTimer;

  VehiclesRepository get repository => _repo;

  int _generation = 0;
  bool _disposed = false;

  AsyncValue<List<Vehicle>> listState = const AsyncLoading();
  bool loadingMore = false;
  AppError? loadMoreError;
  bool _hasNext = false;
  int _page = 1;
  int _total = 0;

  String _query = '';
  String? _customerId;
  bool? _assigned;
  bool? _postpaid;
  VehicleOwnerKind? _ownerKind;

  String get query => _query;
  String? get customerId => _customerId;
  bool? get assigned => _assigned;
  bool? get postpaid => _postpaid;
  VehicleOwnerKind? get ownerKind => _ownerKind;
  bool get hasNext => _hasNext;
  int get total => _total;
  int get page => _page;

  /// Whether any filter beyond free-text search is active — drives the
  /// "clear filters" affordance and the empty-state copy.
  bool get hasActiveFilters =>
      _customerId != null ||
      _assigned != null ||
      _postpaid != null ||
      _ownerKind != null;

  /// Compatibility getter mirroring `AppointmentListController.filtered`:
  /// the server page, unfiltered on the client.
  List<Vehicle> get filtered => listState.valueOrNull ?? const <Vehicle>[];

  // ─── Server-side filters ─────────────────────────────────────────────────

  /// Debounced exactly like `AppointmentListController.setQuery` /
  /// `OrderListController.setQuery` — the same race protection for every
  /// caller, and pagination resets to page 1 once the debounce fires.
  void setQuery(String value) {
    _query = value.trim();
    _searchTimer?.cancel();
    notifyListeners();
    _searchTimer = Timer(searchDebounce, () {
      if (!_disposed) unawaited(loadVehicles());
    });
  }

  /// `customerId` takes precedence over `assigned` server-side (frozen
  /// contract fact). This controller does not enforce that locally by
  /// clearing [assigned] — the UI that offers both should not let a caller
  /// combine them meaningfully, but the server is what actually decides.
  Future<void> setCustomerId(String? value) {
    _customerId = value;
    return loadVehicles();
  }

  Future<void> setAssigned(bool? value) {
    _assigned = value;
    return loadVehicles();
  }

  Future<void> setPostpaid(bool? value) {
    _postpaid = value;
    return loadVehicles();
  }

  /// Applies both boolean filters at once (the filter sheet's "Хэрэглэх"),
  /// so a two-field change costs one reload rather than two racing ones.
  Future<void> setFilters({
    required bool? assigned,
    required bool? postpaid,
    VehicleOwnerKind? ownerKind,
  }) {
    _assigned = assigned;
    _postpaid = postpaid;
    _ownerKind = ownerKind;
    return loadVehicles();
  }

  Future<void> clearFilters() {
    _customerId = null;
    _assigned = null;
    _postpaid = null;
    _ownerKind = null;
    return loadVehicles();
  }

  // ─── Load / refresh / load-more — generation-guarded, matching
  //     AppointmentListController / OrderListController exactly ───────────

  Future<void> loadVehicles() async {
    final requestGeneration = ++_generation;
    _searchTimer?.cancel();
    loadingMore = false;
    loadMoreError = null;
    _page = 1;
    _hasNext = false;
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

  Future<void> refresh() => loadVehicles();

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
        final current = listState.valueOrNull ?? const <Vehicle>[];
        _page = value.pagination.page;
        _hasNext = value.pagination.hasNext;
        _total = value.pagination.total;
        listState = AsyncData([...current, ...value.items]);
      case Err(:final error):
        // Keep the loaded page intact; the footer allows a retry, matching
        // `OrderListController.loadMore` / `AppointmentListController.loadMore`.
        loadMoreError = error;
    }
    loadingMore = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _searchTimer?.cancel();
    super.dispose();
  }

  VehicleListQuery _queryFor(int page) => VehicleListQuery(
    q: _query.isEmpty ? null : _query,
    customerId: _customerId,
    assigned: _assigned,
    postpaid: _postpaid,
    ownerKind: _ownerKind,
    page: page,
    pageSize: defaultPageSize,
  );

  Future<Result<PagedResult<Vehicle>>> _fetchPage(int page) =>
      _repo.getVehicles(query: _queryFor(page));
}
