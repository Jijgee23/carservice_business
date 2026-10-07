import 'package:carservice_business/core/utils/price_input.dart';
import 'package:carservice_business/app/shell/shell_chrome.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';
import 'package:carservice_business/features/orders/domain/postpaid_settlement.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_payment_controller.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/payment_method_sheet.dart';

class OrderPaymentScreen extends StatefulWidget {
  final String orderId;
  final User? user;

  const OrderPaymentScreen({super.key, required this.orderId, this.user});

  @override
  State<OrderPaymentScreen> createState() => _OrderPaymentScreenState();
}

class _OrderPaymentScreenState extends State<OrderPaymentScreen>
    with WidgetsBindingObserver {
  bool _openedBankApp = false;
  String? _shownError;

  OrderPaymentController get _controller =>
      context.read<OrderPaymentController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedBankApp) {
      _openedBankApp = false;
      if (mounted) _controller.checkQPay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OrderPaymentController>(
      builder: (context, controller, _) {
        final error = controller.lastError;
        if (error == null) _shownError = null;
        if (error != null && error.display != _shownError) {
          _shownError = error.display;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.display)));
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Төлбөр'),
            actions: const [ShellNotificationBell()],
          ),
          body: !controller.canView
              ? const _ForbiddenPaymentView()
              : _buildBody(context, controller),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, OrderPaymentController controller) {
    final detail = controller.order;
    if (detail == null && controller.isLoading) {
      return const AppLoading();
    }
    if (detail == null) {
      return ErrorStateView(
        onRetry: controller.load,
        message: 'Төлбөрийн мэдээлэл ачаалж чадсангүй.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => controller.refresh(),
      child: ListView(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        children: [
          _SummaryCard(detail: detail),
          if (controller.qpayCheckError case final error?)
            _QPayFeedbackBanner(
              text: 'QPay шалгалтын алдаа: ${error.message}',
              color: context.opsDanger,
              key: const ValueKey('qpay_check_error'),
            )
          else if (controller.qpayCheckResult case final result?)
            _QPayFeedbackBanner(
              text: result.paid
                  ? 'QPay төлбөр амжилттай баталгаажлаа.'
                  : (result.message ?? 'QPay төлбөр төлөгдөөгүй байна.'),
              color: result.paid ? context.opsGood : context.opsWarning,
              key: const ValueKey('qpay_check_feedback'),
            ),
          const SizedBox(height: 12),
          _LedgerCard(controller: controller),
          if (controller.internalLocked) ...[
            const SizedBox(height: 12),
            Padding(
              key: const ValueKey('internal_payment_note'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.paddingSM,
              ),
              child: Text(
                internalOrderPaymentNote,
                style: context.textStyles.caption,
              ),
            ),
          ] else if (controller.settlementLocked &&
              (controller.can('payments.create') ||
                  controller.can('payments.edit') ||
                  controller.can('payments.delete'))) ...[
            const SizedBox(height: 12),
            Padding(
              key: const ValueKey('postpaid_settlement_note'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.paddingSM,
              ),
              child: Text(
                postpaidSettlementNote,
                style: context.textStyles.caption,
              ),
            ),
          ],
          if (detail.paymentStatus != PaymentStatus.PAID &&
              (controller.canCreate ||
                  (!controller.internalLocked &&
                      controller.qpay?.qpayEnabled == true))) ...[
            const SizedBox(height: 12),
            _ManualPaymentCard(
              controller: controller,
              remaining: _remainingRaw(detail),
              onBankLaunch: _launchBank,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _launchBank(String link) async {
    if (!isSafeBankUrl(link)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Банкны холбоос буруу байна.')),
        );
      }
      return;
    }
    final uri = Uri.parse(link);
    if (!await canLaunchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Банкны апп нээх боломжгүй байна.')),
        );
      }
      return;
    }
    _openedBankApp = true;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ForbiddenPaymentView extends StatelessWidget {
  const _ForbiddenPaymentView();
  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.lock_outline_rounded,
    message: 'Төлбөрийн мэдээлэл харах эрхгүй байна.',
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.detail});
  final ServiceOrderDetail detail;
  @override
  Widget build(BuildContext context) {
    final total = detail.totalAmountMoney ?? _fallbackMoney(detail.totalAmount);
    final paid = detail.paidAmountMoney ?? _fallbackMoney(detail.paidAmount);
    final remaining =
        detail.paymentTotals?.remainingAmountMoney ??
        (total == null || paid == null
            ? null
            : Money(_subtractDisplayMoney(total.raw, paid.raw)));
    return _PaymentCard(
      title: 'Төлбөрийн мэдээлэл',
      icon: Icons.payments_outlined,
      children: [
        _PaymentRow(label: 'Нийт дүн', value: _displayMoney(total)),
        _PaymentRow(label: 'Төлсөн дүн', value: _displayMoney(paid)),
        if (remaining != null)
          _PaymentRow(
            label: 'Үлдэгдэл',
            value: remaining.raw == '0'
                ? '✓ ${_displayMoney(remaining)}'
                : _displayMoney(remaining),
            color: remaining.raw == '0' ? context.opsGood : context.opsWarning,
            bold: true,
            emphasized: true,
          ),
        _PaymentRow(
          label: 'Төлөв',
          value: detail.paymentStatus.label,
          color: context.paymentStatusColor(detail.paymentStatus),
          bold: true,
        ),
      ],
    );
  }
}

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({required this.controller});
  final OrderPaymentController controller;
  @override
  Widget build(BuildContext context) {
    final state = controller.paymentsState;
    final payments = state.valueOrNull;
    return _PaymentCard(
      title: 'Төлбөрийн түүх',
      icon: Icons.receipt_long_outlined,
      children: [
        if (state is AsyncLoading && payments == null)
          const Padding(
            padding: EdgeInsets.all(AppDimens.paddingMD),
            child: AppLoading(),
          )
        else if (payments == null || payments.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppDimens.paddingMD,
              AppDimens.paddingXS,
              AppDimens.paddingMD,
              AppDimens.paddingMD,
            ),
            child: Text('Төлбөрийн бүртгэл алга.'),
          )
        else
          ...payments.map(
            (payment) => _LedgerRow(
              payment: payment,
              canReverse: controller.canDelete,
              reverseBlockedReason: controller.reverseBlockedReason(payment),
              busy: controller.isBusy,
              onReverse: () => controller.reverse(payment),
            ),
          ),
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.payment,
    required this.canReverse,
    required this.reverseBlockedReason,
    required this.busy,
    required this.onReverse,
  });
  final OrderPaymentRecord payment;
  final bool canReverse;

  /// Non-null disables reverse and is shown as its tooltip.
  final String? reverseBlockedReason;
  final bool busy;
  final VoidCallback onReverse;
  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy-MM-dd HH:mm')
        .format(payment.paidAt ?? payment.createdAt);
    final bank = payment.bank;
    final method = bank == null
        ? _methodLabel(payment.method)
        : '${_methodLabel(payment.method)} · ${paymentBankLabel(bank)}';
    final showReverse =
        payment.status == OrderPaymentRecordStatus.PAID && canReverse;
    return ListTile(
      dense: true,
      title: Text('${_displayMoney(payment.amountMoney)} · $method'),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$date · ${_recordStatusLabel(payment.status)}'),
            if (payment.isSettlement)
              const TextSpan(
                text: ' · Нэгдсэн тооцоо',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
          ],
        ),
        key: ValueKey('ledger_subtitle_${payment.id}'),
      ),
      trailing: showReverse
          ? IconButton(
              key: ValueKey('reverse_payment_${payment.id}'),
              tooltip: reverseBlockedReason ?? 'Буцаах',
              onPressed: busy || reverseBlockedReason != null
                  ? null
                  : onReverse,
              icon: const Icon(Icons.undo_rounded),
            )
          : null,
    );
  }
}

