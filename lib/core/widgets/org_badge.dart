import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';

/// Small "Байгууллага" pill shown on organization customers and on vehicles
/// owned by an organization (Phase 4).
class OrgBadge extends StatelessWidget {
  const OrgBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.colors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      ),
      child: Text(
        'Байгууллага',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
