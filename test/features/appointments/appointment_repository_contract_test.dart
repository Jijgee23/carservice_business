import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/data/appointment_dto.dart';
import 'package:carservice_business/features/appointments/data/appointment_repository.dart';
import 'package:carservice_business/features/appointments/data/appointments_data_source.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_appointment_repository.dart';

/// Records the last call made through [AppointmentsDataSource] and returns a
/// canned response — lets this test assert the remote adapter never
/// expresses a mutation twice (one call in ⇒ one HTTP verb+path out) without
/// a live server.
class _RecordingSource implements AppointmentsDataSource {
  String? lastCall;
  Map<String, dynamic>? lastQuery;
  Map<String, dynamic>? lastBody;
  Object? response;
  Object? Function()? throwing;

  Future<Object?> _record(
    String name, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
  }) async {
    lastCall = name;
    lastQuery = query;
    lastBody = body;
    if (throwing != null) throwing!();
    return response;
  }

  @override
  Future<Object?> list(Map<String, dynamic> query) =>
      _record('list', query: query);
  @override
  Future<Object?> slots(Map<String, dynamic> query) =>
      _record('slots', query: query);
  @override
  Future<Object?> calendar(Map<String, dynamic> query) =>
      _record('calendar', query: query);
  @override
  Future<Object?> create(Map<String, dynamic> body) =>
      _record('create', body: body);
  @override
  Future<Object?> confirm(String id, {Map<String, dynamic>? body}) =>
      _record('confirm', body: body);
  @override
  Future<Object?> update(String id, Map<String, dynamic> body) =>
      _record('update', body: body);
  @override
  Future<Object?> detail(String id) => _record('detail');
  @override
  Future<Object?> reject(String id) => _record('reject');
  @override
  Future<Object?> noShow(String id) => _record('noShow');
  @override
  Future<Object?> arrived(String id) => _record('arrived');
  @override
  Future<Object?> cancel(String id) => _record('cancel');
  @override
  Future<Object?> reschedule(String id, Map<String, dynamic> body) =>
      _record('reschedule', body: body);
  @override
  Future<Object?> bulkCategory(Map<String, dynamic> body) =>
      _record('bulkCategory', body: body);
  @override
  Future<Object?> checkPayment(String id) => _record('checkPayment');
  @override
  Future<Object?> retryPayment(String id) => _record('retryPayment');
  @override
  Future<Object?> refundPayment(String id, Map<String, dynamic> body) =>
      _record('refundPayment', body: body);
}

AppError _err(Result<Object?> result) => (result as Err).error;

/// [AppointmentsDataSource] converts a `DioException` into [AppError] itself
/// (see `RemoteAppointmentsDataSource._toAppError`) — below the repository
/// contract, per the module doc comment. This test double sits at the
/// [AppointmentsDataSource] seam, so it throws the already-converted
/// [AppError] a real data source implementation would produce for the given
/// HTTP status, mirroring `_toAppError`'s status/code/fieldErrors mapping
/// exactly (401/403/404/500 have a fixed kind; 409/422 stay `unknown` with
/// `statusCode` as the caller-facing discriminator).
AppError _appError(int status, Map<String, dynamic> data) {
  final message = data['error'] as String?;
  final code = data['code'] as String?;
  final rawFieldErrors = data['fieldErrors'];
  final fieldErrors = rawFieldErrors is Map
      ? Map<String, String>.from(rawFieldErrors)
      : null;
  return switch (status) {
    401 => AppError(
      ErrorKind.unauthorized,
      'Нэвтрэх шаардлагатай',
      statusCode: status,
      code: code,
      fieldErrors: fieldErrors,
    ),
    403 => AppError(
      ErrorKind.forbidden,
      message ?? 'Хандах эрх байхгүй',
      statusCode: status,
      code: code,
      fieldErrors: fieldErrors,
    ),
    404 => AppError(
      ErrorKind.notFound,
      'Олдсонгүй',
      statusCode: status,
      code: code,
      fieldErrors: fieldErrors,
    ),
    500 => AppError(
      ErrorKind.server,
      'Серверийн алдаа',
      statusCode: status,
      code: code,
      fieldErrors: fieldErrors,
    ),
    _ => AppError(
      ErrorKind.unknown,
      message ?? 'Алдаа гарлаа',
      statusCode: status,
      code: code,
      fieldErrors: fieldErrors,
    ),
  };
}

