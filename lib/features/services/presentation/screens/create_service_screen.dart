import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/price_input.dart';
import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/picker_screen.dart';
import 'package:carservice_business/features/services/domain/service.dart';
import 'package:carservice_business/features/services/domain/services_repository.dart';
import 'package:carservice_business/features/services/presentation/controllers/create_service_controller.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Create/edit form rebuild — P4-F3.
///
/// [existing] `null` → create; non-`null` → edit. See
/// `CreateServiceController`'s doc comment for why the two modes submit
/// through two different backends. Gated at the surface (D-163) on
/// `services.create`/`services.edit` respectively — a staff member who
/// somehow reaches this screen without the right permission sees a denial,
/// not a form that will just 403 on submit.
///
/// Pops `true` on success, `false`/`null` otherwise — never the created or
/// updated record. The caller (`ServiceDetailScreen._edit`,
/// `service_list_screen.dart`'s create FAB) is expected to re-fetch, not
/// read anything off this screen's result — see the controller's doc
/// comment on the `PATCH`/`POST` response shapes this form deliberately
/// never surfaces.
class CreateServiceScreen extends StatelessWidget {
  const CreateServiceScreen({
    super.key,
    this.initialType = ServiceKind.labor,
    this.existing,
    this.repo,
    this.user,
  });

  final ServiceKind initialType;
  final Service? existing;
  final ServicesRepository? repo;
  final User? user;

  bool get _isEditing => existing != null;

  @override
  Widget build(BuildContext context) {
    final effectiveUser = user ?? Authenticator.user;
    final requiredPermission = _isEditing ? 'services.edit' : 'services.create';
    if (!canSeeView(effectiveUser, requiredPermission)) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEditing ? 'Засах' : 'Бүртгэх')),
        body: const EmptyState(
          message: 'Энэ үйлдэлд эрх байхгүй байна',
          icon: Icons.lock_outline,
        ),
      );
    }
    return ChangeNotifierProvider(
      create: (_) => CreateServiceController(
        existing: existing,
        repo: repo,
        initialType: initialType,
      )..init(),
      child: const _CreateServiceBody(),
    );
  }
}

class _CreateServiceBody extends StatefulWidget {
  const _CreateServiceBody();

  @override
  State<_CreateServiceBody> createState() => _CreateServiceBodyState();
}

class _CreateServiceBodyState extends State<_CreateServiceBody> {
  final _formKey = GlobalKey<FormState>();

  // Created eagerly in `initState`, never as lazy `late final` field
  // initializers: a conditionally-visible field (e.g. `_durationCtrl` on a
  // `GOODS` row, where `showDuration` is false) may never be *read* during
  // build, which would defer its lazy initializer — including the
  // `context.read<CreateServiceController>()` call `_existing` used to
  // make — until `dispose()`, by which point this widget's context is
  // already deactivated and `context.read` throws. Reading the controller
  // once, up front, in `initState` avoids that entirely.
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costPriceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _reminderCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    final existing = context.read<CreateServiceController>().existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _codeCtrl = TextEditingController(text: existing?.code ?? '');
    _priceCtrl = TextEditingController(
      text: formatPriceInput(existing?.price ?? ''),
    );
    _costPriceCtrl = TextEditingController(
      text: formatPriceInput(existing?.costPrice ?? ''),
    );
    _stockCtrl = TextEditingController();
    _durationCtrl = TextEditingController(text: existing?.durationValue ?? '');
    // Pre-filled on edit: PATCH replaces the whole record, so an empty field
    // here would wipe the interval (the GET routes now return it).
    _reminderCtrl = TextEditingController(
      text: existing?.reminderIntervalMonths?.toString() ?? '',
    );
    _descCtrl = TextEditingController(text: existing?.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _priceCtrl.dispose();
    _costPriceCtrl.dispose();
    _stockCtrl.dispose();
    _durationCtrl.dispose();
    _reminderCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool _canSubmit(CreateServiceController ctrl) =>
      !ctrl.submitting &&
      !ctrl.loadingLookups &&
      _nameCtrl.text.trim().isNotEmpty &&
      _priceCtrl.text.trim().isNotEmpty &&
      ctrl.selectedCategory != null;

  /// A price field's number as the API takes it: grouping commas removed.
  static String _priceText(TextEditingController c) =>
      c.text.replaceAll(',', '').trim();

  Future<void> _submit(CreateServiceController ctrl) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (ctrl.selectedCategory == null) {
      messageError('Ангилал сонгоно уу');
      return;
    }

    final saved = await ctrl.submit(
      name: _nameCtrl.text.trim(),
      code: _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
      price: _priceText(_priceCtrl),
      costPrice: _priceText(_costPriceCtrl).isEmpty
          ? null
          : _priceText(_costPriceCtrl),
      stock: _stockCtrl.text.trim().isEmpty ? null : _stockCtrl.text.trim(),
      durationValue: _durationCtrl.text.trim().isEmpty
          ? null
          : _durationCtrl.text.trim(),
      reminderIntervalMonths: _reminderCtrl.text.trim().isEmpty
          ? null
          : int.tryParse(_reminderCtrl.text.trim()),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
    );

    if (!mounted) return;
    if (saved) {
      AppNav.back(true);
    } else {
      final error = ctrl.lastError;
      if (error != null &&
          (error.fieldErrors == null || error.fieldErrors!.isEmpty)) {
        messageError(error.display);
      }
      // Field-level errors are rendered inline by `build` below via
      // `ctrl.fieldErrors` — no toast for those, matching
      // `CustomerEditSheet`'s 422-binding convention.
    }
  }

