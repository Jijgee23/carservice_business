/// Appointments domain model — P2-F1.
///
/// Mirrors the `carservice.mn` backend contract in
/// `lib/appointments/appointment-commands.ts`,
/// `lib/appointments/calendar-day-model.ts`,
/// `lib/appointments/appointment-create-request.ts`,
/// `lib/appointments/appointment-bulk-commands.ts` and the routes under
/// `app/api/v1/appointments/`. Follows the Phase 1 Orders idiom
/// (`lib/features/orders/domain/order.dart`): `Money`-style raw values are
/// not needed here (no decimal amounts in the appointment payload itself —
/// payment amounts from `/payment/refund` are surfaced as raw decimal
/// strings, see [AppointmentRefundResult]).
///
/// Defensive parsing: an unknown status/reason, a null finish, a missing
/// linked order, or an unexpected enum value degrades to a typed value
/// (`AppointmentStatus.unknown`, `null`, etc.) — a DTO never throws a parse
/// crash for a field the backend may reasonably omit or extend. Only
/// structurally-required identifiers (id) throw
/// [AppointmentParseException], exactly like `OrderParseException` in the
/// Orders precedent.
library;

import 'package:carservice_business/core/utils/business_time.dart';

/// Typed failure for a structurally malformed Appointments payload — thrown
/// only when a field the contract calls unconditionally required (an `id`)
/// is missing or the wrong type. Everything else degrades; see the module
/// doc comment.
class AppointmentParseException implements Exception {
  const AppointmentParseException(this.message);

  final String message;

  @override
  String toString() => 'AppointmentParseException: $message';
}

// ─── Status ────────────────────────────────────────────────────────────────

/// Mirrors `APPOINTMENT_STATUSES` / `APPOINTMENT_STATUS_TRANSITIONS` in
/// `carservice.mn/lib/appointments.ts`. [unknown] is the defensive fallback for
/// any value the backend adds later that this build does not know about yet
/// — it is deliberately excluded from [nextStatuses] so a stale client can
/// never offer a transition it cannot interpret.
enum AppointmentStatus {
  PENDING,
  CONFIRMED,
  REJECTED,
  CANCELLED,
  NO_SHOW,
  unknown;

  static AppointmentStatus fromJson(Object? value) {
    if (value is! String) return unknown;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return unknown;
  }

  String get label => switch (this) {
    PENDING => 'Хүлээгдэж буй',
    CONFIRMED => 'Баталгаажсан',
    REJECTED => 'Татгалзсан',
    CANCELLED => 'Цуцлагдсан',
    NO_SHOW => 'Ирээгүй',
    unknown => 'Тодорхойгүй',
  };

  /// Matches `APPOINTMENT_STATUS_TRANSITIONS` exactly — the same matrix
  /// `PATCH /appointments/[id]` and the named lifecycle routes enforce
  /// server-side. Never used for client-side authorization; the repository
  /// still sends the request and the server is the final authority.
  List<AppointmentStatus> get nextStatuses => switch (this) {
    PENDING => const [CONFIRMED, REJECTED],
    CONFIRMED => const [NO_SHOW, CANCELLED],
    _ => const [],
  };

  bool get isTerminal =>
      this == REJECTED || this == CANCELLED || this == NO_SHOW;
}

/// Mirrors `AppointmentBookingPaymentStatus` in
/// `carservice.mn/lib/appointment-payment-status.ts`.
enum AppointmentBookingPaymentStatus {
  NOT_REQUIRED,
  PENDING,
  UNDERPAID,
  FAILED,
  PAID,
  unknown;

  static AppointmentBookingPaymentStatus fromJson(Object? value) {
    if (value is! String) return unknown;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return unknown;
  }

