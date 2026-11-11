import 'dart:async';

import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/services/device_service.dart';
import 'package:carservice_business/features/auth/presentation/controllers/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// The signup screens, in order: the workshop, the owner's sign-in details,
/// the map pin, then the SMS code.
enum SignupStep { business, account, location, code }

/// What a registry number says about who signs up (`lib/tenant-regno.ts`):
/// a company has 7 digits, a person 2 Cyrillic letters + 8 digits.
enum RegnoKind { org, person }

final _orgRegno = RegExp(r'^\d{7}$');
final _personRegno = RegExp(r'^[А-ЯЁӨҮ]{2}\d{8}$');

/// Spaces dropped and letters upper-cased, as the server stores it.
String normalizeRegno(String raw) => raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();

RegnoKind? regnoKindOf(String raw) {
  final v = normalizeRegno(raw);
  if (_orgRegno.hasMatch(v)) return RegnoKind.org;
  if (_personRegno.hasMatch(v)) return RegnoKind.person;
  return null;
}

/// The pin's address from `auth/signup/address`: the city/district/khoroo
/// names of the server's address directory plus a readable line. Any part
/// may be empty — the address is optional, the pin is not.
class SignupAddress {
  const SignupAddress({this.city = '', this.district = '', this.khoroo = '', this.address = ''});

  factory SignupAddress.fromJson(Map<String, dynamic> j) => SignupAddress(
    city: j['city'] as String? ?? '',
    district: j['district'] as String? ?? '',
    khoroo: j['khoroo'] as String? ?? '',
    address: j['address'] as String? ?? '',
  );

  final String city;
  final String district;
  final String khoroo;
  final String address;

  /// Empty when nothing was found.
  String get label =>
      address.isNotEmpty ? address : [city, district, khoroo].where((s) => s.isNotEmpty).join(', ');
}

/// Pre-login signup calls. Like [AuthTransport], every HTTP status comes
/// back as a value — no global toast and no token interceptor logout.
abstract interface class SignupApi {
  Future<AuthResponse> get(String path, Map<String, String> query);
  Future<AuthResponse> post(String path, Map<String, dynamic> body);
}

class DioSignupApi implements SignupApi {
  const DioSignupApi();

  static AuthResponse _wrap(Response<dynamic> res) {
    final data = res.data;
    return AuthResponse(res.statusCode ?? 0, data is Map ? Map<String, dynamic>.from(data) : const {});
  }

  @override
  Future<AuthResponse> get(String path, Map<String, String> query) async => _wrap(
    await ApiService.instance.dio.get<dynamic>(
      path,
      queryParameters: query,
      options: Options(validateStatus: (_) => true),
    ),
  );

  @override
  Future<AuthResponse> post(String path, Map<String, dynamic> body) async => _wrap(
    await ApiService.instance.dio.post<dynamic>(
      path,
      data: body,
      options: Options(validateStatus: (_) => true),
    ),
  );
}

/// New workshop (tenant) signup against the mobile API — the app version of
/// the web's `/page/signup`:
///
/// - `GET auth/signup/lookup?regno=` → the registered name from eBarimt,
///   filled into the name field while the user has not typed one;
/// - `GET auth/signup/address?lat=&lng=` → the pin's address;
/// - `POST auth/signup/request-otp` → checks every field and duplicates,
///   then texts a code to the owner's phone;
/// - `POST auth/signup` (same fields + `code` + device fields) → creates the
///   workshop, its main branch and the owner, and answers like `auth/login`
///   — handed to [onSignedUp], which signs the owner in.
///
/// Server field errors send the user back to the step that has the field.
class SignupController extends ChangeNotifier {
  SignupController({
    required this.onSignedUp,
    SignupApi? api,
    Future<Map<String, Object>> Function()? deviceFields,
    String? initialPhone,
  }) : _api = api ?? const DioSignupApi(),
       _deviceFields = deviceFields ?? DeviceService.instance.loginFields {
    if (initialPhone != null) phoneCtrl.text = initialPhone;
  }

  /// Signs in the owner `auth/signup` created ([loginData] is the
  /// `auth/login` reply) — [AuthController.completeSignup].
  final Future<void> Function(Map<String, dynamic> loginData, String phone) onSignedUp;
  final SignupApi _api;
  final Future<Map<String, Object>> Function() _deviceFields;

  static const stepCount = 4;
  static const resendCooldownSeconds = AuthController.resendCooldownSeconds;
  static const lookupDebounce = Duration(milliseconds: 400);
  static const addressDebounce = Duration(milliseconds: 600);

