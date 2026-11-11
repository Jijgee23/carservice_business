import 'package:carservice_business/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carservice_business/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Future<AuthResponse> server(String path, Map<String, dynamic> body) async => switch (path) {
    'auth/check-email' => const AuthResponse(200, {'status': 'password', 'identifier': '99112233'}),
    'auth/login' => const AuthResponse(423, {
      'error': 'Хэт олон удаа буруу оролдсон тул аккаунт түгжигдсэн.',
    }),
    'auth/password/request-otp' => const AuthResponse(200, {
      'sent': true,
      'maskedPhone': '99***33',
    }),
    'auth/password/reset' => const AuthResponse(401, {'error': 'Код буруу байна.'}),
    _ => throw StateError(path),
  };

  for (final width in const [320.0, 390.0]) {
    testWidgets('phone → locked → reset card, no overflow at ${width.toInt()}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = AuthController(transport: server);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.enterText(find.byKey(const ValueKey('login_identifier_field')), '99112233');
      await tester.tap(find.text('Үргэлжлүүлэх'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('login_password_field')), 'wrong-pass');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Нэвтрэх'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login_locked')), findsOneWidget);

      await tester.tap(find.text('Утсаар нууц үг сэргээх'));
      await tester.pumpAndSettle();
      expect(find.text('Нууц үг сэргээх'), findsOneWidget);
      expect(find.text('99***33 дугаарт илгээсэн 6 оронтой кодыг оруулна уу.'), findsOneWidget);
      expect(find.textContaining('Код дахин авах'), findsOneWidget);

      // A full code moves on to the new-password screen by itself.
      await tester.enterText(find.byKey(const ValueKey('login_code_field')), '123456');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('login_new_password_field')), 'newpass12');
      await tester.enterText(
        find.byKey(const ValueKey('login_confirm_password_field')),
        'newpass12',
      );
      await tester.ensureVisible(find.text('Хадгалах'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();
      // A wrong code goes back to the code screen with the server message.
      expect(find.text('Код буруу байна.'), findsOneWidget);
      expect(find.byKey(const ValueKey('login_code_field')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Stop the resend countdown so no timer outlives the test.
      auth.cancelPasswordReset();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login_password_field')), findsOneWidget);
    });
  }
}
