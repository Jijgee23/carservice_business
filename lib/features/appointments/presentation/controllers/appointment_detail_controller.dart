import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/data/appointment_repository.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';
import 'package:carservice_business/features/orders/data/order_repository.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';

/// Owns one appointment's detail request and its server-authoritative
/// lifecycle/payment mutations — P2-F5.
///
/// **Known trap, do not repeat** (see `TENANT_MOBILE_SLICES.md`, P2-F5): the
/// Orders detail controller once discarded a successful mutation response and
/// issued a second `refresh()`, so a failed follow-up GET/DTO parse
/// overwrote the page with `AsyncError` while the write stayed committed —
/// the user saw an error page after a successful action. Every mutation
/// below applies its own response directly to [detailState] first; a
/// subsequent [refresh] failure only ever sets [refreshError] (a
/// non-destructive banner the screen renders on top of the already-updated
/// state) and never replaces good data with an error state.
///
/// The frozen [AppointmentsRepository] contract (P2-F1, do not modify) has
/// no single-appointment GET — only `getAppointments` (paged, day-scoped).
/// [refresh] is therefore best-effort: it re-fetches the day/branch page the
/// current appointment belongs to and looks the id up in it. When the
/// appointment is not found on that page (moved day/branch, or a fetch
/// error) the last-known state is kept and [refreshError] is set instead of
/// discarding it — this class never has a hard dependency on that lookup
/// succeeding.
class AppointmentDetailController extends ChangeNotifier {
  AppointmentDetailController({
    required AppointmentSummary initial,
    AppointmentsRepository? repo,
    OrdersRepository? ordersRepository,
  }) : _repo = repo ?? RemoteAppointmentsRepository(),
       _ordersRepository = ordersRepository ?? RemoteOrdersRepository(),
       detailState = AsyncData(initial),
       arrived = initial.arrivedAt != null ? true : null,
       paymentStatus =
           initial.paymentStatus ?? AppointmentBookingPaymentStatus.unknown;

  final AppointmentsRepository _repo;
  final OrdersRepository _ordersRepository;

  /// For screens that open the create-order form linked to this appointment.
  OrdersRepository get ordersRepository => _ordersRepository;

  AsyncValue<AppointmentSummary> detailState;
  AppError? refreshError;

  /// Whether the last-known appointment has since arrived (staff-marked).
  /// Not part of the frozen [AppointmentSummary] contract — surfaced only by
  /// [AppointmentLifecycleResult.arrived] from the `arrived` route.
  bool? arrived;

  /// Payment section state. Seeded from the server's
  /// [AppointmentSummary.paymentStatus] (web dashboard parity) and refreshed
  /// on [refresh]; a local check/retry/refund then overrides it. An older
  /// server that omits the field leaves it `unknown`, which must be treated
  /// neutrally (no action assumed available).
  AppointmentBookingPaymentStatus paymentStatus;
  AppointmentPaymentCheckResult? lastPaymentCheck;
  AppointmentPaymentRetryResult? lastPaymentRetry;
  AppointmentRefundResult? lastRefund;

  bool mutating = false;

  /// Inline reason a non-assigner's confirm was refused (ASSIGNEE_REQUIRED).
  String? confirmBlockedReason;
  void setConfirmBlockedReason(String? reason) {
    confirmBlockedReason = reason;
    notifyListeners();
  }

  int _generation = 0;
  bool _disposed = false;

  AppointmentSummary? get appointment => detailState.valueOrNull;
  String? get appointmentId => appointment?.id;

  // ─── Refresh (best-effort, never destructive) ───────────────────────────

