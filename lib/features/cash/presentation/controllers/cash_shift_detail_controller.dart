import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/data/cash_shift_repository.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';
import 'package:carservice_business/features/cash/domain/cash_shift_repository.dart';

/// One shift's detail (`GET /cash/sessions/[id]`): figures, per-method
/// breakdown and the ledger rows. [changed] tells the list to reload after
/// a close.
class CashShiftDetailController extends ChangeNotifier {
  CashShiftDetailController({required this.shiftId, CashShiftRepository? repo})
    : repo = repo ?? RemoteCashShiftRepository();

  final String shiftId;
  final CashShiftRepository repo;

  AsyncValue<CashShiftDetail> state = const AsyncLoading();
  bool changed = false;
  bool _disposed = false;
  int _generation = 0;

  CashShift? get shift => state.valueOrNull?.shift;

  Future<void> load() async {
    final generation = ++_generation;
    if (state is! AsyncData) {
      state = const AsyncLoading();
      _notify();
    }
    final result = await repo.shiftDetail(shiftId);
    if (_disposed || generation != _generation) return;
    state = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => AsyncError(error),
    };
    _notify();
  }

  /// After the close sheet succeeded.
  Future<void> markClosed() {
    changed = true;
    return load();
  }

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
