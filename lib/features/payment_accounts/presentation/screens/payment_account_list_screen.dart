import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/payment_accounts/domain/payment_account.dart';
import 'package:carservice_business/features/payment_accounts/presentation/controllers/payment_account_list_controller.dart';
import 'package:carservice_business/features/payment_accounts/presentation/screens/payment_account_form_screen.dart';

/// «Төлбөрийн данс» — the tenant's payment methods (Бэлэн / Данс / POS),
/// active and inactive. Add, edit, activate/deactivate and delete (only an
/// unused account; a used one must be deactivated). Gated on `cash.manage`.
class PaymentAccountListScreen extends StatelessWidget {
  const PaymentAccountListScreen({super.key, this.repository, this.user});

  final PaymentAccountsRepository? repository;
  final User? user;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => PaymentAccountListController(repo: repository),
    child: _Body(user: user),
  );
}

enum _Action { edit, activate, deactivate, delete }

class _Body extends StatefulWidget {
  const _Body({this.user});
  final User? user;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final bool _allowed;

  @override
  void initState() {
    super.initState();
    User? user = widget.user;
    if (user == null) {
      try {
        user = Authenticator.user;
      } catch (_) {}
    }
    _allowed = canSeeView(user, 'cash.manage');
    if (_allowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<PaymentAccountListController>().load();
      });
    }
  }

  Future<void> _openForm(
    PaymentAccountListController c, [
    PaymentAccount? account,
  ]) async {
    final saved = await Navigator.of(context).push<PaymentAccount>(
      MaterialPageRoute(
        builder: (_) =>
            PaymentAccountFormScreen(account: account, repository: c.repo),
      ),
    );
    if (saved != null && mounted) c.upsert(saved);
  }

  Future<void> _onAction(
    PaymentAccountListController c,
    PaymentAccount account,
    _Action action,
  ) async {
    switch (action) {
      case _Action.edit:
        await _openForm(c, account);
      case _Action.activate:
      case _Action.deactivate:
        final next = action == _Action.activate;
        final error = await c.setActive(account, next);
        if (error != null) {
          messageError(error.display);
        } else {
          messageComplete(next ? 'Идэвхжлээ' : 'Идэвхгүй боллоо');
        }
      case _Action.delete:
        final ok = await ConfirmSheet.show(
          context,
          title: '«${account.name}»-г устгах уу?',
          message:
              'Гүйлгээнд ашиглагдсан бол устгах боломжгүй — идэвхгүй болгоно уу.',
          confirmLabel: 'Устгах',
          icon: Icons.delete_outline_rounded,
          isDangerous: true,
        );
        if (!ok || !mounted) return;
        final error = await c.delete(account);
        if (error != null) {
          messageError(error.display);
        } else {
          messageComplete('Устгагдлаа');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Төлбөрийн данс')),
        body: const EmptyState(
          message: 'Танд кассыг удирдах эрх байхгүй байна.',
          icon: Icons.lock_outline,
        ),
      );
    }
    final c = context.watch<PaymentAccountListController>();
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Төлбөрийн данс'),
        actions: [
          IconButton(
            tooltip: 'Шинэчлэх',
            onPressed: c.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('payment_account_add'),
        heroTag: 'payment_account_add_fab',
        onPressed: () => _openForm(c),
        backgroundColor: context.colors.accent,
        foregroundColor: CarserviceTheme.of(context).onAccent,
        icon: const Icon(Icons.add),
        label: const Text('Нэмэх'),
      ),
      body: AsyncStateView<List<PaymentAccount>>(
        state: c.state,
        onRetry: c.load,
        isEmpty: (items) => items.isEmpty,
        empty: const EmptyState(
          message: 'Төлбөрийн арга бүртгээгүй байна',
          icon: Icons.account_balance_outlined,
        ),
        builder: (context, items) {
          final groups = [
            for (final type in PaymentAccountType.values)
              (type, items.where((a) => a.type == type).toList()),
          ].where((g) => g.$2.isNotEmpty);
          return RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final (type, accounts) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                    child: OpsSectionLabel(type.label),
                  ),
                  OpsGroup(
                    children: [
                      for (final a in accounts)
                        _AccountRow(
                          account: a,
                          busy: c.busy.contains(a.id),
                          onTap: () => _openForm(c, a),
                          onAction: (action) => _onAction(c, a, action),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.busy,
    required this.onTap,
    required this.onAction,
  });

  final PaymentAccount account;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<_Action> onAction;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final t = CarserviceTheme.of(context);
    final icon = switch (a.type) {
      PaymentAccountType.cash => Icons.payments_outlined,
      PaymentAccountType.bankAccount => Icons.account_balance_outlined,
      PaymentAccountType.pos => Icons.credit_card_outlined,
    };
    return InkWell(
      key: ValueKey('payment_account_${a.id}'),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: t.shellBackground,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: a.isActive ? t.ink : t.mutedText3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: a.isActive ? t.ink : t.mutedText,
                    ),
                  ),
                  if (a.hint != null)
                    Text(
                      a.hint!,
                      style: opsMono(context, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (a.isTest) ...[
              const OpsPill('Туршилт', tone: OpsTone.info),
              const SizedBox(width: 4),
            ],
            if (!a.isActive) const OpsPill('Идэвхгүй', tone: OpsTone.neutral),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              PopupMenuButton<_Action>(
                key: ValueKey('payment_account_menu_${a.id}'),
                tooltip: 'Үйлдэл',
                icon: Icon(Icons.more_vert, color: t.mutedText),
                onSelected: onAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: _Action.edit, child: Text('Засах')),
                  if (!a.isCash)
                    a.isActive
                        ? const PopupMenuItem(
                            value: _Action.deactivate,
                            child: Text('Идэвхгүй болгох'),
                          )
                        : const PopupMenuItem(
                            value: _Action.activate,
                            child: Text('Идэвхжүүлэх'),
                          ),
                  if (!a.isCash)
                    PopupMenuItem(
                      value: _Action.delete,
                      child: Text(
                        'Устгах',
                        style: TextStyle(color: context.colors.danger),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
