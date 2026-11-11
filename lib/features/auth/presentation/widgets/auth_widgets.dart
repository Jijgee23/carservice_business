import 'dart:math' as math;

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The sign-in design's building blocks, shared by [LoginScreen] and
/// [SignupScreen]: the white 14px-corner fields, the SMS code boxes, the
/// accent button, the inline error and the back/step-counter page frame.

const authFieldRadius = 14.0;
const authFormMaxWidth = 480.0;

/// Side padding that centres the form at most [authFormMaxWidth] wide. Padding,
/// not a ConstrainedBox: SliverFillRemaining sizes its child by intrinsic
/// height, and a ConstrainedBox would measure the text at the full width.
double authGutter(double width) => math.max(24, (width - authFormMaxWidth) / 2);

Widget authFadeSlide(Widget child, Animation<double> anim) => FadeTransition(
  opacity: anim,
  child: SlideTransition(
    position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
    child: child,
  ),
);

/// Shared frame of the step screens (login's code and new-password screens,
/// every signup step): back button and step counter, icon tile, title, then
/// the screen's own content.
class AuthStepPage extends StatelessWidget {
  const AuthStepPage({
    super.key,
    required this.stepLabel,
    required this.onBack,
    required this.icon,
    required this.flowName,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String stepLabel;
  final VoidCallback? onBack;
  final Widget icon;
  final String flowName;
  final String title;
  final Widget subtitle;
  final List<Widget> children;

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
            return CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, 12, side, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthStepHeader(
                          stepLabel: stepLabel,
                          flowName: flowName,
                          onBack: onBack,
                        ),
                        const SizedBox(height: 24),
                        Align(alignment: Alignment.centerLeft, child: icon),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.56,
                            height: 1.2,
                            color: t.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DefaultTextStyle.merge(
                          style: TextStyle(fontSize: 15, height: 22 / 15, color: t.mutedText),
                          child: subtitle,
                        ),
                        const SizedBox(height: 24),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Back button, then which flow and which of its steps ("Засвар бүртгүүлэх
/// · 2 / 4") — the top row of every step screen.
class AuthStepHeader extends StatelessWidget {
  const AuthStepHeader({
    super.key,
    required this.stepLabel,
    required this.flowName,
    required this.onBack,
  });

  final String stepLabel;
  final String flowName;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Row(
      children: [
        IconButton(
          key: const ValueKey('login_back'),
          tooltip: 'Буцах',
          onPressed: onBack,
          style: IconButton.styleFrom(
            backgroundColor: t.panel,
            foregroundColor: t.ink,
            side: BorderSide(color: t.border),
            fixedSize: const Size.square(44),
            minimumSize: const Size.square(44),
          ),
          icon: const Icon(Icons.chevron_left_rounded, size: 24),
        ),
        // Which flow, and which of its screens.
        Expanded(
          child: Text(
            flowName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: t.mutedText),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          stepLabel,
          style: TextStyle(fontFamily: t.monoFontFamily, fontSize: 12, color: t.mutedText),
        ),
      ],
    );
  }
}

/// Strength meter and checklist. Only the length is required by the server;
/// the other rules are guidance.
class AuthPasswordRules extends StatelessWidget {
  const AuthPasswordRules({super.key, required this.password});

  final String password;

  static final _digit = RegExp(r'\d');
  static final _symbol = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final p = password;
    final rules = [
      ('8-аас дээш тэмдэгт', p.length >= 8),
      // Has both an upper- and a lower-case letter (Cyrillic too).
      ('Том, жижиг үсэг', p.toLowerCase() != p && p.toUpperCase() != p),
      ('Тоо агуулсан', _digit.hasMatch(p)),
      (r'Тусгай тэмдэгт (!@#$)', _symbol.hasMatch(p)),
    ];
    final score = rules.where((r) => r.$2).length;
    final (strength, color) = switch (score) {
      0 || 1 => ('Сул', t.danger),
      2 => ('Дунд', t.warn),
      3 => ('Сайн', t.ok),
      _ => ('Маш сайн', t.ok),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p.isNotEmpty) ...[
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < score ? color : t.border,
                      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            strength,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(authFieldRadius),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, (label, met)) in rules.indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: met ? t.ok.withValues(alpha: 0.12) : null,
                        border: met ? null : Border.all(color: t.mutedText3, width: 1.5),
                      ),
                      child: met ? Icon(Icons.check_rounded, size: 13, color: t.ok) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 14, color: met ? t.ink : t.mutedText),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Six code boxes over one hidden field: the system number pad and SMS
/// autofill (`oneTimeCode`) keep working, and a full code moves on by itself.
class AuthOtpBoxes extends StatefulWidget {
  const AuthOtpBoxes({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.hasError,
    required this.onChanged,
    required this.onCompleted,
  });

  static const length = 6;

  final Key fieldKey;
  final TextEditingController controller;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onCompleted;

  @override
  State<AuthOtpBoxes> createState() => _AuthOtpBoxesState();
}

class _AuthOtpBoxesState extends State<AuthOtpBoxes> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_rebuild);
    widget.controller.addListener(_rebuild);
    focusWhenShown(this, _focusNode);
  }

  @override
  void didUpdateWidget(AuthOtpBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focusNode.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final code = widget.controller.text;
    final focused = _focusNode.hasFocus;
    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          Positioned.fill(
            child: TextField(
              key: widget.fieldKey,
              focusNode: _focusNode,
              controller: widget.controller,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(AuthOtpBoxes.length),
              ],
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(color: Colors.transparent),
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                // Invisible; read out by screen readers.
                hintText: 'Баталгаажуулах код',
                hintStyle: TextStyle(color: Colors.transparent),
              ),
              onChanged: (value) {
                widget.onChanged(value);
                if (value.length == AuthOtpBoxes.length) widget.onCompleted();
              },
            ),
          ),
          // Drawn over the field; taps fall through to it.
          IgnorePointer(
            child: ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < AuthOtpBoxes.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: _box(t, i, code, focused)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(CarserviceTheme t, int i, String code, bool focused) {
    final active =
        focused &&
        (i == code.length || (code.length == AuthOtpBoxes.length && i == AuthOtpBoxes.length - 1));
    final border = active
        ? t.ink
        : widget.hasError
        ? t.danger
        : t.border;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(authFieldRadius),
        border: Border.all(color: border, width: active ? 2 : 1),
        boxShadow: [if (active) BoxShadow(color: t.ink.withValues(alpha: 0.12), spreadRadius: 4)],
      ),
      child: i < code.length
          ? Text(
              code[i],
              style: TextStyle(
                fontFamily: t.monoFontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: t.ink,
              ),
            )
          : active
          ? Container(width: 2, height: 26, color: t.accentHi)
          : null,
    );
  }
}