  /// Which step each server field lives on; anything else is shown as the
  /// step's own error.
  static const _fieldSteps = {
    'registerNumber': SignupStep.business,
    'orgName': SignupStep.business,
    'ownerName': SignupStep.business,
    'phone1': SignupStep.account,
    'orgEmail': SignupStep.account,
    'password': SignupStep.account,
    'passwordConfirm': SignupStep.account,
    'terms': SignupStep.account,
    'latitude': SignupStep.location,
    'code': SignupStep.code,
  };

  /// Server keys that mean one of the fields above.
  static const _fieldAliases = {
    'adminPhone': 'phone1',
    'adminEmail': 'orgEmail',
    'longitude': 'latitude',
    'otpCode': 'code',
  };

  final regnoCtrl = TextEditingController();
  final orgNameCtrl = TextEditingController();
  final ownerNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  final otpCtrl = TextEditingController();

  SignupStep step = SignupStep.business;
  bool loading = false;

  /// The step's own error (network, server, throttle) — shown in a banner.
  String? errorText;

  /// Per-field errors, keyed like the server's `fieldErrors`.
  Map<String, String> fieldErrors = const {};

  bool termsAccepted = false;

  // ─── Registry lookup ───────────────────────────────────────────────────────

  bool lookingUp = false;

  /// eBarimt knows this number; its name is in the name field unless the user
  /// typed their own.
  bool lookupFound = false;
  String? _lookedUp;
  bool _nameEdited = false;
  Timer? _lookupTimer;

  // ─── Location ──────────────────────────────────────────────────────────────

  double? latitude;
  double? longitude;
  SignupAddress? address;
  bool resolvingAddress = false;
  Timer? _addressTimer;
  int _addressRequest = 0;

  // ─── Code ──────────────────────────────────────────────────────────────────

  String? maskedPhone;
  int resendIn = 0;
  Timer? _resendTimer;

  /// Phone + email the last code went to: a code is per number, so going
  /// back and changing it needs a new one.
  String? _codeSentFor;

  bool _disposed = false;

  RegnoKind? get regnoKind => regnoKindOf(regnoCtrl.text);
  bool get isPerson => regnoKind == RegnoKind.person;
  bool get hasLocation => latitude != null && longitude != null;
  String get stepLabel => '${step.index + 1} / $stepCount';

