import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/data/customer_repository.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';

/// Owns one customer's detail fetch (by id), edit, delete and paginated
/// order-history load — P3-F4.
///
/// Fetches by id rather than taking a pre-loaded summary from the caller —
/// unlike `AppointmentDetailController`, the frozen `CustomersRepository`
/// contract (P3-F1) DOES have a single-customer GET
/// (`GET /customers/[id]`), so there is no "best effort re-derive from a
/// list page" workaround here: [load] is the real, authoritative fetch and
/// must run even on a cold deep-link start where the caller has nothing but
/// an id.
///
/// Every request (initial load, refresh, history page) is guarded by a
/// monotonic [_generation] counter, matching
/// `CustomerListController`/`AppointmentDetailController` exactly, so a
/// stale in-flight response can never clobber a newer one or a state left
/// behind by [dispose].
class CustomerDetailController extends ChangeNotifier {
  CustomerDetailController({
    required this.customerId,
    CustomersRepository? repo,
  }) : _repo = repo ?? RemoteCustomersRepository();

  final String customerId;
  final CustomersRepository _repo;
  CustomersRepository get repository => _repo;

  static const int historyPageSize = 20;

  int _generation = 0;
  bool _disposed = false;

  AsyncValue<CustomerDetail> detailState = const AsyncLoading();

  AsyncValue<List<CustomerHistoryOrder>> historyState = const AsyncLoading();
  bool historyLoadingMore = false;
  AppError? historyLoadMoreError;
  bool _historyHasNext = false;
  int _historyPage = 1;
  int _historyTotal = 0;

  bool mutating = false;
  AppError? lastError;

  Customer? get customer => detailState.valueOrNull?.customer;
  List<CustomerVehicleLink> get vehicles =>
      detailState.valueOrNull?.vehicles ?? const <CustomerVehicleLink>[];
  bool get hasHistoryNext => _historyHasNext;
  int get historyTotal => _historyTotal;

  // ─── Load ────────────────────────────────────────────────────────────────

  Future<void> load() async {
    final generation = ++_generation;
    detailState = const AsyncLoading();
    notifyListeners();
    final result = await _repo.getCustomer(customerId);
    if (_disposed || generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        detailState = AsyncData(value);
      case Err(:final error):
        detailState = AsyncError(error);
    }
    notifyListeners();
    unawaited(loadHistory());
  }

  Future<void> refresh() => load();

  // ─── History (paginated, separate `meta` envelope) ─────────────────────

  Future<void> loadHistory() async {
    final generation = _generation;
    historyState = const AsyncLoading();
    historyLoadingMore = false;
    historyLoadMoreError = null;
    _historyPage = 1;
    _historyHasNext = false;
    notifyListeners();
    final result = await _repo.getCustomerHistory(
      customerId,
      page: 1,
      pageSize: historyPageSize,
    );
    if (_disposed || generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        _historyPage = value.pagination.page;
        _historyHasNext = value.pagination.hasNext;
        _historyTotal = value.pagination.total;
        historyState = AsyncData(value.items);
      case Err(:final error):
        historyState = AsyncError(error);
    }
    notifyListeners();
  }

  Future<void> loadMoreHistory() async {
    if (_disposed || historyLoadingMore || !_historyHasNext) return;
    final generation = _generation;
    final nextPage = _historyPage + 1;
    historyLoadingMore = true;
    historyLoadMoreError = null;
    notifyListeners();
    final result = await _repo.getCustomerHistory(
      customerId,
      page: nextPage,
      pageSize: historyPageSize,
    );
    if (_disposed || generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        final current =
            historyState.valueOrNull ?? const <CustomerHistoryOrder>[];
        _historyPage = value.pagination.page;
        _historyHasNext = value.pagination.hasNext;
        _historyTotal = value.pagination.total;
        historyState = AsyncData([...current, ...value.items]);
      case Err(:final error):
        // Keep the loaded page intact, matching CustomerListController.
        historyLoadMoreError = error;
    }
    historyLoadingMore = false;
    notifyListeners();
  }

  // ─── Edit ────────────────────────────────────────────────────────────────

  /// `PATCH /customers/[id]` is a whole-record replace — every field is
  /// required-with-nullable on the repository contract, so this method
  /// cannot accidentally send a partial update. The response omits
  /// `createdAt`; [_mergeAfterUpdate] preserves the previously-known value
  /// locally rather than showing a blank date after every successful edit.
  Future<Result<Customer>> update({
    required String? fullName,
    required String phone,
    required String? email,
    required String? note,
    bool isOrganization = false,
    String? orgRegnum,
    String? orgName,
    String? orgEmail,
  }) async {
    final current = customer;
    if (current == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Үйлчлүүлэгч ачаалагдаагүй байна'),
      );
    }
    final generation = _generation;
    mutating = true;
    lastError = null;
    notifyListeners();
    final result = await _repo.updateCustomer(
      customerId,
      fullName: fullName,
      phone: phone,
      email: email,
      note: note,
      isOrganization: isOrganization,
      orgRegnum: orgRegnum,
      orgName: orgName,
      orgEmail: orgEmail,
    );
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    switch (result) {
      case Ok(:final value):
        final merged = _mergeAfterUpdate(value, current);
        final existing = detailState.valueOrNull;
        detailState = AsyncData(
          CustomerDetail(
            customer: merged,
            vehicles: existing?.vehicles ?? const <CustomerVehicleLink>[],
          ),
        );
      case Err(:final error):
        lastError = error;
    }
    notifyListeners();
    return result;
  }

  /// The PATCH response never carries `createdAt` (see [Customer] and the
  /// repository doc comment) — this keeps the last-known value on screen
  /// instead of blanking it after every successful edit.
  Customer _mergeAfterUpdate(Customer updated, Customer previous) => Customer(
    id: updated.id,
    fullName: updated.fullName,
    phone: updated.phone,
    email: updated.email,
    note: updated.note,
    isOrganization: updated.isOrganization,
    orgRegnum: updated.orgRegnum,
    orgName: updated.orgName,
    orgEmail: updated.orgEmail,
    createdAt: updated.createdAt ?? previous.createdAt,
  );

  // ─── Delete ─────────────────────────────────────────────────────────────

  /// The caller must confirm with the user before calling this — matching
  /// `AppointmentDetailController.refundPayment`'s convention for
  /// destructive actions. A 409 `CUSTOMER_IN_USE` classifies as
  /// [CustomerFailure.inUse] via `result.error`; the screen renders that as
  /// a real explanation, not a generic failure banner.
  Future<Result<CustomerDeleteResult>> delete() async {
    final generation = _generation;
    mutating = true;
    lastError = null;
    notifyListeners();
    final result = await _repo.deleteCustomer(customerId);
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    if (result case Err(:final error)) {
      lastError = error;
    }
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
