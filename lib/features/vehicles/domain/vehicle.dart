/// Vehicles domain model — P3-F1.
///
/// Measured field-by-field against the `carservice.mn` backend as it stands
/// after `6c4ecc1` ("vehicle-per-owner"):
///
/// * `app/api/v1/vehicles/route.ts` (GET list, POST create)
/// * `app/api/v1/vehicles/[id]/route.ts` (GET / PATCH / DELETE)
/// * `app/api/v1/vehicles/[id]/history/route.ts`
/// * `app/api/v1/vehicles/[id]/refresh-hur/route.ts`
/// * `lib/vehicles/vehicle-commands.ts` (`VehicleRecord`), which is what
///   PATCH serialises verbatim, and whose `customerId` is the **link's real
///   owner** — not the `customerId` the caller asked for. `ensureTenantVehicle`
///   never overwrites an existing owner, so a create/update against an
///   already-owned registration comes back owned by somebody else. The model
///   therefore treats [Vehicle.customerId] as an observation, never as an echo
///   of the request.
/// * `lib/vehicles/vehicle-list-query.ts` (the list/search contract),
/// * `lib/vehicles/vehicle-history.ts` + `isOwnerLocked`,
/// * `lib/vehicle-hur-refresh.ts` (minus the two cross-tenant counts the
///   staff route deliberately strips).
///
/// Deliberately NOT modelled — do not reintroduce:
/// * plate history. `VehiclePlateHistory` was dropped by `6c4ecc1`.
/// * globally-unique `plate`/`vin`. Both may repeat across owners now; the
///   identity of a row is its `id`, and nothing here may key off a plate.
/// * cross-tenant owner import. Removed by decision D-153.
///
/// Defensive parsing follows the Appointments precedent
/// (`features/appointments/domain/appointment.dart`): every field the backend
/// may omit, extend, or send in a shape this build does not know about
/// degrades to `null` or a tolerant default. Only a structurally missing `id`
/// throws [VehicleParseException].
library;

/// Typed failure for a structurally malformed Vehicles payload — thrown only
/// when an `id` the contract calls unconditionally required is missing or the
/// wrong type. Everything else degrades; see the module doc comment.
class VehicleParseException implements Exception {
  const VehicleParseException(this.message);

  final String message;

  @override
  String toString() => 'VehicleParseException: $message';
}

// ─── Refs ──────────────────────────────────────────────────────────────────

/// The owner block the list and single-GET routes embed
/// (`customer: {id, fullName, phone}`), or `null` when the tenant's
/// `TenantVehicle` link has no `customerId`. Prisma types `fullName`/`phone`
/// as non-null on `Customer`, but they are parsed tolerantly anyway — an
/// unassigned link sends the whole block as `null`, and a future serializer
/// change must not crash a list screen.
class VehicleCustomerRef {
  final String? id;
  final String? fullName;
  final String? phone;

  const VehicleCustomerRef({this.id, this.fullName, this.phone});

  factory VehicleCustomerRef.fromJson(Map<String, dynamic> j) =>
      VehicleCustomerRef(
        id: _optString(j['id']),
        fullName: _optString(j['fullName']),
        phone: _optString(j['phone']),
      );

  String get displayName => fullName ?? phone ?? 'Эзэнгүй';
}

// ─── Vehicle ───────────────────────────────────────────────────────────────

/// One vehicle as this tenant sees it.
///
/// A single class covers all four serialisations, because they are strict
/// subsets of one another and a second near-identical "summary" class would
/// only invite drift:
///
/// | field | list GET | POST | GET `[id]` | PATCH |
/// |---|---|---|---|---|
/// | `id` | ✓ | ✓ | ✓ | ✓ |
/// | `plate` `vin` `make` `model` `year` `mileage` | ✓ | ✓ | ✓ | ✓ |
/// | `customerId` | ✓ | ✓ | ✓ | ✓ |
/// | `customer{}` | ✓ | — | ✓ | — |
/// | `fuelType` `wheelPosition` `colorName` `capacity` `purpose` `ownerRegnum` | — | — | ✓ | ✓ |
/// | `isPostpaid` | — | — | ✓ | ✓ |
///
/// An absent field is therefore `null`/[isPostpaid] `false` and means "this
/// response did not carry it", never "the server cleared it". Callers that
/// need the extended block must fetch the detail route; nothing may infer an
/// empty `fuelType` from a list row.
class Vehicle {
  final String id;
  final String? plate;
  final String? vin;
  final String? make;
  final String? model;
  final int? year;
  final int? mileage;
  final String? fuelType;

