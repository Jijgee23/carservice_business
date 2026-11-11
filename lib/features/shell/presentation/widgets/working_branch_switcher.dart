import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/working_branch_scope.dart';
import 'package:carservice_business/core/network/working_branch_interceptor.dart';
import 'package:carservice_business/core/widgets/app_dropdown.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';

/// The scopes [value] offers: "Бүх салбар" when allowed, every branch, and
/// the roster-locked branch if the list does not carry it.
List<AppDropdownItem<String>> workingBranchChoices(
  WorkingBranchController value,
) {
  final choices = <AppDropdownItem<String>>[];
  if (value.options.allowAll && !value.isLocked) {
    choices.add(
      const AppDropdownItem(value: allWorkingBranches, label: 'Бүх салбар'),
    );
  }
  choices.addAll(
    value.options.branches.map(
      (branch) => AppDropdownItem(value: branch.id, label: branch.name),
    ),
  );
  if (value.isLocked &&
      value.options.lockedBranchId != null &&
      !choices.any((choice) => choice.value == value.options.lockedBranchId)) {
    choices.add(
      AppDropdownItem(
        value: value.options.lockedBranchId!,
        label: 'Түгжигдсэн салбар',
      ),
    );
  }
  return choices;
}

/// The current pick among [choices], or the locked branch.
String? workingBranchSelected(
  WorkingBranchController value,
  List<AppDropdownItem<String>> choices,
) =>
    value.selection != null &&
        choices.any((choice) => choice.value == value.selection)
    ? value.selection
    : (value.isLocked ? value.options.lockedBranchId : null);

/// Name of the active scope ("Бүх салбар", a branch name), or null when
/// nothing is picked yet.
String? workingBranchLabel(WorkingBranchController value) {
  final choices = workingBranchChoices(value);
  final selected = workingBranchSelected(value, choices);
  for (final choice in choices) {
    if (choice.value == selected) return choice.label;
  }
  return null;
}

/// Bottom-sheet picker over the same choices as [WorkingBranchSwitcher]
/// ("Солих" on the Бусад branch row). A no-op while locked.
Future<void> showWorkingBranchSheet(
  BuildContext context,
  WorkingBranchController value,
) async {
  if (value.isLocked) return;
  final choices = workingBranchChoices(value);
  final selected = workingBranchSelected(value, choices);
  final picked = await showModalBottomSheet<String>(
    context: context,
    // Above the shell's floating navigation, not inside the tab.
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final t = CarserviceTheme.of(sheetContext);
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                'Ажиллах салбар',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ),
            for (final choice in choices)
              ListTile(
                key: ValueKey('branch_sheet_${choice.value}'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  choice.value == allWorkingBranches
                      ? Icons.apartment_rounded
                      : Icons.store_mall_directory_outlined,
                  color: t.ink,
                ),
                title: Text(choice.label, style: TextStyle(color: t.ink)),
                trailing: choice.value == selected
                    ? Icon(Icons.check_rounded, color: t.accent)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(choice.value),
              ),
          ],
        ),
      );
    },
  );
  if (picked != null && picked != selected) await value.select(picked);
}

/// Reusable compact working-branch selector.
class WorkingBranchSwitcher extends StatelessWidget {
  final WorkingBranchController? controller;

  /// Fill the available width, the picked name right-aligned and
  /// ellipsized — for a row where a long branch name must not overflow.
  final bool expanded;

  const WorkingBranchSwitcher({
    super.key,
    this.controller,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final value = controller ?? context.watch<WorkingBranchController>();
    if (value.state == WorkingBranchLoadState.initial || value.isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (value.hasError || value.options.branches.isEmpty) {
      return const SizedBox.shrink();
    }

    final choices = workingBranchChoices(value);
    return AppDropdown<String>(
      value: workingBranchSelected(value, choices),
      hint: 'Салбар',
      variant: AppDropdownVariant.inline,
      expand: expanded,
      onChanged: value.isLocked ? null : value.select,
      items: choices,
    );
  }
}
