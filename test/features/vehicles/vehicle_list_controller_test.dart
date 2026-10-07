import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';
import 'package:carservice_business/features/vehicles/presentation/controllers/vehicle_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_vehicle_repository.dart';
import '../../support/completer_queue.dart';

/// A repository whose `getVehicles` never resolves on its own — the test
/// controls exactly when and in what order each call completes, via
/// [CompleterQueue]. Every other method throws: this controller never calls
/// them, and a call reaching one is a bug in the test, not something to
/// paper over.
class _QueuedVehiclesRepository implements VehiclesRepository {
  final queue = CompleterQueue<Result<PagedResult<Vehicle>>>();
  final requests = <VehicleListQuery?>[];

  @override
  Future<Result<PagedResult<Vehicle>>> getVehicles({VehicleListQuery? query}) {
    requests.add(query);
    return queue.next();
  }

  @override
  Future<Result<Vehicle>> getVehicle(String vehicleId) =>
      throw UnimplementedError();

  @override
  Future<Result<Vehicle>> createVehicle({
    required String plate,
    required String make,
    required String model,
    String? vin,
    int? year,
    int? mileage,
    String? customerId,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<Result<VehicleDeletionResult>> deleteVehicle(String vehicleId) =>
      throw UnimplementedError();

  @override
  Future<Result<VehicleHistory>> getHistory(String vehicleId) =>
      throw UnimplementedError();

  @override
  Future<Result<VinHistory>> getVinHistory(String vehicleId) =>
      throw UnimplementedError();

  @override
  Future<Result<VehicleHurRefresh>> refreshFromHur(String vehicleId) =>
      throw UnimplementedError();
}

Vehicle _vehicle(String id, {String plate = '1234 УБА'}) =>
    Vehicle(id: id, plate: plate, make: 'Toyota', model: 'Prius');

PagedResult<Vehicle> _page(
  List<Vehicle> items, {
  int page = 1,
  bool hasNext = false,
  int total = 0,
}) => PagedResult(
  items: items,
  pagination: PaginationMeta(
    page: page,
    pageSize: VehicleListController.defaultPageSize,
    total: total == 0 ? items.length : total,
    totalPages: hasNext ? page + 1 : page,
    hasPrev: page > 1,
    hasNext: hasNext,
  ),
);

void main() {
  group('race safety', () {
    test('a stale in-flight response cannot overwrite a newer one '
        '(loadVehicles vs loadVehicles)', () async {
      final repo = _QueuedVehiclesRepository();
      final controller = VehicleListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );

      final oldLoad = controller.loadVehicles(); // call #0 — slow
      final newLoad = controller.loadVehicles(); // call #1 — fast
      expect(repo.queue.callCount, 2);

      // Resolve out of order: the newer request finishes first.
      repo.queue.resolve(1, Ok(_page([_vehicle('new')])));
      await newLoad;
      repo.queue.resolve(0, Ok(_page([_vehicle('old')])));
      await oldLoad;
      // Let the stale continuation run if it was going to.
      await Future<void>.delayed(Duration.zero);

      expect(controller.listState.valueOrNull!.single.id, 'new');
      controller.dispose();
    });

    test(
      'loadMore ignores a stale in-flight page after a fresh reload starts',
      () async {
        final repo = _QueuedVehiclesRepository();
        final controller = VehicleListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );

        final firstLoad = controller.loadVehicles();
        repo.queue.resolve(
          0,
          Ok(_page([_vehicle('first')], hasNext: true, total: 2)),
        );
        await firstLoad;

        final staleLoadMore = controller.loadMore(); // call #1
        final reload = controller.loadVehicles(); // call #2 — bumps generation
        repo.queue.resolve(2, Ok(_page([_vehicle('reloaded')])));
        await reload;
        repo.queue.resolve(1, Ok(_page([_vehicle('stale-page-2')])));
        await staleLoadMore;

        expect(controller.listState.valueOrNull!.single.id, 'reloaded');
        controller.dispose();
      },
    );
  });

