import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/branches/domain/branch.dart';
import 'package:carservice_business/features/branches/domain/branches_repository.dart';
import 'package:carservice_business/features/branches/presentation/controllers/branch_form_controller.dart';
import 'package:carservice_business/features/branches/presentation/screens/branch_location_picker_screen.dart';

/// Opens the map picker; completes with the chosen point or null.
typedef BranchLocationPicker = Future<LatLng?> Function(BuildContext context, LatLng? initial);

/// Create (`branchId == null`) or edit one branch — the web's
/// `BranchForm` (`app/dashboard/branches/branch-form.tsx`): name, phone,
/// primary flag, business-type tags (at least one for a new branch), map
/// pin + address, default and per-weekday hours, online-booking slot length
/// and capacity. Edit adds activate/deactivate (`branches.edit`) and delete
/// (`branches.delete`). Closes with `true` after a change.
class BranchFormScreen extends StatelessWidget {
  const BranchFormScreen({
    super.key,
    this.branchId,
    this.repository,
    this.user,
    this.pickLocation,
  });

  final String? branchId;
  final BranchesRepository? repository;
  final User? user;
  final BranchLocationPicker? pickLocation;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => BranchFormController(branchId: branchId, repo: repository)..load(),
    child: _Body(user: user ?? Authenticator.user, pickLocation: pickLocation),
  );
}

class _Body extends StatefulWidget {
  const _Body({required this.user, required this.pickLocation});

  final User? user;
  final BranchLocationPicker? pickLocation;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _slotMinutes = TextEditingController();
  final _slotCapacity = TextEditingController();

  String _city = '';
  String _district = '';
  String _khoroo = '';
  double? _lat;
  double? _lng;
  bool _resolvingAddress = false;
  String _openTime = '09:00';
  String _closeTime = '18:00';
  bool _isPrimary = false;
  Set<String> _tagIds = {};
  List<BranchDaySchedule> _days = [
    for (final d in BranchWeekday.values)
      BranchDaySchedule(weekday: d, isOpen: d.openByDefault),
  ];

  bool _filled = false;