class _ManualPaymentCard extends StatelessWidget {
  const _ManualPaymentCard({
    required this.controller,
    required this.remaining,
    required this.onBankLaunch,
  });
  final OrderPaymentController controller;
  final String remaining;
  final Future<void> Function(String) onBankLaunch;

  Future<void> _open(BuildContext context) => PaymentMethodSheet.showRecord(
    context,
    builder: () => PaymentMethodSheet(
      title: remaining.isEmpty
          ? 'Төлбөр бүртгэх'
          : 'Төлбөр бүртгэх · Үлдэгдэл $remaining₮',
      banks: controller.enabledBanks,
      liveBanks: () => controller.enabledBanks,
      banksLoading: () => controller.banksLoading,
      banksFailed: () => controller.banksFailed,
      onRetryBanks: controller.retryBanks,
      defaultAmount: remaining,
      // The row shows even when QPay is not configured; the panel then
      // explains it instead of offering a QR button.
      includeQPay: !controller.internalLocked,
      includeManual: controller.canCreate,
      listenable: controller,
      isSettled: () => controller.order?.paymentStatus == PaymentStatus.PAID,
      busy: () => controller.isBusy,
      errorText: () => controller.lastError?.display,
      showNoSessionWarning: controller.showNoSessionWarning,
      onRecord: (choice, amount) => controller.createManual(
        amount: amount,
        method: choice.method,
        bank: choice.bank,
      ),
      qpayBuilder: (_) => _QPayPanel(
        controller: controller,
        onBankLaunch: onBankLaunch,
        remaining: remaining,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => _PaymentCard(
    title: 'Төлбөр бүртгэх',
    icon: Icons.add_card_outlined,
    children: [
      Padding(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('open_payment_sheet'),
            onPressed: () => _open(context),
            icon: const Icon(Icons.add_card_outlined),
            label: const Text('Төлбөр бүртгэх'),
          ),
        ),
      ),
    ],
  );
}

/// QPay detail of the payment sheet: create, QR + bank links, check, cancel.
class _QPayPanel extends StatefulWidget {
  const _QPayPanel({
    required this.controller,
    required this.onBankLaunch,
    required this.remaining,
  });
  final OrderPaymentController controller;
  final Future<void> Function(String) onBankLaunch;