/// Takes focus once its screen is up. `autofocus` alone loses: while the
/// AnimatedSwitcher fades the previous step out, that step's field still
/// holds focus, and autofocus only applies to a scope with nothing focused —
/// so the new field stayed unfocused and the keyboard never opened.
void focusWhenShown(State state, FocusNode node) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (state.mounted) node.requestFocus();
  });
}

/// The design's input: white, 14px corners, a ring while focused.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.fieldKey,
    required this.controller,
    this.hint,
    this.prefix,
    this.suffix,
    this.obscure = false,
    this.autofocus = false,
    this.error = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String? hint;
  final Widget? prefix;
  final Widget? suffix;
  final bool obscure;
  final bool autofocus;
  final bool error;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_rebuild);
    if (widget.autofocus) focusWhenShown(this, _focusNode);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final focused = _focusNode.hasFocus;
    final ring = widget.error ? t.danger : t.ink;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      constraints: const BoxConstraints(minHeight: 54),
      padding: EdgeInsets.only(left: 14, right: widget.suffix == null ? 14 : 4),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(authFieldRadius),
        border: Border.all(
          color: widget.error || focused ? ring : t.border,
          width: widget.error || focused ? 1.5 : 1,
        ),
        boxShadow: [if (focused) BoxShadow(color: ring.withValues(alpha: 0.12), spreadRadius: 3)],
      ),
      child: Row(
        children: [
          if (widget.prefix != null) ...[
            IconTheme.merge(
              data: IconThemeData(size: 18, color: t.mutedText),
              child: widget.prefix!,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextField(
              key: widget.fieldKey,
              focusNode: _focusNode,
              controller: widget.controller,
              obscureText: widget.obscure,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              autofillHints: widget.autofillHints,
              inputFormatters: widget.inputFormatters,
              textCapitalization: widget.textCapitalization,
              // Credentials and registry data: no autocorrect, no suggestion strip.
              autocorrect: false,
              enableSuggestions: false,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              cursorColor: t.ink,
              style: TextStyle(fontSize: 16, color: t.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: 16, color: t.mutedText3),
              ),
            ),
          ),
          ?widget.suffix,
        ],
      ),
    );
  }
}

class AuthPasswordField extends StatelessWidget {
  const AuthPasswordField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.obscure,
    required this.hint,
    this.onToggle,
    this.autofocus = false,
    this.error = false,
    this.autofillHints,
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.onSubmitted,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final bool obscure;
  final String hint;

  /// Null hides the show/hide button (the confirm field follows the first).
  final VoidCallback? onToggle;
  final bool autofocus;
  final bool error;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return AuthField(
      fieldKey: fieldKey,
      controller: controller,
      obscure: obscure,
      autofocus: autofocus,
      error: error,
      hint: hint,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      prefix: const Icon(Icons.lock_outline_rounded),
      suffix: onToggle == null
          ? null
          : IconButton(
              tooltip: obscure ? 'Нууц үг харуулах' : 'Нууц үг нуух',
              onPressed: onToggle,
              color: t.mutedText,
              icon: Icon(
                obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20,
              ),
            ),
    );
  }
}

class AuthIconTile extends StatelessWidget {
  const AuthIconTile({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
    this.size = 52,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(size >= 52 ? 16 : 12),
    ),
    child: Icon(icon, size: size >= 52 ? 26 : 22, color: foreground),
  );
}

/// Inline error under the fields — the server's own message, verbatim.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = text;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: t == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                key: const ValueKey('login_error'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: context.colors.dangerBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 16, color: context.colors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 13,
                          height: 18 / 13,
                          color: context.colors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          disabledBackgroundColor: t.accent.withValues(alpha: 0.55),
          disabledForegroundColor: t.onAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(authFieldRadius)),
          elevation: 0,
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: t.onAccent),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: t.onAccent,
                        ),
                      ),
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 18, color: t.onAccent),
                  ],
                ],
              ),
      ),
    );
  }
}

class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: CarserviceTheme.of(context).ink,
    ),
  );
}
