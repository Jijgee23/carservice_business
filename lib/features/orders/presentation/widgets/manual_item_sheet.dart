import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/core/utils/price_input.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/order_item_draft.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_item_controller.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

/// Hand entry of an order line («Гараар бүртгэх») in a bottom sheet: kind,
/// name, quantity and unit price — no catalog link. The caller saves the line
/// in [onSubmit] (stage it, or post it to the order) and answers whether it
/// went in; the sheet stays open with its input on `false`. Resolves to
/// `true` once saved, null when dismissed.
///
/// Needs `orders.itemPrice`: the server refuses a line without a catalog
/// link otherwise (`ITEM_PRICE_FORBIDDEN`), so callers only offer it then.
Future<bool?> showManualItemSheet({
  OrderItemDraft? initial,
  String? initialDescription,
  required Future<bool> Function(OrderItemDraft draft) onSubmit,
}) => AppNav.sheet<bool>(
  _ManualItemSheet(
    initial: initial,
    initialDescription: initialDescription,
    onSubmit: onSubmit,
  ),
  backgroundColor: Colors.transparent,
);

class _ManualItemSheet extends StatefulWidget {
  const _ManualItemSheet({
    required this.initial,
    required this.initialDescription,
    required this.onSubmit,
  });

  final OrderItemDraft? initial;
  final String? initialDescription;
  final Future<bool> Function(OrderItemDraft draft) onSubmit;

  @override
  State<_ManualItemSheet> createState() => _ManualItemSheetState();
}

class _ManualItemSheetState extends State<_ManualItemSheet> {
  late ItemKind _kind = widget.initial?.kind ?? ItemKind.LABOR;
  late final _descCtrl = TextEditingController(
    text: widget.initial?.description ?? widget.initialDescription ?? '',
  );
  late final _qtyCtrl = TextEditingController(
    text: widget.initial?.quantity.raw ?? '1',
  );
  late final _priceCtrl = TextEditingController(
    text: widget.initial == null
        ? ''
        : formatPriceInput(widget.initial!.unitPrice.raw),
  );
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  @override
  void dispose() {
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final desc = _descCtrl.text.trim();
    final qty = ItemMoneyValidation.quantity(_qtyCtrl.text);
    final price = ItemMoneyValidation.price(_priceCtrl.text);
    final error = desc.isEmpty ? 'Нэрээ оруулна уу.' : qty.error ?? price.error;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final saved = await widget.onSubmit(
      OrderItemDraft(
        kind: _kind,
        description: desc,
        quantity: qty.value!,
        unitPrice: price.value!,
      ),
    );
    if (!mounted) return;
    if (saved) {
      AppNav.back(true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The button sits at the bottom: clear the keyboard when it's open,
    // otherwise the home indicator.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final system = MediaQuery.paddingOf(context).bottom;
    final bottom = keyboard > system ? keyboard : system;

    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXL),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.opsDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            _isEdit ? 'Мөр засах' : 'Гараар бүртгэх',
            style: context.textStyles.h3,
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final k in ItemKind.values)
                        _KindChip(
                          kind: k,
                          selected: k == _kind,
                          onTap: () => setState(() => _kind = k),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    fieldKey: const ValueKey('manual_item_description'),
                    label: 'Нэр *',
                    hint: 'Тосны шилжүүлэлт',
                    controller: _descCtrl,
                    autofocus: !_isEdit,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Field(
                          fieldKey: const ValueKey('manual_item_quantity'),
                          label: 'Тоо *',
                          hint: '1',
                          controller: _qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _Field(
                          fieldKey: const ValueKey('manual_item_price'),
                          label: 'Нэгж үнэ (₮) *',
                          hint: '0',
                          controller: _priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: const [PriceInputFormatter()],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _save(),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      key: const ValueKey('manual_item_error'),
                      style: context.textStyles.body.copyWith(
                        color: context.opsDanger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const ValueKey('manual_item_submit'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Хадгалах' : 'Нэмэх'),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final ItemKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.itemKindColor(kind);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          border: Border.all(color: selected ? color : context.opsDivider),
        ),
        child: Text(
          kind.label,
          style: context.textStyles.body.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? color : context.opsTextSecondary,
          ),
        ),
      ),
    );
  }
}

/// A caption over a themed text field (the look of `AppTextField`), with
/// autofocus and keyboard actions.
class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final Key fieldKey;
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.textStyles.captionMedium),
        const SizedBox(height: 6),
        TextField(
          key: fieldKey,
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: context.textStyles.body,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
