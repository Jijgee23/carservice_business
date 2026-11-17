import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/branch.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/branch_service.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/core/widgets/picker_screen.dart';
import 'package:carservice_business/features/employees/data/employee_repository.dart';
import 'package:carservice_business/features/employees/domain/employee.dart';
import 'package:carservice_business/features/employees/domain/employees_repository.dart';
import 'package:carservice_business/features/employees/presentation/controllers/employee_form_controller.dart';
import 'package:carservice_business/features/roles/data/role_repository.dart';
import 'package:carservice_business/features/roles/domain/role.dart';
import 'package:carservice_business/features/roles/domain/roles_repository.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Create/edit form for one employee — P6-F2.
///
/// `PATCH /employees/[id]` is a whole-record replace, so [_save] always
/// sends every field explicitly on both create and edit — see
/// `EmployeeFormController`'s doc comment. The owner toggle
/// ([_ownerToggleVisible]) is visible only when the signed-in caller is
/// itself an owner, mirroring the web form (`employee-form.tsx`) and the
/// server's own `prepareCreateEmployee` gate — a non-owner would never see
/// the toggle honoured anyway, but hiding it also avoids implying the
/// caller could grant ownership when they cannot.
///
/// Branches are fetched through the existing tenant-wide [BranchService]
/// singleton — the same source `BranchFilterBar` already uses — rather
/// than introducing a second branch data path.
///
/// **Not wired to a route.** Intended paths: `/employees/new` (create,
/// gated `employees.create`) and `/employees/:id/edit` (edit, gated
/// `employees.edit`).
///
/// `activeUntil` (a temporary-access expiry date, date-only — matches the
/// web form's `<DatePicker>`/`lib/employees/validate.ts`'s `activeUntilRaw`
/// parsing: empty means permanent, a set date means temporary) is prefilled
/// from [employee] on edit and always re-sent explicitly on save — since
/// `PATCH` is a whole-record replace, silently omitting it (or always
/// sending `null`) would wipe an existing expiry the moment any other field
/// on the same employee is edited. [_pickActiveUntil] uses the existing
/// [AppDatePicker.single] sheet; there is an explicit clear (✕) affordance
/// alongside it, matching the web form's empty-string-clears-it behaviour.
class EmployeeFormScreen extends StatefulWidget {
  const EmployeeFormScreen({
    super.key,
    this.employee,
    this.repo,
    this.rolesRepo,
    this.user,
    this.onSaved,
  });

  /// `null` = create; non-null = edit that record.
  final Employee? employee;
  final EmployeesRepository? repo;
  final RolesRepository? rolesRepo;
  final User? user;

  /// Called with the created/updated [Employee] after a successful save.
  final ValueChanged<Employee>? onSaved;

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  late final EmployeeFormController _controller = EmployeeFormController(
    repo: widget.repo,
  );
  late final RolesRepository _rolesRepo =
      widget.rolesRepo ?? RemoteRolesRepository();

  late final _firstNameCtrl = TextEditingController(
    text: widget.employee?.firstName ?? '',
  );
  late final _lastNameCtrl = TextEditingController(
    text: widget.employee?.lastName ?? '',
  );
  late final _emailCtrl = TextEditingController(
    text: widget.employee?.email ?? '',
  );
  late final _phoneCtrl = TextEditingController(
    text: widget.employee?.phone ?? '',
  );

  Role? _selectedRole;
  String? _branchId;
  Set<String> _assignableBranchIds = {};
  bool _isActive = true;
  bool _isOwner = false;
  DateTime? _activeUntil;

  List<Role> _roles = const [];
  List<Branch> _branches = const [];
  bool _loadingOptions = true;

  Map<String, String> _fieldErrors = const {};
  String? _generalError;

  bool get _isEdit => widget.employee != null;

  User? get _user => widget.user ?? Authenticator.user;

  bool get _ownerToggleVisible => _user?.isOwner == true;

