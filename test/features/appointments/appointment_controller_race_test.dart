import 'dart:async';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/appointment_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ported to the P2-F1 frozen `AppointmentsRepository` contract and to
/// `AppointmentListController` — P2-F2.
///
/// The original fixture extended the pre-programme `AppointmentRepository`
/// (removed by P2-F1) and pinned a race in the then-current
/// `AppointmentController.loadAppointments`/`loadMonthCounts`. P2-F2 moves
/// list-loading and its generation guard into `AppointmentListController`
/// (mirroring `OrderListController`), so this test is re-pointed there. The
/// race it protects — a stale in-flight response completing *after* a newer
/// request must never win — is the same regression class; `loadMonthCounts`
/// itself is dropped because the frozen contract has no month-count
/// endpoint to race (see the contract-gap note on
/// `AppointmentListController`).
///
/// Confirmed this test actually catches the regression: temporarily
/// reordering `loadAppointments` to drop the
/// `requestGeneration != _generation` check makes both assertions below
/// fail (the stale 'old' response wins instead of 'new').
class _QueuedAppointmentsRepository implements AppointmentsRepository {
  final requests = <String?>[];
  final pendingLists = <Completer<Result<PagedResult<AppointmentSummary>>>>[];

  @override
  Future<Result<PagedResult<AppointmentSummary>>> getAppointments({
    AppointmentListQuery? query,
  }) {
    requests.add(query?.branchId);
    final completer = Completer<Result<PagedResult<AppointmentSummary>>>();
    pendingLists.add(completer);
    return completer.future;
  }

  @override
  Future<Result<AppointmentDayAvailability>> getSlots({
    String? branchId,
    required DateTime date,
    List<String> categoryIds = const [],
  }) => throw UnimplementedError();

  @override
  Future<Result<CalendarDayModel>> getCalendarDay({
    String? branchId,
    required DateTime date,
  }) => throw UnimplementedError();

  @override
  Future<Result<Map<DateTime, int>>> getMonthCounts({
    String? branchId,
    required DateTime month,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<Result<AppointmentLifecycleResult>> confirm(
    String appointmentId, {
    String? assignedToId,
  }) => throw UnimplementedError();

  @override
  Future<Result<AppointmentSummary>> updateAssignee(
    String appointmentId,
    String assignedToId,
  ) => throw UnimplementedError();

  @override
  Future<Result<AppointmentSummary>> getAppointment(String appointmentId) =>
      throw UnimplementedError();

  @override
  Future<Result<AppointmentLifecycleResult>> reject(String appointmentId) =>
      throw UnimplementedError();

  @override
  Future<Result<AppointmentLifecycleResult>> markNoShow(String appointmentId) =>
      throw UnimplementedError();

  @override
  Future<Result<AppointmentLifecycleResult>> markArrived(
    String appointmentId,
  ) => throw UnimplementedError();

  @override
  Future<Result<AppointmentLifecycleResult>> cancel(String appointmentId) =>
      throw UnimplementedError();

  @override
  Future<Result<AppointmentRescheduleResult>> reschedule(
    String appointmentId,
    DateTime requestedAt, {
    bool confirmed = false,
    String? assignedToId,
  }) => throw UnimplementedError();

  @override
  Future<Result<AppointmentBulkResult>> bulkChangeCategory(
    List<String> appointmentIds,
    String categoryId,
  ) => throw UnimplementedError();

  @override
  Future<Result<AppointmentPaymentCheckResult>> checkPayment(
    String appointmentId,
  ) => throw UnimplementedError();

  @override
  Future<Result<AppointmentPaymentRetryResult>> retryPayment(
    String appointmentId,
  ) => throw UnimplementedError();

  @override
  Future<Result<AppointmentRefundResult>> refundPayment(
    String appointmentId, {
    required String note,
  }) => throw UnimplementedError();
}

PagedResult<AppointmentSummary> _page(String id) => PagedResult(
  items: [
    AppointmentSummary(
      id: id,
      status: AppointmentStatus.PENDING,
      requestedAt: DateTime(2026, 1, 1, 9),
      createdAt: DateTime(2026),
      branch: const AppointmentBranchRef(id: 'branch', name: 'Branch'),
    ),
  ],
  pagination: const PaginationMeta(
    page: 1,
    pageSize: 50,
    total: 1,
    totalPages: 1,
    hasPrev: false,
    hasNext: false,
  ),
);

void main() {
  test('branch change sends a new request and a stale in-flight response cannot win', () async {
    final repository = _QueuedAppointmentsRepository();
    final controller = AppointmentListController(repo: repository);

    controller.selectedBranchId = 'stale-branch';
    final oldLoad = controller.loadAppointments();
    final newLoad = controller.setBranch(null);
    expect(repository.requests, ['stale-branch', null]);

    repository.pendingLists[1].complete(Ok(_page('new')));
    await newLoad;
    repository.pendingLists[0].complete(Ok(_page('old')));
    await oldLoad;

    expect(controller.listState.valueOrNull!.single.id, 'new');
    controller.dispose();
  });

  test(
    'loadMore ignores a stale in-flight page after a fresh reload starts',
    () async {
      final repository = _QueuedAppointmentsRepository();
      final controller = AppointmentListController(repo: repository);

      final firstLoad = controller.loadAppointments();
      repository.pendingLists[0].complete(
        Ok(
          PagedResult(
            items: _page('first').items,
            pagination: const PaginationMeta(
              page: 1,
              pageSize: 50,
              total: 2,
              totalPages: 1,
              hasPrev: false,
              hasNext: true,
            ),
          ),
        ),
      );
      await firstLoad;

      final staleLoadMore = controller.loadMore();
      // A fresh reload (e.g. the date changed) starts while page 2 is still
      // in flight — this bumps the generation the stale page must lose to.
      final reload = controller.loadAppointments();
      repository.pendingLists[2].complete(Ok(_page('reloaded')));
      await reload;
      repository.pendingLists[1].complete(Ok(_page('stale-page-2')));
      await staleLoadMore;

      expect(controller.listState.valueOrNull!.single.id, 'reloaded');
      controller.dispose();
    },
  );
}
