import 'dart:async';

import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/branch_service.dart';
import 'package:carservice_business/core/services/device_service.dart';
import 'package:carservice_business/core/services/network_status.dart';
import 'package:carservice_business/core/services/pending_logout_store.dart';
import 'package:carservice_business/core/services/saved_login_store.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

enum AuthState { firstInstall, policyNotAgreed, noLogged, authorized, finding }

/// Login card steps. `identifier` asks for email **or** phone; the server's
/// `check-email` decides between [password], [activate] and [notRegistered].
/// [resetPassword] is the self-service "forgot password" flow.
enum LoginStep { identifier, password, activate, notRegistered, resetPassword }

/// One pre-login API reply. Every HTTP status comes back as a value — no
/// exception, no global toast, and never through the token interceptor's
/// "401 → force logout" path (a wrong password or OTP is a 401 here and
/// must not reset the login screen).
class AuthResponse {
  const AuthResponse(this.status, this.data);

  final int status;
  final Map<String, dynamic> data;

  bool get ok => status >= 200 && status < 300;

  /// The server's `{ error }` message, verbatim.
  String? get error => data['error'] as String?;
}

typedef AuthTransport = Future<AuthResponse> Function(String path, Map<String, dynamic> body);

Future<AuthResponse> _dioTransport(String path, Map<String, dynamic> body) async {
  final res = await ApiService.instance.dio.post<dynamic>(
    path,
    data: body,
    options: Options(validateStatus: (_) => true),
  );
  final data = res.data;
  return AuthResponse(
    res.statusCode ?? 0,
    data is Map ? Map<String, dynamic>.from(data) : const {},
  );
}

/// Staff sign-in against the tenant mobile API (`/api/v1/auth/*`):
///
/// - `check-email {identifier}` → `password` | `activate` | `not_registered`
/// - `login {identifier, password}` → tokens
/// - `activate/request-otp`, `activate {identifier, code, password}` → tokens
///   (first sign-in: the SMS code sets the initial password)
/// - `password/request-otp`, `password/reset {identifier, code, password}`
///   → forgot password; on success the user signs in with the new password
///
/// `identifier` is an email or a phone number; after `check-email` the
/// controller always sends the server's canonical value back.
class AuthController extends ChangeNotifier {
  AuthController({
    AuthTransport? transport,
    SavedLoginStore? savedLogins,
    Future<void> Function()? onSignedIn,
    Future<Map<String, Object>> Function()? deviceFields,
    PendingLogoutStore? pendingLogouts,
    NetworkStatus? network,
  }) : _post = transport ?? _dioTransport,
       _savedLogins = savedLogins ?? HiveSavedLoginStore.instance,
       _onSignedIn = onSignedIn ?? _noSignedInHook,
       _deviceFields = deviceFields ?? DeviceService.instance.loginFields,
       _pendingLogouts = pendingLogouts ?? HivePendingLogoutStore.instance,
       _network = network ?? DeviceNetworkStatus.instance;

  // The server registers the push device during `auth/login` /
  // `auth/activate` itself — nothing extra to call after sign-in.
  static Future<void> _noSignedInHook() async {}

  final AuthTransport _post;
  final SavedLoginStore _savedLogins;

  /// Post-login side effect; injectable for tests (no-op by default).
  final Future<void> Function() _onSignedIn;

  /// Device fields (`type`, `fcm`, `model`, `os`, `deviceId`) sent with
  /// `auth/login` / `auth/activate`; injectable for tests.
  final Future<Map<String, Object>> Function() _deviceFields;

  /// Sign-outs made offline, sent once the network is back.
  final PendingLogoutStore _pendingLogouts;
  final NetworkStatus _network;

  /// How long sign-out waits for `auth/logout` before queueing it instead —
  /// a network without internet reads as online but never answers.
  static const logoutTimeout = Duration(seconds: 5);

  /// Watches the network while queued sign-outs wait for it.
  StreamSubscription<bool>? _networkSub;
  bool _syncingLogouts = false;

  /// Last account that signed in on this device (no secrets) — prefills the
  /// identifier on the login page, including right after logout.
  SavedLogin? savedLogin;

