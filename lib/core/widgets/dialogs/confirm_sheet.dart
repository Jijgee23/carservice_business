import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:flutter/material.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

class ConfirmStep {
  final String title;
  final String? message;
  final IconData? icon;
  final Color? iconColor;
  final String confirmLabel;

  /// true → confirm button red (default for last-step destructive actions)
  final bool isDangerous;

  const ConfirmStep({
    required this.title,
    this.message,
    this.icon,
    this.iconColor,
    required this.confirmLabel,
    this.isDangerous = false,
  });
}

// ─── Public API ───────────────────────────────────────────────────────────────

class ConfirmSheet {
  ConfirmSheet._();

  /// Нэг алхамт баталгаажуулалт.
  ///
  /// ```dart
  /// final ok = await ConfirmSheet.show(
  ///   context,
  ///   title: 'Гарах уу?',
  ///   message: 'Та системээс гарахдаа итгэлтэй байна уу?',
  ///   confirmLabel: 'Гарах',
  ///   icon: Icons.logout_rounded,
  ///   isDangerous: true,
  /// );
  /// if (ok) context.read<AuthController>().logout();
  /// ```
  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    IconData? icon,
    Color? iconColor,
    String confirmLabel = 'Тийм',
    String cancelLabel = 'Болих',
    bool isDangerous = false,

    /// Хэрэв өгвөл confirm дарахад loading харуулж, future дуусмагц хаана.
    Future<void> Function()? onConfirm,
  }) async {
    final result = await AppNav.sheet<bool>(
      _ConfirmSheetWidget(
        steps: [
          ConfirmStep(
            title: title,
            message: message,
            icon: icon,
            iconColor: iconColor,
            confirmLabel: confirmLabel,
            isDangerous: isDangerous,
          ),
        ],
        cancelLabel: cancelLabel,
        onConfirm: onConfirm,
      ),
      backgroundColor: Colors.transparent,
    );
    return result ?? false;
  }

  /// Олон алхамт баталгаажуулалт.
  ///
  /// ```dart
  /// final ok = await ConfirmSheet.steps(
  ///   context,
  ///   steps: [
  ///     ConfirmStep(title: 'Захиалга устгах уу?', confirmLabel: 'Үргэлжлүүлэх'),
  ///     ConfirmStep(
  ///       title: 'Эцсийн баталгаа',
  ///       message: 'Бүх мэдээлэл устах болно.',
  ///       confirmLabel: 'Устгах',
  ///       icon: Icons.delete_forever_rounded,
  ///       isDangerous: true,
  ///     ),
  ///   ],
  ///   onConfirm: () async => await ctrl.deleteOrder(id),
  /// );
  /// ```
  static Future<bool> steps(
    BuildContext context, {
    required List<ConfirmStep> steps,
    String cancelLabel = 'Болих',
    Future<void> Function()? onConfirm,
  }) async {
    assert(steps.isNotEmpty, 'steps must not be empty');
    final result = await AppNav.sheet<bool>(
      _ConfirmSheetWidget(
        steps: steps,
        cancelLabel: cancelLabel,
        onConfirm: onConfirm,
      ),
      backgroundColor: Colors.transparent,
    );
    return result ?? false;
  }
}

// ─── Sheet widget ─────────────────────────────────────────────────────────────

class _ConfirmSheetWidget extends StatefulWidget {
  final List<ConfirmStep> steps;
  final String cancelLabel;
  final Future<void> Function()? onConfirm;

  const _ConfirmSheetWidget({
    required this.steps,
    required this.cancelLabel,
    this.onConfirm,
  });

  @override
  State<_ConfirmSheetWidget> createState() => _ConfirmSheetWidgetState();
}

class _ConfirmSheetWidgetState extends State<_ConfirmSheetWidget> {
  int _step = 0;
  bool _loading = false;
  // Forward/back direction for slide animation
  bool _forward = true;

