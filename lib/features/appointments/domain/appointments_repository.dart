import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';

/// Server-side filters supported by `GET /api/v1/appointments` (day-list
/// mode). `date` is a single business-local day (`YYYY-MM-DD`), matching the
/// route's `date` query param — there is no server-side date-range filter on
/// this endpoint today (P2-F2 paginates within a day/status/branch scope).
class AppointmentListQuery {
  final AppointmentStatus? status;
  final String? branchId;
  final DateTime? date;

  /// `?q=` — free-text search added by `P2-B8`/`P2-F2a`. Matches the web
  /// dashboard's three clauses exactly: account name (case-insensitive),
  /// account phone (case-sensitive — phone numbers have no case), and the
  /// appointment note (case-insensitive). Callers must send it trimmed and
  /// omit it entirely when empty/whitespace-only — never send a vacuous `q`.
  final String? q;
  final int page;
  final int pageSize;

  const AppointmentListQuery({
    this.status,
    this.branchId,
    this.date,
    this.q,
    this.page = 1,
    this.pageSize = 50,
  });
}

/// One frozen repository contract for the Appointments feature — P2-F1.
///
/// Every appointment mutation is expressed exactly once here: each named
/// lifecycle transition (confirm/reject/no-show/arrived) is its own method
/// because the backend itself exposes them as four distinct thin-adapter
/// routes over the shared `appointment-commands.ts`, never as a generic
/// `updateStatus(status)` call that could duplicate that dispatch client
/// side. `PATCH /appointments/[id]` is NOT separately exposed here — for
/// CONFIRMED/REJECTED/NO_SHOW it is the exact same server-side command as
/// the named routes, and CANCELLED (the one transition without a named
/// route) is reached through [cancel].
///
/// Appointment-to-order conversion is explicitly out of scope (`P2-F6`) — it
/// calls the Orders repository's `createOrder(appointmentId: ...)`, never a
/// method on this interface.
abstract interface class AppointmentsRepository {
  /// `GET /appointments/[id]` — one appointment, working-branch scoped
  /// (404 outside it). Used to open a detail from just an id (notifications).
  Future<Result<AppointmentSummary>> getAppointment(String appointmentId);

  Future<Result<PagedResult<AppointmentSummary>>> getAppointments({
    AppointmentListQuery? query,
  });

  Future<Result<AppointmentDayAvailability>> getSlots({
    String? branchId,
    required DateTime date,
    List<String> categoryIds = const [],
  });

  Future<Result<CalendarDayModel>> getCalendarDay({
    String? branchId,
    required DateTime date,
  });

  /// `GET /appointments?month=YYYY-MM` — per-day appointment counts for the
  /// given month, for calendar dot counts (`P2-F1b`).
  ///
  /// The server returns a raw `{dates: string[]}` — one `YYYY-MM-DD` entry
  /// per appointment in that month (a day with 3 appointments appears 3
  /// times), not a pre-aggregated count. This method does the aggregation
  /// the server deliberately left to the caller, and nothing more: no
  /// client-side re-derivation of *which* appointments fall in the month —
  /// that grouping is exactly what this endpoint exists to avoid re-fetching
  /// and re-computing client side. The result keys are date-only
  /// `DateTime`s (`DateTime(y, m, d)`, no time component) so callers can look
  /// up a calendar cell directly; a day with zero appointments is simply
  /// absent from the map, never present with a `0` value.
  Future<Result<Map<DateTime, int>>> getMonthCounts({
    String? branchId,
    required DateTime month,
  });

  /// `POST /appointments` — staff phone-in registration.
  Future<Result<AppointmentSummary>> createAppointment({
    required String branchId,
    required String customerId,
    String? vehicleId,
    required DateTime requestedAt,
    String? note,
    List<String> categoryIds = const [],
    bool confirmed = false,
    String? assignedToId,
  });

  /// `POST /appointments/[id]/confirm`. [assignedToId] is sent as the optional
  /// `{assignedToId}` body; it is required (422 `ASSIGNEE_REQUIRED`) when the
  /// appointment has no master and the caller holds `orders.assign`.
  Future<Result<AppointmentLifecycleResult>> confirm(
    String appointmentId, {
    String? assignedToId,
  });

  /// `PATCH /appointments/[id]` with `{assignedToId}` — change the master.
  /// The id is non-nullable on purpose: the server refuses clearing (422
  /// `ASSIGNEE_REQUIRED`), so the client has no way to ask for it.
  Future<Result<AppointmentSummary>> updateAssignee(
    String appointmentId,
    String assignedToId,
  );

  /// `POST /appointments/[id]/reject`.
  Future<Result<AppointmentLifecycleResult>> reject(String appointmentId);

  /// `POST /appointments/[id]/no-show`.
  Future<Result<AppointmentLifecycleResult>> markNoShow(String appointmentId);

  /// `POST /appointments/[id]/arrived`.
  Future<Result<AppointmentLifecycleResult>> markArrived(String appointmentId);

  /// `PATCH /appointments/[id]` with `{status: "CANCELLED"}` — the one
  /// transition (CONFIRMED → CANCELLED) with no named lifecycle route.
  Future<Result<AppointmentLifecycleResult>> cancel(String appointmentId);

  /// `POST /appointments/[id]/reschedule`.
  Future<Result<AppointmentRescheduleResult>> reschedule(
    String appointmentId,
    DateTime requestedAt, {
    bool confirmed = false,
  });

  /// `POST /appointments/bulk/category` — one category applied to many
  /// appointments; partial success, one row per target in `failed`.
  Future<Result<AppointmentBulkResult>> bulkChangeCategory(
    List<String> appointmentIds,
    String categoryId,
  );

  /// `POST /appointments/[id]/payment` — re-verify a pending online-booking
  /// fee against the provider and record it if paid. Never trusts a
  /// client-supplied paid/amount value; this only asks the server to
  /// re-check.
  Future<Result<AppointmentPaymentCheckResult>> checkPayment(
    String appointmentId,
  );

  /// `POST /appointments/[id]/payment/retry` — re-issue a QPay checkout
  /// after a failed invoice attempt.
  Future<Result<AppointmentPaymentRetryResult>> retryPayment(
    String appointmentId,
  );

  /// `POST /appointments/[id]/payment/refund` — requires `payments.delete`
  /// server-side; `note` is mandatory (422 `REFUND_NOTE_REQUIRED` otherwise).
  Future<Result<AppointmentRefundResult>> refundPayment(
    String appointmentId, {
    required String note,
  });
}
