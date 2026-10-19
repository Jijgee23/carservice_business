import 'dart:math' as math;

import 'package:carservice_business/core/utils/price_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/no_cash_session_warning.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

// Shared payment-method modal (mobile: full-height bottom sheet, list first,
// tapping an option pushes its detail view). Lives in the orders feature
// because it is built on the orders domain (OrderPaymentMethod, PaymentBank)
// and the cash feature already depends on orders, not the other way round.

/// A chosen method (+ receiving account id for transfer / card). [bankLabel]
/// is display-only and never part of equality.
class PaymentChoice {
  final OrderPaymentMethod method;
  final String? bank;
  final String? bankLabel;
  const PaymentChoice(this.method, [this.bank, this.bankLabel]);

  @override
  bool operator ==(Object other) =>
      other is PaymentChoice && other.method == method && other.bank == bank;

  @override
  int get hashCode => Object.hash(method, bank);
}

/// Compact label for a choice, e.g. «Хаан банк · POS».
String paymentChoiceLabel(PaymentChoice choice) => switch (choice.method) {
  OrderPaymentMethod.CASH => 'Бэлэн',
  OrderPaymentMethod.QPAY => 'QPay',
  OrderPaymentMethod.OTHER => 'Бусад',
  OrderPaymentMethod.BANK_TRANSFER =>
    choice.bank == null ? 'Дансаар шилжүүлэх' : '${choice.bankLabel ?? choice.bank} · Шилжүүлэг',
  OrderPaymentMethod.CARD =>
    choice.bank == null ? 'Карт (POS)' : '${choice.bankLabel ?? choice.bank} · POS',
};

IconData paymentChoiceIcon(OrderPaymentMethod method) => switch (method) {
  OrderPaymentMethod.CASH => Icons.payments_outlined,
  OrderPaymentMethod.QPAY => Icons.qr_code_rounded,
  OrderPaymentMethod.OTHER => Icons.more_horiz_rounded,
  OrderPaymentMethod.BANK_TRANSFER => Icons.account_balance_outlined,
  OrderPaymentMethod.CARD => Icons.credit_card_rounded,
};

/// One selectable row of the left list.
class PaymentOption {
  final PaymentChoice choice;

  /// Group header shown above the first row of the group; null = ungrouped.
  final String? group;

  /// Display-only POS account facts; never part of equality.
  final bool isTest;
  final String? terminalId;
  const PaymentOption(this.choice, {this.group, this.isTest = false, this.terminalId});

  @override
  bool operator ==(Object other) => other is PaymentOption && other.choice == choice;

  @override
  int get hashCode => choice.hashCode;

  OrderPaymentMethod get method => choice.method;
  String? get bank => choice.bank;
  String? get bankLabel => choice.bankLabel;

  String get key => '${method.name}${bank == null ? '' : '_$bank'}';
  String get label => bank == null
      ? paymentChoiceLabel(choice)
      : '${bankLabel ?? bank!}${isTest ? ' · Туршилт' : ''}';
}

const kTransferGroup = 'Дансаар шилжүүлэх';
const kCardGroup = 'Карт (POS)';

/// Ordered option list: cash, QPay (order context only), transfer per bank,
/// card per POS account, other. One account list feeds both groups
/// (BANK_ACCOUNT -> transfer, POS -> card); CASH accounts are in neither.
List<PaymentOption> buildPaymentOptions({
  required List<PaymentBank> banks,
  required bool includeQPay,
  bool includeManual = true,
}) => [
  if (includeManual) const PaymentOption(PaymentChoice(OrderPaymentMethod.CASH)),
  if (includeQPay) const PaymentOption(PaymentChoice(OrderPaymentMethod.QPAY)),
  if (includeManual) ...[
    for (final b in banks.where((b) => b.isTransfer))
      PaymentOption(
        PaymentChoice(OrderPaymentMethod.BANK_TRANSFER, b.id, b.label),
        group: kTransferGroup,
      ),
    for (final b in banks.where((b) => b.isPos))
      PaymentOption(
        PaymentChoice(OrderPaymentMethod.CARD, b.id, b.label),
        group: kCardGroup,
        isTest: b.isTest,
        terminalId: b.terminalId,
      ),
    const PaymentOption(PaymentChoice(OrderPaymentMethod.OTHER)),
  ],
];

