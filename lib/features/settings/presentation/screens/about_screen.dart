import 'package:carservice_business/core/services/app_version.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: Text('Тухай')),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: context.colors.brandSurface,
                borderRadius: BorderRadius.circular(AppDimens.radiusXL),
              ),
              child: Icon(
                Icons.build_circle_rounded,
                color: CarserviceTheme.of(context).onAccent,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text('Carservice Business', style: context.textStyles.h2),
          ),
          const SizedBox(height: 4),
          Center(
            child: FutureBuilder<String?>(
              future: appVersionLabel(),
              builder: (context, snapshot) => Text(
                snapshot.data == null ? '' : 'Хувилбар ${snapshot.data}',
                key: const ValueKey('about_version'),
                style: context.textStyles.caption,
              ),
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Тухай', style: context.textStyles.h3),
                const SizedBox(height: 8),
                Text(
                  'Үйлчилгээний төвийн ажилтнуудад зориулсан аппликейшн. '
                  'Засварын хуудас, цаг захиалга, оношилгоо, үйлчилгээний жагсаалт болон '
                  'төлбөрийн урсгалыг нэг дор удирдана.',
                  style: context.textStyles.body.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              children: const [
                _AboutRow(label: 'Хөгжүүлэгч', value: 'Инфосистемс ХХК'),
                Divider(height: 20),
                _AboutRow(label: 'Холбоо барих', value: 'info@infosystems.mn'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '© 2026 Инфосистемс ХХК',
              style: context.textStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: context.textStyles.caption),
        const Spacer(),
        Text(value, style: context.textStyles.bodyMedium),
      ],
    );
  }
}
