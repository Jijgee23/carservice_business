import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_dto.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/presentation/controllers/vehicle_detail_controller.dart';

import '../../fakes/fake_vehicle_repository.dart';

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('VinHistoryDto', () {
    test('parses the enveloped payload', () {
      final v = VinHistoryDto.fromJson({
        'data': {
          'vin': 'JTDKB20U793000000',
          'records': [
            {
              'vehicleId': 'v2',
              'plate': '9999 УБА',
              'make': 'Toyota',
              'model': 'Prius',
              'year': 2012,
              'ownerName': 'Бат',
              'orderCount': 3,
              'lastOrderAt': '2026-09-01T10:00:00.000Z',
              'createdAt': '2026-01-01T00:00:00.000Z',
            },
          ],
          'otherTenantRecords': 2,
        },
      }).value;
      expect(v.vin, 'JTDKB20U793000000');
      expect(v.records.single.vehicleId, 'v2');
      expect(v.records.single.orderCount, 3);
      expect(v.records.single.lastOrderAt, isNotNull);
      expect(v.otherTenantRecords, 2);
      expect(v.hasContent, isTrue);
    });

    test('parses the flat payload (no data wrapper)', () {
      final v = VinHistoryDto.fromJson({
        'vin': 'JTDKB20U793000000',
        'records': [
          {'vehicleId': 'v2', 'plate': '9999 УБА', 'orderCount': 1},
        ],
        'otherTenantRecords': 4,
      }).value;
      expect(v.vin, 'JTDKB20U793000000');
      expect(v.records.single.plate, '9999 УБА');
      expect(v.otherTenantRecords, 4);
    });

    test('missing fields degrade; record without vehicleId is skipped', () {
      final v = VinHistoryDto.fromJson({
        'vin': 'X',
        'records': [
          {'plate': 'no id'},
          {'vehicleId': 'v3'},
        ],
      }).value;
      expect(v.records, hasLength(1));
      expect(v.records.single.plate, '');
      expect(v.records.single.ownerName, isNull);
      expect(v.records.single.orderCount, 0);
      expect(v.records.single.lastOrderAt, isNull);
      expect(v.otherTenantRecords, 0);
    });

    test('null vin or nothing to show has no content', () {
      expect(
        VinHistoryDto.fromJson({
          'data': {'vin': null, 'records': [], 'otherTenantRecords': 0},
        }).value.hasContent,
        isFalse,
      );
      expect(
        VinHistoryDto.fromJson({'vin': 'X', 'records': []}).value.hasContent,
        isFalse,
      );
    });
  });

  group('VehicleDetailController VIN history', () {
    test('loads and exposes content', () async {
      final repo = FakeVehicleRepository(
        vinHistory: {
          'veh-1': const VinHistory(
            vin: 'V',
            records: [VinHistoryRecord(vehicleId: 'v2', plate: 'A')],
            otherTenantRecords: 1,
          ),
        },
      );
      final c = VehicleDetailController(vehicleId: 'veh-1', repo: repo);
      await _settle();
      expect(c.vinHistory?.records, hasLength(1));
      c.dispose();
    });

    test('hidden when empty', () async {
      final c = VehicleDetailController(
        vehicleId: 'veh-1',
        repo: FakeVehicleRepository(),
      );
      await _settle();
      expect(c.vinHistory, isNull);
      c.dispose();
    });

    test('hidden quietly on failure, vehicle still loads', () async {
      final repo = FakeVehicleRepository()..vinHistoryFails = true;
      final c = VehicleDetailController(vehicleId: 'veh-1', repo: repo);
      await _settle();
      expect(c.vinHistory, isNull);
      expect(c.vehicle, isNotNull);
      c.dispose();
    });
  });

  group('formerPlate', () {
    test('null/empty snapshot -> null', () {
      expect(formerPlate(null, '1234 УБА'), isNull);
      expect(formerPlate('  ', '1234 УБА'), isNull);
    });
    test('same plate after normalization -> null', () {
      expect(formerPlate('1234уба', '1234 УБА'), isNull);
      expect(formerPlate('1234-УБА', '1234 УБА'), isNull);
    });
    test('different plate -> trimmed snapshot', () {
      expect(formerPlate(' 5555 УНА ', '1234 УБА'), '5555 УНА');
    });
  });
}
