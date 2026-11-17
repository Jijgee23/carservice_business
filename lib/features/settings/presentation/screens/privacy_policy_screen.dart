import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/features/settings/presentation/widgets/legal_widgets.dart';

/// "Нууцлалын бодлого" — the same text as carservice.mn's privacy page,
/// reachable before sign-in (login footer) and from Меню → Тусламж.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const effectiveDate = '2026 оны 9-р сарын 30';

  static const _dataTypes = [
    (
      icon: Icons.person_outline_rounded,
      type: 'Холбоо барих мэдээлэл',
      example: 'Нэр, утасны дугаар, имэйл (заавал биш), профайл зураг (заавал биш)',
      purpose: 'Бүртгэл, нэвтрэлт, баталгаажуулалт, цаг захиалгын холбоо',
    ),
    (
      icon: Icons.directions_car_outlined,
      type: 'Тээврийн хэрэгсэл',
      example: 'Улсын дугаар, арлын дугаар (VIN), марк, загвар, он, өнгө, гүйлт',
      purpose: 'Цаг захиалга, үйлчилгээний түүх, сануулга',
    ),
    (
      icon: Icons.build_outlined,
      type: 'Үйлчилгээний мэдээлэл',
      example:
          'Цаг захиалга, засварын хуудас, оношилгооны тайлан ба зураг, '
          'санал хүсэлт',
      purpose: 'Үйлчилгээ үзүүлэх, түүх харуулах, дэмжлэг',
    ),
    (
      icon: Icons.receipt_long_outlined,
      type: 'Төлбөрийн мэдээлэл',
      example: 'Нэхэмжлэлийн дугаар, дүн, төлөв, огноо',
      purpose: 'Цаг захиалгын хураамж, үйлчилгээний төлбөр баталгаажуулах',
    ),
    (
      icon: Icons.place_outlined,
      type: 'Байршил',
      example: 'Ойролцоо байршил — зөвхөн та "Ойролцоох" хайлт ашиглах үед',
      purpose: 'Танд ойр үйлчилгээний газрыг харуулах',
    ),
    (
      icon: Icons.phone_iphone_rounded,
      type: 'Төхөөрөмж ба нэвтрэлт',
      example:
          'Суулгалтын ID, төхөөрөмжийн загвар, үйлдлийн систем, push token, '
          'IP хаяг, нэвтэрсэн цаг',
      purpose: 'Push мэдэгдэл, нэвтрэлтийн аюулгүй байдал, төхөөрөмж удирдах',
    ),
  ];

  static const _permissions = [
    (
      icon: Icons.near_me_outlined,
      title: 'Байршил',
      body:
          'Ойролцоох үйлчилгээний газар хайх. Зөвхөн хайлт хийх үед '
          'ашиглагдана. Арын горимд (background) байршил цуглуулахгүй, таны '
          'профайлд хадгалахгүй.',
    ),
    (
      icon: Icons.photo_camera_outlined,
      title: 'Камер ба зургийн сан',
      body:
          'Профайл зураг, оношилгооны зураг, санал хүсэлтийн дэлгэцийн зураг '
          'хавсаргах. Зөвхөн таны сонгосон зургийг илгээнэ.',
    ),
    (
      icon: Icons.notifications_none_rounded,
      title: 'Мэдэгдэл',
      body: 'Цаг захиалгын баталгаажуулалт, сануулга, засварын явц.',
    ),
  ];

  static const _partners = [
    (
      name: 'Google Firebase Cloud Messaging',
      purpose: 'Push мэдэгдэл хүргэх',
      data: 'push token, мэдэгдлийн агуулга',
    ),
    (
      name: 'sendsms.mn / CallPro (messagepro.mn)',
      purpose: 'SMS баталгаажуулах код, сануулга илгээх',
      data: 'утасны дугаар',
    ),
    (
      name: 'QPay',
      purpose: 'Төлбөр хүлээн авах. Картын мэдээллийг бид харахгүй, хадгалахгүй.',
      data: 'нэхэмжлэл, дүн',
    ),
    (
      name: 'МАК-ын тээврийн хэрэгслийн бүртгэлийн систем (HUR)',
      purpose: 'Улсын дугаараар машины мэдээлэл татах',
      data: 'улсын дугаар',
    ),
    (
      name: 'Google Maps',
      purpose: 'Газрын зураг, байршил харуулах',
      data: 'IP хаяг, ойролцоо байршил',
    ),
    (
      name: 'ebarimt.mn',
      purpose: 'Байгууллага бүртгүүлэхэд регистрийн дугаараар нэр шалгах',
      data: 'зөвхөн байгууллагад',
    ),
  ];

  static const _retention = [
    (label: 'Бүртгэлийн мэдээлэл', value: 'Таныг бүртгэлээ устгах хүртэл'),
    (label: 'Нэг удаагийн баталгаажуулах код', value: 'Хэдхэн минут'),
    (label: 'Уншсан мэдэгдэл', value: '90 хоног'),
    (
      label: 'Төлбөр, үйлчилгээний баримт',
      value: 'Нягтлан бодох бүртгэлийн хуульд заасан хугацаанд',
    ),
    (
      label: 'Нэвтрэлт, аудитын бүртгэл',
      value: 'Аюулгүй байдлын зорилгоор хязгаарлагдмал хугацаанд',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background,
    appBar: AppBar(title: const Text('Нууцлалын бодлого')),
    body: const PrivacyPolicyBody(),
  );
}

