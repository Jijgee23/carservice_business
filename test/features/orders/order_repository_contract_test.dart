import 'dart:typed_data';

import 'package:carservice_business/features/orders/data/order_repository.dart';
import 'package:carservice_business/features/orders/data/orders_data_source.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_error_codes.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source implements OrdersDataSource {
  String? method;
  Map<String, dynamic>? query;
  Map<String, dynamic>? body;
  Object? response;

  Future<Object?> _record(
    String name, {
    Map<String, dynamic>? q,
    Map<String, dynamic>? b,
  }) async {
    method = name;
    query = q;
    body = b;
    return response;
  }

  @override
  Future<Object?> list(Map<String, dynamic> q) => _record('list', q: q);
  @override
  Future<Object?> detail(String id) => _record('detail');
  @override
  Future<Object?> create(Map<String, dynamic> b) => _record('create', b: b);
  String? uploadFilename;
  String? uploadMime;
  @override
  Future<Object?> uploadIntake(Uint8List bytes, String filename, String mime) {
    uploadFilename = filename;
    uploadMime = mime;
    return _record('uploadIntake');
  }

  @override
  Future<Object?> patch(String id, Map<String, dynamic> b) =>
      _record('patch', b: b);
  @override
  Future<void> delete(String id) async {
    await _record('delete');
  }

  @override
  Future<Object?> expectedFinish(String id, Map<String, dynamic> b) =>
      _record('expectedFinish', b: b);
  @override
  Future<Object?> schedule(String id, Map<String, dynamic> b) =>
      _record('schedule', b: b);
  @override
  Future<Object?> addItem(String id, Map<String, dynamic> b) =>
      _record('addItem', b: b);
  @override
  Future<Object?> patchItem(String id, String itemId, Map<String, dynamic> b) =>
      _record('patchItem', b: b);
  @override
  Future<void> deleteItem(String id, String itemId) async {
    await _record('deleteItem');
  }

  @override
  Future<Object?> cancelItem(String id, String itemId) => _record('cancelItem');
  @override
  Future<Object?> itemStatus(
    String id,
    String itemId,
    Map<String, dynamic> b,
  ) => _record('itemStatus', b: b);
  @override
  Future<Object?> itemPrice(String id, String itemId, Map<String, dynamic> b) =>
      _record('itemPrice', b: b);
  @override
  Future<Object?> itemHistory(String id, Map<String, dynamic> q) =>
      _record('itemHistory', q: q);
  @override
  Future<Object?> payments(String id) => _record('payments');
  @override
  Future<Object?> createPayment(String id, Map<String, dynamic> b) =>
      _record('createPayment', b: b);
  @override
  Future<Object?> reversePayment(String id, String paymentId) =>
      _record('reversePayment');
  @override
  Future<Object?> banks() => _record('banks');
  @override
  Future<Object?> qpay(String id) => _record('qpay');
  @override
  Future<Object?> createQPay(String id, {String? amount}) =>
      _record('createQPay', b: amount == null ? null : {'amount': amount});
  @override
  Future<Object?> checkQPay(String id, Map<String, dynamic> b) =>
      _record('checkQPay', b: b);
  @override
  Future<void> cancelQPay(String id, Map<String, dynamic> b) async {
    await _record('cancelQPay', b: b);
  }

  @override
  Future<Object?> postpaid(Map<String, dynamic> q) => _record('postpaid', q: q);
  @override
  Future<Object?> assignableUsers(Map<String, dynamic> q) =>
      _record('assignableUsers', q: q);
  @override
  Future<Object?> bulkStatus(Map<String, dynamic> b) =>
      _record('bulkStatus', b: b);
  @override
  Future<Object?> bulkAssign(Map<String, dynamic> b) =>
      _record('bulkAssign', b: b);
}

Map<String, dynamic> _page() => {
  'orders': <Object?>[],
  'pagination': {
    'page': 1,
    'pageSize': 25,
    'total': 0,
    'totalPages': 0,
    'hasPrev': false,
    'hasNext': false,
  },
};

Map<String, dynamic> _summaryResponse() => {
  'order': {
    'id': 'o1',
    'number': 'O-1',
    'status': 'SCHEDULED',
    'paymentStatus': 'UNPAID',
    'scheduledAt': null,
    'startedAt': null,
    'completedAt': null,
    'totalAmount': null,
    'paidAmount': '0',
    'notes': null,
    'createdAt': '2026-09-19T04:00:00.000Z',
    'customer': {'id': 'c1', 'fullName': 'Customer', 'phone': '99001122'},
    'vehicle': {
      'id': 'v1',
      'plate': '1234ABC',
      'make': 'Toyota',
      'model': 'Prius',
    },
    'branch': {'id': 'b1', 'name': 'Branch'},
    'assignedTo': null,
  },
};

