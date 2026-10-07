import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/data/customer_repository.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';

/// Presentation state for the server-backed Customers list — P3-F2.
///
/// Copies `AppointmentListController`'s idiom exactly: the API is
/// authoritative for filtering and pagination, a monotonic `_generation`
/// guards every in-flight request (initial load, debounced search reload and
/// load-more) against being overwritten by a stale response, and a
/// load-more failure never discards the page already on screen.
class CustomerListController extends ChangeNotifier {
  CustomerListController({CustomersRepository? repo, Duration? searchDebounce})
    : _repo = repo ?? RemoteCustomersRepository(),
      searchDebounce = searchDebounce ?? defaultSearchDebounce;

  static const int defaultPageSize = 50;

  /// Matches `AppointmentListController.defaultSearchDebounce` — the same
  /// debounce window the Orders/Appointments precedent uses for `q`.
  static const Duration defaultSearchDebounce = Duration(milliseconds: 350);

  /// Injectable so tests need not sleep on the wall clock — see
  /// `AppointmentListController.searchDebounce` for why `Duration.zero`
  /// still genuinely exercises the debounce path in tests.
  final Duration searchDebounce;

  final CustomersRepository _repo;
  Timer? _searchTimer;

  CustomersRepository get repository => _repo;

  int _generation = 0;
  bool _disposed = false;

  AsyncValue<List<Customer>> listState = const AsyncLoading();
  bool loadingMore = false;
  AppError? loadMoreError;
  bool _hasNext = false;
  int _page = 1;
  int _total = 0;

  String _query = '';
  CustomerKindFilter? _kind;

  String get query => _query;
  CustomerKindFilter? get kind => _kind;

  /// `?kind=org|person`; null = all. Reloads from page 1.
  void setKind(CustomerKindFilter? value) {
    if (value == _kind) return;
    _kind = value;
    unawaited(loadCustomers());
  }

  bool get hasNext => _hasNext;
  int get total => _total;
  int get page => _page;

  List<Customer> get customers => listState.valueOrNull ?? const <Customer>[];

  /// Search is debounced here (not in the widget) so every caller gets the
  /// same race protection, matching
  /// `AppointmentListController.setQuery`/`OrderListController.setQuery`.
  /// Resets pagination to page 1 via [loadCustomers] once the debounce
  /// fires.
  void setQuery(String value) {
    _query = value.trim();
    _searchTimer?.cancel();
    notifyListeners();
    _searchTimer = Timer(searchDebounce, () {
      if (!_disposed) unawaited(loadCustomers());
    });
  }

  // ─── Load / refresh / load-more — generation-guarded, matching
  //     AppointmentListController exactly ─────────────────────────────────

  Future<void> loadCustomers() async {
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

  Future<void> refresh() => loadCustomers();

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
        final current = listState.valueOrNull ?? const <Customer>[];
        _page = value.pagination.page;
        _hasNext = value.pagination.hasNext;
        _total = value.pagination.total;
        listState = AsyncData([...current, ...value.items]);
      case Err(:final error):
        // Keep the loaded page intact; the footer allows a retry, matching
        // `AppointmentListController.loadMore`.
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

  CustomerListQuery _queryFor(int page) => CustomerListQuery(
    q: _query.isEmpty ? null : _query,
    kind: _kind,
    page: page,
    pageSize: defaultPageSize,
  );

  Future<Result<PagedResult<Customer>>> _fetchPage(int page) =>
      _repo.getCustomers(query: _queryFor(page));
}