  Future<void> refresh() async {
    final current = appointment;
    if (current == null || _disposed) return;
    // A reload invalidates the inline confirm-blocked reason; it is re-set
    // only by the next refused confirm. Cleared silently (listeners are
    // notified when the refresh settles, or here if it returns early).
    final hadBlockedReason = confirmBlockedReason != null;
    confirmBlockedReason = null;
    if (hadBlockedReason) notifyListeners();
    final generation = ++_generation;
    final requestedAt = current.requestedAt;
    if (requestedAt == null) {
      // Nothing to scope a day-list refresh by; keep current state silently.
      return;
    }
    final result = await _repo.getAppointments(
      query: AppointmentListQuery(
        branchId: current.branch?.id,
        date: requestedAt,
        pageSize: 200,
      ),
    );
    if (_disposed || generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        AppointmentSummary? match;
        for (final item in value.items) {
          if (item.id == current.id) {
            match = item;
            break;
          }
        }
        if (match != null) {
          detailState = AsyncData(match);
          if (match.arrivedAt != null) arrived = true;
          if (match.paymentStatus != null) paymentStatus = match.paymentStatus!;
          refreshError = null;
        } else {
          // Not on that page any more (moved day/branch, or deleted) — keep
          // the last-known value visible and surface a banner, never an
          // error state, matching the destructive-reload trap this slice
          // must avoid.
          refreshError = const AppError(
            ErrorKind.unknown,
            'Шинэчилсэн мэдээллийг олсонгүй',
          );
        }
      case Err(:final error):
        refreshError = error;
    }
    notifyListeners();
  }

  // ─── Lifecycle mutations ─────────────────────────────────────────────────

  /// [assignee] is the master chosen in the pre-confirm prompt; it is sent as
  /// `{assignedToId}` and applied locally on success. Omit it when the
  /// appointment already has a master (or the user lacks `orders.assign` and
  /// the server assigns the actor).
  Future<Result<AppointmentLifecycleResult>> confirm({
    AssignableUser? assignee,
  }) => _lifecycle(
    (id) => _repo.confirm(id, assignedToId: assignee?.id),
    fallback: AppointmentStatus.CONFIRMED,
    assignee: assignee,
  );

  /// Eligible masters for this appointment's branch (same list as the order
  /// create screen).
  Future<Result<List<AssignableUser>>> loadAssignableUsers() =>
      _ordersRepository.getAssignableUsers(branchId: appointment?.branch?.id);

