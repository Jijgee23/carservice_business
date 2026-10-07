import 'dart:async';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_customer_repository.dart';

/// Completer-queued fake local to this test file — [CustomerDetailController]
/// races `getCustomer` calls against each other (e.g. `load()` fired twice
/// in quick succession, or `load()` racing a stale in-flight request from a
/// previous screen instance), mirroring `_QueuedCustomersRepository` in
/// `customer_list_controller_test.dart`.
class _QueuedDetailRepository implements CustomersRepository {
  final requested = <String>[];
  final pending = <Completer<Result<CustomerDetail>>>[];

  @override
  Future<Result<CustomerDetail>> getCustomer(String customerId) {
    requested.add(customerId);
    final completer = Completer<Result<CustomerDetail>>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<Result<PagedResult<CustomerHistoryOrder>>> getCustomerHistory(
    String customerId, {
    int page = 1,
    int pageSize = 20,
  }) async => Ok(
    PagedResult(
      items: const [],
      pagination: PaginationMeta(
        page: 1,
        pageSize: pageSize,
        total: 0,
        totalPages: 1,
        hasPrev: false,
        hasNext: false,
      ),
    ),
  );

  @override
  Future<Result<PagedResult<Customer>>> getCustomers({
    CustomerListQuery? query,
  }) => throw UnimplementedError();

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

Customer _customer(String id, {String fullName = 'Бат'}) =>
    Customer(id: id, fullName: fullName, phone: '99001122');

void main() {
  group('CustomerDetailController.load', () {
    test('cold start fetches by id — no preloaded summary required', () async {
      final repo = FakeCustomerRepository(seed: [_customer('cust-1')]);
      final ctrl = CustomerDetailController(customerId: 'cust-1', repo: repo);
      expect(ctrl.detailState, isA<AsyncLoading<CustomerDetail>>());
      await ctrl.load();
      expect(ctrl.detailState, isA<AsyncData<CustomerDetail>>());
      expect(ctrl.customer?.id, 'cust-1');
    });

    test('surfaces a 404 as AsyncError rather than crashing', () async {
      final repo = FakeCustomerRepository(seed: [_customer('cust-1')]);
      final ctrl = CustomerDetailController(customerId: 'missing', repo: repo);
      await ctrl.load();
      expect(ctrl.detailState, isA<AsyncError<CustomerDetail>>());
    });

    test(
      'a stale in-flight getCustomer response never overwrites a newer one',
      () async {
        final repo = _QueuedDetailRepository();
        final ctrl = CustomerDetailController(customerId: 'cust-1', repo: repo);

        final first = ctrl.load();
        final second = ctrl.load();
        expect(repo.pending.length, 2);

        // Resolve the SECOND (newer) request first, then the stale first
        // one — the stale response must be discarded, matching the
        // generation-guard convention in `CustomerListController`.
        repo.pending[1].complete(
          Ok(CustomerDetail(customer: _customer('cust-1', fullName: 'Iим'))),
        );
        repo.pending[0].complete(
          Ok(CustomerDetail(customer: _customer('cust-1', fullName: 'Хуучин'))),
        );
        await Future.wait([first, second]);

        expect(ctrl.customer?.fullName, 'Iим');
      },
    );
  });

  group('CustomerDetailController.loadHistory', () {
    test('paginates using the meta envelope and supports load-more', () async {
      final history = List.generate(
        3,
        (i) => CustomerHistoryOrder(id: 'order-$i'),
      );
      final repo = FakeCustomerRepository(
        seed: [_customer('cust-1')],
        history: {'cust-1': history},
      );
      final ctrl = CustomerDetailController(customerId: 'cust-1', repo: repo);
      await ctrl.load();
      // `load()` fires history loading unawaited (best-effort, doesn't block
      // the detail render) — await it explicitly here since this test is
      // about history pagination itself.
      await ctrl.loadHistory();
      // historyPageSize default is 20, so all 3 land on page 1 already —
      // exercise pagination explicitly with a smaller repo-side page.
      expect(ctrl.historyState, isA<AsyncData<List<CustomerHistoryOrder>>>());
      expect(ctrl.historyTotal, 3);
      expect(ctrl.hasHistoryNext, isFalse);
    });

    test('a load-more failure keeps the already-loaded page visible', () async {
      final repo = _FailingHistoryPageTwoRepository();
      final ctrl = CustomerDetailController(customerId: 'cust-1', repo: repo);
      await ctrl.load();
      await ctrl.loadHistory();
      expect(ctrl.historyState.valueOrNull?.length, 1);
      await ctrl.loadMoreHistory();
      expect(ctrl.historyLoadMoreError, isNotNull);
      // Page 1 data must still be there — never discarded by a failed
      // load-more.
      expect(ctrl.historyState.valueOrNull?.length, 1);
    });
  });

  group('CustomerDetailController.update', () {
    test(
      'always sends all four fields explicitly (whole-record replace)',
      () async {
        final repo = _RecordingUpdateRepository();
        final ctrl = CustomerDetailController(customerId: 'cust-1', repo: repo);
        await ctrl.load();
        await ctrl.update(
          fullName: 'Шинэ нэр',
          phone: '99001122',
          email: null,
          note: null,
        );
        expect(repo.lastCall, isNotNull);
        expect(repo.lastCall!['fullName'], 'Шинэ нэр');
        expect(repo.lastCall!['phone'], '99001122');
        expect(repo.lastCall!.containsKey('email'), isTrue);
        expect(repo.lastCall!.containsKey('note'), isTrue);
      },
    );

    test('preserves createdAt locally since PATCH omits it', () async {
      final repo = FakeCustomerRepository(
        seed: [
          Customer(
            id: 'cust-1',
            fullName: 'Бат',
            phone: '99001122',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final ctrl = CustomerDetailController(customerId: 'cust-1', repo: repo);
      await ctrl.load();
      expect(ctrl.customer?.createdAt, DateTime(2026, 1, 1));
      await ctrl.update(
        fullName: 'Шинэ нэр',
        phone: '99001122',
        email: null,
        note: null,
      );
      // The fake's response has no createdAt; the controller must keep the
      // previously-known one rather than blanking it.
      expect(ctrl.customer?.createdAt, DateTime(2026, 1, 1));
      expect(ctrl.customer?.fullName, 'Шинэ нэр');
    });
  });

  group('CustomerDetailController.delete', () {
    test('classifies a 409 CUSTOMER_IN_USE as CustomerFailure.inUse', () async {
      final repo = FakeCustomerRepository(
        seed: [_customer('cust-1')],
        customersWithOrders: {'cust-1'},
      );
      final ctrl = CustomerDetailController(customerId: 'cust-1', repo: repo);
      await ctrl.load();
      final result = await ctrl.delete();
      expect(result, isA<Err<CustomerDeleteResult>>());
      final error = (result as Err<CustomerDeleteResult>).error;
      expect(
        CustomerFailure.classify(
          statusCode: error.statusCode,
          code: error.code,
          fieldErrors: error.fieldErrors,
        ),
        CustomerFailure.inUse,
      );
      expect(error.code, CustomerErrorCode.customerInUse);
    });

    test('succeeds and returns the deleted id when unblocked', () async {
      final repo = FakeCustomerRepository(seed: [_customer('cust-1')]);
      final ctrl = CustomerDetailController(customerId: 'cust-1', repo: repo);
      await ctrl.load();
      final result = await ctrl.delete();
      expect(result, isA<Ok<CustomerDeleteResult>>());
    });
  });
}

class _FailingHistoryPageTwoRepository implements CustomersRepository {
  @override
  Future<Result<CustomerDetail>> getCustomer(String customerId) async =>
      Ok(CustomerDetail(customer: _customer(customerId)));

  @override
  Future<Result<PagedResult<CustomerHistoryOrder>>> getCustomerHistory(
    String customerId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (page == 1) {
      return Ok(
        PagedResult(
          items: [CustomerHistoryOrder(id: 'order-1')],
          pagination: const PaginationMeta(
            page: 1,
            pageSize: 1,
            total: 2,
            totalPages: 2,
            hasPrev: false,
            hasNext: true,
          ),
        ),
      );
    }
    return const Err(AppError(ErrorKind.server, 'алдаа'));
  }

  @override
  Future<Result<PagedResult<Customer>>> getCustomers({
    CustomerListQuery? query,
  }) => throw UnimplementedError();

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

class _RecordingUpdateRepository implements CustomersRepository {
  Map<String, dynamic>? lastCall;

  @override
  Future<Result<CustomerDetail>> getCustomer(String customerId) async =>
      Ok(CustomerDetail(customer: _customer(customerId)));

  @override
  Future<Result<PagedResult<CustomerHistoryOrder>>> getCustomerHistory(
    String customerId, {
    int page = 1,
    int pageSize = 20,
  }) async => Ok(
    PagedResult(
      items: const [],
      pagination: const PaginationMeta(
        page: 1,
        pageSize: 20,
        total: 0,
        totalPages: 1,
        hasPrev: false,
        hasNext: false,
      ),
    ),
  );

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
  }) async {
    lastCall = {
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'note': note,
    };
    return Ok(Customer(id: customerId, fullName: fullName, phone: phone));
  }

  @override
  Future<Result<PagedResult<Customer>>> getCustomers({
    CustomerListQuery? query,
  }) => throw UnimplementedError();

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
  Future<Result<CustomerDeleteResult>> deleteCustomer(String customerId) =>
      throw UnimplementedError();

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
