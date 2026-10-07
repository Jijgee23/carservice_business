import 'dart:async';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';
import 'package:carservice_business/features/vehicles/presentation/controllers/vehicle_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_vehicle_repository.dart';

/// Unit coverage for `VehicleDetailController` — `P3-F5`.
///
/// Covers fetch-by-id (deep-link cold start), the `PATCH` owner-block
/// divergence (owner name survives an update; an actual owner change
/// triggers a re-fetch), delete surfacing `VEHICLE_IN_USE` verbatim, HUR
/// refresh in-flight/success/502 states and that it never discards a field
/// it did not itself send, and a Completer-based generation-guard race test.
void main() {
  group('load (fetch by id)', () {
    test(
      'cold start fetches the vehicle and its history by id alone',
      () async {
        final repo = FakeVehicleRepository(
          seed: [FakeVehicleRepository.seedVehicle(id: 'veh-1')],
        );
        final controller = VehicleDetailController(
          vehicleId: 'veh-1',
          repo: repo,
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.detailState, isA<AsyncData<Vehicle>>());
        expect(controller.vehicle?.id, 'veh-1');
        expect(controller.historyState, isA<AsyncData<VehicleHistory>>());
        controller.dispose();
      },
    );

    test('an id with no tenant link surfaces a 404, never a crash', () async {
      final repo = FakeVehicleRepository(seed: const []);
      final controller = VehicleDetailController(
        vehicleId: 'missing',
        repo: repo,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = controller.detailState;
      expect(state, isA<AsyncError<Vehicle>>());
      expect((state as AsyncError<Vehicle>).error.statusCode, 404);
      controller.dispose();
    });
  });

  group('save — PATCH owner-block divergence', () {
    test(
      'owner unchanged: the owner ref survives the PATCH response',
      () async {
        final repo = FakeVehicleRepository(
          seed: [
            FakeVehicleRepository.seedVehicle(
              id: 'veh-1',
              customerId: 'cust-1',
            ),
          ],
        );
        final controller = VehicleDetailController(
          vehicleId: 'veh-1',
          repo: repo,
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.vehicle?.customer?.fullName, 'Бат');

        final result = await controller.save(
          make: 'Toyota',
          model: 'Prius 30',
          customerId: 'cust-1',
        );

        expect(result, isA<Ok<Vehicle>>());
        // The fake's PATCH response, like the real server, carries no
        // `customer` block when the owner id is unchanged — the controller
        // must have carried the previously-known ref forward itself.
        expect(controller.vehicle?.customerId, 'cust-1');
        expect(controller.vehicle?.customer?.fullName, 'Бат');
        controller.dispose();
      },
    );

    test(
      'owner actually changed: no stale ref shown, a re-fetch is issued',
      () async {
        final repo = FakeVehicleRepository(
          seed: [
            FakeVehicleRepository.seedVehicle(
              id: 'veh-1',
              customerId: 'cust-1',
            ),
          ],
        );
        final controller = VehicleDetailController(
          vehicleId: 'veh-1',
          repo: repo,
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final result = await controller.save(
          make: 'Toyota',
          model: 'Prius 30',
          customerId: 'cust-2',
        );
        expect(result, isA<Ok<Vehicle>>());
        // Since the response carries no owner ref for a *new* owner, save()
        // triggers a follow-up load() rather than trust the bare response —
        // that reload briefly shows AsyncLoading, then settles with the fresh
        // GET (including the new owner's real ref), never a stale "Бат".
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.vehicle?.customerId, 'cust-2');
        expect(controller.vehicle?.customer?.fullName, isNot('Бат'));
        controller.dispose();
      },
    );

    test('save surfaces a validation failure verbatim', () async {
      final repo = FakeVehicleRepository(
        seed: [FakeVehicleRepository.seedVehicle(id: 'veh-1')],
      );
      final controller = VehicleDetailController(
        vehicleId: 'veh-1',
        repo: repo,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final result = await controller.save(make: '', model: '');
      expect(result, isA<Err<Vehicle>>());
      expect(controller.saveError?.code, 'VALIDATION_FAILED');
      controller.dispose();
    });
  });

  group('delete', () {
    test(
      'VEHICLE_IN_USE (409) is surfaced with the server explanation',
      () async {
        final repo = FakeVehicleRepository(
          seed: [FakeVehicleRepository.seedVehicle(id: 'veh-1')],
          history: {
            'veh-1': const VehicleHistory(
              orders: [VehicleHistoryOrder(id: 'ord-1')],
            ),
          },
        );
        final controller = VehicleDetailController(
          vehicleId: 'veh-1',
          repo: repo,
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final result = await controller.delete();
        expect(result, isA<Err<VehicleDeletionResult>>());
        expect(controller.deleteError?.statusCode, 409);
        expect(controller.deleteError?.code, 'VEHICLE_IN_USE');
        expect(controller.deleteError?.display, contains('устгах боломжгүй'));
        controller.dispose();
      },
    );

    test('a clean vehicle deletes without error', () async {
      final repo = FakeVehicleRepository(
        seed: [
          FakeVehicleRepository.seedVehicle(id: 'veh-1', customerId: null),
        ],
      );
      final controller = VehicleDetailController(
        vehicleId: 'veh-1',
        repo: repo,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final result = await controller.delete();
      expect(result, isA<Ok<VehicleDeletionResult>>());
      expect(controller.deleteError, isNull);
      controller.dispose();
    });
  });

  group('HUR refresh', () {
    test(
      'in-flight state is exposed while the request is outstanding',
      () async {
        final repo = _QueuedVehicleRepository(
          base: FakeVehicleRepository.seedVehicle(id: 'veh-1'),
        );
        final controller = VehicleDetailController(
          vehicleId: 'veh-1',
          repo: repo,
        );
        // Resolve the cold-start GET immediately so only refresh-hur is queued.
        repo.vehicleCompleters.single.complete(Ok(repo.base));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final future = controller.refreshFromHur();
        expect(controller.refreshingHur, isTrue);

        repo.hurCompleters.single.complete(
          const Ok(VehicleHurRefresh(make: 'Toyota', model: 'Prius 30')),
        );
        await future;
        expect(controller.refreshingHur, isFalse);
        controller.dispose();
      },
    );

    test(
      'success applies the refresh and never discards fields it did not touch',
      () async {
        final repo = FakeVehicleRepository(
          seed: [
            FakeVehicleRepository.seedVehicle(
              id: 'veh-1',
              customerId: 'cust-1',
            ),
          ],
        );
        final controller = VehicleDetailController(
          vehicleId: 'veh-1',
          repo: repo,
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        final before = controller.vehicle!;

        final result = await controller.refreshFromHur();
        expect(result, isA<Ok<VehicleHurRefresh>>());
        final after = controller.vehicle!;
        // Fields the HUR route never speaks about (or the fake's fixed
        // response left null) must survive untouched — mileage, ownerRegnum,
        // customerId and the owner ref in particular.
        expect(after.mileage, before.mileage);
        expect(after.ownerRegnum, before.ownerRegnum);
        expect(after.customerId, before.customerId);
        expect(after.customer?.fullName, before.customer?.fullName);
        expect(after.isPostpaid, before.isPostpaid);
        controller.dispose();
      },
    );

    test(
      'upstream 502 is an expected outcome: no crash, nothing overwritten',
      () async {
        final repo = FakeVehicleRepository(
          seed: [FakeVehicleRepository.seedVehicle(id: 'veh-1')],
        )..hurUpstreamFails = true;
        final controller = VehicleDetailController(
          vehicleId: 'veh-1',
          repo: repo,
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        final before = controller.vehicle;

        final result = await controller.refreshFromHur();
        expect(result, isA<Err<VehicleHurRefresh>>());
        expect(controller.hurError?.statusCode, 502);
        // Detail state must remain intact — a 502 is not a crash path.
        expect(controller.detailState, isA<AsyncData<Vehicle>>());
        expect(controller.vehicle?.make, before?.make);
        expect(controller.vehicle?.model, before?.model);
        controller.dispose();
      },
    );
  });

  group('generation guard (Completer-based race)', () {
    test(
      'a stale in-flight load result never overwrites a newer one',
      () async {
        final repo = _QueuedVehicleRepository(
          base: Vehicle(id: 'veh-1', make: 'Toyota', model: 'Prius'),
        );
        final controller = VehicleDetailController(
          vehicleId: 'veh-1',
          repo: repo,
        );
        // First (cold-start) request now outstanding.
        expect(repo.vehicleCompleters, hasLength(1));

        // A second load() starts before the first resolves.
        final secondLoad = controller.load();
        expect(repo.vehicleCompleters, hasLength(2));

        // Resolve the stale first request last-in-time is irrelevant — resolve
        // it *after* the second one to prove the earlier generation loses even
        // though it settles second.
        repo.vehicleCompleters[1].complete(
          Ok(Vehicle(id: 'veh-1', make: 'Second', model: 'Prius')),
        );
        await secondLoad;
        expect(controller.vehicle?.make, 'Second');

        repo.vehicleCompleters[0].complete(
          Ok(Vehicle(id: 'veh-1', make: 'Stale-first', model: 'Prius')),
        );
        await Future<void>.delayed(Duration.zero);

        // The stale generation-0 response must never have been applied.
        expect(controller.vehicle?.make, 'Second');
        controller.dispose();
      },
    );
  });
}

/// Minimal queueable fake used only for the in-flight and race assertions
/// above, subclassed locally per the slice's constraint against touching
/// the shared `FakeVehicleRepository`. History resolves immediately with an
/// empty result so only the vehicle GET/refresh-hur route is queued.
class _QueuedVehicleRepository implements VehiclesRepository {
  _QueuedVehicleRepository({required this.base});

  final Vehicle base;
  final vehicleCompleters = <Completer<Result<Vehicle>>>[];
  final hurCompleters = <Completer<Result<VehicleHurRefresh>>>[];

  @override
  Future<Result<Vehicle>> getVehicle(String vehicleId) {
    final completer = Completer<Result<Vehicle>>();
    vehicleCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<Result<VehicleHurRefresh>> refreshFromHur(String vehicleId) {
    final completer = Completer<Result<VehicleHurRefresh>>();
    hurCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<Result<VehicleHistory>> getHistory(String vehicleId) async =>
      const Ok(VehicleHistory());

  @override
  Future<Result<VinHistory>> getVinHistory(String vehicleId) async =>
      const Ok(VinHistory());

  @override
  Future<Result<PagedResult<Vehicle>>> getVehicles({
    VehicleListQuery? query,
  }) async => Ok(
    PagedResult(
      items: [base],
      pagination: const PaginationMeta(
        page: 1,
        pageSize: 50,
        total: 1,
        totalPages: 1,
        hasPrev: false,
        hasNext: false,
      ),
    ),
  );

  @override
  Future<Result<Vehicle>> createVehicle({
    required String plate,
    required String make,
    required String model,
    String? vin,
    int? year,
    int? mileage,
    String? customerId,
  }) async => Ok(base);

  @override
  Future<Result<Vehicle>> updateVehicle(
    String vehicleId, {
    required String plate,
    required String make,
    required String model,
    String? vin,
    int? year,
    int? mileage,
    String? fuelType,
    String? wheelPosition,
    String? colorName,
    int? capacity,
    String? purpose,
    String? ownerRegnum,
    String? customerId,
    bool? isPostpaid,
  }) async => Ok(base);

  @override
  Future<Result<VehicleDeletionResult>> deleteVehicle(String vehicleId) async =>
      Ok(VehicleDeletionResult(id: vehicleId));
}