  String get label => switch (this) {
    NOT_REQUIRED => 'Төлбөр шаардлагагүй',
    PENDING => 'Төлбөр хүлээгдэж байна',
    UNDERPAID => 'Дутуу төлсөн',
    FAILED => 'Төлбөрийн invoice алдаатай',
    PAID => 'Төлбөр төлөгдсөн',
    unknown => 'Тодорхойгүй',
  };
}

/// Mirrors `ScheduleIssue["reason"]` (`SCHEDULE_ISSUE_LABEL`) in
/// `carservice.mn/lib/appointments/calendar-day-model.ts`.
enum CalendarIssueReason {
  missingEstimate,
  unknownOccupancy,
  missingOrder,
  linkedOrderNotOccupying,
  missingStart,
  invalidInterval,
  paymentExpired,
  unknown;

  static const _wire = {
    'missing-estimate': missingEstimate,
    'unknown-occupancy': unknownOccupancy,
    'missing-order': missingOrder,
    'linked-order-not-occupying': linkedOrderNotOccupying,
    'missing-start': missingStart,
    'invalid-interval': invalidInterval,
    'payment-expired': paymentExpired,
  };

  static CalendarIssueReason fromJson(Object? value) {
    if (value is! String) return unknown;
    return _wire[value] ?? unknown;
  }
}

// ─── Ref types ────────────────────────────────────────────────────────────

class AppointmentBranchRef {
  final String id;
  final String? name;

  const AppointmentBranchRef({required this.id, this.name});

  factory AppointmentBranchRef.fromJson(Map<String, dynamic> j) =>
      AppointmentBranchRef(
        id: _reqString(j, 'id'),
        name: _optString(j['name']),
      );
}

class AppointmentAccountRef {
  final String? name;
  final String? phone;

  const AppointmentAccountRef({this.name, this.phone});

  factory AppointmentAccountRef.fromJson(Map<String, dynamic> j) =>
      AppointmentAccountRef(
        name: _optString(j['name']),
        phone: _optString(j['phone']),
      );

  String get displayName =>
      (name?.isNotEmpty ?? false) ? name! : (phone ?? 'Нэргүй');
}

/// `assignedTo` — `{id, name}` of the master the appointment is assigned to.
class AppointmentAssigneeRef {
  final String id;
  final String? name;

  const AppointmentAssigneeRef({required this.id, this.name});

  factory AppointmentAssigneeRef.fromJson(Map<String, dynamic> j) =>
      AppointmentAssigneeRef(
        id: _optString(j['id']) ?? '',
        name: _optString(j['name']),
      );
}

class AppointmentCustomerRef {
  final String? id;
  final String? fullName;
  final String? phone;

  const AppointmentCustomerRef({this.id, this.fullName, this.phone});

  factory AppointmentCustomerRef.fromJson(Map<String, dynamic> j) =>
      AppointmentCustomerRef(
        id: _optString(j['id']),
        fullName: _optString(j['fullName']),
        phone: _optString(j['phone']),
      );
}

/// Covers both `accountVehicle` (server-shaped to `{plate, make, model}` —
/// no `id`, see `shapeAppointment` in the route) and `vehicle` (carries
/// `id`). A malformed sub-field degrades to null rather than discarding the
/// whole ref.
class AppointmentVehicleRef {
  final String? id;
  final String? plate;
  final String? make;
  final String? model;

  const AppointmentVehicleRef({this.id, this.plate, this.make, this.model});

  factory AppointmentVehicleRef.fromJson(Map<String, dynamic> j) =>
      AppointmentVehicleRef(
        id: _optString(j['id']),
        plate: _optString(j['plate']),
        make: _optString(j['make']),
        model: _optString(j['model']),
      );

  String get displayName =>
      [make, model].where((v) => v != null && v.isNotEmpty).join(' ').trim();
}

class AppointmentCategoryRef {
  final String id;
  final String? name;

  const AppointmentCategoryRef({required this.id, this.name});

  factory AppointmentCategoryRef.fromJson(Map<String, dynamic> j) =>
      AppointmentCategoryRef(
        id: _reqString(j, 'id'),
        name: _optString(j['name']),
      );
}

