import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';

/// Server-side filters supported by `GET /api/v1/vehicles`, measured against
/// `lib/vehicles/vehicle-list-query.ts`.
///
/// The route's allow-list is exactly `q`, `customerId`, `assigned`,
/// `postpaid`, `page`, `pageSize`, `limit` and it **rejects an unknown
/// parameter with 400** (`rejectUnknownParams`). That is why this is a closed
/// class rather than a free `Map<String, dynamic>`: a typo'd filter must be
/// impossible to construct, not a runtime 400. `limit` is the legacy alias of
/// `pageSize` and is deliberately not exposed — sending both would be
/// ambiguous.
/// `?ownerKind=` values of `GET /api/v1/vehicles`.
enum VehicleOwnerKind {
  org('org'),
  person('person');

  const VehicleOwnerKind(this.wire);
  final String wire;
}

class VehicleListQuery {
  /// `?q=` — matches **six** clauses, not four: vehicle `plate`, `make`,
  /// `model`, `vin` (all case-insensitive) OR owner `fullName`
  /// (case-insensitive) OR owner `phone` (case-sensitive; phone numbers have
  /// no case). `P3-B6` deliberately widened this endpoint to the dashboard's
  /// clause set, so a search for an owner's name now returns their vehicles.
  /// Send it trimmed, and omit it entirely when empty.
  final String? q;

  /// Exact owner filter. If both this and [assigned] are supplied the server
  /// lets `customerId` win; callers should not combine them.
  final String? customerId;

  /// `?assigned=yes|no` — `true` keeps only vehicles that have an owner,
  /// `false` only unowned links, `null` applies no filter.
  final bool? assigned;

  /// `?postpaid=yes|no` on `TenantVehicle.isPostpaid`.
  final bool? postpaid;

  /// `?ownerKind=org|person` (Phase 4). Null omits the param.
  final VehicleOwnerKind? ownerKind;

  final int page;
  final int pageSize;

  const VehicleListQuery({
    this.q,
    this.customerId,
    this.assigned,
    this.postpaid,
    this.ownerKind,
    this.page = 1,
    this.pageSize = 50,
  });
}

/// One frozen repository contract for the Vehicles feature — P3-F1.
///
/// One named method per backend route, exactly as
/// `AppointmentsRepository` does. Nothing here exposes a generic
/// "update field" call: the backend's `updateVehicleCommand` is a single
/// whole-record command with its own validation, plate immutability and
/// owner-change blocking, and splitting it client-side would duplicate that
/// dispatch.
///
/// Errors a caller must expect and cannot prevent locally, all surfaced as
/// `Err(AppError)` with `statusCode`/`code`/`fieldErrors` preserved by the
/// shared `mapDioException`:
/// * `403` — the list and detail reads require `vehicles.view`;
///   create/update/HUR-refresh require `vehicles.create`/`vehicles.edit`;
///   delete requires `vehicles.delete`.
/// * `404` — a vehicle with no `TenantVehicle` link for this tenant is
///   indistinguishable from one that does not exist. Never treat a 404 as
///   proof the row is gone globally.
/// * `422 PLAN_LIMIT_REACHED` — `MAX_VEHICLES` is enforced on **every** entry
///   point (D-154 supersedes D-151), so [createVehicle] can fail for a reason
///   no form validation can predict.
/// * `422 VALIDATION_FAILED` — carries `fieldErrors` keyed by `plate`,
///   `make`, `model`, `year`, `mileage`, `capacity`, `wheelPosition`,
///   `customerId`.
/// * `422 VEHICLE_OWNER_CHANGE_BLOCKED` — [updateVehicle] cannot move a
///   vehicle with service history to another owner.
/// * `409 VEHICLE_IN_USE` — [deleteVehicle] against a vehicle with orders or
///   diagnostic reports.
/// * `502` — [refreshFromHur] upstream failure. Expected, not a crash path;
///   nothing was written.
abstract interface class VehiclesRepository {
  /// `GET /api/v1/vehicles`.
  Future<Result<PagedResult<Vehicle>>> getVehicles({VehicleListQuery? query});

  /// `GET /api/v1/vehicles/[id]` — the only response carrying the extended
  /// attribute block plus the nested owner.
  Future<Result<Vehicle>> getVehicle(String vehicleId);

  /// `POST /api/v1/vehicles`.
  ///
  /// The returned vehicle reports the **link's real owner**, which may differ
  /// from [customerId]: `ensureTenantVehicle` never overwrites an existing
  /// owner. Callers must render the returned `customerId`, never echo back
  /// the one they sent. The response also omits the extended attribute block
  /// and `isPostpaid`; fetch [getVehicle] if those are needed.
  ///
  /// This route does not accept the extended fields at all (no `fuelType`,
  /// `wheelPosition`, `colorName`, `capacity`, `purpose`, `ownerRegnum`,
  /// `isPostpaid`) and does not enforce the 2100 year upper bound that the
  /// dashboard's own create action does — only `year >= 1900`.
  Future<Result<Vehicle>> createVehicle({
    required String plate,
    required String make,
    required String model,
    String? vin,
    int? year,
    int? mileage,
    String? customerId,
  });

  /// `PATCH /api/v1/vehicles/[id]` — a whole-record update.
  ///
  /// `plate` is **immutable after registration**: `updateVehicleCommand`
  /// validates the supplied plate (so it must still be non-empty) and then
  /// discards it. There is intentionally no plate parameter here rather than
  /// a parameter that silently does nothing; the current plate is resent by
  /// the data source from [plate] purely to satisfy that validation.
  ///
  /// Every omitted optional argument is sent as `null` and **clears** the
  /// stored value — this is a replace, not a merge. Callers must send the
  /// full current record back.
  Future<Result<Vehicle>> updateVehicle(
    String vehicleId, {
    required String plate,
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
  });

  /// `DELETE /api/v1/vehicles/[id]` — unlinks this tenant only.
  Future<Result<VehicleDeletionResult>> deleteVehicle(String vehicleId);

  /// `GET /api/v1/vehicles/[id]/history`.
  Future<Result<VehicleHistory>> getHistory(String vehicleId);

  /// `GET /api/v1/vehicles/[id]/vin-history` (vehicles.view).
  Future<Result<VinHistory>> getVinHistory(String vehicleId);

  /// `POST /api/v1/vehicles/[id]/refresh-hur`.
  Future<Result<VehicleHurRefresh>> refreshFromHur(String vehicleId);
}