Map<String, dynamic> _scheduleResponse({String key = 'scheduledAt'}) => {
  'orderId': 'o1',
  if (key == 'scheduledAt') 'scheduledAt': '2026-09-19T03:04:05.000Z',
  if (key == 'expectedFinishAt') 'expectedFinishAt': '2026-09-19T03:04:05.000Z',
};

Map<String, dynamic> _detailResponse() {
  final order = Map<String, dynamic>.from(_summaryResponse()['order'] as Map)
    ..addAll({
      'items': [
        {
          'id': 'i1',
          'kind': 'PART',
          'description': 'Part',
          'quantity': '1.000',
          'unitPrice': '10.00',
          'total': '10.000',
          'status': 'PENDING',
          'startedAt': null,
          'completedAt': null,
          'cancelledAt': null,
          'cancelledById': null,
          'cancelledBy': null,
          'serviceId': null,
        },
      ],
      'reports': [],
      'paidAt': null,
      'updatedAt': null,
    });
  return {'order': order};
}

Map<String, dynamic> _itemResponse() => {
  'item': {
    'id': 'i1',
    'kind': 'PART',
    'description': 'Part',
    'quantity': '1.000',
    'unitPrice': '10.00',
    'total': '10.000',
    'status': 'PENDING',
    'startedAt': null,
    'completedAt': null,
    'cancelledAt': null,
    'cancelledById': null,
    'cancelledBy': null,
    'serviceId': null,
  },
};

Map<String, dynamic> _historyResponse() => {
  'items': [_itemResponse()['item']],
  'page': 1,
  'pageSize': 20,
  'total': 1,
  'totalPages': 1,
};

Map<String, dynamic> _paymentListResponse() => {
  'payments': [
    {
      'id': 'p1',
      'amount': '10.00',
      'method': 'CASH',
      'status': 'PAID',
      'paidAt': null,
      'createdAt': '2026-09-19T04:00:00.000Z',
    },
  ],
};

Map<String, dynamic> _totalsResponse() => {
  'order': {
    'totalAmount': '100.00',
    'paidAmount': '10.00',
    'remainingAmount': '90.00',
    'paymentStatus': 'PARTIAL',
  },
};

Map<String, dynamic> _qpayResponse() => {
  'qpayEnabled': true,
  'pending': {
    'id': 'q1',
    'amount': '90.00',
    'qrImage': 'image',
    'qrText': 'text',
    'urls': [],
  },
};

Map<String, dynamic> _qpayPaymentResponse() => {
  'payment': {
    'id': 'q1',
    'amount': '90.00',
    'qrImage': 'image',
    'qrText': 'text',
    'urls': [],
  },
};

Map<String, dynamic> _postpaidResponse() => {
  'vehicles': [],
  'summary': {
    'orderCount': 0,
    'totalAmount': '0',
    'paidAmount': '0',
    'balanceAmount': '0',
  },
  'orders': [],
  'pagination': {
    'page': 1,
    'pageSize': 25,
    'total': 0,
    'totalPages': 0,
    'hasPrev': false,
    'hasNext': false,
  },
};

Map<String, dynamic> _bulkResponse() => {
  'succeeded': ['o1'],
  'failed': [
    {'orderId': 'missing', 'code': 'NOT_FOUND', 'message': 'missing'},
  ],
};

