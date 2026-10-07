/// Envelope parsing for Vehicles — P3-F1.
///
/// Field-level tolerance lives on the domain models themselves
/// (`vehicle.dart`'s `fromJson` factories never throw for an optional field).
/// This file only unwraps the top-level response envelopes
/// (`{vehicles:[...], pagination}`, `{vehicle:{...}}`,
/// `{orders, appointments, diagnosticReportCount, ownerLocked}`) and enforces
/// the handful of fields the contract treats as structurally required for a
/// response to be usable at all — the pagination integers, and the presence
/// of the envelope key itself.
///
/// Same shape as `features/appointments/data/appointment_dto.dart`; kept as a
/// sibling rather than a shared generic because the required/optional split
/// is contract-specific and a generic unwrapper would hide it.
library;

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';

typedef JsonMap = Map<String, dynamic>;

JsonMap _map(Object? value, String label) {
  if (value is! Map) throw VehicleParseException('$label буруу байна.');
  return Map<String, dynamic>.from(value);
}

int _requiredInt(JsonMap json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw VehicleParseException('$key буруу байна.');
}

bool _requiredBool(JsonMap json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw VehicleParseException('$key буруу байна.');
}

PaginationMeta _pagination(Object? raw) {
  final json = _map(raw, 'pagination');
  final page = _requiredInt(json, 'page');
  final pageSize = _requiredInt(json, 'pageSize');
  final total = _requiredInt(json, 'total');
  final totalPages = _requiredInt(json, 'totalPages');
  if (page < 1 || pageSize < 1 || total < 0 || totalPages < 0) {
    throw const VehicleParseException('Хуудаслалтын мэдээлэл буруу байна.');
  }
  return PaginationMeta(
    page: page,
    pageSize: pageSize,
    total: total,
    totalPages: totalPages,
    hasPrev: _requiredBool(json, 'hasPrev'),
    hasNext: _requiredBool(json, 'hasNext'),
  );
}

/// `GET /api/v1/vehicles` — `{vehicles:[...], pagination}`.
///
/// A non-map entry in `vehicles` is skipped rather than throwing, matching
/// `AppointmentPageDto`; a row whose `id` is missing still throws, because a
/// vehicle with no id cannot be opened, selected or refreshed and silently
/// dropping it would hide a real server defect behind a short list.
class VehiclePageDto {
  const VehiclePageDto(this.items, this.pagination);
  final List<Vehicle> items;
  final PaginationMeta pagination;

  factory VehiclePageDto.fromJson(Object? raw) {
    final json = _map(raw, 'vehicles response');
    final list = json['vehicles'];
    if (list is! List) {
      throw const VehicleParseException('Машины жагсаалт буруу байна.');
    }
    return VehiclePageDto(
      list
          .whereType<Map>()
          .map((item) => Vehicle.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      _pagination(json['pagination']),
    );
  }
}

/// `GET /api/v1/vehicles/[id]`, `POST /api/v1/vehicles`,
/// `PATCH /api/v1/vehicles/[id]` — all three are `{vehicle:{...}}`.
class VehicleDto {
  const VehicleDto(this.value);
  final Vehicle value;

  factory VehicleDto.fromJson(Object? raw) {
    final json = _map(raw, 'vehicle response');
    return VehicleDto(Vehicle.fromJson(_map(json['vehicle'], 'vehicle')));
  }
}

/// `DELETE /api/v1/vehicles/[id]` — `{vehicle:{id, plate, make, model}}`.
class VehicleDeletionResultDto {
  const VehicleDeletionResultDto(this.value);
  final VehicleDeletionResult value;

  factory VehicleDeletionResultDto.fromJson(Object? raw) {
    final json = _map(raw, 'vehicle delete response');
    return VehicleDeletionResultDto(
      VehicleDeletionResult.fromJson(_map(json['vehicle'], 'vehicle')),
    );
  }
}

/// `GET /api/v1/vehicles/[id]/history` —
/// `{orders:[...], appointments:[...], diagnosticReportCount, ownerLocked}`.
///
/// A vehicle with no history at all is a perfectly normal response, so an
/// absent or malformed list degrades to empty rather than throwing. A row
/// without an `id` still throws, for the same reason as the list route: it
/// cannot be opened.
class VehicleHistoryDto {
  const VehicleHistoryDto(this.value);
  final VehicleHistory value;

  factory VehicleHistoryDto.fromJson(Object? raw) {
    final json = _map(raw, 'vehicle history response');
    final orders = json['orders'];
    final appointments = json['appointments'];
    return VehicleHistoryDto(
      VehicleHistory(
        orders: orders is List
            ? orders
                  .whereType<Map>()
                  .map(
                    (e) => VehicleHistoryOrder.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList(growable: false)
            : const [],
        appointments: appointments is List
            ? appointments
                  .whereType<Map>()
                  .map(
                    (e) => VehicleHistoryAppointment.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList(growable: false)
            : const [],
        diagnosticReportCount: json['diagnosticReportCount'] is int
            ? json['diagnosticReportCount'] as int
            : 0,
        // Server-computed (`isOwnerLocked`). Absent/malformed degrades to
        // `false` — the permissive value — because the server rejects a
        // blocked owner change with 422 regardless of what this client
        // believes, so a stale `false` costs one round trip while a wrongly
        // sticky `true` would make a legitimate edit unreachable.
        ownerLocked: json['ownerLocked'] == true,
      ),
    );
  }
}

/// `POST /api/v1/vehicles/[id]/refresh-hur` — `{vehicle:{...}}` with no `id`.
class VehicleHurRefreshDto {
  const VehicleHurRefreshDto(this.value);
  final VehicleHurRefresh value;

  factory VehicleHurRefreshDto.fromJson(Object? raw) {
    final json = _map(raw, 'HUR refresh response');
    return VehicleHurRefreshDto(
      VehicleHurRefresh.fromJson(_map(json['vehicle'], 'vehicle')),
    );
  }
}

/// `GET /api/v1/vehicles/[id]/vin-history` —
/// `{vin, records:[...], otherTenantRecords}}` (a `data` wrapper is also tolerated).
/// Every field degrades rather than throws; a record without a `vehicleId`
/// is skipped because it cannot be opened.
class VinHistoryDto {
  const VinHistoryDto(this.value);
  final VinHistory value;

  factory VinHistoryDto.fromJson(Object? raw) {
    var json = _map(raw, 'vin history response');
    if (json['data'] is Map) json = _map(json['data'], 'vin history');
    final records = json['records'];
    DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
    String? str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    return VinHistoryDto(
      VinHistory(
        vin: str(json['vin']),
        records: records is List
            ? records
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .where((e) => str(e['vehicleId']) != null)
                  .map(
                    (e) => VinHistoryRecord(
                      vehicleId: e['vehicleId'] as String,
                      plate: str(e['plate']) ?? '',
                      make: str(e['make']),
                      model: str(e['model']),
                      year: e['year'] is int ? e['year'] as int : null,
                      ownerName: str(e['ownerName']),
                      orderCount: e['orderCount'] is num
                          ? (e['orderCount'] as num).toInt()
                          : 0,
                      lastOrderAt: date(e['lastOrderAt']),
                      createdAt: date(e['createdAt']),
                    ),
                  )
                  .toList(growable: false)
            : const [],
        otherTenantRecords: json['otherTenantRecords'] is num
            ? (json['otherTenantRecords'] as num).toInt()
            : 0,
      ),
    );
  }
}
