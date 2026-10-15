import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/app_dropdown.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/cash/domain/settlement.dart';
import 'package:carservice_business/features/cash/presentation/controllers/settlement_flow_controller.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';
import 'package:carservice_business/features/orders/presentation/widgets/no_cash_session_warning.dart';
import 'package:carservice_business/features/orders/presentation/widgets/payment_method_sheet.dart';

/// Branch choice offered when the working scope does not pin one.
class CashBranchOption {
  final String id;
  final String name;
  const CashBranchOption(this.id, this.name);
}

/// «Тооцоо нийлэх» — one lump sum for several postpaid orders of a customer.
/// Pops with the created [Settlement].
class SettlementFlowScreen extends StatefulWidget {
  const SettlementFlowScreen({
    super.key,
    required this.controller,
    required this.customers,
    this.branches = const [],
  });

  final SettlementFlowController controller;
  final CustomersRepository customers;

  /// Switchable branches; the picker shows only when there are several.
  final List<CashBranchOption> branches;

  static Future<Settlement?> show(
    BuildContext context, {
    required SettlementFlowController controller,
    required CustomersRepository customers,
    List<CashBranchOption> branches = const [],
  }) => Navigator.of(context).push<Settlement>(
    MaterialPageRoute(
      builder: (_) => SettlementFlowScreen(
        controller: controller,
        customers: customers,
        branches: branches,
      ),
    ),
  );

  @override
  State<SettlementFlowScreen> createState() => _SettlementFlowScreenState();
}