  Future<void> _pickUnit(CreateServiceController ctrl) async {
    if (ctrl.units.isEmpty) return;
    final picked = await PickerScreen.push<Unit>(
      context,
      title: 'Хэмжих нэгж',
      items: ctrl.units,
      selected: ctrl.selectedUnit,
      label: (u) => u.name ?? u.id,
      subtitle: (u) => u.code,
    );
    if (picked != null) ctrl.setUnit(picked);
  }

  Future<void> _pickCategory(CreateServiceController ctrl) async {
    if (ctrl.categories.isEmpty) return;
    final picked = await PickerScreen.push<Category>(
      context,
      title: 'Ангилал',
      items: ctrl.categories,
      selected: ctrl.selectedCategory,
      label: (c) => c.name ?? c.id,
    );
    if (picked != null) ctrl.setCategory(picked);
  }

  Future<void> _pickDurationUnit(CreateServiceController ctrl) async {
    if (ctrl.units.isEmpty) return;
    final picked = await PickerScreen.push<Unit>(
      context,
      title: 'Хугацааны нэгж',
      items: ctrl.units,
      selected: ctrl.selectedDurationUnit,
      label: (u) => u.name ?? u.id,
      subtitle: (u) => u.code,
    );
    if (picked != null) ctrl.setDurationUnit(picked);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreateServiceController>();
    final errors = ctrl.fieldErrors;
    final isEditing = ctrl.isEditing;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(isEditing ? 'Үйлчилгээ засах' : 'Үйлчилгээ бүртгэх'),
      ),
      body: ctrl.loadingLookups
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ctrl.lastError?.display != null &&
                        (ctrl.fieldErrors.isEmpty)) ...[
                      // General (non-field) failure banner.
                      if (ctrl.lastError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            ctrl.lastError!.display,
                            style: TextStyle(color: context.colors.danger),
                          ),
                        ),
                    ],

                    // ─── Төрөл ──────────────────────────────────────────
                    _Section(
                      title: 'Төрөл',
                      child: isEditing
                          ? _KindReadOnly(kind: ctrl.type)
                          : Row(
                              children:
                                  const [
                                    ServiceKind.labor,
                                    ServiceKind.goods,
                                    ServiceKind.diagnostic,
                                  ].map((k) {
                                    final active = ctrl.type == k;
                                    return Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: k != ServiceKind.diagnostic
                                              ? 8
                                              : 0,
                                        ),
                                        child: GestureDetector(
                                          onTap: () => ctrl.setType(k),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 160,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: active
                                                  ? context.colors.accent
                                                        .withValues(alpha: 0.12)
                                                  : context.colors.surface,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: active
                                                    ? context.colors.accent
                                                    : context.colors.divider,
                                                width: active ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  k.label,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: active
                                                        ? FontWeight.w700
                                                        : FontWeight.w400,
                                                    color: active
                                                        ? context.colors.accent
                                                        : context
                                                              .colors
                                                              .textSecondary,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Ангилал (mandatory for every kind now — D-164 /
                    // the widened `allowedKinds`) ────────────────────────
                    _Section(
                      title: 'Ангилал',
                      child: _PickerTile(
                        label: 'Ангилал сонгох',
                        value: ctrl.selectedCategory?.name,
                        onTap: () => _pickCategory(ctrl),
                        errorText: errors['categoryId'],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Үндсэн мэдээлэл ────────────────────────────────
                    _Section(
                      title: 'Үндсэн мэдээлэл',
                      child: Column(
                        children: [
                          _Field(
                            controller: _nameCtrl,
                            label: 'Нэр',
                            hint: 'Тос солих, Тоормосны шингэн...',
                            required: true,
                            errorText: errors['name'],
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            controller: _codeCtrl,
                            label: 'Код / SKU',
                            hint: 'SVC-001 (заавал биш)',
                            errorText: errors['code'],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Хэмжих нэгж ────────────────────────────────────
                    _Section(
                      title: 'Хэмжих нэгж',
                      child: _PickerTile(
                        label: 'Нэгж сонгох',
                        value: ctrl.selectedUnit?.name,
                        valueSubtitle: ctrl.selectedUnit?.code,
                        onTap: () => _pickUnit(ctrl),
                        errorText: errors['unitId'],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Үнэ ────────────────────────────────────────────
                    _Section(
                      title: 'Үнэ',
                      child: Column(
                        children: [
                          _Field(
                            controller: _priceCtrl,
                            label: 'Зарах үнэ ₮',
                            hint: '0',
                            required: true,
                            errorText: errors['price'],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: const [PriceInputFormatter()],
                            onChanged: (_) => setState(() {}),
                          ),
                          if (ctrl.showCostAndStock) ...[
                            const SizedBox(height: 12),
                            _Field(
                              controller: _costPriceCtrl,
                              label: 'Өртөг ₮',
                              hint: '0 (заавал биш)',
                              errorText: errors['costPrice'],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: const [PriceInputFormatter()],
                            ),
                            const SizedBox(height: 12),
                            if (isEditing)
                              _LockedStockNotice(stock: ctrl.lockedStock)
                            else
                              _Field(
                                controller: _stockCtrl,
                                label: 'Нөөц тоо ширхэг',
                                hint: '0',
                                errorText: errors['stock'],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d*'),
                                  ),
                                ],
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Үргэлжлэх хугацаа ──────────────────────────────
                    if (ctrl.showDuration) ...[
                      _Section(
                        title: 'Үргэлжлэх хугацаа',
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _Field(
                                controller: _durationCtrl,
                                label: 'Хугацаа',
                                hint: '1.5 (заавал биш)',
                                errorText: errors['durationValue'],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d*'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: _PickerTile(
                                label: 'Нэгж',
                                value: ctrl.selectedDurationUnit?.name,
                                valueSubtitle: ctrl.selectedDurationUnit?.code,
                                onTap: () => _pickDurationUnit(ctrl),
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ─── Сануулгын хугацаа ──────────────────────────────
                    _Section(
                      title: 'Сануулга',
                      child: _Field(
                        controller: _reminderCtrl,
                        label: 'Сануулах хугацаа (сар)',
                        hint: '6 (заавал биш)',
                        errorText: errors['reminderIntervalMonths'],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Тайлбар ────────────────────────────────────────
                    _Section(
                      title: 'Тайлбар',
                      child: _Field(
                        controller: _descCtrl,
                        label: 'Тайлбар',
                        hint: 'Нэмэлт мэдээлэл (заавал биш)',
                        maxLines: 3,
                        errorText: errors['description'],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Тохиргоо ───────────────────────────────────────
                    _Section(
                      title: 'Тохиргоо',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Идэвхтэй',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          Switch(
                            value: ctrl.isActive,
                            onChanged: ctrl.setIsActive,
                            activeColor: context.colors.accent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ─── Submit ─────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        key: const ValueKey('service_form_submit'),
                        onPressed: _canSubmit(ctrl)
                            ? () => _submit(ctrl)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.accent,
                          foregroundColor: CarserviceTheme.of(context).onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: ctrl.submitting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: CarserviceTheme.of(context).onAccent,
                                ),
                              )
                            : Text(isEditing ? 'Хадгалах' : 'Бүртгэх'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─── Small widgets ──────────────────────────────────────────────────────────

class _KindReadOnly extends StatelessWidget {
  const _KindReadOnly({required this.kind});
  final ServiceKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.divider),
      ),
      child: Row(
        children: [
          Text(kind.label, style: context.textStyles.bodyMedium),
          const Spacer(),
          Icon(Icons.lock_outline, size: 16, color: context.colors.textHint),
          const SizedBox(width: 6),
          Text(
            'Үүсгэсний дараа өөрчлөгдөхгүй',
            style: TextStyle(fontSize: 11, color: context.colors.textHint),
          ),
        ],
      ),
    );
  }
}

class _LockedStockNotice extends StatelessWidget {
  const _LockedStockNotice({required this.stock});
  final String? stock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Одоогийн үлдэгдэл: ${stock ?? '—'}',
              style: context.textStyles.bodyMedium,
            ),
          ),
          Icon(Icons.info_outline, size: 14, color: context.colors.textHint),
          const SizedBox(width: 4),
          Text(
            '"Үлдэгдэл" товчоор өөрчилнө',
            style: TextStyle(fontSize: 11, color: context.colors.textHint),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.onTap,
    this.value,
    this.valueSubtitle,
    this.compact = false,
    this.errorText,
  });

  final String label;
  final String? value;
  final String? valueSubtitle;
  final VoidCallback onTap;
  final bool compact;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final hasError = errorText != null && errorText!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: compact ? 11 : 14,
            ),
            decoration: BoxDecoration(
              color: context.colors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasError
                    ? context.colors.danger
                    : context.colors.divider,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!hasValue)
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.textHint,
                          ),
                        )
                      else ...[
                        Text(
                          value!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        if (valueSubtitle != null && valueSubtitle!.isNotEmpty)
                          Text(
                            valueSubtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textSecondary,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.colors.textHint,
                ),
              ],
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              errorText!,
              style: TextStyle(fontSize: 12, color: context.colors.danger),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textHint,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final void Function(String)? onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      validator: required ? (v) => AppValidators.required(v, label) : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        filled: true,
        fillColor: context.colors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