  /// Seconds before an SMS code can be requested again — keeps staff well
  /// inside the server's OTP throttle.
  static const resendCooldownSeconds = 60;

  bool loading = false;
  AuthState authState = AuthState.finding;
  LoginStep step = LoginStep.identifier;

  final identifierCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  final newPasswordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();

  /// Canonical identifier from `check-email` (lowercase email / 8-digit phone).
  String? _identifier;

  String? maskedPhone;

  /// Set when login answered 423 — the password card then offers a reset.
  bool lockedOut = false;

  /// Inline error for the current card (wrong password, wrong code, …).
  String? errorText;

  int resendIn = 0;
  Timer? _resendTimer;

  String get identifierForDisplay {
    final typed = identifierCtrl.text.trim();
    return typed.isNotEmpty ? typed : (_identifier ?? '');
  }

  /// Whether the user typed a phone number rather than an email.
  bool get isPhoneIdentifier => !identifierForDisplay.contains('@');

  String get _canonical => _identifier ?? identifierCtrl.text.trim();

  @override
  void dispose() {
    _resendTimer?.cancel();
    _stopWatchingNetwork();
    identifierCtrl.dispose();
    passwordCtrl.dispose();
    otpCtrl.dispose();
    newPasswordCtrl.dispose();
    confirmPasswordCtrl.dispose();
    super.dispose();
  }

  void _setLoading(bool v) {
    loading = v;
    notifyListeners();
  }

  void setAuthState(AuthState v) {
    authState = v;
    notifyListeners();
  }

  void _clearSecrets() {
    passwordCtrl.clear();
    otpCtrl.clear();
    newPasswordCtrl.clear();
    confirmPasswordCtrl.clear();
  }

  void resetToIdentifier() {
    step = LoginStep.identifier;
    _clearSecrets();
    _identifier = null;
    maskedPhone = null;
    lockedOut = false;
    errorText = null;
    _stopCooldown();
    notifyListeners();
  }

  void clearError() {
    if (errorText == null) return;
    errorText = null;
    notifyListeners();
  }

