import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_repository.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';

/// Owns one vehicle's detail request, its service history, and the edit /
/// delete / HUR-refresh mutations — `P3-F5`.
///
/// Fetches by [vehicleId] (deep-link cold start included), matching
/// `P3-F4`'s customer detail and the frozen contract: there is no
/// preloaded-summary constructor here on purpose, because the list/search
/// rows this screen is opened from never carry the extended attribute block
/// (`fuelType`, `wheelPosition`, `colorName`, `capacity`, `purpose`,
/// `ownerRegnum`) or `isPostpaid` — only `GET /vehicles/[id]` does.
///
/// Generation-guarded exactly like `AppointmentDetailController` /
/// `VehicleListController`: every mutation captures `_generation` before
/// awaiting and discards a stale response rather than applying it after a
/// newer request (or dispose) has superseded it.
///
/// **The `PATCH` divergence** (measured during `P3-F1`, `TENANT_MOBILE_SLICES.md`
/// P3-F5): `PATCH /vehicles/[id]` never carries the nested `customer` block
/// that `GET` does. [save] handles this deliberately rather than rendering
/// the bare response: when the owner did not change, the previously-known
/// [VehicleCustomerRef] is carried over onto the merged vehicle so the owner
/// name never blanks after a successful save; when the owner *did* change,
/// there is no local ref to fall back to, so [save] re-fetches via [load]
/// instead of showing a stale or absent name.
///
/// **HUR refresh never discards user-entered fields.** [refreshFromHur]
/// applies the response through [VehicleHurRefresh.applyTo] — the `P3-F1`
/// seam that treats every field the refresh omitted as "no new information"
/// — onto the *current* in-memory vehicle, not a fresh fetch. A 502 upstream
/// failure is applied nowhere: it is an expected outcome, surfaced as
/// [hurError], with the vehicle left exactly as it was.
class VehicleDetailController extends ChangeNotifier {
  VehicleDetailController({required this.vehicleId, VehiclesRepository? repo})
    : _repo = repo ?? RemoteVehiclesRepository() {
    unawaited(load());
  }

  final String vehicleId;
  final VehiclesRepository _repo;

  int _generation = 0;
  bool _disposed = false;

  AsyncValue<Vehicle> detailState = const AsyncLoading();
  AsyncValue<VehicleHistory> historyState = const AsyncLoading();

  /// Same-VIN records. `null` until loaded, and stays `null` on failure or
  /// when there is nothing to show — the section hides quietly.
  VinHistory? vinHistory;

  bool saving = false;
  AppError? saveError;

  bool deleting = false;
  AppError? deleteError;

  bool refreshingHur = false;
  AppError? hurError;

  Vehicle? get vehicle => detailState.valueOrNull;

  // ─── Load (deep-link cold start and pull-to-refresh both land here) ─────

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_generation;
    detailState = const AsyncLoading();
    historyState = const AsyncLoading();
    vinHistory = null;
    notifyListeners();

    // Started together, awaited separately: one slow/failing route must not
    // block the other from rendering.
    final vehicleFuture = _repo.getVehicle(vehicleId);
    final historyFuture = _repo.getHistory(vehicleId);
    final vinFuture = _repo.getVinHistory(vehicleId);
    final vehicleResult = await vehicleFuture;
    if (_disposed || generation != _generation) return;
    switch (vehicleResult) {
      case Ok(:final value):
        detailState = AsyncData(value);
      case Err(:final error):
        detailState = AsyncError(error);
    }
    notifyListeners();

    final historyResult = await historyFuture;
    if (_disposed || generation != _generation) return;
    switch (historyResult) {
      case Ok(:final value):
        historyState = AsyncData(value);
      case Err(:final error):
        historyState = AsyncError(error);
    }
    notifyListeners();

