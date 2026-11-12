import 'package:carservice_business/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carservice_business/features/auth/presentation/controllers/signup_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted [SignupApi]: each path answers from [replies] (last reply
/// repeats) and every call is recorded.
class _FakeSignupApi implements SignupApi {
  _FakeSignupApi(this.replies);

  final Map<String, List<AuthResponse>> replies;
  final calls = <(String, Map<String, dynamic>)>[];

  AuthResponse _next(String path) {
    final queue = replies[path];
    if (queue == null || queue.isEmpty) return const AuthResponse(404, {'error': 'not found'});
    return queue.length == 1 ? queue.first : queue.removeAt(0);
  }

  @override
  Future<AuthResponse> get(String path, Map<String, String> query) async {
    calls.add((path, Map<String, dynamic>.from(query)));
    return _next(path);
  }

  @override
  Future<AuthResponse> post(String path, Map<String, dynamic> body) async {
    calls.add((path, body));
    return _next(path);
  }
}

void main() {
  const device = {'deviceId': 'dev-1', 'type': 'android', 'fcm': 'fcm-token', 'model': 'Pixel', 'os': 'Android 15'};

  late _FakeSignupApi api;
  late SignupController c;
  late List<(Map<String, dynamic>, String)> signedUp;

  SignupController make(Map<String, List<AuthResponse>> replies) {
    api = _FakeSignupApi(replies);
    signedUp = [];
    return SignupController(
      api: api,
      deviceFields: () async => device,
      onSignedUp: (data, phone) async => signedUp.add((data, phone)),
    );
  }

  /// Fills the first three steps validly (company register number).
  Future<void> fillToLocation() async {
    c.regnoCtrl.text = '1234567';
    c.onRegnoChanged('1234567');
    c.orgNameCtrl.text = 'Тест Засвар';
    c.ownerNameCtrl.text = 'Батын Болд';
    await c.next();
    c.phoneCtrl.text = '99000001';
    c.passwordCtrl.text = '12345678';
    c.confirmCtrl.text = '12345678';
    c.setTermsAccepted(true);
    await c.next();
    c.setLocation(47.9184, 106.9177);
  }

  Map<String, dynamic> bodyOf(String path) => api.calls.lastWhere((x) => x.$1 == path).$2;

  tearDown(() => c.dispose());

  test('register number kind: 7 digits = company, 2 letters + 8 digits = person', () {
    c = make({});
    expect(regnoKindOf('1234567'), RegnoKind.org);
    expect(regnoKindOf('үү 99993333'), RegnoKind.person);
    expect(regnoKindOf('12345'), isNull);
    expect(normalizeRegno(' үү99 993333 '), 'ҮҮ99993333');
  });

  test('each step validates locally before moving on', () async {
    c = make({});
    await c.next();
    expect(c.step, SignupStep.business);
    expect(c.fieldErrors.keys, containsAll(['registerNumber', 'orgName', 'ownerName']));

    // A person signs up under their own name: no owner field.
    c.regnoCtrl.text = 'ҮҮ99993333';
    c.orgNameCtrl.text = 'Батын Болд';
    await c.next();
    expect(c.step, SignupStep.account);

    c.phoneCtrl.text = '123';
    c.passwordCtrl.text = 'short';
    await c.next();
    expect(c.step, SignupStep.account);
    expect(c.fieldErrors.keys, containsAll(['phone1', 'password', 'terms']));

    c.phoneCtrl.text = '99000001';
    c.passwordCtrl.text = '12345678';
    c.confirmCtrl.text = '12345679';
    c.setTermsAccepted(true);
    await c.next();
    expect(c.fieldErrors.keys, ['passwordConfirm']);

    c.confirmCtrl.text = '12345678';
    await c.next();
    expect(c.step, SignupStep.location);
    await c.next();
    expect(c.fieldErrors.keys, ['latitude']);
    expect(api.calls.where((x) => x.$1 == 'auth/signup/request-otp'), isEmpty);
  });

  test('full happy path: request-otp then signup with code + device fields, then signs in', () async {
    c = make({
      'auth/signup/request-otp': [const AuthResponse(200, {'sent': true, 'maskedPhone': '99****01'})],
      'auth/signup': [const AuthResponse(201, {'accessToken': 'a', 'refreshToken': 'r', 'user': {'id': 'u1'}})],
    });
    await fillToLocation();
    await c.next();
    expect(c.step, SignupStep.code);
    expect(c.maskedPhone, '99****01');
    expect(c.resendIn, greaterThan(0));

    final otpBody = bodyOf('auth/signup/request-otp');
    expect(otpBody['registerNumber'], '1234567');
    expect(otpBody['phone1'], '99000001');
    expect(otpBody['ownerName'], 'Батын Болд');
    expect(otpBody['latitude'], 47.9184);
    expect(otpBody.containsKey('code'), isFalse);

    c.otpCtrl.text = '123456';
    await c.next();
    final body = bodyOf('auth/signup');
    expect(body['code'], '123456');
    expect(body['fcm'], 'fcm-token');
    expect(body['passwordConfirm'], '12345678');
    expect(signedUp.single.$2, '99000001');
    expect(signedUp.single.$1['accessToken'], 'a');
  });

  test('a server conflict sends the user back to the step that has the field', () async {
    c = make({
      'auth/signup/request-otp': [
        const AuthResponse(409, {
          'error': 'Энэ регистр аль хэдийн бүртгэгдсэн байна.',
          'code': 'CONFLICT',
          'fieldErrors': {'registerNumber': 'Энэ регистр аль хэдийн бүртгэгдсэн байна.'},
        }),
      ],
    });
    await fillToLocation();
    await c.next();
    expect(c.step, SignupStep.business);
    expect(c.fieldErrors['registerNumber'], contains('бүртгэгдсэн'));
    expect(c.errorText, isNull);
  });

  test('adminPhone conflict is shown on the phone field (account step)', () async {
    c = make({
      'auth/signup/request-otp': [
        const AuthResponse(409, {
          'error': 'Энэ утасны дугаар аль хэдийн бүртгэгдсэн байна.',
          'fieldErrors': {'adminPhone': 'Энэ утасны дугаар аль хэдийн бүртгэгдсэн байна.'},
        }),
      ],
    });
    await fillToLocation();
    await c.next();
    expect(c.step, SignupStep.account);
    expect(c.fieldErrors.keys, ['phone1']);
  });

  test('wrong code stays on the code step and clears the input', () async {
    c = make({
      'auth/signup/request-otp': [const AuthResponse(200, {'sent': true, 'maskedPhone': '99****01'})],
      'auth/signup': [
        const AuthResponse(401, {
          'error': 'Код буруу байна.',
          'code': 'OTP_INVALID',
          'fieldErrors': {'code': 'Код буруу байна.'},
        }),
      ],
    });
    await fillToLocation();
    await c.next();
    c.otpCtrl.text = '000000';
    await c.next();
    expect(c.step, SignupStep.code);
    expect(c.fieldErrors['code'], 'Код буруу байна.');
    expect(c.otpCtrl.text, isEmpty);
    expect(signedUp, isEmpty);
  });

  test('a non-6-digit code is rejected without calling the server', () async {
    c = make({
      'auth/signup/request-otp': [const AuthResponse(200, {'sent': true})],
    });
    await fillToLocation();
    await c.next();
    c.otpCtrl.text = '12';
    await c.next();
    expect(c.fieldErrors.keys, ['code']);
    expect(api.calls.where((x) => x.$1 == 'auth/signup'), isEmpty);
  });

  test('SMS gateway failure (502) shows the server message as a banner', () async {
    c = make({
      'auth/signup/request-otp': [
        const AuthResponse(502, {'error': 'Баталгаажуулах код илгээгдсэнгүй. Утсаа шалгаж дахин оролдоно уу.'}),
      ],
    });
    await fillToLocation();
    await c.next();
    expect(c.step, SignupStep.location);
    expect(c.errorText, contains('илгээгдсэнгүй'));
  });

  test('going back and forth reuses a fresh code for the same number', () async {
    c = make({
      'auth/signup/request-otp': [const AuthResponse(200, {'sent': true})],
    });
    await fillToLocation();
    await c.next();
    expect(c.back(), isTrue);
    expect(c.step, SignupStep.location);
    await c.next();
    expect(c.step, SignupStep.code);
    expect(api.calls.where((x) => x.$1 == 'auth/signup/request-otp').length, 1);
  });

  test('back on the first step returns false so the screen can close', () {
    c = make({});
    expect(c.back(), isFalse);
  });
}
