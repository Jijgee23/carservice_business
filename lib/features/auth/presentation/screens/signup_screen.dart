import 'dart:math' as math;

import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carservice_business/features/auth/presentation/controllers/signup_controller.dart';
import 'package:carservice_business/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

const _flowName = 'Засвар бүртгүүлэх';

/// New workshop signup, in the sign-in design: the workshop, the owner's
/// sign-in details, a map pin, then the SMS code ([SignupController]). On
/// success the owner is signed in and lands in the app — the router leaves
/// the login page, and this screen with it.
///
/// Opened from the login page ([AppPages.signup]); [initialPhone] prefills
/// the phone when the number typed there was not registered.
class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key, this.initialPhone, this.api, this.deviceFields});

  final String? initialPhone;

  /// Test seams; the real API and device fields by default.
  @visibleForTesting
  final SignupApi? api;
  @visibleForTesting
  final Future<Map<String, Object>> Function()? deviceFields;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => SignupController(
        api: api,
        deviceFields: deviceFields,
        initialPhone: initialPhone,
        onSignedUp: (data, phone) =>
            context.read<AuthController>().completeSignup(data, phone: phone),
      ),
      child: const _SignupView(),
    );
  }
}

class _SignupView extends StatefulWidget {
  const _SignupView();

  @override
  State<_SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends State<_SignupView> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SignupController>();
    void back() {
      if (!c.back()) Navigator.of(context).maybePop();
    }

    return PopScope(
      // System back walks the steps; only the first one closes the screen.
      canPop: c.step == SignupStep.business && !c.loading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.back();
      },
      child: Scaffold(
        backgroundColor: CarserviceTheme.of(context).shellBackground,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          transitionBuilder: authFadeSlide,
          child: KeyedSubtree(
            key: ValueKey(c.step),
            child: switch (c.step) {
              SignupStep.business => _BusinessStep(c: c, onBack: back),
              SignupStep.account => _AccountStep(
                c: c,
                onBack: back,
                obscure: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
              ),
              SignupStep.location => _LocationStep(c: c, onBack: back),
              SignupStep.code => _CodeStep(c: c, onBack: back),
            },
          ),
        ),
      ),
    );
  }
}

// ─── 1 / 4: Засвар ──────────────────────────────────────────────────────────

class _BusinessStep extends StatelessWidget {
  const _BusinessStep({required this.c, required this.onBack});