    final vinResult = await vinFuture;
    if (_disposed || generation != _generation) return;
    if (vinResult case Ok(:final value) when value.hasContent) {
      vinHistory = value;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  // ─── Edit ────────────────────────────────────────────────────────────────

  Future<Result<Vehicle>> save({
    required String make,
    required String model,
    String? vin,
    int? year,
    int? mileage,
    String? fuelType,
    String? wheelPosition,
    String? colorName,
    int? capacity,
    String? purpose,
    String? ownerRegnum,
    String? customerId,
    bool? isPostpaid,
  }) async {
    final current = vehicle;
    if (current == null) return _noVehicleError();
    final generation = _generation;
    saving = true;
    saveError = null;
    notifyListeners();

    final result = await _repo.updateVehicle(
      vehicleId,
      // `plate` is immutable — resent only to satisfy the server's
      // validate-then-discard, never editable from this screen.
      plate: current.plate ?? '',
      make: make,
      model: model,
      vin: vin,
      year: year,
      mileage: mileage,
      fuelType: fuelType,
      wheelPosition: wheelPosition,
      colorName: colorName,
      capacity: capacity,
      purpose: purpose,
      ownerRegnum: ownerRegnum,
      customerId: customerId,
      isPostpaid: isPostpaid,
    );
    if (_disposed || generation != _generation) {
      saving = false;
      return result;
    }
    saving = false;
    switch (result) {
      case Ok(:final value):
        saveError = null;
        if (value.customerId == current.customerId) {
          // Same owner: PATCH's response has no `customer` block, so carry
          // the one we already have rather than rendering it blank.
          detailState = AsyncData(_withCustomer(value, current.customer));
          notifyListeners();
        } else {
          // Owner actually changed (only reachable when the vehicle has no
          // history — otherwise the server 422s VEHICLE_OWNER_CHANGE_BLOCKED
          // before this branch is ever reached). No local ref for the new
          // owner exists, so re-fetch instead of guessing.
          detailState = AsyncData(value);
          notifyListeners();
          unawaited(load());
        }
      case Err(:final error):
        saveError = error;
        notifyListeners();
    }
    return result;
  }

  // ─── Delete ──────────────────────────────────────────────────────────────

  Future<Result<VehicleDeletionResult>> delete() async {
    final generation = _generation;
    deleting = true;
    deleteError = null;
    notifyListeners();
    final result = await _repo.deleteVehicle(vehicleId);
    if (_disposed || generation != _generation) {
      deleting = false;
      return result;
    }
    deleting = false;
    if (result case Err(:final error)) {
      // `VEHICLE_IN_USE` (409) lands here with the server's own explanation
      // in `error.message` — the screen renders `error.display` verbatim,
      // never a generic "action failed" string.
      deleteError = error;
    }
    notifyListeners();
    return result;
  }

  // ─── Staff HUR refresh ───────────────────────────────────────────────────

  Future<Result<VehicleHurRefresh>> refreshFromHur() async {
    final current = vehicle;
    if (current == null) return _noVehicleErrorHur();
    final generation = _generation;
    refreshingHur = true;
    hurError = null;
    notifyListeners();
    final result = await _repo.refreshFromHur(vehicleId);
    if (_disposed || generation != _generation) {
      refreshingHur = false;
      return result;
    }
    refreshingHur = false;
    switch (result) {
      case Ok(:final value):
        hurError = null;
        // Merge onto whatever is current *now* (not the snapshot captured
        // before the await) so a user edit that landed while this request
        // was in flight is not clobbered either.
        final base = vehicle ?? current;
        detailState = AsyncData(value.applyTo(base));
      case Err(:final error):
        // Expected outcome (502 upstream failure) — nothing was written,
        // so the vehicle is left exactly as it was; this is not a crash
        // path and must never throw or clear `detailState`.
        hurError = error;
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

  Result<Vehicle> _noVehicleError() => const Err(
    AppError(ErrorKind.unknown, 'Машины мэдээлэл ачаалагдаагүй байна'),
  );

  Result<VehicleHurRefresh> _noVehicleErrorHur() => const Err(
    AppError(ErrorKind.unknown, 'Машины мэдээлэл ачаалагдаагүй байна'),
  );
}

/// [Vehicle] has no `copyWith` (frozen `P3-F1` domain) — rebuilt locally,
/// matching how `appointment_detail_controller.dart` handles the same
/// constraint for `AppointmentSummary`.
Vehicle _withCustomer(Vehicle v, VehicleCustomerRef? customer) => Vehicle(
  id: v.id,
  plate: v.plate,
  vin: v.vin,
  make: v.make,
  model: v.model,
  year: v.year,
  mileage: v.mileage,
  fuelType: v.fuelType,
  wheelPosition: v.wheelPosition,
  colorName: v.colorName,
  capacity: v.capacity,
  purpose: v.purpose,
  ownerRegnum: v.ownerRegnum,
  customerId: v.customerId,
  customer: customer,
  isPostpaid: v.isPostpaid,
  ownerIsOrganization: v.ownerIsOrganization,
);
