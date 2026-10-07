import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/cash/domain/cash_session.dart';

/// Reason shown next to a disabled money action while the branch has no open
/// register session.
class NoCashSessionWarning extends StatelessWidget {
  const NoCashSessionWarning({super.key});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('no_cash_session_warning'),
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: context.colors.warningBg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: context.colors.warning,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            kNoCashSessionWarning,
            style: TextStyle(color: context.colors.warning, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