/// The policy text on its own, for any page that needs to show it.
class PrivacyPolicyBody extends StatelessWidget {
  const PrivacyPolicyBody({super.key});

  @override
  Widget build(BuildContext context) => LegalDocumentView(
    title: 'Нууцлалын бодлого',
    effectiveDate: PrivacyPolicyScreen.effectiveDate,
    children: _sections(context),
  );

  List<Widget> _sections(BuildContext context) => [
    const LegalSection(
      number: 1,
      title: 'Бидний тухай',
      children: [
        LegalPara(
          'Энэхүү бодлого нь Carservice вэб сайт (carservice.mn) болон iOS, '
          'Android гар утасны аппликейшнд (цаашид "Үйлчилгээ") хамаарна. '
          'Үйлчилгээг Инфосистемс ХХК (Infosystems LLC, infosystems.mn) '
          'хөгжүүлж, ажиллуулдаг бөгөөд таны хувийн мэдээллийг хариуцагч нь '
          'мөн болно.',
        ),
        LegalPara(
          'Үйлчилгээ нь хоёр төрлийн хэрэглэгчтэй: машинаа үйлчилгээнд '
          'бүртгүүлдэг хэрэглэгч, мөн авто үйлчилгээний газрын ажилтан. Энэ '
          'бодлого хоёуланд нь хамаарна.',
        ),
      ],
    ),
    LegalSection(
      number: 2,
      title: 'Бидний цуглуулдаг мэдээлэл',
      children: [
        const LegalPara(
          'Бид Үйлчилгээ ажиллуулахад шаардлагатай мэдээллийг л цуглуулна. '
          'Ихэнхийг нь та өөрөө оруулна; заримыг нь таныг Үйлчилгээ ашиглах '
          'үед автоматаар бүртгэнэ.',
        ),
        for (final d in PrivacyPolicyScreen._dataTypes)
          LegalItemCard(
            icon: d.icon,
            title: d.type,
            rows: [('Жишээ', d.example), ('Зорилго', d.purpose)],
          ),
        const LegalPara(
          'Ажилтны хувьд дээрхээс гадна ажлын эрх, салбар, ажлын хуваарь, '
          'хийсэн ажлын бүртгэл хадгалагдана. Нууц үгийг зөвхөн нэг талын '
          'hash хэлбэрээр хадгалдаг тул бид харах боломжгүй.',
        ),
        const LegalNote(
          icon: Icons.block_rounded,
          text:
              'Бид таны харилцагчдын жагсаалт, мессеж, эрүүл мэндийн '
              'мэдээлэл, картын дугаарыг цуглуулахгүй.',
        ),
      ],
    ),
    LegalSection(
      number: 3,
      title: 'Төхөөрөмжийн зөвшөөрөл',
      children: [
        const LegalPara(
          'Аппликейшн дараах зөвшөөрлийг зөвхөн тухайн боломжийг ашиглах үед '
          'асууна. Та татгалзсан ч бусад хэсэг хэвийн ажиллана. Мөн утасныхаа '
          'тохиргооноос хүссэн үедээ цуцалж болно.',
        ),
        for (final p in PrivacyPolicyScreen._permissions)
          LegalItemCard(icon: p.icon, title: p.title, body: p.body),
      ],
    ),
    const LegalSection(
      number: 4,
      title: 'Мэдээллийг ашиглах зорилго',
      children: [
        LegalBullets([
          'Бүртгэл үүсгэх, нэвтрүүлэх, утас/имэйлээ баталгаажуулах.',
          'Цаг захиалгыг сонгосон үйлчилгээний газарт дамжуулах, '
              'баталгаажуулах, төлбөр боловсруулах.',
          'Үйлчилгээний түүх, оношилгооны тайланг танд харуулах.',
          'SMS болон push мэдэгдэл илгээх (баталгаажуулалт, сануулга).',
          'Аюулгүй байдлыг хангах, залилан болон зүй бус хэрэглээнээс '
              'сэргийлэх, алдаа засах.',
          'Хуулиар хүлээсэн үүргээ биелүүлэх (нягтлан бодох бүртгэл г.м.).',
        ]),
        LegalNote(
          icon: Icons.verified_user_outlined,
          text:
              'Бид таны мэдээллийг зар сурталчилгаанд ашиглахгүй, бусад '
              'компанийн апп болон вэб дээр таныг мөрдөхгүй (tracking '
              'хийхгүй), гуравдагч этгээдэд зарахгүй. Үйлчилгээнд зар '
              'сурталчилгааны болон аналитикийн гуравдагч SDK байхгүй.',
        ),
      ],
    ),
    LegalSection(
      number: 5,
      title: 'Мэдээлэл хуваалцах',
      children: [
        const LegalSubHeading('Үйлчилгээний газар'),
        const LegalPara(
          'Та цаг захиалах эсвэл үйлчилгээ авахад таны нэр, утас, машины '
          'мэдээлэл, захиалгын дэлгэрэнгүй тухайн авто үйлчилгээний газарт '
          'очно. Тэд энэ мэдээллийг өөрийн харилцагчийн бүртгэлд хадгалж, '
          'үйлчилгээ үзүүлэхэд ашиглана.',
        ),
        const LegalSubHeading('Үйлчилгээ үзүүлэгч түншүүд'),
        const LegalPara(
          'Дараах түншүүд бидний өмнөөс, зөвхөн дурдсан зорилгоор мэдээлэл '
          'боловсруулна:',
        ),
        for (final p in PrivacyPolicyScreen._partners)
          LegalItemCard(title: p.name, rows: [('Зорилго', p.purpose), ('Мэдээлэл', p.data)]),
        const LegalSubHeading('Хууль ёсны шаардлага'),
        const LegalPara(
          'Монгол Улсын хууль тогтоомжийн дагуу эрх бүхий байгууллагын албан '
          'ёсны шаардлагаар мэдээлэл өгч болно.',
        ),
      ],
    ),
    LegalSection(
      number: 6,
      title: 'Хадгалах хугацаа',
      children: [
        AppCard(
          child: Column(
            children: [
              for (final (i, r) in PrivacyPolicyScreen._retention.indexed) ...[
                if (i > 0) const Divider(height: 20),
                LegalKeyValue(label: r.label, value: r.value),
              ],
            ],
          ),
        ),
      ],
    ),
    const LegalSection(
      number: 7,
      title: 'Аюулгүй байдал',
      children: [
        LegalPara(
          'Мэдээллийг HTTPS шифрлэлтээр дамжуулж, хандалтын хяналттай '
          'серверт хадгална. Байгууллага бүрийн өгөгдөл өгөгдлийн сангийн '
          'түвшинд тусгаарлагдсан, нууц үг hash хэлбэрээр хадгалагдана. Та '
          'нэвтэрсэн төхөөрөмжүүдээ харж, хүссэнээсээ гарах боломжтой. '
          'Интернэтээр дамжуулах ямар ч арга 100% аюулгүй биш тул эрсдэлийг '
          'бүрэн арилгана гэж баталж чадахгүй.',
        ),
      ],
    ),
    LegalSection(
      number: 8,
      title: 'Таны эрх ба сонголт',
      children: [
        const LegalBullets([
          'Профайлаасаа мэдээллээ харах, засах.',
          'Push мэдэгдлийг утасны тохиргооноос унтраах, байршил болон '
              'камерын зөвшөөрлийг цуцлах.',
          'Бүртгэлээ түр идэвхгүй болгох эсвэл бүрмөсөн устгах (доор).',
          'Мэдээллийнхээ хуулбарыг авах, ашиглалтыг хязгаарлах хүсэлтээ '
              '$legalContactEmail хаягаар илгээх. Бид 30 хоногийн дотор хариулна.',
        ]),
        LegalLinkRow(
          icon: Icons.mail_outline_rounded,
          label: legalContactEmail,
          onTap: () => openLegalLink(legalMailto()),
        ),
      ],
    ),
    LegalSection(
      number: 9,
      title: 'Бүртгэл устгах',
      children: [
        const LegalPara('Бүртгэлээ хоёр аргаар устгаж болно:'),
        const LegalItemCard(
          icon: Icons.phone_iphone_rounded,
          title: 'Аппликейшнээс',
          body: 'Профайл → Бүртгэл хаах → Бүртгэл устгах.',
        ),
        LegalItemCard(
          icon: Icons.language_rounded,
          title: 'Апп суулгаагүй бол',
          body:
              'carservice.mn/account-deletion хуудсанд утасны дугаараа '
              'баталгаажуулж устгана.',
          onTap: () => openLegalLink(Uri.parse(legalDeletionUrl)),
        ),
        const LegalSubHeading('Шууд устгагдах мэдээлэл'),
        const LegalPara(
          'Нэр, утас, имэйл, профайл зураг, нууц үг, "Миний машин" жагсаалт, '
          'мэдэгдэл, бүртгэлтэй төхөөрөмж, push token.',
        ),
        const LegalSubHeading('Хадгалагдах мэдээлэл'),
        const LegalBullets([
          'Таны үйлчилгээ авсан газрын өөрийн харилцагчийн бүртгэл, '
              'засварын түүх, төлбөрийн баримт — хуулийн дагуу, таны '
              'бүртгэлтэй холбоогүйгээр.',
          'Ажилтны хувьд байгууллагын түүхэнд хийсэн ажил нь "Устгагдсан '
              'ажилтан" нэрээр, аудитын бүртгэлд нэр нь хадгалагдана.',
        ]),
        const LegalNote(
          icon: Icons.warning_amber_rounded,
          warning: true,
          text:
              'Устгасан бүртгэлийг сэргээх боломжгүй. Түр идэвхгүй болгох нь '
              'устгахаас өөр — дахин нэвтэрснээр бүртгэл сэргэнэ.',
        ),
      ],
    ),
    const LegalSection(
      number: 10,
      title: 'Хүүхдийн нууцлал',
      children: [
        LegalPara(
          'Үйлчилгээ нь 16-аас доош насны хүүхдэд зориулагдаагүй бөгөөд бид '
          'тэднээс санаатайгаар мэдээлэл цуглуулахгүй. Хүүхэд мэдээлэл өгсөн '
          'нь мэдэгдвэл бидэнтэй холбогдоно уу — бид устгана.',
        ),
      ],
    ),
    const LegalSection(
      number: 11,
      title: 'Cookie',
      children: [
        LegalPara(
          'Вэб сайт зөвхөн нэвтрэлтийг хадгалах, хамгаалахад зайлшгүй '
          'шаардлагатай cookie ашиглана. Зар сурталчилгааны болон мөрдөх '
          'cookie ашиглахгүй.',
        ),
      ],
    ),
    const LegalSection(
      number: 12,
      title: 'Бодлогын өөрчлөлт',
      children: [
        LegalPara(
          'Энэхүү бодлогыг шинэчлэх бол энэ хуудасны огноог өөрчилнө. Чухал '
          'өөрчлөлтийг апп эсвэл SMS-ээр урьдчилан мэдэгдэнэ.',
        ),
      ],
    ),
    LegalSection(
      number: 13,
      title: 'Холбоо барих',
      children: [
        const LegalPara('Нууцлалтай холбоотой асуулт, хүсэлтээ дараах хаягаар илгээнэ үү:'),
        const LegalContactCard(),
      ],
    ),
  ];
}