class AppointmentOrderRef {
  final String id;
  final int? number;

  const AppointmentOrderRef({required this.id, this.number});

  factory AppointmentOrderRef.fromJson(Map<String, dynamic> j) =>
      AppointmentOrderRef(
        id: _reqString(j, 'id'),
        number: j['number'] is int ? j['number'] as int : null,
      );
}

// ─── AppointmentSummary ─────────────────────────────────────────────────────

/// One appointment as returned by `GET/POST /api/v1/appointments` and
/// `PATCH /api/v1/appointments/[id]` (both wrap the same
/// `shapeAppointment(APPT_SELECT)` row).
class AppointmentSummary {
  final String id;
  final AppointmentStatus status;
  final DateTime? requestedAt;
  final String? note;
  final DateTime? createdAt;
  final AppointmentBranchRef? branch;
  final AppointmentCategoryRef? category;
  final AppointmentAccountRef? account;
  final AppointmentCustomerRef? customer;
  final AppointmentVehicleRef? accountVehicle;
  final AppointmentVehicleRef? vehicle;
  final AppointmentOrderRef? serviceOrder;

  /// Захиалгын хураамжийн төлөв (веб dashboard-ийн `appointmentBookingPaymentStatus`).
  /// `null` = хуучин сервер талбарыг илгээгээгүй — мэдэгдэхгүй гэж үзнэ.
  final AppointmentBookingPaymentStatus? paymentStatus;

  /// Staff-marked arrival time. `null` = not arrived (or an older server).
  final DateTime? arrivedAt;

  /// Хариуцах мастер. `null` = мастер оноогоогүй (эсвэл хуучин сервер талбарыг
  /// илгээгээгүй). Сервер мастерыг заавал шаарддаг тул шинэ цагт ихэвчлэн
  /// байна; хуучин цагт `null` байж болно.
  final String? assignedToId;
  final AppointmentAssigneeRef? assignedTo;

  const AppointmentSummary({
    required this.id,
    required this.status,
    this.requestedAt,
    this.note,
    this.createdAt,
    this.branch,
    this.category,
    this.account,
    this.customer,
    this.accountVehicle,
    this.vehicle,
    this.serviceOrder,
    this.paymentStatus,
    this.arrivedAt,
    this.assignedToId,
    this.assignedTo,
  });

  factory AppointmentSummary.fromJson(Map<String, dynamic> j) {
    return AppointmentSummary(
      id: _reqString(j, 'id'),
      status: AppointmentStatus.fromJson(j['status']),
      requestedAt: _optDate(j['requestedAt']),
      note: _optString(j['note']),
      createdAt: _optDate(j['createdAt']),
      branch: _optMap(j['branch']) != null
          ? AppointmentBranchRef.fromJson(_optMap(j['branch'])!)
          : null,
      category: _optMap(j['category']) != null
          ? AppointmentCategoryRef.fromJson(_optMap(j['category'])!)
          : null,
      account: _optMap(j['account']) != null
          ? AppointmentAccountRef.fromJson(_optMap(j['account'])!)
          : null,
      customer: _optMap(j['customer']) != null
          ? AppointmentCustomerRef.fromJson(_optMap(j['customer'])!)
          : null,
      accountVehicle: _optMap(j['accountVehicle']) != null
          ? AppointmentVehicleRef.fromJson(_optMap(j['accountVehicle'])!)
          : null,
      vehicle: _optMap(j['vehicle']) != null
          ? AppointmentVehicleRef.fromJson(_optMap(j['vehicle'])!)
          : null,
      serviceOrder: _optMap(j['serviceOrder']) != null
          ? AppointmentOrderRef.fromJson(_optMap(j['serviceOrder'])!)
          : null,
      paymentStatus: j['paymentStatus'] == null
          ? null
          : AppointmentBookingPaymentStatus.fromJson(j['paymentStatus']),
      arrivedAt: _optDate(j['arrivedAt']),
      assignedToId: _optString(j['assignedToId']),
      assignedTo: _optMap(j['assignedTo']) != null
          ? AppointmentAssigneeRef.fromJson(_optMap(j['assignedTo'])!)
          : null,
    );
  }