/// Records one payment; true on success (the sheet then closes).
typedef PaymentRecorder = Future<bool> Function(PaymentChoice choice, String amount);

final _primaryButtonStyle = FilledButton.styleFrom(minimumSize: const Size.fromHeight(52));
final _secondaryButtonStyle = OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52));

const _amountExceedsMessage = 'Дүн үлдэгдлээс их байж болохгүй.';

/// QPay in the record sheet. The form's action creates the invoice from the
/// typed amount; once one is pending, [viewBuilder] shows it.
class QPaySheetHooks {
  const QPaySheetHooks({
    required this.pending,
    required this.canCreate,
    required this.create,
    required this.noteBuilder,
    required this.viewBuilder,
  });

  /// An invoice is waiting to be paid.
  final bool Function() pending;

  /// QPay is loaded and configured, and the user may create an invoice.
  final bool Function() canCreate;

  /// Creates the invoice for the raw amount; true once it is pending.
  final Future<bool> Function(String amount) create;

  /// QPay's state under its row in the form (loading, not configured, a
  /// pending amount, ...); null when there is nothing to say.
  final Widget? Function(BuildContext context) noteBuilder;

  /// The pending invoice: QR, bank apps, check, cancel.
  final WidgetBuilder viewBuilder;
}

enum _Stage { form, qpay }

/// The payment modal. Two modes:
/// * record mode ([onRecord] set): one form — the amount on top, the method
///   as a select field (its list opens in a picker sheet), and pinned at the
///   bottom «Бүртгэх» with QPay's own button beside it. Every method but QPay
///   (card / POS too: no terminal is connected) records straight away; QPay
///   goes on to its invoice, with a back arrow;
/// * picker mode ([onRecord] null): list + «Сонгох», pops a [PaymentChoice]
///   ([pickOnTap]: a row tap pops it straight away).
///
/// The sheet is as tall as its content (up to 92% of the screen) and keeps
/// its main action pinned above the keyboard / home indicator.
class PaymentMethodSheet extends StatefulWidget {
  const PaymentMethodSheet({
    super.key,
    required this.banks,
    required this.title,
    this.balance,
    this.onRecord,
    this.initial,
    this.includeQPay = false,
    this.includeManual = true,
    this.defaultAmount = '',
    this.maxAmount,
    this.validateAmount,
    this.pickOnTap = false,
    this.qpay,
    this.listenable,
    this.isSettled,
    this.showNoSessionWarning,
    this.errorText,
    this.busy,
    this.liveBanks,
    this.banksLoading,
    this.banksFailed,
    this.onRetryBanks,
  });

  final List<PaymentBank> banks;
  final String title;

  /// Raw outstanding amount, shown under the title as «Үлдэгдэл …₮».
  final String? balance;
  final PaymentRecorder? onRecord;
  final PaymentChoice? initial;

  /// Offer QPay: its own button in record mode.
  final bool includeQPay;
  final bool includeManual;

  /// The amount field's starting value (the unpaid balance).
  final String defaultAmount;

  /// Raw upper bound of the amount (the unpaid balance): a larger value
  /// can't be typed. Null or empty: no bound.
  final String? maxAmount;

  /// Why the typed raw amount can't be used, shown under the field; null
  /// when it can. Checked before every method's action.
  final String? Function(String amount)? validateAmount;

  /// Picker mode: a row tap returns its choice, without «Сонгох».
  final bool pickOnTap;

  /// QPay's button and invoice; order context only.
  final QPaySheetHooks? qpay;

  /// Rebuilds the sheet when the owning controller changes.
  final Listenable? listenable;

