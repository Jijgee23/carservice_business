import 'package:carservice_business/core/utils/price_input.dart';
import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/no_cash_session_warning.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

// Shared payment-method modal (mobile: full-height bottom sheet, list first,
// tapping an option pushes its detail view). Lives in the orders feature
// because it is built on the orders domain (OrderPaymentMethod, PaymentBank)
// and the cash feature already depends on orders, not the other way round.

/// A chosen method (+ receiving bank for transfer / card).
class PaymentChoice {
  final OrderPaymentMethod method;
  final String? bank;
  const PaymentChoice(this.method, [this.bank]);

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
    choice.bank == null
        ? 'Дансаар шилжүүлэх'
        : '${paymentBankLabel(choice.bank!)} · Шилжүүлэг',
  OrderPaymentMethod.CARD =>
    choice.bank == null
        ? 'Карт (POS)'
        : '${paymentBankLabel(choice.bank!)} · POS',
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
  const PaymentOption(this.choice, {this.group});

  @override
  bool operator ==(Object other) =>
      other is PaymentOption && other.choice == choice;

  @override
  int get hashCode => choice.hashCode;

  OrderPaymentMethod get method => choice.method;
  String? get bank => choice.bank;

  String get key => '${method.name}${bank == null ? '' : '_$bank'}';
  String get label =>
      bank == null ? paymentChoiceLabel(choice) : paymentBankLabel(bank!);
}

const kTransferGroup = 'Дансаар шилжүүлэх';
const kCardGroup = 'Карт (POS)';

/// Ordered option list: cash, QPay (order context only), transfer per bank,
/// card per bank, other. One enabled-bank list feeds both bank groups.
List<PaymentOption> buildPaymentOptions({
  required List<PaymentBank> banks,
  required bool includeQPay,
  bool includeManual = true,
}) => [
  if (includeManual)
    const PaymentOption(PaymentChoice(OrderPaymentMethod.CASH)),
  if (includeQPay) const PaymentOption(PaymentChoice(OrderPaymentMethod.QPAY)),
  if (includeManual) ...[
    for (final b in banks)
      PaymentOption(
        PaymentChoice(OrderPaymentMethod.BANK_TRANSFER, b.code),
        group: kTransferGroup,
      ),
    for (final b in banks)
      PaymentOption(
        PaymentChoice(OrderPaymentMethod.CARD, b.code),
        group: kCardGroup,
      ),
    const PaymentOption(PaymentChoice(OrderPaymentMethod.OTHER)),
  ],
];

/// Records one payment; true on success (the sheet then closes).
typedef PaymentRecorder = Future<bool> Function(
  PaymentChoice choice,
  String amount,
);

/// Simulated POS terminal. One component so a real POS integration can
/// replace its internals later: it only reports success or cancel.
class PosSimulator extends StatelessWidget {
  const PosSimulator({
    super.key,
    required this.bankLabel,
    required this.amount,
    required this.onSuccess,
    required this.onCancel,
    this.busy = false,
  });

  final String bankLabel;
  final String amount;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final bool busy;

