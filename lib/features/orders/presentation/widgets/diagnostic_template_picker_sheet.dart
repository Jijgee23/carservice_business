import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/features/diagnostics/data/diagnostic_repository.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/new_inspection_screen.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

/// Opens the diagnostic form for an order's DIAGNOSTIC [item]: its own
/// template, or one picked from [DiagnosticTemplatePickerSheet]. Completes
/// once the form is done or abandoned, so the caller can reload.
Future<void> openOrderDiagnostic(
  BuildContext context, {
  required String orderId,
  required ServiceItem item,
  required VehicleSummary vehicle,
  required CustomerSummary customer,
}) async {
  final templateId =
      item.diagnosticTemplateId ??
      await AppNav.sheet<String>(
        const DiagnosticTemplatePickerSheet(),
        backgroundColor: Colors.transparent, // the sheet paints its own surface
      );
  if (templateId == null || !context.mounted) return;
  await NewInspectionScreen.pushFromOrder(
    context,
    orderId: orderId,
    itemId: item.id,
    vehicle: vehicle,
    customer: customer,
    templateId: templateId,
  );
}

/// Lists the tenant's active diagnostic templates; pops the picked id.
class DiagnosticTemplatePickerSheet extends StatefulWidget {
  const DiagnosticTemplatePickerSheet({super.key});

  @override
  State<DiagnosticTemplatePickerSheet> createState() =>
      _DiagnosticTemplatePickerSheetState();
}

class _DiagnosticTemplatePickerSheetState
    extends State<DiagnosticTemplatePickerSheet> {
  List<DiagnosticTemplateSummary>? _templates;
  bool _loading = true;
  final _repo = DiagnosticRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _repo.getTemplates();
    if (mounted) {
      setState(() {
        _templates = result;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXL),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.opsDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.opsAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.post_add_outlined,
                    size: 16,
                    color: context.opsAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Оношилгооны загвар', style: context.textStyles.h3),
                    Text(
                      'Загвараа сонгоно уу',
                      style: context.textStyles.caption,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Body
          Flexible(
            child: _loading
                ? const AppLoading(padding: EdgeInsets.all(32))
                : (_templates == null || _templates!.isEmpty)
                ? Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Идэвхтэй загвар олдсонгүй.\nВеб дашбоардаас загвар үүсгэнэ үү.',
                        textAlign: TextAlign.center,
                        style: context.textStyles.body.copyWith(
                          color: context.opsTextSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.only(bottom: bottom + 16),
                    itemCount: _templates!.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) {
                      final t = _templates![i];
                      return _TemplateRow(
                        template: t,
                        onTap: () => AppNav.back(t.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  final DiagnosticTemplateSummary template;
  final VoidCallback onTap;
  const _TemplateRow({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = template.type;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.diagnosticTypeBackground(type),
                borderRadius: BorderRadius.circular(AppDimens.radiusFull),
              ),
              child: Text(
                type.label,
                style: context.textStyles.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.diagnosticTypeColor(type),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name, style: context.textStyles.bodyMedium),
                  if (template.description != null &&
                      template.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      template.description!,
                      style: context.textStyles.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: context.opsTextHint),
          ],
        ),
      ),
    );
  }
}