  String get _phone => phoneCtrl.text.trim();
  String get _email => emailCtrl.text.trim();
  String get _codeKey => '$_phone|${_email.toLowerCase()}';

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lookupTimer?.cancel();
    _addressTimer?.cancel();
    _resendTimer?.cancel();
    for (final c in [
      regnoCtrl,
      orgNameCtrl,
      ownerNameCtrl,
      phoneCtrl,
      emailCtrl,
      passwordCtrl,
      confirmCtrl,
      otpCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Field edits ───────────────────────────────────────────────────────────

  /// Clears [key]'s error (and the step banner) once the user edits it.
  void clearError([String? key]) {
    final hadField = key != null && fieldErrors.containsKey(key);
    if (!hadField && errorText == null) return;
    if (hadField) fieldErrors = Map.of(fieldErrors)..remove(key);
    errorText = null;
    notifyListeners();
  }

  void onRegnoChanged(String _) {
    clearError('registerNumber');
    final regno = normalizeRegno(regnoCtrl.text);
    _lookupTimer?.cancel();
    if (regnoKindOf(regno) == null) {
      lookingUp = false;
      lookupFound = false;
      _lookedUp = null;
    } else if (regno != _lookedUp) {
      lookupFound = false;
      _lookupTimer = Timer(lookupDebounce, () => _lookup(regno));
    }
    // The name field's label and the owner field follow the kind.
    notifyListeners();
  }

  void onOrgNameChanged(String value) {
    _nameEdited = value.trim().isNotEmpty;
    clearError('orgName');
  }

  void setTermsAccepted(bool value) {
    termsAccepted = value;
    clearError('terms');
    notifyListeners();
  }

  /// Best-effort: on any failure the user just types the name.
  Future<void> _lookup(String regno) async {
    _lookedUp = regno;
    lookingUp = true;
    notifyListeners();
    try {
      final res = await _api.get('auth/signup/lookup', {'regno': regno});
      if (normalizeRegno(regnoCtrl.text) != regno) return;
      final name = res.data['name'];
      lookupFound = res.ok && res.data['found'] == true && name is String && name.isNotEmpty;
      if (lookupFound && !_nameEdited) {
        orgNameCtrl.text = name as String;
        clearError('orgName');
      }
      if (!res.ok) _lookedUp = null;
    } catch (_) {
      _lookedUp = null;
    } finally {
      if (normalizeRegno(regnoCtrl.text) == regno) lookingUp = false;
      notifyListeners();
    }
  }

  // ─── Location ──────────────────────────────────────────────────────────────

  /// The map's pin moved here: keep it, then look up its address once the
  /// map has been still for [addressDebounce].
  void setLocation(double lat, double lng) {
    latitude = double.parse(lat.toStringAsFixed(6));
    longitude = double.parse(lng.toStringAsFixed(6));
    address = null;
    resolvingAddress = true;
    if (fieldErrors.containsKey('latitude')) fieldErrors = Map.of(fieldErrors)..remove('latitude');
    errorText = null;
    _addressTimer?.cancel();
    _addressTimer = Timer(addressDebounce, _resolveAddress);
    notifyListeners();
  }

  Future<void> _resolveAddress() async {
    final request = ++_addressRequest;
    final lat = latitude, lng = longitude;
    if (lat == null || lng == null) return;
    SignupAddress found = const SignupAddress();
    try {
      final res = await _api.get('auth/signup/address', {'lat': '$lat', 'lng': '$lng'});
      if (res.ok) found = SignupAddress.fromJson(res.data);
    } catch (_) {}
    // A newer pin is on its way.
    if (request != _addressRequest) return;
    address = found;
    resolvingAddress = false;
    notifyListeners();
  }

  /// A message from the map (location permission, GPS off) for the banner.
  void showError(String message) {
    errorText = message;
    notifyListeners();
  }

  // ─── Steps ─────────────────────────────────────────────────────────────────

  /// The step's primary button.
  Future<void> next() async {
    if (loading) return;
    switch (step) {
      case SignupStep.business:
        if (_validate(_businessErrors())) _goTo(SignupStep.account);
      case SignupStep.account:
        if (_validate(_accountErrors())) _goTo(SignupStep.location);
      case SignupStep.location:
        if (_validate(_locationErrors())) await _requestCode();
      case SignupStep.code:
        await submit();
    }
  }

  /// Back one step. False on the first step: the screen closes instead.
  bool back() {
    if (loading || step == SignupStep.business) return false;
    _goTo(SignupStep.values[step.index - 1]);
    return true;
  }

  void _goTo(SignupStep target) {
    step = target;
    errorText = null;
    notifyListeners();
  }

  Map<String, String> _businessErrors() {
    final kind = regnoKind;
    return {
      if (kind == null)
        'registerNumber':
            'Регистр буруу: байгууллага бол 7 оронтой тоо, хувь хүн бол 2 үсэг + 8 цифр (ж: ҮҮ99993333).',
      if (orgNameCtrl.text.trim().isEmpty)
        'orgName': kind == RegnoKind.person ? 'Овог нэрээ оруулна уу.' : 'Засварын нэрээ оруулна уу.',
      if (kind != RegnoKind.person && ownerNameCtrl.text.trim().isEmpty)
        'ownerName': 'Эзний овог нэрийг оруулна уу.',
    };
  }

  Map<String, String> _accountErrors() => {
    if (_phone.isEmpty)
      'phone1': 'Утасны дугаараа оруулна уу.'
    else if (!RegExp(r'^\d{8}$').hasMatch(_phone))
      'phone1': 'Утасны дугаар 8 оронтой тоо байх ёстой.',
    if (_email.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email))
      'orgEmail': 'Имэйл хаяг буруу.',
    if (passwordCtrl.text.length < 8)
      'password': 'Нууц үг хамгийн багадаа 8 тэмдэгт байна.'
    else if (passwordCtrl.text != confirmCtrl.text)
      'passwordConfirm': 'Нууц үг таарахгүй байна.',
    if (!termsAccepted) 'terms': 'Үйлчилгээний нөхцөл, нууцлалын бодлогыг зөвшөөрнө үү.',
  };

  Map<String, String> _locationErrors() => {
    if (!hasLocation) 'latitude': 'Газрын зураг дээр байршлаа тэмдэглэнэ үү.',
  };

  bool _validate(Map<String, String> errors) {
    fieldErrors = errors;
    errorText = null;
    notifyListeners();
    return errors.isEmpty;
  }

  Map<String, dynamic> _body() => {
    'registerNumber': normalizeRegno(regnoCtrl.text),
    'orgName': orgNameCtrl.text.trim(),
    'ownerName': isPerson ? '' : ownerNameCtrl.text.trim(),
    'phone1': _phone,
    'orgEmail': _email,
    'password': passwordCtrl.text,
    'passwordConfirm': confirmCtrl.text,
    'latitude': latitude,
    'longitude': longitude,
    'city': address?.city ?? '',
    'district': address?.district ?? '',
    'khoroo': address?.khoroo ?? '',
    'address': address?.address ?? '',
  };

  // ─── SMS code ──────────────────────────────────────────────────────────────

  /// Location → code. The server checks every field and duplicate before it
  /// texts the code. A code sent to the same number moments ago is reused
  /// rather than throttled.
  Future<void> _requestCode() async {
    if (_codeSentFor == _codeKey && resendIn > 0) return _goTo(SignupStep.code);
    await _sendCode();
  }

  Future<void> resendCode() async {
    if (resendIn > 0) return;
    await _sendCode();
  }

  Future<void> _sendCode() async {
    final key = _codeKey;
    final res = await _call('auth/signup/request-otp', _body());
    if (res == null || errorText != null) return notifyListeners();
    if (!res.ok) return _applyErrors(res, 'Код илгээхэд алдаа гарлаа.');
    maskedPhone = res.data['maskedPhone'] as String?;
    _codeSentFor = key;
    otpCtrl.clear();
    _startCooldown();
    _goTo(SignupStep.code);
  }

  /// Creates the workshop. On success the owner is signed in and the router
  /// leaves the login pages, this screen with them.
  Future<void> submit() async {
    if (loading) return;
    final code = otpCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _validate({'code': '6 оронтой кодоо оруулна уу.'});
      return;
    }
    final res = await _call('auth/signup', {..._body(), 'code': code, ...await _deviceFields()});
    if (res == null || errorText != null) return notifyListeners();
    if (res.ok) {
      _resendTimer?.cancel();
      // Stays busy: the screen goes away with the login page.
      loading = true;
      notifyListeners();
      try {
        await onSignedUp(res.data, _phone);
      } catch (_) {
        loading = false;
        errorText = 'Бүртгэл үүссэн. Утас, нууц үгээрээ нэвтэрнэ үү.';
        notifyListeners();
      }
      return;
    }
    // 401: wrong code, type it again. 409: the code was accepted (and spent)
    // before a duplicate turned up, so the next pass texts a new one.
    if (res.status == 401 || res.status == 409) otpCtrl.clear();
    if (res.status == 409) _codeSentFor = null;
    _applyErrors(res, 'Бүртгэл үүсгэхэд алдаа гарлаа.');
  }

