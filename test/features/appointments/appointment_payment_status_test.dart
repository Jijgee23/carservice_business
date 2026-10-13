import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/appointment_detail_controller.dart';

import '../../fakes/fake_order_repository.dart';

Map<String, dynamic> _json([Object? paymentStatus]) => {
  'id': 'a1',
  'status': 'CONFIRMED',
  'paymentStatus': ?paymentStatus,
};

void main() {
  test('AppointmentSummary parses the server paymentStatus', () {
    expect(
      AppointmentSummary.fromJson(_json('NOT_REQUIRED')).paymentStatus,
      AppointmentBookingPaymentStatus.NOT_REQUIRED,
    );
    expect(
      AppointmentSummary.fromJson(_json('PAID')).paymentStatus,
      AppointmentBookingPaymentStatus.PAID,
    );
  });

  test('AppointmentSummary maps REFUNDED explicitly (not unknown)', () {
    final status = AppointmentSummary.fromJson(_json('REFUNDED')).paymentStatus;
    expect(status, AppointmentBookingPaymentStatus.REFUNDED);
    expect(status!.label, 'Төлбөр буцаагдсан');
  });

  test('an older server without the field leaves paymentStatus null', () {
    expect(AppointmentSummary.fromJson(_json()).paymentStatus, isNull);
  });

  test('detail controller seeds its payment state from the appointment', () {
    final seeded = AppointmentDetailController(
      initial: AppointmentSummary.fromJson(_json('PENDING')),
      ordersRepository: FakeOrderRepository(),
    );
    addTearDown(seeded.dispose);
    expect(seeded.paymentStatus, AppointmentBookingPaymentStatus.PENDING);

    final legacy = AppointmentDetailController(
      initial: AppointmentSummary.fromJson(_json()),
      ordersRepository: FakeOrderRepository(),
    );
    addTearDown(legacy.dispose);
    expect(legacy.paymentStatus, AppointmentBookingPaymentStatus.unknown);
  });
}