void main() {
  test(
    'serializes every list filter with business dates and encoded search value',
    () async {
      final source = _Source()..response = _page();
      final repository = RemoteOrdersRepository(dataSource: source);
      final result = await repository.getOrders(
        query: OrderListQuery(
          status: OrderStatus.IN_PROGRESS,
          branchId: 'b/1',
          assignedToId: 'u 1',
          paymentStatus: PaymentStatus.PARTIAL,
          postpaid: true,
          dateFrom: DateTime(2026, 9, 1),
          dateTo: DateTime(2026, 9, 19),
          q: 'Бат & sons',
          vehicleId: 'v/1',
          customerId: 'c 1',
          page: 2,
          pageSize: 10,
        ),
      );
      expect(result, isA<Ok>());
      expect(source.method, 'list');
      expect(source.query, containsPair('dateFrom', '2026-09-01'));
      expect(source.query, containsPair('q', 'Бат & sons'));
      expect(source.query, containsPair('page', 2));
    },
  );

  test('rejects invalid request and response pagination', () async {
    final source = _Source()..response = _page();
    final repository = RemoteOrdersRepository(dataSource: source);
    final invalidRequest = await repository.getOrders(
      query: const OrderListQuery(page: 0),
    );
    expect(invalidRequest, isA<Err>());

    source.response = {
      'orders': <Object?>[],
      'pagination': {
        'page': 0,
        'pageSize': 25,
        'total': 0,
        'totalPages': 0,
        'hasPrev': false,
        'hasNext': false,
      },
    };
    final invalidResponse = await repository.getOrders();
    expect(invalidResponse, isA<Err>());
  });

  test('payment locked defaults to false and parses true', () async {
    Map<String, Object?> body(Map<String, Object?> extra) => {
      'payment': {
        'id': 'p1',
        'amount': '10',
        'method': 'CASH',
        'status': 'PAID',
        'paidAt': '2026-10-05T00:00:00.000Z',
        'createdAt': '2026-10-05T00:00:00.000Z',
        ...extra,
      },
      'order': {
        'totalAmount': '10',
        'paidAmount': '10',
        'remainingAmount': '0',
        'paymentStatus': 'PAID',
      },
    };
    final source = _Source();
    final repository = RemoteOrdersRepository(dataSource: source);
    Future<bool> locked(Map<String, Object?> extra) async {
      source.response = body(extra);
      final r = await repository.createPayment(
        'o1',
        method: OrderPaymentMethod.CASH,
        amount: const Money('10'),
      );
      return (r as Ok<OrderPaymentResult>).value.payment.locked;
    }

    expect(await locked({}), isFalse);
    expect(await locked({'locked': true}), isTrue);
  });

  test('payment bank is sent for CARD only and parsed (legacy reconcile fields ignored)', () async {
    final payment = {
      'id': 'p1',
      'amount': '10',
      'method': 'CARD',
      'status': 'PAID',
      'paidAt': '2026-10-05T00:00:00.000Z',
      'createdAt': '2026-10-05T00:00:00.000Z',
      'bankId': 'acc-khan',
      'bank': 'KHAN',
      'bankLabel': 'Хаан банк',
      'bankType': 'BANK_ACCOUNT',
      'bankIsTest': false,
      'reconciledAt': '2026-10-05T01:00:00.000Z',
      'reconciledBy': {'id': 'u1', 'name': 'Бат'},
    };
    final source = _Source()
      ..response = {
        'payment': payment,
        'order': {
          'totalAmount': '10',
          'paidAmount': '10',
          'remainingAmount': '0',
          'paymentStatus': 'PAID',
        },
      };
    final repository = RemoteOrdersRepository(dataSource: source);
    final created = await repository.createPayment(
      'o1',
      method: OrderPaymentMethod.CARD,
      amount: const Money('10'),
      bankId: 'acc-khan',
    );
    expect(source.body?['bankId'], 'acc-khan');
    expect(source.body?.containsKey('bank'), isFalse);
    final record = (created as Ok<OrderPaymentResult>).value.payment;
    expect(record.bankId, 'acc-khan');
    expect(record.bank, 'KHAN');
    expect(record.bankLabel, 'Хаан банк');

    await repository.createPayment(
      'o1',
      method: OrderPaymentMethod.CASH,
      amount: const Money('10'),
      bankId: 'acc-khan',
    );
    expect(source.body?.containsKey('bankId'), isFalse);

    source.response = {
      'accounts': [
        {
          'id': 'a1',
          'type': 'BANK_ACCOUNT',
          'method': 'BANK_TRANSFER',
          'name': 'Хаан банк',
          'accountNumberMasked': '••••5678',
          'terminalId': null,
          'merchantId': null,
          'isTest': false,
        },
        {
          'id': 'p1',
          'type': 'POS',
          'method': 'CARD',
          'name': 'Голомт POS',
          'accountNumberMasked': null,
          'terminalId': 'TID001',
          'merchantId': null,
          'isTest': true,
        },
      ],
      'banks': <Object?>[],
      'enabledBanks': ['KHAN', 'TDB'],
      'configured': true,
    };
    final banks = await repository.getBanks();
    final settings = (banks as Ok<BankSettings>).value;
    expect(settings.accounts.map((b) => b.id), ['a1', 'p1']);
    expect(settings.transferAccounts.single.maskedNumber, '••••5678');
    expect(settings.posAccounts.single.terminalId, 'TID001');
    expect(settings.posAccounts.single.isTest, isTrue);
  });

  test('uses ledger payment route and preserves amount as a string', () async {
    final source = _Source()
      ..response = {
        'payment': {
          'id': 'p1',
          'amount': '123.4500',
          'method': 'CASH',
          'status': 'PAID',
          'paidAt': '2026-09-19T04:00:00.000Z',
          'createdAt': '2026-09-19T04:00:00.000Z',
        },
        'order': {
          'totalAmount': '500.0000',
          'paidAmount': '123.4500',
          'remainingAmount': '376.5500',
          'paymentStatus': 'PARTIAL',
        },
      };
    final repository = RemoteOrdersRepository(dataSource: source);
    final result = await repository.createPayment(
      'o1',
      method: OrderPaymentMethod.CASH,
      amount: const Money('123.4500'),
    );
    expect(result, isA<Ok>());
    expect(source.method, 'createPayment');
    expect(source.body?['amount'], '123.4500');
    expect(
      (result as Ok<OrderPaymentResult>).value.payment.amountMoney.raw,
      '123.4500',
    );
  });

  test(
    'repository keeps a pending QPay invoice when one URL entry is malformed',
    () async {
      final source = _Source()
        ..response = {
          'qpayEnabled': true,
          'pending': {
            'id': 'q1',
            'amount': '90.00',
            'qrImage': 'image',
            'qrText': 'text',
            'urls': [
              {
                'name': 'Valid bank',
                'name_mn': 'Зөв банк',
                'link': 'bank://pay',
              },
              {'name': 'Missing link'},
            ],
          },
        };
      final repository = RemoteOrdersRepository(dataSource: source);

      final result = await repository.getQPay('o1');

      expect(result, isA<Ok>());
      final pending =
          (result as Ok<({bool qpayEnabled, OrderPayment? pending})>)
              .value
              .pending;
      expect(pending, isNotNull);
      expect(pending!.urls, hasLength(1));
      expect(pending.urls.single.link, 'bank://pay');

      source.response = {
        'payment': {
          'id': 'q1',
          'amount': '90.00',
          'urls': [
            {'name': 'Valid bank', 'link': 'bank://pay'},
            {'name': 'Missing link'},
          ],
        },
      };
      final created = await repository.createQPay('o1');
      expect(created, isA<Ok>());
      expect(source.body, isNull);
      await repository.createQPay('o1', amount: '40');
      expect(source.body, {'amount': '40'});
      expect((created as Ok<OrderPayment>).value.urls, hasLength(1));
      expect(created.value.urls.single.link, 'bank://pay');
    },
  );

  test(
    'formats create and scheduling datetimes as business-local seconds',
    () async {
      final source = _Source()..response = _summaryResponse();
      final repository = RemoteOrdersRepository(dataSource: source);
      final value = DateTime(2026, 9, 19, 3, 4, 5, 987);
      await repository.createOrder(
        branchId: 'b1',
        customerId: 'c1',
        vehicleId: 'v1',
        scheduledAt: value,
      );
      expect(source.body?['scheduledAt'], '2026-09-19T03:04:05');

      source.response = _scheduleResponse(key: 'expectedFinishAt');
      await repository.reviseExpectedFinish('o1', value);
      expect(source.body?['expectedFinishAt'], '2026-09-19T03:04:05');

      source.response = _scheduleResponse();
      await repository.rescheduleOrder('o1', value);
      expect(source.body?['scheduledAt'], '2026-09-19T03:04:05');
    },
  );

  test('passes encoded query values through Dio transport', () async {
    late RequestOptions request;
    final dio = Dio(BaseOptions(baseUrl: 'https://orders.example.test/api/v1/'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<dynamic>(requestOptions: options, data: _page()),
            );
          },
        ),
      );
    final source = RemoteOrdersDataSource(dio: dio);
    await source.list({'q': 'Бат & sons', 'branchId': 'b/1', 'page': 2});
    expect(request.uri.path, '/api/v1/orders');
    expect(request.uri.queryParameters['q'], 'Бат & sons');
    expect(request.uri.queryParameters['branchId'], 'b/1');
    expect(request.uri.query, contains('q='));
    expect(request.uri.query, contains('%26'));
  });

  test('maps the complete Orders transport route matrix', () async {
    final requests = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://orders.example.test/api/v1/'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add('${options.method} ${options.uri.path}');
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: <String, dynamic>{},
              ),
            );
          },
        ),
      );
    final source = RemoteOrdersDataSource(dio: dio);
    await source.list({});
    await source.detail('o1');
    await source.create({});
    await source.patch('o1', {});
    await source.delete('o1');
    await source.expectedFinish('o1', {});
    await source.schedule('o1', {});
    await source.addItem('o1', {});
    await source.patchItem('o1', 'i1', {});
    await source.deleteItem('o1', 'i1');
    await source.cancelItem('o1', 'i1');
    await source.itemStatus('o1', 'i1', {});
    await source.itemPrice('o1', 'i1', {});
    await source.itemHistory('o1', {});
    await source.payments('o1');
    await source.createPayment('o1', {});
    await source.reversePayment('o1', 'p1');
    await source.qpay('o1');
    await source.createQPay('o1');
    await source.checkQPay('o1', {});
    await source.cancelQPay('o1', {});
    await source.postpaid({});
    await source.assignableUsers({});
    await source.bulkStatus({});
    await source.bulkAssign({});

    expect(
      requests,
      containsAll(<String>[
        'GET /api/v1/orders',
        'GET /api/v1/orders/o1',
        'POST /api/v1/orders',
        'PATCH /api/v1/orders/o1',
        'DELETE /api/v1/orders/o1',
        'PATCH /api/v1/orders/o1/expected-finish',
        'PATCH /api/v1/orders/o1/schedule',
        'POST /api/v1/orders/o1/items',
        'PATCH /api/v1/orders/o1/items/i1',
        'DELETE /api/v1/orders/o1/items/i1',
        'POST /api/v1/orders/o1/items/i1/cancel',
        'POST /api/v1/orders/o1/items/i1/status',
        'PATCH /api/v1/orders/o1/items/i1/price',
        'GET /api/v1/orders/o1/items/history',
        'GET /api/v1/orders/o1/payments',
        'POST /api/v1/orders/o1/payments',
        'POST /api/v1/orders/o1/payments/p1/reverse',
        'GET /api/v1/orders/o1/qpay',
        'POST /api/v1/orders/o1/qpay',
        'POST /api/v1/orders/o1/qpay/check',
        'DELETE /api/v1/orders/o1/qpay',
        'GET /api/v1/orders/postpaid',
        'GET /api/v1/orders/assignable-users',
        'POST /api/v1/orders/bulk/status',
        'POST /api/v1/orders/bulk/assign',
      ]),
    );
  });

  test(
    'repository contract covers every method body/query and response parser',
    () async {
      final source = _Source();
      final repository = RemoteOrdersRepository(dataSource: source);

      source.response = _page();
      expect(await repository.getOrders(page: 2, pageSize: 10), isA<Ok>());
      expect(source.method, 'list');
      expect(source.query, containsPair('pageSize', 10));

      source.response = _detailResponse();
      expect(await repository.getOrderDetail('o1'), isA<Ok>());
      expect(source.method, 'detail');

      source.response = _summaryResponse();
      expect(
        await repository.createOrder(
          branchId: 'b1',
          customerId: 'c1',
          vehicleId: 'v1',
          assignedToId: 'u1',
          notes: 'note',
        ),
        isA<Ok>(),
      );
      expect(source.method, 'create');
      expect(source.body, containsPair('branchId', 'b1'));
      expect(source.body, containsPair('assignedToId', 'u1'));

      source.response = _detailResponse();
      expect(
        await repository.updateStatus(
          'o1',
          OrderStatus.IN_PROGRESS,
          durationMinutes: 45,
        ),
        isA<Ok>(),
      );
      expect(source.method, 'patch');
      expect(source.body, containsPair('status', 'IN_PROGRESS'));
      expect(source.body, containsPair('durationMinutes', 45));
      expect(await repository.updateAssignment('o1', 'u1'), isA<Ok>());
      expect(source.body, containsPair('assignedToId', 'u1'));
      expect(await repository.deleteOrder('o1'), isA<Ok>());
      expect(source.method, 'delete');

      source.response = _scheduleResponse(key: 'expectedFinishAt');
      expect(
        await repository.reviseExpectedFinish(
          'o1',
          DateTime(2026, 9, 19, 3, 4, 5),
        ),
        isA<Ok>(),
      );
      expect(source.method, 'expectedFinish');
      expect(source.body, containsPair('confirmed', false));
      source.response = _scheduleResponse();
      expect(
        await repository.rescheduleOrder('o1', DateTime(2026, 9, 19, 3, 4, 5)),
        isA<Ok>(),
      );
      expect(source.method, 'schedule');

      source.response = _itemResponse();
      expect(
        await repository.addItemMoney(
          'o1',
          kind: ItemKind.PART,
          description: 'Part',
          quantity: const Money('1.250'),
          unitPrice: const Money('10.00'),
          serviceId: 's1',
          diagnosticTemplateId: 'd1',
        ),
        isA<Ok>(),
      );
      expect(source.method, 'addItem');
      expect(source.body, containsPair('quantity', '1.250'));
      expect(source.body, containsPair('diagnosticTemplateId', 'd1'));
      expect(
        await repository.updateItemMoney(
          'o1',
          'i1',
          status: ServiceItemStatus.COMPLETED,
          unitPrice: const Money('11.00'),
        ),
        isA<Ok>(),
      );
      expect(source.method, 'patchItem');
      expect(source.body, containsPair('status', 'COMPLETED'));
      expect(source.body, containsPair('unitPrice', '11.00'));
      expect(await repository.removeItem('o1', 'i1'), isA<Ok>());
      expect(source.method, 'deleteItem');
      expect(await repository.cancelItem('o1', 'i1'), isA<Ok>());
      expect(source.method, 'cancelItem');
      source.response = _itemResponse();
      expect(
        await repository.changeItemStatus(
          'o1',
          'i1',
          ServiceItemStatus.IN_PROGRESS,
        ),
        isA<Ok>(),
      );
      expect(source.method, 'itemStatus');
      expect(source.body, containsPair('status', 'IN_PROGRESS'));
      expect(
        await repository.changeItemPrice('o1', 'i1', const Money('12.00')),
        isA<Ok>(),
      );
      expect(source.method, 'itemPrice');
      expect(source.body, containsPair('unitPrice', '12.00'));
      source.response = _historyResponse();
      expect(
        await repository.getItemHistory('o1', page: 2, pageSize: 5),
        isA<Ok>(),
      );
      expect(source.method, 'itemHistory');
      expect(source.query, containsPair('pageSize', 5));

      source.response = _paymentListResponse();
      expect(await repository.getPayments('o1'), isA<Ok>());
      expect(source.method, 'payments');
      source.response = {
        'payment': _paymentListResponse()['payments'] is List
            ? (_paymentListResponse()['payments'] as List).single
            : null,
        ..._totalsResponse(),
      };
      expect(
        await repository.createPayment(
          'o1',
          method: OrderPaymentMethod.CASH,
          amount: const Money('10.00'),
        ),
        isA<Ok>(),
      );
      expect(source.method, 'createPayment');
      expect(source.body, containsPair('amount', '10.00'));
      source.response = _totalsResponse();
      expect(await repository.reversePayment('o1', 'p1'), isA<Ok>());
      expect(source.method, 'reversePayment');

      source.response = _qpayResponse();
      expect(await repository.getQPay('o1'), isA<Ok>());
      expect(source.method, 'qpay');
      source.response = _qpayPaymentResponse();
      expect(await repository.createQPay('o1'), isA<Ok>());
      expect(source.method, 'createQPay');
      source.response = {'paid': true, 'message': 'paid'};
      expect(await repository.checkQPay('o1', 'q1'), isA<Ok>());
      expect(source.method, 'checkQPay');
      expect(source.body, containsPair('paymentId', 'q1'));
      expect(await repository.cancelQPay('o1', 'q1'), isA<Ok>());
      expect(source.method, 'cancelQPay');

      source.response = _postpaidResponse();
      expect(
        await repository.getPostpaid(
          query: const PostpaidQuery(page: 2, pageSize: 3),
        ),
        isA<Ok>(),
      );
      expect(source.method, 'postpaid');
      expect(source.query, containsPair('pageSize', 3));
      source.response = {
        'users': [
          {'id': 'u1', 'firstName': 'A', 'lastName': 'B'},
        ],
      };
      expect(await repository.getAssignableUsers(branchId: 'b1'), isA<Ok>());
      expect(source.method, 'assignableUsers');
      expect(source.query, containsPair('branchId', 'b1'));
      source.response = _bulkResponse();
      expect(
        await repository.bulkChangeStatus(
          ['o1', 'missing'],
          OrderStatus.CANCELLED,
          durationMinutes: 10,
        ),
        isA<Ok>(),
      );
      expect(source.method, 'bulkStatus');
      expect(source.body, containsPair('durationMinutes', 10));
      expect(await repository.bulkAssign(['o1'], 'u1'), isA<Ok>());
      expect(source.method, 'bulkAssign');
      expect(source.body, containsPair('assignedToId', 'u1'));
    },
  );

  test('repository turns malformed success payloads into AppError', () async {
    final source = _Source()..response = <String, dynamic>{};
    final repository = RemoteOrdersRepository(dataSource: source);
    expect(await repository.getOrderDetail('o1'), isA<Err>());
    expect(
      await repository.createOrder(
        branchId: 'b',
        customerId: 'c',
        vehicleId: 'v',
      ),
      isA<Err>(),
    );
    expect(
      await repository.updateStatus('o1', OrderStatus.CANCELLED),
      isA<Err>(),
    );
    expect(
      await repository.addItemMoney(
        'o1',
        kind: ItemKind.PART,
        description: 'x',
        quantity: const Money('1'),
        unitPrice: const Money('1'),
      ),
      isA<Err>(),
    );
    expect(
      await repository.updateItemMoney('o1', 'i1', unitPrice: const Money('1')),
      isA<Err>(),
    );
    expect(
      await repository.changeItemStatus(
        'o1',
        'i1',
        ServiceItemStatus.CANCELLED,
      ),
      isA<Err>(),
    );
    expect(
      await repository.changeItemPrice('o1', 'i1', const Money('1')),
      isA<Err>(),
    );
    expect(await repository.getItemHistory('o1'), isA<Err>());
    expect(await repository.getPayments('o1'), isA<Err>());
    expect(
      await repository.createPayment(
        'o1',
        method: OrderPaymentMethod.CASH,
        amount: const Money('1'),
      ),
      isA<Err>(),
    );
    expect(await repository.reversePayment('o1', 'p1'), isA<Err>());
    expect(await repository.getQPay('o1'), isA<Err>());
    expect(await repository.createQPay('o1'), isA<Err>());
    expect(await repository.checkQPay('o1', 'q1'), isA<Err>());
    expect(await repository.getPostpaid(), isA<Err>());
    expect(await repository.getAssignableUsers(), isA<Err>());
    expect(
      await repository.bulkChangeStatus(['o1'], OrderStatus.CANCELLED),
      isA<Err>(),
    );
    expect(await repository.bulkAssign(['o1'], 'u1'), isA<Err>());
  });

  test('createOrder sends appointmentId only when given, omits estimatedDurationMinutes', () async {
    final source = _Source()..response = _summaryResponse();
    final repository = RemoteOrdersRepository(dataSource: source);
    final result = await repository.createOrder(
      branchId: 'b1',
      customerId: 'c1',
      vehicleId: 'v1',
      appointmentId: 'appt-1',
    );
    expect(result, isA<Ok>());
    expect(source.body, containsPair('appointmentId', 'appt-1'));
    expect(source.body!.containsKey('estimatedDurationMinutes'), isFalse);
  });

  test('createOrder sends estimatedDurationMinutes only when given, omits appointmentId', () async {
    final source = _Source()..response = _summaryResponse();
    final repository = RemoteOrdersRepository(dataSource: source);
    final result = await repository.createOrder(
      branchId: 'b1',
      customerId: 'c1',
      vehicleId: 'v1',
      estimatedDurationMinutes: 45,
    );
    expect(result, isA<Ok>());
    expect(source.body, containsPair('estimatedDurationMinutes', 45));
    expect(source.body!.containsKey('appointmentId'), isFalse);
  });

  test('createOrder sends neither appointmentId nor estimatedDurationMinutes when both omitted', () async {
    final source = _Source()..response = _summaryResponse();
    final repository = RemoteOrdersRepository(dataSource: source);
    final result = await repository.createOrder(
      branchId: 'b1',
      customerId: 'c1',
      vehicleId: 'v1',
    );
    expect(result, isA<Ok>());
    expect(source.body!.containsKey('appointmentId'), isFalse);
    expect(source.body!.containsKey('estimatedDurationMinutes'), isFalse);
  });

  test('createOrder rejects appointmentId and estimatedDurationMinutes together without calling the data source', () async {
    final source = _Source();
    final repository = RemoteOrdersRepository(dataSource: source);
    final result = await repository.createOrder(
      branchId: 'b1',
      customerId: 'c1',
      vehicleId: 'v1',
      appointmentId: 'appt-1',
      estimatedDurationMinutes: 45,
    );
    expect(result, isA<Err>());
    expect(
      (result as Err).error.message,
      'Цаг захиалгатай үед хугацааг цаг захиалгаас авна.',
    );
    expect(source.method, isNull);
  });

  test(
    'preserves stale working-branch 403 message from shared transport',
    () async {
      final dio =
          Dio(BaseOptions(baseUrl: 'https://orders.example.test/api/v1/'))
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      response: Response<dynamic>(
                        requestOptions: options,
                        statusCode: 403,
                        data: {
                          'error': 'working branch is stale',
                          'code': 'WORKING_BRANCH_STALE',
                          'fieldErrors': {'branchId': 'stale'},
                        },
                      ),
                    ),
                  );
                },
              ),
            );
      final repository = RemoteOrdersRepository(
        dataSource: RemoteOrdersDataSource(dio: dio),
      );
      final result = await repository.getOrders();
      expect(result, isA<Err>());
      expect((result as Err).error.kind, ErrorKind.forbidden);
      expect((result as Err).error.message, 'working branch is stale');
      expect((result as Err).error.statusCode, 403);
      expect((result as Err).error.code, 'WORKING_BRANCH_STALE');
      expect((result as Err).error.fieldErrors, {'branchId': 'stale'});
    },
  );

  test('preserves confirmation metadata from a 409 response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://orders.example.test/api/v1/'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 409,
                  data: {
                    'error': 'confirmation required',
                    'code': OrdersErrorCodes.confirmationRequired,
                    'fieldErrors': {'confirmNeeded': 'true'},
                  },
                ),
              ),
            );
          },
        ),
      );
    final result = await RemoteOrdersRepository(
      dataSource: RemoteOrdersDataSource(dio: dio),
    ).getOrders();

    expect(result, isA<Err>());
    final error = (result as Err).error;
    expect(error.kind, ErrorKind.unknown);
    expect(error.statusCode, 409);
    expect(error.code, OrdersErrorCodes.confirmationRequired);
    expect(error.fieldErrors, {'confirmNeeded': 'true'});
  });

  test('ignores malformed transport metadata without throwing', () async {
    final payloads = <Map<String, dynamic>>[
      {
        'error': 'bad metadata',
        'code': 409,
        'fieldErrors': {'confirmNeeded': 'true'},
      },
      {'error': 'bad metadata', 'code': 'CODE', 'fieldErrors': 'not-a-map'},
      {
        'error': 'bad metadata',
        'code': 'CODE',
        'fieldErrors': {'confirmNeeded': true},
      },
    ];

    for (final payload in payloads) {
      final dio =
          Dio(BaseOptions(baseUrl: 'https://orders.example.test/api/v1/'))
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      response: Response<dynamic>(
                        requestOptions: options,
                        statusCode: 422,
                        data: payload,
                      ),
                    ),
                  );
                },
              ),
            );
      final result = await RemoteOrdersRepository(
        dataSource: RemoteOrdersDataSource(dio: dio),
      ).getOrders();
      final error = (result as Err).error;

      expect(error.statusCode, 422);
      expect(error.message, 'bad metadata');
      if (payload['code'] is String) {
        expect(error.code, 'CODE');
      } else {
        expect(error.code, isNull);
      }
      if (payload['fieldErrors'] is Map &&
          (payload['fieldErrors'] as Map).values.every(
            (value) => value is String,
          )) {
        expect(error.fieldErrors, {'confirmNeeded': 'true'});
      } else {
        expect(error.fieldErrors, isNull);
      }
    }
  });

  test('an overpaid order (negative balance) parses instead of failing', () async {
    // total − paid goes negative when an item is cancelled after full payment.
    final source = _Source()
      ..response = {
        ..._postpaidResponse(),
        'summary': {
          'orderCount': 1,
          'totalAmount': '80000',
          'paidAmount': '100000',
          'balanceAmount': '-20000',
        },
      };
    final result = await RemoteOrdersRepository(dataSource: source)
        .getPostpaid();
    expect(result, isA<Ok>());
    expect((result as Ok).value.summary.balanceAmountMoney.raw, '-20000');
  });

  test('ordinary amounts still reject negatives', () async {
    final source = _Source()
      ..response = {
        ..._postpaidResponse(),
        'summary': {
          'orderCount': 1,
          'totalAmount': '-5',
          'paidAmount': '0',
          'balanceAmount': '0',
        },
      };
    expect(
      await RemoteOrdersRepository(dataSource: source).getPostpaid(),
      isA<Err>(),
    );
  });
}
