import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/branches/data/branch_repository.dart';
import 'package:carservice_business/features/branches/domain/branch.dart';
import 'package:carservice_business/features/branches/domain/branches_repository.dart';

/// What happened to a [BranchFormController.submit].
sealed class BranchSaveOutcome {
  const BranchSaveOutcome();
}

final class BranchSaved extends BranchSaveOutcome {
  const BranchSaved(this.branch);
  final BranchDetail branch;
}

/// The new hours shorten upcoming bookings: ask, then resubmit with
/// `confirm: true`.
final class BranchNeedsConfirm extends BranchSaveOutcome {
  const BranchNeedsConfirm(this.impact);
  final BranchScheduleImpactError impact;
}

/// Shown in [BranchFormController.formError] / `fieldErrors`.
final class BranchSaveFailed extends BranchSaveOutcome {
  const BranchSaveFailed();
}

/// Create (`branchId == null`) or edit one branch: the detail and tag
/// options, the save with the server's field errors, the schedule-impact
/// confirmation, toggle-active and delete.
class BranchFormController extends ChangeNotifier {
  BranchFormController({this.branchId, BranchesRepository? repo})
    : _repo = repo ?? RemoteBranchesRepository();

  final String? branchId;
  final BranchesRepository _repo;

  bool get isEdit => branchId != null;

  /// Edit: the loaded branch. Create: [AsyncData] of null right away.
  AsyncValue<BranchDetail?> detail = const AsyncLoading();
  List<BranchTag> tagOptions = const [];
  String? tagsError;

  bool saving = false;
  bool busy = false;
  Map<String, String> fieldErrors = const {};
  String? formError;
  bool _disposed = false;

  BranchDetail? get branch => detail.valueOrNull;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    detail = const AsyncLoading();
    _notify();
    final tagsFuture = _repo.listTags();
    final id = branchId;
    if (id != null) {
      final result = await _repo.getBranch(id);
      detail = switch (result) {
        Ok(:final value) => AsyncData(value),
        Err(:final error) => AsyncError(error),
      };
    } else {
      detail = const AsyncData(null);
    }
    final tags = await tagsFuture;
    switch (tags) {
      case Ok(:final value):
        tagOptions = value;
        tagsError = null;
      case Err(:final error):
        tagsError = error.display;
    }
    _mergeOwnTags();
    _notify();
  }

  /// The public catalog lists only tags already in use; keep the branch's
  /// own tags selectable even when missing there.
  void _mergeOwnTags() {
    final own = branch?.tags ?? const <BranchTag>[];
    final known = {for (final t in tagOptions) t.id};
    final missing = own.where((t) => !known.contains(t.id)).toList();
    if (missing.isEmpty) return;
    tagOptions = [...tagOptions, ...missing]..sort((a, b) => a.name.compareTo(b.name));
  }

  void clearFieldError(String key) {
    if (!fieldErrors.containsKey(key)) return;
    fieldErrors = Map.of(fieldErrors)..remove(key);
    _notify();
  }

  Future<BranchSaveOutcome> submit(BranchDraft draft, {bool confirm = false}) async {
    if (saving) return const BranchSaveFailed();
    fieldErrors = const {};
    formError = null;
    saving = true;
    _notify();
    final id = branchId;
    final result = id == null
        ? await _repo.createBranch(draft)
        : await _repo.updateBranch(id, draft, confirm: confirm);
    saving = false;
    switch (result) {
      case Ok(:final value):
        detail = AsyncData(value);
        _notify();
        return BranchSaved(value);
      case Err(:final error):
        if (error is BranchScheduleImpactError && error.needsConfirm && !confirm) {
          _notify();
          return BranchNeedsConfirm(error);
        }
        _applyError(error);
        _notify();
        return const BranchSaveFailed();
    }
  }

  /// Field keys the form renders inline (`schedule_<DAY>_openTime` too).
  static bool _isFormField(String key) =>
      const {
        'name',
        'phone',
        'address',
        'latitude',
        'longitude',
        'openTime',
        'closeTime',
        'slotMinutes',
        'slotCapacity',
        'tagIds',
      }.contains(key) ||
      key.startsWith('schedule_');

  void _applyError(AppError error) {
    final fe = error.fieldErrors ?? const <String, String>{};
    fieldErrors = fe;
    final unshown = fe.entries.where((e) => !_isFormField(e.key)).map((e) => e.value);
    formError = fe.isEmpty ? error.display : (unshown.isEmpty ? null : unshown.first);
  }

  /// Answers an error message, or null on success.
  Future<String?> toggleActive() async {
    final current = branch;
    if (current == null || busy) return null;
    busy = true;
    _notify();
    final result = await _repo.toggleActive(current.id);
    busy = false;
    String? message;
    switch (result) {
      case Ok():
        final refreshed = await _repo.getBranch(current.id);
        if (refreshed case Ok(:final value)) detail = AsyncData(value);
      case Err(:final error):
        message = error.display;
    }
    _notify();
    return message;
  }

  Future<String?> delete() async {
    final current = branch;
    if (current == null || busy) return null;
    busy = true;
    _notify();
    final result = await _repo.deleteBranch(current.id);
    busy = false;
    _notify();
    return switch (result) {
      Ok() => null,
      Err(:final error) => error.display,
    };
  }

  Future<BranchPinAddress?> addressAt(double lat, double lng) async =>
      (await _repo.addressAt(lat, lng)).valueOrNull;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
