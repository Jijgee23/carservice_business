import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/domain/working_branch_scope.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/network/working_branch_interceptor.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/data/cash_shift_repository.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';
import 'package:carservice_business/features/cash/domain/cash_shift_repository.dart';
import 'package:carservice_business/features/shell/data/working_branch_repository.dart';
import 'package:carservice_business/features/shell/domain/working_branch.dart';

/// «Кассын ээлж» list: the branch's current (open) shift on top, then every
/// shift newest first, paged.
///
/// Branch scope follows the app's working branch: while it is pinned to one
/// branch (header `X-Working-Branch`, or a roster lock) the server scopes
/// every call to it, so the screen shows that branch only. Otherwise the
/// user picks a branch chip (or «Бүгд»); the current-shift card needs a
/// concrete branch, so it shows only when one is selected.
class CashShiftListController extends ChangeNotifier {
  CashShiftListController({
    CashShiftRepository? repo,
    WorkingBranchRepository? branchRepo,
    WorkingBranchSelectionStore? store,
  }) : repo = repo ?? RemoteCashShiftRepository(),
       _branchRepo = branchRepo ?? RemoteWorkingBranchRepository(),
       _store = store ?? HiveWorkingBranchSelectionStore();

  static const pageSize = 30;

  final CashShiftRepository repo;
  final WorkingBranchRepository _branchRepo;
  final WorkingBranchSelectionStore _store;

  bool _disposed = false;
  int _generation = 0;
  bool _branchesLoaded = false;

  List<SwitchableBranch> branches = const [];

  /// Set when the server scopes every call to one branch.
  String? pinnedBranchId;
  String? _branchId;

  /// null = both; `OPEN` | `CLOSED`.
  String? status;

  AsyncValue<List<CashShift>> listState = const AsyncLoading();

  /// The selected branch's open shift; null while no branch is selected.
  AsyncValue<CashShift?>? currentState;

  bool loadingMore = false;
  AppError? loadMoreError;
  bool hasNext = false;
  int _page = 1;
  int total = 0;

  String? get branchId => pinnedBranchId ?? _branchId;

  /// Branch chips are offered only when the scope is not pinned and there
  /// is more than one branch to choose from.
  bool get canPickBranch => pinnedBranchId == null && branches.length > 1;

  String? branchName(String? id) {
    if (id == null) return null;
    for (final b in branches) {
      if (b.id == id) return b.name;
    }
    return null;
  }

  Future<void> load() async {
    if (!_branchesLoaded) await _loadBranches();
    if (_disposed) return;
    await Future.wait([_loadShifts(), _loadCurrent()]);
  }

  Future<void> refresh() => load();

  Future<void> setBranch(String? id) {
    if (pinnedBranchId != null || id == _branchId) return Future.value();
    _branchId = id;
    return load();
  }

  Future<void> setStatus(String? value) {
    if (value == status) return Future.value();
    status = value;
    return _loadShifts();
  }

  Future<void> _loadBranches() async {
    try {
      final options = await _branchRepo.fetchOptions();
      final persisted = await _store.read();
      branches = options.branches;
      pinnedBranchId =
          options.lockedBranchId ??
          (persisted != null && persisted != allWorkingBranches
              ? persisted
              : null);
      if (pinnedBranchId == null && branches.length == 1) {
        _branchId = branches.first.id;
      }
      _branchesLoaded = true;
    } catch (_) {
      // Without branch options the list still works (server default scope);
      // only the current-shift card and branch chips are unavailable. Retried
      // on the next refresh.
      branches = const [];
    }
  }

  Future<void> _loadShifts() async {
    final generation = ++_generation;
    loadingMore = false;
    loadMoreError = null;
    hasNext = false;
    _page = 1;
    listState = const AsyncLoading();
    _notify();
    final result = await repo.listShifts(_query(1));
    if (_disposed || generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        _page = value.pagination.page;
        hasNext = value.pagination.hasNext;
        total = value.pagination.total;
        listState = AsyncData(value.items);
      case Err(:final error):
        listState = AsyncError(error);
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (_disposed || loadingMore || !hasNext) return;
    final generation = _generation;
    loadingMore = true;
    loadMoreError = null;
    _notify();
    final result = await repo.listShifts(_query(_page + 1));
    if (_disposed || generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        _page = value.pagination.page;
        hasNext = value.pagination.hasNext;
        total = value.pagination.total;
        listState = AsyncData([
          ...listState.valueOrNull ?? const <CashShift>[],
          ...value.items,
        ]);
      case Err(:final error):
        loadMoreError = error;
    }
    loadingMore = false;
    _notify();
  }

  Future<void> _loadCurrent() async {
    final branch = branchId;
    if (branch == null) {
      currentState = null;
      _notify();
      return;
    }
    currentState = const AsyncLoading();
    _notify();
    final result = await repo.currentShift(branch);
    if (_disposed || branch != branchId) return;
    currentState = switch (result) {
      Ok(:final value) => AsyncData(value.shift),
      Err(:final error) => AsyncError(error),
    };
    _notify();
  }

  CashShiftQuery _query(int page) => CashShiftQuery(
    branchId: pinnedBranchId == null ? _branchId : null,
    status: status,
    page: page,
    pageSize: pageSize,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
