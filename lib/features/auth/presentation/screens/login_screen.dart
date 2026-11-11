import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The fixed navy hero behind the sign-in form ("Midnight + Alizarin"):
/// always dark, whatever the app brightness.
abstract final class _Hero {
  static const bg = OpsColors.darkPanel;
  static const line = OpsColors.darkLine;
  static const accent = OpsColors.darkAccent;
  static const ink = OpsColors.darkInk;
  static const muted = OpsColors.darkMuted;
}

/// Staff sign-in, following the tenant-app design (Auth — Нэвтрэх / OTP /
/// Шинэ нууц үг). The steps stay server-driven ([AuthController]):
///
/// - identifier / password / not registered → navy hero + form sheet;
/// - first sign-in and forgot password → the SMS code screen, then the
///   new-password screen ([AuthController.codeConfirmed]).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _obscureNewPassword = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final codeFlow = auth.step == LoginStep.activate || auth.step == LoginStep.resetPassword;

    return Scaffold(
      backgroundColor: CarserviceTheme.of(context).shellBackground,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        transitionBuilder: authFadeSlide,
        child: codeFlow
            ? _codeFlow(auth)
            : _HeroLayout(
                key: const ValueKey('login_hero'),
                subtitle: switch (auth.step) {
                  LoginStep.password => 'Нууц үгээ оруулаад нэвтэрнэ үү.',
                  LoginStep.notRegistered => 'Энэ дугаар, имэйл системд бүртгэлгүй байна.',
                  _ => 'Утасны дугаар эсвэл имэйлээрээ нэвтэрнэ үү.',
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                  transitionBuilder: authFadeSlide,
                  child: KeyedSubtree(
                    key: ValueKey(auth.step),
                    child: switch (auth.step) {
                      LoginStep.password => _PasswordStep(
                        auth: auth,
                        obscure: _obscurePassword,
                        onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      LoginStep.notRegistered => _NotRegisteredStep(auth: auth),
                      _ => _IdentifierStep(auth: auth),
                    },
                  ),
                ),
              ),
      ),
    );
  }

  Widget _codeFlow(AuthController auth) {
    final activate = auth.step == LoginStep.activate;
    final flowName = activate ? 'Анхны нэвтрэлт' : 'Нууц үг сэргээх';
    if (!auth.codeConfirmed) {
      return _CodeScreen(
        key: ValueKey('login_code_${auth.step}'),
        auth: auth,
        flowName: flowName,
        onBack: activate ? auth.resetToIdentifier : auth.cancelPasswordReset,
        onResend: activate ? auth.requestOtp : auth.resendResetCode,
      );
    }
    return _NewPasswordScreen(
      key: ValueKey('login_new_password_${auth.step}'),
      auth: auth,
      flowName: flowName,
      subtitle: activate
          ? 'Цаашид нэвтрэхдээ ашиглах нууц үгээ үүсгэнэ үү.'
          : 'Өмнө ашиглаж байгаагүй, хүчтэй нууц үг сонгоно уу.',
      submitLabel: activate ? 'Идэвхжүүлэх' : 'Хадгалах',
      onSubmit: activate ? auth.activate : auth.resetPassword,
      obscure: _obscureNewPassword,
      onToggle: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
    );
  }
}

// ─── Hero layout: navy header + rounded form sheet ───────────────────────────