  /// Normalised server-side by `normalizeWheelPosition` to exactly `"Зүүн"` or
  /// `"Баруун"` (or `null`). Kept as a raw string rather than an enum: the
  /// backend validates it as a string pair, and an unexpected value must
  /// survive a round-trip rather than silently become a default.
  final String? wheelPosition;
  final String? colorName;

  /// Engine displacement in cm³ (HUR `capacity`).
  final int? capacity;
  final String? purpose;
  final String? ownerRegnum;

  /// The link's **actual** owner id. See the module doc comment: a create or
  /// update may return an owner different from the one requested.
  final String? customerId;
  final VehicleCustomerRef? customer;

  /// `TenantVehicle.isPostpaid`. Absent from the list and create responses,
  /// where it degrades to `false`.
  final bool isPostpaid;

  /// Phase 4: derived server-side (owning customer is an organization, or an
  /// unowned link whose `ownerRegnum` is a 7-digit org regnum). Degrades to
  /// `false` when absent.
  final bool ownerIsOrganization;

  const Vehicle({
    required this.id,
    this.plate,
    this.vin,
    this.make,
    this.model,
    this.year,
    this.mileage,
    this.fuelType,
    this.wheelPosition,
    this.colorName,
    this.capacity,
    this.purpose,
    this.ownerRegnum,
    this.customerId,
    this.customer,
    this.isPostpaid = false,
    this.ownerIsOrganization = false,
  });

  factory Vehicle.fromJson(Map<String, dynamic> j) {
    final customer = _optMap(j['customer']);
    return Vehicle(
      id: _reqString(j, 'id'),
      plate: _optString(j['plate']),
      vin: _optString(j['vin']),
      make: _optString(j['make']),
      model: _optString(j['model']),
      year: _optInt(j['year']),
      mileage: _optInt(j['mileage']),
      fuelType: _optString(j['fuelType']),
      wheelPosition: _optString(j['wheelPosition']),
      colorName: _optString(j['colorName']),
      capacity: _optInt(j['capacity']),
      purpose: _optString(j['purpose']),
      ownerRegnum: _optString(j['ownerRegnum']),
      customerId: _optString(j['customerId']),
      customer: customer == null ? null : VehicleCustomerRef.fromJson(customer),
      isPostpaid: j['isPostpaid'] == true,
      ownerIsOrganization: j['ownerIsOrganization'] == true,
    );
  }

  /// `"Toyota Prius"`, or an empty string when neither is present. Never falls
  /// back to the plate — a plate is no longer unique, so a caller that wants
  /// to identify a row must show both explicitly.
  String get displayName =>
      [make, model].where((v) => v != null && v.isNotEmpty).join(' ').trim();

  /// Whether this tenant's link has an owner. `false` covers both an
  /// unassigned link and a response that did not carry the field.
  bool get hasOwner => customerId != null;
}

/// `DELETE /api/v1/vehicles/[id]` — `{vehicle: {id, plate, make, model}}`.
///
/// Only the tenant's `TenantVehicle` link is removed; the global `Vehicle`
/// row and other tenants' links survive. `plate`/`make`/`model` come from a
/// pre-delete lookup and are all nullable: the command tolerates the global
/// row already being gone.
class VehicleDeletionResult {
  final String id;
  final String? plate;
  final String? make;
  final String? model;

  const VehicleDeletionResult({
    required this.id,
    this.plate,
    this.make,
    this.model,
  });

  factory VehicleDeletionResult.fromJson(Map<String, dynamic> j) =>
      VehicleDeletionResult(
        id: _reqString(j, 'id'),
        plate: _optString(j['plate']),
        make: _optString(j['make']),
        model: _optString(j['model']),
      );
}

