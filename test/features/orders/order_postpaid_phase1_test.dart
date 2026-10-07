import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/features/orders/data/order_dto.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json(Map<String, dynamic> extra) => {
  'id': 'o1',
  'number': 'D1-1',
  'status': 'IN_PROGRESS',
  'paymentStatus': 'UNPAID',
  'totalAmount': '1000.00',
  'paidAmount': '0.00',
  'createdAt': '2026-09-18T03:00:00.000Z',
  'customer': {'id': 'c1', 'fullName': 'Бат', 'phone': '99001122'},
  'vehicle': {'id': 'v1', 'plate': '1234ABC', 'make': 'T', 'model': 'P'},
  'branch': {'id': 'b1', 'name': 'Толгойт'},
  ...extra,
};

ServiceOrderSummary _order({required bool postpaid, double paid = 0}) =>
    OrderSummaryDto.fromJson(
      _json({'isPostpaid': postpaid, 'paidAmount': paid.toStringAsFixed(2)}),
    ).value;

void main() {
  group('completionBlocker', () {
    test('non-postpaid unpaid is blocked regardless of permission', () {
      final o = _order(postpaid: false);
      expect(o.completionBlocker(), contains('төлөгдөөгүй'));
      expect(
        o.completionBlocker(canCloseUnpaidPostpaid: true),
        contains('төлөгдөөгүй'),
      );
    });

    test('postpaid unpaid without permission is blocked', () {
      expect(
        _order(postpaid: true).completionBlocker(),
        contains('Дараа тооцоот: төлбөр дутуу'),
      );
    });

    test('postpaid unpaid with permission is allowed', () {
      expect(
        _order(postpaid: true).completionBlocker(canCloseUnpaidPostpaid: true),
        isNull,
      );
    });

    test('fully paid is allowed', () {
      expect(_order(postpaid: false, paid: 1000).completionBlocker(), isNull);
      expect(_order(postpaid: true, paid: 1000).completionBlocker(), isNull);
    });
  });

  group('DTO parsing', () {
    test('parses new fields', () {
      final o = OrderSummaryDto.fromJson(
        _json({
          'isPostpaid': true,
          'paidInFullBeforeCompletion': true,
          'plateSnapshot': '1234ABC',
          'vinSnapshot': 'VIN123',
        }),
      ).value;
      expect(o.paidInFullBeforeCompletion, isTrue);
      expect(o.plateSnapshot, '1234ABC');
      expect(o.vinSnapshot, 'VIN123');
    });

    test('defaults when absent and flows into detail', () {
      final o = OrderSummaryDto.fromJson(_json({})).value;
      expect(o.paidInFullBeforeCompletion, isFalse);
      expect(o.plateSnapshot, isNull);
      final d = OrderDetailDto.fromJson(
        _json({
          'items': [],
          'reports': [],
          'paidInFullBeforeCompletion': true,
          'plateSnapshot': 'X',
        }),
      ).value;
      expect(d.paidInFullBeforeCompletion, isTrue);
      expect(d.plateSnapshot, 'X');
    });

    test('vehicle summary parses isPostpaid, default false', () {
      final base = {'id': 'v', 'plate': 'p', 'make': 'm', 'model': 'x'};
      expect(VehicleSummary.fromJson(base).isPostpaid, isFalse);
      expect(
        VehicleSummary.fromJson({...base, 'isPostpaid': true}).isPostpaid,
        isTrue,
      );
    });
  });
}
