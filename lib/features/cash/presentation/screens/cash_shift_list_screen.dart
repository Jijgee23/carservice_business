import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/network/working_branch_interceptor.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/money_format.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/filter_pill.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';
import 'package:carservice_business/features/cash/domain/cash_shift_repository.dart';
import 'package:carservice_business/features/cash/presentation/controllers/cash_shift_list_controller.dart';
import 'package:carservice_business/features/cash/presentation/screens/cash_shift_detail_screen.dart';
import 'package:carservice_business/features/cash/presentation/widgets/cash_shift_widgets.dart';
import 'package:carservice_business/features/cash/presentation/widgets/close_cash_shift_sheet.dart';
import 'package:carservice_business/features/cash/presentation/widgets/open_cash_shift_sheet.dart';
import 'package:carservice_business/features/shell/domain/working_branch.dart';

/// «Кассын ээлж» — the selected branch's current shift (open / close) and
/// every shift, newest first. Gated on `cash.manage` (owner always), like
/// every `/cash/sessions*` endpoint.
class CashShiftListScreen extends StatelessWidget {
  const CashShiftListScreen({
    super.key,
    this.repository,
    this.branchRepository,
    this.branchStore,
    this.user,
  });

  final CashShiftRepository? repository;
  final WorkingBranchRepository? branchRepository;
  final WorkingBranchSelectionStore? branchStore;
  final User? user;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => CashShiftListController(
      repo: repository,
      branchRepo: branchRepository,
      store: branchStore,
    ),
    child: _Body(user: user),
  );
}

User? _currentUser(User? injected) {
  if (injected != null) return injected;
  try {
    return Authenticator.user;
  } catch (_) {
    return null;
  }
}

class _Body extends StatefulWidget {
  const _Body({this.user});
  final User? user;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _allowed = canSeeView(_currentUser(widget.user), 'cash.manage');
    if (_allowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<CashShiftListController>().load();
      });
    }
  }

  Future<void> _open(CashShiftListController c) async {
    final branch = c.branchId;
    final opened = await OpenCashShiftSheet.show(
      context,
      branchId: branch,
      branchName: c.branchName(branch),
      branches: c.branches,
      repo: c.repo,
    );
    if (opened == null || !mounted) return;
    messageComplete('Ээлж нээгдлээ');
    await c.refresh();
  }

  Future<void> _close(CashShiftListController c, CashShift shift) async {
    final closed = await CloseCashShiftSheet.show(
      context,
      shift: shift,
      repo: c.repo,
    );
    if (closed == null || !mounted) return;
    messageComplete('Ээлж хаагдлаа · зөрүү ${formatSignedMoney(closed.difference)}');
    await c.refresh();
  }

  Future<void> _detail(CashShiftListController c, CashShift shift) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CashShiftDetailScreen(
          shiftId: shift.id,
          repository: c.repo,
          user: widget.user,
        ),
      ),
    );
    if (changed == true && mounted) await c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Кассын ээлж')),
        body: const EmptyState(
          message: 'Танд кассыг удирдах эрх байхгүй байна.',
          icon: Icons.lock_outline,
        ),
      );
    }
    final c = context.watch<CashShiftListController>();
    final items = c.listState.valueOrNull;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Кассын ээлж'),
        actions: [
          IconButton(
            tooltip: 'Шинэчлэх',
            onPressed: c.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: c.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (c.canPickBranch) ...[
              _BranchChips(controller: c),
              const SizedBox(height: 12),
            ] else if (c.branchName(c.branchId) != null) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.store_mall_directory_outlined,
                      size: 16,
                      color: context.colors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c.branchName(c.branchId)!,
                      style: context.textStyles.captionMedium,
                    ),
                  ],
                ),
              ),
            ],
            _CurrentShiftCard(
              controller: c,
              onOpen: () => _open(c),
              onClose: (s) => _close(c, s),
              onDetail: (s) => _detail(c, s),
            ),
            const SizedBox(height: 20),
            const OpsSectionLabel('Ээлжийн түүх'),
            const SizedBox(height: 8),
            _StatusChips(controller: c),
            const SizedBox(height: 12),
            ...switch (c.listState) {
              AsyncLoading() => const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              AsyncError(:final error) => [
                _ErrorBlock(error: error, onRetry: c.refresh),
              ],
              AsyncData() when items!.isEmpty => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: EmptyState(
                    key: ValueKey('cash_shift_empty'),
                    message: 'Ээлж бүртгэгдээгүй байна',
                    icon: Icons.point_of_sale_outlined,
                  ),
                ),
              ],
              AsyncData() => [
                for (final s in items!) ...[
                  _ShiftTile(
                    shift: s,
                    showBranch: c.branchId == null,
                    onTap: () => _detail(c, s),
                  ),
                  const SizedBox(height: 8),
                ],
                _Footer(controller: c),
              ],
            },
          ],
        ),
      ),
    );
  }
}

