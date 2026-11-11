import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/money_format.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';
import 'package:carservice_business/features/cash/domain/cash_shift_repository.dart';
import 'package:carservice_business/features/cash/presentation/controllers/cash_shift_detail_controller.dart';
import 'package:carservice_business/features/cash/presentation/widgets/cash_shift_widgets.dart';
import 'package:carservice_business/features/cash/presentation/widgets/close_cash_shift_sheet.dart';

/// One shift: figures, per-method breakdown, ledger rows, post-close voids,
/// and «Ээлж хаах» while it is open. Pops `true` when the shift changed.
class CashShiftDetailScreen extends StatelessWidget {
  const CashShiftDetailScreen({
    super.key,
    required this.shiftId,
    this.repository,
    this.user,
  });

  final String shiftId;
  final CashShiftRepository? repository;
  final User? user;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) =>
        CashShiftDetailController(shiftId: shiftId, repo: repository)..load(),
    child: _Body(user: user),
  );
}

class _Body extends StatelessWidget {
  const _Body({this.user});
  final User? user;

  User? get _user {
    if (user != null) return user;
    try {
      return Authenticator.user;
    } catch (_) {
      return null;
    }
  }

  Future<void> _close(BuildContext context, CashShiftDetailController c) async {
    final shift = c.shift;
    if (shift == null) return;
    final closed = await CloseCashShiftSheet.show(
      context,
      shift: shift,
      repo: c.repo,
    );
    if (closed == null || !context.mounted) return;
    messageComplete(
      'Ээлж хаагдлаа · зөрүү ${formatSignedMoney(closed.difference)}',
    );
    await c.markClosed();
  }

  @override
  Widget build(BuildContext context) {
    if (!canSeeView(_user, 'cash.manage')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ээлж')),
        body: const EmptyState(
          message: 'Танд кассыг удирдах эрх байхгүй байна.',
          icon: Icons.lock_outline,
        ),
      );
    }
    final c = context.watch<CashShiftDetailController>();
    final shift = c.shift;
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(c.changed);
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: Text(shift == null ? 'Ээлж' : shift.branch.name),
          actions: [
            IconButton(
              tooltip: 'Шинэчлэх',
              onPressed: c.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        bottomNavigationBar: shift != null && shift.isOpen
            ? OpsBottomActionBar(
                children: [
                  Expanded(
                    child: OpsPrimaryButton(
                      key: const ValueKey('cash_shift_detail_close'),
                      label: 'Ээлж хаах',
                      icon: Icons.lock_outline_rounded,
                      dark: true,
                      onPressed: () => _close(context, c),
                    ),
                  ),
                ],
              )
            : null,
        body: AsyncStateView<CashShiftDetail>(
          state: c.state,
          onRetry: c.load,
          builder: (context, detail) => RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Header(shift: detail.shift),
                if (detail.shift.byMethod.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const OpsSectionLabel('Төлбөрийн хэлбэрээр'),
                  const SizedBox(height: 8),
                  _MethodTable(rows: detail.shift.byMethod),
                ],
                if (detail.postCloseVoids.count > 0) ...[
                  const SizedBox(height: 12),
                  _PostCloseVoids(voids: detail.postCloseVoids),
                ],
                const SizedBox(height: 20),
                OpsSectionLabel('Гүйлгээ (${detail.entries.length})'),
                const SizedBox(height: 8),
                if (detail.entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'Гүйлгээ алга',
                        style: context.textStyles.caption,
                      ),
                    ),
                  )
                else
                  OpsGroup(
                    children: [
                      for (final e in detail.entries) _EntryRow(entry: e),
                    ],
                  ),
                if (detail.truncated)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Зөвхөн сүүлийн гүйлгээнүүдийг харуулж байна.',
                      style: context.textStyles.caption,
                    ),
                  ),
                if (detail.voidedEntries.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  OpsSectionLabel(
                    'Хүчингүй болсон (${detail.voidedEntries.length})',
                  ),
                  const SizedBox(height: 8),
                  OpsGroup(
                    children: [
                      for (final e in detail.voidedEntries)
                        _EntryRow(entry: e, voided: true),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.shift});
  final CashShift shift;

  @override
  Widget build(BuildContext context) {
    final s = shift;
    return OpsCard(
      key: const ValueKey('cash_shift_detail_header'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.branch.name, style: context.textStyles.bodyMedium),
              ),
              ShiftStatusPill(isOpen: s.isOpen),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Нээсэн: ${formatShiftDateTime(s.openedAt)}'
            '${s.openedBy == null ? '' : ' · ${s.openedBy!.name}'}',
            style: context.textStyles.caption,
          ),
          if (!s.isOpen)
            Text(
              'Хаасан: ${formatShiftDateTime(s.closedAt)}'
              '${s.closedBy == null ? '' : ' · ${s.closedBy!.name}'}',
              style: context.textStyles.caption,
            ),
          const Divider(height: 20),
          CashShiftSummary(shift: s),
          if (s.note != null) ...[
            const Divider(height: 20),
            Text(s.note!, style: context.textStyles.caption),
          ],
        ],
      ),
    );
  }
}

class _MethodTable extends StatelessWidget {
  const _MethodTable({required this.rows});
  final List<CashShiftMethodTotal> rows;

  @override
  Widget build(BuildContext context) => OpsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShiftFigure(
                  label:
                      '${[cashMethodLabel(m.method), ?m.bankLabel].join(' · ')} (${m.count})',
                  value: formatMoney(m.net),
                  bold: true,
                ),
                if (num.tryParse(m.expense) != 0)
                  Text(
                    'Орлого ${formatMoney(m.income)} · Зарлага ${formatMoney(m.expense)}',
                    style: context.textStyles.caption,
                  ),
                if (m.difference != null && m.method != 'CASH')
                  Text(
                    'Тоолсон ${formatMoney(m.counted)} · Зөрүү ${formatSignedMoney(m.difference)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: differenceColor(context, m.difference),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _PostCloseVoids extends StatelessWidget {
  const _PostCloseVoids({required this.voids});
  final CashShiftPostCloseVoids voids;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.colors.warningBg,
      borderRadius: BorderRadius.circular(AppDimens.radiusSM),
    ),
    child: Text(
      'Хаасны дараа ${voids.count} бэлэн гүйлгээ хүчингүй болсон '
      '(цэвэр ${formatMoney(voids.netAmount)}). Хаалтын дүн өөрчлөгдөхгүй.',
      style: TextStyle(color: context.colors.warning, fontSize: 12),
    ),
  );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, this.voided = false});
  final CashShiftEntry entry;
  final bool voided;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = voided
        ? context.colors.textHint
        : e.isIncome
        ? context.colors.good
        : context.colors.danger;
    final subtitle = [
      formatShiftTime(e.occurredAt),
      [e.methodLabel, ?e.bankLabel].join(' '),
      ?e.orderNumber,
      ?(e.customerName ?? e.counterparty),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            e.isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.typeName,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textPrimary,
                    decoration: voided ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  subtitle,
                  style: context.textStyles.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (voided && e.voidReason != null)
                  Text(e.voidReason!, style: context.textStyles.caption),
              ],
            ),
          ),
          Text(
            '${e.isIncome ? '+' : '−'}${formatMoney(e.amount)}',
            style: opsMono(
              context,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
