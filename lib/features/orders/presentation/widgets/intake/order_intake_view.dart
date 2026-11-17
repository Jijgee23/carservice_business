import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/media_url.dart';
import 'package:carservice_business/features/orders/domain/order_intake.dart';
import 'package:carservice_business/features/orders/domain/order_settings.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Детайл дэлгэцийн унших-зөвхөн «Хүлээн авах» мөр. `intake == null` үед
/// ямар ч зүйл харуулахгүй.
class OrderIntakeTile extends StatelessWidget {
  const OrderIntakeTile({super.key, required this.intake});

  final OrderIntake? intake;

  @override
  Widget build(BuildContext context) {
    final i = intake;
    if (i == null) return const SizedBox.shrink();
    return Material(
      color: context.opsSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        side: BorderSide(color: context.opsDivider),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: const ValueKey('order_detail_intake_tile'),
        leading: Icon(Icons.assignment_outlined, color: context.opsPrimary),
        title: const Text('Хүлээн авах'),
        subtitle: Text(
          '${i.mileageKm != null ? '${formatMileageKm(i.mileageKm!)} · ' : ''}'
          '${i.photos.length} зураг'
          '${i.signatureUrl != null ? ' · гарын үсэгтэй' : ''}'
          '${i.checklist.isNotEmpty ? ' · шалгах жагсаалт' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => OrderIntakePage(intake: i)),
        ),
      ),
    );
  }
}

/// Бүтэн дэлгэцийн унших-зөвхөн хүлээн авалтын харагдац.
class OrderIntakePage extends StatelessWidget {
  const OrderIntakePage({super.key, required this.intake});

  final OrderIntake intake;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return Scaffold(
      backgroundColor: context.opsBackground,
      appBar: AppBar(title: const Text('Хүлээн авах')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (intake.recordedBy != null)
            Text(
              'Бүртгэсэн: ${intake.recordedBy}',
              key: const ValueKey('intake_recorded_by'),
              style: context.textStyles.body,
            ),
          Text(
            'Огноо: ${fmt.format(intake.recordedAt)}',
            style: context.textStyles.caption,
          ),
          if (intake.mileageKm != null) ...[
            Text(
              'Гүйлт: ${formatMileageKm(intake.mileageKm!)}',
              key: const ValueKey('intake_mileage_text'),
              style: context.textStyles.body,
            ),
          ],
          const SizedBox(height: 16),
          if (intake.checklist.isNotEmpty) ...[
            Text('Шалгах жагсаалт', style: context.textStyles.caption),
            const SizedBox(height: 4),
            for (final c in intake.checklist) _ChecklistRow(entry: c),
            const SizedBox(height: 16),
          ],
          if (intake.notes != null && intake.notes!.isNotEmpty) ...[
            Text('Тэмдэглэл', style: context.textStyles.caption),
            const SizedBox(height: 4),
            Text(
              intake.notes!,
              key: const ValueKey('intake_notes_text'),
              style: context.textStyles.body,
            ),
            const SizedBox(height: 16),
          ],
          if (intake.photos.isNotEmpty) ...[
            Text(
              'Зураг (${intake.photos.length})',
              style: context.textStyles.caption,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: PageView.builder(
                key: const ValueKey('intake_photo_pager'),
                itemCount: intake.photos.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _NetImage(
                    url: intake.photos[index].url,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (intake.signatureUrl != null) ...[
            Text('Гарын үсэг', style: context.textStyles.caption),
            const SizedBox(height: 8),
            Container(
              height: 140,
              color: Colors.white,
              child: _NetImage(url: intake.signatureUrl!, fit: BoxFit.contain),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.entry});

  final IntakeChecklistEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.status) {
      ChecklistStatus.OK => context.opsGood,
      ChecklistStatus.ISSUE => context.opsDanger,
      ChecklistStatus.NA => context.opsTextSecondary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(entry.label, style: context.textStyles.body)),
              const SizedBox(width: 8),
              Text(
                entry.status.label,
                style: context.textStyles.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (entry.note != null)
            Text(entry.note!, style: context.textStyles.caption),
        ],
      ),
    );
  }
}

class _NetImage extends StatelessWidget {
  const _NetImage({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      resolveMediaUrl(url),
      fit: fit,
      errorBuilder: (_, _, _) => Center(
        child: Icon(Icons.broken_image_outlined, color: context.opsTextHint),
      ),
    );
  }
}