  final SignupController c;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final person = c.isPerson;
    final regnoError = c.fieldErrors['registerNumber'];
    return AuthStepPage(
      stepLabel: c.stepLabel,
      onBack: c.loading ? null : onBack,
      icon: AuthIconTile(
        icon: Icons.storefront_outlined,
        background: t.accent.withValues(alpha: 0.1),
        foreground: t.accent,
      ),
      flowName: _flowName,
      title: 'Засварын мэдээлэл',
      subtitle: const Text(
        'Байгууллага эсвэл хувь хүнээр бүртгүүлж болно. Регистрээр нэр автоматаар бөглөгдөнө.',
      ),
      children: [
        const AuthFieldLabel('Регистрийн дугаар'),
        const SizedBox(height: 8),
        AuthField(
          fieldKey: const ValueKey('signup_regno_field'),
          controller: c.regnoCtrl,
          autofocus: true,
          hint: '1234567 эсвэл ҮҮ99993333',
          prefix: const Icon(Icons.badge_outlined),
          error: regnoError != null,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [_RegnoFormatter(), LengthLimitingTextInputFormatter(10)],
          textInputAction: TextInputAction.next,
          onChanged: c.onRegnoChanged,
          suffix: c.lookingUp
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                  ),
                )
              : c.lookupFound
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(Icons.check_circle_rounded, size: 20, color: t.ok),
                )
              : null,
        ),
        _FieldNote(
          error: regnoError,
          hint: c.lookingUp
              ? 'Шалгаж байна…'
              : c.lookupFound
              ? 'Олдсон (${person ? 'хувь хүн' : 'байгууллага'}) · нэр автоматаар бөглөгдлөө'
              : 'Байгууллага: 7 оронтой тоо · Хувь хүн: ҮҮ99993333',
        ),
        const SizedBox(height: 16),
        AuthFieldLabel(person ? 'Овог нэр' : 'Засварын нэр'),
        const SizedBox(height: 8),
        AuthField(
          fieldKey: const ValueKey('signup_org_name_field'),
          controller: c.orgNameCtrl,
          hint: person ? 'Жишээ: Бат Дорж' : 'Жишээ: Гранд Гараж ХХК',
          prefix: Icon(person ? Icons.person_outline_rounded : Icons.store_mall_directory_outlined),
          error: c.fieldErrors['orgName'] != null,
          textCapitalization: TextCapitalization.words,
          textInputAction: person ? TextInputAction.done : TextInputAction.next,
          onChanged: c.onOrgNameChanged,
          onSubmitted: person ? (_) => c.next() : null,
        ),
        _FieldNote(error: c.fieldErrors['orgName']),
        if (!person) ...[
          const SizedBox(height: 16),
          const AuthFieldLabel('Эзний овог нэр'),
          const SizedBox(height: 8),
          AuthField(
            fieldKey: const ValueKey('signup_owner_name_field'),
            controller: c.ownerNameCtrl,
            hint: 'Жишээ: Батын Болд',
            prefix: const Icon(Icons.person_outline_rounded),
            error: c.fieldErrors['ownerName'] != null,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.done,
            onChanged: (_) => c.clearError('ownerName'),
            onSubmitted: (_) => c.next(),
          ),
          _FieldNote(
            error: c.fieldErrors['ownerName'],
            hint: 'Та системийн эзэн (бүх эрхтэй админ) болж нэвтэрнэ.',
          ),
        ],
        AuthErrorBanner(text: c.errorText),
        const Spacer(),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: 'Үргэлжлүүлэх',
          icon: Icons.arrow_forward_rounded,
          loading: c.loading,
          onPressed: c.next,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Бүртгэлтэй юу?', style: TextStyle(fontSize: 14, color: t.mutedText)),
            TextButton(
              key: const ValueKey('signup_to_login'),
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(
                foregroundColor: t.accent,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text(
                'Нэвтрэх',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Registry numbers: no spaces, letters upper-cased as they are typed.
class _RegnoFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = normalizeRegno(newValue.text);
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ─── 2 / 4: Нэвтрэх мэдээлэл ────────────────────────────────────────────────

class _AccountStep extends StatelessWidget {
  const _AccountStep({
    required this.c,
    required this.onBack,
    required this.obscure,
    required this.onToggle,
  });

  final SignupController c;
  final VoidCallback onBack;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return AuthStepPage(
      stepLabel: c.stepLabel,
      onBack: c.loading ? null : onBack,
      icon: AuthIconTile(icon: Icons.verified_user_outlined, background: t.ink, foreground: t.shellBackground),
      flowName: _flowName,
      title: 'Нэвтрэх мэдээлэл',
      subtitle: const Text('Энэ утас, нууц үгээрээ апп болон carservice.mn-д нэвтэрнэ.'),
      children: [
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthFieldLabel('Утасны дугаар'),
              const SizedBox(height: 8),
              AuthField(
                fieldKey: const ValueKey('signup_phone_field'),
                controller: c.phoneCtrl,
                autofocus: c.phoneCtrl.text.isEmpty,
                hint: '8888 8888',
                prefix: const Icon(Icons.phone_iphone_rounded),
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                error: c.fieldErrors['phone1'] != null,
                textInputAction: TextInputAction.next,
                onChanged: (_) => c.clearError('phone1'),
              ),
              _FieldNote(
                error: c.fieldErrors['phone1'],
                hint: 'Баталгаажуулах код энэ дугаарт ирнэ.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const AuthFieldLabel('Имэйл'),
                  const SizedBox(width: 6),
                  Text('· заавал биш', style: TextStyle(fontSize: 13, color: t.mutedText)),
                ],
              ),
              const SizedBox(height: 8),
              AuthField(
                fieldKey: const ValueKey('signup_email_field'),
                controller: c.emailCtrl,
                hint: 'garage@gmail.com',
                prefix: const Icon(Icons.mail_outline_rounded),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                error: c.fieldErrors['orgEmail'] != null,
                textInputAction: TextInputAction.next,
                onChanged: (_) => c.clearError('orgEmail'),
              ),
              _FieldNote(error: c.fieldErrors['orgEmail']),
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: Listenable.merge([c.passwordCtrl, c.confirmCtrl]),
                builder: (context, _) {
                  final password = c.passwordCtrl.text;
                  final confirm = c.confirmCtrl.text;
                  // Flag a mismatch once it can no longer be a half-typed match.
                  final mismatch =
                      confirm.isNotEmpty &&
                      confirm != password &&
                      (confirm.length >= password.length || !password.startsWith(confirm));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AuthFieldLabel('Нууц үг'),
                      const SizedBox(height: 8),
                      AuthPasswordField(
                        fieldKey: const ValueKey('signup_password_field'),
                        controller: c.passwordCtrl,
                        obscure: obscure,
                        onToggle: onToggle,
                        hint: 'Хамгийн багадаа 8 тэмдэгт',
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        error: c.fieldErrors['password'] != null,
                        onChanged: (_) => c.clearError('password'),
                      ),
                      _FieldNote(error: c.fieldErrors['password']),
                      if (password.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        AuthPasswordRules(password: password),
                      ],
                      const SizedBox(height: 16),
                      const AuthFieldLabel('Нууц үг давтах'),
                      const SizedBox(height: 8),
                      AuthPasswordField(
                        fieldKey: const ValueKey('signup_confirm_password_field'),
                        controller: c.confirmCtrl,
                        obscure: obscure,
                        hint: 'Нууц үгээ дахин оруулна уу',
                        autofillHints: const [AutofillHints.newPassword],
                        error: mismatch || c.fieldErrors['passwordConfirm'] != null,
                        onChanged: (_) => c.clearError('passwordConfirm'),
                        onSubmitted: () => c.next(),
                      ),
                      _FieldNote(
                        error: mismatch ? 'Нууц үг таарахгүй байна.' : c.fieldErrors['passwordConfirm'],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _TermsCheckbox(
          value: c.termsAccepted,
          error: c.fieldErrors['terms'],
          onChanged: c.loading ? null : c.setTermsAccepted,
        ),
        AuthErrorBanner(text: c.errorText),
        const Spacer(),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: 'Үргэлжлүүлэх',
          icon: Icons.arrow_forward_rounded,
          loading: c.loading,
          onPressed: c.next,
        ),
      ],
    );
  }
}

/// The terms are accepted here, so the consent page after sign-in is skipped.
class _TermsCheckbox extends StatefulWidget {
  const _TermsCheckbox({required this.value, required this.error, required this.onChanged});

  final bool value;
  final String? error;
  final ValueChanged<bool>? onChanged;

  @override
  State<_TermsCheckbox> createState() => _TermsCheckboxState();
}

class _TermsCheckboxState extends State<_TermsCheckbox> {
  // Root navigator: there is no shell before sign-in.
  late final _terms = TapGestureRecognizer()..onTap = () => AppNav.toNamed<void>(AppPages.terms);
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => AppNav.toNamed<void>(AppPages.privacy);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final link = TextStyle(color: t.accent, fontWeight: FontWeight.w500);
    final onChanged = widget.onChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('signup_terms'),
          borderRadius: BorderRadius.circular(12),
          onTap: onChanged == null ? null : () => onChanged(!widget.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: widget.value,
                  onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
                  activeColor: t.accent,
                  checkColor: t.onAccent,
                  side: BorderSide(color: widget.error != null ? t.danger : t.mutedText3, width: 1.5),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Үйлчилгээний нөхцөл', style: link, recognizer: _terms),
                          const TextSpan(text: ' болон '),
                          TextSpan(text: 'Нууцлалын бодлого', style: link, recognizer: _privacy),
                          const TextSpan(text: '-г уншиж, зөвшөөрч байна.'),
                        ],
                      ),
                      style: TextStyle(fontSize: 14, height: 20 / 14, color: t.ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _FieldNote(error: widget.error),
      ],
    );
  }
}

