import 'dart:async';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/appointment_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_appointment_repository.dart';

/// Records each `q` sent and holds every response open on a [Completer],
/// mirroring `_QueuedAppointmentsRepository` in
/// `appointment_controller_race_test.dart` (same Completer-based race
/// technique, scoped to `q` instead of `branchId`).
class _QueuedSearchRepository implements AppointmentsRepository {
  final requestedTerms = <String?>[];
  final pending = <Completer<Result<PagedResult<AppointmentSummary>>>>[];

  @override
  Future<Result<PagedResult<AppointmentSummary>>> getAppointments({
    AppointmentListQuery? query,
  }) {
    requestedTerms.add(query?.q);
    final completer = Completer<Result<PagedResult<AppointmentSummary>>>();
    pending.add(completer);
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

PagedResult<AppointmentSummary> _qPage(String id) => PagedResult(
  items: [
    AppointmentSummary(
      id: id,
      status: AppointmentStatus.PENDING,
      requestedAt: DateTime(2026, 1, 1, 9),
      branch: const AppointmentBranchRef(id: 'branch'),
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

AppointmentSummary _appt(
  String id, {
  AppointmentStatus status = AppointmentStatus.PENDING,
  DateTime? requestedAt,
  String branchId = 'branch-1',
}) {
  // Filtering happens server-side against `AppointmentListController`'s
  // selected day, which defaults to the real "today" — anchor every fixture
  // to the actual current day (rather than a fixed 2026 date) so these
  // tests do not depend on the machine clock matching a hardcoded date.
  final now = DateTime.now();
  return AppointmentSummary(
    id: id,
    status: status,
    requestedAt: requestedAt ?? DateTime(now.year, now.month, now.day, 10),
    createdAt: DateTime(now.year, now.month, now.day, 9),
    branch: AppointmentBranchRef(id: branchId),
    customer: const AppointmentCustomerRef(id: 'cust-1', fullName: 'Бат'),
  );
}

void main() {
  group('AppointmentListController — filters and pagination', () {
    test(
      'setStatusFilter reloads with the server-side status filter',
      () async {
        final repo = FakeAppointmentRepository(
          seed: [
            _appt('a1', status: AppointmentStatus.PENDING),
            _appt('a2', status: AppointmentStatus.CONFIRMED),
          ],
        );
        final controller = AppointmentListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );
        await controller.loadAppointments();
        expect(controller.filtered, hasLength(2));

        await controller.setStatusFilter(AppointmentStatus.CONFIRMED);

        expect(controller.filtered.map((a) => a.id), ['a2']);
        controller.dispose();
      },
    );

    test('setBranch reloads scoped to the branch', () async {
      final repo = FakeAppointmentRepository(
        seed: [
          _appt('a1', branchId: 'branch-1'),
          _appt('a2', branchId: 'branch-2'),
        ],
      );
      final controller = AppointmentListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.setBranch('branch-2');

      expect(controller.filtered.map((a) => a.id), ['a2']);
      controller.dispose();
    });

    test(
      'filter reset (status/branch cleared) restores the full page',
      () async {
        final repo = FakeAppointmentRepository(
          seed: [
            _appt('a1', status: AppointmentStatus.PENDING),
            _appt('a2', status: AppointmentStatus.CONFIRMED),
          ],
        );
        final controller = AppointmentListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );
        await controller.setStatusFilter(AppointmentStatus.CONFIRMED);
        expect(controller.filtered, hasLength(1));

        await controller.setStatusFilter(null);

        expect(controller.filtered, hasLength(2));
        controller.dispose();
      },
    );

    test(
      'applyFilters sets branch/status/group with a single reload',
      () async {
        final repo = FakeAppointmentRepository(
          seed: [
            _appt('a1', status: AppointmentStatus.PENDING, branchId: 'b1'),
            _appt('a2', status: AppointmentStatus.CANCELLED, branchId: 'b1'),
            _appt('a3', status: AppointmentStatus.CANCELLED, branchId: 'b2'),
          ],
        );
        final controller = AppointmentListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );

        await controller.applyFilters(
          branchId: 'b1',
          status: null,
          statusGroup: const {
            AppointmentStatus.REJECTED,
            AppointmentStatus.NO_SHOW,
            AppointmentStatus.CANCELLED,
          },
        );
        expect(controller.selectedBranchId, 'b1');
        expect(controller.statusGroup, hasLength(3));
        expect(controller.filtered.map((a) => a.id), ['a2']);

        // A single status wins over the group it narrows.
        await controller.applyFilters(
          branchId: null,
          status: AppointmentStatus.CANCELLED,
          statusGroup: const {AppointmentStatus.CANCELLED},
        );
        expect(controller.statusFilter, AppointmentStatus.CANCELLED);
        expect(controller.statusGroup, isNull);
        // The default every-date list is newest first: the server's
        // ascending page, reversed.
        expect(controller.filtered.map((a) => a.id), ['a3', 'a2']);
        controller.dispose();
      },
    );

    test('changing the filter clears any existing selection', () async {
      final repo = FakeAppointmentRepository(
        seed: [
          _appt('a1', status: AppointmentStatus.PENDING),
          _appt('a2', status: AppointmentStatus.PENDING),
        ],
      );
      final controller = AppointmentListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadAppointments();
      controller.enterSelectionMode('a1');
      expect(controller.selectedCount, 1);

      await controller.setStatusFilter(AppointmentStatus.CONFIRMED);

      expect(controller.selectedCount, 0);
      expect(controller.selectionMode, isFalse);
      controller.dispose();
    });
  });

  group('AppointmentListController — touch-native selection', () {
    late FakeAppointmentRepository repo;
    late AppointmentListController controller;

    setUp(() async {
      repo = FakeAppointmentRepository(
        seed: [_appt('a1'), _appt('a2'), _appt('a3'), _appt('a4')],
      );
      controller = AppointmentListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadAppointments();
    });

    tearDown(() => controller.dispose());

    test('enterSelectionMode is the discoverable long-press entry point', () {
      expect(controller.selectionMode, isFalse);

      controller.enterSelectionMode('a2');

      expect(controller.selectionMode, isTrue);
      expect(controller.isSelected('a2'), isTrue);
      expect(controller.selectedCount, 1);
    });

    test('toggleSelection is a no-op before selection mode is entered', () {
      controller.toggleSelection('a1');

      expect(controller.selectionMode, isFalse);
      expect(controller.selectedCount, 0);
    });

    test('toggleSelection adds/removes once in selection mode', () {
      controller.enterSelectionMode('a1');
      controller.toggleSelection('a2');
      expect(controller.selectedCount, 2);

      controller.toggleSelection('a2');
      expect(controller.selectedCount, 1);
      expect(controller.isSelected('a2'), isFalse);
    });

    test('selectAllVisible selects exactly the rendered page and live count updates', () {
      controller.selectAllVisible();

      expect(controller.selectedCount, 4);
      expect(controller.selectedIds, {'a1', 'a2', 'a3', 'a4'});
    });

    test('clearSelection exits selection mode entirely', () {
      controller.selectAllVisible();

      controller.clearSelection();

      expect(controller.selectionMode, isFalse);
      expect(controller.selectedCount, 0);
    });

    test('range select: arm then tap selects the contiguous visible run', () {
      controller.enterSelectionMode('a1'); // anchor = a1
      controller.armRangeSelect();
      expect(controller.rangeSelectArmed, isTrue);

      controller.applyRangeSelectTap('a3');

      expect(controller.rangeSelectArmed, isFalse);
      expect(controller.selectedIds, {'a1', 'a2', 'a3'});
    });

    test('range select works selecting backwards from a later anchor', () {
      controller.enterSelectionMode('a3');
      controller.armRangeSelect();

      controller.applyRangeSelectTap('a1');

      expect(controller.selectedIds, {'a1', 'a2', 'a3'});
    });
  });

  group('AppointmentListController — bulk category', () {
    test(
      'partial failure is surfaced then the list reloads authoritatively',
      () async {
        final repo = FakeAppointmentRepository(
          seed: [
            _appt('a1'),
            AppointmentSummary(
              id: 'linked',
              status: AppointmentStatus.CONFIRMED,
              requestedAt: DateTime.now(),
              branch: const AppointmentBranchRef(id: 'branch-1'),
              serviceOrder: const AppointmentOrderRef(id: 'order-1', number: 1),
            ),
          ],
        );
        final controller = AppointmentListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );
        await controller.loadAppointments();
        controller.enterSelectionMode('a1');
        controller.toggleSelection('linked');
        expect(controller.selectedCount, 2);

        final result = await controller.bulkChangeCategory('cat-2');

        expect(result, isNotNull);
        expect(result!.succeeded, ['a1']);
        expect(result.failed, hasLength(1));
        expect(result.failed.single.appointmentId, 'linked');
        // Authoritative reload happened — selection cleared and the list
        // reflects the server's post-mutation state, not a client patch.
        expect(controller.selectionMode, isFalse);
        expect(controller.selectedCount, 0);
        expect(
          controller.filtered.firstWhere((a) => a.id == 'a1').category?.id,
          'cat-2',
        );
        controller.dispose();
      },
    );

    test('bulk category on an empty selection is a no-op', () async {
      final repo = FakeAppointmentRepository(seed: [_appt('a1')]);
      final controller = AppointmentListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadAppointments();

      final result = await controller.bulkChangeCategory('cat-2');

      expect(result, isNull);
      controller.dispose();
    });
  });

  group('AppointmentListController — search (q)', () {
    AppointmentSummary withAccount(
      String id, {
      String name = 'Болд',
      String phone = '99001122',
    }) {
      final now = DateTime.now();
      return AppointmentSummary(
        id: id,
        status: AppointmentStatus.PENDING,
        requestedAt: DateTime(now.year, now.month, now.day, 10),
        branch: const AppointmentBranchRef(id: 'branch-1'),
        account: AppointmentAccountRef(name: name, phone: phone),
      );
    }

    test(
      'setQuery debounces then reloads filtered to the matching term',
      () async {
        final repo = FakeAppointmentRepository(
          seed: [
            withAccount('a1', name: 'Болд Ганбат'),
            withAccount('a2', name: 'Мөнх'),
          ],
        );
        final controller = AppointmentListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );
        await controller.loadAppointments();
        expect(controller.filtered, hasLength(2));

        controller.setQuery('Ганбат');
        // Not yet reloaded — the debounce timer has not fired.
        expect(controller.filtered, hasLength(2));

        await pumpEventQueue();

        expect(controller.filtered.map((a) => a.id), ['a1']);
        controller.dispose();
      },
    );

    test('searching resets pagination to the first page', () async {
      final repo = FakeAppointmentRepository(
        seed: List.generate(
          AppointmentListController.defaultPageSize + 1,
          (i) => withAccount('a$i'),
        ),
      );
      final controller = AppointmentListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadAppointments();
      await controller.loadMore();
      expect(controller.page, 2);

      controller.setQuery('Болд');
      await pumpEventQueue();

      expect(controller.page, 1);
      controller.dispose();
    });

    test('the search term persists across pagination and refresh', () async {
      final repo = FakeAppointmentRepository(
        seed: [
          withAccount('a1', name: 'Болд'),
          withAccount('a2', name: 'Мөнх'),
        ],
      );
      final controller = AppointmentListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadAppointments();
      controller.setQuery('Болд');
      await pumpEventQueue();
      expect(controller.filtered.map((a) => a.id), ['a1']);

      await controller.loadMore();
      expect(controller.filtered.map((a) => a.id), ['a1']);

      await controller.refresh();
      expect(controller.filtered.map((a) => a.id), ['a1']);
      expect(controller.query, 'Болд');
      controller.dispose();
    });

    test('clearing the search restores the unfiltered list', () async {
      final repo = FakeAppointmentRepository(
        seed: [
          withAccount('a1', name: 'Болд'),
          withAccount('a2', name: 'Мөнх'),
        ],
      );
      final controller = AppointmentListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadAppointments();
      controller.setQuery('Болд');
      await pumpEventQueue();
      expect(controller.filtered, hasLength(1));

      controller.setQuery('');
      await pumpEventQueue();

      expect(controller.filtered, hasLength(2));
      expect(controller.query, '');
      controller.dispose();
    });

    test(
      'search composes with the existing status/branch/date filters',
      () async {
        final repo = FakeAppointmentRepository(
          seed: [
            withAccount('a1', name: 'Болд'),
            AppointmentSummary(
              id: 'a2',
              status: AppointmentStatus.CONFIRMED,
              requestedAt: DateTime.now(),
              branch: const AppointmentBranchRef(id: 'branch-1'),
              account: const AppointmentAccountRef(name: 'Болд'),
            ),
          ],
        );
        final controller = AppointmentListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );
        await controller.setStatusFilter(AppointmentStatus.CONFIRMED);

        controller.setQuery('Болд');
        await pumpEventQueue();

        expect(controller.filtered.map((a) => a.id), ['a2']);
        controller.dispose();
      },
    );

    test('setQuery clears any existing selection', () async {
      final repo = FakeAppointmentRepository(
        seed: [withAccount('a1'), withAccount('a2')],
      );
      final controller = AppointmentListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadAppointments();
      controller.enterSelectionMode('a1');
      expect(controller.selectedCount, 1);

      controller.setQuery('x');

      expect(controller.selectedCount, 0);
      expect(controller.selectionMode, isFalse);
      controller.dispose();
    });
  });

  group(
    'AppointmentListController — search stale-response race (Completer-based)',
    () {
      test(
        'a slow response for an old search term never overwrites a newer term',
        () async {
          final repo = _QueuedSearchRepository();
          final controller = AppointmentListController(
            repo: repo,
            searchDebounce: Duration.zero,
          );

          controller.setQuery('old');
          await pumpEventQueue();
          controller.setQuery('new');
          await pumpEventQueue();
          expect(repo.requestedTerms, ['old', 'new']);

          repo.pending[1].complete(Ok(_qPage('new-result')));
          repo.pending[0].complete(Ok(_qPage('old-result')));
          await pumpEventQueue();

          expect(controller.listState.valueOrNull!.single.id, 'new-result');
          controller.dispose();
        },
      );
    },
  );

  group('AppointmentListController — load-more generation guard', () {
    test(
      'loadMore appends the next page and preserves selection semantics',
      () async {
        final repo = FakeAppointmentRepository(
          seed: List.generate(
            AppointmentListController.defaultPageSize + 1,
            (i) => _appt('a$i'),
          ),
        );
        final controller = AppointmentListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );
        // A picked day pages by `defaultPageSize`.
        await controller.setDate(DateTime.now());
        expect(controller.hasNext, isTrue);
        expect(
          controller.filtered,
          hasLength(AppointmentListController.defaultPageSize),
        );

        await controller.loadMore();

        expect(controller.hasNext, isFalse);
        expect(
          controller.filtered,
          hasLength(AppointmentListController.defaultPageSize + 1),
        );
        controller.dispose();
      },
    );
  });

  group('AppointmentListController — default every-date list', () {
    // `d0` is today and `d<i>` is i days ago, seeded oldest first — the
    // order `GET /appointments` returns.
    List<AppointmentSummary> daysAgo(
      int count, {
      AppointmentStatus Function(int i)? status,
    }) => [
      for (var i = count - 1; i >= 0; i--)
        _appt(
          'd$i',
          status: status?.call(i) ?? AppointmentStatus.PENDING,
          requestedAt: DateTime.now().subtract(Duration(days: i)),
        ),
    ];

    List<String> ids(AppointmentListController c) =>
        c.filtered.map((a) => a.id).toList();

    test('pages every date newest first, 10 at a time', () async {
      final controller = AppointmentListController(
        repo: FakeAppointmentRepository(seed: daysAgo(25)),
        searchDebounce: Duration.zero,
      );
      await controller.loadAppointments();

      expect(controller.allDates, isTrue);
      expect(controller.total, 25);
      expect(controller.hasNext, isTrue);
      expect(ids(controller), [for (var i = 0; i < 10; i++) 'd$i']);

      await controller.loadMore();
      expect(ids(controller), [for (var i = 0; i < 20; i++) 'd$i']);

      await controller.loadMore();
      expect(ids(controller), [for (var i = 0; i < 25; i++) 'd$i']);
      expect(controller.hasNext, isFalse);
      controller.dispose();
    });

    test('a status group merges its statuses newest first, paged', () async {
      final controller = AppointmentListController(
        repo: FakeAppointmentRepository(
          seed: daysAgo(
            30,
            status: (i) => switch (i % 3) {
              0 => AppointmentStatus.CONFIRMED,
              1 => AppointmentStatus.PENDING,
              _ => AppointmentStatus.CANCELLED,
            },
          ),
        ),
        searchDebounce: Duration.zero,
      );
      await controller.applyFilters(
        branchId: null,
        status: null,
        statusGroup: const {
          AppointmentStatus.PENDING,
          AppointmentStatus.CONFIRMED,
        },
      );
      final open = [
        for (var i = 0; i < 30; i++)
          if (i % 3 != 2) 'd$i',
      ];

      expect(controller.total, 20);
      expect(ids(controller), open.take(10));
      expect(controller.hasNext, isTrue);

      await controller.loadMore();
      expect(ids(controller), open);
      expect(controller.hasNext, isFalse);
      controller.dispose();
    });

    test('a picked day lists only that day; showAllDates returns', () async {
      final controller = AppointmentListController(
        repo: FakeAppointmentRepository(seed: daysAgo(12)),
        searchDebounce: Duration.zero,
      );
      await controller.loadAppointments();

      await controller.setDate(DateTime.now().subtract(const Duration(days: 3)));
      expect(controller.allDates, isFalse);
      expect(ids(controller), ['d3']);

      await controller.showAllDates();
      expect(controller.allDates, isTrue);
      expect(ids(controller), [for (var i = 0; i < 10; i++) 'd$i']);
      controller.dispose();
    });
  });
}
