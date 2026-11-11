import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/features/branches/domain/branch.dart';
import 'package:carservice_business/features/branches/domain/branches_repository.dart';
import 'package:carservice_business/features/branches/presentation/controllers/branch_list_controller.dart';
import 'package:carservice_business/features/branches/presentation/screens/branch_form_screen.dart';

/// Opens the create (`id == null`) or edit form; completes when it closes.
typedef BranchFormOpener = Future<Object?> Function(BuildContext context, String? id);

/// "Салбарууд" — the web's `/dashboard/branches` list: primary first, with
/// the primary/inactive badges, address and phone. Creating needs
/// `branches.create`, opening a branch's form `branches.edit` (owners
/// always); the list reloads when the form closes.
class BranchListScreen extends StatelessWidget {
  const BranchListScreen({super.key, this.repository, this.user, this.openForm});

  final BranchesRepository? repository;

  /// Defaults to the signed-in user.
  final User? user;

  /// Defaults to pushing [BranchFormScreen] on the current navigator.
  final BranchFormOpener? openForm;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => BranchListController(repo: repository)..load(),
    child: _Body(user: user ?? Authenticator.user, openForm: openForm),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.user, required this.openForm});

  final User? user;
  final BranchFormOpener? openForm;

  Future<void> _open(BuildContext context, String? id) async {
    final controller = context.read<BranchListController>();
    final opener = openForm;
    if (opener != null) {
      await opener(context, id);
    } else {
      await Navigator.of(context).push<Object?>(
        MaterialPageRoute(
          builder: (_) => BranchFormScreen(branchId: id, repository: controller.repository, user: user),
        ),
      );
    }
    await controller.load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BranchListController>();
    final canCreate = canSeeView(user, 'branches.create');
    final canEdit = canSeeView(user, 'branches.edit');
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Салбарууд'),
        actions: [
          IconButton(
            tooltip: 'Шинэчлэх',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: c.load,
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              key: const ValueKey('branch_create'),
              onPressed: () => _open(context, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Шинэ салбар'),
            )
          : null,
      body: AsyncStateView<List<BranchSummary>>(
        state: c.state,
        onRetry: c.load,
        isEmpty: (rows) => rows.isEmpty,
        empty: _Empty(canCreate: canCreate, onCreate: () => _open(context, null)),
        builder: (context, rows) => RefreshIndicator(
          onRefresh: c.load,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gutter = ((constraints.maxWidth - 720) / 2).clamp(16.0, double.infinity);
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 96),
                itemCount: rows.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == rows.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Зөвхөн идэвхтэй салбарууд жагсаалтад харагдана.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: context.colors.textHint),
                      ),
                    );
                  }
                  final b = rows[i];
                  return _BranchCard(
                    branch: b,
                    onTap: canEdit ? () => _open(context, b.id) : null,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({required this.branch, required this.onTap});

  final BranchSummary branch;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return OpsCard(
      key: ValueKey('branch_${branch.id}'),
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: branch.isPrimary ? OpsTone.accent.background(t) : t.shellBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.store_mall_directory_outlined,
              size: 20,
              color: branch.isPrimary ? t.accent : t.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        branch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.ink),
                      ),
                    ),
                    if (branch.isPrimary) ...[
                      const SizedBox(width: 8),
                      const OpsPill('Үндсэн', tone: OpsTone.accent),
                    ],
                    if (!branch.isActive) ...[
                      const SizedBox(width: 8),
                      const OpsPill('Идэвхгүй'),
                    ],
                  ],
                ),
                if (branch.address != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    branch.address!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: t.mutedText),
                  ),
                ],
                if (branch.phone != null) ...[
                  const SizedBox(height: 2),
                  Text(branch.phone!, style: opsMono(context, fontSize: 12)),
                ],
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: t.mutedText3),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canCreate, required this.onCreate});

  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.store_mall_directory_outlined, size: 48, color: context.colors.textHint),
          const SizedBox(height: 12),
          const Text('Салбар бүртгэгдээгүй байна'),
          if (canCreate) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Салбар нэмэх'),
            ),
          ],
        ],
      ),
    ),
  );
}
