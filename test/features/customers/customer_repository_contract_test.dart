import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/data/customer_repository.dart';
import 'package:carservice_business/features/customers/data/customers_data_source.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_customer_repository.dart';

/// Records the last call made through [CustomersDataSource] and returns a
/// canned response — lets this test assert the remote adapter never
/// expresses a mutation twice (one call in ⇒ one HTTP verb+path out) and
/// only ever puts allow-listed params on the wire, without a live server.
class _RecordingSource implements CustomersDataSource {
  String? lastCall;
  String? lastId;
  Map<String, dynamic>? lastQuery;
  Map<String, dynamic>? lastBody;
  Object? response;
  int? statusCode = 200;
  Object Function()? throwing;

  Future<Object?> _record(
    String name, {
    String? id,
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
  }) async {
    lastCall = name;
    lastId = id;
    lastQuery = query;
    lastBody = body;
    if (throwing != null) throw throwing!();
    return response;
  }

  @override
  Future<Object?> list(Map<String, dynamic> query) =>
      _record('list', query: query);

  @override
  Future<Object?> detail(String id) => _record('detail', id: id);

  @override
  Future<ApiEnvelope> create(Map<String, dynamic> body) async {
    final data = await _record('create', body: body);
    return (statusCode: statusCode, data: data);
  }

  @override
  Future<Object?> update(String id, Map<String, dynamic> body) =>
      _record('update', id: id, body: body);

  @override
  Future<Object?> delete(String id) => _record('delete', id: id);

  @override
  Future<Object?> history(String id, Map<String, dynamic> query) =>
      _record('history', id: id, query: query);

  @override
  Future<Object?> notifyCount() => _record('notifyCount');

  @override
  Future<Object?> notify(Map<String, dynamic> body) =>
      _record('notify', body: body);

  @override
  Future<Object?> orgLookup(String regno) =>
      _record('orgLookup', query: {'regno': regno});
}

Map<String, dynamic> _meta({int total = 1, int page = 1, int pageSize = 50}) =>
    {
      'page': page,
      'pageSize': pageSize,
      'total': total,
      'totalPages': 1,
      'hasPrev': false,
      'hasNext': false,
    };