void main() {
  group('AppointmentStatus — defensive parsing', () {
    test('known values round-trip', () {
      for (final status in AppointmentStatus.values) {
        if (status == AppointmentStatus.unknown) continue;
        expect(AppointmentStatus.fromJson(status.name), status);
      }
    });

    test('unknown string degrades to unknown, never throws', () {
      expect(
        AppointmentStatus.fromJson('SOME_FUTURE_STATUS'),
        AppointmentStatus.unknown,
      );
    });

    test('non-string/null degrades to unknown, never throws', () {
      expect(AppointmentStatus.fromJson(null), AppointmentStatus.unknown);
      expect(AppointmentStatus.fromJson(42), AppointmentStatus.unknown);
    });

    test('unknown status offers no transitions', () {
      expect(AppointmentStatus.unknown.nextStatuses, isEmpty);
    });
  });

  group('AppointmentSummary.fromJson — DTO tolerance fixtures', () {
    test('minimal payload with only id degrades every optional field', () {
      final appt = AppointmentSummary.fromJson({'id': 'a1'});
      expect(appt.id, 'a1');
      expect(appt.status, AppointmentStatus.unknown);
      expect(appt.requestedAt, isNull);
      expect(appt.note, isNull);
      expect(appt.createdAt, isNull);
      expect(appt.branch, isNull);
      expect(appt.category, isNull);
      expect(appt.account, isNull);
      expect(appt.customer, isNull);
      expect(appt.accountVehicle, isNull);
      expect(appt.vehicle, isNull);
      expect(appt.serviceOrder, isNull);
      expect(appt.displayName, 'Нэргүй');
    });

    test(
      'missing id throws AppointmentParseException (structurally required)',
      () {
        expect(
          () => AppointmentSummary.fromJson({'status': 'PENDING'}),
          throwsA(isA<AppointmentParseException>()),
        );
      },
    );

    test('unknown status string degrades to AppointmentStatus.unknown', () {
      final appt = AppointmentSummary.fromJson({
        'id': 'a1',
        'status': 'SOMETHING_NEW',
      });
      expect(appt.status, AppointmentStatus.unknown);
    });

    test('null requestedAt/createdAt degrade to null, no crash', () {
      final appt = AppointmentSummary.fromJson({
        'id': 'a1',
        'requestedAt': null,
        'createdAt': null,
      });
      expect(appt.requestedAt, isNull);
      expect(appt.createdAt, isNull);
    });

    test('malformed date string degrades to null rather than throwing', () {
      final appt = AppointmentSummary.fromJson({
        'id': 'a1',
        'requestedAt': 'not-a-date',
      });
      expect(appt.requestedAt, isNull);
    });

    test('missing linked order (serviceOrder absent) degrades to null', () {
      final appt = AppointmentSummary.fromJson({'id': 'a1'});
      expect(appt.serviceOrder, isNull);
    });

    test(
      'accountVehicle shaped without id (server shapeAppointment) parses',
      () {
        final appt = AppointmentSummary.fromJson({
          'id': 'a1',
          'accountVehicle': {
            'plate': '1234ABC',
            'make': 'Toyota',
            'model': 'Prius',
          },
        });
        expect(appt.accountVehicle!.id, isNull);
        expect(appt.accountVehicle!.plate, '1234ABC');
        expect(appt.displayVehicle, appt.accountVehicle);
      },
    );

    test('malformed nested ref (wrong type) degrades that ref to null', () {
      final appt = AppointmentSummary.fromJson({
        'id': 'a1',
        'branch': 'not-a-map',
      });
      expect(appt.branch, isNull);
    });

    test('displayName resolves customer > account > fallback', () {
      final customerOnly = AppointmentSummary.fromJson({
        'id': 'a1',
        'customer': {'fullName': 'Бат', 'phone': '99001122'},
      });
      expect(customerOnly.displayName, 'Бат');

      final accountOnly = AppointmentSummary.fromJson({
        'id': 'a1',
        'account': {'name': 'Болд', 'phone': '99002233'},
      });
      expect(accountOnly.displayName, 'Болд');

      final neither = AppointmentSummary.fromJson({'id': 'a1'});
      expect(neither.displayName, 'Нэргүй');
    });
  });

  group('CalendarBlock.fromJson — DTO tolerance fixtures', () {
    test('unknown issue reason degrades to CalendarIssueReason.unknown', () {
      final block = CalendarBlock.fromJson({
        'issue': {'reason': 'some-future-reason', 'label': 'x'},
      });
      expect(block.issue!.reason, CalendarIssueReason.unknown);
    });

    test('missing boolean flags default to false, never throw', () {
      final block = CalendarBlock.fromJson(const {});
      expect(block.finishKnown, isFalse);
      expect(block.endsAtDayBoundary, isFalse);
      expect(block.capacityOverflow, isFalse);
    });

    test(
      'unknown appointment status inside a block degrades, never throws',
      () {
        final block = CalendarBlock.fromJson({'status': 'FUTURE_STATUS'});
        expect(block.status, AppointmentStatus.unknown);
      },
    );
  });

  group('CalendarDayModel.fromJson — legend union tolerance', () {
    test('unknown legend kind is dropped, known entries survive', () {
      final model = CalendarDayModel.fromJson({
        'legend': [
          {'kind': 'status', 'status': 'PENDING', 'label': 'Хүлээгдэж буй'},
          {'kind': 'something-else', 'label': 'x'},
          {
            'kind': 'issue',
            'reason': 'missing-order',
            'label': 'Холбогдсон захиалга олдсонгүй',
          },
        ],
      });
      expect(model.legend, hasLength(2));
      expect(model.legend[0], isA<CalendarLegendStatus>());
      expect(model.legend[1], isA<CalendarLegendIssue>());
    });

    test('non-list blocks/legend degrade to empty lists', () {
      final model = CalendarDayModel.fromJson(const {
        'blocks': 'x',
        'legend': 'y',
      });
      expect(model.blocks, isEmpty);
      expect(model.legend, isEmpty);
    });
  });

  group(
    'RemoteAppointmentsRepository — one call per operation, correct verb/path',
    () {
      test(
        'getAppointments issues exactly one list call with server-side filters',
        () async {
          final source = _RecordingSource()
            ..response = {
              'appointments': [],
              'pagination': {
                'page': 1,
                'pageSize': 50,
                'total': 0,
                'totalPages': 0,
                'hasPrev': false,
                'hasNext': false,
              },
            };
          final repo = RemoteAppointmentsRepository(dataSource: source);
          final result = await repo.getAppointments(
            query: AppointmentListQuery(
              status: AppointmentStatus.CONFIRMED,
              branchId: 'branch-1',
              date: DateTime(2026, 9, 22),
            ),
          );
          expect(result, isA<Ok<Object?>>());
          expect(source.lastCall, 'list');
          expect(source.lastQuery!['status'], 'CONFIRMED');
          expect(source.lastQuery!['branchId'], 'branch-1');
          expect(source.lastQuery!['date'], '2026-09-22');
        },
      );

      test('getAppointments sends q trimmed when non-empty', () async {
        final source = _RecordingSource()
          ..response = {
            'appointments': [],
            'pagination': {
              'page': 1,
              'pageSize': 50,
              'total': 0,
              'totalPages': 0,
              'hasPrev': false,
              'hasNext': false,
            },
          };
        final repo = RemoteAppointmentsRepository(dataSource: source);

        await repo.getAppointments(
          query: const AppointmentListQuery(q: '  Бат  '),
        );

        expect(source.lastQuery!['q'], 'Бат');
      });

      test(
        'getAppointments omits q entirely when empty or whitespace-only',
        () async {
          final source = _RecordingSource()
            ..response = {
              'appointments': [],
              'pagination': {
                'page': 1,
                'pageSize': 50,
                'total': 0,
                'totalPages': 0,
                'hasPrev': false,
                'hasNext': false,
              },
            };
          final repo = RemoteAppointmentsRepository(dataSource: source);

          await repo.getAppointments(query: const AppointmentListQuery(q: ''));
          expect(source.lastQuery!.containsKey('q'), isFalse);

          await repo.getAppointments(
            query: const AppointmentListQuery(q: '   '),
          );
          expect(source.lastQuery!.containsKey('q'), isFalse);

          await repo.getAppointments(query: const AppointmentListQuery());
          expect(source.lastQuery!.containsKey('q'), isFalse);
        },
      );

      test('each lifecycle transition calls exactly one endpoint', () async {
        final cases =
            <
              String,
              Future<Result<Object?>> Function(RemoteAppointmentsRepository)
            >{
              'confirm': (r) => r.confirm('a1'),
              'reject': (r) => r.reject('a1'),
              'noShow': (r) => r.markNoShow('a1'),
              'arrived': (r) => r.markArrived('a1'),
              'cancel': (r) => r.cancel('a1'),
            };
        for (final entry in cases.entries) {
          final source = _RecordingSource()
            ..response = {'ok': true, 'appointmentId': 'a1', 'arrived': true};
          final repo = RemoteAppointmentsRepository(dataSource: source);
          await entry.value(repo);
          expect(
            source.lastCall,
            entry.key,
            reason: '${entry.key} must call its own endpoint only',
          );
        }
      });

      test(
        'bulkChangeCategory sends one categoryId wrapped once, not per-id',
        () async {
          final source = _RecordingSource()
            ..response = {
              'succeeded': ['a1', 'a2'],
              'failed': [],
            };
          final repo = RemoteAppointmentsRepository(dataSource: source);
          await repo.bulkChangeCategory(['a1', 'a2'], 'cat-1');
          expect(source.lastCall, 'bulkCategory');
          expect(source.lastBody!['appointmentIds'], ['a1', 'a2']);
          expect(source.lastBody!['categoryId'], 'cat-1');
        },
      );
    },
  );

  test(
    'createAppointment sends vehicleId only when a vehicle is picked',
    () async {
      final source = _RecordingSource();
      final repo = RemoteAppointmentsRepository(dataSource: source);
      final at = DateTime.now().add(const Duration(days: 1));
      await repo.createAppointment(
        branchId: 'b1',
        customerId: 'c1',
        vehicleId: 'veh-1',
        requestedAt: at,
      );
      expect(source.lastBody?['vehicleId'], 'veh-1');
      await repo.createAppointment(
        branchId: 'b1',
        customerId: 'c1',
        requestedAt: at,
      );
      expect(source.lastBody?.containsKey('vehicleId'), isFalse);
    },
  );

  test(
    'a UTC requestedAt (slot iso) is sent as Ulaanbaatar wall time',
    () async {
      // The server reads the zone-less value as +08:00, so it must be business
      // time on every device — not device-local (which shifted bookings by an
      // hour on UTC+7 phones). Holds under any TZ the test runs in.
      final source = _RecordingSource();
      final repo = RemoteAppointmentsRepository(dataSource: source);
      await repo.createAppointment(
        branchId: 'b1',
        customerId: 'c1',
        requestedAt: DateTime.parse('2026-09-25T04:30:00Z'),
      );
      expect(source.lastBody?['requestedAt'], '2026-09-25T12:30:00');
    },
  );

  group('Error mapping — 409 conflict vs 422 field errors stay distinct', () {
    test(
      '409 reservation conflict surfaces statusCode 409 and its code',
      () async {
        final source = _RecordingSource()
          ..throwing = () => throw _appError(409, {
            'error': 'Энэ цаг аль хэдийн захиалагдсан байна.',
            'code': 'RESERVATION_CONFLICT',
            'fieldErrors': {'confirmNeeded': 'true'},
          });
        final repo = RemoteAppointmentsRepository(dataSource: source);
        final result = await repo.createAppointment(
          branchId: 'b1',
          customerId: 'c1',
          requestedAt: DateTime.now().add(const Duration(days: 1)),
        );
        final error = _err(result);
        expect(error.statusCode, 409);
        expect(error.code, 'RESERVATION_CONFLICT');
        expect(error.fieldErrors, containsPair('confirmNeeded', 'true'));
      },
    );

    test(
      '422 field errors surface statusCode 422 with per-field messages',
      () async {
        final source = _RecordingSource()
          ..throwing = () => throw _appError(422, {
            'error': 'Хүсэлт буруу.',
            'fieldErrors': {'requestedAt': 'Огноо буруу.'},
          });
        final repo = RemoteAppointmentsRepository(dataSource: source);
        final result = await repo.reschedule('a1', DateTime.now());
        final error = _err(result);
        expect(error.statusCode, 422);
        expect(error.fieldErrors, containsPair('requestedAt', 'Огноо буруу.'));
      },
    );

    test(
      '409 and 422 map to different statusCodes, never collapsed into one kind',
      () async {
        final conflictSource = _RecordingSource()
          ..throwing = () => throw _appError(409, {'error': 'conflict'});
        final fieldSource = _RecordingSource()
          ..throwing = () => throw _appError(422, {
            'error': 'invalid',
            'fieldErrors': {'x': 'y'},
          });
        final conflictRepo = RemoteAppointmentsRepository(
          dataSource: conflictSource,
        );
        final fieldRepo = RemoteAppointmentsRepository(dataSource: fieldSource);
        final conflictResult = await conflictRepo.confirm('a1');
        final fieldResult = await fieldRepo.confirm('a1');
        expect(
          _err(conflictResult).statusCode,
          isNot(_err(fieldResult).statusCode),
        );
      },
    );

    test('404 maps to ErrorKind.notFound', () async {
      final source = _RecordingSource()
        ..throwing = () => throw _appError(404, {'error': 'Олдсонгүй'});
      final repo = RemoteAppointmentsRepository(dataSource: source);
      final result = await repo.confirm('missing');
      expect(_err(result).kind, ErrorKind.notFound);
    });

    test(
      '403 forbidden preserves server message (branch-scope rejection)',
      () async {
        final source = _RecordingSource()
          ..throwing = () => throw _appError(403, {
            'error': 'Зөвхөн өөрийн салбарын цаг захиалгыг удирдана.',
          });
        final repo = RemoteAppointmentsRepository(dataSource: source);
        final result = await repo.reject('a1');
        final error = _err(result);
        expect(error.kind, ErrorKind.forbidden);
        expect(error.message, 'Зөвхөн өөрийн салбарын цаг захиалгыг удирдана.');
      },
    );
  });

  group('FakeAppointmentRepository — mirrors server constraints', () {
    late FakeAppointmentRepository repo;

    setUp(() {
      repo = FakeAppointmentRepository();
    });

    test(
      'rejects a transition outside APPOINTMENT_STATUS_TRANSITIONS as a 409',
      () async {
        // Seed is PENDING; NO_SHOW is only reachable from CONFIRMED.
        final result = await repo.markNoShow('appt-1');
        expect(result, isA<Err<Object?>>());
        expect(_err(result).statusCode, 409);
      },
    );

    test(
      'allows the PENDING → CONFIRMED transition the matrix permits',
      () async {
        final result = await repo.confirm('appt-1');
        expect(result, isA<Ok<Object?>>());
      },
    );

    test('rejects arrived on a non-CONFIRMED appointment', () async {
      final result = await repo.markArrived('appt-1'); // still PENDING
      expect(result, isA<Err<Object?>>());
      expect(_err(result).statusCode, 422);
    });

    test(
      'rejects createAppointment with a past requestedAt as 422 field error',
      () async {
        final result = await repo.createAppointment(
          branchId: 'b1',
          customerId: 'c1',
          requestedAt: DateTime.now().subtract(const Duration(days: 1)),
        );
        expect(result, isA<Err<Object?>>());
        final error = _err(result);
        expect(error.statusCode, 422);
        expect(error.fieldErrors, contains('requestedAt'));
      },
    );

    test(
      'rejects a double-booked slot as a 409 conflict unless confirmed',
      () async {
        final requestedAt = DateTime.now().add(const Duration(days: 1));
        final first = await repo.createAppointment(
          branchId: 'b1',
          customerId: 'c1',
          requestedAt: requestedAt,
        );
        expect(first, isA<Ok<Object?>>());
        final second = await repo.createAppointment(
          branchId: 'b1',
          customerId: 'c2',
          requestedAt: requestedAt,
        );
        expect(second, isA<Err<Object?>>());
        expect(_err(second).statusCode, 409);

        final overridden = await repo.createAppointment(
          branchId: 'b1',
          customerId: 'c2',
          requestedAt: requestedAt,
          confirmed: true,
        );
        expect(overridden, isA<Ok<Object?>>());
      },
    );

    test('bulkChangeCategory rejects an empty id list', () async {
      final result = await repo.bulkChangeCategory([], 'cat-1');
      expect(result, isA<Err<Object?>>());
    });

    test(
      'bulkChangeCategory rejects a list past MAX_BULK_APPOINTMENT_IDS',
      () async {
        final ids = List.generate(
          FakeAppointmentRepository.maxBulkAppointmentIds + 1,
          (i) => 'a$i',
        );
        final result = await repo.bulkChangeCategory(ids, 'cat-1');
        expect(result, isA<Err<Object?>>());
      },
    );

    test(
      'bulkChangeCategory rejects a duplicate id in the same request',
      () async {
        final result = await repo.bulkChangeCategory([
          'appt-1',
          'appt-1',
        ], 'cat-1');
        expect(result, isA<Err<Object?>>());
      },
    );

    test('bulkChangeCategory reports partial success — one bad id never aborts the batch', () async {
      final result = await repo.bulkChangeCategory([
        'appt-1',
        'missing-id',
      ], 'cat-1');
      expect(result, isA<Ok<Object?>>());
      final ok = (result as Ok<AppointmentBulkResult>).value;
      expect(ok.succeeded, ['appt-1']);
      expect(ok.failed, hasLength(1));
      expect(ok.failed.first.appointmentId, 'missing-id');
      expect(ok.failed.first.code, 'APPOINTMENT_NOT_FOUND');
    });

    test(
      'refundPayment requires a non-empty note (422 REFUND_NOTE_REQUIRED)',
      () async {
        final result = await repo.refundPayment('appt-1', note: '');
        expect(result, isA<Err<Object?>>());
        expect(_err(result).code, 'REFUND_NOTE_REQUIRED');
      },
    );

    test('refundPayment rejects a second refund of the same payment', () async {
      final first = await repo.refundPayment('appt-1', note: 'сав гэмтсэн');
      expect(first, isA<Ok<Object?>>());
      final second = await repo.refundPayment('appt-1', note: 'дахин оролдъё');
      expect(second, isA<Err<Object?>>());
      expect(_err(second).code, 'PAYMENT_ALREADY_REFUNDED');
    });
  });

  group('Envelope DTOs — bulk/lifecycle/reschedule parsing', () {
    test('AppointmentBulkResultDto parses succeeded/failed rows', () {
      final dto = AppointmentBulkResultDto.fromJson({
        'succeeded': ['a1'],
        'failed': [
          {
            'appointmentId': 'a2',
            'code': 'APPOINTMENT_NOT_FOUND',
            'message': 'олдсонгүй',
          },
        ],
      });
      expect(dto.value.succeeded, ['a1']);
      expect(dto.value.failed.single.appointmentId, 'a2');
    });

    test(
      'AppointmentLifecycleResultDto falls back to the caller-supplied status',
      () {
        final dto = AppointmentLifecycleResultDto.fromJson({
          'ok': true,
          'appointmentId': 'a1',
        }, fallbackStatus: AppointmentStatus.CONFIRMED);
        expect(dto.value.status, AppointmentStatus.CONFIRMED);
      },
    );

    test('AppointmentRescheduleResultDto requires a valid requestedAt', () {
      expect(
        () => AppointmentRescheduleResultDto.fromJson({
          'appointmentId': 'a1',
          'linked': false,
          'requestedAt': 'not-a-date',
        }),
        throwsA(isA<AppointmentParseException>()),
      );
    });
  });

  group('AppointmentMonthCountsDto.fromJson — month dot-counts (P2-F1b)', () {
    test('a day with multiple appointments is counted, not deduped', () {
      final dto = AppointmentMonthCountsDto.fromJson({
        'dates': ['2026-09-05', '2026-09-05', '2026-09-05', '2026-09-22'],
      });
      expect(dto.counts[DateTime(2026, 9, 5)], 3);
      expect(dto.counts[DateTime(2026, 9, 22)], 1);
      expect(dto.counts.length, 2);
    });

    test('an empty month yields an empty map, not an error', () {
      final dto = AppointmentMonthCountsDto.fromJson({'dates': <String>[]});
      expect(dto.counts, isEmpty);
    });

    test('a non-string or unparseable entry is skipped, never throws', () {
      final dto = AppointmentMonthCountsDto.fromJson({
        'dates': [
          '2026-09-05',
          42,
          null,
          'not-a-date',
          '2026-13-40',
          {'not': 'a string'},
          '2026-09-05',
        ],
      });
      expect(dto.counts, {DateTime(2026, 9, 5): 2});
    });

    test('a structurally missing/non-list dates field throws', () {
      expect(
        () => AppointmentMonthCountsDto.fromJson({'dates': 'not-a-list'}),
        throwsA(isA<AppointmentParseException>()),
      );
      expect(
        () => AppointmentMonthCountsDto.fromJson({}),
        throwsA(isA<AppointmentParseException>()),
      );
    });
  });

  group('RemoteAppointmentsRepository.getMonthCounts', () {
    test('issues one list call with month (and branchId when given), and aggregates', () async {
      final source = _RecordingSource()
        ..response = {
          'dates': ['2026-09-05', '2026-09-05', '2026-09-22'],
        };
      final repo = RemoteAppointmentsRepository(dataSource: source);

      final result = await repo.getMonthCounts(
        branchId: 'branch-1',
        month: DateTime(2026, 9),
      );

      expect(source.lastCall, 'list');
      expect(source.lastQuery!['month'], '2026-09');
      expect(source.lastQuery!['branchId'], 'branch-1');
      expect(result, isA<Ok<Object?>>());
      final counts = (result as Ok<Map<DateTime, int>>).value;
      expect(counts[DateTime(2026, 9, 5)], 2);
      expect(counts[DateTime(2026, 9, 22)], 1);
    });

    test('omits branchId when not given', () async {
      final source = _RecordingSource()..response = {'dates': <String>[]};
      final repo = RemoteAppointmentsRepository(dataSource: source);

      await repo.getMonthCounts(month: DateTime(2026, 9));

      expect(source.lastQuery!.containsKey('branchId'), isFalse);
    });

    test('a malformed response maps to an Err, not a throw', () async {
      final source = _RecordingSource()..response = {'dates': 'oops'};
      final repo = RemoteAppointmentsRepository(dataSource: source);

      final result = await repo.getMonthCounts(month: DateTime(2026, 9));

      expect(result, isA<Err<Object?>>());
    });
  });

  group(
    'FakeAppointmentRepository.getMonthCounts — mirrors server grouping',
    () {
      test(
        'derives counts from its own seeded appointments, not a hardcoded map',
        () async {
          final repo = FakeAppointmentRepository(
            seed: [
              AppointmentSummary(
                id: 'a1',
                status: AppointmentStatus.CONFIRMED,
                requestedAt: DateTime(2026, 9, 5, 9),
                branch: const AppointmentBranchRef(id: 'branch-1'),
              ),
              AppointmentSummary(
                id: 'a2',
                status: AppointmentStatus.PENDING,
                requestedAt: DateTime(2026, 9, 5, 14),
                branch: const AppointmentBranchRef(id: 'branch-1'),
              ),
              AppointmentSummary(
                id: 'a3',
                status: AppointmentStatus.CONFIRMED,
                requestedAt: DateTime(2026, 9, 22, 10),
                branch: const AppointmentBranchRef(id: 'branch-2'),
              ),
              // Different month — must not leak into the September count.
              AppointmentSummary(
                id: 'a4',
                status: AppointmentStatus.CONFIRMED,
                requestedAt: DateTime(2026, 10, 1, 10),
                branch: const AppointmentBranchRef(id: 'branch-1'),
              ),
            ],
          );

          final result = await repo.getMonthCounts(month: DateTime(2026, 9));
          expect(result, isA<Ok<Object?>>());
          final counts = (result as Ok<Map<DateTime, int>>).value;
          expect(counts[DateTime(2026, 9, 5)], 2);
          expect(counts[DateTime(2026, 9, 22)], 1);
          expect(counts.containsKey(DateTime(2026, 10, 1)), isFalse);
        },
      );

      test('scopes by branchId when given', () async {
        final repo = FakeAppointmentRepository(
          seed: [
            AppointmentSummary(
              id: 'a1',
              status: AppointmentStatus.CONFIRMED,
              requestedAt: DateTime(2026, 9, 5, 9),
              branch: const AppointmentBranchRef(id: 'branch-1'),
            ),
            AppointmentSummary(
              id: 'a2',
              status: AppointmentStatus.CONFIRMED,
              requestedAt: DateTime(2026, 9, 5, 9),
              branch: const AppointmentBranchRef(id: 'branch-2'),
            ),
          ],
        );

        final result = await repo.getMonthCounts(
          branchId: 'branch-1',
          month: DateTime(2026, 9),
        );
        final counts = (result as Ok<Map<DateTime, int>>).value;
        expect(counts, {DateTime(2026, 9, 5): 1});
      });

      test('a month with no appointments returns an empty map', () async {
        final repo = FakeAppointmentRepository(seed: const []);
        final result = await repo.getMonthCounts(month: DateTime(2026, 11));
        final counts = (result as Ok<Map<DateTime, int>>).value;
        expect(counts, isEmpty);
      });
    },
  );
}
