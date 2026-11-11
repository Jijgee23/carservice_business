import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/features/cash/domain/cash_session.dart';
import 'package:carservice_business/features/cash/domain/cash_shift_repository.dart';
import 'package:carservice_business/features/cash/presentation/widgets/open_cash_shift_sheet.dart';

/// Reason shown next to a disabled money action while the branch has no open
/// register session.
///
/// With [branchId] and a user holding `cash.manage` (owner always) it also
/// offers «Ээлж нээх»: the open-shift sheet for that branch, then
/// [onOpened] so the caller re-reads the open flag.
class NoCashSessionWarning extends StatelessWidget {
  const NoCashSessionWarning({
    super.key,
    this.branchId,
    this.onOpened,
    this.user,
    this.repository,
  });

  final String? branchId;
  final Future<void> Function()? onOpened;

  /// Defaults to the signed-in user.
  final User? user;
  final CashShiftRepository? repository;

  bool get _canOpen {
    if (branchId == null || branchId!.isEmpty) return false;
    User? current = user;
    if (current == null) {
      try {
        current = Authenticator.user;
      } catch (_) {
        // Hive not open (tests, pre-auth): no affordance.
        return false;
      }
    }
    return canSeeView(current, 'cash.manage');
  }

  Future<void> _open(BuildContext context) async {
    final opened = await OpenCashShiftSheet.show(
      context,
      branchId: branchId,
      repo: repository,
    );
    if (opened != null) await onOpened?.call();
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('no_cash_session_warning'),
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: context.colors.warningBg,
      borderRadius: BorderRadius.circular(AppDimens.radiusSM),
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
        if (_canOpen) ...[
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('no_cash_session_open'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.warning,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _open(context),
            child: const Text(
              'Ээлж нээх',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ],
    ),
  );
}