// ─── 3 / 4: Байршил ─────────────────────────────────────────────────────────

/// A map with a fixed centre pin instead of the scrolling step page: the map
/// takes the free height, and no scroll view fights its drag gestures.
class _LocationStep extends StatelessWidget {
  const _LocationStep({required this.c, required this.onBack});

  final SignupController c;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = authGutter(constraints.maxWidth);
            return Padding(
              padding: EdgeInsets.fromLTRB(side, 12, side, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthStepHeader(
                    stepLabel: c.stepLabel,
                    flowName: _flowName,
                    onBack: c.loading ? null : onBack,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Байршил',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.56,
                      height: 1.2,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${c.isPerson ? 'Үйлчилгээ үзүүлэх газраа' : 'Засварын газраа'} '
                    'газрын зургийн голын тэмдэгт тааруулна уу. Үйлчлүүлэгчид таныг эндээс олно.',
                    style: TextStyle(fontSize: 15, height: 22 / 15, color: t.mutedText),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _PinMap(
                      initial: c.hasLocation ? LatLng(c.latitude!, c.longitude!) : null,
                      onPicked: c.setLocation,
                      onError: c.showError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AddressCard(c: c),
                  AuthErrorBanner(text: c.errorText ?? c.fieldErrors['latitude']),
                  const SizedBox(height: 16),
                  AuthPrimaryButton(
                    label: 'Код авах',
                    icon: Icons.sms_outlined,
                    loading: c.loading,
                    onPressed: c.next,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PinMap extends StatefulWidget {
  const _PinMap({required this.initial, required this.onPicked, required this.onError});

  /// The pin chosen earlier, if any; otherwise the map opens on Ulaanbaatar.
  final LatLng? initial;
  final void Function(double lat, double lng) onPicked;
  final ValueChanged<String> onError;

  @override
  State<_PinMap> createState() => _PinMapState();
}

class _PinMapState extends State<_PinMap> {
  static const _ulaanbaatar = LatLng(47.9185, 106.9177);
  static const _pickZoom = 17.0;

  final _map = MapController();
  bool _locating = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  /// The user moved the map: the pin (the centre) is the new location.
  void _onEvent(MapEvent e) {
    if (e.source == MapEventSource.mapController ||
        e.source == MapEventSource.nonRotatedSizeChange) {
      return;
    }
    final settled =
        e is MapEventMoveEnd ||
        e is MapEventFlingAnimationEnd ||
        e is MapEventFlingAnimationNotStarted ||
        e is MapEventDoubleTapZoomEnd ||
        e is MapEventScrollWheelZoom;
    if (settled) widget.onPicked(e.camera.center.latitude, e.camera.center.longitude);
  }

  void _moveTo(LatLng point, {double? zoom}) {
    _map.move(point, zoom ?? math.max(_map.camera.zoom, 16));
    widget.onPicked(point.latitude, point.longitude);
  }

  /// "Миний байршил": the permission is asked only now, on the tap.
  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        widget.onError('Утасны байршил (GPS) унтраалттай байна. Газрын зургаас гараар сонгоно уу.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        widget.onError('Байршлын зөвшөөрөл өгөөгүй тул газрын зургаас гараар сонгоно уу.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      _moveTo(LatLng(pos.latitude, pos.longitude), zoom: _pickZoom);
    } catch (_) {
      widget.onError('Байршил тогтоож чадсангүй. Газрын зургаас гараар сонгоно уу.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: widget.initial ?? _ulaanbaatar,
              initialZoom: widget.initial != null ? _pickZoom : 12,
              minZoom: 4,
              maxZoom: 19,
              backgroundColor: t.panel2,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapEvent: _onEvent,
              onTap: (_, point) => _moveTo(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'mn.infosystems.carservice_business',
                maxNativeZoom: 19,
              ),
              SimpleAttributionWidget(
                source: const Text('OpenStreetMap'),
                onTap: () => launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          // The pin's tip sits on the map's centre.
          IgnorePointer(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.25),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -20),
                    child: Icon(
                      Icons.location_on_rounded,
                      size: 44,
                      color: t.accent,
                      shadows: const [Shadow(blurRadius: 6, color: Color(0x40000000))],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: t.panel,
              shape: CircleBorder(side: BorderSide(color: t.border)),
              child: IconButton(
                key: const ValueKey('signup_my_location'),
                tooltip: 'Миний байршил',
                onPressed: _locating ? null : _locate,
                color: t.ink,
                icon: _locating
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                      )
                    : const Icon(Icons.my_location_rounded, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.c});

  final SignupController c;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final label = c.address?.label ?? '';
    final (String title, String detail) = !c.hasLocation
        ? ('Байршил сонгоогүй', 'Газрын зургийг чирэх эсвэл «Миний байршил»-ыг дарна уу.')
        : c.resolvingAddress
        ? ('Хаяг тодорхойлж байна…', _coords)
        : label.isNotEmpty
        ? (label, _coords)
        : ('Тэмдэглэсэн байршил', _coords);
    return Container(
      key: const ValueKey('signup_address'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(authFieldRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          AuthIconTile(
            icon: c.hasLocation ? Icons.place_rounded : Icons.place_outlined,
            size: 40,
            background: c.hasLocation ? t.accent.withValues(alpha: 0.1) : t.panel2,
            foreground: c.hasLocation ? t.accent : t.mutedText,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.mutedText,
                    fontFamily: c.hasLocation ? t.monoFontFamily : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _coords => '${c.latitude!.toStringAsFixed(6)}, ${c.longitude!.toStringAsFixed(6)}';
}

// ─── 4 / 4: Код ─────────────────────────────────────────────────────────────

class _CodeStep extends StatelessWidget {
  const _CodeStep({required this.c, required this.onBack});

  final SignupController c;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final masked = c.maskedPhone;
    final waiting = c.resendIn > 0;
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final countdown = '${twoDigits(c.resendIn ~/ 60)}:${twoDigits(c.resendIn % 60)}';
    final error = c.errorText ?? c.fieldErrors['code'];

    return AuthStepPage(
      stepLabel: c.stepLabel,
      onBack: c.loading ? null : onBack,
      icon: AuthIconTile(
        icon: Icons.smartphone_rounded,
        background: t.accent.withValues(alpha: 0.1),
        foreground: t.accent,
      ),
      flowName: _flowName,
      title: 'Код оруулах',
      subtitle: masked == null
          ? const Text('Утсанд тань илгээсэн 6 оронтой кодыг оруулна уу.')
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: masked,
                    style: TextStyle(color: t.ink, fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' дугаарт илгээсэн 6 оронтой кодыг оруулна уу.'),
                ],
              ),
            ),
      children: [
        AuthOtpBoxes(
          fieldKey: const ValueKey('signup_code_field'),
          controller: c.otpCtrl,
          hasError: error != null,
          onChanged: (_) => c.clearError('code'),
          onCompleted: c.submit,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: waiting
                  ? Text.rich(
                      TextSpan(
                        text: 'Код дахин авах ',
                        children: [
                          TextSpan(
                            text: countdown,
                            style: TextStyle(
                              fontFamily: t.monoFontFamily,
                              fontWeight: FontWeight.w500,
                              color: t.ink,
                            ),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: 14, color: t.mutedText),
                    )
                  : Text('Код ирээгүй юу?', style: TextStyle(fontSize: 14, color: t.mutedText)),
            ),
            TextButton(
              key: const ValueKey('signup_resend_code'),
              onPressed: c.loading || waiting ? null : c.resendCode,
              style: TextButton.styleFrom(
                foregroundColor: t.accent,
                disabledForegroundColor: t.mutedText3,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text(
                'Дахин илгээх',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        AuthErrorBanner(text: error),
        const Spacer(),
        const SizedBox(height: 24),
        AuthPrimaryButton(label: 'Бүртгүүлэх', loading: c.loading, onPressed: c.submit),
        const SizedBox(height: 12),
        Text(
          'Шинэ засвар үнэгүй багцаар эхэлнэ. Лого, ажлын цаг зэргийг дараа нь тохиргооноос оруулна.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 17 / 12, color: t.mutedText),
        ),
      ],
    );
  }
}

// ─── Shared ─────────────────────────────────────────────────────────────────

/// Under a field: its error in red, otherwise an optional muted hint.
class _FieldNote extends StatelessWidget {
  const _FieldNote({this.error, this.hint});

  final String? error;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final error = this.error;
    final hint = this.hint;
    if (error == null && hint == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: error != null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.error_outline_rounded, size: 14, color: t.danger),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(fontSize: 13, height: 18 / 13, color: t.danger),
                  ),
                ),
              ],
            )
          : Text(hint!, style: TextStyle(fontSize: 12, height: 17 / 12, color: t.mutedText)),
    );
  }
}