  /// Dialog variant for forms that submit later. Resolves true on
  /// «Амжилттай», false/null on «Цуцлах».
  static Future<bool> confirm(
    BuildContext context, {
    required String bankLabel,
    required String amount,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.paddingMD),
          child: PosSimulator(
            bankLabel: bankLabel,
            amount: amount,
            onSuccess: () => Navigator.of(ctx).pop(true),
            onCancel: () => Navigator.of(ctx).pop(false),
          ),
        ),
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('pos_simulator'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: context.opsWarning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Туршилтын POS',
              style: TextStyle(
                color: context.opsWarning,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          ),
          child: Column(
            children: [
              const Icon(Icons.contactless_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                '$bankLabel POS · $amount₮ · Картаа уншуулна уу',
                key: const ValueKey('pos_prompt'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('pos_success'),
          onPressed: busy ? null : onSuccess,
          child: const Text('Амжилттай'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('pos_cancel'),
          onPressed: busy ? null : onCancel,
          child: const Text('Цуцлах'),
        ),
      ],
    );
  }
}

/// The payment modal. Two modes:
/// * record mode ([onRecord] set): detail panels carry amount + submit;
/// * picker mode ([onRecord] null): list + «Сонгох», pops a [PaymentChoice].
class PaymentMethodSheet extends StatefulWidget {
  const PaymentMethodSheet({
    super.key,
    required this.banks,
    required this.title,
    this.onRecord,
    this.initial,
    this.includeQPay = false,
    this.includeManual = true,
    this.defaultAmount = '',
    this.qpayBuilder,
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
  final PaymentRecorder? onRecord;
  final PaymentChoice? initial;
  final bool includeQPay;
  final bool includeManual;
  final String defaultAmount;

  /// QPay detail content (create / QR / check / cancel); order context only.
  final WidgetBuilder? qpayBuilder;

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
  }) => showModalBottomSheet<PaymentChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => PaymentMethodSheet(
      banks: banks,
      title: title,
      initial: current,
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
  List<PaymentOption> get _options => buildPaymentOptions(
    banks: widget.liveBanks?.call() ?? widget.banks,
    includeQPay: widget.includeQPay,
    includeManual: widget.includeManual,
  );
  PaymentOption? _selected;
  bool _detailOpen = false;
  bool _posActive = false;
  bool _closing = false;

  bool get _pickerMode => widget.onRecord == null;

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
    setState(() {
      _selected = option;
      _posActive = false;
      // Picker mode confirms from the list; record mode opens the detail.
      _detailOpen = !_pickerMode;
    });
  }

  void _back() => setState(() {
    _detailOpen = false;
    _posActive = false;
  });

  Future<void> _record(PaymentOption option) async {
    final ok = await widget.onRecord!(
      option.choice,
      _amount.text.replaceAll(',', ''),
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.listenable == null
        ? _content(context)
        : ListenableBuilder(
            listenable: widget.listenable!,
            builder: (context, _) => _content(context),
          );
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.92,
      child: body,
    );
  }

  Widget _content(BuildContext context) {
    if (!_closing && (widget.isSettled?.call() ?? false)) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    final inDetail = _detailOpen && !_pickerMode && _selected != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, inDetail),
          const Divider(height: 1),
          Expanded(
            child: inDetail ? _detail(context, _selected!) : _list(context),
          ),
          if (_pickerMode && !inDetail) _pickerFooter(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool inDetail) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
    child: Row(
      children: [
        if (inDetail)
          IconButton(
            key: const ValueKey('pay_sheet_back'),
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_rounded),
          )
        else
          const SizedBox(width: 12),
        Expanded(
          child: Text(
            widget.title,
            key: const ValueKey('pay_sheet_title'),
            style: context.textStyles.h3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          key: const ValueKey('pay_sheet_close'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );

  Widget _list(BuildContext context) {
    final rows = <Widget>[];
    String? lastGroup;
    for (final option in _options) {
      if (option.group != null && option.group != lastGroup) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              option.group!,
              key: ValueKey('pay_group_${option.group}'),
              style: context.textStyles.caption,
            ),
          ),
        );
      }
      lastGroup = option.group;
      rows.add(_row(context, option));
    }
    if (widget.includeManual) {
      final loading = widget.banksLoading?.call() ?? false;
      final failed = widget.banksFailed?.call() ?? false;
      if (loading || failed) {
        final status = loading
            ? const Padding(
                key: ValueKey('pay_banks_loading'),
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : ListTile(
                key: const ValueKey('pay_banks_error'),
                title: const Text('Банкны жагсаалт ачаалж чадсангүй'),
                trailing: TextButton(
                  key: const ValueKey('pay_banks_retry'),
                  onPressed: widget.onRetryBanks,
                  child: const Text('Дахин оролдох'),
                ),
              );
        // Placed before «Бусад» so it sits with the bank groups.
        final otherAt = rows.length - 1;
        rows.insert(otherAt < 0 ? 0 : otherAt, status);
      }
    }
    return ListView(children: rows);
  }

  Widget _row(BuildContext context, PaymentOption option) {
    final selected = _selected == option;
    final isCard = option.method == OrderPaymentMethod.CARD;
    return ListTile(
      key: ValueKey('pay_opt_${option.key}'),
      selected: selected,
      leading: (option.group == kTransferGroup)
          ? null
          : Icon(paymentChoiceIcon(option.method), size: 22),
      title: Text(
        option.label,
        style: isCard ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ),
      trailing: isCard
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('POS', style: TextStyle(fontSize: 10)),
            )
          : (_pickerMode && selected
                ? const Icon(Icons.check_rounded)
                : (_pickerMode ? null : const Icon(Icons.chevron_right))),
      onTap: () => _select(option),
    );
  }

  Widget _pickerFooter(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: FilledButton(
      key: const ValueKey('pay_pick_confirm'),
      onPressed: _selected == null
          ? null
          : () => Navigator.of(context).pop(_selected!.choice),
      child: const Text('Сонгох'),
    ),
  );

  Widget _detail(BuildContext context, PaymentOption option) {
    final busy = widget.busy?.call() ?? false;
    final error = widget.errorText?.call();
    final children = <Widget>[
      Text(
        option.method == OrderPaymentMethod.BANK_TRANSFER ||
                option.method == OrderPaymentMethod.CARD
            ? paymentChoiceLabel(option.choice)
            : option.label,
        style: context.textStyles.h3,
      ),
      const SizedBox(height: 12),
    ];

    final blocked = widget.showNoSessionWarning?.call(option.method) ?? false;
    if (option.method == OrderPaymentMethod.QPAY) {
      // Amount field + validation live in the QPay panel itself; its create
      // button is disabled by the controller while the register is closed.
      if (blocked) children.add(const NoCashSessionWarning());
      final qpay = widget.qpayBuilder;
      if (qpay != null) children.add(qpay(context));
    } else if (_posActive) {
      children.add(
        PosSimulator(
          bankLabel: paymentBankLabel(option.bank ?? ''),
          amount: _amount.text,
          busy: busy,
          onSuccess: () => _record(option),
          onCancel: () => setState(() => _posActive = false),
        ),
      );
    } else {
      children.add(
        TextField(
          key: const ValueKey('payment_amount_input'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [PriceInputFormatter()],
          decoration: const InputDecoration(labelText: 'Дүн', suffixText: '₮'),
        ),
      );
      if (blocked) children.add(const NoCashSessionWarning());
      children.add(const SizedBox(height: 16));
      if (option.method == OrderPaymentMethod.CARD) {
        children.add(
          FilledButton.icon(
            key: const ValueKey('pos_start'),
            onPressed: busy || blocked
                ? null
                : () => setState(() => _posActive = true),
            icon: const Icon(Icons.credit_card_rounded),
            label: const Text('POS-оор төлөх'),
          ),
        );
      } else {
        children.add(
          FilledButton.icon(
            key: const ValueKey('create_manual_payment'),
            onPressed: busy || blocked ? null : () => _record(option),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Бүртгэх'),
          ),
        );
      }
    }
    if (error != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            error,
            key: const ValueKey('pay_sheet_error'),
            style: TextStyle(color: context.opsDanger),
          ),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.all(16), children: children);
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
      final picked = await PaymentMethodSheet.pick(
        context,
        banks: banks,
        current: choice,
      );
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
          Expanded(
            child: Text(
              paymentChoiceLabel(choice),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}