class _HeroLayout extends StatelessWidget {
  const _HeroLayout({super.key, required this.subtitle, required this.child});

  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final insets = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: LayoutBuilder(
        builder: (context, constraints) => _scrollView(t, insets, authGutter(constraints.maxWidth)),
      ),
    );
  }

  Widget _scrollView(CarserviceTheme t, EdgeInsets insets, double side) => CustomScrollView(
    // No bounce: it would pull the navy header off the top edge.
    physics: const ClampingScrollPhysics(),
    slivers: [
      SliverToBoxAdapter(
        child: _HeroHeader(topInset: insets.top, side: side, subtitle: subtitle),
      ),
      SliverFillRemaining(
        hasScrollBody: false,
        // Navy behind the sheet's rounded top corners.
        child: ColoredBox(
          color: _Hero.bg,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.shellBackground,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, 28, side, 16 + insets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [child, const Spacer(), const SizedBox(height: 24), const _Footer()],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.topInset, required this.side, required this.subtitle});

  final double topInset;
  final double side;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final mono = CarserviceTheme.of(context).monoFontFamily;
    return ColoredBox(
      color: _Hero.bg,
      child: ClipRect(
        child: Stack(
          children: [
            const Positioned(
              right: -70,
              top: -40,
              child: CustomPaint(size: Size.square(260), painter: _RingsPainter()),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(side, topInset + 28, side, 64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'asset/icons/logo.png',
                          key: const ValueKey('login_logo'),
                          width: 40,
                          height: 40,
                          filterQuality: FilterQuality.medium,
                          // The name next to it already says it.
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Flexible(
                        child: Text(
                          'carservice.mn',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _Hero.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _Hero.line,
                          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                        ),
                        child: Text(
                          'АЖИЛТАН',
                          style: TextStyle(
                            fontFamily: mono,
                            color: _Hero.ink,
                            fontSize: 10,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Тавтай морил',
                    style: TextStyle(
                      color: _Hero.ink,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _Hero.muted, fontSize: 15, height: 22 / 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three concentric rings, the innermost in the accent — header decoration.
class _RingsPainter extends CustomPainter {
  const _RingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = size.width / 260;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 120 * scale, paint..color = _Hero.line);
    canvas.drawCircle(center, 84 * scale, paint..color = _Hero.line);
    canvas.drawCircle(center, 48 * scale, paint..color = _Hero.accent);
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) => false;
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    // On the Text, not as the button's textStyle: that would replace the
    // theme's font family instead of merging with it.
    const legalStyle = TextStyle(fontSize: 12, decoration: TextDecoration.underline);
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Шинэ сервис үү?', style: TextStyle(fontSize: 14, color: t.mutedText)),
            // A new workshop signs up in the app; staff accounts are created
            // by their workshop.
            TextButton(
              key: const ValueKey('login_signup'),
              onPressed: () => AppNav.toNamed<void>(AppPages.signup),
              style: TextButton.styleFrom(
                foregroundColor: t.accent,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text(
                'Бүртгүүлэх',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        // Root navigator: there is no shell tab before sign-in.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('login_terms'),
              onPressed: () => AppNav.toNamed<void>(AppPages.terms),
              style: TextButton.styleFrom(foregroundColor: t.mutedText),
              child: const Text('Үйлчилгээний нөхцөл', style: legalStyle),
            ),
            Text('·', style: context.textStyles.caption),
            TextButton(
              key: const ValueKey('login_privacy_policy'),
              onPressed: () => AppNav.toNamed<void>(AppPages.privacy),
              style: TextButton.styleFrom(foregroundColor: t.mutedText),
              child: const Text('Нууцлалын бодлого', style: legalStyle),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Step 1: Email or phone ───────────────────────────────────────────────────

class _IdentifierStep extends StatelessWidget {
  const _IdentifierStep({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthFieldLabel('Утасны дугаар эсвэл имэйл'),
        const SizedBox(height: 8),
        AuthField(
          fieldKey: const ValueKey('login_identifier_field'),
          controller: auth.identifierCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.username],
          hint: '8888 8888 эсвэл name@example.mn',
          prefix: const Icon(Icons.person_outline_rounded),
          onChanged: (_) => auth.clearError(),
          onSubmitted: (_) => auth.loading ? null : auth.checkIdentifier(),
        ),
        AuthErrorBanner(text: auth.errorText),
        const SizedBox(height: 20),
        AuthPrimaryButton(
          label: 'Үргэлжлүүлэх',
          loading: auth.loading,
          onPressed: auth.checkIdentifier,
          icon: Icons.arrow_forward_rounded,
        ),
      ],
    );
  }
}

// ─── Step 2a: Password ────────────────────────────────────────────────────────

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({required this.auth, required this.obscure, required this.onToggle});

  final AuthController auth;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthFieldLabel('Утасны дугаар эсвэл имэйл'),
        const SizedBox(height: 8),
        _IdentifierField(auth: auth),
        const SizedBox(height: 16),
        const AuthFieldLabel('Нууц үг'),
        const SizedBox(height: 8),
        AuthPasswordField(
          fieldKey: const ValueKey('login_password_field'),
          controller: auth.passwordCtrl,
          obscure: obscure,
          onToggle: onToggle,
          autofocus: true,
          hint: '••••••••',
          autofillHints: const [AutofillHints.password],
          onChanged: (_) => auth.clearError(),
          onSubmitted: () => auth.loading ? null : auth.login(),
        ),
        if (auth.lockedOut)
          _LockedBanner(
            message: auth.errorText,
            onReset: auth.loading ? null : auth.startPasswordReset,
          )
        else
          AuthErrorBanner(text: auth.errorText),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('login_forgot_password'),
            onPressed: auth.loading ? null : auth.startPasswordReset,
            style: TextButton.styleFrom(
              foregroundColor: t.accent,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: const Text(
              'Нууц үг мартсан?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 4),
        AuthPrimaryButton(label: 'Нэвтрэх', loading: auth.loading, onPressed: auth.login),
      ],
    );
  }
}

/// The identifier already checked by the server, shown like a filled field;
/// "Солих" goes back to step 1.
class _IdentifierField extends StatelessWidget {
  const _IdentifierField({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(authFieldRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(
            auth.isPhoneIdentifier ? Icons.phone_iphone_rounded : Icons.mail_outline_rounded,
            size: 18,
            color: t.mutedText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              auth.identifierForDisplay,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: t.ink),
            ),
          ),
          TextButton(
            key: const ValueKey('login_change_identifier'),
            onPressed: auth.loading ? null : auth.resetToIdentifier,
            style: TextButton.styleFrom(
              foregroundColor: t.accent,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Солих', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Step 2c: Not registered ─────────────────────────────────────────────────

class _NotRegisteredStep extends StatelessWidget {
  const _NotRegisteredStep({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final phone = auth.isPhoneIdentifier;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IdentifierField(auth: auth),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthIconTile(
                icon: Icons.no_accounts_outlined,
                size: 44,
                background: context.colors.dangerBg,
                foreground: t.danger,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phone ? 'Бүртгэлгүй утасны дугаар' : 'Бүртгэлгүй имэйл хаяг',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ажилтны эрхийг сервисийн админ олгодог. Байгууллагынхаа админтай холбогдоно уу.',
                      style: TextStyle(fontSize: 13, height: 19 / 13, color: t.mutedText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 54,
          child: OutlinedButton(
            onPressed: auth.resetToIdentifier,
            style: OutlinedButton.styleFrom(
              foregroundColor: t.ink,
              backgroundColor: t.panel,
              side: BorderSide(color: t.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(authFieldRadius)),
            ),
            child: const Text(
              'Өөр имэйл / утас оруулах',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // The owner of a workshop that is not on carservice yet: sign it up,
        // with the number they just typed.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Засварын эзэн үү?', style: TextStyle(fontSize: 14, color: t.mutedText)),
            TextButton(
              key: const ValueKey('login_not_registered_signup'),
              onPressed: () => AppNav.toNamed<void>(
                AppPages.signup,
                arguments: _localPhone.hasMatch(auth.identifierForDisplay)
                    ? auth.identifierForDisplay
                    : null,
              ),
              style: TextButton.styleFrom(
                foregroundColor: t.accent,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text(
                'Засвараа бүртгүүлэх',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static final _localPhone = RegExp(r'^\d{8}$');
}

// ─── Code flow: SMS code, then the new password ──────────────────────────────

class _CodeScreen extends StatelessWidget {
  const _CodeScreen({
    super.key,
    required this.auth,
    required this.flowName,
    required this.onBack,
    required this.onResend,
  });

  final AuthController auth;
  final String flowName;
  final VoidCallback onBack;
  final Future<void> Function() onResend;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final masked = auth.maskedPhone;
    final waiting = auth.resendIn > 0;
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final countdown = '${twoDigits(auth.resendIn ~/ 60)}:${twoDigits(auth.resendIn % 60)}';

    return AuthStepPage(
      stepLabel: '1 / 2',
      onBack: auth.loading ? null : onBack,
      icon: AuthIconTile(
        icon: Icons.smartphone_rounded,
        background: t.accent.withValues(alpha: 0.1),
        foreground: t.accent,
      ),
      flowName: flowName,
      title: 'Код оруулах',
      subtitle: masked == null
          ? Text(
              auth.loading
                  ? 'Код илгээж байна…'
                  : 'Бүртгэлтэй утсанд илгээсэн 6 оронтой кодыг оруулна уу.',
            )
          : masked == '**'
          ? const Text('Бүртгэлтэй бол утсанд тань 6 оронтой код илгээгдсэн.')
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
          fieldKey: const ValueKey('login_code_field'),
          controller: auth.otpCtrl,
          hasError: auth.errorText != null,
          onChanged: (_) => auth.clearError(),
          onCompleted: auth.confirmCode,
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
              key: const ValueKey('login_resend_code'),
              onPressed: auth.loading || waiting ? null : onResend,
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
        AuthErrorBanner(text: auth.errorText),
        const SizedBox(height: 16),
        AuthPrimaryButton(label: 'Баталгаажуулах', loading: auth.loading, onPressed: auth.confirmCode),
      ],
    );
  }
}

class _NewPasswordScreen extends StatelessWidget {
  const _NewPasswordScreen({
    super.key,
    required this.auth,
    required this.flowName,
    required this.subtitle,
    required this.submitLabel,
    required this.onSubmit,
    required this.obscure,
    required this.onToggle,
  });

  final AuthController auth;
  final String flowName;
  final String subtitle;
  final String submitLabel;
  final Future<void> Function() onSubmit;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return AuthStepPage(
      stepLabel: '2 / 2',
      onBack: auth.loading ? null : auth.editCode,
      icon: AuthIconTile(
        icon: Icons.verified_user_outlined,
        background: t.ink,
        foreground: t.shellBackground,
      ),
      flowName: flowName,
      title: 'Шинэ нууц үг',
      subtitle: Text(subtitle),
      children: [
        AutofillGroup(
          child: ListenableBuilder(
            listenable: Listenable.merge([auth.newPasswordCtrl, auth.confirmPasswordCtrl]),
            builder: (context, _) {
              final password = auth.newPasswordCtrl.text;
              final confirm = auth.confirmPasswordCtrl.text;
              // Flag a mismatch once it can no longer be a half-typed match.
              final mismatch =
                  confirm.isNotEmpty &&
                  confirm != password &&
                  (confirm.length >= password.length || !password.startsWith(confirm));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthFieldLabel('Шинэ нууц үг'),
                  const SizedBox(height: 8),
                  AuthPasswordField(
                    fieldKey: const ValueKey('login_new_password_field'),
                    controller: auth.newPasswordCtrl,
                    obscure: obscure,
                    onToggle: onToggle,
                    autofocus: true,
                    hint: 'Хамгийн багадаа 8 тэмдэгт',
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => auth.clearError(),
                  ),
                  const SizedBox(height: 10),
                  AuthPasswordRules(password: password),
                  const SizedBox(height: 16),
                  const AuthFieldLabel('Нууц үг давтах'),
                  const SizedBox(height: 8),
                  AuthPasswordField(
                    fieldKey: const ValueKey('login_confirm_password_field'),
                    controller: auth.confirmPasswordCtrl,
                    obscure: obscure,
                    hint: 'Нууц үгээ дахин оруулна уу',
                    autofillHints: const [AutofillHints.newPassword],
                    error: mismatch,
                    onChanged: (_) => auth.clearError(),
                    onSubmitted: () => auth.loading ? null : onSubmit(),
                  ),
                  if (mismatch)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, size: 14, color: t.danger),
                          const SizedBox(width: 6),
                          Text(
                            'Нууц үг таарахгүй байна',
                            style: TextStyle(fontSize: 13, color: t.danger),
                          ),
                        ],
                      ),
                    ),
                  // The inline mismatch already says what is wrong.
                  AuthErrorBanner(text: mismatch ? null : auth.errorText),
                ],
              );
            },
          ),
        ),
        const Spacer(),
        const SizedBox(height: 24),
        AuthPrimaryButton(label: submitLabel, loading: auth.loading, onPressed: onSubmit),
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

/// Shown after too many wrong passwords (423): the only way back in is a
/// reset, so offer it right there.
class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.message, required this.onReset});

  final String? message;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const ValueKey('login_locked'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.warningBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_clock_outlined, size: 16, color: t.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message ?? 'Аккаунт түгжигдсэн байна.',
                    style: TextStyle(fontSize: 13, height: 18 / 13, color: t.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: onReset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.ink,
                  backgroundColor: t.panel,
                  side: BorderSide(color: t.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.sms_outlined, size: 16),
                label: const Text('Утсаар нууц үг сэргээх'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
