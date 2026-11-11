import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/branches/data/branch_repository.dart';
import 'package:carservice_business/features/branches/domain/branch.dart';
import 'package:carservice_business/features/branches/domain/branches_repository.dart';

/// "Салбарууд" list state. A refresh keeps the previous rows on failure.
class BranchListController extends ChangeNotifier {
  BranchListController({BranchesRepository? repo}) : _repo = repo ?? RemoteBranchesRepository();

  final BranchesRepository _repo;
  BranchesRepository get repository => _repo;

  AsyncValue<List<BranchSummary>> state = const AsyncLoading();
  bool _disposed = false;
  int _generation = 0;

  List<BranchSummary> get branches => state.valueOrNull ?? const [];

  Future<void> load() async {
    final gen = ++_generation;
    if (state is! AsyncData) {
      state = const AsyncLoading();
      _notify();
    }
    final result = await _repo.listBranches();
    if (gen != _generation || _disposed) return;
    state = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => state is AsyncData ? state : AsyncError(error),
    };
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