// ─── History ───────────────────────────────────────────────────────────────

/// One `ServiceOrder` row of a vehicle's history.
///
/// `status` and `paymentStatus` stay raw strings rather than borrowing the
/// Orders feature's `OrderStatus`/`PaymentStatus` enums, whose `fromString`
/// throws an `OrderParseException` on an unknown value — that would make a
/// single future status value crash the whole history screen, which is
/// exactly what this slice's tolerance rule forbids. `totalAmount` is a raw
/// decimal string (Prisma `Decimal.toString()`), never a double: rounding a
/// money value in the client is a defect, not a convenience.
class VehicleHistoryOrder {
  final String id;
  final String? number;
  final String? status;
  final String? paymentStatus;
  final DateTime? scheduledAt;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final String? totalAmount;
  final String? branchName;
  final int itemCount;

  const VehicleHistoryOrder({
    required this.id,
    this.number,
    this.status,
    this.paymentStatus,
    this.scheduledAt,
    this.completedAt,
    this.createdAt,
    this.totalAmount,
    this.branchName,
    this.itemCount = 0,
  });

  factory VehicleHistoryOrder.fromJson(Map<String, dynamic> j) =>
      VehicleHistoryOrder(
        id: _reqString(j, 'id'),
        number: _optString(j['number']),
        status: _optString(j['status']),
        paymentStatus: _optString(j['paymentStatus']),
        scheduledAt: _optDate(j['scheduledAt']),
        completedAt: _optDate(j['completedAt']),
        createdAt: _optDate(j['createdAt']),
        totalAmount: _optString(j['totalAmount']),
        branchName: _optString(_optMap(j['branch'])?['name']),
        itemCount: _optInt(j['itemCount']) ?? 0,
      );
}

/// One `Appointment` row of a vehicle's history.
class VehicleHistoryAppointment {
  final String id;
  final String? status;
  final DateTime? requestedAt;
  final String? note;
  final String? branchName;
  final String? categoryName;

  const VehicleHistoryAppointment({
    required this.id,
    this.status,
    this.requestedAt,
    this.note,
    this.branchName,
    this.categoryName,
  });

  factory VehicleHistoryAppointment.fromJson(Map<String, dynamic> j) =>
      VehicleHistoryAppointment(
        id: _reqString(j, 'id'),
        status: _optString(j['status']),
        requestedAt: _optDate(j['requestedAt']),
        note: _optString(j['note']),
        branchName: _optString(_optMap(j['branch'])?['name']),
        categoryName: _optString(_optMap(j['category'])?['name']),
      );
}

/// `GET /api/v1/vehicles/[id]/history` — unbounded and unpaginated by design
/// (one vehicle's own history), unlike customer order history.
///
/// [ownerLocked] is computed **server-side** by `isOwnerLocked` and must be
/// taken at face value: it is `true` when the vehicle has any order or any
/// diagnostic report for this tenant, and it is what blocks an owner change
/// (`VEHICLE_OWNER_CHANGE_BLOCKED`, 422). It is deliberately not re-derived
/// from [orders]/[diagnosticReportCount] here — a client re-derivation would
/// silently diverge the moment the server rule changes.
class VehicleHistory {
  final List<VehicleHistoryOrder> orders;
  final List<VehicleHistoryAppointment> appointments;
  final int diagnosticReportCount;
  final bool ownerLocked;

  const VehicleHistory({
    this.orders = const [],
    this.appointments = const [],
    this.diagnosticReportCount = 0,
    this.ownerLocked = false,
  });
}

// ─── HUR refresh ───────────────────────────────────────────────────────────

/// `POST /api/v1/vehicles/[id]/refresh-hur` — `{vehicle: {...}}`.
///
/// Carries **no `id`**: the payload is the refreshed attribute set of the
/// global `Vehicle` row, not a full vehicle. `serviceCount`/`diagnosisCount`
/// exist on the underlying helper but are stripped by the staff route because
/// they are counted unscoped across every tenant sharing the registration —
/// do not model them, and do not "restore" them by analogy with the customer
/// app's route.
///
/// `plate` is never refreshed: this is "update the record", not "change the
/// plate". An upstream HUR failure comes back as a 502 and is an expected
/// outcome — the helper writes nothing in that branch, so the stored fields
/// are untouched.
class VehicleHurRefresh {
  final String? plate;
  final String? make;
  final String? model;
  final int? year;
  final String? vin;
  final String? fuelType;
  final String? wheelPosition;
  final String? colorName;
  final int? capacity;
  final String? purpose;

