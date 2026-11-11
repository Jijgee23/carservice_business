import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/media_url.dart';
import 'package:carservice_business/core/utils/upload_image.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/organization/domain/organization.dart';
import 'package:carservice_business/features/organization/domain/organization_repository.dart';
import 'package:carservice_business/features/organization/presentation/controllers/organization_settings_controller.dart';

/// "Байгууллагын тохиргоо" — the web's `/dashboard/settings` main card for
/// the app: logo, name/register/contacts, online booking and the cash-shift
/// requirement, the appointment reminder lead, and read-only slug/plan/date.
/// Everyone signed in may read; only the owner (`canEdit`) may change it.
class OrganizationSettingsScreen extends StatelessWidget {
  const OrganizationSettingsScreen({
    super.key,
    this.repository,
    this.refreshUser,
    this.imagePicker,
  });

  final OrganizationRepository? repository;
  final Future<void> Function()? refreshUser;
  final ImagePicker? imagePicker;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) =>
        OrganizationSettingsController(repo: repository, refreshUser: refreshUser)..load(),
    child: _Body(picker: imagePicker),
  );
}

class _Body extends StatefulWidget {
  const _Body({this.picker});

  final ImagePicker? picker;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _name = TextEditingController();
  final _regno = TextEditingController();
  final _email = TextEditingController();
  final _phone1 = TextEditingController();
  final _phone2 = TextEditingController();
  bool _acceptsOnlineBooking = false;
  bool _requireCashSession = false;
  int? _leadMinutes;

  /// The settings object the fields were last filled from.
  OrganizationSettings? _filledFrom;

