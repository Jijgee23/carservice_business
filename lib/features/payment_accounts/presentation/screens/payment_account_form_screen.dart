import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/payment_accounts/data/payment_accounts_repository.dart';
import 'package:carservice_business/features/payment_accounts/domain/payment_account.dart';

/// Create / edit one payment account. Create offers «Данс» or «POS» («Бэлэн»
/// exists automatically); the type is fixed once saved. «Бэлэн» edits only
/// its name. Pops the saved [PaymentAccount].
class PaymentAccountFormScreen extends StatefulWidget {
  const PaymentAccountFormScreen({super.key, this.account, this.repository});

  /// null = create.
  final PaymentAccount? account;
  final PaymentAccountsRepository? repository;

  @override
  State<PaymentAccountFormScreen> createState() =>
      _PaymentAccountFormScreenState();
}

class _PaymentAccountFormScreenState extends State<PaymentAccountFormScreen> {
  late final PaymentAccountsRepository _repo =
      widget.repository ?? RemotePaymentAccountsRepository();
  late PaymentAccountType _type =
      widget.account?.type ?? PaymentAccountType.bankAccount;
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _number = TextEditingController(
    text: widget.account?.accountNumber ?? '',
  );
  late final _terminal = TextEditingController(
    text: widget.account?.terminalId ?? '',
  );
  late final _merchant = TextEditingController(
    text: widget.account?.merchantId ?? '',
  );
  late bool _isTest = widget.account?.isTest ?? false;

  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  bool get _isEdit => widget.account != null;
  bool get _isCash => _type == PaymentAccountType.cash;
  bool get _isPos => _type == PaymentAccountType.pos;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _terminal.dispose();
    _merchant.dispose();
    super.dispose();
  }

  Map<String, String> _validate() {
    final name = _name.text.trim();
    final digits = _number.text.replaceAll(RegExp(r'\D'), '');
    final idPattern = RegExp(r'^[A-Za-z0-9]{1,32}$');
    return {
      if (name.length < 2 || name.length > 80) 'name': 'Нэр 2–80 тэмдэгт байна.',
      if (!_isCash && (digits.length < 6 || digits.length > 20))
        'accountNumber': 'Дансны дугаар 6–20 орон байна.',
      if (_isPos &&
          _terminal.text.trim().isNotEmpty &&
          !idPattern.hasMatch(_terminal.text.trim()))
        'terminalId': 'Зөвхөн үсэг, тоо (32 хүртэл тэмдэгт).',
      if (_isPos &&
          _merchant.text.trim().isNotEmpty &&
          !idPattern.hasMatch(_merchant.text.trim()))
        'merchantId': 'Зөвхөн үсэг, тоо (32 хүртэл тэмдэгт).',
    };
  }

  Future<void> _submit() async {
    final local = _validate();
    if (local.isNotEmpty) {
      setState(() {
        _fieldErrors = local;
        _error = null;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _fieldErrors = const {};
    });
    final draft = PaymentAccountDraft(
      type: _type,
      name: _name.text,
      accountNumber: _isCash
          ? null
          : _number.text.replaceAll(RegExp(r'\D'), ''),
      terminalId: _terminal.text,
      merchantId: _merchant.text,
      isTest: _isTest,
    );
    final result = _isEdit
        ? await _repo.update(widget.account!.id, draft)
        : await _repo.create(draft);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        messageComplete(_isEdit ? 'Хадгалагдлаа' : 'Төлбөрийн данс нэмэгдлээ');
        Navigator.of(context).pop(value);
      case Err(:final error):
        setState(() {
          _submitting = false;
          _fieldErrors = error.fieldErrors ?? const {};
          _error = error.display;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    const shownFields = {'name', 'accountNumber', 'terminalId', 'merchantId'};
    final showError =
        _error != null && !_fieldErrors.keys.any(shownFields.contains);
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Төлбөрийн данс засах' : 'Төлбөрийн данс нэмэх'),
      ),
      bottomNavigationBar: OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsPrimaryButton(
              key: const ValueKey('payment_account_submit'),
              label: 'Хадгалах',
              icon: Icons.check_rounded,
              loading: _submitting,
              onPressed: _submit,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const OpsSectionLabel('Төрөл'),
          const SizedBox(height: 8),
          if (_isEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: OpsPill(_type.label, tone: OpsTone.info),
            )
          else
            SegmentedButton<PaymentAccountType>(
              key: const ValueKey('payment_account_type'),
              segments: const [
                ButtonSegment(
                  value: PaymentAccountType.bankAccount,
                  label: Text('Данс'),
                  icon: Icon(Icons.account_balance_outlined),
                ),
                ButtonSegment(
                  value: PaymentAccountType.pos,
                  label: Text('POS'),
                  icon: Icon(Icons.credit_card_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: _submitting
                  ? null
                  : (s) => setState(() => _type = s.first),
            ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('payment_account_name'),
            controller: _name,
            enabled: !_submitting,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Нэр',
              hintText: _isPos ? 'Жишээ: Хаан банк POS' : 'Жишээ: Хаан банк',
              errorText: _fieldErrors['name'],
            ),
          ),
          if (!_isCash && !_isEdit) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in paymentAccountNameSuggestions.take(6))
                  ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _name.text = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (!_isCash) ...[
            TextField(
              key: const ValueKey('payment_account_number'),
              controller: _number,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: InputDecoration(
                labelText: 'Дансны дугаар',
                errorText: _fieldErrors['accountNumber'],
              ),
            ),
          ],
          if (_isPos) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('payment_account_terminal'),
              controller: _terminal,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: 'Терминал ID (TID, заавал биш)',
                errorText: _fieldErrors['terminalId'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('payment_account_merchant'),
              controller: _merchant,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: 'Merchant ID (заавал биш)',
                errorText: _fieldErrors['merchantId'],
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('payment_account_test'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Туршилтын терминал'),
              subtitle: const Text('Туршилтын гүйлгээг тайлангаас ялгана'),
              value: _isTest,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _isTest = v),
            ),
          ],
          if (_isCash)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '«Бэлэн» нь автоматаар үүсдэг — зөвхөн нэрийг өөрчилнө.',
                style: context.textStyles.caption,
              ),
            ),
          if (showError)
            Container(
              key: const ValueKey('payment_account_error'),
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.dangerBg,
                borderRadius: BorderRadius.circular(AppDimens.radiusSM),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: context.colors.danger, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