  /// Мастерын харуулах нэр (нэр байхгүй бол `null`).
  String? get assigneeName {
    final name = assignedTo?.name;
    return (name == null || name.trim().isEmpty) ? null : name.trim();
  }

  /// PENDING and the start time (`requestedAt`, same field the server checks)
  /// has passed: the server refuses to confirm (`APPOINTMENT_OVERDUE`); reject
  /// is still allowed.
  bool get isOverdue {
    final at = requestedAt;
    return status == AppointmentStatus.PENDING &&
        at != null &&
        at.isBefore(businessNow());
  }

  /// Харуулах нэр: resolve хийгдсэн Customer → Account → fallback.
  String get displayName =>
      customer?.fullName ?? account?.displayName ?? 'Нэргүй';

  String get displayPhone => customer?.phone ?? account?.phone ?? '—';

  /// Харуулах машин: snapshot хийгдсэн Vehicle → consumer AccountVehicle.
  AppointmentVehicleRef? get displayVehicle => vehicle ?? accountVehicle;
}

// ─── Slots ───────────────────────────────────────────────────────────────

/// One row of `GET /appointments/slots`'s `slots[]` (`DaySlot` in
/// `carservice.mn/lib/appointment-slots.ts`).
class AppointmentSlot {
  final String time;
  final String iso;
  final bool available;
  final int remaining;

  const AppointmentSlot({
    required this.time,
    required this.iso,
    required this.available,
    required this.remaining,
  });

  factory AppointmentSlot.fromJson(Map<String, dynamic> j) => AppointmentSlot(
    time: _optString(j['time']) ?? '',
    iso: _optString(j['iso']) ?? '',
    available: j['available'] == true,
    remaining: j['remaining'] is int ? j['remaining'] as int : 0,
  );
}

/// Full response of `GET /appointments/slots`.
class AppointmentDayAvailability {
  final bool open;
  final String? reason;
  final List<AppointmentSlot> slots;
  final String? scheduleSource;
  final String? scheduleLabel;
  final int? durationMinutes;

  const AppointmentDayAvailability({
    required this.open,
    this.reason,
    required this.slots,
    this.scheduleSource,
    this.scheduleLabel,
    this.durationMinutes,
  });

  factory AppointmentDayAvailability.fromJson(Map<String, dynamic> j) {
    final rawSlots = j['slots'];
    return AppointmentDayAvailability(
      open: j['open'] == true,
      reason: _optString(j['reason']),
      slots: rawSlots is List
          ? rawSlots
                .whereType<Map>()
                .map(
                  (e) => AppointmentSlot.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const [],
      scheduleSource: _optString(j['scheduleSource']),
      scheduleLabel: _optString(j['scheduleLabel']),
      durationMinutes: j['durationMinutes'] is int
          ? j['durationMinutes'] as int
          : null,
    );
  }
}

// ─── Calendar day model ────────────────────────────────────────────────────

/// Mirrors `CalendarBlockIssue` in `calendar-day-model.ts`.
class CalendarBlockIssue {
  final CalendarIssueReason reason;
  final String label;

  const CalendarBlockIssue({required this.reason, required this.label});