  ConfirmStep get _current => widget.steps[_step];
  bool get _isLast => _step == widget.steps.length - 1;
  bool get _isMultiStep => widget.steps.length > 1;

  void _next() {
    setState(() {
      _forward = true;
      _step++;
    });
  }

  void _back() {
    setState(() {
      _forward = false;
      _step--;
    });
  }

  Future<void> _confirm() async {
    if (widget.onConfirm != null) {
      setState(() => _loading = true);
      try {
        await widget.onConfirm!();
        if (mounted) AppNav.back(true);
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    } else {
      AppNav.back(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXL)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Back row (multi-step, step > 0)
          if (_isMultiStep && _step > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading ? null : _back,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: context.colors.textSecondary,
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Буцах', style: TextStyle(fontSize: 13)),
              ),
            ),

          // Step dots (multi-step only)
          if (_isMultiStep) ...[
            const SizedBox(height: 4),
            _StepDots(total: widget.steps.length, current: _step),
            const SizedBox(height: 20),
          ] else
            const SizedBox(height: 8),

          // Animated content; scrolls if a long message outgrows the sheet.
          Flexible(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) {
                  final begin = _forward
                      ? const Offset(0.12, 0)
                      : const Offset(-0.12, 0);
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: begin,
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: _StepContent(key: ValueKey(_step), step: _current),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Buttons
          Row(
            children: [
              // Cancel (always visible on first step or non-multi-step)
              if (_step == 0) ...[
                Expanded(
                  child: _CancelButton(
                    label: widget.cancelLabel,
                    onTap: _loading ? null : () => AppNav.back(false),
                  ),
                ),
                const SizedBox(width: 12),
              ],

              // Confirm / Next
              Expanded(
                flex: _step == 0 ? 1 : 1,
                child: _ConfirmButton(
                  label: _isLast
                      ? _current.confirmLabel
                      : _current.confirmLabel,
                  isDangerous: _current.isDangerous,
                  loading: _loading,
                  isLast: _isLast,
                  onTap: _isLast ? _confirm : _next,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Step content ─────────────────────────────────────────────────────────────

class _StepContent extends StatelessWidget {
  final ConfirmStep step;
  const _StepContent({super.key, required this.step});

  Color _iconColor(BuildContext context) =>
      step.iconColor ??
      (step.isDangerous ? context.colors.danger : context.colors.accent);
  Color _iconBg(BuildContext context) => step.isDangerous
      ? context.colors.dangerBg
      : _iconColor(context).withOpacity(0.1);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (step.icon != null) ...[
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _iconBg(context),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 28, color: _iconColor(context)),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          step.title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        if (step.message != null) ...[
          const SizedBox(height: 8),
          Text(
            step.message!,
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

// ─── Step dots ────────────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final int total;
  final int current;
  const _StepDots({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        final done = i < current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: done
                ? context.colors.good
                : active
                ? context.colors.accent
                : context.colors.divider,
            borderRadius: BorderRadius.circular(AppDimens.radiusXS),
          ),
          child: done
              ? Icon(
                  Icons.check_rounded,
                  size: 7,
                  color: CarserviceTheme.of(context).onAccent,
                )
              : null,
        );
      }),
    );
  }
}

// ─── Buttons ──────────────────────────────────────────────────────────────────

class _CancelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _CancelButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.textSecondary,
          side: BorderSide(color: context.colors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final String label;
  final bool isDangerous;
  final bool loading;
  final bool isLast;
  final VoidCallback onTap;

  const _ConfirmButton({
    required this.label,
    required this.isDangerous,
    required this.loading,
    required this.isLast,
    required this.onTap,
  });

  Color _bg(BuildContext context) =>
      isDangerous ? context.colors.danger : context.colors.accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _bg(context),
          disabledBackgroundColor: _bg(context).withOpacity(0.45),
          foregroundColor: CarserviceTheme.of(context).onAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          ),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!isLast) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, size: 15),
                  ],
                ],
              ),
      ),
    );
  }
}