  /// When true the sheet closes itself (order fully paid).
  final bool Function()? isSettled;
  final bool Function(OrderPaymentMethod method)? showNoSessionWarning;
  final String? Function()? errorText;
  final bool Function()? busy;

  /// Live bank list / load state; when set it overrides [banks] so rows
  /// appear as soon as GET /banks resolves.
  final List<PaymentBank> Function()? liveBanks;
  final bool Function()? banksLoading;
  final bool Function()? banksFailed;
  final VoidCallback? onRetryBanks;

  static Future<void> showRecord(
    BuildContext context, {
    required PaymentMethodSheet Function() builder,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => builder(),
  );

  static Future<PaymentChoice?> pick(
    BuildContext context, {
    required List<PaymentBank> banks,
    PaymentChoice? current,
    String title = 'Төлбөрийн хэлбэр',
    bool pickOnTap = false,
    List<PaymentBank> Function()? liveBanks,
    bool Function()? banksLoading,
    bool Function()? banksFailed,
    VoidCallback? onRetryBanks,
    Listenable? listenable,
  }) => showModalBottomSheet<PaymentChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => PaymentMethodSheet(
      banks: banks,
      title: title,
      initial: current,
      pickOnTap: pickOnTap,
      liveBanks: liveBanks,
      banksLoading: banksLoading,
      banksFailed: banksFailed,
      onRetryBanks: onRetryBanks,
      listenable: listenable,
      showNoSessionWarning: null,
    ),
  );

