import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/app/router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirm = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: context.colors.brandSurface,
      body: Stack(
        children: [
          // ─── Background blobs ──────────────────────────────────────────
          Positioned(top: -80, right: -60, child: _Blob(size: 240, opacity: 0.08)),
          Positioned(bottom: -100, left: -80, child: _Blob(size: 300, opacity: 0.06)),
          Positioned(top: 160, left: -40, child: _Blob(size: 160, opacity: 0.04)),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),

                    // ─── Logo ────────────────────────────────────────────
                    // The gear is round, so a circular glow hugs it.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.accent.withOpacity(0.35),
                            blurRadius: 28,
                            spreadRadius: -6,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'asset/icons/logo.png',
                        key: const ValueKey('login_logo'),
                        width: 88,
                        height: 88,
                        filterQuality: FilterQuality.medium,
                        // The "carservice.mn" title below already names it.
                        excludeFromSemantics: true,
                      ),
                    ),

                    const SizedBox(height: AppDimens.paddingLG),

                    Text(
                      'carservice.mn',
                      // brandSurface is a fixed always-dark hero surface
                      // regardless of app brightness, so textOnDark (not a
                      // brightness-following ink token) is correct here.
                      style: TextStyle(
                        color: context.colors.textOnDark,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Автомашины үйлчилгээний систем',
                      style: context.textStyles.caption.copyWith(
                        color: context.colors.textOnDark.withOpacity(0.55),
                      ),
                    ),

                    const SizedBox(height: 48),

                    // ─── Step card ───────────────────────────────────────
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.06),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _buildCard(auth),
                    ),

                    const SizedBox(height: 32),
                    Text(
                      '© 2025 carservice.mn — Бүх эрх хуулиар хамгаалагдсан',
                      style: context.textStyles.caption.copyWith(
                        color: context.colors.textOnDark.withOpacity(0.3),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    // Root navigator: there is no shell tab before sign-in.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _LegalLink(
                          key: const ValueKey('login_terms'),
                          label: 'Үйлчилгээний нөхцөл',
                          onTap: () => AppNav.toNamed<void>(AppPages.terms),
                        ),
                        Text(
                          '·',
                          style: context.textStyles.caption.copyWith(
                            color: context.colors.textOnDark.withOpacity(0.4),
                          ),
                        ),
                        _LegalLink(
                          key: const ValueKey('login_privacy_policy'),
                          label: 'Нууцлалын бодлого',
                          onTap: () => AppNav.toNamed<void>(AppPages.privacy),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(AuthController auth) {
    return Container(
      key: ValueKey(auth.step),
      padding: const EdgeInsets.all(AppDimens.paddingXL),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusXL),
        boxShadow: [
          BoxShadow(
            color: context.colors.textPrimary.withOpacity(0.15),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: switch (auth.step) {
        LoginStep.identifier => _IdentifierStep(auth: auth),
        LoginStep.password => _PasswordStep(
          auth: auth,
          obscure: _obscurePassword,
          onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        LoginStep.activate => _CodeStep(
          auth: auth,
          title: 'Анхны нэвтрэлт',
          subtitle: 'Та анх удаа нэвтэрч байна. Утсанд ирсэн кодоор нууц үгээ үүсгэнэ үү.',
          submitLabel: 'Идэвхжүүлэх',
          onSubmit: auth.activate,
          onResend: auth.requestOtp,
          obscureNew: _obscureNewPassword,
          onToggleNew: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
          obscureConfirm: _obscureConfirm,
          onToggleConfirm: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
        LoginStep.resetPassword => _CodeStep(
          auth: auth,
          title: 'Нууц үг сэргээх',
          subtitle: 'Бүртгэлтэй утсанд ирсэн кодоо оруулаад шинэ нууц үгээ тохируулна уу.',
          submitLabel: 'Нууц үг шинэчлэх',
          onSubmit: auth.resetPassword,
          onResend: auth.resendResetCode,
          onCancel: auth.cancelPasswordReset,
          obscureNew: _obscureNewPassword,
          onToggleNew: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
          obscureConfirm: _obscureConfirm,
          onToggleConfirm: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
        LoginStep.notRegistered => _NotRegisteredStep(auth: auth),
      },
    );
  }
}

// ─── Identifier chip (current email/phone + back) ─────────────────────────────

class _IdentifierChip extends StatelessWidget {
  final AuthController auth;
  const _IdentifierChip({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: InkWell(
            key: const ValueKey('login_change_identifier'),
            onTap: auth.loading ? null : auth.resetToIdentifier,
            borderRadius: BorderRadius.circular(AppDimens.radiusXL),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(AppDimens.radiusXL),
                border: Border.all(color: context.colors.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 14, color: context.colors.textSecondary),
                  const SizedBox(width: 6),
                  Icon(
                    auth.isPhoneIdentifier
                        ? Icons.phone_iphone_rounded
                        : Icons.mail_outline_rounded,
                    size: 14,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      auth.identifierForDisplay,
                      style: context.textStyles.captionMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Step 1: Email or phone ───────────────────────────────────────────────────

class _IdentifierStep extends StatelessWidget {
  final AuthController auth;
  const _IdentifierStep({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Нэвтрэх', style: context.textStyles.h2),
        const SizedBox(height: AppDimens.paddingXS),
        Text(
          'Бүртгэлтэй имэйл хаяг эсвэл утасны дугаараа оруулна уу',
          style: context.textStyles.caption,
        ),
        const SizedBox(height: AppDimens.paddingXL),
        const _FieldLabel('Имэйл эсвэл утасны дугаар'),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('login_identifier_field'),
          controller: auth.identifierCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.username],
          onChanged: (_) => auth.clearError(),
          onSubmitted: (_) => auth.loading ? null : auth.checkIdentifier(),
          style: context.textStyles.body,
          decoration: InputDecoration(
            hintText: 'name@example.mn эсвэл 99112233',
            prefixIcon: Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: context.colors.textHint,
            ),
          ),
        ),
        _ErrorBanner(text: auth.errorText),
        const SizedBox(height: AppDimens.paddingLG),
        _PrimaryButton(
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
  final AuthController auth;
  final bool obscure;
  final VoidCallback onToggle;
  const _PasswordStep({required this.auth, required this.obscure, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _IdentifierChip(auth: auth),
        const SizedBox(height: AppDimens.paddingMD),
        Text('Нэвтрэх', style: context.textStyles.h2),
        const SizedBox(height: AppDimens.paddingXS),
        Text('Нууц үгээ оруулна уу', style: context.textStyles.caption),
        const SizedBox(height: AppDimens.paddingXL),
        const _FieldLabel('Нууц үг'),
        const SizedBox(height: 6),
        _PasswordField(
          key: const ValueKey('login_password_field'),
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
          _ErrorBanner(text: auth.errorText),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('login_forgot_password'),
            onPressed: auth.loading ? null : auth.startPasswordReset,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Нууц үг мартсан уу?',
              style: context.textStyles.captionMedium.copyWith(color: context.colors.accent),
            ),
          ),
        ),
        const SizedBox(height: AppDimens.paddingSM),
        _PrimaryButton(label: 'Нэвтрэх', loading: auth.loading, onPressed: auth.login),
      ],
    );
  }
}

// ─── Step 2b / reset: SMS code + new password ────────────────────────────────

/// Shared by first sign-in (activate) and forgot-password: both send a
/// 6-digit SMS code and set a new password with it.
class _CodeStep extends StatelessWidget {
  final AuthController auth;
  final String title;
  final String subtitle;
  final String submitLabel;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onResend;
  final VoidCallback? onCancel;
  final bool obscureNew;
  final VoidCallback onToggleNew;
  final bool obscureConfirm;
  final VoidCallback onToggleConfirm;

  const _CodeStep({
    required this.auth,
    required this.title,
    required this.subtitle,
    required this.submitLabel,
    required this.onSubmit,
    required this.onResend,
    this.onCancel,
    required this.obscureNew,
    required this.onToggleNew,
    required this.obscureConfirm,
    required this.onToggleConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final masked = auth.maskedPhone;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _IdentifierChip(auth: auth),
          const SizedBox(height: AppDimens.paddingMD),
          Text(title, style: context.textStyles.h2),
          const SizedBox(height: AppDimens.paddingXS),
          Text(subtitle, style: context.textStyles.caption),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.colors.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            ),
            child: Row(
              children: [
                Icon(Icons.sms_outlined, size: 16, color: context.colors.accent),
                const SizedBox(width: AppDimens.paddingSM),
                Expanded(
                  child: Text(
                    masked == null
                        ? (auth.loading ? 'Код илгээж байна…' : 'Бүртгэлтэй утсанд код илгээнэ')
                        : masked == '**'
                        ? 'Бүртгэлтэй бол утсанд код илгээгдсэн'
                        : '$masked дугаарт код илгээлээ',
                    style: context.textStyles.captionMedium.copyWith(color: context.colors.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.paddingLG),
          const _FieldLabel('Баталгаажуулах код'),
          const SizedBox(height: 6),
          _FocusOnShow(
            builder: (focusNode) => TextField(
              key: const ValueKey('login_code_field'),
              focusNode: focusNode,
              controller: auth.otpCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.oneTimeCode],
              onChanged: (_) => auth.clearError(),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: context.textStyles.body.copyWith(
                letterSpacing: 6,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '• • • • • •',
                hintStyle: TextStyle(letterSpacing: 6, color: context.colors.textHint),
                prefixIcon: Icon(Icons.pin_rounded, size: 18, color: context.colors.textHint),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Шинэ нууц үг'),
          const SizedBox(height: 6),
          _PasswordField(
            key: const ValueKey('login_new_password_field'),
            controller: auth.newPasswordCtrl,
            obscure: obscureNew,
            onToggle: onToggleNew,
            hint: 'Хамгийн багадаа 8 тэмдэгт',
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            onChanged: (_) => auth.clearError(),
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Нууц үг давтах'),
          const SizedBox(height: 6),
          _PasswordField(
            key: const ValueKey('login_confirm_password_field'),
            controller: auth.confirmPasswordCtrl,
            obscure: obscureConfirm,
            onToggle: onToggleConfirm,
            hint: 'Нууц үгийг дахин оруулна уу',
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (_) => auth.clearError(),
            onSubmitted: () => auth.loading ? null : onSubmit(),
          ),
          _ErrorBanner(text: auth.errorText),
          Row(
            children: [
              if (onCancel != null)
                TextButton(
                  key: const ValueKey('login_cancel_reset'),
                  onPressed: auth.loading ? null : onCancel,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Буцах',
                    style: context.textStyles.captionMedium.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              const Spacer(),
              Flexible(
                flex: 4,
                child: TextButton(
                  key: const ValueKey('login_resend_code'),
                  onPressed: auth.loading || auth.resendIn > 0 ? null : onResend,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    auth.resendIn > 0 ? 'Дахин илгээх (${auth.resendIn}с)' : 'Код дахин илгээх',
                    style: context.textStyles.captionMedium.copyWith(
                      color: auth.resendIn > 0 ? context.colors.textHint : context.colors.accent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.paddingSM),
          _PrimaryButton(label: submitLabel, loading: auth.loading, onPressed: onSubmit),
        ],
      ),
    );
  }
}

// ─── Step 2c: Not registered ─────────────────────────────────────────────────

class _NotRegisteredStep extends StatelessWidget {
  final AuthController auth;
  const _NotRegisteredStep({required this.auth});

  @override
  Widget build(BuildContext context) {
    final phone = auth.isPhoneIdentifier;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _IdentifierChip(auth: auth),
        const SizedBox(height: AppDimens.paddingXL),
        Center(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: context.colors.dangerBg, shape: BoxShape.circle),
                child: Icon(Icons.no_accounts_outlined, size: 26, color: context.colors.danger),
              ),
              const SizedBox(height: AppDimens.paddingMD),
              Text(
                phone ? 'Бүртгэлгүй утасны дугаар' : 'Бүртгэлгүй имэйл хаяг',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                auth.identifierForDisplay,
                style: context.textStyles.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Системд бүртгэлгүй байна.\nБайгууллагынхаа админтай холбогдоно уу.',
                style: context.textStyles.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.paddingXL),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: auth.resetToIdentifier,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.textPrimary,
              side: BorderSide(color: context.colors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusLG),
              ),
            ),
            child: const Text(
              'Өөр имэйл / утас оруулах',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final String hint;
  final bool autofocus;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  const _PasswordField({
    super.key,
    required this.controller,
    required this.obscure,
    required this.onToggle,
    required this.hint,
    this.autofocus = false,
    this.autofillHints,
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => autofocus ? _FocusOnShow(builder: _field) : _field(null);

  Widget _field(FocusNode? focusNode) => Builder(
    builder: (context) => TextField(
      focusNode: focusNode,
      controller: controller,
      obscureText: obscure,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      style: context.textStyles.body,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: context.colors.textHint),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Харуулах' : 'Нуух',
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18,
            color: context.colors.textHint,
          ),
        ),
      ),
    ),
  );
}

/// Takes focus once its step is on screen. `autofocus` alone loses: while
/// the AnimatedSwitcher fades the previous step out, that step's field still
/// holds focus, and autofocus only applies to a scope with nothing focused —
/// so the new field stayed unfocused and the keyboard never opened.
class _FocusOnShow extends StatefulWidget {
  const _FocusOnShow({required this.builder});

  final Widget Function(FocusNode focusNode) builder;

  @override
  State<_FocusOnShow> createState() => _FocusOnShowState();
}

class _FocusOnShowState extends State<_FocusOnShow> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_focusNode);
}

/// Inline error under the fields — the server's own message, verbatim.
class _ErrorBanner extends StatelessWidget {
  final String? text;
  const _ErrorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = text;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: t == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                key: const ValueKey('login_error'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: context.colors.dangerBg,
                  borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 16, color: context.colors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t,
                        style: context.textStyles.caption.copyWith(color: context.colors.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Shown after too many wrong passwords (423): the only way back in is a
/// reset, so offer it right there.
class _LockedBanner extends StatelessWidget {
  final String? message;
  final VoidCallback? onReset;
  const _LockedBanner({required this.message, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        key: const ValueKey('login_locked'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.warningBg,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_clock_outlined, size: 16, color: context.colors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message ?? 'Аккаунт түгжигдсэн байна.',
                    style: context.textStyles.caption.copyWith(color: context.colors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReset,
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

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final IconData? icon;

  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.colors.accent,
          disabledBackgroundColor: context.colors.accent.withOpacity(0.55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusLG)),
          elevation: 0,
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CarserviceTheme.of(context).onAccent,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, style: context.textStyles.buttonText),
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 6),
                    Icon(icon, size: 16, color: CarserviceTheme.of(context).onAccent),
                  ],
                ],
              ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.colors.textPrimary,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final double opacity;
  const _Blob({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colors.accent.withOpacity(opacity),
      ),
    );
  }
}

/// Underlined footer link on the always-dark login surface.
class _LegalLink extends StatelessWidget {
  const _LegalLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: context.colors.textOnDark.withOpacity(0.6),
      textStyle: context.textStyles.caption.copyWith(decoration: TextDecoration.underline),
    ),
    child: Text(label),
  );
}