  /// Raw remaining balance; default and upper bound of the QPay amount.
  final String remaining;

  @override
  State<_QPayPanel> createState() => _QPayPanelState();
}

class _QPayPanelState extends State<_QPayPanel> {
  late final TextEditingController _amount = TextEditingController(
    text: liveFormatPriceInput(widget.remaining),
  );
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Error text for the typed amount, or null when valid (> 0, <= remaining).
  String? _validate() => validateQPayAmount(_amount.text, widget.remaining);

  void _create() {
    final error = _validate();
    setState(() => _amountError = error);
    if (error != null) return;
    widget.controller.createQPay(
      amount: _amount.text.replaceAll(',', '').trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final onBankLaunch = widget.onBankLaunch;
    if (controller.qpayState is AsyncLoading) {
      return const Padding(
        key: ValueKey('qpay_loading'),
        padding: EdgeInsets.all(AppDimens.paddingMD),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (controller.qpayState is AsyncError) {
      return Padding(
        key: const ValueKey('qpay_load_failed'),
        padding: const EdgeInsets.only(top: AppDimens.paddingXS),
        child: Row(
          children: [
            const Expanded(child: Text(qpayLoadFailedMessage)),
            TextButton(
              key: const ValueKey('qpay_retry'),
              onPressed: controller.retryQPay,
              child: const Text('Дахин оролдох'),
            ),
          ],
        ),
      );
    }
    if (controller.qpay?.qpayEnabled != true) {
      return const Padding(
        key: ValueKey('qpay_not_configured'),
        padding: EdgeInsets.only(top: AppDimens.paddingXS),
        child: Text(qpayNotConfiguredMessage),
      );
    }
    final pending = controller.qpay?.pending;
    final result = controller.qpayCheckResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.qpayCheckError case final error?)
          _QPayFeedbackBanner(
            text: 'QPay шалгалтын алдаа: ${error.message}',
            color: context.opsDanger,
            key: const ValueKey('qpay_sheet_error'),
          )
        else if (result != null && !result.paid)
          _QPayFeedbackBanner(
            text: result.message ?? 'QPay төлбөр төлөгдөөгүй байна.',
            color: context.opsWarning,
            key: const ValueKey('qpay_sheet_feedback'),
          ),
        if (pending == null && controller.canCreate)
          Padding(
            padding: const EdgeInsets.only(top: AppDimens.paddingXS),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('qpay_amount_input'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [PriceInputFormatter()],
                  onChanged: (_) {
                    if (_amountError != null) {
                      setState(() => _amountError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Дүн',
                    suffixText: '₮',
                    errorText: _amountError,
                  ),
                ),
                const SizedBox(height: AppDimens.paddingSM),
                FilledButton(
                  key: const ValueKey('create_qpay'),
                  onPressed: controller.isBusy || controller.cashSessionClosed
                      ? null
                      : _create,
                  child: const Text('QR үүсгэх'),
                ),
              ],
            ),
          )
        else if (pending == null)
          const Padding(
            padding: EdgeInsets.only(top: AppDimens.paddingXS),
            child: Text('QPay нэхэмжлэл үүсгэх эрхгүй байна.'),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.paddingXS),
            child: Text(
              'Нэхэмжлэл хүлээгдэж байна · ${_displayMoney(pending.amountMoney)}',
            ),
          ),
          if (decodeQrImage(pending.qrImage) case final bytes?)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Container(
                  // QR codes need a guaranteed-white backing to stay
                  // scannable, independent of the active theme.
                  color: Colors.white,
                  padding: const EdgeInsets.all(AppDimens.paddingSM),
                  child: Image.memory(
                    bytes,
                    width: 180,
                    height: 180,
                    errorBuilder: (_, _, _) => const _QrFallback(),
                  ),
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(AppDimens.paddingMD),
              child: Center(child: _QrFallback()),
            ),
          if (pending.urls.any((item) => isSafeBankUrl(item.link)))
            Padding(
              padding: const EdgeInsets.only(bottom: AppDimens.paddingSM),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final bank in pending.urls)
                    if (isSafeBankUrl(bank.link))
                      OutlinedButton(
                        onPressed: controller.isBusy
                            ? null
                            : () => onBankLaunch(bank.link),
                        child: Text(bank.nameMn),
                      ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('check_qpay'),
                  onPressed: controller.canEdit && !controller.isBusy
                      ? controller.checkQPay
                      : null,
                  child: const Text('Төлбөр шалгах'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('cancel_qpay'),
                onPressed: controller.canDelete && !controller.isBusy
                    ? controller.cancelQPay
                    : null,
                child: const Text('Цуцлах'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

const qpayNotConfiguredMessage =
    'QPay тохируулаагүй байна. QPay-ээр төлбөр авахын тулд тохиргоог хийнэ үү.';
const qpayLoadFailedMessage = 'QPay-ийн мэдээлэл ачаалж чадсангүй.';
const qpayAmountRequiredMessage = 'Дүнгээ оруулна уу.';
const qpayAmountExceedsMessage = 'Дүн үлдэгдлээс их байж болохгүй.';

/// Validates a typed QPay amount: must be > 0 and not above [remaining]
/// (raw decimal string; empty remaining = no upper bound). Null when valid.
String? validateQPayAmount(String input, String remaining) {
  final value = double.tryParse(input.trim().replaceAll(',', ''));
  if (value == null || value <= 0) return qpayAmountRequiredMessage;
  final max = double.tryParse(remaining.trim());
  if (max != null && value > max) return qpayAmountExceedsMessage;
  return null;
}

class _QPayFeedbackBanner extends StatelessWidget {
  const _QPayFeedbackBanner({
    super.key,
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class _QrFallback extends StatelessWidget {
  const _QrFallback();
  @override
  Widget build(BuildContext context) => Text(
    'QR зураг боломжгүй байна. Банкны аппын холбоос ашиглана уу.',
    textAlign: TextAlign.center,
    style: context.textStyles.caption,
  );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: context.opsAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.h3,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...children,
      ],
    ),
  );
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
    this.emphasized = false,
  });
  final String label;
  final String value;
  final Color? color;
  final bool bold;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: Row(
      children: [
        Text(label, style: context.textStyles.caption),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: color ?? context.opsTextPrimary,
            fontSize: emphasized ? 17 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// Outstanding amount as a raw string (default for the payment sheet).
String _remainingRaw(ServiceOrderDetail detail) {
  final total = detail.totalAmountMoney ?? _fallbackMoney(detail.totalAmount);
  final paid = detail.paidAmountMoney ?? _fallbackMoney(detail.paidAmount);
  final remaining =
      detail.paymentTotals?.remainingAmountMoney ??
      (total == null || paid == null
          ? null
          : Money(_subtractDisplayMoney(total.raw, paid.raw)));
  if (remaining != null) return remaining.raw;
  final balance = detail.unpaidBalance;
  if (balance == null) return '';
  return balance == balance.roundToDouble()
      ? balance.toInt().toString()
      : balance.toString();
}

String _displayMoney(Money? money) => money == null ? '—' : '${money.raw}₮';
Money? _fallbackMoney(double? value) =>
    value == null ? null : Money(value.toString());

String _methodLabel(OrderPaymentMethod method) => switch (method) {
  OrderPaymentMethod.CASH => 'Бэлэн',
  OrderPaymentMethod.CARD => 'Карт',
  OrderPaymentMethod.OTHER => 'Бусад',
  OrderPaymentMethod.QPAY => 'QPay',
  OrderPaymentMethod.BANK_TRANSFER => 'Шилжүүлэг',
};

String _recordStatusLabel(OrderPaymentRecordStatus status) => switch (status) {
  OrderPaymentRecordStatus.PENDING => 'Хүлээгдэж байна',
  OrderPaymentRecordStatus.PAID => 'Төлөгдсөн',
  OrderPaymentRecordStatus.CANCELLED => 'Буцаасан',
  OrderPaymentRecordStatus.FAILED => 'Амжилтгүй',
};

/// Decodes both a data URI and a plain base64 QR value defensively.
Uint8List? decodeQrImage(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final comma = value.indexOf(',');
  final encoded = value.toLowerCase().startsWith('data:')
      ? (comma < 0 ? null : value.substring(comma + 1))
      : value;
  if (encoded == null || encoded.isEmpty) return null;
  try {
    final bytes = base64.decode(encoded);
    return bytes.isEmpty ? null : Uint8List.fromList(bytes);
  } on FormatException {
    return null;
  }
}

bool isSafeBankUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  final scheme = uri?.scheme.toLowerCase() ?? '';
  if (uri == null || scheme.isEmpty) {
    return false;
  }
  if (scheme == 'https') return uri.host.isNotEmpty;
  return const {
    'khanbank',
    'golomtbank',
    'tdbbank',
    'statebank',
    'monpay',
    'socialpay',
    'bogdbank',
    'mostmoney',
    'qpay',
  }.contains(scheme);
}

String _subtractDisplayMoney(String left, String right) {
  final a = _parts(left);
  final b = _parts(right);
  final scale = a.$2.length > b.$2.length ? a.$2.length : b.$2.length;
  final av =
      BigInt.parse(a.$1) * BigInt.from(10).pow(scale) +
      _fractionPart(a.$2, scale);
  final bv =
      BigInt.parse(b.$1) * BigInt.from(10).pow(scale) +
      _fractionPart(b.$2, scale);
  final value = av - bv;
  if (value <= BigInt.zero) return '0';
  final raw = value.toString().padLeft(scale + 1, '0');
  if (scale == 0) return raw;
  return '${raw.substring(0, raw.length - scale)}.${raw.substring(raw.length - scale)}';
}

(String, String) _parts(String value) {
  final split = value.split('.');
  return (split.first, split.length == 1 ? '' : split.last);
}

// scale == 0 үед бутархай хоосон — BigInt.parse('') шиддэг.
BigInt _fractionPart(String digits, int scale) {
  final padded = digits.padRight(scale, '0');
  return padded.isEmpty ? BigInt.zero : BigInt.parse(padded);
}
