import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/services/domain/service.dart';
import 'package:carservice_business/features/services/presentation/controllers/service_detail_controller.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Stock-adjust sheet — P4-F3.
///
/// `GOODS`-only ([Service.isStockAdjustable]) and directional
/// ([StockDirection.incoming]/[StockDirection.outgoing] + a positive
/// `amount`), matching `POST /services/[id]/stock`'s contract exactly — this
/// sheet never computes or sends an absolute target stock. A resulting
/// negative balance is the server's call, not this client's: it comes back
/// as a `422` on the `amount` field (`ServicesRepository.adjustStock`'s doc
/// comment), and [_AdjustFieldError] renders it as the amount field's
/// `errorText`, never a generic toast.
class StockAdjustSheet extends StatefulWidget {
  const StockAdjustSheet({
    super.key,
    required this.service,
    required this.controller,
  });

  final Service service;
  final ServiceDetailController controller;

  /// Returns `true` when the adjustment succeeded. Guards the `GOODS`-only
  /// rule itself (defense in depth — the detail screen already hides/disables
  /// the entry point for a non-`GOODS` service, per D-163's "gate the
  /// surface" lesson applied to this smaller surface too).
  static Future<bool> show(
    BuildContext context, {
    required Service service,
    required ServiceDetailController controller,
  }) async {
    if (!service.isStockAdjustable) return false;
    final result = await AppNav.sheet<bool>(
      StockAdjustSheet(service: service, controller: controller),
      backgroundColor: Colors.transparent,
    );
    return result ?? false;
  }

  @override
  State<StockAdjustSheet> createState() => _StockAdjustSheetState();
}

class _StockAdjustSheetState extends State<StockAdjustSheet> {
  StockDirection _direction = StockDirection.incoming;
  final _amountCtrl = TextEditingController();

  bool _saving = false;
  String? _amountError;
  String? _generalError;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = _amountCtrl.text.trim();
    setState(() {
      _saving = true;
      _amountError = null;
      _generalError = null;
    });
    final result = await widget.controller.adjustStock(
      direction: _direction,
      amount: amount,
    );
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        AppNav.back(true);
        // Resulting balance, never an echo of the requested delta — see
        // `ServiceStockResult`'s doc comment.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Үлдэгдэл: ${value.stock ?? '—'}')),
        );
      case Err(:final error):
        setState(() {
          _saving = false;
          _amountError = error.fieldErrors?['amount'];
          _generalError =
              (error.fieldErrors == null || error.fieldErrors!.isEmpty)
              ? error.display
              : null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXL)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Үлдэгдэл тохируулах', style: context.textStyles.h3),
                    const SizedBox(height: 4),
                    Text(
                      widget.service.displayName,
                      style: context.textStyles.caption,
                    ),
                    const SizedBox(height: 16),
                    if (_generalError != null) ...[
                      Text(
                        _generalError!,
                        style: TextStyle(color: context.colors.danger),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _DirectionButton(
                            key: const ValueKey('stock_direction_in'),
                            label: 'Орлого',
                            icon: Icons.arrow_downward_rounded,
                            selected: _direction == StockDirection.incoming,
                            color: context.colors.good,
                            onTap: () => setState(
                              () => _direction = StockDirection.incoming,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DirectionButton(
                            key: const ValueKey('stock_direction_out'),
                            label: 'Зарлага',
                            icon: Icons.arrow_upward_rounded,
                            selected: _direction == StockDirection.outgoing,
                            color: context.colors.danger,
                            onTap: () => setState(
                              () => _direction = StockDirection.outgoing,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('stock_amount_field'),
                      controller: _amountCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      // Re-evaluates the submit button's enabled state on every
                      // keystroke — without this, `build()`'s
                      // `_amountCtrl.text.trim().isEmpty` check is only
                      // recomputed on the next unrelated rebuild (e.g. toggling
                      // direction), so typing an amount alone would never enable
                      // the button.
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Хэмжээ',
                        errorText: _amountError,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => AppNav.back(false),
                    child: const Text('Болих'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('stock_adjust_submit'),
                    onPressed: _saving || _amountCtrl.text.trim().isEmpty
                        ? null
                        : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Тохируулах'),
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

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : context.colors.background,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(
            color: selected ? color : context.colors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? color : context.colors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? color : context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