  const VehicleHurRefresh({
    this.plate,
    this.make,
    this.model,
    this.year,
    this.vin,
    this.fuelType,
    this.wheelPosition,
    this.colorName,
    this.capacity,
    this.purpose,
  });

  factory VehicleHurRefresh.fromJson(Map<String, dynamic> j) =>
      VehicleHurRefresh(
        plate: _optString(j['plate']),
        make: _optString(j['make']),
        model: _optString(j['model']),
        year: _optInt(j['year']),
        vin: _optString(j['vin']),
        fuelType: _optString(j['fuelType']),
        wheelPosition: _optString(j['wheelPosition']),
        colorName: _optString(j['colorName']),
        capacity: _optInt(j['capacity']),
        purpose: _optString(j['purpose']),
      );

  /// Applies the refreshed attributes onto [base], keeping every field the
  /// refresh does not speak about (`id`, `mileage`, `ownerRegnum`,
  /// `customerId`, `customer`, `isPostpaid`) and every field the refresh
  /// returned as `null` — HUR omitting a value means "no new information",
  /// never "clear it" (`refreshVehicleFieldsFromHur` maps each `null` to
  /// Prisma `undefined` for exactly that reason). This is why a refresh can
  /// never silently discard user-entered data.
  Vehicle applyTo(Vehicle base) => Vehicle(
    id: base.id,
    plate: base.plate,
    vin: vin ?? base.vin,
    make: make ?? base.make,
    model: model ?? base.model,
    year: year ?? base.year,
    mileage: base.mileage,
    fuelType: fuelType ?? base.fuelType,
    wheelPosition: wheelPosition ?? base.wheelPosition,
    colorName: colorName ?? base.colorName,
    capacity: capacity ?? base.capacity,
    purpose: purpose ?? base.purpose,
    ownerRegnum: base.ownerRegnum,
    customerId: base.customerId,
    customer: base.customer,
    isPostpaid: base.isPostpaid,
    ownerIsOrganization: base.ownerIsOrganization,
  );
}

// ─── Parse helpers ─────────────────────────────────────────────────────────

String _reqString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw VehicleParseException('$key талбар буруу байна.');
  }
  return value.trim();
}

String? _optString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Accepts a JSON number and a numeric string (a `year`/`mileage` typed as a
/// string by a proxy is still usable), but never truncates a fractional value
/// into a silently-wrong integer.
int? _optInt(Object? value) {
  if (value is int) return value;
  if (value is double) {
    return value == value.roundToDouble() ? value.toInt() : null;
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

DateTime? _optDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toLocal();
}

Map<String, dynamic>? _optMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

// ─── VIN history ───────────────────────────────────────────────────────────

/// One same-VIN vehicle linked to this tenant (`GET /vehicles/[id]/vin-history`).
class VinHistoryRecord {
  final String vehicleId;
  final String plate;
  final String? make;
  final String? model;
  final int? year;
  final String? ownerName;
  final int orderCount;
  final DateTime? lastOrderAt;
  final DateTime? createdAt;

  const VinHistoryRecord({
    required this.vehicleId,
    required this.plate,
    this.make,
    this.model,
    this.year,
    this.ownerName,
    this.orderCount = 0,
    this.lastOrderAt,
    this.createdAt,
  });
}

/// `{vin, records, otherTenantRecords}`. [hasContent] drives whether the
/// vehicle screen shows the section at all.
class VinHistory {
  final String? vin;
  final List<VinHistoryRecord> records;
  final int otherTenantRecords;

  const VinHistory({
    this.vin,
    this.records = const [],
    this.otherTenantRecords = 0,
  });

  bool get hasContent =>
      vin != null && (records.isNotEmpty || otherTenantRecords > 0);
}
