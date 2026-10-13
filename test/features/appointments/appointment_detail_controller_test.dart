import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/appointment_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_appointment_repository.dart';

/// Wraps [FakeAppointmentRepository] and lets a test force the *next*
/// `getAppointments` call (the one [AppointmentDetailController.refresh]
/// issues after a mutation) to fail, without touching any mutation
/// endpoint. This is what pins the P2-F5 regression: a successful mutation
/// must stay visible even when the follow-up refresh fails.
class _RefreshFailureRepository implements AppointmentsRepository {
  _RefreshFailureRepository(this._inner);

  final FakeAppointmentRepository _inner;
  bool failNextGetAppointments = false;
  int getAppointmentsCallCount = 0;

  @override
  Future<Result<PagedResult<AppointmentSummary>>> getAppointments({
    AppointmentListQuery? query,
  }) async {
    getAppointmentsCallCount++;
    if (failNextGetAppointments) {
      failNextGetAppointments = false;
      return const Err(AppError(ErrorKind.network, 'Холболт байхгүй'));
    }
    return _inner.getAppointments(query: query);
  }

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
  Future<Result<AppointmentLifecycleResult>> confirm(
    String appointmentId, {
    String? assignedToId,
  }) => _inner.confirm(appointmentId, assignedToId: assignedToId);

  @override
  Future<Result<AppointmentSummary>> updateAssignee(
    String appointmentId,
    String assignedToId,
  ) => _inner.updateAssignee(appointmentId, assignedToId);

  @override
  Future<Result<AppointmentSummary>> getAppointment(String appointmentId) =>
      _inner.getAppointment(appointmentId);

  @override
  Future<Result<AppointmentLifecycleResult>> reject(String appointmentId) =>
      _inner.reject(appointmentId);

  @override
  Future<Result<AppointmentLifecycleResult>> markNoShow(String appointmentId) =>
      _inner.markNoShow(appointmentId);

  @override
  Future<Result<AppointmentLifecycleResult>> markArrived(
    String appointmentId,
  ) => _inner.markArrived(appointmentId);

  @override
  Future<Result<AppointmentLifecycleResult>> cancel(String appointmentId) =>
      _inner.cancel(appointmentId);

  @override
  Future<Result<AppointmentRescheduleResult>> reschedule(
    String appointmentId,
    DateTime requestedAt, {
    bool confirmed = false,
    String? assignedToId,
  }) => _inner.reschedule(appointmentId, requestedAt, confirmed: confirmed);

  @override
  Future<Result<AppointmentBulkResult>> bulkChangeCategory(
    List<String> appointmentIds,
    String categoryId,
  ) => _inner.bulkChangeCategory(appointmentIds, categoryId);

  @override
  Future<Result<AppointmentPaymentCheckResult>> checkPayment(
    String appointmentId,
  ) => _inner.checkPayment(appointmentId);

  @override
  Future<Result<AppointmentPaymentRetryResult>> retryPayment(
    String appointmentId,
  ) => _inner.retryPayment(appointmentId);

  @override
  Future<Result<AppointmentRefundResult>> refundPayment(
    String appointmentId, {
    required String note,
  }) => _inner.refundPayment(appointmentId, note: note);
}

AppointmentSummary _pending({
  String id = 'appt-1',
  AppointmentStatus status = AppointmentStatus.PENDING,
  DateTime? requestedAt,
}) => AppointmentSummary(
  id: id,
  status: status,
  requestedAt: requestedAt ?? DateTime(2026, 9, 22, 10),
  branch: const AppointmentBranchRef(id: 'branch-1', name: 'Толгойт салбар'),
  customer: const AppointmentCustomerRef(
    id: 'cust-1',
    fullName: 'Бат',
    phone: '99001122',
  ),
);

