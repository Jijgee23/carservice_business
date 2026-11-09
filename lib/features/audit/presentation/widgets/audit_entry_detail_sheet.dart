import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/audit/domain/audit_log.dart';
import 'package:carservice_business/features/audit/presentation/widgets/audit_vocab.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Detail sheet for one [AuditLogEntry] — shows `before`/`after` pretty
/// printed. The server (`lib/audit-redact.ts`) has already dropped any
/// secret-named key at any depth before this ever reaches the client; this
/// sheet only renders whatever JSON it is given, never re-derives redaction.
class AuditEntryDetailSheet extends StatelessWidget {
  const AuditEntryDetailSheet({super.key, required this.entry});

  final AuditLogEntry entry;

  static Future<void> show(BuildContext context, AuditLogEntry entry) {
    return AppNav.sheet<void>(
      AuditEntryDetailSheet(entry: entry),
      backgroundColor: Colors.transparent,
    );
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _pretty(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return '—';
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXL)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.summary ??
                          (e.action == null
                              ? 'Аудит бичлэг'
                              : auditActionLabel(e.action!)),
                      style: context.textStyles.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmtDate(e.createdAt),
                      style: context.textStyles.caption,
                    ),
                    const SizedBox(height: 16),
                    _KeyValueRow(
                      label: 'Обьект',
                      value: e.entity == null
                          ? '—'
                          : auditEntityLabel(e.entity!),
                    ),
                    _KeyValueRow(
                      label: 'Обьектын ID',
                      value: e.entityId ?? '—',
                    ),
                    _KeyValueRow(
                      label: 'Үйлдэл',
                      value: e.action == null
                          ? '—'
                          : auditActionLabel(e.action!),
                    ),
                    _KeyValueRow(
                      label: 'Хэрэглэгч',
                      value: e.user?.displayName ?? 'Систем',
                    ),
                    if (e.branchId != null)
                      _KeyValueRow(label: 'Салбар', value: e.branchId!),
                    const SizedBox(height: 20),
                    Text('Өмнөх утга', style: context.textStyles.captionMedium),
                    const SizedBox(height: 6),
                    _JsonBlock(text: _pretty(e.before)),
                    const SizedBox(height: 16),
                    Text('Шинэ утга', style: context.textStyles.captionMedium),
                    const SizedBox(height: 6),
                    _JsonBlock(text: _pretty(e.after)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: context.textStyles.caption),
        ),
        Expanded(child: Text(value, style: context.textStyles.body)),
      ],
    ),
  );
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.colors.background,
      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
      border: Border.all(color: context.colors.divider),
    ),
    child: SelectableText(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: context.colors.textPrimary,
      ),
    ),
  );
}