  factory CalendarBlockIssue.fromJson(Map<String, dynamic> j) =>
      CalendarBlockIssue(
        reason: CalendarIssueReason.fromJson(j['reason']),
        label: _optString(j['label']) ?? '',
      );
}

/// Mirrors `CalendarBlock` — one rendered block of the day grid. Every field
/// the server marks as semantically load-bearing (`finishKnown`,
/// `endsAtDayBoundary`, `capacityOverflow`) survives a defensive parse as a
/// safe default (`false`) rather than throwing, so one malformed block never
/// takes down the whole day's render.
class CalendarBlock {
  final String key;
  final String appointmentId;
  final int laneIndex;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool finishKnown;
  final bool endsAtDayBoundary;
  final AppointmentStatus? status;
  final String statusLabel;
  final String name;
  final AppointmentBookingPaymentStatus? paymentStatus;
  final String? paymentStatusLabel;
  final CalendarBlockIssue? issue;
  final bool capacityOverflow;
  final String accessibleLabel;

  const CalendarBlock({
    required this.key,
    required this.appointmentId,
    required this.laneIndex,
    this.startAt,
    this.endAt,
    required this.finishKnown,
    required this.endsAtDayBoundary,
    this.status,
    required this.statusLabel,
    required this.name,
    this.paymentStatus,
    this.paymentStatusLabel,
    this.issue,
    required this.capacityOverflow,
    required this.accessibleLabel,
  });

  factory CalendarBlock.fromJson(Map<String, dynamic> j) => CalendarBlock(
    key: _optString(j['key']) ?? '',
    appointmentId: _optString(j['appointmentId']) ?? '',
    laneIndex: j['laneIndex'] is int ? j['laneIndex'] as int : 0,
    startAt: _optDate(j['startAt']),
    endAt: _optDate(j['endAt']),
    finishKnown: j['finishKnown'] == true,
    endsAtDayBoundary: j['endsAtDayBoundary'] == true,
    status: j['status'] == null
        ? null
        : AppointmentStatus.fromJson(j['status']),
    statusLabel: _optString(j['statusLabel']) ?? '',
    name: _optString(j['name']) ?? '—',
    paymentStatus: j['paymentStatus'] == null
        ? null
        : AppointmentBookingPaymentStatus.fromJson(j['paymentStatus']),
    paymentStatusLabel: _optString(j['paymentStatusLabel']),
    issue: _optMap(j['issue']) != null
        ? CalendarBlockIssue.fromJson(_optMap(j['issue'])!)
        : null,
    capacityOverflow: j['capacityOverflow'] == true,
    accessibleLabel: _optString(j['accessibleLabel']) ?? '',
  );
}

sealed class CalendarLegendEntry {
  const CalendarLegendEntry();
}

class CalendarLegendStatus extends CalendarLegendEntry {
  final AppointmentStatus status;
  final String label;
  const CalendarLegendStatus({required this.status, required this.label});
}

class CalendarLegendIssue extends CalendarLegendEntry {
  final CalendarIssueReason reason;
  final String label;
  const CalendarLegendIssue({required this.reason, required this.label});
}

/// Full response of `GET /appointments/calendar` (`CalendarDayModel`).
class CalendarDayModel {
  final String branchId;
  final String? branchName;
  final String dateKey;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final int slotCapacity;
  final int laneCount;
  final bool hasCapacityOverflow;
  final List<CalendarBlock> blocks;
  final List<CalendarLegendEntry> legend;

  const CalendarDayModel({
    required this.branchId,
    this.branchName,
    required this.dateKey,
    this.rangeStart,
    this.rangeEnd,
    required this.slotCapacity,
    required this.laneCount,
    required this.hasCapacityOverflow,
    required this.blocks,
    required this.legend,
  });

