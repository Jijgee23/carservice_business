import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';

/// Hand-written fake for [AppointmentsRepository] — P2-F1.
///
/// Deterministic in-memory seed data; no network. Mirrors the server-side
/// rules this repository binds to so a payload the real API would reject
/// (a status transition outside `APPOINTMENT_STATUS_TRANSITIONS`, a bulk
/// request over `MAX_BULK_APPOINTMENT_IDS`, a duplicate id, a past
/// `requestedAt`) cannot pass in a test that only exercises this fake.
class FakeAppointmentRepository implements AppointmentsRepository {
  FakeAppointmentRepository({List<AppointmentSummary>? seed})
    : _appointments = [
        ...(seed ?? [_seedAppointment()]),
      ];

  final List<AppointmentSummary> _appointments;
  final Set<String> _refunded = {};
  int _idSequence = 0;

  /// Mirrors `MAX_BULK_APPOINTMENT_IDS` in
  /// `carservice.mn/lib/appointments/appointment-bulk-commands.ts`.
  static const maxBulkAppointmentIds = 100;

  static AppointmentSummary _seedAppointment({
    String id = 'appt-1',
    AppointmentStatus status = AppointmentStatus.PENDING,
  }) => AppointmentSummary(
    id: id,
    status: status,
    requestedAt: DateTime(2026, 9, 22, 10),
    createdAt: DateTime(2026, 9, 21, 9),
    branch: const AppointmentBranchRef(id: 'branch-1', name: 'Толгойт салбар'),
    customer: const AppointmentCustomerRef(
      id: 'cust-1',
      fullName: 'Бат',
      phone: '99001122',
    ),
    category: const AppointmentCategoryRef(id: 'cat-1', name: 'Оношилгоо'),
  );

  int _indexOf(String id) => _appointments.indexWhere((a) => a.id == id);

  /// Mirrors `appointmentSearchWhere` in
  /// `carservice.mn/lib/appointments/appointment-list-query.ts` exactly — five
  /// clauses: account name, account phone, customer fullName, customer phone,
  /// and the note. Name and note match case-insensitively; both phone clauses
  /// are case-sensitive, because phone numbers have no case.
  ///
  /// The customer clauses matter more than they look: a staff-registered
  /// appointment is booked against a tenant `Customer` and has no `account` at
  /// all, so without them such an appointment cannot be found by the person's
  /// own name or phone. Do not widen past these five, and do not drop any —
  /// the same helper now backs the web dashboard, so a difference here means
  /// this fake is lying about the server.
  bool _matchesSearch(AppointmentSummary a, String q) {
    final lower = q.toLowerCase();
    final accountName = a.account?.name;
    if (accountName != null && accountName.toLowerCase().contains(lower)) {
      return true;
    }
    final accountPhone = a.account?.phone;
    if (accountPhone != null && accountPhone.contains(q)) return true;
    final customerName = a.customer?.fullName;
    if (customerName != null && customerName.toLowerCase().contains(lower)) {
      return true;
    }
    final customerPhone = a.customer?.phone;
    if (customerPhone != null && customerPhone.contains(q)) return true;
    final note = a.note;
    if (note != null && note.toLowerCase().contains(lower)) return true;
    return false;
  }

  AppointmentSummary _replaceStatus(
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
    assignedToId: appt.assignedToId,
    assignedTo: appt.assignedTo,
  );

  Result<AppointmentLifecycleResult> _transition(
    String id,
    AppointmentStatus target, {
    bool Function(AppointmentSummary)? extraGuard,
    String? guardMessage,
  }) {
    final index = _indexOf(id);
    if (index < 0) {
      return const Err(
        AppError(
          ErrorKind.notFound,
          'Цаг захиалга олдсонгүй.',
          statusCode: 404,
        ),
      );
    }
    final appt = _appointments[index];
    // Mirrors `APPOINTMENT_STATUS_TRANSITIONS` — the same matrix
    // `PATCH /appointments/[id]` and the named lifecycle routes enforce.
    if (!appt.status.nextStatuses.contains(target)) {
      return Err(
        AppError(
          ErrorKind.unknown,
          '${appt.status.name} → ${target.name} шилжилт боломжгүй.',
          statusCode: 409,
          code: 'APPOINTMENT_NOT_${appt.status.name}',
        ),
      );
    }
    if (extraGuard != null && !extraGuard(appt)) {
      return Err(
        AppError(
          ErrorKind.unknown,
          guardMessage ?? 'Боломжгүй.',
          statusCode: 422,
        ),
      );
    }
    _appointments[index] = _replaceStatus(appt, target);
    return Ok(AppointmentLifecycleResult(appointmentId: id, status: target));
  }

