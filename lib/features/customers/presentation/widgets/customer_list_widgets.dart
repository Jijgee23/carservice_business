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
    final name = customer.displayName;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppDimens.paddingMD),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: context.colors.accent.withOpacity(0.12),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: context.textStyles.h3.copyWith(
                fontWeight: FontWeight.w700,
                color: context.colors.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: context.textStyles.bodyMedium),
                if (customer.isOrganization) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const OrgBadge(),
                      if (customer.orgRegnumLabel != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            customer.orgRegnumLabel!,
                            style: context.textStyles.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (customer.fullName != null)
                    Text(customer.fullName!, style: context.textStyles.caption),
                ],
                const SizedBox(height: 2),
                if (customer.phone != null)
                  Text(customer.phone!, style: context.textStyles.caption),
                if (customer.email != null)
                  Text(customer.email!, style: context.textStyles.caption),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: context.colors.textHint),
        ],
      ),
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