  /// A change was saved — the list should reload.
  bool _changed = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _slotMinutes, _slotCapacity]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(BranchDetail b) {
    _name.text = b.name;
    _phone.text = b.phone ?? '';
    _address.text = b.address ?? '';
    _slotMinutes.text = b.slotMinutes?.toString() ?? '';
    _slotCapacity.text = b.slotCapacity?.toString() ?? '';
    _city = b.city ?? '';
    _district = b.district ?? '';
    _khoroo = b.khoroo ?? '';
    _lat = b.latitude;
    _lng = b.longitude;
    _openTime = b.openTime ?? '09:00';
    _closeTime = b.closeTime ?? '18:00';
    _isPrimary = b.isPrimary;
    _tagIds = {for (final t in b.tags) t.id};
    _days = [
      for (final d in b.schedules)
        d.isOpen
            ? d.copyWith(openTime: d.openTime ?? _openTime, closeTime: d.closeTime ?? _closeTime)
            : d,
    ];
  }

  BranchDraft get _draft => BranchDraft(
    name: _name.text,
    phone: _phone.text,
    city: _city,
    district: _district,
    khoroo: _khoroo,
    address: _address.text,
    latitude: _lat,
    longitude: _lng,
    openTime: _openTime,
    closeTime: _closeTime,
    slotMinutes: _slotMinutes.text,
    slotCapacity: _slotCapacity.text,
    isPrimary: _isPrimary,
    tagIds: _tagIds.toList(),
    schedules: [
      for (final d in _days)
        d.isOpen
            ? d.copyWith(openTime: d.openTime ?? _openTime, closeTime: d.closeTime ?? _closeTime)
            : d,
    ],
  );

  void _close() => Navigator.of(context).pop(_changed);

  Future<void> _save(BranchFormController c, {bool confirm = false}) async {
    FocusScope.of(context).unfocus();
    final outcome = await c.submit(_draft, confirm: confirm);
    if (!mounted) return;
    switch (outcome) {
      case BranchSaved():
        _changed = true;
        messageComplete(c.isEdit ? 'Салбар хадгалагдлаа' : 'Салбар нэмэгдлээ');
        _close();
      case BranchNeedsConfirm(:final impact):
        final ok = await ConfirmSheet.show(
          context,
          title: 'Цаг захиалга богиносно',
          message: impact.message,
          confirmLabel: 'Үргэлжлүүлэх',
          icon: Icons.schedule_rounded,
        );
        if (ok && mounted) await _save(c, confirm: true);
      case BranchSaveFailed():
        if (c.formError != null) messageError(c.formError!);
    }
  }

  Future<void> _toggleActive(BranchFormController c, BranchDetail b) async {
    final deactivate = b.isActive;
    final ok = await ConfirmSheet.show(
      context,
      title: deactivate ? 'Салбарыг идэвхгүй болгох уу?' : 'Салбарыг идэвхжүүлэх үү?',
      message: deactivate
          ? 'Идэвхгүй салбар жагсаалт, сонголт болон онлайн захиалгаас нуугдана. Өгөгдөл, түүх хадгалагдана.'
          : 'Салбар дахин жагсаалт, сонголтод харагдана.',
      confirmLabel: deactivate ? 'Идэвхгүй болгох' : 'Идэвхжүүлэх',
      icon: deactivate ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
      isDangerous: deactivate,
    );
    if (!ok || !mounted) return;
    final error = await c.toggleActive();
    if (!mounted) return;
    if (error != null) {
      messageError(error);
    } else {
      _changed = true;
      messageComplete(deactivate ? 'Салбар идэвхгүй боллоо' : 'Салбар идэвхжлээ');
    }
  }

  Future<void> _delete(BranchFormController c, BranchDetail b) async {
    final ok = await ConfirmSheet.show(
      context,
      title: '«${b.name}» салбарыг устгах уу?',
      message:
          'Устгасан салбарыг сэргээх боломжгүй. Ажилтан, засварын хуудас эсвэл цаг захиалгатай салбарыг устгах боломжгүй — оронд нь идэвхгүй болгоно уу.',
      confirmLabel: 'Устгах',
      icon: Icons.delete_outline_rounded,
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    final error = await c.delete();
    if (!mounted) return;
    if (error != null) {
      messageError(error);
      return;
    }
    _changed = true;
    messageComplete('Салбар устгагдлаа');
    _close();
  }

  Future<void> _pickLocation(BranchFormController c) async {
    final initial = _lat != null && _lng != null ? LatLng(_lat!, _lng!) : null;
    final picked = widget.pickLocation != null
        ? await widget.pickLocation!(context, initial)
        : await Navigator.of(context).push<LatLng>(
            MaterialPageRoute(builder: (_) => BranchLocationPickerScreen(initial: initial)),
          );
    if (picked == null || !mounted) return;
    setState(() {
      _lat = double.parse(picked.latitude.toStringAsFixed(6));
      _lng = double.parse(picked.longitude.toStringAsFixed(6));
      _resolvingAddress = true;
    });
    c.clearFieldError('latitude');
    c.clearFieldError('longitude');
    final found = await c.addressAt(_lat!, _lng!);
    if (!mounted) return;
    setState(() {
      _resolvingAddress = false;
      if (found != null) {
        _city = found.city;
        _district = found.district;
        _khoroo = found.khoroo;
        if (_address.text.trim().isEmpty && found.address.isNotEmpty) {
          _address.text = found.address;
        }
      }
    });
  }

  void _clearLocation() => setState(() {
    _lat = null;
    _lng = null;
    _city = '';
    _district = '';
    _khoroo = '';
  });

  Future<String?> _pickTime(String? current) async {
    final parts = (current ?? '09:00').split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(picked.hour)}:${two(picked.minute)}';
  }

  void _applyDefaultHoursToOpenDays() => setState(() {
    _days = [
      for (final d in _days)
        d.isOpen ? d.copyWith(openTime: _openTime, closeTime: _closeTime) : d,
    ];
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BranchFormController>();
    final b = c.branch;
    if (!_filled && c.detail is! AsyncLoading) {
      if (b != null) _fill(b);
      _filled = c.detail is! AsyncError;
    }
    final canSave = c.isEdit
        ? canSeeView(widget.user, 'branches.edit')
        : canSeeView(widget.user, 'branches.create');
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(title: Text(c.isEdit ? (b?.name ?? 'Салбар') : 'Шинэ салбар')),
        bottomNavigationBar: canSave && c.detail is AsyncData
            ? OpsBottomActionBar(
                children: [
                  Expanded(
                    child: OpsPrimaryButton(
                      key: const ValueKey('branch_save'),
                      label: c.isEdit ? 'Хадгалах' : 'Салбар нэмэх',
                      icon: Icons.check_rounded,
                      loading: c.saving,
                      onPressed: c.busy ? null : () => _save(c),
                    ),
                  ),
                ],
              )
            : null,
        body: AsyncStateView<BranchDetail?>(
          state: c.detail,
          onRetry: c.load,
          builder: (context, branch) => LayoutBuilder(
            builder: (context, constraints) {
              final gutter = ((constraints.maxWidth - 640) / 2).clamp(16.0, double.infinity);
              return ListView(
                padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
                children: [
                  if (branch != null) ...[
                    _StatusCard(
                      branch: branch,
                      busy: c.busy,
                      onToggle: canSeeView(widget.user, 'branches.edit')
                          ? () => _toggleActive(c, branch)
                          : null,
                      onDelete: canSeeView(widget.user, 'branches.delete') && !branch.isPrimary
                          ? () => _delete(c, branch)
                          : null,
                    ),
                    const SizedBox(height: 20),
                  ],
                  const OpsSectionLabel('Үндсэн мэдээлэл'),
                  const SizedBox(height: 8),
                  _text(c, 'name', _name, 'Салбарын нэр', enabled: canSave),
                  _text(
                    c,
                    'phone',
                    _phone,
                    'Утас (заавал биш)',
                    enabled: canSave,
                    keyboard: TextInputType.phone,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                  ),
                  OpsCard(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile(
                      key: const ValueKey('branch_primary'),
                      title: const Text('Үндсэн салбар'),
                      subtitle: Text(
                        branch?.isPrimary == true
                            ? 'Үндсэнийг солихын тулд өөр салбарыг үндсэн болгоно уу.'
                            : 'Байгууллагад нэг л үндсэн салбар байна.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _isPrimary,
                      onChanged: canSave && branch?.isPrimary != true
                          ? (v) => setState(() => _isPrimary = v)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const OpsSectionLabel('Бизнесийн төрөл'),
                  const SizedBox(height: 8),
                  _TagPicker(
                    options: c.tagOptions,
                    selected: _tagIds,
                    loadError: c.tagsError,
                    error: c.fieldErrors['tagIds'],
                    required: !c.isEdit,
                    onToggle: canSave
                        ? (id) {
                            setState(() {
                              _tagIds = {..._tagIds};
                              if (!_tagIds.remove(id)) _tagIds.add(id);
                            });
                            c.clearFieldError('tagIds');
                          }
                        : null,
                  ),
                  const SizedBox(height: 20),
                  const OpsSectionLabel('Байршил'),
                  const SizedBox(height: 8),
                  _LocationCard(
                    lat: _lat,
                    lng: _lng,
                    region: [_city, _district, _khoroo].where((s) => s.isNotEmpty).join(', '),
                    resolving: _resolvingAddress,
                    error: c.fieldErrors['latitude'] ?? c.fieldErrors['longitude'],
                    onPick: canSave ? () => _pickLocation(c) : null,
                    onClear: canSave && _lat != null ? _clearLocation : null,
                  ),
                  const SizedBox(height: 12),
                  _text(
                    c,
                    'address',
                    _address,
                    'Дэлгэрэнгүй хаяг (гудамж, тоот, баримжаа)',
                    enabled: canSave,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  const OpsSectionLabel('Ажлын цаг'),
                  const SizedBox(height: 8),
                  _DefaultHours(
                    open: _openTime,
                    close: _closeTime,
                    error: c.fieldErrors['openTime'] ?? c.fieldErrors['closeTime'],
                    enabled: canSave,
                    onPickOpen: () async {
                      final v = await _pickTime(_openTime);
                      if (v != null) setState(() => _openTime = v);
                    },
                    onPickClose: () async {
                      final v = await _pickTime(_closeTime);
                      if (v != null) setState(() => _closeTime = v);
                    },
                    onApplyAll: _applyDefaultHoursToOpenDays,
                  ),
                  const SizedBox(height: 10),
                  OpsGroup(
                    children: [
                      for (var i = 0; i < _days.length; i++)
                        _DayRow(
                          day: _days[i],
                          error:
                              c.fieldErrors['schedule_${_days[i].weekday.code}_openTime'] ??
                              c.fieldErrors['schedule_${_days[i].weekday.code}_closeTime'],
                          enabled: canSave,
                          onToggle: (open) => setState(() {
                            _days = [..._days];
                            _days[i] = open
                                ? _days[i].copyWith(
                                    isOpen: true,
                                    openTime: _days[i].openTime ?? _openTime,
                                    closeTime: _days[i].closeTime ?? _closeTime,
                                  )
                                : _days[i].copyWith(isOpen: false);
                          }),
                          onPickOpen: () async {
                            final v = await _pickTime(_days[i].openTime ?? _openTime);
                            if (v != null) {
                              setState(() {
                                _days = [..._days];
                                _days[i] = _days[i].copyWith(openTime: v);
                              });
                            }
                          },
                          onPickClose: () async {
                            final v = await _pickTime(_days[i].closeTime ?? _closeTime);
                            if (v != null) {
                              setState(() {
                                _days = [..._days];
                                _days[i] = _days[i].copyWith(closeTime: v);
                              });
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const OpsSectionLabel('Онлайн цаг захиалга'),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _text(
                          c,
                          'slotMinutes',
                          _slotMinutes,
                          'Нэг цагийн урт (мин)',
                          enabled: canSave,
                          hint: '30',
                          helper: '5–480',
                          keyboard: TextInputType.number,
                          formatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _text(
                          c,
                          'slotCapacity',
                          _slotCapacity,
                          'Зэрэг авах захиалга',
                          enabled: canSave,
                          hint: '1',
                          helper: '1–100',
                          keyboard: TextInputType.number,
                          formatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Онлайн цаг захиалга авах эсэхийг «Байгууллагын тохиргоо»-ноос бүх салбарт '
                    'нэг дор асаана. Хоосон орхивол 30 минут, 1 захиалга.',
                    style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _text(
    BranchFormController c,
    String key,
    TextEditingController controller,
    String label, {
    required bool enabled,
    String? hint,
    String? helper,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey('branch_$key'),
      controller: controller,
      enabled: enabled,
      keyboardType: keyboard,
      inputFormatters: formatters,
      minLines: 1,
      maxLines: maxLines,
      onChanged: (_) => c.clearFieldError(key),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        errorText: c.fieldErrors[key],
        errorMaxLines: 3,
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.branch,
    required this.busy,
    required this.onToggle,
    required this.onDelete,
  });

  final BranchDetail branch;
  final bool busy;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    // An active primary branch cannot be deactivated (PRIMARY_LOCKED).
    final canToggle = onToggle != null && !(branch.isPrimary && branch.isActive);
    return OpsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (branch.isPrimary) const OpsPill('Үндсэн', tone: OpsTone.accent),
              OpsPill(
                branch.isActive ? 'Идэвхтэй' : 'Идэвхгүй',
                tone: branch.isActive ? OpsTone.ok : OpsTone.neutral,
              ),
              OpsPill('${branch.employeeCount} ажилтан', icon: Icons.badge_outlined),
            ],
          ),
          if (canToggle || onDelete != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (canToggle)
                  OutlinedButton.icon(
                    key: const ValueKey('branch_toggle_active'),
                    onPressed: busy ? null : onToggle,
                    icon: Icon(
                      branch.isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 18,
                    ),
                    label: Text(branch.isActive ? 'Идэвхгүй болгох' : 'Идэвхжүүлэх'),
                  ),
                if (onDelete != null)
                  TextButton.icon(
                    key: const ValueKey('branch_delete'),
                    onPressed: busy ? null : onDelete,
                    style: TextButton.styleFrom(foregroundColor: t.danger),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Устгах'),
                  ),
              ],
            ),
          ],
          if (branch.isPrimary) ...[
            const SizedBox(height: 8),
            Text(
              'Үндсэн салбарыг идэвхгүй болгох, устгахын тулд эхлээд өөр салбарыг үндсэн болгоно уу.',
              style: TextStyle(fontSize: 12, color: t.mutedText),
            ),
          ],
        ],
      ),
    );
  }
}

class _TagPicker extends StatelessWidget {
  const _TagPicker({
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.required,
    this.loadError,
    this.error,
  });

  final List<BranchTag> options;
  final Set<String> selected;
  final ValueChanged<String>? onToggle;
  final bool required;
  final String? loadError;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (options.isEmpty)
          Text(
            loadError ?? 'Сонгох шошго алга.',
            style: TextStyle(fontSize: 13, color: t.mutedText),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in options)
                FilterChip(
                  key: ValueKey('branch_tag_${tag.id}'),
                  label: Text(tag.name),
                  selected: selected.contains(tag.id),
                  onSelected: onToggle == null ? null : (_) => onToggle!(tag.id),
                ),
            ],
          ),
        const SizedBox(height: 6),
        Text(
          error ??
              (required
                  ? 'Ядаж нэгийг сонгоно уу — каталогт бизнесийн төрлөөр шүүхэд хэрэглэнэ.'
                  : 'Каталогт бизнесийн төрлөөр шүүхэд хэрэглэнэ.'),
          style: TextStyle(fontSize: 12, color: error != null ? t.danger : t.mutedText),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.lat,
    required this.lng,
    required this.region,
    required this.resolving,
    required this.onPick,
    required this.onClear,
    this.error,
  });

  final double? lat;
  final double? lng;
  final String region;
  final bool resolving;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final has = lat != null && lng != null;
    return OpsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                has ? Icons.place_rounded : Icons.place_outlined,
                color: has ? t.accent : t.mutedText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      !has
                          ? 'Байршил тэмдэглээгүй'
                          : resolving
                          ? 'Хаяг тодорхойлж байна…'
                          : region.isNotEmpty
                          ? region
                          : 'Тэмдэглэсэн байршил',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink),
                    ),
                    if (has)
                      Text(
                        '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}',
                        style: opsMono(context, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (onPick != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('branch_pick_location'),
                  onPressed: onPick,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: Text(has ? 'Өөрчлөх' : 'Газрын зураг дээр сонгох'),
                ),
                if (onClear != null)
                  TextButton(onPressed: onClear, child: const Text('Арилгах')),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error!, style: TextStyle(fontSize: 12, color: t.danger)),
          ],
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.value, required this.onTap, super.key});

  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: t.panel2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.border),
        ),
        child: Text(value, style: opsMono(context, fontSize: 13, color: t.ink)),
      ),
    );
  }
}