  @override
  Future<Result<PagedResult<AppointmentSummary>>> getAppointments({
    AppointmentListQuery? query,
  }) async {
    final effective = query ?? const AppointmentListQuery();
    if (effective.page < 1 || effective.pageSize < 1) {
      return const Err(
        AppError(ErrorKind.unknown, 'page/pageSize буруу байна.'),
      );
    }
    final filtered = _appointments
        .where((a) {
          if (effective.status != null && a.status != effective.status) {
            return false;
          }
          if (effective.branchId != null &&
              a.branch?.id != effective.branchId) {
            return false;
          }
          if (effective.date != null) {
            final requested = a.requestedAt;
            if (requested == null ||
                requested.year != effective.date!.year ||
                requested.month != effective.date!.month ||
                requested.day != effective.date!.day) {
              return false;
            }
          }
          if (effective.q != null && effective.q!.trim().isNotEmpty) {
            if (!_matchesSearch(a, effective.q!.trim())) return false;
          }
          return true;
        })
        .toList(growable: false);
    final start = (effective.page - 1) * effective.pageSize;
    final page = start >= filtered.length
        ? const <AppointmentSummary>[]
        : filtered.skip(start).take(effective.pageSize).toList(growable: false);
    return Ok(
      PagedResult(
        items: page,
        pagination: PaginationMeta(
          page: effective.page,
          pageSize: effective.pageSize,
          total: filtered.length,
          totalPages: (filtered.length / effective.pageSize).ceil(),
          hasPrev: effective.page > 1,
          hasNext: start + page.length < filtered.length,
        ),
      ),
    );
  }

