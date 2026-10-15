import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_error_codes.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_list_controller.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';

/// Owns one order detail request and its server-authoritative mutations.
///
/// The list controller is deliberately injected instead of being recreated:
/// a successful detail mutation must refresh the same list instance that owns
/// the active filters, page and total. Failed mutations never write a local
/// value; the API remains the source of truth for every transition.
class OrderDetailController extends ChangeNotifier {
  OrderDetailController({
    required this.repo,
    this.listController,
    this.branchController,
  }) {
    branchController?.addListener(_branchChanged);
  }

  final OrdersRepository repo;
  final OrderListController? listController;
  final WorkingBranchController? branchController;

  AsyncValue<ServiceOrderDetail> detailState = const AsyncLoading();
  AppError? _detailRefreshError;
  AsyncValue<List<AssignableUser>> assignableUsersState = const AsyncLoading();
  bool loadingAssignableUsers = false;
  String? assignableUsersError;

  String? _orderId;
  String? _lastBranch;
  int _generation = 0;
  int _assignableGeneration = 0;
  bool _disposed = false;
  bool _assignableUsersRequested = false;

  String? get orderId => _orderId;
  ServiceOrderDetail? get order => detailState.valueOrNull;
  AppError? get detailRefreshError => _detailRefreshError;

  Future<void> load(String id) async {
    final generation = ++_generation;
    _orderId = id;
    _detailRefreshError = null;
    detailState = const AsyncLoading();
    notifyListeners();

    final result = await repo.getOrderDetail(id);
    if (_disposed || generation != _generation || id != _orderId) return;
    detailState = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => AsyncError(error),
    };
    notifyListeners();
  }

  Future<void> refresh() async {
    final id = _orderId;
    if (id == null) return;
    final current = detailState.valueOrNull;
    if (current == null) {
      await load(id);
      return;
    }
    await _refreshPreservingDetail(current);
  }

  /// Compatibility names for callers that used the pre-F4 controller.
  Future<void> loadDetail(String id) => load(id);

  Future<void> refreshDetail() => refresh();

  Future<void> loadAssignableUsers() async {
    _assignableUsersRequested = true;
    if (_disposed || loadingAssignableUsers) return;
    final generation = ++_assignableGeneration;
    // The order's own branch: assignment is validated against it
    // (ASSIGNEE_INELIGIBLE), so "all branches" must not list everyone.
    final branchId = order?.branch.id ?? branchController?.selectedBranchId;
    loadingAssignableUsers = true;
    assignableUsersError = null;
    assignableUsersState = const AsyncLoading();
    notifyListeners();

    final result = await repo.getAssignableUsers(branchId: branchId);
    if (_disposed || generation != _assignableGeneration) return;
    loadingAssignableUsers = false;
    assignableUsersState = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => AsyncError(error),
    };
    if (result case Err(:final error)) {
      assignableUsersError = error.display;
    }
    notifyListeners();
  }

  Future<Result<ServiceOrderDetail>> updateStatus(
    OrderStatus status, {
    int? durationMinutes,
  }) async {
    final id = _orderId;
    if (id == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Засварын хуудас сонгогдоогүй байна'),
      );
    }
    final generation = _generation;
    final result = await repo.updateStatus(
      id,
      status,
      durationMinutes: durationMinutes,
    );
    if (_disposed || generation != _generation) return result;
    return _afterDetailMutation(result);
  }

  Future<Result<ServiceOrderDetail>> updateAssignment(
    String assignedToId,
  ) async {
    final id = _orderId;
    if (id == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Засварын хуудас сонгогдоогүй байна'),
      );
    }
    final generation = _generation;
    final result = await repo.updateAssignment(id, assignedToId);
    if (_disposed || generation != _generation) return result;
    return _afterDetailMutation(result);
  }

  Future<Result<OrderScheduleResult>> reviseExpectedFinish(
    DateTime? expectedFinishAt, {
    bool confirmed = false,
  }) async {
    final id = _orderId;
    if (id == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Засварын хуудас сонгогдоогүй байна'),
      );
    }
    final generation = _generation;
    final result = await repo.reviseExpectedFinish(
      id,
      expectedFinishAt,
      confirmed: confirmed,
    );
    if (_disposed || generation != _generation) return result;
    return _afterScheduleMutation(result);
  }

  Future<Result<OrderScheduleResult>> rescheduleOrder(
    DateTime scheduledAt, {
    bool confirmed = false,
  }) async {
    final id = _orderId;
    if (id == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Засварын хуудас сонгогдоогүй байна'),
      );
    }
    final generation = _generation;
    final result = await repo.rescheduleOrder(
      id,
      scheduledAt,
      confirmed: confirmed,
    );
    if (_disposed || generation != _generation) return result;
    return _afterScheduleMutation(result);
  }

  Future<Result<void>> deleteOrder() async {
    final id = _orderId;
    if (id == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Засварын хуудас сонгогдоогүй байна'),
      );
    }
    final generation = _generation;
    final result = await repo.deleteOrder(id);
    if (_disposed || generation != _generation) return result;
    if (result case Ok()) {
      await listController?.refresh();
      if (!_disposed && generation == _generation) {
        detailState = const AsyncError(
          AppError(ErrorKind.notFound, 'Засварын хуудас устгагдсан'),
        );
        notifyListeners();
      }
    }
    return result;
  }

  static bool requiresConfirmation(AppError error) =>
      error.statusCode == 409 &&
      error.code == OrdersErrorCodes.confirmationRequired;

  Future<Result<ServiceOrderDetail>> _afterDetailMutation(
    Result<ServiceOrderDetail> result,
  ) async {
    if (result case Ok(:final value)) {
      // The mutation response is already an authoritative committed value.
      // Keep it visible even when the follow-up reconciliation request fails.
      detailState = AsyncData(value);
      _detailRefreshError = null;
      notifyListeners();
      final refreshed = await _refreshPreservingDetail(value);
      await listController?.refresh();
      return Ok(refreshed);
    }
    return result;
  }

  Future<Result<OrderScheduleResult>> _afterScheduleMutation(
    Result<OrderScheduleResult> result,
  ) async {
    if (result case Ok()) {
      final current = detailState.valueOrNull;
      if (current == null) {
        await refresh();
      } else {
        await _refreshPreservingDetail(current);
      }
      await listController?.refresh();
    }
    return result;
  }

  Future<ServiceOrderDetail> _refreshPreservingDetail(
    ServiceOrderDetail fallback,
  ) async {
    final id = _orderId;
    if (id == null || _disposed) return fallback;
    final generation = ++_generation;
    _detailRefreshError = null;
    notifyListeners();

    final result = await repo.getOrderDetail(id);
    if (_disposed || generation != _generation || id != _orderId) {
      return detailState.valueOrNull ?? fallback;
    }

    switch (result) {
      case Ok(:final value):
        detailState = AsyncData(value);
        _detailRefreshError = null;
        notifyListeners();
        return value;
      case Err(:final error):
        detailState = AsyncData(fallback);
        _detailRefreshError = error;
        notifyListeners();
        return fallback;
    }
  }

  void _branchChanged() {
    if (_disposed) return;
    final branch = branchController?.selectedBranchId;
    if (_lastBranch == null && _orderId == null) {
      _lastBranch = branch;
      return;
    }
    if (_lastBranch == branch) return;
    _lastBranch = branch;
    _assignableGeneration++;
    final reloadRoster = _assignableUsersRequested;
    loadingAssignableUsers = false;
    assignableUsersState = const AsyncLoading();
    assignableUsersError = null;
    final id = _orderId;
    if (id != null) load(id);
    if (reloadRoster) loadAssignableUsers();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _assignableGeneration++;
    branchController?.removeListener(_branchChanged);
    super.dispose();
  }
}