  @override
  State<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<PaymentMethodSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: liveFormatPriceInput(widget.defaultAmount),
  );
  PaymentOption? _selected;
  _Stage _stage = _Stage.form;
  String? _amountError;
  bool _closing = false;

  // The option list is rebuilt only when the bank list instance changes,
  // not on every controller notification.
  List<PaymentBank>? _optionsFor;
  List<PaymentOption> _optionsCache = const [];

  List<PaymentBank> get _banks => widget.liveBanks?.call() ?? widget.banks;

  List<PaymentOption> get _options {
    final banks = _banks;
    if (!identical(banks, _optionsFor)) {
      _optionsFor = banks;
      // Record mode offers QPay as its own button, not as a method.
      _optionsCache = buildPaymentOptions(
        banks: banks,
        includeQPay: _pickerMode && widget.includeQPay,
        includeManual: widget.includeManual,
      );
    }
    return _optionsCache;
  }

  bool get _pickerMode => widget.onRecord == null;

  bool get _qpayPending => widget.qpay?.pending() ?? false;

  /// The stage on screen. A QPay view whose invoice is gone (cancelled, or
  /// paid and cleared) falls back to the form.
  _Stage get _shownStage {
    if (_pickerMode) return _Stage.form;
    if (_stage == _Stage.qpay && !_qpayPending) return _Stage.form;
    return _stage;
  }

  String get _rawAmount => _amount.text.replaceAll(',', '').trim();

  @override
  void initState() {
    super.initState();
    final options = _options;
    _selected = options.firstWhere(
      (o) => widget.initial != null && o.choice == widget.initial,
      orElse: () => options.isEmpty
          ? const PaymentOption(PaymentChoice(OrderPaymentMethod.CASH))
          : options.first,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _select(PaymentOption option) {
    if (_pickerMode && widget.pickOnTap) {
      Navigator.of(context).pop(option.choice);
      return;
    }
    setState(() {
      _selected = option;
      _amountError = null;
    });
  }

  void _back() => setState(() => _stage = _Stage.form);

  /// Opens the method list over the form; a tap picks and closes it.
  Future<void> _pickMethod() async {
    final picked = await PaymentMethodSheet.pick(
      context,
      banks: _banks,
      current: _selected?.choice,
      pickOnTap: true,
      liveBanks: widget.liveBanks,
      banksLoading: widget.banksLoading,
      banksFailed: widget.banksFailed,
      onRetryBanks: widget.onRetryBanks,
      listenable: widget.listenable,
    );
    if (picked == null || !mounted) return;
    _select(_options.firstWhere((o) => o.choice == picked, orElse: () => PaymentOption(picked)));
  }

  /// Shows why the amount can't be used, if it can't.
  bool _amountOk() {
    final error = widget.validateAmount?.call(_rawAmount);
    setState(() => _amountError = error);
    return error == null;
  }

  /// Records the payment once the amount checks out. A card payment too:
  /// POS is only the method (no terminal is connected).
  Future<void> _submit(PaymentOption option) async {
    if (!_amountOk()) return;
    await _record(option);
  }

  /// Creates the QPay invoice for the amount and shows it.
  Future<void> _submitQPay() async {
    if (!_amountOk()) return;
    final ok = await widget.qpay!.create(_rawAmount);
    if (ok && mounted) setState(() => _stage = _Stage.qpay);
  }

  Future<void> _record(PaymentOption option) async {
    final ok = await widget.onRecord!(option.choice, _rawAmount);
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // `sizeOf` / `viewInsetsOf` subscribe to just those fields, so unrelated
    // MediaQuery changes do not rebuild the sheet.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final listenable = widget.listenable;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(0, maxHeight - keyboard)),
        // The stage (and so the header's back arrow) can follow controller
        // state, e.g. a cancelled invoice returns to the form.
        child: listenable == null
            ? _sheet(context)
            : ListenableBuilder(
                listenable: listenable,
                builder: (context, _) => _sheet(context),
              ),
      ),
    );
  }

  Widget _sheet(BuildContext context) {
    if (!_closing && (widget.isSettled?.call() ?? false)) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    final stage = _shownStage;
    final (content, footer) = switch (stage) {
      _ when _pickerMode => (_list(context), widget.pickOnTap ? null : _pickerFooter(context)),
      _Stage.form => _form(context),
      _Stage.qpay => (_qpayView(context), null),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader(
          title: widget.title,
          balance: widget.balance,
          onBack: stage == _Stage.form ? null : _back,
        ),
        Divider(height: 1, color: context.opsDivider),
        Flexible(child: content),
        if (footer != null) _Footer(child: footer),
      ],
    );
  }

  /// The option rows in their group blocks, with the bank load note.
  List<Widget> _optionBlocks(BuildContext context) {
    final blocks = <Widget>[];
    var rows = <Widget>[];
    String? group;
    var started = false;

    void flush() {
      if (!started) return;
      blocks.add(_OptionGroup(title: group, rows: rows));
      rows = <Widget>[];
    }

    for (final option in _options) {
      // «Бусад» always closes the list in its own block, so the bank status
      // note below can sit between it and the bank groups.
      if (!started || option.group != group || option.method == OrderPaymentMethod.OTHER) {
        flush();
        group = option.group;
        started = true;
      }
      rows.add(_row(context, option));
    }
    flush();

    if (widget.includeManual) {
      final loading = widget.banksLoading?.call() ?? false;
      final failed = widget.banksFailed?.call() ?? false;
      Widget? status;
      if (loading) {
        status = const Padding(
          key: ValueKey('pay_banks_loading'),
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      } else if (failed) {
        status = _StatusNote(
          key: const ValueKey('pay_banks_error'),
          icon: Icons.cloud_off_outlined,
          text: 'Банкны жагсаалт ачаалж чадсангүй',
          action: TextButton(
            key: const ValueKey('pay_banks_retry'),
            onPressed: widget.onRetryBanks,
            child: const Text('Дахин оролдох'),
          ),
        );
      } else if (_banks.isEmpty) {
        status = const _StatusNote(
          key: ValueKey('pay_banks_empty'),
          icon: Icons.account_balance_outlined,
          text: 'Төлбөрийн сонголт бүртгээгүй байна',
        );
      }
      // Placed before «Бусад» so it sits with the bank groups.
      if (status != null) {
        blocks.insert(blocks.isEmpty ? 0 : blocks.length - 1, status);
      }
    }
    return [
      for (var i = 0; i < blocks.length; i++) ...[
        if (i > 0) const SizedBox(height: 16),
        blocks[i],
      ],
    ];
  }

  /// A handful of rows: built eagerly, so the sheet sizes to its content
  /// and every row is reachable (scroll-into-view, accessibility).
  Widget _scroll(BuildContext context, List<Widget> children, {required bool hasFooter}) {
    final bottom = hasFooter ? 8.0 : 16 + MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _list(BuildContext context) =>
      _scroll(context, _optionBlocks(context), hasFooter: !widget.pickOnTap);

  /// Record mode: the amount, the method as a select field, and the
  /// method's action with QPay's own button beside it.
  (Widget, Widget?) _form(BuildContext context) {
    final option = _selected;
    final busy = widget.busy?.call() ?? false;
    final blocked =
        widget.showNoSessionWarning?.call(option?.method ?? OrderPaymentMethod.QPAY) ?? false;
    final qpayNote = widget.includeQPay ? widget.qpay?.noteBuilder(context) : null;
    final error = _errorBox(context);
    final children = <Widget>[
      _AmountField(
        controller: _amount,
        errorText: _amountError,
        maxAmount: double.tryParse(widget.maxAmount ?? ''),
        onChanged: () {
          if (_amountError != null) setState(() => _amountError = null);
        },
        onRejected: (raw) => setState(
          () => _amountError = widget.validateAmount?.call(raw) ?? _amountExceedsMessage,
        ),
      ),
      if (blocked) const NoCashSessionWarning(),
      if (widget.includeManual && option != null) ...[
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('ТӨЛБӨРИЙН ХЭЛБЭР', style: context.textStyles.label),
        ),
        _MethodSelect(
          option: option,
          subtitle: _subtitle(option),
          onTap: busy ? null : _pickMethod,
        ),
      ],
      if (qpayNote != null) ...[const SizedBox(height: 16), qpayNote],
      ?error,
    ];
    final footer = _formFooter(option, disabled: busy || blocked);
    return (_scroll(context, children, hasFooter: footer != null), footer);
  }

  /// The method's action, with QPay's button beside it when offered.
  Widget? _formFooter(PaymentOption? option, {required bool disabled}) {
    final primary = widget.includeManual && option != null
        ? _formAction(option, disabled: disabled)
        : null;
    final qpay = _qpayButton(disabled: disabled, filled: primary == null);
    if (primary == null || qpay == null) return primary ?? qpay;
    return Row(
      children: [
        Expanded(child: qpay),
        const SizedBox(width: 8),
        Expanded(child: primary),
      ],
    );
  }

  /// QPay's own action: creates the invoice for the typed amount, or shows
  /// the one already waiting.
  Widget? _qpayButton({required bool disabled, required bool filled}) {
    final qpay = widget.qpay;
    if (!widget.includeQPay || qpay == null) return null;
    final pending = _qpayPending;
    final VoidCallback? onPressed = pending
        ? () => setState(() => _stage = _Stage.qpay)
        : disabled || !qpay.canCreate()
        ? null
        : _submitQPay;
    final key = ValueKey(pending ? 'view_qpay' : 'create_qpay');
    const icon = Icon(Icons.qr_code_rounded, size: 20);
    final label = Text(pending ? 'QR харах' : 'QPay');
    return filled
        ? FilledButton.icon(
            key: key,
            style: _primaryButtonStyle,
            onPressed: onPressed,
            icon: icon,
            label: label,
          )
        : OutlinedButton.icon(
            key: key,
            style: _secondaryButtonStyle,
            onPressed: onPressed,
            icon: icon,
            label: label,
          );
  }

  Widget _formAction(PaymentOption option, {required bool disabled}) => FilledButton.icon(
    key: const ValueKey('create_manual_payment'),
    style: _primaryButtonStyle,
    onPressed: disabled ? null : () => _submit(option),
    icon: const Icon(Icons.check_rounded, size: 20),
    label: const Text('Бүртгэх'),
  );

  /// QPay: the pending invoice (QR, bank apps, check, cancel).
  Widget _qpayView(BuildContext context) => _scroll(context, [
    const _MethodSummary(method: OrderPaymentMethod.QPAY, title: 'QPay'),
    const SizedBox(height: 20),
    widget.qpay!.viewBuilder(context),
    ?_errorBox(context),
  ], hasFooter: false);

  Widget? _errorBox(BuildContext context) {
    final error = widget.errorText?.call();
    if (error == null) return null;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.opsDanger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: context.opsDanger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              key: const ValueKey('pay_sheet_error'),
              style: TextStyle(color: context.opsDanger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Account number for a transfer, terminal id for a card.
  String? _subtitle(PaymentOption option) => switch (option.method) {
    OrderPaymentMethod.BANK_TRANSFER => _accountNumber(option.bank),
    OrderPaymentMethod.CARD => option.terminalId == null ? null : 'TID ${option.terminalId}',
    _ => null,
  };

  Widget _row(BuildContext context, PaymentOption option) {
    final selected = _selected == option;
    final isCard = option.method == OrderPaymentMethod.CARD;
    final subtitle = _subtitle(option);
    final title = option.bank == null
        ? paymentChoiceLabel(option.choice)
        : option.bankLabel ?? option.bank!;
    return Material(
      key: ValueKey('pay_opt_${option.key}'),
      color: selected ? context.opsAccent.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: () => _select(option),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _MethodIcon(method: option.method),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: context.textStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (option.isTest) _Tag(text: 'Туршилт', color: context.opsWarning),
                          if (isCard) _Tag(text: 'POS', color: context.opsTextSecondary),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: context.textStyles.caption.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? context.opsAccent : context.opsTextHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _accountNumber(String? bankId) {
    for (final b in _banks) {
      if (b.id == bankId) return b.displayNumber;
    }
    return null;
  }

  Widget _pickerFooter(BuildContext context) => FilledButton(
    key: const ValueKey('pay_pick_confirm'),
    style: _primaryButtonStyle,
    onPressed: _selected == null ? null : () => Navigator.of(context).pop(_selected!.choice),
    child: const Text('Сонгох'),
  );
}

/// The chosen method as a select field; a tap opens the method list.
class _MethodSelect extends StatelessWidget {
  const _MethodSelect({required this.option, required this.subtitle, required this.onTap});

  final PaymentOption option;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDimens.radiusMD);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('pay_method_select'),
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: context.opsDivider),
          ),
          child: Row(
            children: [
              _MethodIcon(method: option.method, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          paymentChoiceLabel(option.choice),
                          style: context.textStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (option.isTest) _Tag(text: 'Туршилт', color: context.opsWarning),
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: context.textStyles.caption.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.unfold_more_rounded, color: context.opsTextHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.balance, this.onBack});

  final String title;
  final String? balance;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final amount = balance == null || balance!.isEmpty ? null : '${formatPriceInput(balance!)}₮';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.opsDivider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  key: const ValueKey('pay_sheet_back'),
                  tooltip: 'Буцах',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              else
                const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: const ValueKey('pay_sheet_title'),
                      style: context.textStyles.h3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (amount != null)
                      Text.rich(
                        TextSpan(
                          text: 'Үлдэгдэл ',
                          children: [
                            TextSpan(
                              text: amount,
                              style: TextStyle(
                                color: context.opsTextPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        key: const ValueKey('pay_sheet_balance'),
                        style: context.textStyles.caption.copyWith(
                          fontSize: 13,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('pay_sheet_close'),
                tooltip: 'Хаах',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rows of one group in a single bordered block, divided by hairlines.
class _OptionGroup extends StatelessWidget {
  const _OptionGroup({required this.title, required this.rows});

  final String? title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title!.toUpperCase(),
              key: ValueKey('pay_group_$title'),
              style: context.textStyles.label,
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: context.opsDivider),
            borderRadius: BorderRadius.circular(AppDimens.radiusLG),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusLG - 1),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 64, color: context.opsDivider),
                  rows[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MethodIcon extends StatelessWidget {
  const _MethodIcon({required this.method, this.size = 40});

  final OrderPaymentMethod method;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.opsAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
      ),
      child: Icon(paymentChoiceIcon(method), size: size * 0.5, color: context.opsAccent),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _StatusNote extends StatelessWidget {
  const _StatusNote({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: context.opsCardBg,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.opsTextSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.textStyles.body)),
          ?action,
        ],
      ),
    );
  }
}

/// The chosen method at the top of its detail view.
class _MethodSummary extends StatelessWidget {
  const _MethodSummary({required this.method, required this.title});

  final OrderPaymentMethod method;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.opsCardBg,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
      ),
      child: Row(
        children: [
          _MethodIcon(method: method, size: 44),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: context.textStyles.h3)),
        ],
      ),
    );
  }
}

