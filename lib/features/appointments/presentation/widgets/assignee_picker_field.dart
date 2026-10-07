import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/app_dropdown.dart';
import 'package:carservice_business/features/appointments/domain/assignee_access.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/assignee_avatar.dart';

/// «Хариуцах мастер» picker for appointments — same look and states as
/// `_AssigneeSection` in `create_order_screen.dart` (loading, retryable list
/// error, inline field error). Deliberately offers no "none" entry: the server
/// refuses a master-less appointment (`ASSIGNEE_REQUIRED`).
class AssigneePickerField extends StatelessWidget {
  const AssigneePickerField({
    super.key,
    required this.users,
    required this.selected,
    required this.loading,
    required this.error,
    this.fieldError,
    required this.onChanged,
    required this.onRetry,
    this.pickerKey = const ValueKey('appointment_assignee_picker'),
  });

  final List<AssignableUser> users;
  final AssignableUser? selected;
  final bool loading;
  final String? error;
  final String? fieldError;
  final ValueChanged<AssignableUser> onChanged;
  final VoidCallback onRetry;
  final Key pickerKey;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (loading && users.isEmpty) {
      child = Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Мастеруудыг ачааллаж байна...',
            style: context.textStyles.caption,
          ),
        ],
      );
    } else if (error != null) {
      child = Row(
        children: [
          Expanded(
            child: Text(
              error!,
              style: context.textStyles.caption.copyWith(
                color: context.opsTextSecondary,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Дахин')),
        ],
      );
    } else if (users.isEmpty) {
      child = Text(
        kNoEligibleAssigneeReason,
        key: const ValueKey('appointment_assignee_none_eligible'),
        style: context.textStyles.caption.copyWith(
          color: context.opsTextSecondary,
        ),
      );
    } else {
      child = AppDropdown<String?>(
        key: pickerKey,
        value: users.any((u) => u.id == selected?.id) ? selected?.id : null,
        decoration: const InputDecoration(
          hintText: 'Мастер сонгоно уу',
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        items: [
          for (final u in users)
            AppDropdownItem<String?>(
              value: u.id,
              label: u.fullName.isEmpty ? '—' : u.fullName,
              leading: AssigneeAvatar(name: u.fullName, size: 28),
            ),
        ],
        onChanged: (id) {
          if (id == null) return;
          onChanged(users.firstWhere((u) => u.id == id));
        },
      );
    }
    final errText = fieldError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('appointment_assignee_field'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.opsSurface,
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            border: Border.all(
              color: errText != null ? context.opsDanger : context.opsDivider,
            ),
          ),
          child: child,
        ),
        if (errText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errText,
              key: const ValueKey('appointment_assignee_field_error'),
              style: context.textStyles.caption.copyWith(
                color: context.opsDanger,
              ),
            ),
          ),
      ],
    );
  }
}