  /// Runs one auth call with the loading flag; a network failure becomes a
  /// friendly [errorText] instead of an exception.
  Future<AuthResponse?> _call(String path, Map<String, dynamic> body) async {
    _setLoading(true);
    errorText = null;
    try {
      final res = await _post(path, body);
      if (res.status == 429 && res.error == null) {
        errorText = 'Хэт олон хүсэлт илгээлээ. Түр хүлээгээд дахин оролдоно уу.';
      } else if (res.status >= 500) {
        errorText = 'Серверийн алдаа гарлаа. Дахин оролдоно уу.';
      }
      return res;
    } on DioException {
      errorText = 'Сервертэй холбогдож чадсангүй. Интернэтээ шалгана уу.';
      return null;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Resend cooldown ───────────────────────────────────────────────────────

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

  void _stopCooldown() {
    _resendTimer?.cancel();
    resendIn = 0;
  }

  // ─── App start ─────────────────────────────────────────────────────────────

  Future<void> loadUser() async {
    Authenticator.onUnauthorized = logout;
    Authenticator.onAccountClosed = handleRemoteAccountClosed;
    // Sign-outs made offline last time reach the server now, or once online.
    unawaited(syncPendingLogouts());
    final user = Authenticator.user;
    if (user != null) {
      setAuthState(AuthState.authorized);
      return;
    }
    await _prefillIdentifier();
    setAuthState(AuthState.noLogged);
  }

  /// [serverCleanup] = false skips the `auth/logout` call — used after the account was deactivated/deleted, when the server
  /// has already revoked the tokens and dropped the devices, so those calls
  /// would only 401, trigger a nested forced logout and toast an error.
  Future<void> logout({bool serverCleanup = true}) async {
    // Best-effort server cleanup before clearing local state — a failure here
    // must never block local sign-out. After a forced 401 logout the session
    // is already gone, so there is nothing to send.
    if (serverCleanup && Authenticator.user != null) {
      // One call: the server revokes this session's refresh token and drops
      // the push device this login registered (no separate DELETE /devices).
      final refreshToken = Authenticator.user?.refreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        final pending = PendingLogout(
          refreshToken: refreshToken,
          loggedOutAt: DateTime.now(),
        );
        // Offline, or no answer in time: no call to wait on. The sign-out
        // and its time are kept and sent once the network is back.
        if (!await _network.isOnline() || !await _sendLogout(pending)) {
          await _queueLogout(pending);
        }
      }
    }

    // Always — forced logouts too — so the next account on this device never
    // sees the previous tenant's branches or subscription state. Credentials
    // first: a fetch racing this logout then hits the old cache (or, once the
    // user is gone, is skipped) instead of calling the API with a dead token.
    await Authenticator.clear();
    _clearSessionCaches();
    step = LoginStep.identifier;
    _clearSecrets();
    _identifier = null;
    maskedPhone = null;
    lockedOut = false;
    errorText = null;
    _stopCooldown();
    await _prefillIdentifier();
    setAuthState(AuthState.noLogged);
  }

  /// Handles the backend's silent `account_closed` data push (deactivation
  /// or deletion, including from the website). Local-only: the server
  /// already revoked the tokens and dropped this device's row, so
  /// `serverCleanup: false` skips `logout()`'s network calls (they would
  /// only 401, trigger a nested forced logout, and toast an error).
  /// Idempotent — a no-op once already signed out, which covers the device
  /// that initiated the closure and receives its own push while already
  /// logging out. Also a no-op while `AccountClosureController.submit` is
  /// still in flight on this device (`Authenticator.accountClosureInFlight`)
  /// — the backend can deliver this push before that call's own HTTP
  /// response returns, and `submit` already owns the sign-out and its own
  /// toast in that case.
  Future<void> handleRemoteAccountClosed({required bool deleted}) async {
    if (Authenticator.accountClosureInFlight) return;
    if (Authenticator.user == null) return;
    await logout(serverCleanup: false);
    messageComplete(deleted ? 'Бүртгэл тань устгагдсан' : 'Бүртгэл тань идэвхгүй болсон');
  }

  // ─── Offline sign-out ──────────────────────────────────────────────────────

  /// Sends one sign-out. True once the server has answered for good
  /// (revoked, or a 4xx: nothing to retry); false keeps it for later (no
  /// network, no answer in [logoutTimeout], a 5xx).
  Future<bool> _sendLogout(PendingLogout logout) async {
    try {
      final res = await _post('auth/logout', {
        'refreshToken': logout.refreshToken,
        // When the user signed out; later than the request for one queued
        // while offline.
        'loggedOutAt': logout.loggedOutAt.toUtc().toIso8601String(),
      }).timeout(logoutTimeout);
      return res.status < 500;
    } catch (_) {
      return false;
    }
  }

  Future<void> _queueLogout(PendingLogout logout) async {
    final queue = await _pendingLogouts.read();
    await _pendingLogouts.write([...queue, logout]);
    _watchNetwork();
  }

  /// Sends the sign-outs queued while offline: at app start, after a sign-in
  /// and whenever the network comes back. Those still failing stay queued;
  /// stale ones (their refresh token long expired) are dropped.
  Future<void> syncPendingLogouts() async {
    if (_syncingLogouts) return;
    _syncingLogouts = true;
    try {
      final now = DateTime.now();
      final queue = await _pendingLogouts.read();
      final due = queue.where((p) => !p.isStale(now)).toList();
      if (due.isEmpty) {
        if (queue.isNotEmpty) await _pendingLogouts.write(const []);
        _stopWatchingNetwork();
        return;
      }
      if (!await _network.isOnline()) {
        _watchNetwork();
        return;
      }
      final failed = <PendingLogout>[];
      for (final pending in due) {
        if (!await _sendLogout(pending)) failed.add(pending);
      }
      // A sign-out may have been queued while these were being sent.
      final queuedMeanwhile = (await _pendingLogouts.read()).where(
        (p) => !queue.any((q) => q.refreshToken == p.refreshToken),
      );
      final left = [...failed, ...queuedMeanwhile];
      await _pendingLogouts.write(left);
      left.isEmpty ? _stopWatchingNetwork() : _watchNetwork();
    } finally {
      _syncingLogouts = false;
    }
  }

  void _watchNetwork() {
    _networkSub ??= _network.changes
        .where((online) => online)
        .listen((_) => unawaited(syncPendingLogouts()), onError: (_) {});
  }

  void _stopWatchingNetwork() {
    _networkSub?.cancel();
    _networkSub = null;
  }

  void _clearSessionCaches() {
    SubscriptionService.instance.invalidate();
    BranchService.instance.invalidate();
  }

  /// Puts the last signed-in identifier back into the field (email or phone,
  /// exactly as typed). Leaves the field alone when nothing is saved.
  Future<void> _prefillIdentifier() async {
    savedLogin = await _savedLogins.read();
    final saved = savedLogin?.identifier;
    if (saved != null && saved.isNotEmpty) identifierCtrl.text = saved;
  }

  // ─── Step 1: имэйл / утас шалгах ──────────────────────────────────────────

  Future<void> checkIdentifier() async {
    final raw = identifierCtrl.text.trim();
    if (raw.isEmpty) {
      errorText = 'Имэйл эсвэл утасны дугаараа оруулна уу.';
      notifyListeners();
      return;
    }
    final res = await _call('auth/check-email', {'identifier': raw});
    if (res == null || errorText != null) return notifyListeners();
    if (!res.ok) {
      errorText = res.error ?? 'Имэйл эсвэл утасны дугаар буруу.';
      return notifyListeners();
    }
    _identifier = res.data['identifier'] as String? ?? raw;
    lockedOut = false;
    switch (res.data['status']) {
      case 'password':
        step = LoginStep.password;
      case 'activate':
        step = LoginStep.activate;
        maskedPhone = res.data['maskedPhone'] as String?;
        if (res.data['otpSent'] == false) {
          // Code not sent (e.g. throttled) — stay on the step so the user can
          // resend, and say why.
          errorText = res.data['message'] as String?;
        } else {
          _startCooldown();
        }
      default:
        step = LoginStep.notRegistered;
    }
    notifyListeners();
  }

  // ─── Step 2a: нууц үгээр нэвтрэх ─────────────────────────────────────────

  Future<void> login() async {
    if (passwordCtrl.text.isEmpty) {
      errorText = 'Нууц үгээ оруулна уу.';
      return notifyListeners();
    }
    final res = await _call('auth/login', {
      'identifier': _canonical,
      'password': passwordCtrl.text,
      ...await _deviceFields(),
    });
    if (res == null || errorText != null) return notifyListeners();
    if (res.ok) return _handleLoginResponse(res.data);
    passwordCtrl.clear();
    lockedOut = res.status == 423;
    errorText = res.error ?? 'Нэвтрэх нэр эсвэл нууц үг буруу.';
    notifyListeners();
  }

  // ─── Step 2b: анхны нэвтрэлт (OTP + шинэ нууц үг) ──────────────────────

  Future<void> activate() async {
    if (!_validateCodeAndNewPassword()) return;
    final res = await _call('auth/activate', {
      'identifier': _canonical,
      'code': otpCtrl.text.trim(),
      'password': newPasswordCtrl.text,
      ...await _deviceFields(),
    });
    if (res == null || errorText != null) return notifyListeners();
    if (res.ok) return _handleLoginResponse(res.data);
    if (res.status == 409) {
      // Already activated elsewhere — sign in with the password instead.
      step = LoginStep.password;
      _clearSecrets();
      _stopCooldown();
    }
    errorText = res.error ?? 'Код буруу байна.';
    notifyListeners();
  }

  Future<void> requestOtp() => _requestCode('auth/activate/request-otp');

  // ─── Нууц үг сэргээх ───────────────────────────────────────────────────────

  /// "Нууц үг мартсан уу?" — sends a reset code to the account's phone and
  /// opens the reset card.
  Future<void> startPasswordReset() async {
    step = LoginStep.resetPassword;
    _clearSecrets();
    maskedPhone = null;
    errorText = null;
    notifyListeners();
    await _requestCode('auth/password/request-otp');
  }

  Future<void> resendResetCode() => _requestCode('auth/password/request-otp');

  Future<void> resetPassword() async {
    if (!_validateCodeAndNewPassword()) return;
    final res = await _call('auth/password/reset', {
      'identifier': _canonical,
      'code': otpCtrl.text.trim(),
      'password': newPasswordCtrl.text,
    });
    if (res == null || errorText != null) return notifyListeners();
    if (!res.ok) {
      errorText = res.error ?? 'Код буруу байна.';
      return notifyListeners();
    }
    // Success: back to the password card, ready to sign in with the new one.
    step = LoginStep.password;
    lockedOut = false;
    _clearSecrets();
    _stopCooldown();
    messageComplete(
      res.data['message'] as String? ?? 'Нууц үг шинэчлэгдлээ. Шинэ нууц үгээрээ нэвтэрнэ үү.',
    );
    notifyListeners();
  }

  void cancelPasswordReset() {
    step = LoginStep.password;
    _clearSecrets();
    errorText = null;
    _stopCooldown();
    notifyListeners();
  }

  // ─── Common ────────────────────────────────────────────────────────────────

  Future<void> _requestCode(String path) async {
    if (resendIn > 0) return;
    final res = await _call(path, {'identifier': _canonical});
    if (res == null || errorText != null) return notifyListeners();
    if (!res.ok) {
      errorText = res.error ?? 'Код илгээхэд алдаа гарлаа.';
      return notifyListeners();
    }
    maskedPhone = res.data['maskedPhone'] as String? ?? maskedPhone;
    _startCooldown();
    notifyListeners();
  }

  bool _validateCodeAndNewPassword() {
    String? error;
    if (!RegExp(r'^\d{6}$').hasMatch(otpCtrl.text.trim())) {
      error = '6 оронтой кодоо оруулна уу.';
    } else if (newPasswordCtrl.text.length < 8) {
      error = 'Нууц үг хамгийн багадаа 8 тэмдэгт байна.';
    } else if (newPasswordCtrl.text != confirmPasswordCtrl.text) {
      error = 'Нууц үг таарахгүй байна.';
    }
    errorText = error;
    notifyListeners();
    return error == null;
  }

  void _handleLoginResponse(Map<String, dynamic> data) {
    final u = data['user'] as Map<String, dynamic>;
    final r = u['role'] as Map<String, dynamic>?;
    final t = u['tenant'] as Map<String, dynamic>;
    final login = SavedLogin(
      identifier: identifierForDisplay,
      email: u['email'] as String?,
      phone: u['phone']?.toString(),
      firstName: u['firstName'] as String?,
      lastName: u['lastName'] as String?,
      tenantName: t['name'] as String?,
      lastLoginAt: DateTime.now(),
    );
    savedLogin = login;
    unawaited(_savedLogins.write(login));
    Authenticator.user = User(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      id: u['id'] as String,
      email: u['email'] as String,
      firstName: u['firstName'] as String,
      lastName: u['lastName'] as String,
      phone: u['phone'].toString(),
      isOwner: u['isOwner'] as bool,
      // Server may return null for unassigned/owner staff — do not force-cast.
      branchId: u['branchId'] as String?,
      role: r != null
          ? UserRole(
              r['id'] as String,
              r['name'] as String,
              List<String>.from(r['permissions'] as List),
            )
          : null,
      tenant: UserTenant(t['id'] as String, t['name'] as String),
    );
    _clearSecrets();
    _stopCooldown();
    lockedOut = false;
    errorText = null;
    authState = AuthState.authorized;
    notifyListeners();
    // A self-deactivated account (Task 8) reactivates the moment it logs
    // back in — this login response is the only signal of that, so surface
    // it once here rather than the caller having to check separately.
    if (data['reactivated'] == true) {
      messageComplete('Бүртгэл тань сэргээгдлээ');
    }
    unawaited(_onSignedIn());
    // Just reached the server: a good moment for any queued sign-outs.
    unawaited(syncPendingLogouts());
  }
}
