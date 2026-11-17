import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/branch.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/branch_service.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/picker_screen.dart';
import 'package:carservice_business/core/widgets/selection/selection_bar.dart';
import 'package:carservice_business/features/employees/domain/employee.dart';
import 'package:carservice_business/features/employees/domain/employees_repository.dart';
import 'package:carservice_business/features/employees/presentation/controllers/employee_bulk_controller.dart';
import 'package:carservice_business/features/roles/data/role_repository.dart';
import 'package:carservice_business/features/roles/domain/role.dart';
import 'package:carservice_business/features/roles/domain/roles_repository.dart';

/// Bulk role/branch reassignment — P6-F2, new surface.
///
/// Drives the new generic `lib/core/widgets/selection/` [SelectionController]
/// (via [EmployeeBulkController.selection]) — tap/long-press to enter
/// selection, select-all with an indeterminate tri-state, count, clear —
/// through [SelectionActionBar]. `POST /employees/bulk` is per-row, never
/// all-or-nothing (see `EmployeesRepository.bulkUpdateRoleBranch`'s doc
/// comment), surfaced with [SelectionResultBanner], matching
/// `BulkCategoryScreen`'s partial-result banner for services.
///
/// Gated on `employees.edit` at the surface level (D-163) — the same
/// permission the backend requires on this route.
///
/// **Not yet wired to a navigation entry point** — `employee_list_screen.dart`
/// exposes [EmployeeListScreen.onBulkEdit] as the hook for whichever slice
/// (`P6-F5`) adds the button. Intended path: `/employees/bulk`.
class EmployeeBulkScreen extends StatefulWidget {
  const EmployeeBulkScreen({super.key, this.repo, this.rolesRepo, this.user});

  final EmployeesRepository? repo;
  final RolesRepository? rolesRepo;
  final User? user;

  @override
  State<EmployeeBulkScreen> createState() => _EmployeeBulkScreenState();
}

class _EmployeeBulkScreenState extends State<EmployeeBulkScreen> {
  late final EmployeeBulkController _controller = EmployeeBulkController(
    repo: widget.repo,
  );
  late final RolesRepository _rolesRepo =
      widget.rolesRepo ?? RemoteRolesRepository();

  List<Role> _roles = const [];
  List<Branch> _branches = const [];

  User? get _user => widget.user ?? Authenticator.user;
  bool get _canEdit => canSeeView(_user, 'employees.edit');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _controller.selection.addListener(_onControllerChanged);
    if (_canEdit) {
      _controller.load();
      _loadOptions();
    }
  }

  Future<void> _loadOptions() async {
    final branches = await BranchService.instance.getBranches();
    final rolesResult = await _rolesRepo.getRoles();
    if (!mounted) return;
    setState(() {
      _branches = branches;
      // System roles (global); only active ones may be assigned.
      _roles = switch (rolesResult) {
        Ok(:final value) =>
          value.items.where((r) => r.isActive).toList(growable: false),
        Err() => const [],
      };
    });
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.selection.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickRoleAndApply() async {
    if (_roles.isEmpty) return;
    final picked = await PickerScreen.push<Role>(
      context,
      title: 'Шинэ үүрэг',
      items: _roles,
      label: (r) => r.name ?? '—',
    );
    if (picked == null || !mounted) return;
    await _apply(roleId: picked.id);
  }

  Future<void> _pickBranchAndApply() async {
    if (_branches.isEmpty) return;
    final picked = await PickerScreen.push<Branch>(
      context,
      title: 'Шинэ салбар',
      items: _branches,
      label: (b) => b.name,
    );
    if (picked == null || !mounted) return;
    await _apply(branchId: picked.id);
  }

  Future<void> _apply({String? roleId, String? branchId}) async {
    final result = await _controller.apply(roleId: roleId, branchId: branchId);
    if (!mounted) return;
    if (result case Err(:final error)) {
      // Whole-request rejection — never per-item, see the class doc
      // comment — so a toast is the right surface here, unlike the
      // per-item errors rendered via `SelectionResultBanner`.
      messageError(error.display);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canEdit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Бөөнөөр өөрчлөх')),
        body: const EmptyState(
          message: 'Энэ үйлдэлд эрх байхгүй байна',
          icon: Icons.lock_outline,
        ),
      );
    }

    final selection = _controller.selection;
    final items = _controller.items;
    final visibleIds = items.map((e) => e.id);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Ажилтан бөөнөөр өөрчлөх'),
        actions: [
          IconButton(
            icon: Icon(
              selection.isIndeterminate(visibleIds)
                  ? Icons.indeterminate_check_box_outlined
                  : selection.isAllSelected(visibleIds)
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
            ),
            tooltip: 'Бүгдийг сонгох/цуцлах',
            onPressed: items.isEmpty
                ? null
                : () => selection.selectAllVisible(visibleIds),
          ),
        ],
      ),
      body: AsyncStateView<List<Employee>>(
        state: _controller.listState,
        isEmpty: (v) => v.isEmpty,
        empty: const EmptyState(
          message: 'Ажилтан байхгүй байна',
          icon: Icons.people_outline,
        ),
        onRetry: _controller.refresh,
        builder: (context, items) => RefreshIndicator(
          onRefresh: _controller.refresh,
          child: Column(
            children: [
              if (_controller.lastResult != null)
                SelectionResultBanner(
                  succeeded: _controller.lastResult!.succeeded,
                  failed: _controller.lastResult!.failed,
                  errors: _controller.lastResult!.errors,
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppDimens.paddingMD),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final employee = items[i];
                    return SelectableListTile(
                      selected: selection.isSelected(employee.id),
                      selectionMode: selection.isActive,
                      onTap: () => selection.toggle(employee.id),
                      onLongPress: () => selection.toggle(employee.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              employee.displayName,
                              style: context.textStyles.bodyMedium,
                            ),
                            if (employee.roleName != null)
                              Text(
                                employee.roleName!,
                                style: context.textStyles.caption,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: selection.isEmpty
          ? null
          : SelectionActionBar(
              count: selection.count,
              busy: _controller.submitting,
              onClear: selection.clear,
              actions: [
                SelectionAction(
                  label: 'Үүрэг',
                  icon: Icons.badge_outlined,
                  onPressed: _roles.isEmpty ? null : _pickRoleAndApply,
                ),
                SelectionAction(
                  label: 'Салбар',
                  icon: Icons.store_outlined,
                  onPressed: _branches.isEmpty ? null : _pickBranchAndApply,
                ),
              ],
            ),
    );
  }
}