class _DefaultHours extends StatelessWidget {
  const _DefaultHours({
    required this.open,
    required this.close,
    required this.enabled,
    required this.onPickOpen,
    required this.onPickClose,
    required this.onApplyAll,
    this.error,
  });

  final String open;
  final String close;
  final bool enabled;
  final VoidCallback onPickOpen;
  final VoidCallback onPickClose;
  final VoidCallback onApplyAll;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return OpsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Үндсэн цаг', style: TextStyle(fontSize: 14, color: t.ink)),
              ),
              _TimeChip(
                key: const ValueKey('branch_default_open'),
                value: open,
                onTap: enabled ? onPickOpen : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('–', style: TextStyle(color: t.mutedText)),
              ),
              _TimeChip(
                key: const ValueKey('branch_default_close'),
                value: close,
                onTap: enabled ? onPickClose : null,
              ),
            ],
          ),
          if (enabled)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onApplyAll,
                child: const Text('Нээлттэй бүх өдөрт хэрэглэх'),
              ),
            ),
          if (error != null) Text(error!, style: TextStyle(fontSize: 12, color: t.danger)),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.enabled,
    required this.onToggle,
    required this.onPickOpen,
    required this.onPickClose,
    this.error,
  });

  final BranchDaySchedule day;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickOpen;
  final VoidCallback onPickClose;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(day.weekday.label, style: TextStyle(fontSize: 14, color: t.ink)),
              ),
              Expanded(
                child: day.isOpen
                    ? Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _TimeChip(
                            value: day.openTime ?? '--:--',
                            onTap: enabled ? onPickOpen : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text('–', style: TextStyle(color: t.mutedText)),
                          ),
                          _TimeChip(
                            value: day.closeTime ?? '--:--',
                            onTap: enabled ? onPickClose : null,
                          ),
                        ],
                      )
                    : Text('Амарна', style: TextStyle(fontSize: 13, color: t.mutedText)),
              ),
              Switch(
                key: ValueKey('branch_day_${day.weekday.code}'),
                value: day.isOpen,
                onChanged: enabled ? onToggle : null,
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(error!, style: TextStyle(fontSize: 12, color: t.danger)),
            ),
        ],
      ),
    );
  }
}