  /// `PATCH /appointments/[id]` `{assignedToId}`. Takes a non-null user on
  /// purpose - there is no way to clear the master. The chosen master is
  /// applied locally on success (no destructive reload, see class docs).
  Future<Result<AppointmentSummary>> changeAssignee(
    AssignableUser assignee,
  ) async {
    final id = appointmentId;
    final current = appointment;
    if (id == null || current == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Цаг захиалга сонгогдоогүй байна'),
      );
    }
    if (mutating) {
      return const Err(
        AppError(ErrorKind.unknown, 'Өөр үйлдэл боловсруулагдаж байна'),
      );
    }
    final generation = _generation;
    mutating = true;
    notifyListeners();
    final result = await _repo.updateAssignee(id, assignee.id);
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    if (result case Ok()) {
      detailState = AsyncData(_withAssignee(current, assignee));
      confirmBlockedReason = null; // master changed
      refreshError = null;
      notifyListeners();
      unawaited(refresh());
    } else {
      notifyListeners();
    }
    return result;
  }

  Future<Result<AppointmentLifecycleResult>> reject() =>
      _lifecycle(_repo.reject, fallback: AppointmentStatus.REJECTED);

  Future<Result<AppointmentLifecycleResult>> markNoShow() =>
      _lifecycle(_repo.markNoShow, fallback: AppointmentStatus.NO_SHOW);

  Future<Result<AppointmentLifecycleResult>> cancel() =>
      _lifecycle(_repo.cancel, fallback: AppointmentStatus.CANCELLED);

  Future<Result<AppointmentLifecycleResult>> markArrived() async {
    final id = appointmentId;
    if (id == null) return _noAppointmentError();
    final generation = _generation;
    mutating = true;
    notifyListeners();
    final result = await _repo.markArrived(id);
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    if (result case Ok(:final value)) {
      arrived = value.arrived ?? true;
      refreshError = null;
      notifyListeners();
      unawaited(refresh());
    } else {
      notifyListeners();
    }
    return result;
  }

  Future<Result<AppointmentRescheduleResult>> reschedule(
    DateTime requestedAt,
  ) async {
    final id = appointmentId;
    final current = appointment;
    if (id == null || current == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Цаг захиалга сонгогдоогүй байна'),
      );
    }
    final generation = _generation;
    mutating = true;
    notifyListeners();
    // D-111: reschedule never sends `confirmed: true` from this client — the
    // capacity/overlap confirmation step was deliberately removed
    // server-side, only working-hours validation remains, and the client
    // must not simulate its own overlap check or confirm-retry loop.
    final result = await _repo.reschedule(id, requestedAt);
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    if (result case Ok(:final value)) {
      detailState = AsyncData(_withRequestedAt(current, value.requestedAt));
      refreshError = null;
      notifyListeners();
      unawaited(refresh());
    } else {
      notifyListeners();
    }
    return result;
  }

  // ─── Payment ─────────────────────────────────────────────────────────────

  Future<Result<AppointmentPaymentCheckResult>> checkPayment() async {
    final id = appointmentId;
    if (id == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Цаг захиалга сонгогдоогүй байна'),
      );
    }
    final generation = _generation;
    mutating = true;
    notifyListeners();
    final result = await _repo.checkPayment(id);
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    if (result case Ok(:final value)) {
      lastPaymentCheck = value;
      paymentStatus = value.paid
          ? AppointmentBookingPaymentStatus.PAID
          : (value.underpaidAmount != null && value.underpaidAmount! > 0
                ? AppointmentBookingPaymentStatus.UNDERPAID
                : AppointmentBookingPaymentStatus.PENDING);
    }
    notifyListeners();
    return result;
  }

  Future<Result<AppointmentPaymentRetryResult>> retryPayment() async {
    final id = appointmentId;
    if (id == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Цаг захиалга сонгогдоогүй байна'),
      );
    }
    final generation = _generation;
    mutating = true;
    notifyListeners();
    final result = await _repo.retryPayment(id);
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    if (result case Ok(:final value)) {
      lastPaymentRetry = value;
      paymentStatus = value.required
          ? AppointmentBookingPaymentStatus.PENDING
          : AppointmentBookingPaymentStatus.NOT_REQUIRED;
    }
    notifyListeners();
    return result;
  }

  /// Destructive — the screen must confirm with the user before calling
  /// this, and [note] is mandatory (the server 422s `REFUND_NOTE_REQUIRED`
  /// otherwise; this method never invents a placeholder note to dodge that).
  Future<Result<AppointmentRefundResult>> refundPayment({
    required String note,
  }) async {
    final id = appointmentId;
    if (id == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Цаг захиалга сонгогдоогүй байна'),
      );
    }
    if (mutating) {
      return const Err(
        AppError(ErrorKind.unknown, 'Өөр үйлдэл боловсруулагдаж байна'),
      );
    }
    final generation = _generation;
    mutating = true;
    notifyListeners();
    final result = await _repo.refundPayment(id, note: note);
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    if (result case Ok(:final value)) {
      lastRefund = value;
      // Server now reports REFUNDED explicitly (appointmentBookingPaymentStatus).
      paymentStatus = AppointmentBookingPaymentStatus.REFUNDED;
    }
    notifyListeners();
    return result;
  }

  /// Creates the appointment's order through the Phase 1 Orders repository.
  ///
  /// The appointment is the server-side source of duration when
  /// [appointmentId] is present, so this flow deliberately does not send
  /// `estimatedDurationMinutes` and has no appointment-specific order path.
  /// The local appointment link is applied only after the repository confirms
  /// creation; a failed request therefore leaves the appointment untouched.
  Future<Result<ServiceOrderSummary>> convertToOrder() async {
    final current = appointment;
    if (current == null) {
      return const Err(
        AppError(ErrorKind.unknown, 'Цаг захиалга сонгогдоогүй байна'),
      );
    }
    if (current.serviceOrder != null) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Энэ цаг захиалгад захиалга аль хэдийн холбогдсон байна',
          statusCode: 409,
        ),
      );
    }
    final branchId = current.branch?.id;
    final customerId = current.customer?.id;
    final vehicleId = current.vehicle?.id;
    if (branchId == null || customerId == null || vehicleId == null) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Захиалга үүсгэхэд салбар, үйлчлүүлэгч, тээврийн хэрэгслийн мэдээлэл дутуу байна',
        ),
      );
    }
    if (mutating) {
      return const Err(
        AppError(ErrorKind.unknown, 'Өөр үйлдэл боловсруулагдаж байна'),
      );
    }

    final generation = _generation;
    mutating = true;
    notifyListeners();
    final result = await _ordersRepository.createOrder(
      branchId: branchId,
      customerId: customerId,
      vehicleId: vehicleId,
      scheduledAt: current.requestedAt,
      notes: current.note,
      appointmentId: current.id,
    );
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    if (result case Ok(:final value)) {
      detailState = AsyncData(
        _withServiceOrder(
          current,
          AppointmentOrderRef(id: value.id, number: int.tryParse(value.number)),
        ),
      );
      refreshError = null;
    }
    notifyListeners();
    return result;
  }

  // ─── Client-side gating helpers ─────────────────────────────────────────
  //
  // These are UX hints only — hiding/disabling a button is never access
  // control, and a server rejection of an action this class thought legal
  // must always surface verbatim (see the screen's error handling), never be
  // replaced by client copy. `AppointmentStatus.nextStatuses` is the frozen,
  // server-mirrored source for confirm/reject/no-show/cancel. `arrived` and
  // `reschedule` are not status transitions in that matrix (arrived is a
  // separate boolean flag; reschedule keeps the same status) — their
  // preconditions below mirror `assertAppointmentConfirmed` in
  // `carservice.mn/lib/appointments/appointment-commands.ts` (both require
  // CONFIRMED) and are documented here rather than added to the frozen
  // domain file.

  static bool canConfirm(AppointmentStatus status, {bool overdue = false}) =>
      !overdue && status.nextStatuses.contains(AppointmentStatus.CONFIRMED);

  static bool canReject(AppointmentStatus status) =>
      status.nextStatuses.contains(AppointmentStatus.REJECTED);

  static bool canCancel(AppointmentStatus status) =>
      status.nextStatuses.contains(AppointmentStatus.CANCELLED);

  /// Also false once the customer has arrived, matching the web calendar
  /// (`day-rows.tsx`: `status === "CONFIRMED" && !appt.arrivedAt`).
  static bool canMarkNoShow(AppointmentStatus status, [bool? arrived]) =>
      arrived != true &&
      status.nextStatuses.contains(AppointmentStatus.NO_SHOW);

  static bool canMarkArrived(AppointmentStatus status, bool? arrived) =>
      status == AppointmentStatus.CONFIRMED && arrived != true;

  /// The master is required, so a master-less appointment must be given one
  /// before it can be confirmed; only `orders.assign` holders get to choose
  /// (everyone else is auto-assigned by the server).
  static bool needsAssigneeBeforeConfirm(
    AppointmentSummary appointment, {
    required bool canAssign,
  }) => canAssign && appointment.assignedToId == null;

  /// Master can be changed while the appointment is still live.
  static bool canChangeAssignee(AppointmentStatus status) =>
      status == AppointmentStatus.PENDING ||
      status == AppointmentStatus.CONFIRMED;

  static bool canReschedule(AppointmentStatus status) =>
      status == AppointmentStatus.CONFIRMED;

  // ─── Internal ────────────────────────────────────────────────────────────

  Future<Result<AppointmentLifecycleResult>> _lifecycle(
    Future<Result<AppointmentLifecycleResult>> Function(String id) call, {
    required AppointmentStatus fallback,
    AssignableUser? assignee,
  }) async {
    final id = appointmentId;
    final current = appointment;
    if (id == null || current == null) return _noAppointmentError();
    final generation = _generation;
    mutating = true;
    notifyListeners();
    final result = await call(id);
    if (_disposed || generation != _generation) {
      mutating = false;
      return result;
    }
    mutating = false;
    if (result case Ok(:final value)) {
      final next = _withStatus(current, value.status ?? fallback);
      detailState = AsyncData(
        assignee == null ? next : _withAssignee(next, assignee),
      );
      confirmBlockedReason = null; // status/master changed
      refreshError = null;
      notifyListeners();
      unawaited(refresh());
    } else {
      // Illegal-transition / permission rejections stay exactly as the
      // server phrased them (result.error.message) — the caller (screen)
      // surfaces `error.display` unmodified, never client-authored copy.
      notifyListeners();
    }
    return result;
  }

  Result<AppointmentLifecycleResult> _noAppointmentError() =>
      const Err(AppError(ErrorKind.unknown, 'Цаг захиалга сонгогдоогүй байна'));

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

