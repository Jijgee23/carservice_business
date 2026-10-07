import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_repository.dart';
import 'package:carservice_business/features/vehicles/data/vehicles_data_source.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// P3-F1 — `RemoteVehiclesRepository` request/response contract, exercised
/// over a recording data source. No network, no Dio: the transport seam is
/// exactly what this substitutes.
void main() {
  group('request shaping', () {
    test('the list query sends only allow-listed params', () async {
      final ds = _RecordingDataSource(_listPayload);
      await RemoteVehiclesRepository(dataSource: ds).getVehicles(
        query: const VehicleListQuery(
          q: '  Бат  ',
          assigned: true,
          postpaid: false,
          page: 2,
          pageSize: 25,
        ),
      );

      expect(ds.lastQuery, {
        'page': 2,
        'pageSize': 25,
        'q': 'Бат',
        'assigned': 'yes',
        'postpaid': 'no',
      });
      // `rejectUnknownParams` 400s on anything outside the allow-list, and
      // `limit` is the legacy alias this client never sends.
      expect(ds.lastQuery!.keys, isNot(contains('limit')));
    });

    test('an empty or whitespace q is omitted entirely', () async {
      for (final term in ['', '   ']) {
        final ds = _RecordingDataSource(_listPayload);
        await RemoteVehiclesRepository(dataSource: ds)
            .getVehicles(query: VehicleListQuery(q: term));
        expect(ds.lastQuery!.containsKey('q'), isFalse);
      }
    });

    test(
      'the default query is page 1 / pageSize 50 and nothing else',
      () async {
        final ds = _RecordingDataSource(_listPayload);
        await RemoteVehiclesRepository(dataSource: ds).getVehicles();
        expect(ds.lastQuery, {'page': 1, 'pageSize': 50});
      },
    );

    test('create sends only the seven keys the POST route reads', () async {
      final ds = _RecordingDataSource({
        'vehicle': {'id': 'veh-9', 'plate': '1234 УБА'},
      });
      await RemoteVehiclesRepository(dataSource: ds).createVehicle(
        plate: '1234 УБА',
        make: 'Toyota',
        model: 'Prius 30',
        customerId: 'cust-1',
      );

      expect(ds.lastBody, {
        'plate': '1234 УБА',
        'make': 'Toyota',
        'model': 'Prius 30',
        'customerId': 'cust-1',
      });
      expect(ds.lastBody!.keys, isNot(contains('fuelType')));
      expect(ds.lastBody!.keys, isNot(contains('isPostpaid')));
    });

    test(
      'update sends explicit nulls — it replaces, it does not merge',
      () async {
        final ds = _RecordingDataSource({
          'vehicle': {'id': 'veh-1'},
        });
        await RemoteVehiclesRepository(dataSource: ds).updateVehicle(
          'veh-1',
          plate: '1234 УБА',
          make: 'Toyota',
          model: 'Prius 30',
        );

        expect(ds.lastBody!['vin'], isNull);
        expect(ds.lastBody!.containsKey('vin'), isTrue);
        expect(ds.lastBody!.containsKey('ownerRegnum'), isTrue);
        expect(ds.lastBody!.containsKey('customerId'), isTrue);
        // `isPostpaid` is the exception: omitted means "leave it".
        expect(ds.lastBody!.containsKey('isPostpaid'), isFalse);
        expect(ds.lastId, 'veh-1');
      },
    );

    test(
      'update passes isPostpaid through when the caller has an opinion',
      () async {
        final ds = _RecordingDataSource({
          'vehicle': {'id': 'veh-1'},
        });
        await RemoteVehiclesRepository(dataSource: ds).updateVehicle(
          'veh-1',
          plate: '1234 УБА',
          make: 'Toyota',
          model: 'Prius 30',
          isPostpaid: true,
        );
        expect(ds.lastBody!['isPostpaid'], isTrue);
      },
    );
  });

  group('response handling', () {
    test('getVehicles unwraps items and pagination', () async {
      final result = await RemoteVehiclesRepository(
        dataSource: _RecordingDataSource(_listPayload),
      ).getVehicles();

      final page = (result as Ok).value;
      expect(page.items.single.id, 'veh-1');
      expect(page.pagination.pageSize, 50);
    });

    test(
      'createVehicle reports the link owner, not the requested one',
      () async {
        final ds = _RecordingDataSource({
          'vehicle': {
            'id': 'veh-9',
            'plate': '1234 УБА',
            'customerId': 'cust-OTHER',
          },
        });
        final result = await RemoteVehiclesRepository(dataSource: ds)
            .createVehicle(
              plate: '1234 УБА',
              make: 'Toyota',
              model: 'Prius 30',
              customerId: 'cust-REQUESTED',
            );

        expect((result as Ok).value.customerId, 'cust-OTHER');
      },
    );

    test('a parse failure becomes Err, never a thrown exception', () async {
      final result = await RemoteVehiclesRepository(
        dataSource: _RecordingDataSource({'wrong': 'envelope'}),
      ).getVehicles();

      expect(result, isA<Err>());
      expect((result as Err).error.kind, ErrorKind.unknown);
    });

    test(
      'an AppError from the shared mapper passes through verbatim',
      () async {
        const mapped = AppError(
          ErrorKind.unknown,
          'Хүсэлт буруу.',
          statusCode: 422,
          code: 'PLAN_LIMIT_REACHED',
        );
        final result = await RemoteVehiclesRepository(
          dataSource: _ThrowingDataSource(mapped),
        ).createVehicle(plate: 'X', make: 'Y', model: 'Z');

        final error = (result as Err).error;
        expect(identical(error, mapped), isTrue);
        expect(error.statusCode, 422);
        expect(error.code, 'PLAN_LIMIT_REACHED');
      },
    );

    test('a 409 VEHICLE_IN_USE keeps its status and code on delete', () async {
      const mapped = AppError(
        ErrorKind.unknown,
        'Засварын хуудас байна.',
        statusCode: 409,
        code: 'VEHICLE_IN_USE',
      );
      final result = await RemoteVehiclesRepository(
        dataSource: _ThrowingDataSource(mapped),
      ).deleteVehicle('veh-1');

      final error = (result as Err).error;
      expect(error.statusCode, 409);
      expect(error.code, 'VEHICLE_IN_USE');
    });

    test('a 502 HUR failure is an Err, not a crash', () async {
      const mapped = AppError(ErrorKind.unknown, 'ХУР алдаа', statusCode: 502);
      final result = await RemoteVehiclesRepository(
        dataSource: _ThrowingDataSource(mapped),
      ).refreshFromHur('veh-1');

      expect((result as Err).error.statusCode, 502);
    });

    test('getHistory unwraps the four-key envelope', () async {
      final result = await RemoteVehiclesRepository(
        dataSource: _RecordingDataSource({
          'orders': const [],
          'appointments': const [],
          'diagnosticReportCount': 4,
          'ownerLocked': true,
        }),
      ).getHistory('veh-1');

      final history = (result as Ok).value;
      expect(history.diagnosticReportCount, 4);
      expect(history.ownerLocked, isTrue);
    });
  });
}