/// The amount, set large: it is the one value staff must get right. A clear
/// button empties it in one tap, ready for typing.
class _AmountField extends StatefulWidget {
  const _AmountField({
    required this.controller,
    this.errorText,
    this.maxAmount,
    this.onChanged,
    this.onRejected,
  });

  final TextEditingController controller;
  final String? errorText;

  /// An edit above this is refused and reported to [onRejected].
  final double? maxAmount;
  final VoidCallback? onChanged;
  final ValueChanged<String>? onRejected;

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('ТӨЛӨХ ДҮН', style: context.textStyles.label),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) => TextField(
            key: const ValueKey('payment_amount_input'),
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              const PriceInputFormatter(),
              if (widget.maxAmount case final max?)
                _MaxAmountFormatter(max, (raw) => widget.onRejected?.call(raw)),
            ],
            onChanged: (_) => widget.onChanged?.call(),
            style: context.textStyles.h1.copyWith(
              fontSize: 28,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              hintText: '0',
              suffixText: '₮',
              suffixStyle: context.textStyles.h2.copyWith(color: context.opsTextSecondary),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('payment_amount_clear'),
                      tooltip: 'Арилгах',
                      onPressed: _clear,
                      icon: Icon(Icons.cancel_rounded, color: context.opsTextHint),
                    ),
              errorText: widget.errorText,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// Refuses an edit that would take the amount above [max], so more than the