  @override
  void initState() {
    super.initState();
    _isActive = widget.employee?.isActive ?? true;
    _isOwner = widget.employee?.isOwner ?? false;
    _activeUntil = widget.employee?.activeUntil;
    _branchId = widget.employee?.branchId;
    _assignableBranchIds = {
      ...(widget.employee?.assignableBranchIds ?? const []),
    };
    _loadOptions();
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
      _selectedRole = _roles
          .where((r) => r.id == widget.employee?.roleId)
          .firstOrNull;
      _loadingOptions = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRole() async {
    final picked = await PickerScreen.push<Role>(
      context,
      title: 'Үүрэг сонгох',
      items: _roles,
      label: (r) => r.name ?? '—',
      selected: _selectedRole,
    );
    if (picked != null) setState(() => _selectedRole = picked);
  }

  Future<void> _pickActiveUntil() async {
    final now = DateTime.now();
    final picked = await AppDatePicker.single(
      context,
      initial: _activeUntil ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _activeUntil = picked);
  }

  void _toggleAssignableBranch(String id) {
    setState(() {
      if (_assignableBranchIds.contains(id)) {
        _assignableBranchIds.remove(id);
      } else {
        _assignableBranchIds.add(id);
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _fieldErrors = const {};
      _generalError = null;
    });
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    final Result<Employee> result;
    if (_isEdit) {
      result = await _controller.submitUpdate(
        widget.employee!.id,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        roleId: widget.employee!.isOwner
            ? widget.employee!.roleId
            : _selectedRole?.id,
        branchId: _branchId,
        assignableBranchIds: _assignableBranchIds.toList(growable: false),
        isActive: _isActive,
        activeUntil: _activeUntil,
      );
    } else {
      result = await _controller.submitCreate(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        roleId: _selectedRole?.id,
        branchId: _branchId,
        assignableBranchIds: _assignableBranchIds.toList(growable: false),
        isActive: _isActive,
        activeUntil: _activeUntil,
        isOwner: _ownerToggleVisible && _isOwner,
      );
    }
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        messageComplete(_isEdit ? 'Хадгалагдлаа' : 'Ажилтан үүслээ');
        widget.onSaved?.call(value);
        AppNav.back(value);
      case Err(:final error):
        setState(() {
          _fieldErrors = error.fieldErrors ?? const {};
          _generalError =
              (error.fieldErrors == null || error.fieldErrors!.isEmpty)
              ? error.display
              : null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = _controller.submitting;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Ажилтан засах' : 'Шинэ ажилтан'),
        actions: [
          TextButton(
            onPressed: saving || _loadingOptions ? null : _save,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Хадгалах'),
          ),
        ],
      ),
      body: _loadingOptions
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppDimens.paddingMD),
              children: [
                if (_generalError != null) ...[
                  Text(
                    _generalError!,
                    style: TextStyle(color: context.colors.danger),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _lastNameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Овог',
                    errorText: _fieldErrors['lastName'],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _firstNameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Нэр',
                    errorText: _fieldErrors['firstName'],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Имэйл',
                    errorText: _fieldErrors['email'],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Утас',
                    errorText: _fieldErrors['phone'],
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  key: const ValueKey('employee_form_role_tile'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Үүрэг'),
                  subtitle: Text(
                    widget.employee?.isOwner == true
                        ? 'Эзэмшигчийн үүргийг өөрчлөх боломжгүй'
                        : (_selectedRole?.name ?? 'Сонгоогүй'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: widget.employee?.isOwner != true,
                  onTap: widget.employee?.isOwner == true ? null : _pickRole,
                ),
                if (_fieldErrors['roleId'] != null)
                  Text(
                    _fieldErrors['roleId']!,
                    style: TextStyle(
                      color: context.colors.danger,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 8),
                Text('Үндсэн салбар', style: context.textStyles.bodyMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Хуваарилаагүй'),
                      selected: _branchId == null,
                      onSelected: (_) => setState(() => _branchId = null),
                    ),
                    for (final b in _branches)
                      ChoiceChip(
                        label: Text(b.name),
                        selected: _branchId == b.id,
                        onSelected: (_) => setState(() => _branchId = b.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Хандах эрхтэй салбарууд',
                  style: context.textStyles.bodyMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final b in _branches)
                      FilterChip(
                        label: Text(b.name),
                        selected: _assignableBranchIds.contains(b.id),
                        onSelected: (_) => _toggleAssignableBranch(b.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  key: const ValueKey('employee_form_active_until_tile'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ажиллах хугацаа дуусах огноо'),
                  subtitle: Text(
                    _activeUntil == null
                        ? 'Байнгын (огноо тавиагүй)'
                        : '${_activeUntil!.year}-${_activeUntil!.month.toString().padLeft(2, '0')}-${_activeUntil!.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: _activeUntil == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          key: const ValueKey(
                            'employee_form_active_until_clear',
                          ),
                          icon: const Icon(Icons.close),
                          tooltip: 'Цэвэрлэх',
                          onPressed: () => setState(() => _activeUntil = null),
                        ),
                  onTap: _pickActiveUntil,
                ),
                if (_fieldErrors['activeUntil'] != null)
                  Text(
                    _fieldErrors['activeUntil']!,
                    style: TextStyle(
                      color: context.colors.danger,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 16),
                SwitchListTile(
                  key: const ValueKey('employee_form_active_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Идэвхтэй'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                if (_ownerToggleVisible && !_isEdit)
                  SwitchListTile(
                    key: const ValueKey('employee_form_owner_switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Эзэмшигч эрхтэй болгох'),
                    subtitle: const Text(
                      'Зөвхөн эзэмшигч эрхтэй хэрэглэгч энэ сонголтыг хийж болно.',
                    ),
                    value: _isOwner,
                    onChanged: (v) => setState(() => _isOwner = v),
                  ),
              ],
            ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
