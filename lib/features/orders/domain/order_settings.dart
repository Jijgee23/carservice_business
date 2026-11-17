/// Засварын хуудасны тохиргоо (tenant бүр) — `GET /api/v1/tenant/order-settings`.
///
/// Нээх формын заавал талбарууд (хариуцагч, гүйлт, гарын үсэг, зургийн доод
/// тоо, шалгах жагсаалт) болон хаах дүрэм (оношилгоо, бүх ажил, төлбөр дутуу
/// хаах). Тохиргоогүй tenant-д сервер анхдагч утга (= өмнөх хатуу дүрэм)
/// буцаана; апп ч хариу ирээгүй үед [OrderSettings.defaults]-аар ажиллана.
/// Сервер үргэлж дахин шалгадаг тул энд зөвхөн UX.
library;

/// Шалгах жагсаалтын хариулт — `OK` / `ISSUE` / `NA`.
enum ChecklistStatus {
  OK('Хэвийн'),
  ISSUE('Асуудалтай'),
  NA('Хамаарахгүй');

  const ChecklistStatus(this.label);
  final String label;

  static ChecklistStatus? tryParse(Object? raw) {
    for (final s in values) {
      if (s.name == raw) return s;
    }
    return null;
  }
}

/// Tenant-ийн тодорхойлсон шалгах жагсаалтын мөр.
class ChecklistItemDef {
  const ChecklistItemDef({required this.id, required this.label});

  final String id;
  final String label;
}

/// Шалгах жагсаалтын тэмдэглэлийн дээд урт (`CHECKLIST_NOTE_MAX`).
const checklistNoteMax = 300;

class OrderSettings {
  const OrderSettings({
    this.requireAssignee = true,
    this.requireMileage = false,
    this.requireSignature = false,
    this.minIntakePhotos = 0,
    this.requireChecklist = false,
    this.intakeChecklist = const [],
    this.requireDiagnosticsFilled = true,
    this.requireItemsCompleted = true,
    this.allowCloseUnpaid = false,
    this.canEdit = false,
  });

  /// `ORDER_SETTINGS_DEFAULTS` — тохиргоогүй tenant-ийн (хуучин) дүрэм.
  static const defaults = OrderSettings();

  /// `{ settings: {...}, canEdit }`. Буруу/дутуу талбар анхдагч утгаа авна.
  factory OrderSettings.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final s = raw['settings'] is Map ? raw['settings'] as Map : const {};
    bool b(String k, bool fb) => s[k] is bool ? s[k] as bool : fb;
    final photos = s['minIntakePhotos'];
    final checklist = <ChecklistItemDef>[];
    final list = s['intakeChecklist'];
    if (list is List) {
      for (final it in list) {
        if (it is! Map) continue;
        final id = it['id'];
        final label = it['label'];
        if (id is String && id.isNotEmpty && label is String) {
          final trimmed = label.trim();
          if (trimmed.isNotEmpty) {
            checklist.add(ChecklistItemDef(id: id, label: trimmed));
          }
        }
      }
    }
    return OrderSettings(
      requireAssignee: b('requireAssignee', defaults.requireAssignee),
      requireMileage: b('requireMileage', defaults.requireMileage),
      requireSignature: b('requireSignature', defaults.requireSignature),
      minIntakePhotos: photos is num && photos >= 0 ? photos.toInt() : 0,
      requireChecklist: b('requireChecklist', defaults.requireChecklist),
      intakeChecklist: List.unmodifiable(checklist),
      requireDiagnosticsFilled: b(
        'requireDiagnosticsFilled',
        defaults.requireDiagnosticsFilled,
      ),
      requireItemsCompleted: b(
        'requireItemsCompleted',
        defaults.requireItemsCompleted,
      ),
      allowCloseUnpaid: b('allowCloseUnpaid', defaults.allowCloseUnpaid),
      canEdit: raw['canEdit'] == true,
    );
  }

  /// Хариуцах мастер заавал (false бол сонгохгүй байж болно).
  final bool requireAssignee;
  final bool requireMileage;
  final bool requireSignature;

  /// Хүлээн авалтын зургийн доод тоо (0 = заавал биш).
  final int minIntakePhotos;

  /// Шалгах жагсаалтын бүх мөрийг заавал бөглөх эсэх.
  final bool requireChecklist;
  final List<ChecklistItemDef> intakeChecklist;

  /// Хаахад бүх оношилгоо бөглөгдсөн байх.
  final bool requireDiagnosticsFilled;

  /// Хаахад бүх ажил дууссан байх (false бол сервер хаахдаа автоматаар
  /// дуусгана).
  final bool requireItemsCompleted;

  /// Ердийн засварыг үлдэгдэлтэй хаах (`orders.closeUnpaidPostpaid` эрхтэй
  /// хэрэглэгч; үлдэгдэл нь дараа тооцоо/авлага болно).
  final bool allowCloseUnpaid;

  /// Эзэн — тохиргоог засах эрхтэй.
  final bool canEdit;

  /// Шалгах жагсаалт заавал бөглөгдөх эсэх (мөргүй бол хамаарахгүй).
  bool get checklistRequired => requireChecklist && intakeChecklist.isNotEmpty;

  /// «Хүлээн авах» хэсэгт заавал бөглөх зүйл байгаа эсэх.
  bool get hasIntakeRequirements =>
      requireMileage ||
      requireSignature ||
      minIntakePhotos > 0 ||
      checklistRequired;
}

/// Захиалга үүсгэхэд илгээх шалгах жагсаалтын хариулт.
class IntakeChecklistAnswer {
  const IntakeChecklistAnswer({
    required this.id,
    required this.status,
    this.note,
  });

  final String id;
  final ChecklistStatus status;
  final String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.name,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
  };
}

/// Захиалгын дэлгэрэнгүйн `intake.checklist[]` — нээх үеийн snapshot.
class IntakeChecklistEntry {
  const IntakeChecklistEntry({
    required this.label,
    required this.status,
    this.note,
  });

  final String label;
  final ChecklistStatus status;
  final String? note;
}
