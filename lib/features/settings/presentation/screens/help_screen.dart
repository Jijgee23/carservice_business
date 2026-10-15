import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = [
    (
      q: 'Шинэ оношилгоо хэрхэн үүсгэх вэ?',
      a: 'Нүүр хуудасны "Шинэ оношилгоо" цэсээр орж, тээврийн хэрэгсэл болон '
          'үйлчлүүлэгчээ сонгоод загварын дагуу бөглөнө.',
    ),
    (
      q: 'Засварын хуудасны төлбөрийг хэрхэн авах вэ?',
      a: 'Засварын хуудасны дэлгэрэнгүй хэсгээс төлбөрийн төлөвийг гараар шинэчлэх, '
          'эсвэл QPay-ээр нэхэмжлэх үүсгэж болно.',
    ),
    (
      q: 'Нууц үгээ мартсан бол?',
      a: 'Нууц үгээ өөрөө сэргээх боломжгүй. Байгууллагын админтайгаа '
          'холбогдож нууц үгээ дахин тохируулна уу.',
    ),
    (
      q: 'Мэдэгдэл ирэхгүй байна?',
      a: 'Төхөөрөмжийн тохиргооноос аппликейшний мэдэгдлийг зөвшөөрсөн эсэхээ '
          'шалгаад, дахин нэвтэрч үзнэ үү.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: Text('Тусламж')),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        children: [
          Text('Түгээмэл асуултууд', style: context.textStyles.h3),
          const SizedBox(height: 12),
          ..._faqs.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      title: Text(f.q, style: context.textStyles.bodyMedium),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(f.a, style: context.textStyles.caption.copyWith(height: 1.5)),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
          const SizedBox(height: 8),
          AppCard(
            child: Row(
              children: [
                Icon(Icons.support_agent_rounded, color: context.colors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Тусламж хэрэгтэй юу?', style: context.textStyles.bodyMedium),
                      const SizedBox(height: 2),
                      Text('info@infosystems.mn', style: context.textStyles.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
