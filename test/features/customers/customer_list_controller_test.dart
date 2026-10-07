import 'dart:async';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_customer_repository.dart';

/// Records each `q` sent and holds every response open on a [Completer],
/// mirroring `_QueuedSearchRepository` in
/// `appointment_list_controller_test.dart` (same Completer-based race
/// technique, scoped to the Customers repository's smaller surface).
class _QueuedCustomersRepository implements CustomersRepository {
  final requestedTerms = <String?>[];
  final pending = <Completer<Result<PagedResult<Customer>>>>[];

  @override
  Future<Result<PagedResult<Customer>>> getCustomers({
    CustomerListQuery? query,
  }) {
    requestedTerms.add(query?.q);
    final completer = Completer<Result<PagedResult<Customer>>>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<Result<CustomerDetail>> getCustomer(String customerId) =>
      throw UnimplementedError();

  @override
  Future<Result<CustomerCreateResult>> createCustomer({
    String? fullName,
    required String phone,
    String? email,
    String? note,
    bool isOrganization = false,
    String? orgRegnum,
    String? orgName,
    String? orgEmail,
  }) => throw UnimplementedError();

  @override
  Future<Result<Customer>> updateCustomer(
    String customerId, {
    required String? fullName,
    required String phone,
    required String? email,
    required String? note,
    bool isOrganization = false,
    String? orgRegnum,
    String? orgName,
    String? orgEmail,
  }) => throw UnimplementedError();

  @override
  Future<Result<CustomerDeleteResult>> deleteCustomer(String customerId) =>
      throw UnimplementedError();

  @override
  Future<Result<PagedResult<CustomerHistoryOrder>>> getCustomerHistory(
    String customerId, {
    int page = 1,
    int pageSize = 20,
  }) => throw UnimplementedError();

  @override
  Future<Result<int>> getBroadcastRecipientCount() =>
      throw UnimplementedError();

  @override
  Future<Result<OrgLookupResult>> lookupOrg(String regno) =>
      throw UnimplementedError();

  @override
  Future<Result<CustomerBroadcastResult>> sendBroadcast({
    required String title,
    required String body,
  }) => throw UnimplementedError();
}

/// A repository whose second page fails, so `loadMore`'s
/// error-preserves-existing-data behaviour can be exercised deterministically
/// (as opposed to relying on the fake's own pagination running out).
class _FailingSecondPageRepository implements CustomersRepository {
  _FailingSecondPageRepository(this._page1);
  final PagedResult<Customer> _page1;
  int calls = 0;

  @override
  Future<Result<PagedResult<Customer>>> getCustomers({
    CustomerListQuery? query,
  }) async {
    calls++;
    final page = query?.page ?? 1;
    if (page == 1) return Ok(_page1);
    return const Err(
      AppError(ErrorKind.server, 'Дараагийн хуудас ачаалж чадсангүй'),
    );
  }

  @override
  Future<Result<CustomerDetail>> getCustomer(String customerId) =>
      throw UnimplementedError();

  @override
  Future<Result<CustomerCreateResult>> createCustomer({
    String? fullName,
    required String phone,
    String? email,
    String? note,
    bool isOrganization = false,
    String? orgRegnum,
    String? orgName,
    String? orgEmail,
  }) => throw UnimplementedError();

  @override
  Future<Result<Customer>> updateCustomer(
    String customerId, {
    required String? fullName,
    required String phone,
    required String? email,
    required String? note,
    bool isOrganization = false,
    String? orgRegnum,
    String? orgName,
    String? orgEmail,
  }) => throw UnimplementedError();

  @override
  Future<Result<CustomerDeleteResult>> deleteCustomer(String customerId) =>
      throw UnimplementedError();

  @override
  Future<Result<PagedResult<CustomerHistoryOrder>>> getCustomerHistory(
    String customerId, {
    int page = 1,
    int pageSize = 20,
  }) => throw UnimplementedError();

  @override
  Future<Result<int>> getBroadcastRecipientCount() =>
      throw UnimplementedError();

  @override
  Future<Result<OrgLookupResult>> lookupOrg(String regno) =>
      throw UnimplementedError();

