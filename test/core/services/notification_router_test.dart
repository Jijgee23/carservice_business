import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/keys/keys.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/notification_router.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_detail_route.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/report_detail_screen.dart';
import 'package:carservice_business/features/feedback/presentation/screens/feedback_detail_screen.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_api_backend.dart';
import '../../support/app_harness.dart';
import '../../support/hive_test_setup.dart';

void signIn() {
  Authenticator.user = User(
    accessToken: 'test-token',
    refreshToken: 'test-refresh',
    id: 'test-user',
    email: 'test@example.com',
    firstName: 'Test',
    lastName: 'User',
    phone: '',
    isOwner: false,
    role: UserRole('test-role', 'Test role', const [
      'orders.view',
      'appointments.view',
    ]),
    tenant: UserTenant('test-tenant', 'Test tenant'),
  );
}

void main() {
  setUpAll(openTestHiveBoxes);

  setUp(() {
    FakeApiBackend.instance.reset();
    SubscriptionService.instance.invalidate();
  });

  testWidgets(
    'authenticated order notification reaches the routed detail screen',
    (tester) async {
      Authenticator.user = User(
        accessToken: 'test-token',
        refreshToken: 'test-refresh',
        id: 'test-user',
        email: 'test@example.com',
        firstName: 'Test',
        lastName: 'User',
        phone: '',
        isOwner: false,
        role: UserRole('test-role', 'Test role', const ['orders.view']),
        tenant: UserTenant('test-tenant', 'Test tenant'),
      );
      addTearDown(() => Authenticator.user = null);

      final harness = RouterHarness();
      addTearDown(harness.dispose);
      addTearDown(() {
        if (identical(GlobalKeys.router, harness.router)) {
          GlobalKeys.router = null;
        }
      });
      harness.authController.setAuthState(AuthState.authorized);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      NotificationRouter.route({'orderId': 'order-1'});
      await tester.pump();
      await tester.pumpAndSettle();

      expect(harness.location, '/orders/order-1');
      expect(find.byType(OrderDetailScreen), findsOneWidget);
    },
  );

  // Shell destinations use `go` (checked by location); top-level screens are
  // pushed, which doesn't change the location, so those check the screen.
  for (final (payload, location, screen)
      in <(Map<String, String>, String?, Type)>[
        (
          {'appointmentId': 'appt-1'},
          '/appointments/appt-1',
          AppointmentDetailRoute,
        ),
        ({'feedbackId': 'fb-1'}, null, FeedbackDetailScreen),
        ({'reportId': 'rep-1'}, null, ReportDetailScreen),
        // `order_assigned` (staff push when an order is assigned to you).
        (
          {'type': 'order_assigned', 'orderId': 'order-3'},
          '/orders/order-3',
          OrderDetailScreen,
        ),
        // Order payloads also carry appointmentId; the order wins.
        (
          {'orderId': 'order-2', 'appointmentId': 'appt-2'},
          '/orders/order-2',
          OrderDetailScreen,
        ),
      ]) {
    testWidgets('notification $payload opens $screen', (tester) async {
      signIn();
      addTearDown(() => Authenticator.user = null);
      final harness = RouterHarness();
      addTearDown(harness.dispose);
      addTearDown(() {
        if (identical(GlobalKeys.router, harness.router)) {
          GlobalKeys.router = null;
        }
      });
      harness.authController.setAuthState(AuthState.authorized);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      NotificationRouter.route(payload);
      await tester.pump();
      await tester.pumpAndSettle();

      if (location != null) expect(harness.location, location);
      expect(find.byType(screen), findsOneWidget);
    });
  }

  test('hasTarget is false only for id-less payloads', () {
    expect(NotificationRouter.hasTarget({'type': 'broadcast_staff'}), isFalse);
    expect(NotificationRouter.hasTarget({'appointmentId': ''}), isFalse);
    expect(NotificationRouter.hasTarget({'orderId': 'o1'}), isTrue);
    expect(
      NotificationRouter.hasTarget({'type': 'order_assigned', 'orderId': 'o1'}),
      isTrue,
    );
    expect(NotificationRouter.hasTarget({'appointment_id': 'a1'}), isTrue);
    expect(NotificationRouter.hasTarget({'reportId': 'r1'}), isTrue);
    expect(NotificationRouter.hasTarget({'feedbackId': 'f1'}), isTrue);
  });
}
