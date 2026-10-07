import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';
import 'package:carservice_business/features/today/presentation/controllers/today_appointments_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_appointment_repository.dart';

/// Wraps [FakeAppointmentRepository] so a test can force `getAppointments`
/// to fail on demand — the base fake has no way to inject a transport-level
/// error, and this controller's `AsyncError` / `refreshError` paths need one.
class _ErrorInjectingRepository implements AppointmentsRepository {
  _ErrorInjectingRepository(this._inner);

  final FakeAppointmentRepository _inner;
  AppError? failNextWith;

  @override
  Future<Result<PagedResult<AppointmentSummary>>> getAppointments({
    AppointmentListQuery? query,
  }) async {
    final error = failNextWith;
    if (error != null) {
      failNextWith = null;
      return Err(error);
    }
    return _inner.getAppointments(query: query);
  }

  @override
  Future<Result<AppointmentLifecycleResult>> markArrived(String id) =>
      _inner.markArrived(id);

  @override
  Future<Result<AppointmentLifecycleResult>> confirm(
    String id, {
    String? assignedToId,
  }) => _inner.confirm(id, assignedToId: assignedToId);

  @override
  Future<Result<AppointmentSummary>> updateAssignee(
    String id,
    String assignedToId,
  ) => _inner.updateAssignee(id, assignedToId);

  @override
  Future<Result<AppointmentSummary>> getAppointment(String id) =>
      _inner.getAppointment(id);

  @override
  Future<Result<AppointmentLifecycleResult>> reject(String id) =>
      _inner.reject(id);

  @override
  Future<Result<AppointmentLifecycleResult>> markNoShow(String id) =>
      _inner.markNoShow(id);

  @override
  Future<Result<AppointmentLifecycleResult>> cancel(String id) =>
      _inner.cancel(id);

  @override
  Future<Result<AppointmentRescheduleResult>> reschedule(
    String id,
    DateTime requestedAt, {
    bool confirmed = false,
    String? assignedToId,
  }) => _inner.reschedule(id, requestedAt, confirmed: confirmed);

  @override
  Future<Result<AppointmentBulkResult>> bulkChangeCategory(
    List<String> ids,
    String categoryId,
  ) => _inner.bulkChangeCategory(ids, categoryId);

  @override
  Future<Result<AppointmentPaymentCheckResult>> checkPayment(String id) =>
      _inner.checkPayment(id);

  @override
  Future<Result<AppointmentPaymentRetryResult>> retryPayment(String id) =>
      _inner.retryPayment(id);

  @override
  Future<Result<AppointmentRefundResult>> refundPayment(
    String id, {
    required String note,
  }) => _inner.refundPayment(id, note: note);

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
  }) => _inner.createAppointment(
    branchId: branchId,
    customerId: customerId,
    vehicleId: vehicleId,
    requestedAt: requestedAt,
    note: note,
    categoryIds: categoryIds,
    confirmed: confirmed,
    assignedToId: assignedToId,
  );

  @override
  Future<Result<AppointmentDayAvailability>> getSlots({
    String? branchId,
    required DateTime date,
    List<String> categoryIds = const [],
  }) =>
      _inner.getSlots(branchId: branchId, date: date, categoryIds: categoryIds);

  @override
  Future<Result<CalendarDayModel>> getCalendarDay({
    String? branchId,
    required DateTime date,
  }) => _inner.getCalendarDay(branchId: branchId, date: date);

  @override
  Future<Result<Map<DateTime, int>>> getMonthCounts({
    String? branchId,
    required DateTime month,
  }) => _inner.getMonthCounts(branchId: branchId, month: month);
}

/// Fixed "now" for Today tests, matching `today_fixtures.dart`'s
/// `todayNow` (2026-09-23 10:00 local).
final _now = DateTime(2026, 9, 23, 10);

AppointmentSummary _appt(
  String id, {
  AppointmentStatus status = AppointmentStatus.CONFIRMED,
  DateTime? requestedAt,
  String plate = 'AA-1111',
  String customerName = 'Бат',
}) => AppointmentSummary(
  id: id,
  status: status,
  requestedAt: requestedAt,
  createdAt: DateTime(2026, 9, 22, 9),
  branch: const AppointmentBranchRef(id: 'branch-1'),
  customer: AppointmentCustomerRef(
    id: 'cust-$id',
    fullName: customerName,
    phone: '99001122',
  ),
  vehicle: AppointmentVehicleRef(id: 'veh-$id', plate: plate, make: 'Toyota'),
  category: const AppointmentCategoryRef(id: 'cat-1', name: 'Засвар'),
);

TodayAppointmentsController _controller(FakeAppointmentRepository repo) =>
    TodayAppointmentsController(
      repository: repo,
      clock: () => _now,
      autoRefresh: null,
    );

List<AppointmentSummary> _items(TodayAppointmentsController c) =>
    (c.state as AsyncData<List<AppointmentSummary>>).value;