  @override
  void dispose() {
    for (final c in [_name, _regno, _email, _phone1, _phone2]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(OrganizationSettings s) {
    if (identical(_filledFrom, s)) return;
    final previous = _filledFrom;
    _filledFrom = s;
    // A logo change only swaps the logo; keep what the user is typing.
    if (previous != null && _sameProfile(previous, s)) return;
    _name.text = s.name;
    _regno.text = s.registerNumber;
    _email.text = s.email ?? '';
    _phone1.text = s.phone1;
    _phone2.text = s.phone2 ?? '';
    _acceptsOnlineBooking = s.acceptsOnlineBooking;
    _requireCashSession = s.requireCashSession;
    _leadMinutes = s.appointmentReminderLeadMinutes;
  }

  static bool _sameProfile(OrganizationSettings a, OrganizationSettings b) =>
      a.name == b.name &&
      a.registerNumber == b.registerNumber &&
      a.email == b.email &&
      a.phone1 == b.phone1 &&
      a.phone2 == b.phone2 &&
      a.acceptsOnlineBooking == b.acceptsOnlineBooking &&
      a.requireCashSession == b.requireCashSession &&
      a.appointmentReminderLeadMinutes == b.appointmentReminderLeadMinutes;

  OrganizationDraft get _draft => OrganizationDraft(
    name: _name.text,
    registerNumber: _regno.text,
    email: _email.text,
    phone1: _phone1.text,
    phone2: _phone2.text,
    acceptsOnlineBooking: _acceptsOnlineBooking,
    requireCashSession: _requireCashSession,
    reminderLeadMinutes: _leadMinutes,
  );

  Future<void> _save(OrganizationSettingsController c) async {
    FocusScope.of(context).unfocus();
    final outcome = await c.save(_draft);
    if (!mounted) return;
    switch (outcome) {
      case OrganizationSaveOutcome.saved:
        messageComplete('Тохиргоо хадгалагдлаа');
      case OrganizationSaveOutcome.unchanged:
        message('Өөрчлөлт алга');
      case OrganizationSaveOutcome.failed:
        break;
    }
  }

  Future<void> _pickLogo(OrganizationSettingsController c) async {
    final picker = widget.picker ?? ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: uploadImageQuality,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image == null) return;
    if ((await filterUploadable([image])).rejected > 0) {
      messageWarning(uploadTooLargeMessage);
      return;
    }
    final error = await c.uploadLogo(image.path);
    if (!mounted) return;
    if (error != null) {
      messageError(error);
    } else {
      messageComplete('Лого шинэчлэгдлээ');
    }
  }

  Future<void> _removeLogo(OrganizationSettingsController c) async {
    final ok = await ConfirmSheet.show(
      context,
      title: 'Лого устгах уу?',
      message: 'Нэхэмжлэх, баримт болон каталогт лого харагдахаа больно.',
      confirmLabel: 'Устгах',
      icon: Icons.delete_outline_rounded,
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    final error = await c.removeLogo();
    if (!mounted) return;
    if (error != null) messageError(error);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OrganizationSettingsController>();
    final s = c.settings;
    if (s != null) _fill(s);
    final canEdit = s?.canEdit == true;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Байгууллагын тохиргоо')),
      bottomNavigationBar: canEdit
          ? OpsBottomActionBar(
              children: [
                Expanded(
                  child: OpsPrimaryButton(
                    key: const ValueKey('org_save'),
                    label: 'Хадгалах',
                    icon: Icons.check_rounded,
                    loading: c.saving,
                    onPressed: () => _save(c),
                  ),
                ),
              ],
            )
          : null,
      body: AsyncStateView<OrganizationSettings>(
        state: c.state,
        onRetry: c.load,
        builder: (context, s) => RefreshIndicator(
          onRefresh: c.load,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gutter = ((constraints.maxWidth - 640) / 2).clamp(16.0, double.infinity);
              return ListView(
                padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
                children: [
                  _LogoCard(
                    settings: s,
                    busy: c.logoBusy,
                    onPick: canEdit ? () => _pickLogo(c) : null,
                    onRemove: canEdit && s.logoUrl != null ? () => _removeLogo(c) : null,
                  ),
                  if (!canEdit) ...[
                    const SizedBox(height: 12),
                    const _Notice(
                      icon: Icons.lock_outline_rounded,
                      text: 'Тохиргоог зөвхөн байгууллагын эзэмшигч өөрчилнө.',
                    ),
                  ],
                  if (c.formError != null) ...[
                    const SizedBox(height: 12),
                    _Notice(
                      icon: Icons.error_outline_rounded,
                      text: c.formError!,
                      danger: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  const OpsSectionLabel('Үндсэн мэдээлэл'),
                  const SizedBox(height: 8),
                  _field(
                    c,
                    key: 'name',
                    controller: _name,
                    label: 'Байгууллага / хувь хүний нэр',
                    enabled: canEdit,
                  ),
                  _field(
                    c,
                    key: 'registerNumber',
                    controller: _regno,
                    label: 'Регистр',
                    enabled: canEdit,
                    helper: 'Байгууллага 7 орон, хувь хүн 2 үсэг + 8 орон',
                    capitalize: true,
                  ),
                  _field(
                    c,
                    key: 'email',
                    controller: _email,
                    label: 'Имэйл (заавал биш)',
                    enabled: canEdit,
                    keyboard: TextInputType.emailAddress,
                  ),
                  _field(
                    c,
                    key: 'phone1',
                    controller: _phone1,
                    label: 'Утас 1',
                    enabled: canEdit,
                    keyboard: TextInputType.phone,
                    digits: 8,
                  ),
                  _field(
                    c,
                    key: 'phone2',
                    controller: _phone2,
                    label: 'Утас 2 (заавал биш)',
                    enabled: canEdit,
                    keyboard: TextInputType.phone,
                    digits: 8,
                  ),
                  const SizedBox(height: 12),
                  const OpsSectionLabel('Ажиллагаа'),
                  const SizedBox(height: 8),
                  OpsGroup(
                    children: [
                      if (s.onlineBookingInPlan)
                        _SwitchRow(
                          key: const ValueKey('org_online_booking'),
                          icon: Icons.public_rounded,
                          title: 'Онлайн цаг захиалга',
                          subtitle:
                              'Идэвхжүүлбэл каталогт харагдаж, үйлчлүүлэгчид онлайнаар цаг захиална.',
                          value: _acceptsOnlineBooking,
                          onChanged: canEdit
                              ? (v) {
                                  setState(() => _acceptsOnlineBooking = v);
                                  c.clearFieldError('acceptsOnlineBooking');
                                }
                              : null,
                        ),
                      _SwitchRow(
                        key: const ValueKey('org_require_cash'),
                        icon: Icons.point_of_sale_rounded,
                        title: 'Касс заавал нээх',
                        subtitle:
                            'Асаалттай бол төлбөр бүртгэх, буцаах, тооцоо хийхийн өмнө кассын ээлжээ нээнэ.',
                        value: _requireCashSession,
                        onChanged: canEdit ? (v) => setState(() => _requireCashSession = v) : null,
                      ),
                    ],
                  ),
                  if (!s.onlineBookingInPlan) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Таны багц онлайн цаг захиалгыг дэмжихгүй байна.',
                      style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                    ),
                  ],
                  if (c.fieldErrors['acceptsOnlineBooking'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      c.fieldErrors['acceptsOnlineBooking']!,
                      style: TextStyle(fontSize: 12, color: context.colors.danger),
                    ),
                  ],
                  if (_leadMinutes != null) ...[
                    const SizedBox(height: 20),
                    const OpsSectionLabel('Цаг захиалгын сануулга'),
                    const SizedBox(height: 8),
                    _ReminderLeadPicker(
                      minutes: _leadMinutes!,
                      enabled: canEdit,
                      error: c.fieldErrors['appointmentReminderLeadMinutes'],
                      onChanged: (m) {
                        setState(() => _leadMinutes = m);
                        c.clearFieldError('appointmentReminderLeadMinutes');
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  const OpsSectionLabel('Бүртгэл'),
                  const SizedBox(height: 8),
                  OpsGroup(
                    children: [
                      OpsGroupRow(
                        icon: Icons.link_rounded,
                        title: 'Хаяг (slug)',
                        value: s.slug.isEmpty ? '—' : s.slug,
                      ),
                      OpsGroupRow(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Багц',
                        value: s.plan.isEmpty ? '—' : planLabel(s.plan),
                      ),
                      OpsGroupRow(
                        icon: Icons.event_outlined,
                        title: 'Бүртгүүлсэн',
                        value: s.createdAt == null
                            ? '—'
                            : DateFormat('yyyy.MM.dd').format(s.createdAt!),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _field(
    OrganizationSettingsController c, {
    required String key,
    required TextEditingController controller,
    required String label,
    required bool enabled,
    String? helper,
    TextInputType? keyboard,
    int? digits,
    bool capitalize = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey('org_$key'),
      controller: controller,
      enabled: enabled,
      keyboardType: keyboard,
      textCapitalization: capitalize ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: digits != null
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(digits)]
          : null,
      onChanged: (_) => c.clearFieldError(key),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: c.fieldErrors[key],
        errorMaxLines: 3,
      ),
    ),
  );
}

class _LogoCard extends StatelessWidget {
  const _LogoCard({
    required this.settings,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final OrganizationSettings settings;
  final bool busy;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final url = settings.logoUrl;
    return OpsCard(
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: t.panel2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.border),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: busy
                ? SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                  )
                : url == null
                ? Icon(Icons.storefront_outlined, size: 30, color: t.mutedText)
                : Image.network(
                    resolveMediaUrl(url),
                    key: ValueKey(url),
                    fit: BoxFit.cover,
                    width: 72,
                    height: 72,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.broken_image_outlined, size: 28, color: t.mutedText),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  'PNG, JPG, WEBP · 2MB хүртэл',
                  style: TextStyle(fontSize: 12, color: t.mutedText),
                ),
                if (onPick != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('org_logo_pick'),
                        onPressed: busy ? null : onPick,
                        icon: const Icon(Icons.upload_rounded, size: 18),
                        label: Text(url == null ? 'Лого оруулах' : 'Солих'),
                      ),
                      if (onRemove != null)
                        TextButton(
                          key: const ValueKey('org_logo_remove'),
                          onPressed: busy ? null : onRemove,
                          style: TextButton.styleFrom(foregroundColor: t.danger),
                          child: const Text('Устгах'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: t.shellBackground,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: t.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, color: t.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: t.mutedText)),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Days (0–7) + hours (0–23), whole hours between 1 h and 7 days.
class _ReminderLeadPicker extends StatelessWidget {
  const _ReminderLeadPicker({
    required this.minutes,
    required this.enabled,
    required this.onChanged,
    this.error,
  });

  final int minutes;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final days = minutes ~/ 1440;
    final hours = (minutes % 1440) ~/ 60;

    void emit(int d, int h) {
      final next = (d * 1440 + h * 60).clamp(ReminderLead.minMinutes, ReminderLead.maxMinutes);
      onChanged(next);
    }

    return OpsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('org_lead_days'),
                  initialValue: days,
                  decoration: const InputDecoration(labelText: 'Хоног'),
                  items: [
                    for (var d = 0; d <= 7; d++) DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: enabled ? (d) => emit(d ?? 0, d == 7 ? 0 : hours) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('org_lead_hours_$days'),
                  initialValue: hours,
                  decoration: const InputDecoration(labelText: 'Цаг'),
                  items: [
                    for (var h = 0; h <= (days == 7 ? 0 : 23); h++)
                      DropdownMenuItem(value: h, child: Text('$h')),
                  ],
                  onChanged: enabled ? (h) => emit(days, h ?? 0) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Баталгаажсан цаг захиалгаас ${ReminderLead.label(minutes)} өмнө үйлчлүүлэгчид '
            'SMS/мэдэгдлээр сануулна. Хамгийн багадаа 1 цаг, ихдээ 7 хоног.',
            style: TextStyle(fontSize: 12, color: t.mutedText),
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error!, style: TextStyle(fontSize: 12, color: t.danger)),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.danger = false});

  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final fg = danger ? t.danger : t.mutedText;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger ? t.danger.withValues(alpha: 0.08) : t.panel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: danger ? t.danger.withValues(alpha: 0.3) : t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: fg))),
        ],
      ),
    );
  }
}
