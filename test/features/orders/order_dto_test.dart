import 'package:carservice_business/features/orders/data/order_dto.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _order({
  String status = 'SCHEDULED',
  Object? total = '123.4500',
}) => {
  'id': 'order-1',
  'number': 'D1-1001',
  'status': status,
  'paymentStatus': 'PARTIAL',
  'scheduledAt': '2026-09-19T03:00:00.000Z',
  'startedAt': null,
  'completedAt': null,
  'totalAmount': total,
  'paidAmount': '23.4500',
  'notes': null,
  'createdAt': '2026-09-18T03:00:00.000Z',
  'customer': {
    'id': 'customer-1',
    'fullName': 'Бат',
    'phone': '99001122',
    'email': null,
  },
  'vehicle': {
    'id': 'vehicle-1',
    'plate': '1234ABC',
    'make': 'Toyota',
    'model': 'Prius',
    'year': 2020,
    'vin': null,
    'mileage': null,
  },
  'branch': {'id': 'branch-1', 'name': 'Толгойт'},
  'assignedTo': null,
};

void main() {
  test('preserves decimal strings and unwraps order response', () {
    final dto = OrderSummaryDto.fromJson({'order': _order()});
    expect(dto.value.totalAmountMoney?.raw, '123.4500');
    expect(dto.value.paidAmountMoney?.raw, '23.4500');
    expect(dto.value.paymentStatus.name, 'PARTIAL');
  });

  test('rejects unknown status instead of defaulting to SCHEDULED', () {
    expect(
      () => OrderSummaryDto.fromJson({'order': _order(status: 'FUTURE')}),
      throwsA(isA<OrderParseException>()),
    );
  });

  test('rejects the retired WAITING_PARTS status defensively', () {
    expect(
      () =>
          OrderSummaryDto.fromJson({'order': _order(status: 'WAITING_PARTS')}),
      throwsA(isA<OrderParseException>()),
    );
  });

  test('accepts nullable totalAmount but rejects invalid money and dates', () {
    final nullableTotal = OrderSummaryDto.fromJson({
      'order': _order(total: null),
    });
    expect(nullableTotal.value.totalAmountMoney, isNull);
    expect(
      () => OrderSummaryDto.fromJson({'order': _order(total: 'not-money')}),
      throwsA(isA<OrderParseException>()),
    );
    final malformed = _order()..['createdAt'] = '2026-09-19';
    expect(
      () => OrderSummaryDto.fromJson({'order': malformed}),
      throwsA(isA<OrderParseException>()),
    );
  });

  test(
    'parses optional server progress and preserves missing compatibility',
    () {
      final valid = _order()..['progress'] = {'total': 4, 'completed': 2};
      expect(
        OrderSummaryDto.fromJson({'order': valid}).value.progress,
        const OrderProgressSummary(total: 4, completed: 2),
      );
      expect(
        OrderSummaryDto.fromJson({'order': _order()}).value.progress,
        isNull,
      );
    },
  );

  test('parses the service preview and tolerates a bad one', () {
    final withPreview = _order()
      ..['servicePreview'] = ['Тос солих', 7, 'Тоормос засах'];
    expect(
      OrderSummaryDto.fromJson({'order': withPreview}).value.servicePreview,
      ['Тос солих', 'Тоормос засах'],
    );
    for (final preview in <Object?>[null, 'Тос солих', 3]) {
      final order = _order()..['servicePreview'] = preview;
      expect(
        OrderSummaryDto.fromJson({'order': order}).value.servicePreview,
        isEmpty,
        reason: 'servicePreview=$preview',
      );
    }
  });

  test('rejects malformed present progress', () {
    for (final progress in <Object?>[
      null,
      {'total': -1, 'completed': 0},
      {'total': 2, 'completed': -1},
      {'total': 1, 'completed': 2},
      {'total': 1.0, 'completed': 0},
      {'total': 1},
    ]) {
      final order = _order()..['progress'] = progress;
      expect(
        () => OrderSummaryDto.fromJson({'order': order}),
        throwsA(isA<OrderParseException>()),
        reason: 'progress=$progress',
      );
    }
  });

  test('discards malformed QPay URL entries but keeps valid entries', () {
    final dto = QPayStateDto.fromJson({
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
            'logo': 'logo',
            'description': 'description',
            'link': 'bank://pay',
          },
          {'name': 'Missing link'},
          'not-an-object',
        ],
      },
    });

    expect(dto.value.pending, isNotNull);
    expect(dto.value.pending!.urls, hasLength(1));
    expect(dto.value.pending!.urls.single.link, 'bank://pay');
    expect(dto.value.pending!.urls.single.nameMn, 'Зөв банк');
  });

  test('parses item lifecycle and cancellation metadata', () {
    final order = _order()
      ..addAll({
        'items': [
          {
            'id': 'item-1',
            'kind': 'PART',
            'description': 'Шүүлтүүр',
            'quantity': '1.000',
            'unitPrice': '10.00',
            'total': '10.000',
            'serviceId': null,
            'status': 'CANCELLED',
            'startedAt': null,
            'completedAt': null,
            'cancelledAt': '2026-09-19T04:00:00.000Z',
            'cancelledById': 'user-1',
            'cancelledBy': {'id': 'user-1', 'firstName': 'Н', 'lastName': 'Б'},
          },
        ],
        'reports': [],
        'paidAt': null,
        'updatedAt': '2026-09-19T04:00:00.000Z',
      });
    final detail = OrderDetailDto.fromJson({'order': order}).value;
    expect(detail.items.single.status.name, 'CANCELLED');
    expect(detail.items.single.unitPriceMoney?.raw, '10.00');
    expect(detail.items.single.cancelledBy?.id, 'user-1');
  });

  test(
    'legacy domain parsers reject unknown enums and malformed required fields',
    () {
      expect(
        () => OrderStatus.fromString('FUTURE'),
        throwsA(isA<OrderParseException>()),
      );
      expect(
        () => PaymentStatus.fromString('UNKNOWN'),
        throwsA(isA<OrderParseException>()),
      );
      expect(
        () => ItemKind.fromString('OTHER'),
        throwsA(isA<OrderParseException>()),
      );
      expect(
        () => ServiceItem.fromJson({
          'id': 'i1',
          'kind': 'LABOR',
          'description': 'work',
          'quantity': '1',
          'unitPrice': '2',
          'total': '2',
          'status': 'UNKNOWN',
        }),
        throwsA(isA<OrderParseException>()),
      );
    },
  );
}
