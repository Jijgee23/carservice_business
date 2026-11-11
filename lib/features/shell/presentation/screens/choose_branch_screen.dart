import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/working_branch_scope.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';

/// Post-login working-branch picker (web `/page/choose-branch` parity),
/// styled after the tenant-app design (Auth — Салбар сонгох).
///
/// Shown by the shell while [WorkingBranchController.needsChoice] is true.
/// The user marks a branch (the primary one to start with) and confirms with
/// "Үргэлжлүүлэх"; the pick is persisted by the controller and survives
/// restarts until the user switches it from Бусад or signs out.
class ChooseBranchScreen extends StatefulWidget {
  final WorkingBranchController controller;

  /// The signed-in user, for the greeting and the workshop name; null hides
  /// both.
  final User? user;

  const ChooseBranchScreen({super.key, required this.controller, this.user});

  @override
  State<ChooseBranchScreen> createState() => _ChooseBranchScreenState();
}

class _ChooseBranchScreenState extends State<ChooseBranchScreen> {
  bool _pending = false;
  String? _picked;

  /// The user's mark if still offered, else the primary branch, else the
  /// first option.
  String? get _selected {
    final options = widget.controller.options;
    final picked = _picked;
    if (picked != null && options.isValidSelection(picked)) return picked;
    for (final b in options.branches) {
      if (b.isPrimary) return b.id;
    }
    if (options.branches.isNotEmpty) return options.branches.first.id;
    return options.allowAll ? allWorkingBranches : null;
  }

  Future<void> _continue() async {
    final value = _selected;
    if (_pending || value == null) return;
    setState(() => _pending = true);
    final ok = await widget.controller.select(value);
    if (!mounted) return;
    setState(() => _pending = false);
    if (!ok) messageError('Энэ салбарыг сонгох боломжгүй байна.');
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final options = widget.controller.options;
    final user = widget.user;
    final selected = _selected;
    final tenant = user?.tenant.name.trim() ?? '';

    Widget option({
      required String value,
      required String title,
      String? subtitle,
      required IconData icon,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _BranchOption(
        key: ValueKey(
          value == allWorkingBranches
              ? 'choose_branch_all'
              : 'choose_branch_$value',
        ),
        title: title,
        subtitle: subtitle,
        icon: icon,
        selected: selected == value,
        onTap: _pending ? null : () => setState(() => _picked = value),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: t.shellBackground,
        body: SafeArea(
          // Centred, at most 520 wide — as padding, not a ConstrainedBox:
          // SliverFillRemaining sizes its child by intrinsic height, and a
          // ConstrainedBox would measure the text at the full width.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = math.max(24.0, (constraints.maxWidth - 520) / 2);
              return CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(side, 24, side, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (user != null) ...[
                            _Greeting(
                              firstName: user.firstName,
                              lastName: user.lastName,
                            ),
                            const SizedBox(height: 22),
                          ],
                          Text(
                            'Салбар сонгох',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.56,
                              height: 1.2,
                              color: t.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Өнөөдөр аль салбарт ажиллах вэ? Засварын хуудас, цаг '
                            'захиалга, тайлан энэ салбараар харагдана. Дараа нь '
                            '«Бусад» цэснээс солих боломжтой.',
                            style: TextStyle(
                              fontSize: 15,
                              height: 22 / 15,
                              color: t.mutedText,
                            ),
                          ),
                          const SizedBox(height: 22),
                          if (tenant.isNotEmpty) ...[
                            Text(
                              tenant.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: t.monoFontFamily,
                                fontSize: 11,
                                letterSpacing: 0.66,
                                color: t.mutedText,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          for (final b in options.branches)
                            option(
                              value: b.id,
                              title: b.name,
                              subtitle: [
                                if (b.isPrimary) 'Үндсэн салбар',
                                ?b.location,
                                ?b.hours,
                              ].join('\n'),
                              icon: Icons.store_mall_directory_outlined,
                            ),
                          if (options.allowAll)
                            option(
                              value: allWorkingBranches,
                              title: 'Бүх салбар',
                              subtitle:
                                  'Бүх салбарын өгөгдлийг нэгэн зэрэг харах',
                              icon: Icons.apartment_rounded,
                            ),
                          const Spacer(),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              key: const ValueKey('choose_branch_continue'),
                              onPressed: _pending || selected == null
                                  ? null
                                  : _continue,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.accent,
                                foregroundColor: t.onAccent,
                                disabledBackgroundColor: t.accent.withValues(
                                  alpha: 0.55,
                                ),
                                disabledForegroundColor: t.onAccent,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _pending
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: t.onAccent,
                                      ),
                                    )
                                  : const Text(
                                      'Үргэлжлүүлэх',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 48,
                            child: TextButton(
                              key: const ValueKey('choose_branch_logout'),
                              onPressed: _pending
                                  ? null
                                  : () =>
                                        context.read<AuthController>().logout(),
                              style: TextButton.styleFrom(
                                foregroundColor: t.ink,
                              ),
                              child: const Text(
                                'Гарах',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.firstName, required this.lastName});

  final String firstName;
  final String lastName;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final first = firstName.trim();
    final last = lastName.trim();
    final initials = [
      if (first.isNotEmpty) first.characters.first,
      if (last.isNotEmpty) last.characters.first,
    ].join().toUpperCase();
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: t.ink, shape: BoxShape.circle),
          child: ExcludeSemantics(
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: t.shellBackground,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Сайн байна уу,',
                style: TextStyle(fontSize: 13, color: t.mutedText),
              ),
              const SizedBox(height: 2),
              Text(
                first.isEmpty ? last : first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One choice: icon tile, name + details, radio mark. The selected card gets
/// a 2px ink border and a filled tile.
class _BranchOption extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _BranchOption({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: selected ? t.ink : t.border,
        width: selected ? 2 : 1,
      ),
    );
    final details = subtitle;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: t.panel,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            // The 2px border eats one more pixel of the 14px padding.
            padding: EdgeInsets.all(selected ? 13 : 14),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? t.ink : t.shellBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: selected ? t.shellBackground : t.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                      if (details != null && details.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          details,
                          style: TextStyle(
                            fontSize: 13,
                            height: 18 / 13,
                            color: t.mutedText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.panel,
                    border: Border.all(
                      color: selected ? t.accentHi : t.mutedText3,
                      width: selected ? 7 : 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
