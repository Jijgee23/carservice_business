import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_dto.dart';
import 'package:carservice_business/features/vehicles/data/vehicles_data_source.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';

/// Remote adapter for [VehiclesRepository] — P3-F1. JSON and Dio stay below
/// the repository contract; controllers depend on [VehiclesRepository] or the
/// fake, matching `RemoteAppointmentsRepository`.
class RemoteVehiclesRepository implements VehiclesRepository {
  RemoteVehiclesRepository({VehiclesDataSource? dataSource})
    : _dataSource = dataSource ?? RemoteVehiclesDataSource();

  final VehiclesDataSource _dataSource;

  @override
  Future<Result<PagedResult<Vehicle>>> getVehicles({
    VehicleListQuery? query,
  }) async {
    final effective = query ?? const VehicleListQuery();
    try {
      final parsed = VehiclePageDto.fromJson(
        await _dataSource.list(_listQuery(effective)),
      );
      return Ok(
        PagedResult(items: parsed.items, pagination: parsed.pagination),
      );
    } catch (error) {
      return Err(_error(error, 'Машины жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<Vehicle>> getVehicle(String vehicleId) async {
    try {
      return Ok(VehicleDto.fromJson(await _dataSource.detail(vehicleId)).value);
    } catch (error) {
      return Err(_error(error, 'Машины мэдээлэл ачаалж чадсангүй'));
    }
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
    try {
      // Only the seven keys `POST /api/v1/vehicles` reads. The extended
      // attribute block is not accepted by this route; sending it would be
      // silently ignored, which is worse than not offering it.
      return Ok(
        VehicleDto.fromJson(
          await _dataSource.create({
            'plate': plate,
            'make': make,
            'model': model,
            if (vin != null) 'vin': vin,
            if (year != null) 'year': year,
            if (mileage != null) 'mileage': mileage,
            if (customerId != null) 'customerId': customerId,
          }),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Машин бүртгэж чадсангүй'));
    }
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
    try {
      // Every nullable field is sent explicitly, including as `null`: the
      // command replaces the whole record, so an omitted key and an explicit
      // `null` mean the same thing server-side ("clear it"). Writing them out
      // makes that destructive semantic visible at the call site instead of
      // hiding it behind `if (x != null)`.
      //
      // `isPostpaid` is the one exception — `updateVehicleCommand` maps a
      // non-boolean to `undefined`, i.e. "leave it", so it is omitted when
      // the caller has no opinion rather than defaulted to `false`.
      return Ok(
        VehicleDto.fromJson(
          await _dataSource.update(vehicleId, {
            // Validated then discarded server-side (plate is immutable after
            // registration) — sent only to satisfy that validation.
            'plate': plate,
            'make': make,
            'model': model,
            'vin': vin,
            'year': year,
            'mileage': mileage,
            'fuelType': fuelType,
            'wheelPosition': wheelPosition,
            'colorName': colorName,
            'capacity': capacity,
            'purpose': purpose,
            'ownerRegnum': ownerRegnum,
            'customerId': customerId,
            if (isPostpaid != null) 'isPostpaid': isPostpaid,
          }),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Машины мэдээлэл хадгалж чадсангүй'));
    }
  }

  @override
  Future<Result<VehicleDeletionResult>> deleteVehicle(String vehicleId) async {
    try {
      return Ok(
        VehicleDeletionResultDto.fromJson(await _dataSource.delete(vehicleId))
            .value,
      );
    } catch (error) {
      return Err(_error(error, 'Машин устгаж чадсангүй'));
    }
  }

  @override
  Future<Result<VehicleHistory>> getHistory(String vehicleId) async {
    try {
      return Ok(
        VehicleHistoryDto.fromJson(await _dataSource.history(vehicleId)).value,
      );
    } catch (error) {
      return Err(_error(error, 'Машины түүх ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<VinHistory>> getVinHistory(String vehicleId) async {
    try {
      return Ok(
        VinHistoryDto.fromJson(await _dataSource.vinHistory(vehicleId)).value,
      );
    } catch (error) {
      return Err(_error(error, 'VIN түүх ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<VehicleHurRefresh>> refreshFromHur(String vehicleId) async {
    try {
      return Ok(
        VehicleHurRefreshDto.fromJson(await _dataSource.refreshHur(vehicleId))
            .value,
      );
    } catch (error) {
      // A 502 (upstream HUR failure) arrives here as an `AppError` from the
      // consolidated mapper and is returned verbatim — it is an expected
      // outcome with nothing written server-side, not a crash path.
      return Err(_error(error, 'ХУР-аас мэдээлэл шинэчилж чадсангүй'));
    }
  }
}

/// Builds only the parameters `parseVehicleListQuery` allows. Anything else
/// makes the route answer 400 (`rejectUnknownParams`), so this map is the
/// single place that must stay in step with that allow-list.
Map<String, dynamic> _listQuery(VehicleListQuery query) => {
  'page': query.page,
  'pageSize': query.pageSize,
  // Trimmed, and omitted entirely when empty/whitespace-only — an empty `q`
  // is a vacuous parameter on the wire.
  // A plate-shaped search is sent canonical, as plates are stored.
  if (query.q != null && query.q!.trim().isNotEmpty)
    'q': plateSearchQuery(query.q!),
  if (query.customerId != null) 'customerId': query.customerId,
  if (query.assigned != null) 'assigned': query.assigned! ? 'yes' : 'no',
  if (query.postpaid != null) 'postpaid': query.postpaid! ? 'yes' : 'no',
  if (query.ownerKind != null) 'ownerKind': query.ownerKind!.wire,
};

AppError _error(Object error, String fallback) => switch (error) {
  AppError value => value,
  VehicleParseException value => AppError(ErrorKind.unknown, value.message),
  _ => AppError(ErrorKind.unknown, fallback),
};
