import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';

/// Hand-written fake for [VehiclesRepository] — P3-F1.
///
/// Deterministic in-memory seed data; no network. Mirrors the server-side
/// rules this repository binds to, so a payload the real API would reject
/// cannot pass in a test that only exercises this fake:
///
/// * the six-clause `?q=` search (`buildVehicleListWhere`), including the
///   owner name/phone clauses that `P3-B6` added to this endpoint;
/// * `MAX_VEHICLES`, enforced on create (D-154 — every entry point, no flag);
/// * the plate staying immutable across an update;
/// * the owner reported after a create being the **link's** owner, not the
///   requested one, when the registration is already owned;
/// * `VEHICLE_OWNER_CHANGE_BLOCKED` (422) and `VEHICLE_IN_USE` (409) for a
///   vehicle that has history;
/// * 404 for an unknown id — the same answer the server gives for a vehicle
///   linked to another tenant.
///
/// Vehicles are keyed by id, never by plate: plate and VIN stopped being
/// globally unique in `6c4ecc1`, and a fake that deduplicated on plate would
/// be lying about the server.
class FakeVehicleRepository implements VehiclesRepository {
  FakeVehicleRepository({
    List<Vehicle>? seed,
    Map<String, VehicleHistory>? history,
    Map<String, VinHistory>? vinHistory,
    this.maxVehicles = 50,
  }) : _vehicles = [
         ...(seed ?? [seedVehicle()]),
       ],
       _history = {...?history},
       _vinHistory = {...?vinHistory};

  final List<Vehicle> _vehicles;
  final Map<String, VehicleHistory> _history;
  final Map<String, VinHistory> _vinHistory;

  /// Set to make [getVinHistory] fail.
  bool vinHistoryFails = false;

  /// Stand-in for the tenant's `MAX_VEHICLES` plan limit.
  final int maxVehicles;

  /// Registrations already owned by somebody else, keyed by canonical plate.
  /// A create naming such a plate comes back owned by the value, whatever
  /// owner the caller asked for — this is the `ensureTenantVehicle` rule.
  final Map<String, String> preOwnedPlates = {};

  /// Set to fail the next [refreshFromHur] the way a 502 does.
  bool hurUpstreamFails = false;

  int _idSequence = 0;

  /// Call counters, so a controller test can assert a route was hit exactly
  /// once without reaching for a mocking framework.
  int listCalls = 0;
  int refreshCalls = 0;

  static Vehicle seedVehicle({
    String id = 'veh-1',
    String plate = '1234 УБА',
    String? customerId = 'cust-1',
  }) => Vehicle(
    id: id,
    plate: plate,
    vin: 'JTDKB20U793000000',
    make: 'Toyota',
    model: 'Prius 30',
    year: 2012,
    mileage: 180000,
    fuelType: 'Хайбрид',
    wheelPosition: 'Баруун',
    colorName: 'Цагаан',
    capacity: 1797,
    purpose: 'Суудал',
    ownerRegnum: 'УБ99112233',
    customerId: customerId,
    customer: customerId == null
        ? null
        : const VehicleCustomerRef(
            id: 'cust-1',
            fullName: 'Бат',
            phone: '99001122',
          ),
    isPostpaid: false,
  );

  int _indexOf(String id) => _vehicles.indexWhere((v) => v.id == id);

  AppError _notFound() =>
      const AppError(ErrorKind.notFound, 'Машин олдсонгүй.', statusCode: 404);

  /// Mirrors `searchWhere` in `lib/vehicles/vehicle-list-query.ts` exactly —
  /// six clauses: plate, make, model and vin case-insensitively, owner
  /// `fullName` case-insensitively, owner `phone` case-sensitively (phone
  /// numbers have no case). Do not widen past these six and do not drop any:
  /// the same builder backs the web dashboard, so a difference here means
  /// this fake is lying about the server.
  bool _matchesSearch(Vehicle v, String q) {
    final lower = q.toLowerCase();
    bool ci(String? value) =>
        value != null && value.toLowerCase().contains(lower);
    if (ci(v.plate) || ci(v.make) || ci(v.model) || ci(v.vin)) return true;
    if (ci(v.customer?.fullName)) return true;
    final phone = v.customer?.phone;
    return phone != null && phone.contains(q);
  }