  group('debounce', () {
    test('setQuery collapses rapid keystrokes into a single request', () async {
      final repo = _QueuedVehiclesRepository();
      final controller = VehicleListController(
        repo: repo,
        searchDebounce: const Duration(milliseconds: 20),
      );

      controller.setQuery('a');
      controller.setQuery('ab');
      controller.setQuery('abc');
      expect(repo.queue.callCount, 0, reason: 'debounced, nothing sent yet');

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(repo.queue.callCount, 1);
      expect(repo.requests.single?.q, 'abc');

      repo.queue.resolve(0, Ok(_page([])));
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
    });

    test('a fresh debounce cancels a still-pending earlier timer', () async {
      final repo = _QueuedVehiclesRepository();
      final controller = VehicleListController(
        repo: repo,
        searchDebounce: const Duration(milliseconds: 20),
      );

      controller.setQuery('first');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repo.queue.callCount, 1);
      repo.queue.resolve(0, Ok(_page([])));
      await Future<void>.delayed(Duration.zero);

      controller.setQuery('second');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repo.queue.callCount, 2);
      expect(repo.requests.last?.q, 'second');
      repo.queue.resolve(1, Ok(_page([])));
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
    });
  });

  group('pagination', () {
    test('loadMore appends to the already-loaded page', () async {
      // The controller's page size is fixed at
      // `VehicleListController.defaultPageSize` (matching the contract's own
      // default), so seeding more than one page's worth of rows is what
      // exercises pagination — there is no per-instance override to reach
      // for instead.
      final many = FakeVehicleRepository(
        seed: [
          for (var i = 0; i < VehicleListController.defaultPageSize + 5; i++)
            _vehicle('veh-$i'),
        ],
      );
      final paged = VehicleListController(
        repo: many,
        searchDebounce: Duration.zero,
      );
      await paged.loadVehicles();
      expect(
        paged.listState.valueOrNull!.length,
        VehicleListController.defaultPageSize,
      );
      expect(paged.hasNext, isTrue);

      await paged.loadMore();
      expect(
        paged.listState.valueOrNull!.length,
        VehicleListController.defaultPageSize + 5,
      );
      expect(paged.hasNext, isFalse);
      paged.dispose();
    });

    test(
      'a load-more error preserves the already-loaded data and is retryable',
      () async {
        final repo = _QueuedVehiclesRepository();
        final controller = VehicleListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );

        final firstLoad = controller.loadVehicles();
        repo.queue.resolve(
          0,
          Ok(_page([_vehicle('a'), _vehicle('b')], hasNext: true, total: 4)),
        );
        await firstLoad;

        final loadMore = controller.loadMore();
        // A real `VehiclesRepository` never throws — every failure it
        // observes (including a transport exception) is mapped to
        // `Err(AppError)` before it reaches the controller, so the fake
        // resolves with `Err`, not `resolveError`.
        repo.queue.resolve(
          1,
          Err(const AppError(ErrorKind.network, 'сүлжээний алдаа')),
        );
        await loadMore;

        expect(controller.listState.valueOrNull!.length, 2);
        expect(controller.loadMoreError, isNotNull);
        expect(controller.loadingMore, isFalse);

        // Retry succeeds and appends, and the error clears.
        final retry = controller.loadMore();
        repo.queue.resolve(2, Ok(_page([_vehicle('c')], page: 2)));
        await retry;

        expect(controller.listState.valueOrNull!.length, 3);
        expect(controller.loadMoreError, isNull);
        controller.dispose();
      },
    );
  });

  group('empty vs error states', () {
    test(
      'an empty page is AsyncData with an empty list, not AsyncError',
      () async {
        final fake = FakeVehicleRepository(seed: const []);
        final controller = VehicleListController(
          repo: fake,
          searchDebounce: Duration.zero,
        );
        await controller.loadVehicles();

        expect(controller.listState, isA<AsyncData<List<Vehicle>>>());
        expect(controller.listState.valueOrNull, isEmpty);
        controller.dispose();
      },
    );

    test('a request-level failure is AsyncError, not an empty list', () async {
      final repo = _QueuedVehiclesRepository();
      final controller = VehicleListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      final load = controller.loadVehicles();
      repo.queue.resolve(
        0,
        Err(
          const AppError(ErrorKind.forbidden, 'Хандах эрхгүй', statusCode: 403),
        ),
      );
      await load;

      expect(controller.listState, isA<AsyncError<List<Vehicle>>>());
      controller.dispose();
    });
  });

  group('server-side filters', () {
    test(
      'assigned/postpaid/customerId are sent through to the repository',
      () async {
        final repo = _QueuedVehiclesRepository();
        final controller = VehicleListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );

        final load1 = controller.setAssigned(true);
        repo.queue.resolve(0, Ok(_page([])));
        await load1;
        expect(repo.requests.last?.assigned, isTrue);

        final load2 = controller.setPostpaid(false);
        repo.queue.resolve(1, Ok(_page([])));
        await load2;
        expect(repo.requests.last?.postpaid, isFalse);

        final load3 = controller.setCustomerId('cust-9');
        repo.queue.resolve(2, Ok(_page([])));
        await load3;
        expect(repo.requests.last?.customerId, 'cust-9');
        expect(controller.hasActiveFilters, isTrue);

        final load4 = controller.clearFilters();
        repo.queue.resolve(3, Ok(_page([])));
        await load4;
        expect(controller.hasActiveFilters, isFalse);
        expect(repo.requests.last?.assigned, isNull);
        expect(repo.requests.last?.postpaid, isNull);
        expect(repo.requests.last?.customerId, isNull);

        controller.dispose();
      },
    );
  });
}