class _BranchChips extends StatelessWidget {
  const _BranchChips({required this.controller});
  final CashShiftListController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        FilterPill(
          label: 'Бүх салбар',
          selected: controller.branchId == null,
          onTap: () => controller.setBranch(null),
        ),
        for (final b in controller.branches) ...[
          const SizedBox(width: 6),
          FilterPill(
            label: b.name,
            selected: controller.branchId == b.id,
            onTap: () => controller.setBranch(b.id),
          ),
        ],
      ],
    ),
  );
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.controller});
  final CashShiftListController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final (value, label) in const [
          (null, 'Бүгд'),
          ('OPEN', 'Нээлттэй'),
          ('CLOSED', 'Хаагдсан'),
        ]) ...[
          FilterPill(
            label: label,
            selected: controller.status == value,
            onTap: () => controller.setStatus(value),
          ),
          const SizedBox(width: 6),
        ],
      ],
    ),
  );
}

class _CurrentShiftCard extends StatelessWidget {
  const _CurrentShiftCard({
    required this.controller,
    required this.onOpen,
    required this.onClose,
    required this.onDetail,
  });

  final CashShiftListController controller;
  final VoidCallback onOpen;
  final ValueChanged<CashShift> onClose;
  final ValueChanged<CashShift> onDetail;

  @override
  Widget build(BuildContext context) {
    final state = controller.currentState;
    if (state == null) {
      // No concrete branch selected: the sheet asks for one.
      return OpsCard(
        key: const ValueKey('cash_shift_pick_branch'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Одоогийн ээлжийг харахын тулд салбар сонгоно уу.',
              style: context.textStyles.caption,
            ),
            const SizedBox(height: 12),
            OpsPrimaryButton(
              label: 'Ээлж нээх',
              icon: Icons.lock_open_rounded,
              height: 46,
              onPressed: controller.branches.isEmpty ? null : onOpen,
            ),
          ],
        ),
      );
    }
    return switch (state) {
      AsyncLoading() => const OpsCard(
        child: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      AsyncError(:final error) => OpsCard(
        child: _ErrorBlock(error: error, onRetry: controller.refresh),
      ),
      AsyncData(value: null) => OpsCard(
        key: const ValueKey('cash_shift_none_open'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.point_of_sale_outlined, color: context.colors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Нээлттэй ээлж алга',
                    style: context.textStyles.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Төлбөр бүртгэхийн өмнө кассын ээлж нээнэ үү.',
              style: context.textStyles.caption,
            ),
            const SizedBox(height: 12),
            OpsPrimaryButton(
              key: const ValueKey('cash_shift_open_button'),
              label: 'Ээлж нээх',
              icon: Icons.lock_open_rounded,
              height: 46,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
      AsyncData(value: final CashShift value) => OpsCard(
        key: const ValueKey('cash_shift_current'),
        onTap: () => onDetail(value),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Одоогийн ээлж',
                    style: context.textStyles.bodyMedium,
                  ),
                ),
                const ShiftStatusPill(isOpen: true),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                '${formatShiftDateTime(value.openedAt)}-с',
                ?value.openedBy?.name,
              ].join(' · '),
              style: context.textStyles.caption,
            ),
            const Divider(height: 20),
            CashShiftSummary(shift: value),
            const SizedBox(height: 12),
            Row(
              children: [
                OpsSecondaryButton(
                  icon: Icons.receipt_long_outlined,
                  tooltip: 'Дэлгэрэнгүй',
                  height: 46,
                  onPressed: () => onDetail(value),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OpsPrimaryButton(
                    key: const ValueKey('cash_shift_close_button'),
                    label: 'Ээлж хаах',
                    icon: Icons.lock_outline_rounded,
                    dark: true,
                    height: 46,
                    onPressed: () => onClose(value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    };
  }
}

class _ShiftTile extends StatelessWidget {
  const _ShiftTile({
    required this.shift,
    required this.showBranch,
    required this.onTap,
  });

  final CashShift shift;
  final bool showBranch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = shift;
    final period = s.isOpen
        ? '${formatShiftTime(s.openedAt)} — одоо'
        : '${formatShiftTime(s.openedAt)} — ${formatShiftTime(s.closedAt)}';
    return OpsCard(
      key: ValueKey('cash_shift_tile_${s.id}'),
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        period,
                        style: opsMono(
                          context,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ShiftStatusPill(isOpen: s.isOpen),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (showBranch) s.branch.name,
                    ?(s.isOpen ? s.openedBy?.name : s.closedBy?.name),
                  ].join(' · '),
                  style: context.textStyles.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(s.isOpen ? s.expectedCash : s.countedCash),
                style: opsMono(
                  context,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              if (!s.isOpen)
                Text(
                  'Зөрүү ${formatSignedMoney(s.difference)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: differenceColor(context, s.difference),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: context.colors.textHint),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller});
  final CashShiftListController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final error = controller.loadMoreError;
    if (error != null || controller.hasNext) {
      return TextButton.icon(
        onPressed: controller.loadMore,
        icon: Icon(error != null ? Icons.refresh : Icons.expand_more),
        label: Text(
          error != null
              ? 'Дахин оролдох: ${error.display}'
              : 'Дараагийн хуудас',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Text(
          'Нийт ${controller.total} ээлж',
          style: context.textStyles.caption,
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.error, required this.onRetry});
  final AppError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        Icon(Icons.cloud_off_rounded, size: 40, color: context.colors.textHint),
        const SizedBox(height: 8),
        Text(error.display, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Дахин оролдох'),
        ),
      ],
    ),
  );
}
