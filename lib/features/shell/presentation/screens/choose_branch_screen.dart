import 'package:flutter/material.dart';

import 'package:carservice_business/core/domain/working_branch_scope.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';

/// Post-login working-branch picker (web `/page/choose-branch` parity).
///
/// Shown by the shell while [WorkingBranchController.needsChoice] is true. The
/// pick is persisted by the controller and survives restarts until the user
/// switches it from the header or signs out.
class ChooseBranchScreen extends StatefulWidget {
  final WorkingBranchController controller;

  const ChooseBranchScreen({super.key, required this.controller});

  @override
  State<ChooseBranchScreen> createState() => _ChooseBranchScreenState();
}

class _ChooseBranchScreenState extends State<ChooseBranchScreen> {
  bool _pending = false;

  Future<void> _choose(String value) async {
    if (_pending) return;
    setState(() => _pending = true);
    final ok = await widget.controller.select(value);
    if (!mounted) return;
    setState(() => _pending = false);
    if (!ok) messageError('Энэ салбарыг сонгох боломжгүй байна.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = widget.controller.options;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
              children: [
                Text(
                  'Ажиллах салбараа сонгоно уу',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Засварын хуудас, цаг захиалга, тайлан цаашид энэ салбараар '
                  'харагдана. Дараа нь дээд талын цэснээс өөр салбар руу '
                  'шилжиж болно.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                for (final b in options.branches)
                  _BranchCard(
                    key: ValueKey('choose_branch_${b.id}'),
                    title: b.name,
                    subtitle: [
                      if (b.isPrimary) 'Үндсэн салбар',
                      ?b.location,
                      ?b.hours,
                    ].join('\n'),
                    enabled: !_pending,
                    onTap: () => _choose(b.id),
                  ),
                if (options.allowAll)
                  _BranchCard(
                    key: const ValueKey('choose_branch_all'),
                    title: 'Бүх салбар',
                    subtitle: 'Бүх салбарын өгөгдлийг нэгэн зэрэг харах',
                    accent: true,
                    enabled: !_pending,
                    onTap: () => _choose(allWorkingBranches),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool accent;
  final bool enabled;
  final VoidCallback onTap;

  const _BranchCard({
    super.key,
    required this.title,
    this.subtitle,
    this.accent = false,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: accent ? scheme.primary.withValues(alpha: 0.05) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: accent
                ? scheme.primary.withValues(alpha: 0.4)
                : scheme.outlineVariant,
          ),
        ),
        child: ListTile(
          enabled: enabled,
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: Icon(
            accent ? Icons.apartment_rounded : Icons.store_mall_directory,
            color: accent ? scheme.primary : null,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: accent ? scheme.primary : null,
            ),
          ),
          subtitle: subtitle == null || subtitle!.isEmpty
              ? null
              : Text(subtitle!),
          isThreeLine: (subtitle ?? '').contains('\n'),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