const _listPayload = {
  'vehicles': [
    {'id': 'veh-1', 'plate': '1234 УБА'},
  ],
  'pagination': {
    'page': 1,
    'pageSize': 50,
    'total': 1,
    'totalPages': 1,
    'hasPrev': false,
    'hasNext': false,
  },
};

class _RecordingDataSource implements VehiclesDataSource {
  _RecordingDataSource(this.payload);

  final Object? payload;
  Map<String, dynamic>? lastQuery;
  Map<String, dynamic>? lastBody;
  String? lastId;

  @override
  Future<Object?> list(Map<String, dynamic> query) async {
    lastQuery = query;
    return payload;
  }

  @override
  Future<Object?> detail(String id) async {
    lastId = id;
    return payload;
  }

  @override
  Future<Object?> create(Map<String, dynamic> body) async {
    lastBody = body;
    return payload;
  }

  @override
  Future<Object?> update(String id, Map<String, dynamic> body) async {
    lastId = id;
    lastBody = body;
    return payload;
  }

  @override
  Future<Object?> delete(String id) async {
    lastId = id;
    return payload;
  }

  @override
  Future<Object?> history(String id) async {
    lastId = id;
    return payload;
  }

  @override
  Future<Object?> vinHistory(String id) async {
    lastId = id;
    return payload;
  }

  @override
  Future<Object?> refreshHur(String id) async {
    lastId = id;
    return payload;
  }
}

class _ThrowingDataSource implements VehiclesDataSource {
  _ThrowingDataSource(this.error);

  final AppError error;

  @override
  Future<Object?> list(Map<String, dynamic> query) async => throw error;
  @override
  Future<Object?> detail(String id) async => throw error;
  @override
  Future<Object?> create(Map<String, dynamic> body) async => throw error;
  @override
  Future<Object?> update(String id, Map<String, dynamic> body) async =>
      throw error;
  @override
  Future<Object?> delete(String id) async => throw error;
  @override
  Future<Object?> history(String id) async => throw error;
  @override
  Future<Object?> vinHistory(String id) async => throw error;
  @override
  Future<Object?> refreshHur(String id) async => throw error;
}