/// [AppointmentSummary] has no `copyWith` — the domain contract is frozen
/// (P2-F1-owned), matching how `appointment_controller.dart` rebuilds it
/// locally rather than adding one there.
AppointmentSummary _withStatus(
  AppointmentSummary appt,
  AppointmentStatus status,
) => AppointmentSummary(
  id: appt.id,
  status: status,
  requestedAt: appt.requestedAt,
  note: appt.note,
  createdAt: appt.createdAt,
  branch: appt.branch,
  category: appt.category,
  account: appt.account,
  customer: appt.customer,
  accountVehicle: appt.accountVehicle,
  vehicle: appt.vehicle,
  serviceOrder: appt.serviceOrder,
  paymentStatus: appt.paymentStatus,
  arrivedAt: appt.arrivedAt,
  assignedToId: appt.assignedToId,
  assignedTo: appt.assignedTo,
);

AppointmentSummary _withAssignee(
  AppointmentSummary appt,
  AssignableUser assignee,
) => AppointmentSummary(
  id: appt.id,
  status: appt.status,
  requestedAt: appt.requestedAt,
  note: appt.note,
  createdAt: appt.createdAt,
  branch: appt.branch,
  category: appt.category,
  account: appt.account,
  customer: appt.customer,
  accountVehicle: appt.accountVehicle,
  vehicle: appt.vehicle,
  serviceOrder: appt.serviceOrder,
  paymentStatus: appt.paymentStatus,
  arrivedAt: appt.arrivedAt,
  assignedToId: assignee.id,
  assignedTo: AppointmentAssigneeRef(id: assignee.id, name: assignee.fullName),
);

