import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_appointment_repository.dart';
import '../../fakes/fake_order_repository.dart';

User _owner() => User(
  accessToken: 't',
  refreshToken: 'r',
  id: 'u1',
  email: 'u@example.com',
  firstName: 'U',
  lastName: 'U',
  phone: '',
  isOwner: true,
  role: UserRole('r1', 'Owner', const []),
  tenant: UserTenant('t1', 'Tenant'),
);

/// Every section filled, and every action and payment button on offer.
AppointmentSummary _full(AppointmentStatus status) => AppointmentSummary(
  id: 'a1',
  status: status,
  requestedAt: DateTime(2026, 10, 18, 10, 30),
  createdAt: DateTime(2026, 10, 14, 16, 5),
  branch: const AppointmentBranchRef(id: 'b1', name: 'Үндсэн салбар'),
  customer: const AppointmentCustomerRef(
    id: 'c1',
    fullName: 'Батболд Ганзориг',
    phone: '99112233',
  ),
  vehicle: const AppointmentVehicleRef(
    id: 'v1',
    plate: '1234УБА',
    make: 'Toyota',
    model: 'Prius 41',
  ),
  category: const AppointmentCategoryRef(id: 'cat', name: 'Оношилгоо'),
  assignedToId: 'm1',
  assignedTo: const AppointmentAssigneeRef(id: 'm1', name: 'Мөнх-Эрдэнэ'),
  note: 'Хөдөлгүүрийн дуу чимээ гарна, тосоо солиулах хүсэлтэй.',
  paymentStatus: AppointmentBookingPaymentStatus.PENDING,
  serviceOrder: const AppointmentOrderRef(id: 'o1', number: 1042),
);

Future<void> _pump(
  WidgetTester tester,
  AppointmentSummary appt, {
  double width = 393,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppointmentDetailScreen(
        initial: appt,
        repo: FakeAppointmentRepository(seed: [appt]),
        ordersRepository: FakeOrderRepository(),
        user: _owner(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final status in [
    AppointmentStatus.PENDING,
    AppointmentStatus.CONFIRMED,
  ]) {
    testWidgets(
      '${status.name}: a 320dp phone at 1.5x text lays out without overflow',
      (tester) async {
        await _pump(tester, _full(status), width: 320, textScale: 1.5);
        expect(tester.takeException(), isNull);
        expect(find.text('Хариуцах мастер'), findsOneWidget);
        expect(find.text('#1042'), findsOneWidget);
      },
    );
  }

  testWidgets('shows the plate and offers a call when there is a phone', (
    tester,
  ) async {
    await _pump(tester, _full(AppointmentStatus.CONFIRMED));
    expect(find.text('1234УБА'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appointment_call_button')),
      findsOneWidget,
    );
  });

  testWidgets('no phone, no call button', (tester) async {
    await _pump(
      tester,
      AppointmentSummary(
        id: 'a2',
        status: AppointmentStatus.CONFIRMED,
        requestedAt: DateTime(2026, 10, 18, 10, 30),
        customer: const AppointmentCustomerRef(id: 'c2', fullName: 'Нэргүй'),
      ),
    );
    expect(find.byKey(const ValueKey('appointment_call_button')), findsNothing);
  });
}
