import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/features/audit/domain/audit_log.dart';
import 'package:carservice_business/features/audit/presentation/widgets/audit_vocab.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// The applied filter set — `null` means the field is cleared. Dates are
/// `YYYY-MM-DD`, matching `AuditListQuery.from`/`.to`.
class AuditFilterResult {
  const AuditFilterResult({
    this.action,
    this.entity,
    this.userId,
    this.from,
    this.to,
  });

  final String? action;
  final String? entity;
  final String? userId;
  final String? from;
  final String? to;
}

/// Filter sheet for the Audit list — action/entity/user chips from the
/// server's `meta` vocab (P7-F1's `AuditListMeta`) plus a from/to date
/// range. Vocab that the API returns but this app has no Mongolian label for
/// yet still renders (via `auditActionLabel`/`auditEntityLabel`'s raw
/// fallback) rather than being silently dropped.
class AuditFilterSheet extends StatefulWidget {
  const AuditFilterSheet({
    super.key,
    required this.meta,
    this.action,
    this.entity,
    this.userId,
    this.from,
    this.to,
  });

  final AuditListMeta meta;
  final String? action;
  final String? entity;
  final String? userId;
  final String? from;
  final String? to;

  static Future<AuditFilterResult?> show(
    BuildContext context, {
    required AuditListMeta meta,
    String? action,
    String? entity,
    String? userId,
    String? from,
    String? to,
  }) {
    return AppNav.sheet<AuditFilterResult>(
      AuditFilterSheet(
        meta: meta,
        action: action,
        entity: entity,
        userId: userId,
        from: from,
        to: to,
      ),
      backgroundColor: Colors.transparent,
    );
  }

  @override
  State<AuditFilterSheet> createState() => _AuditFilterSheetState();
}

class _AuditFilterSheetState extends State<AuditFilterSheet> {
  String? _action;
  String? _entity;
  String? _userId;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _action = widget.action;
    _entity = widget.entity;
    _userId = widget.userId;
    _from = _parseDate(widget.from);
    _to = _parseDate(widget.to);
  }

  DateTime? _parseDate(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickFrom() async {
    final picked = await AppDatePicker.single(
      context,
      initial: _from ?? DateTime.now(),
      lastDate: _to,
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await AppDatePicker.single(
      context,
      initial: _to ?? DateTime.now(),
      firstDate: _from,
    );
    if (picked != null) setState(() => _to = picked);
  }

  void _apply() {
    AppNav.back(
      AuditFilterResult(
        action: _action,
        entity: _entity,
        userId: _userId,
        from: _from == null ? null : _formatDate(_from!),
        to: _to == null ? null : _formatDate(_to!),
      ),
    );
  }

  void _clear() {
    setState(() {
      _action = null;
      _entity = null;
      _userId = null;
      _from = null;
      _to = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXL)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Шүүлтүүр', style: context.textStyles.bodyMedium),
                  TextButton(onPressed: _clear, child: const Text('Цэвэрлэх')),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.meta.actions.isNotEmpty) ...[
                        Text('Үйлдэл', style: context.textStyles.captionMedium),
                        const SizedBox(height: 8),
                        _ChipWrap(
                          options: widget.meta.actions,
                          label: auditActionLabel,
                          selected: _action,
                          onSelect: (v) => setState(() => _action = v),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (widget.meta.entities.isNotEmpty) ...[
                        Text('Обьект', style: context.textStyles.captionMedium),
                        const SizedBox(height: 8),
                        _ChipWrap(
                          options: widget.meta.entities,
                          label: auditEntityLabel,
                          selected: _entity,
                          onSelect: (v) => setState(() => _entity = v),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (widget.meta.users.isNotEmpty) ...[
                        Text(
                          'Ажилтан',
                          style: context.textStyles.captionMedium,
                        ),
                        const SizedBox(height: 8),
                        _ChipWrap(
                          options: widget.meta.users.map((u) => u.id).toList(),
                          label: (id) {
                            final u = widget.meta.users.firstWhere(
                              (u) => u.id == id,
                            );
                            final name = [
                              u.lastName,
                              u.firstName,
                            ].where((s) => s != null && s.isNotEmpty).join(' ');
                            return name.isEmpty ? id : name;
                          },
                          selected: _userId,
                          onSelect: (v) => setState(() => _userId = v),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        'Огнооны хязгаар',
                        style: context.textStyles.captionMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _DateField(
                              label: 'Эхлэх',
                              value: _from,
                              onTap: _pickFrom,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DateField(
                              label: 'Дуусах',
                              value: _to,
                              onTap: _pickTo,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: CarserviceTheme.of(context).onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    ),
                  ),
                  child: const Text('Хэрэглэх'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.options,
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final List<String> options;
  final String Function(String) label;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: options.map((value) {
      final isSelected = value == selected;
      return GestureDetector(
        onTap: () => onSelect(isSelected ? null : value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colors.accent.withValues(alpha: 0.14)
                : null,
            borderRadius: BorderRadius.circular(AppDimens.radiusFull),
            border: Border.all(
              color: isSelected
                  ? context.colors.accent
                  : context.colors.divider,
            ),
          ),
          child: Text(
            label(value),
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              color: isSelected
                  ? context.colors.accent
                  : context.colors.textSecondary,
            ),
          ),
        ),
      );
    }).toList(),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? label
        : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.colors.divider),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: context.colors.textHint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: value == null
                      ? context.colors.textHint
                      : context.colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
