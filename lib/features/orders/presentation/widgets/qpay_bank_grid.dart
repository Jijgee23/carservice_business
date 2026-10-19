import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

/// The bank apps a QPay invoice can be paid in, laid out as on the web
/// (`app/_components/qpay-bank-grid.tsx`): small logo + name tiles, four
/// across on a phone, each opening that bank's app with the invoice.
///
/// [banks] must already be filtered to safe links (`isSafeBankUrl`).
class QPayBankGrid extends StatelessWidget {
  const QPayBankGrid({super.key, required this.banks, required this.onSelect});

  final List<QPayBankUrl> banks;

  /// Null disables the tiles, e.g. while a payment action is running.
  final ValueChanged<QPayBankUrl>? onSelect;

  static const _gap = 6.0;
  static const _logoSize = 24.0;
  static const _tilePadding = EdgeInsets.symmetric(horizontal: 4, vertical: 8);
  static const _nameSize = 10.0;

  @override
  Widget build(BuildContext context) {
    if (banks.isEmpty) return const SizedBox.shrink();
    final nameStyle = context.textStyles.caption.copyWith(fontSize: _nameSize, height: 1.2);
    // Every tile fits a two-line name, so rows line up whatever the names.
    final tileHeight =
        _tilePadding.vertical +
        _logoSize +
        4 +
        MediaQuery.textScalerOf(context).scale(2 * _nameSize * 1.2) +
        // Slack for the font's own line metrics.
        4;
    return Column(
      key: const ValueKey('qpay_bank_grid'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('БАНКНЫ АПП СОНГОХ', style: context.textStyles.label),
        ),
        LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              // 4 across on a phone, more on a wide sheet.
              crossAxisCount: (constraints.maxWidth / 80).floor().clamp(4, 8),
              mainAxisSpacing: _gap,
              crossAxisSpacing: _gap,
              mainAxisExtent: tileHeight,
            ),
            itemCount: banks.length,
            itemBuilder: (context, index) {
              final bank = banks[index];
              return _BankTile(
                key: ValueKey('qpay_bank_$index'),
                bank: bank,
                nameStyle: nameStyle,
                onTap: onSelect == null ? null : () => onSelect!(bank),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BankTile extends StatelessWidget {
  const _BankTile({super.key, required this.bank, required this.nameStyle, required this.onTap});

  final QPayBankUrl bank;
  final TextStyle nameStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDimens.radiusSM);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            padding: QPayBankGrid._tilePadding,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: context.opsDivider),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _BankLogo(bank: bank),
                const SizedBox(height: 4),
                Text(
                  bank.nameMn,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: nameStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bank's logo from QPay; its initial when there is no logo or it fails
/// to load, so a network problem never leaves a blank tile.
class _BankLogo extends StatelessWidget {
  const _BankLogo({required this.bank});
  final QPayBankUrl bank;

  @override
  Widget build(BuildContext context) {
    const size = QPayBankGrid._logoSize;
    final name = bank.nameMn.trim();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: context.opsDivider, borderRadius: BorderRadius.circular(6)),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: context.textStyles.caption,
      ),
    );
    if (!bank.logo.startsWith('https://')) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        bank.logo,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
