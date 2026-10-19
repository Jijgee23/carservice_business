import 'package:carservice_business/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server registers the push device during `auth/login` / `auth/activate`
/// (and drops it on `auth/logout`), so the app sends the device fields with
/// those calls instead of a separate `POST /devices` afterwards.
void main() {
  const device = {
    'deviceId': 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
    'type': 'android',
    'fcm': 'fcm-token',
    'model': 'samsung SM-S918B',
    'os': 'Android 14',
  };

  late List<(String, Map<String, dynamic>)> calls;
  late AuthController auth;

  setUp(() {
    calls = [];
    auth = AuthController(
      transport: (path, body) async {
        calls.add((path, body));
        return switch (path) {
          'auth/check-email' => const AuthResponse(200, {
            'status': 'password',
            'identifier': '99112233',
          }),
          _ => const AuthResponse(401, {'error': 'Нэвтрэх нэр эсвэл нууц үг буруу.'}),
        };
      },
      deviceFields: () async => device,
    );
  });

  tearDown(() => auth.dispose());

  Map<String, dynamic> bodyOf(String path) => calls.lastWhere((c) => c.$1 == path).$2;

  test('login sends identifier, password and the device fields in one call', () async {
    auth.identifierCtrl.text = '9911-2233';
    await auth.checkIdentifier();
    auth.passwordCtrl.text = 'Secret123';
    await auth.login();
    expect(bodyOf('auth/login'), {'identifier': '99112233', 'password': 'Secret123', ...device});
  });

  test('activate (first sign-in) sends the device fields too', () async {
    auth.identifierCtrl.text = '99112233';
    await auth.checkIdentifier();
    auth.otpCtrl.text = '123456';
    auth.newPasswordCtrl.text = 'Secret123';
    auth.confirmPasswordCtrl.text = 'Secret123';
    await auth.activate();
    final body = bodyOf('auth/activate');
    expect(body['code'], '123456');
    for (final entry in device.entries) {
      expect(body[entry.key], entry.value, reason: entry.key);
    }
  });

  test('only the auth endpoints are called — no separate device registration', () async {
    auth.identifierCtrl.text = '99112233';
    await auth.checkIdentifier();
    auth.passwordCtrl.text = 'Secret123';
    await auth.login();
    expect(calls.map((c) => c.$1), ['auth/check-email', 'auth/login']);
  });
}