  /// One bookable 09:00 slot, derived from the requested [date].
  ///
  /// Deliberately not a hardcoded ISO string. A fixed future date is a time
  /// bomb — once the wall clock passes it the slot becomes a *past* slot, and
  /// every test that depends on "a bookable future slot" starts failing for a
  /// reason that has nothing to do with the change under test. Deriving from
  /// [date] also stops this fake from claiming the same slot for every day,
  /// which the real endpoint would never do.
  @override
  Future<Result<AppointmentDayAvailability>> getSlots({
    String? branchId,
    required DateTime date,
    List<String> categoryIds = const [],
  }) async {
    // 09:00 on the requested day, unless that is already in the past (the
    // common case when `date` is today and it is now afternoon). Callers rely
    // on this slot being *bookable*, and the controller correctly refuses a
    // past slot — so the fake must offer a future one or it would be promising
    // something the real UI would reject.
    final nineAm = DateTime(date.year, date.month, date.day, 9);
    final now = DateTime.now();
    var slotAt = nineAm.isAfter(now)
        ? nineAm
        : DateTime(now.year, now.month, now.day, now.hour + 1);
    // Never offer a slot this same fake would then reject as a reservation
    // conflict. The real `GET /appointments/slots` does not advertise a time
    // that is already taken, and a fake that does produces a dead end the UI
    // can never escape: `canSubmit` goes true and `submit()` returns a 409.
    // This is not hypothetical — the seeded appointment sits at a fixed
    // calendar date and hour, so the derived fallback above collides with it
    // for exactly one hour of one day, which is precisely the kind of failure
    // that looks like a regression in whatever change happens to be in flight.
    bool taken(DateTime at) => _appointments.any(
      (a) =>
          a.branch?.id == branchId &&
          a.requestedAt == at &&
          (a.status == AppointmentStatus.PENDING ||
              a.status == AppointmentStatus.CONFIRMED),
    );
    while (taken(slotAt)) {
      slotAt = slotAt.add(const Duration(minutes: 30));
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final iso =
        '${slotAt.year}-${two(slotAt.month)}-${two(slotAt.day)}'
        'T${two(slotAt.hour)}:${two(slotAt.minute)}:00';
    return Ok(
      AppointmentDayAvailability(
        open: true,
        slots: [
          AppointmentSlot(
            time: '${two(slotAt.hour)}:${two(slotAt.minute)}',
            iso: iso,
            available: true,
            remaining: 1,
          ),
        ],
        durationMinutes: 30,
      ),
    );
  }

  @override
  Future<Result<CalendarDayModel>> getCalendarDay({
    String? branchId,
    required DateTime date,
  }) async => Ok(
    CalendarDayModel(
      branchId: branchId ?? 'branch-1',
      dateKey: _dateOnly(date),
      slotCapacity: 1,
      laneCount: 1,
      hasCapacityOverflow: false,
      blocks: const [],
      legend: const [],
    ),
  );

  /// Derives counts from the fake's own seeded `_appointments` — never a
  /// hardcoded map — so a test cannot pass against behavior the server
  /// would not actually produce. Mirrors the route's month-counts mode:
  /// filtered by `requestedAt` falling in [month] (and `branchId` when
  /// given), one occurrence per appointment, grouped into a date-only
  /// `DateTime -> count` map exactly like `AppointmentMonthCountsDto`.
  @override
  Future<Result<Map<DateTime, int>>> getMonthCounts({
    String? branchId,
    required DateTime month,
  }) async {
    final counts = <DateTime, int>{};
    for (final appt in _appointments) {
      final requested = appt.requestedAt;
      if (requested == null) continue;
      if (requested.year != month.year || requested.month != month.month) {
        continue;
      }
      if (branchId != null && appt.branch?.id != branchId) continue;
      final key = DateTime(requested.year, requested.month, requested.day);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return Ok(counts);
  }

  @override
  Future<Result<AppointmentSummary>> createAppointment({
    required String branchId,
    required String customerId,
    String? vehicleId,
    required DateTime requestedAt,
    String? note,
    List<String> categoryIds = const [],
    bool confirmed = false,
    String? assignedToId,
  }) async {
    // Mirrors `parseCreateAppointmentBody`'s past-time rejection — the same
    // 422 field-error shape the server returns.
    if (requestedAt.isBefore(DateTime.now())) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Өнгөрсөн цаг сонгох боломжгүй.',
          statusCode: 422,
          code: 'APPOINTMENT_COMMAND_REJECTED',
          fieldErrors: {'requestedAt': 'Өнгөрсөн цаг сонгох боломжгүй.'},
        ),
      );
    }
    // Mirrors `ReservationConflictError` → 409 RESERVATION_CONFLICT: the
    // same slot (branch + exact requestedAt) already taken by a
    // PENDING/CONFIRMED appointment, unless the caller passes `confirmed`
    // (staff override), matching `reserveAppointment`'s semantics.
    final conflict = _appointments.any(
      (a) =>
          a.branch?.id == branchId &&
          a.requestedAt == requestedAt &&
          (a.status == AppointmentStatus.PENDING ||
              a.status == AppointmentStatus.CONFIRMED),
    );
    if (conflict && !confirmed) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Энэ цаг аль хэдийн захиалагдсан байна.',
          statusCode: 409,
          code: 'RESERVATION_CONFLICT',
          fieldErrors: {'confirmNeeded': 'true'},
        ),
      );
    }
    final id = 'appt-${++_idSequence}';
    final created = AppointmentSummary(
      id: id,
      status: AppointmentStatus.CONFIRMED,
      requestedAt: requestedAt,
      note: note,
      createdAt: DateTime.now(),
      branch: AppointmentBranchRef(id: branchId, name: 'Салбар'),
      customer: AppointmentCustomerRef(id: customerId, fullName: 'Үйлчлүүлэгч'),
      category: categoryIds.isEmpty
          ? null
          : AppointmentCategoryRef(id: categoryIds.first),
      assignedToId: assignedToId,
    );
    _appointments.add(created);
    return Ok(created);
  }

  @override
  Future<Result<AppointmentLifecycleResult>> confirm(
    String appointmentId, {
    String? assignedToId,
  }) async {
    // Lenient on purpose: the real server answers 422 ASSIGNEE_REQUIRED for a
    // master-less appointment, but enforcing that here would break every
    // lifecycle test that confirms the (master-less) seed. Tests that need the
    // rule script their own repository. A supplied master is recorded.
    final result = _transition(appointmentId, AppointmentStatus.CONFIRMED);
    final index = _indexOf(appointmentId);
    if (result is Ok && assignedToId != null && index >= 0) {
      final a = _appointments[index];
      _appointments[index] = AppointmentSummary(
        id: a.id,
        status: a.status,
        requestedAt: a.requestedAt,
        note: a.note,
        createdAt: a.createdAt,
        branch: a.branch,
        category: a.category,
        account: a.account,
        customer: a.customer,
        accountVehicle: a.accountVehicle,
        vehicle: a.vehicle,
        serviceOrder: a.serviceOrder,
        assignedToId: assignedToId,
        assignedTo: AppointmentAssigneeRef(id: assignedToId),
      );
    }
    return result;
  }

  /// Mirrors `PATCH /appointments/[id]` `{assignedToId}`; the interface takes a
  /// non-null id, so clearing (the server's 422) cannot be expressed.
  @override
  Future<Result<AppointmentSummary>> updateAssignee(
    String appointmentId,
    String assignedToId,
  ) async {
    final index = _indexOf(appointmentId);
    if (index < 0) {
      return const Err(
        AppError(ErrorKind.notFound, 'Цаг захиалга олдсонгүй', statusCode: 404),
      );
    }
    final a = _appointments[index];
    final updated = AppointmentSummary(
      id: a.id,
      status: a.status,
      requestedAt: a.requestedAt,
      note: a.note,
      createdAt: a.createdAt,
      branch: a.branch,
      category: a.category,
      account: a.account,
      customer: a.customer,
      accountVehicle: a.accountVehicle,
      vehicle: a.vehicle,
      serviceOrder: a.serviceOrder,
      assignedToId: assignedToId,
      assignedTo: AppointmentAssigneeRef(id: assignedToId),
    );
    _appointments[index] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<AppointmentSummary>> getAppointment(
    String appointmentId,
  ) async {
    final index = _indexOf(appointmentId);
    if (index < 0) {
      return const Err(
        AppError(ErrorKind.notFound, 'Цаг захиалга олдсонгүй', statusCode: 404),
      );
    }
    return Ok(_appointments[index]);
  }

  @override
  Future<Result<AppointmentLifecycleResult>> reject(
    String appointmentId,
  ) async => _transition(appointmentId, AppointmentStatus.REJECTED);

  @override
  Future<Result<AppointmentLifecycleResult>> markNoShow(
    String appointmentId,
  ) async => _transition(appointmentId, AppointmentStatus.NO_SHOW);

  @override
  Future<Result<AppointmentLifecycleResult>> markArrived(
    String appointmentId,
  ) async {
    final index = _indexOf(appointmentId);
    if (index < 0) {
      return const Err(
        AppError(
          ErrorKind.notFound,
          'Цаг захиалга олдсонгүй.',
          statusCode: 404,
        ),
      );
    }
    if (_appointments[index].status != AppointmentStatus.CONFIRMED) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Энэ цагийг тэмдэглэх боломжгүй.',
          statusCode: 422,
          code: 'APPOINTMENT_NOT_CONFIRMED',
        ),
      );
    }
    return Ok(
      AppointmentLifecycleResult(appointmentId: appointmentId, arrived: true),
    );
  }

  @override
  Future<Result<AppointmentLifecycleResult>> cancel(
    String appointmentId,
  ) async => _transition(appointmentId, AppointmentStatus.CANCELLED);

  @override
  Future<Result<AppointmentRescheduleResult>> reschedule(
    String appointmentId,
    DateTime requestedAt, {
    bool confirmed = false,
  }) async {
    final index = _indexOf(appointmentId);
    if (index < 0) {
      return const Err(
        AppError(
          ErrorKind.notFound,
          'Цаг захиалга олдсонгүй.',
          statusCode: 404,
        ),
      );
    }
    final appt = _appointments[index];
    if (appt.status != AppointmentStatus.CONFIRMED) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Зөвхөн баталгаажсан цагийг энд шилжүүлнэ.',
          statusCode: 422,
          code: 'APPOINTMENT_NOT_CONFIRMED',
        ),
      );
    }
    if (requestedAt.isBefore(DateTime.now())) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Өнгөрсөн цаг сонгох боломжгүй.',
          statusCode: 422,
          fieldErrors: {'requestedAt': 'Өнгөрсөн цаг сонгох боломжгүй.'},
        ),
      );
    }
    if (appt.serviceOrder != null) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Энэ цаг захиалга эхэлсэн/хойшлуулсан ажлын хуудастай холбогдсон тул энд шилжүүлэх боломжгүй.',
          statusCode: 422,
          code: 'LINKED_ORDER_NOT_SCHEDULED',
        ),
      );
    }
    _appointments[index] = AppointmentSummary(
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
    );
    return Ok(
      AppointmentRescheduleResult(
        appointmentId: appt.id,
        linked: false,
        requestedAt: requestedAt,
      ),
    );
  }

  @override
  Future<Result<AppointmentBulkResult>> bulkChangeCategory(
    List<String> appointmentIds,
    String categoryId,
  ) async {
    // Mirrors the route's own boundary parse (`parseBulkCategoryBody`) —
    // empty, oversized and duplicate id lists are rejected client-visibly
    // the same way, before any row is touched.
    if (appointmentIds.isEmpty) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Дор хаяж нэг цаг захиалга сонгоно уу.',
          statusCode: 400,
          code: 'INVALID_BULK_REQUEST',
        ),
      );
    }
    if (appointmentIds.length > maxBulkAppointmentIds) {
      return Err(
        AppError(
          ErrorKind.unknown,
          'Нэг хүсэлтэд хамгийн ихдээ $maxBulkAppointmentIds цаг захиалга сонгоно уу.',
          statusCode: 400,
          code: 'INVALID_BULK_REQUEST',
        ),
      );
    }
    if (appointmentIds.toSet().length != appointmentIds.length) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Нэг цаг захиалгыг давхар сонгож болохгүй.',
          statusCode: 400,
          code: 'INVALID_BULK_REQUEST',
        ),
      );
    }
    final succeeded = <String>[];
    final failed = <AppointmentBulkFailure>[];
    for (final id in appointmentIds) {
      final index = _indexOf(id);
      if (index < 0) {
        failed.add(
          AppointmentBulkFailure(
            appointmentId: id,
            code: 'APPOINTMENT_NOT_FOUND',
            message: 'Цаг захиалга олдсонгүй.',
          ),
        );
        continue;
      }
      final appt = _appointments[index];
      if (appt.serviceOrder != null) {
        failed.add(
          AppointmentBulkFailure(
            appointmentId: id,
            code: 'LINKED_ORDER_EXISTS',
            message: 'Засварын хуудас үүссэн тул ажлын төрлийг энд өөрчлөх боломжгүй.',
          ),
        );
        continue;
      }
      _appointments[index] = AppointmentSummary(
        id: appt.id,
        status: appt.status,
        requestedAt: appt.requestedAt,
        note: appt.note,
        createdAt: appt.createdAt,
        branch: appt.branch,
        category: AppointmentCategoryRef(id: categoryId),
        account: appt.account,
        customer: appt.customer,
        accountVehicle: appt.accountVehicle,
        vehicle: appt.vehicle,
        serviceOrder: appt.serviceOrder,
      );
      succeeded.add(id);
    }
    return Ok(AppointmentBulkResult(succeeded: succeeded, failed: failed));
  }

  @override
  Future<Result<AppointmentPaymentCheckResult>> checkPayment(
    String appointmentId,
  ) async => const Ok(AppointmentPaymentCheckResult(ok: true, paid: false));

  @override
  Future<Result<AppointmentPaymentRetryResult>> retryPayment(
    String appointmentId,
  ) async => const Ok(AppointmentPaymentRetryResult(ok: true, required: false));

  @override
  Future<Result<AppointmentRefundResult>> refundPayment(
    String appointmentId, {
    required String note,
  }) async {
    // Mirrors the route's mandatory-note rejection (422 REFUND_NOTE_REQUIRED)
    // and its double-refund rejection (422 PAYMENT_ALREADY_REFUNDED).
    if (note.trim().isEmpty) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Буцаах шалтгаан/тэмдэглэл заавал бөглөнө үү.',
          statusCode: 422,
          code: 'REFUND_NOTE_REQUIRED',
          fieldErrors: {'note': 'Заавал бөглөнө.'},
        ),
      );
    }
    if (_refunded.contains(appointmentId)) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Энэ төлбөр аль хэдийн буцаагдсан.',
          statusCode: 422,
          code: 'PAYMENT_ALREADY_REFUNDED',
        ),
      );
    }
    _refunded.add(appointmentId);
    return Ok(
      AppointmentRefundResult(
        paymentId: 'pay-$appointmentId',
        refundedVia: 'MANUAL',
        amount: '10000',
        currency: 'MNT',
      ),
    );
  }
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