  @override
  Future<Result<PagedResult<Vehicle>>> getVehicles({
    VehicleListQuery? query,
  }) async {
    listCalls++;
    final q = query ?? const VehicleListQuery();
    var rows = _vehicles.toList();
    final term = q.q?.trim();
    if (term != null && term.isNotEmpty) {
      rows = rows.where((v) => _matchesSearch(v, term)).toList();
    }
    // `customerId` wins over `assigned` when both are supplied, exactly as
    // `buildVehicleListWhere` does.
    if (q.customerId != null) {
      rows = rows.where((v) => v.customerId == q.customerId).toList();
    } else if (q.assigned != null) {
      rows = rows.where((v) => v.hasOwner == q.assigned).toList();
    }
    if (q.postpaid != null) {
      rows = rows.where((v) => v.isPostpaid == q.postpaid).toList();
    }

    final total = rows.length;
    // `buildMeta` clamps the page into range and never reports zero pages.
    final totalPages = (total / q.pageSize).ceil().clamp(1, 1 << 30);
    final page = q.page.clamp(1, totalPages);
    final skip = (page - 1) * q.pageSize;
    final items = rows.skip(skip).take(q.pageSize).toList(growable: false);

    return Ok(
      PagedResult(
        items: items,
        pagination: PaginationMeta(
          page: page,
          pageSize: q.pageSize,
          total: total,
          totalPages: totalPages,
          hasPrev: page > 1,
          hasNext: page < totalPages,
        ),
      ),
    );
  }

  @override
  Future<Result<Vehicle>> getVehicle(String vehicleId) async {
    final index = _indexOf(vehicleId);
    if (index < 0) return Err(_notFound());
    return Ok(_vehicles[index]);
  }

  @override
  Future<Result<Vehicle>> createVehicle({
    required String plate,
    required String make,
    required String model,
    String? vin,
    int? year,
    int? mileage,
    String? customerId,
  }) async {
    final fieldErrors = <String, String>{};
    if (plate.trim().isEmpty) fieldErrors['plate'] = 'Улсын дугаар оруулна уу.';
    if (make.trim().isEmpty) fieldErrors['make'] = 'Маркаа оруулна уу.';
    if (model.trim().isEmpty) fieldErrors['model'] = 'Моделоо оруулна уу.';
    // The API route checks only the lower year bound (Divergence 3).
    if (year != null && year < 1900) fieldErrors['year'] = 'Жил буруу.';
    if (mileage != null && mileage < 0) fieldErrors['mileage'] = 'Гүйлт буруу.';
    if (fieldErrors.isNotEmpty) {
      return Err(
        AppError(
          ErrorKind.unknown,
          'Хүсэлт буруу.',
          statusCode: 422,
          code: 'VALIDATION_FAILED',
          fieldErrors: fieldErrors,
        ),
      );
    }

    if (_vehicles.length >= maxVehicles) {
      return Err(
        const AppError(
          ErrorKind.unknown,
          'Машины хязгаарт хүрсэн байна.',
          statusCode: 422,
          code: 'PLAN_LIMIT_REACHED',
        ),
      );
    }

    final canon = plate.trim().toUpperCase();
    // `ensureTenantVehicle` never overwrites an existing owner, so the
    // reported owner can differ from the requested one.
    final realOwner = preOwnedPlates[canon] ?? customerId;
    final created = Vehicle(
      id: 'veh-new-${++_idSequence}',
      plate: canon,
      vin: vin?.trim().toUpperCase(),
      make: make.trim(),
      model: model.trim(),
      year: year,
      mileage: mileage,
      customerId: realOwner,
    );
    _vehicles.add(created);
    return Ok(created);
  }