/// unpaid balance can't even be typed; [onRejected] gets the refused value.
class _MaxAmountFormatter extends TextInputFormatter {
  _MaxAmountFormatter(this.max, this.onRejected);

  final double max;
  final ValueChanged<String> onRejected;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(',', '').trim();
    final value = double.tryParse(raw);
    if (value == null || value <= max) return newValue;
    onRejected(raw);
    return oldValue;
  }
}

/// Pinned action strip: a hairline on top, clear of the home indicator.
class _Footer extends StatelessWidget {
  const _Footer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.opsDivider)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: child),
      ),
    );
  }
}

/// Compact «Төлбөрийн хэлбэр» field for forms that keep their own extra
/// fields; opens the picker-mode sheet.
class PaymentMethodField extends StatelessWidget {
  const PaymentMethodField({
    super.key,
    required this.choice,
    required this.banks,
    required this.onChanged,
  });

  final PaymentChoice choice;
  final List<PaymentBank> banks;
  final ValueChanged<PaymentChoice> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final picked = await PaymentMethodSheet.pick(context, banks: banks, current: choice);
      if (picked != null) onChanged(picked);
    },
    child: InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Төлбөрийн хэлбэр',
        suffixIcon: Icon(Icons.arrow_drop_down),
      ),
      child: Row(
        children: [
          Icon(paymentChoiceIcon(choice.method), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(paymentChoiceLabel(choice), overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
  );
}
