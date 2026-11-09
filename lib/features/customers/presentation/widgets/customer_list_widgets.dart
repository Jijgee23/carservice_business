import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/org_badge.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';

/// List row + load-more footer for the Customers list — P3-F2. Mirrors
/// `appointment_list_widgets.dart`'s shape, minus selection (the customer
/// list has none).

class CustomerCard extends StatelessWidget {
  const CustomerCard({super.key, required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    // A walk-in known only by phone: the phone is already the title.
    final phoneOnly =
        !c.isOrganization && c.fullName == null && c.phone != null;
    final meta = <Widget>[
      if (c.orgRegnumLabel != null)
        _Meta(icon: Icons.badge_outlined, text: c.orgRegnumLabel!),
      if (c.isOrganization && c.orgName != null && c.fullName != null)
        _Meta(icon: Icons.person_outline, text: c.fullName!),
      if (c.phone != null && !phoneOnly)
        _Meta(icon: Icons.call_outlined, text: c.phone!),
      if (c.email != null) _Meta(icon: Icons.mail_outline, text: c.email!),
      if (phoneOnly)
        const _Meta(
          icon: Icons.person_outline,
          text: 'Нэр бүртгэгдээгүй',
          muted: true,
        ),
    ];
    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        side: BorderSide(color: context.colors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              _CustomerAvatar(customer: c),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (c.isOrganization) ...[
                          const SizedBox(width: 6),
                          const OrgBadge(),
                        ],
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, children: meta),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.colors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Initials in a circle for a person; a building in a rounded square for an
/// organization, or for a person with no name to take initials from.
class _CustomerAvatar extends StatelessWidget {
  const _CustomerAvatar({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.accent;
    final org = customer.isOrganization;
    final initials = org ? '' : _initials(customer.fullName);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: org ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: org ? BorderRadius.circular(AppDimens.radiusMD) : null,
      ),
      child: initials.isEmpty
          ? Icon(
              org ? Icons.apartment_rounded : Icons.person_outline_rounded,
              size: 22,
              color: color,
            )
          : Text(
              initials,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
    );
  }

  /// First letters of the first two words: «Батбаяр Дорж» → «БД».
  static String _initials(String? name) => (name ?? '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w.characters.first.toUpperCase())
      .join();
}

/// One icon + text fact on a card, as on the Orders list rows.
class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? context.colors.textHint
        : context.colors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.caption.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class CustomerListFooter extends StatelessWidget {
  const CustomerListFooter({
    super.key,
    required this.loadingMore,
    required this.loadMoreError,
    required this.hasNext,
    required this.total,
    required this.onLoadMore,
  });

  final bool loadingMore;
  final String? loadMoreError;
  final bool hasNext;
  final int total;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppDimens.paddingLG),
        child: AppLoading(size: 24),
      );
    }
    if (loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        child: TextButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.refresh),
          label: Text('Дахин оролдох: $loadMoreError'),
        ),
      );
    }
    if (hasNext) {
      return Padding(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        child: TextButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('Дараагийн хуудас'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppDimens.paddingLG),
      child: Center(
        child: Text(
          'Нийт $total үйлчлүүлэгч',
          style: context.textStyles.caption,
        ),
      ),
    );
  }
}