void main() {
  test('loads appointments for today only, sorted by requested time', () async {
    final repo = FakeAppointmentRepository(
      seed: [
        _appt('later-day', requestedAt: DateTime(2026, 9, 24, 9)),
        _appt('noon', requestedAt: DateTime(2026, 9, 23, 12)),
        _appt('morning', requestedAt: DateTime(2026, 9, 23, 9)),
      ],
    );
    final c = _controller(repo);
    await c.load();

    expect(
      _items(c).map((a) => a.id),
      ['morning', 'noon'],
      reason:
          'later-day is outside today and excluded by the server-side '
          'date filter; the remaining rows sort by requested time',
    );
    expect(c.lastUpdated, _now);
    c.dispose();
  });

  test('a background refresh failure keeps the last good page and sets '
      'refreshError instead of replacing the state with AsyncError', () async {
    final repo = _ErrorInjectingRepository(
      FakeAppointmentRepository(
        seed: [_appt('a', requestedAt: DateTime(2026, 9, 23, 9))],
      ),
    );
    final c = TodayAppointmentsController(
      repository: repo,
      clock: () => _now,
      autoRefresh: null,
    );
    await c.load();
    expect(c.state, isA<AsyncData<List<AppointmentSummary>>>());
    expect(c.refreshError, isNull);

    repo.failNextWith = const AppError(ErrorKind.unknown, 'network down');
    await c.load();

    expect(
      c.state,
      isA<AsyncData<List<AppointmentSummary>>>(),
      reason: 'stale data must survive a background refresh failure',
    );
    expect(_items(c).map((a) => a.id), ['a']);
    expect(c.refreshError, isNotNull);
    c.dispose();
  });

  test('an initial load failure surfaces as AsyncError', () async {
    final repo = _ErrorInjectingRepository(FakeAppointmentRepository());
    repo.failNextWith = const AppError(ErrorKind.unknown, 'boom');
    final c = TodayAppointmentsController(
      repository: repo,
      clock: () => _now,
      autoRefresh: null,
    );

    await c.load();

    expect(c.state, isA<AsyncError<List<AppointmentSummary>>>());
    c.dispose();
  });

  group('markArrived', () {
    test('marks a CONFIRMED appointment arrived locally on success', () async {
      final repo = FakeAppointmentRepository(
        seed: [
          _appt(
            'a',
            status: AppointmentStatus.CONFIRMED,
            requestedAt: DateTime(2026, 9, 23, 9),
          ),
        ],
      );
      final c = _controller(repo);
      await c.load();
      expect(c.isArrived('a'), isFalse);

      final error = await c.markArrived('a');

      expect(error, isNull);
      expect(c.isArrived('a'), isTrue);
      c.dispose();
    });

    test('a rejected transition (not CONFIRMED) returns the error and '
        'leaves arrived false', () async {
      final repo = FakeAppointmentRepository(
        seed: [
          _appt(
            'a',
            status: AppointmentStatus.PENDING,
            requestedAt: DateTime(2026, 9, 23, 9),
          ),
        ],
      );
      final c = _controller(repo);
      await c.load();

      final error = await c.markArrived('a');

      expect(error, isNotNull);
      expect(error, isA<AppError>());
      expect(c.isArrived('a'), isFalse);
      c.dispose();
    });

    test('a reload clears every locally-tracked arrived flag', () async {
      final repo = FakeAppointmentRepository(
        seed: [
          _appt(
            'a',
            status: AppointmentStatus.CONFIRMED,
            requestedAt: DateTime(2026, 9, 23, 9),
          ),
        ],
      );
      final c = _controller(repo);
      await c.load();
      await c.markArrived('a');
      expect(c.isArrived('a'), isTrue);

      await c.load();

      expect(c.isArrived('a'), isFalse);
      c.dispose();
    });

    test('two concurrent calls for the same id are serialized via the busy '
        'set (second call is a no-op while the first is in flight)', () async {
      final repo = FakeAppointmentRepository(
        seed: [
          _appt(
            'a',
            status: AppointmentStatus.CONFIRMED,
            requestedAt: DateTime(2026, 9, 23, 9),
          ),
        ],
      );
      final c = _controller(repo);
      await c.load();

      final first = c.markArrived('a');
      expect(c.isBusy('a'), isTrue);
      final second = await c.markArrived('a');
      expect(second, isNull);

      await first;
      expect(c.isArrived('a'), isTrue);
      c.dispose();
    });
  });

  test('truncated is set when the page did not cover the full total', () async {
    final repo = FakeAppointmentRepository(
      seed: List.generate(
        3,
        (i) => _appt('a$i', requestedAt: DateTime(2026, 9, 23, 8 + i)),
      ),
    );
    final c = TodayAppointmentsController(
      repository: repo,
      clock: () => _now,
      autoRefresh: null,
    );
    await c.load();
    // The fake's default page size (200) comfortably covers 3 items.
    expect(c.truncated, isFalse);
    c.dispose();
  });
}