class _SettlementFlowScreenState extends State<SettlementFlowScreen> {
  final _note = TextEditingController();
  SettlementFlowController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_rebuild);
    unawaited(_c.loadSessionFlag());
  }

  @override
  void dispose() {
    _c.removeListener(_rebuild);
    _note.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<CashRef>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CustomerPickerSheet(repo: widget.customers),
    );
    if (picked != null) await _c.setCustomer(picked);
  }

  Future<void> _pickDate() async {
    final picked = await AppDatePicker.single(
      context,
      initial: _c.date,
      lastDate: DateTime.now(),
    );
    if (picked != null) _c.setDate(picked);
  }

  Future<void> _confirm() async {
    // CARD goes through the (simulated) POS terminal before the settlement;
    // an unsubmittable draft never reaches it.
    if (!_c.canSubmit) return;
    if (_c.method == OrderPaymentMethod.CARD) {
      final terminalId = _c.accounts
          .where((a) => a.id == _c.bankId)
          .map((a) => a.terminalId)
          .firstOrNull;
      final paid = await PosSimulator.confirm(
        context,
        bankLabel:
            '${paymentBankLabelIn(_c.accounts, _c.bankId)}'
            '${terminalId == null ? '' : ' · TID $terminalId'}',
        amount: _c.total,
      );
      if (!paid || !mounted) return;
    }
    final saved = await _c.submit();
    if (saved != null && mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final customer = _c.customer;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Тооцоо нийлэх')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottom),
        children: [
          if (widget.branches.length > 1) ...[
            AppDropdown<String>(
              key: const ValueKey('settlement_branch'),
              value: _c.branchId,
              label: 'Салбар',
              hint: 'Салбар сонгох',
              items: [
                for (final b in widget.branches)
                  AppDropdownItem(value: b.id, label: b.name),
              ],
              onChanged: (v) => unawaited(_c.setBranch(v)),
            ),
            const SizedBox(height: 12),
          ],
          AppCard(
            key: const ValueKey('settlement_customer'),
            onTap: _pickCustomer,
            child: Row(
              children: [
                const Icon(Icons.business_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    customer?.name ?? 'Үйлчлүүлэгч сонгох',
                    style: context.textStyles.bodyMedium,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_c.notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _c.notice!,
                key: const ValueKey('settlement_notice'),
                style: TextStyle(color: context.colors.danger),
              ),
            ),
          _orders(context),
          if (_c.orders.isNotEmpty) ...[
            const SizedBox(height: 12),
            PaymentMethodField(
              key: const ValueKey('settlement_method'),
              choice: PaymentChoice(
                _c.method,
                _c.bankId,
                _c.bankId == null
                    ? null
                    : paymentBankLabelIn(_c.accounts, _c.bankId),
              ),
              banks: _c.accounts,
              onChanged: (choice) {
                _c.setMethod(choice.method);
                if (choice.bank != null) _c.setBank(choice.bank);
              },
            ),
            if (_c.showNoSessionWarning) const NoCashSessionWarning(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('settlement_date'),
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(cashDateParam(_c.date)),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('settlement_note'),
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Тайлбар'),
              onChanged: (v) => _c.note = v,
            ),
            if (_c.submitError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _c.submitError!.display,
                  key: const ValueKey('settlement_error'),
                  style: TextStyle(color: context.colors.danger),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('settlement_confirm'),
              onPressed: _c.canSubmit ? _confirm : null,
              child: _c.submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Баталгаажуулах · ${formatCashAmount(_c.total)}'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _orders(BuildContext context) {
    if (_c.customer == null) {
      return const EmptyState(
        message: 'Үйлчлүүлэгчээ сонгоно уу.',
        icon: Icons.person_search_outlined,
      );
    }
    if (_c.branchId == null) {
      return const EmptyState(
        message: 'Салбараа сонгоно уу.',
        icon: Icons.store_outlined,
      );
    }
    if (_c.loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_c.loadError != null) {
      return Column(
        children: [
          Text(_c.loadError!.display),
          TextButton(
            onPressed: () => unawaited(_c.loadEligible(selectAll: true)),
            child: const Text('Дахин оролдох'),
          ),
        ],
      );
    }
    if (_c.orders.isEmpty) {
      return const EmptyState(
        message: 'Тооцоо нийлэх засварын хуудас алга.',
        icon: Icons.receipt_long_outlined,
      );
    }
    final dateFmt = DateFormat('MM/dd');
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          CheckboxListTile(
            key: const ValueKey('settlement_select_all'),
            dense: true,
            value: _c.allSelected,
            onChanged: (v) => _c.toggleAll(v ?? false),
            title: const Text('Бүгдийг сонгох'),
          ),
          const Divider(height: 1),
          for (final o in _c.orders)
            CheckboxListTile(
              key: ValueKey('settlement_order_${o.id}'),
              dense: true,
              value: _c.selected.contains(o.id),
              onChanged: (v) => _c.toggle(o.id, v ?? false),
              title: Text(
                '${o.number}${o.plate == null ? '' : ' · ${o.plate}'}',
              ),
              subtitle: Text(
                [
                  if (o.completedAt != null) dateFmt.format(o.completedAt!),
                  'Нийт ${formatCashAmount(o.totalAmount)}',
                ].join(' · '),
              ),
              secondary: Text(
                formatCashAmount(o.outstanding),
                style: context.textStyles.bodyMedium,
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Нийт (${_c.selected.length} засварын хуудас)',
                    style: context.textStyles.bodyMedium,
                  ),
                ),
                Text(
                  formatCashAmount(_c.total),
                  key: const ValueKey('settlement_total'),
                  style: context.textStyles.bodyMedium.copyWith(fontSize: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet({required this.repo});
  final CustomersRepository repo;

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  Timer? _debounce;
  List<CashRef> _items = const [];
  bool _loading = true;
  String? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.repo.getCustomers(
      query: CustomerListQuery(q: q.trim().isEmpty ? null : q.trim()),
    );
    if (!mounted || gen != _gen) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _items = [
            for (final c in value.items)
              CashRef(c.id, [c.displayName, ?c.orgRegnumLabel].join(' · ')),
          ];
        case Err(:final error):
          _error = error.display;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('settlement_customer_search'),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Нэр, утас, регистр',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => unawaited(_search(v)),
              );
            },
          ),
          const SizedBox(height: 8),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in _items)
                        ListTile(
                          key: ValueKey('settlement_pick_${c.id}'),
                          title: Text(c.name),
                          onTap: () => Navigator.of(context).pop(c),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