  void _startCooldown() {
    _resendTimer?.cancel();
    resendIn = resendCooldownSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      resendIn--;
      if (resendIn <= 0) {
        resendIn = 0;
        t.cancel();
      }
      notifyListeners();
    });
  }

  // ─── Common ────────────────────────────────────────────────────────────────

  /// One call with the loading flag; a network failure, a bare 429 or a 5xx
  /// becomes [errorText] instead of an exception.
  Future<AuthResponse?> _call(String path, Map<String, dynamic> body) async {
    loading = true;
    errorText = null;
    notifyListeners();
    try {
      final res = await _api.post(path, body);
      if (res.status == 429 && res.error == null) {
        errorText = 'Хэт олон хүсэлт илгээлээ. Түр хүлээгээд дахин оролдоно уу.';
      } else if (res.status >= 500 && res.status != 502) {
        errorText = 'Серверийн алдаа гарлаа. Дахин оролдоно уу.';
      } else if (res.status == 502) {
        // The SMS gateway: the server says what happened.
        errorText = res.error ?? 'Код илгээгдсэнгүй. Дахин оролдоно уу.';
      }
      return res;
    } on DioException {
      errorText = 'Сервертэй холбогдож чадсангүй. Интернэтээ шалгана уу.';
      return null;
    } finally {
      loading = false;
    }
  }

  /// Server field errors go next to their fields — on the earliest step that
  /// has one, so the user lands where to fix it; anything else is the
  /// current step's banner.
  void _applyErrors(AuthResponse res, String fallback) {
    final raw = res.data['fieldErrors'];
    final errors = <String, String>{};
    String? other;
    if (raw is Map) {
      for (final MapEntry(:key, :value) in raw.entries) {
        final field = _fieldAliases[key] ?? '$key';
        if (_fieldSteps.containsKey(field)) {
          errors.putIfAbsent(field, () => '$value');
        } else {
          other ??= '$value';
        }
      }
    }
    final steps = errors.keys.map((k) => _fieldSteps[k]!).toList()
      ..sort((a, b) => a.index - b.index);
    fieldErrors = errors;
    if (steps.isNotEmpty) step = steps.first;
    errorText = errors.isEmpty ? (other ?? res.error ?? fallback) : other;
    notifyListeners();
  }
}