  @override
  Future<Result<CustomerBroadcastResult>> sendBroadcast({
    required String title,
    required String body,
  }) => throw UnimplementedError();
}

Customer _cust(String id, {String? fullName, String? phone}) => Customer(
  id: id,
  fullName: fullName ?? id,
  phone: phone ?? '9900${id.hashCode.abs() % 10000}',
);

PagedResult<Customer> _page(List<Customer> items, {bool hasNext = false}) =>
    PagedResult(
      items: items,
      pagination: PaginationMeta(
        page: 1,
        pageSize: CustomerListController.defaultPageSize,
        total: items.length,
        totalPages: hasNext ? 2 : 1,
        hasPrev: false,
        hasNext: hasNext,
      ),
    );

void main() {
  group('CustomerListController — load / pagination', () {
    test('loadCustomers populates the list from page 1', () async {
      final repo = FakeCustomerRepository(
        seed: [
          _cust('c1', fullName: 'Бат'),
          _cust('c2', fullName: 'Болд'),
        ],
      );
      final controller = CustomerListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );

      await controller.loadCustomers();

      expect(controller.customers, hasLength(2));
      expect(controller.listState, isA<AsyncData<List<Customer>>>());
      controller.dispose();
    });

    test('loadMore appends the next page and updates hasNext/total', () async {
      final repo = FakeCustomerRepository(
        seed: List.generate(
          CustomerListController.defaultPageSize + 1,
          (i) => _cust('c$i', fullName: 'Үйлчлүүлэгч $i'),
        ),
      );
      final controller = CustomerListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadCustomers();
      expect(controller.hasNext, isTrue);
      expect(
        controller.customers,
        hasLength(CustomerListController.defaultPageSize),
      );

      await controller.loadMore();

      expect(controller.hasNext, isFalse);
      expect(
        controller.customers,
        hasLength(CustomerListController.defaultPageSize + 1),
      );
      controller.dispose();
    });

    test(
      'a load-more failure preserves the already-loaded page and is retryable',
      () async {
        final repo = _FailingSecondPageRepository(
          _page([_cust('c1'), _cust('c2')], hasNext: true),
        );
        final controller = CustomerListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );
        await controller.loadCustomers();
        expect(controller.customers, hasLength(2));

        await controller.loadMore();

        expect(controller.loadMoreError, isNotNull);
        expect(controller.loadingMore, isFalse);
        // The page already on screen must survive the failed load-more.
        expect(controller.customers, hasLength(2));
        expect(controller.customers.map((c) => c.id), ['c1', 'c2']);
        controller.dispose();
      },
    );

    test('searching resets pagination to the first page', () async {
      final repo = FakeCustomerRepository(
        seed: List.generate(
          CustomerListController.defaultPageSize + 1,
          (i) => _cust('c$i', fullName: 'Болд $i'),
        ),
      );
      final controller = CustomerListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadCustomers();
      await controller.loadMore();
      expect(controller.page, 2);

      controller.setQuery('Болд');
      await pumpEventQueue();

      expect(controller.page, 1);
      controller.dispose();
    });
  });

  group('CustomerListController — empty vs error states', () {
    test(
      'an empty result is AsyncData with an empty list, not AsyncError',
      () async {
        final repo = FakeCustomerRepository(seed: const []);
        final controller = CustomerListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );

        await controller.loadCustomers();

        expect(controller.listState, isA<AsyncData<List<Customer>>>());
        expect(controller.customers, isEmpty);
        controller.dispose();
      },
    );

    test(
      'a request-level failure surfaces as AsyncError, not an empty list',
      () async {
        final repo = _QueuedCustomersRepository();
        final controller = CustomerListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );

        final load = controller.loadCustomers();
        repo.pending.single.complete(
          const Err(AppError(ErrorKind.forbidden, 'Хандах эрхгүй')),
        );
        await load;

        expect(controller.listState, isA<AsyncError<List<Customer>>>());
        controller.dispose();
      },
    );
  });

  group('CustomerListController — search debounce', () {
    test('setQuery does not reload until the debounce timer fires', () async {
      final repo = FakeCustomerRepository(
        seed: [
          _cust('c1', fullName: 'Болд'),
          _cust('c2', fullName: 'Мөнх'),
        ],
      );
      final controller = CustomerListController(
        repo: repo,
        searchDebounce: Duration.zero,
      );
      await controller.loadCustomers();
      expect(controller.customers, hasLength(2));

      controller.setQuery('Мөнх');
      // Not yet reloaded — the debounce timer has not fired.
      expect(controller.customers, hasLength(2));

      await pumpEventQueue();

      expect(controller.customers.map((c) => c.id), ['c2']);
      controller.dispose();
    });

    test('rapid setQuery calls coalesce into a single reload', () async {
      final repo = _QueuedCustomersRepository();
      final controller = CustomerListController(repo: repo);

      controller.setQuery('a');
      controller.setQuery('ab');
      controller.setQuery('abc');
      await Future<void>.delayed(
        CustomerListController.defaultSearchDebounce +
            const Duration(milliseconds: 50),
      );

      expect(repo.requestedTerms, ['abc']);
      controller.dispose();
    });
  });

  group('CustomerListController — stale-response race (Completer-based)', () {
    test(
      'a slow response for an old search term never overwrites a newer term',
      () async {
        final repo = _QueuedCustomersRepository();
        final controller = CustomerListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );

        controller.setQuery('old');
        await pumpEventQueue();
        controller.setQuery('new');
        await pumpEventQueue();
        expect(repo.requestedTerms, ['old', 'new']);

        repo.pending[1].complete(Ok(_page([_cust('new-result')])));
        repo.pending[0].complete(Ok(_page([_cust('old-result')])));
        await pumpEventQueue();

        expect(controller.customers.single.id, 'new-result');
        controller.dispose();
      },
    );

    test(
      'a stale response arriving after dispose is dropped, not applied',
      () async {
        final repo = _QueuedCustomersRepository();
        final controller = CustomerListController(
          repo: repo,
          searchDebounce: Duration.zero,
        );

        final load = controller.loadCustomers();
        controller.dispose();
        repo.pending.single.complete(Ok(_page([_cust('late')])));
        await load;

        // No assertion beyond "does not throw" is meaningful once disposed —
        // the guard's job is exactly to make this a no-op.
      },
    );
  });
}
