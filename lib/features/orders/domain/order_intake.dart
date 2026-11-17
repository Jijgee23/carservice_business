import 'package:carservice_business/features/orders/domain/order_settings.dart';

/// Хүлээн авалтын тэмдэглэл (зөвхөн захиалга үүсгэх үед бичигдэнэ, дараа нь
/// засагдахгүй).
class OrderIntakePhoto {
  const OrderIntakePhoto({required this.id, required this.url});

  final String id;

  /// Серверийн харьцангуй зам (`/uploads/...`).
  final String url;
}

class OrderIntake {
  const OrderIntake({
    this.notes,
    this.photos = const [],
    this.signatureUrl,
    required this.recordedAt,
    this.recordedBy,
    this.mileageKm,
    this.checklist = const [],
  });

  final String? notes;
  final List<OrderIntakePhoto> photos;
  final String? signatureUrl;
  final DateTime recordedAt;
  final String? recordedBy;

  /// Одометрийн заалт (км); оруулаагүй бол null.
  final int? mileageKm;

  /// Нээх үеийн шалгах жагсаалт (snapshot); бөглөөгүй бол хоосон.
  final List<IntakeChecklistEntry> checklist;
}

/// `152300` → `152,300 км`.
String formatMileageKm(int km) {
  final grouped = km.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$grouped км';
}

/// Захиалга үүсгэхэд илгээх хүлээн авалтын ноорог.
class OrderIntakeDraft {
  const OrderIntakeDraft({
    this.notes,
    this.photoPaths = const [],
    this.signaturePath,
    this.mileageKm,
    this.checklist = const [],
  });

  final String? notes;
  final List<String> photoPaths;
  final String? signaturePath;
  final int? mileageKm;

  /// Шалгах жагсаалтын хариулт — `intake`-ээс тусдаа `intakeChecklist`
  /// талбараар илгээгдэнэ.
  final List<IntakeChecklistAnswer> checklist;

  /// `intake` объект (гүйлт/тэмдэглэл/зураг/гарын үсэг) хоосон эсэх.
  bool get hasNoRecord =>
      mileageKm == null &&
      (notes == null || notes!.trim().isEmpty) &&
      photoPaths.isEmpty &&
      signaturePath == null;

  bool get isEmpty => hasNoRecord && checklist.isEmpty;

  /// `POST /orders`-ийн `intakeChecklist`.
  List<Map<String, dynamic>> checklistJson() => [
    for (final a in checklist) a.toJson(),
  ];

  Map<String, dynamic> toJson() => {
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
    if (photoPaths.isNotEmpty) 'photoPaths': photoPaths,
    if (signaturePath != null) 'signaturePath': signaturePath,
    if (mileageKm != null) 'mileageKm': mileageKm,
  };
}