  factory CalendarDayModel.fromJson(Map<String, dynamic> j) {
    final rawBlocks = j['blocks'];
    final rawLegend = j['legend'];
    return CalendarDayModel(
      branchId: _optString(j['branchId']) ?? '',
      branchName: _optString(j['branchName']),
      dateKey: _optString(j['dateKey']) ?? '',
      rangeStart: _optDate(j['rangeStart']),
      rangeEnd: _optDate(j['rangeEnd']),
      slotCapacity: j['slotCapacity'] is int ? j['slotCapacity'] as int : 1,
      laneCount: j['laneCount'] is int ? j['laneCount'] as int : 1,
      hasCapacityOverflow: j['hasCapacityOverflow'] == true,
      blocks: rawBlocks is List
          ? rawBlocks
                .whereType<Map>()
                .map(
                  (e) => CalendarBlock.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const [],
      legend: rawLegend is List
          ? rawLegend
                .whereType<Map>()
                .map<CalendarLegendEntry?>((raw) {
                  final e = Map<String, dynamic>.from(raw);
                  final label = _optString(e['label']) ?? '';
                  return switch (e['kind']) {
                    'status' => CalendarLegendStatus(
                      status: AppointmentStatus.fromJson(e['status']),
                      label: label,
                    ),
                    'issue' => CalendarLegendIssue(
                      reason: CalendarIssueReason.fromJson(e['reason']),
                      label: label,
                    ),
                    _ => null,
                  };
                })
                .whereType<CalendarLegendEntry>()
                .toList(growable: false)
          : const [],
    );
  }
}

// ─── Lifecycle / mutation results ──────────────────────────────────────────

/// Result of confirm/reject/no-show/arrived — the four named lifecycle
/// POST endpoints, each a thin adapter over one P2-B1 command. `status` is
/// only populated for confirm/reject/no-show (each route echoes a fixed
/// literal, not read back from the DB); `arrived` is only populated for the
/// arrived transition.
class AppointmentLifecycleResult {
  final String appointmentId;
  final AppointmentStatus? status;
  final bool? arrived;

  const AppointmentLifecycleResult({
    required this.appointmentId,
    this.status,
    this.arrived,
  });
}

/// Result of `POST /appointments/[id]/reschedule`.
class AppointmentRescheduleResult {
  final String appointmentId;
  final String? orderId;
  final bool linked;
  final DateTime requestedAt;

  const AppointmentRescheduleResult({
    required this.appointmentId,
    this.orderId,
    required this.linked,
    required this.requestedAt,
  });
}

/// One row of the bulk-category `{failed:[...]}` array.
class AppointmentBulkFailure {
  final String appointmentId;
  final String code;
  final String message;

  const AppointmentBulkFailure({
    required this.appointmentId,
    required this.code,
    required this.message,
  });
}

/// Result of `POST /appointments/bulk/category` — partial success, mirrors
/// `BulkOrderResult` in the Orders contract.
class AppointmentBulkResult {
  final List<String> succeeded;
  final List<AppointmentBulkFailure> failed;

  const AppointmentBulkResult({required this.succeeded, required this.failed});
}

/// Result of `POST /appointments/[id]/payment` (check/confirm).
class AppointmentPaymentCheckResult {
  final bool ok;
  final bool paid;
  final String? message;
  final double? underpaidAmount;

  const AppointmentPaymentCheckResult({
    required this.ok,
    required this.paid,
    this.message,
    this.underpaidAmount,
  });
}

/// Result of `POST /appointments/[id]/payment/retry`.
class AppointmentPaymentRetryResult {
  final bool ok;
  final bool required;

  const AppointmentPaymentRetryResult({
    required this.ok,
    required this.required,
  });
}

/// Result of `POST /appointments/[id]/payment/refund`.
class AppointmentRefundResult {
  final String paymentId;
  final String refundedVia;
  final String amount;
  final String currency;

  const AppointmentRefundResult({
    required this.paymentId,
    required this.refundedVia,
    required this.amount,
    required this.currency,
  });
}

// ─── Helpers ────────────────────────────────────────────────────────────────

String _reqString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw AppointmentParseException('$key талбар буруу байна.');
  }
  return value.trim();
}

String? _optString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Server instants shown as Ulaanbaatar wall-clock time, whatever the
/// device zone — see `business_time.dart`.
DateTime? _optDate(Object? value) => parseBusinessTime(value);

Map<String, dynamic>? _optMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}