  @override
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
  }) async {
    final index = _indexOf(vehicleId);
    if (index < 0) return Err(_notFound());
    final current = _vehicles[index];

    if (plate.trim().isEmpty || make.trim().isEmpty || model.trim().isEmpty) {
      return Err(
        AppError(
          ErrorKind.unknown,
          'Хүсэлт буруу.',
          statusCode: 422,
          code: 'VALIDATION_FAILED',
          fieldErrors: {
            if (plate.trim().isEmpty) 'plate': 'Улсын дугаар оруулна уу.',
            if (make.trim().isEmpty) 'make': 'Маркаа оруулна уу.',
            if (model.trim().isEmpty) 'model': 'Моделоо оруулна уу.',
          },
        ),
      );
    }

    if (customerId != current.customerId && _hasHistory(vehicleId)) {
      return Err(
        const AppError(
          ErrorKind.unknown,
          'Хүсэлт буруу.',
          statusCode: 422,
          code: 'VEHICLE_OWNER_CHANGE_BLOCKED',
          fieldErrors: {
            'customerId': 'Засварын түүхтэй машины эзнийг солих боломжгүй — шинэ эзэн бол машиныг шинээр бүртгэнэ.',
          },
        ),
      );
    }

    final updated = Vehicle(
      id: current.id,
      // Immutable after registration: the supplied plate is validated then
      // discarded server-side.
      plate: current.plate,
      vin: vin,
      make: make.trim(),
      model: model.trim(),
      year: year,
      mileage: mileage,
      fuelType: fuelType,
      wheelPosition: wheelPosition,
      colorName: colorName,
      capacity: capacity,
      purpose: purpose,
      ownerRegnum: ownerRegnum,
      customerId: customerId,
      customer: customerId == current.customerId ? current.customer : null,
      isPostpaid: isPostpaid ?? current.isPostpaid,
    );
    _vehicles[index] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<VehicleDeletionResult>> deleteVehicle(String vehicleId) async {
    final index = _indexOf(vehicleId);
    if (index < 0) return Err(_notFound());
    if (_hasHistory(vehicleId)) {
      return Err(
        const AppError(
          ErrorKind.unknown,
          'Энэ машинтай холбоотой засварын хуудас байгаа тул устгах боломжгүй.',
          statusCode: 409,
          code: 'VEHICLE_IN_USE',
        ),
      );
    }
    final removed = _vehicles.removeAt(index);
    return Ok(
      VehicleDeletionResult(
        id: removed.id,
        plate: removed.plate,
        make: removed.make,
        model: removed.model,
      ),
    );
  }

  @override
  Future<Result<VehicleHistory>> getHistory(String vehicleId) async {
    if (_indexOf(vehicleId) < 0) return Err(_notFound());
    return Ok(_history[vehicleId] ?? const VehicleHistory());
  }

  @override
  Future<Result<VinHistory>> getVinHistory(String vehicleId) async {
    if (vinHistoryFails) {
      return const Err(AppError(ErrorKind.unknown, 'VIN түүх алдаа.'));
    }
    if (_indexOf(vehicleId) < 0) return Err(_notFound());
    return Ok(_vinHistory[vehicleId] ?? const VinHistory());
  }

  @override
  Future<Result<VehicleHurRefresh>> refreshFromHur(String vehicleId) async {
    refreshCalls++;
    final index = _indexOf(vehicleId);
    if (index < 0) return Err(_notFound());
    if (hurUpstreamFails) {
      // Upstream failure: nothing was written, so the stored row is
      // deliberately left untouched here too.
      return Err(
        const AppError(
          ErrorKind.unknown,
          'ХУР-аас мэдээлэл татаж чадсангүй.',
          statusCode: 502,
        ),
      );
    }
    const refresh = VehicleHurRefresh(
      make: 'Toyota',
      model: 'Prius 30',
      year: 2013,
      fuelType: 'Хайбрид',
      wheelPosition: 'Баруун',
      colorName: 'Мөнгөлөг',
      capacity: 1797,
      purpose: 'Суудал',
    );
    _vehicles[index] = refresh.applyTo(_vehicles[index]);
    return Ok(refresh);
  }

  bool _hasHistory(String vehicleId) {
    final history = _history[vehicleId];
    if (history == null) return false;
    return history.orders.isNotEmpty || history.diagnosticReportCount > 0;
  }
}