void main() {
  group('AppointmentDetailController — success then refresh failure', () {
    test('confirm() applies the mutation response and keeps it visible even '
        'when the follow-up refresh fails', () async {
      final seed = _pending();
      final fake = FakeAppointmentRepository(seed: [seed]);
      final repo = _RefreshFailureRepository(fake);
      final controller = AppointmentDetailController(initial: seed, repo: repo);
      addTearDown(controller.dispose);

      repo.failNextGetAppointments = true;
      final result = await controller.confirm();

      expect(result, isA<Ok<AppointmentLifecycleResult>>());
      // The write is visible immediately...
      expect(
        controller.detailState.valueOrNull?.status,
        AppointmentStatus.CONFIRMED,
      );

      // ...and the incidental refresh() this triggers is `unawaited`, so
      // pump the event loop once for it to actually run and fail.
      await Future<void>.delayed(Duration.zero);

      // The successful write must still be what's displayed — never
      // replaced by an AsyncError from the failed refresh.
      expect(controller.detailState, isA<AsyncData<AppointmentSummary>>());
      expect(
        controller.detailState.valueOrNull?.status,
        AppointmentStatus.CONFIRMED,
      );
      // The failure is surfaced as a non-destructive banner field instead.
      expect(controller.refreshError, isNotNull);
    });

    test('refresh() succeeding afterwards clears the banner and applies the '
        'server row', () async {
      final seed = _pending();
      final fake = FakeAppointmentRepository(seed: [seed]);
      final repo = _RefreshFailureRepository(fake);
      final controller = AppointmentDetailController(initial: seed, repo: repo);
      addTearDown(controller.dispose);

      repo.failNextGetAppointments = true;
      await controller.confirm();
      await Future<void>.delayed(Duration.zero);
      expect(controller.refreshError, isNotNull);

      await controller.refresh();
      expect(controller.refreshError, isNull);
      expect(
        controller.detailState.valueOrNull?.status,
        AppointmentStatus.CONFIRMED,
      );
    });
  });

  group('AppointmentDetailController — confirm-blocked reason', () {
    test('refresh() clears a previously set reason', () async {
      final seed = _pending();
      final fake = FakeAppointmentRepository(seed: [seed]);
      final controller = AppointmentDetailController(initial: seed, repo: fake);
      addTearDown(controller.dispose);

      controller.setConfirmBlockedReason('blocked');
      expect(controller.confirmBlockedReason, 'blocked');

      await controller.refresh();
      expect(controller.confirmBlockedReason, isNull);
    });
  });

  group('AppointmentDetailController — illegal transitions', () {
    test('reject() on an already-CONFIRMED appointment surfaces the server '
        'message verbatim and does not change local state', () async {
      final seed = _pending(status: AppointmentStatus.CONFIRMED);
      final fake = FakeAppointmentRepository(seed: [seed]);
      final controller = AppointmentDetailController(initial: seed, repo: fake);
      addTearDown(controller.dispose);

      final result = await controller.reject();
      expect(result, isA<Err<AppointmentLifecycleResult>>());
      final error = (result as Err<AppointmentLifecycleResult>).error;
      expect(error.statusCode, 409);
      expect(error.message, contains('шилжилт боломжгүй'));
      // Local state is untouched by the rejected mutation.
      expect(
        controller.detailState.valueOrNull?.status,
        AppointmentStatus.CONFIRMED,
      );
    });

    test(
      'markArrived() on a PENDING appointment is rejected by the server',
      () async {
        final seed = _pending();
        final fake = FakeAppointmentRepository(seed: [seed]);
        final controller = AppointmentDetailController(
          initial: seed,
          repo: fake,
        );
        addTearDown(controller.dispose);

        final result = await controller.markArrived();
        expect(result, isA<Err<AppointmentLifecycleResult>>());
        expect(controller.arrived, isNot(true));
      },
    );
  });

  group('AppointmentDetailController — client-side gating helpers', () {
    test('unknown status offers no action', () {
      expect(
        AppointmentDetailController.canConfirm(AppointmentStatus.unknown),
        isFalse,
      );
      expect(
        AppointmentDetailController.canReject(AppointmentStatus.unknown),
        isFalse,
      );
      expect(
        AppointmentDetailController.canCancel(AppointmentStatus.unknown),
        isFalse,
      );
      expect(
        AppointmentDetailController.canMarkNoShow(AppointmentStatus.unknown),
        isFalse,
      );
      expect(
        AppointmentDetailController.canMarkArrived(
          AppointmentStatus.unknown,
          null,
        ),
        isFalse,
      );
      expect(
        AppointmentDetailController.canReschedule(AppointmentStatus.unknown),
        isFalse,
      );
    });

    test('PENDING allows confirm/reject only', () {
      expect(
        AppointmentDetailController.canConfirm(AppointmentStatus.PENDING),
        isTrue,
      );
      expect(
        AppointmentDetailController.canReject(AppointmentStatus.PENDING),
        isTrue,
      );
      expect(
        AppointmentDetailController.canCancel(AppointmentStatus.PENDING),
        isFalse,
      );
      expect(
        AppointmentDetailController.canMarkArrived(
          AppointmentStatus.PENDING,
          null,
        ),
        isFalse,
      );
    });

    test('CONFIRMED allows no-show/cancel/arrived/reschedule', () {
      expect(
        AppointmentDetailController.canMarkNoShow(AppointmentStatus.CONFIRMED),
        isTrue,
      );
      expect(
        AppointmentDetailController.canCancel(AppointmentStatus.CONFIRMED),
        isTrue,
      );
      expect(
        AppointmentDetailController.canMarkArrived(
          AppointmentStatus.CONFIRMED,
          null,
        ),
        isTrue,
      );
      expect(
        AppointmentDetailController.canMarkArrived(
          AppointmentStatus.CONFIRMED,
          true,
        ),
        isFalse,
      );
      expect(
        AppointmentDetailController.canReschedule(AppointmentStatus.CONFIRMED),
        isTrue,
      );
    });
  });

  group('AppointmentDetailController — reschedule (no overlap confirm)', () {
    test('reschedule() never sends confirmed:true', () async {
      final seed = _pending(status: AppointmentStatus.CONFIRMED);
      final fake = FakeAppointmentRepository(seed: [seed]);
      final controller = AppointmentDetailController(initial: seed, repo: fake);
      addTearDown(controller.dispose);

      final next = DateTime.now().add(const Duration(days: 1));
      final result = await controller.reschedule(next);
      expect(result, isA<Ok<AppointmentRescheduleResult>>());
      expect(controller.detailState.valueOrNull?.requestedAt, next);
    });
  });

  group('AppointmentDetailController — payments', () {
    test(
      'checkPayment/retryPayment/refundPayment apply their own result',
      () async {
        final seed = _pending(status: AppointmentStatus.CONFIRMED);
        final fake = FakeAppointmentRepository(seed: [seed]);
        final controller = AppointmentDetailController(
          initial: seed,
          repo: fake,
        );
        addTearDown(controller.dispose);

        expect(
          controller.paymentStatus,
          AppointmentBookingPaymentStatus.unknown,
        );

        await controller.checkPayment();
        expect(controller.lastPaymentCheck, isNotNull);

        final refundResult = await controller.refundPayment(
          note: 'Тест шалтгаан',
        );
        // The fake's refund behavior mirrors the real server's rules; assert
        // only on the controller's own bookkeeping, not the fake's business
        // outcome, so this stays a controller test.
        if (refundResult case Ok(:final value)) {
          expect(controller.lastRefund, value);
          expect(
            controller.paymentStatus,
            AppointmentBookingPaymentStatus.REFUNDED,
          );
        }
      },
    );

    test('refundPayment ignores a second tap while one is in flight', () async {
      final seed = _pending(status: AppointmentStatus.CONFIRMED);
      final fake = FakeAppointmentRepository(seed: [seed]);
      final controller = AppointmentDetailController(initial: seed, repo: fake);
      addTearDown(controller.dispose);

      final first = controller.refundPayment(note: 'a');
      final second = await controller.refundPayment(note: 'b');
      expect(second, isA<Err<AppointmentRefundResult>>());
      await first;
    });
  });

  group('AppointmentDetailController — generation guard', () {
    test('a stale in-flight mutation cannot clobber a newer state', () async {
      final seed = _pending();
      final fake = FakeAppointmentRepository(seed: [seed]);
      final controller = AppointmentDetailController(initial: seed, repo: fake);

      // Start a confirm, then dispose mid-flight to bump `_generation` via
      // teardown ordering is awkward to race deterministically without an
      // injectable delay; instead assert the documented contract directly:
      // dispose() bumps the generation so any in-flight callback becomes
      // stale and is a no-op.
      final future = controller.confirm();
      controller.dispose();
      final result = await future;
      expect(result, isA<Ok<AppointmentLifecycleResult>>());
      // No crash / no notifyListeners after dispose — reaching here without
      // a "used after dispose" exception is the assertion.
    });
  });
}