void main() {
  group('RemoteCustomersRepository — wire contract', () {
    late _RecordingSource source;
    late RemoteCustomersRepository repository;

    setUp(() {
      source = _RecordingSource();
      repository = RemoteCustomersRepository(dataSource: source);
    });

    test('list sends only allow-listed params', () async {
      source.response = {'customers': const [], 'pagination': _meta(total: 0)};
      await repository.getCustomers(
        query: const CustomerListQuery(q: '  Бат  ', page: 2, pageSize: 25),
      );

      expect(source.lastCall, 'list');
      // `rejectUnknownParams(["q","page","pageSize","limit"])` returns 400
      // for anything else, so this set must never grow accidentally.
      expect(source.lastQuery!.keys.toSet(), {'page', 'pageSize', 'q'});
      expect(source.lastQuery!['q'], 'Бат');
      expect(source.lastQuery!['page'], 2);
    });

    test('an empty or whitespace q is omitted entirely', () async {
      source.response = {'customers': const [], 'pagination': _meta(total: 0)};
      await repository.getCustomers(query: const CustomerListQuery(q: '   '));
      expect(source.lastQuery!.containsKey('q'), isFalse);

      await repository.getCustomers();
      expect(source.lastQuery!.keys.toSet(), {'page', 'pageSize'});
    });

    test('create reports 201 as created and 200 as claim/reuse', () async {
      source.response = {
        'customer': {'id': 'c1', 'phone': '99001122'},
      };

      source.statusCode = 201;
      final created = await repository.createCustomer(phone: '99001122');
      expect((created as Ok<CustomerCreateResult>).value.created, isTrue);

      source.statusCode = 200;
      final claimed = await repository.createCustomer(phone: '99001122');
      expect(claimed, isA<Ok<CustomerCreateResult>>());
      expect((claimed as Ok<CustomerCreateResult>).value.created, isFalse);
      expect(claimed.value.customer.id, 'c1');
    });

    test('create sends all body fields the route reads (incl. org fields)', () async {
      source.statusCode = 201;
      source.response = {
        'customer': {'id': 'c1'},
      };
      await repository.createCustomer(
        fullName: 'Бат',
        phone: '99001122',
        email: null,
        note: 'VIP',
      );
      expect(source.lastBody, {
        'fullName': 'Бат',
        'phone': '99001122',
        'email': null,
        'note': 'VIP',
        'isOrganization': false,
        'orgRegnum': null,
        'orgName': null,
        'orgEmail': null,
      });
    });

    test('update is a full-state PATCH — a null note clears it', () async {
      source.response = {
        'customer': {'id': 'c1', 'phone': '99001122'},
      };
      final result = await repository.updateCustomer(
        'c1',
        fullName: null,
        phone: '99001122',
        email: null,
        note: null,
      );

      expect(source.lastCall, 'update');
      expect(source.lastId, 'c1');
      expect(source.lastBody, {
        'fullName': '',
        'phone': '99001122',
        'email': null,
        'note': null,
        'isOrganization': false,
        'orgRegnum': null,
        'orgName': null,
        'orgEmail': null,
      });
      // The route omits createdAt on this response; parsing must not fail.
      expect((result as Ok<Customer>).value.createdAt, isNull);
    });

    test('delete falls back to the requested id', () async {
      source.response = {'ok': true};
      final result = await repository.deleteCustomer('c-42');
      expect((result as Ok<CustomerDeleteResult>).value.id, 'c-42');
      expect(source.lastCall, 'delete');
    });

    test('history reads the meta key and paginates', () async {
      source.response = {
        'orders': [
          {'id': 'o1'},
        ],
        'meta': _meta(total: 1, page: 3, pageSize: 10),
      };
      final result = await repository.getCustomerHistory(
        'c1',
        page: 3,
        pageSize: 10,
      );

      expect(source.lastQuery, {'page': 3, 'pageSize': 10});
      final page = (result as Ok).value;
      expect(page.items.single.id, 'o1');
      expect(page.pagination.page, 3);
    });

    test('broadcast count and send hit their own routes', () async {
      source.response = {'recipientCount': 7};
      expect((await repository.getBroadcastRecipientCount() as Ok).value, 7);
      expect(source.lastCall, 'notifyCount');

      source.response = {'notified': 7};
      final sent = await repository.sendBroadcast(title: 'T', body: 'B');
      expect((sent as Ok<CustomerBroadcastResult>).value.notified, 7);
      expect(source.lastCall, 'notify');
      expect(source.lastBody, {'title': 'T', 'body': 'B'});
    });

    test('an AppError from the mapper survives verbatim into Err', () async {
      // The consolidated P3-D2 mapper's metadata must not be flattened by
      // the repository — a 422 with fieldErrors has to stay bindable.
      source.throwing = () => const AppError(
        ErrorKind.unknown,
        'Хүсэлт буруу.',
        statusCode: 422,
        fieldErrors: {'phone': 'Утасны дугаар 8 оронтой тоо байх ёстой.'},
      );
      final result = await repository.createCustomer(phone: 'abc');

      final error = (result as Err<CustomerCreateResult>).error;
      expect(error.statusCode, 422);
      expect(error.fieldErrors, isNotNull);
      expect(
        CustomerFailure.classify(
          statusCode: error.statusCode,
          code: error.code,
          fieldErrors: error.fieldErrors,
        ),
        CustomerFailure.validation,
      );
    });

    test(
      'a 403 from the newly-gated list route surfaces as forbidden',
      () async {
        source.throwing = () => const AppError(
          ErrorKind.forbidden,
          'Хандах эрх байхгүй',
          statusCode: 403,
        );
        final result = await repository.getCustomers();
        final error = (result as Err).error;
        expect(
          CustomerFailure.classify(statusCode: error.statusCode),
          CustomerFailure.forbidden,
        );
      },
    );

    test('a parse failure becomes an Err, never an uncaught throw', () async {
      source.response = {'customers': 'nope'};
      expect(await repository.getCustomers(), isA<Err>());
    });
  });

  group('FakeCustomerRepository — mirrors the server rules', () {
    test('search matches fullName, phone and email only', () async {
      final fake = FakeCustomerRepository(
        seed: [
          const Customer(id: 'c1', fullName: 'Бат', phone: '99001122'),
          const Customer(id: 'c2', fullName: 'Дорж', email: 'D@Example.mn'),
          const Customer(id: 'c3', fullName: 'Сараа', note: 'Бат referral'),
        ],
      );

      Future<List<String>> ids(String q) async {
        final result = await fake.getCustomers(query: CustomerListQuery(q: q));
        return (result as Ok<PagedResult<Customer>>).value.items
            .map((c) => c.id)
            .toList();
      }

      expect(await ids('бат'), ['c1']); // fullName, case-insensitive
      expect(await ids('9900'), ['c1']); // phone substring
      expect(await ids('d@example'), ['c2']); // email, case-insensitive
      // The note is NOT a search field on this route — `buildCustomerListWhere`
      // has three clauses, unlike the appointments search's five.
      expect(await ids('referral'), isEmpty);
    });

    test(
      'list is ordered fullName asc and rejects an over-cap pageSize',
      () async {
        final fake = FakeCustomerRepository(
          seed: [
            const Customer(id: 'c1', fullName: 'Ялалт'),
            const Customer(id: 'c2', fullName: 'Азжаргал'),
          ],
        );
        final page = (await fake.getCustomers() as Ok).value;
        expect(page.items.map((c) => c.id), ['c2', 'c1']);

        final rejected = await fake.getCustomers(
          query: const CustomerListQuery(pageSize: 101),
        );
        expect((rejected as Err).error.statusCode, 400);
      },
    );

    test('create validates phone the way normalizePhone does', () async {
      final fake = FakeCustomerRepository(seed: const []);

      final short =
          await fake.createCustomer(phone: '1234') as Err<CustomerCreateResult>;
      expect(short.error.statusCode, 422);
      expect(short.error.fieldErrors, contains('phone'));

      // Leading 0 and +976 both normalise to the canonical 8 digits.
      final normalized = await fake.createCustomer(phone: '+976 9900-1122');
      expect(
        (normalized as Ok<CustomerCreateResult>).value.customer.phone,
        '99001122',
      );
      expect(normalized.value.created, isTrue);
    });

    test('create rejects a bad email but allows an absent one', () async {
      final fake = FakeCustomerRepository(seed: const []);
      final bad = await fake.createCustomer(
        phone: '99001122',
        email: 'not-an-email',
      );
      expect((bad as Err).error.fieldErrors, contains('email'));

      expect(
        await fake.createCustomer(phone: '99001123'),
        isA<Ok<CustomerCreateResult>>(),
      );
    });

    test('an account-linked phone reuses the existing row as a 200', () async {
      final fake = FakeCustomerRepository(
        seed: [const Customer(id: 'c1', phone: '99001122', fullName: 'Бат')],
        accountLinkedPhones: {'99001122'},
      );
      final result = await fake.createCustomer(
        phone: '99001122',
        fullName: 'Бат',
      );
      expect((result as Ok<CustomerCreateResult>).value.created, isFalse);
      expect(result.value.customer.id, 'c1');
      expect(fake.customers.length, 1);
    });

    test('a duplicate walk-in phone is a 409 with phone fieldErrors', () async {
      final fake = FakeCustomerRepository(
        seed: [const Customer(id: 'c1', phone: '99001122')],
      );
      final result = await fake.createCustomer(phone: '99001122');
      final error = (result as Err).error;
      expect(error.statusCode, 409);
      expect(error.fieldErrors, contains('phone'));
      expect(
        CustomerFailure.classify(
          statusCode: error.statusCode,
          code: error.code,
          fieldErrors: error.fieldErrors,
        ),
        CustomerFailure.phoneConflict,
      );
    });

    test('MAX_CUSTOMERS is a 422 with no fieldErrors and no code', () async {
      final fake = FakeCustomerRepository(
        seed: [const Customer(id: 'c1', phone: '99001122')],
        maxCustomers: 1,
      );
      final result = await fake.createCustomer(phone: '99001133');
      final error = (result as Err).error;
      expect(error.statusCode, 422);
      expect(error.fieldErrors, isNull);
      // `POST /customers` genuinely drops the code — see CustomerErrorCode.
      expect(error.code, isNull);
      expect(
        CustomerFailure.classify(
          statusCode: error.statusCode,
          code: error.code,
          fieldErrors: error.fieldErrors,
        ),
        CustomerFailure.planLimit,
      );
    });

    test('update drops createdAt, matching the PATCH response', () async {
      final fake = FakeCustomerRepository();
      final before = (await fake.getCustomer('cust-1') as Ok).value.customer;
      expect(before.createdAt, isNotNull);

      final result = await fake.updateCustomer(
        'cust-1',
        fullName: 'Батаа',
        phone: '99001122',
        email: null,
        note: null,
      );
      final updated = (result as Ok<Customer>).value;
      expect(updated.fullName, 'Батаа');
      expect(updated.email, isNull);
      expect(updated.createdAt, isNull);
    });

    test('unknown ids are 404 everywhere, never 403', () async {
      final fake = FakeCustomerRepository();
      for (final result in [
        await fake.getCustomer('nope'),
        await fake.deleteCustomer('nope'),
        await fake.getCustomerHistory('nope'),
        await fake.updateCustomer(
          'nope',
          fullName: 'X',
          phone: '99001122',
          email: null,
          note: null,
        ),
      ]) {
        final error = (result as Err).error;
        expect(error.statusCode, 404, reason: 'cross-tenant must look absent');
        expect(error.code, CustomerErrorCode.customerNotFound);
      }
    });

    test('deleting a customer with orders is 409 CUSTOMER_IN_USE', () async {
      final fake = FakeCustomerRepository(customersWithOrders: {'cust-1'});
      final result = await fake.deleteCustomer('cust-1');
      final error = (result as Err).error;
      expect(error.statusCode, 409);
      expect(error.code, CustomerErrorCode.customerInUse);
      expect(
        CustomerFailure.classify(
          statusCode: error.statusCode,
          code: error.code,
        ),
        CustomerFailure.inUse,
      );
      expect(fake.customers.length, 1, reason: 'row must survive the refusal');
    });

    test('a successful delete removes the row', () async {
      final fake = FakeCustomerRepository();
      final result = await fake.deleteCustomer('cust-1');
      expect((result as Ok<CustomerDeleteResult>).value.fullName, 'Бат');
      expect(fake.customers, isEmpty);
    });

    test(
      'history clamps rather than rejecting, matching getApiPageInfo',
      () async {
        final fake = FakeCustomerRepository(
          history: {
            'cust-1': [
              for (var i = 0; i < 5; i++) CustomerHistoryOrder(id: 'o$i'),
            ],
          },
        );
        final result = await fake.getCustomerHistory(
          'cust-1',
          page: 0,
          pageSize: 2,
        );
        final page = (result as Ok).value;
        expect(page.pagination.page, 1);
        expect(page.items.map((o) => o.id), ['o0', 'o1']);
        expect(page.pagination.total, 5);
        expect(page.pagination.totalPages, 3);
        expect(page.pagination.hasNext, isTrue);
      },
    );

    test('only account-linked customers are broadcast recipients', () async {
      final fake = FakeCustomerRepository(
        seed: [
          const Customer(id: 'c1', phone: '99001122'),
          const Customer(id: 'c2', phone: '99001133'), // walk-in
        ],
        accountLinkedPhones: {'99001122'},
      );
      expect((await fake.getBroadcastRecipientCount() as Ok).value, 1);
      final sent = await fake.sendBroadcast(title: 'T', body: 'B');
      expect((sent as Ok<CustomerBroadcastResult>).value.notified, 1);
    });

    test('an empty title or body is a 422 with fieldErrors', () async {
      final fake = FakeCustomerRepository();
      final result = await fake.sendBroadcast(title: '  ', body: '');
      final error = (result as Err).error;
      expect(error.statusCode, 422);
      expect(error.fieldErrors, containsPair('title', isNotEmpty));
      expect(error.fieldErrors, containsPair('body', isNotEmpty));
      expect(fake.broadcastsToday, 0, reason: 'rejected send costs nothing');
    });

    test('a zero-recipient send still consumes a daily send', () async {
      // The documented wart in `customer-broadcast.ts`: the audit row is the
      // rate-limit counter, so it is written regardless of recipient count.
      final fake = FakeCustomerRepository(
        seed: const [],
        dailyBroadcastLimit: 1,
      );
      final first = await fake.sendBroadcast(title: 'T', body: 'B');
      expect((first as Ok<CustomerBroadcastResult>).value.notified, 0);
      expect(fake.broadcastsToday, 1);

      final second = await fake.sendBroadcast(title: 'T', body: 'B');
      final error = (second as Err).error;
      expect(error.statusCode, 422);
      expect(error.code, CustomerErrorCode.dailyLimitReached);
      expect(error.fieldErrors, isNull);
    });

    test('the fake satisfies the frozen interface', () {
      expect(FakeCustomerRepository(), isA<CustomersRepository>());
      expect(
        RemoteCustomersRepository(dataSource: _RecordingSource()),
        isA<CustomersRepository>(),
      );
    });
  });
}