AppointmentSummary _withRequestedAt(
  AppointmentSummary appt,
  DateTime requestedAt,
) => AppointmentSummary(
  id: appt.id,
  status: appt.status,
  requestedAt: requestedAt,
  note: appt.note,
  createdAt: appt.createdAt,
  branch: appt.branch,
  category: appt.category,
  account: appt.account,
  customer: appt.customer,
  accountVehicle: appt.accountVehicle,
  vehicle: appt.vehicle,
  serviceOrder: appt.serviceOrder,
  paymentStatus: appt.paymentStatus,
  arrivedAt: appt.arrivedAt,
  assignedToId: appt.assignedToId,
  assignedTo: appt.assignedTo,
);

AppointmentSummary _withServiceOrder(
  AppointmentSummary appt,
  AppointmentOrderRef serviceOrder,
) => AppointmentSummary(
  id: appt.id,
  status: appt.status,
  requestedAt: appt.requestedAt,
  note: appt.note,
  createdAt: appt.createdAt,
  branch: appt.branch,
  category: appt.category,
  account: appt.account,
  customer: appt.customer,
  accountVehicle: appt.accountVehicle,
  vehicle: appt.vehicle,
  serviceOrder: serviceOrder,
  paymentStatus: appt.paymentStatus,
  arrivedAt: appt.arrivedAt,
  assignedToId: appt.assignedToId,
  assignedTo: appt.assignedTo,
);
