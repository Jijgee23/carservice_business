import 'package:carservice_business/core/domain/models.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

enum DiagnosticType {
  INTAKE,
  POST_SERVICE,
  ROUTINE,
  DAMAGE_REPORT;

  String get label {
    switch (this) {
      case DiagnosticType.INTAKE:
        return 'Хүлээж авах';
      case DiagnosticType.POST_SERVICE:
        return 'Үйлчилгээний дараа';
      case DiagnosticType.ROUTINE:
        return 'Тогтмол үзлэг';
      case DiagnosticType.DAMAGE_REPORT:
        return 'Гэмтлийн тайлан';
    }
  }

  static DiagnosticType fromString(String s) => DiagnosticType.values
      .firstWhere((e) => e.name == s, orElse: () => DiagnosticType.ROUTINE);
}

enum ItemType {
  check,
  text,
  number,
  photo,
  signature;

  static ItemType fromString(String s) => ItemType.values.firstWhere(
    (e) => e.name == s,
    orElse: () => ItemType.text,
  );
}

// ─── Position support ─────────────────────────────────────────────────────────

class PositionDef {
  final String code;
  final String label;
  const PositionDef({required this.code, required this.label});
}

enum PositionSetKey {
  LR,
  FB,
  CORNERS;

  List<PositionDef> get positions {
    switch (this) {
      case PositionSetKey.LR:
        return const [
          PositionDef(code: 'L', label: 'Зүүн'),
          PositionDef(code: 'R', label: 'Баруун'),
        ];
      case PositionSetKey.FB:
        return const [
          PositionDef(code: 'F', label: 'Урд'),
          PositionDef(code: 'B', label: 'Хойд'),
        ];
      case PositionSetKey.CORNERS:
        return const [
          PositionDef(code: 'FL', label: 'Урд зүүн'),
          PositionDef(code: 'FR', label: 'Урд баруун'),
          PositionDef(code: 'RL', label: 'Хойд зүүн'),
          PositionDef(code: 'RR', label: 'Хойд баруун'),
        ];
    }
  }

  static PositionSetKey? tryParse(String? s) {
    if (s == null) return null;
    for (final v in PositionSetKey.values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// Байрлалтай item-ийн report.data дахь түлхүүр: `itemId@code`
String positionedKey(String itemId, String code) => '$itemId@$code';

// ─── Template schema types ────────────────────────────────────────────────────

class ShowWhen {
  final String itemId;
  final List<String> values;
  const ShowWhen({required this.itemId, required this.values});

  factory ShowWhen.fromJson(Map<String, dynamic> j) => ShowWhen(
    itemId: j['itemId'] as String,
    values: List<String>.from(j['values'] as List),
  );
}

class TemplateItem {
  final String id;
  final String label;
  final ItemType type;
  final bool required;
  final List<String>? options; // check төрөлд байна
  final ShowWhen? showWhen;
  final PositionSetKey? positionSet; // байрлал бүрээр давтаж шалгах

  const TemplateItem({
    required this.id,
    required this.label,
    required this.type,
    required this.required,
    this.options,
    this.showWhen,
    this.positionSet,
  });

  List<String> get effectiveOptions =>
      options?.isNotEmpty == true ? options! : ['OK', 'Анхаарах', 'Засах'];

  factory TemplateItem.fromJson(Map<String, dynamic> j) => TemplateItem(
    id: j['id'] as String,
    label: j['label'] as String,
    type: ItemType.fromString(j['type'] as String),
    required: j['required'] as bool? ?? false,
    options: j['options'] != null
        ? List<String>.from(j['options'] as List)
        : null,
    showWhen: j['showWhen'] != null
        ? ShowWhen.fromJson(j['showWhen'] as Map<String, dynamic>)
        : null,
    positionSet: PositionSetKey.tryParse(j['positionSet'] as String?),
  );
}

class TemplateSection {
  final String id;
  final String title;
  final List<TemplateItem> items;
  const TemplateSection({
    required this.id,
    required this.title,
    required this.items,
  });

  factory TemplateSection.fromJson(Map<String, dynamic> j) => TemplateSection(
    id: j['id'] as String,
    title: j['title'] as String,
    items: (j['items'] as List)
        .map((i) => TemplateItem.fromJson(i as Map<String, dynamic>))
        .toList(),
  );
}

class TemplateSchema {
  final List<TemplateSection> sections;
  const TemplateSchema({required this.sections});

  factory TemplateSchema.fromJson(Map<String, dynamic> j) => TemplateSchema(
    sections: (j['sections'] as List)
        .map((s) => TemplateSection.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

// ─── Template models ──────────────────────────────────────────────────────────

class DiagnosticTemplateSummary {
  final String id;
  final String name;
  final String? description;
  final DiagnosticType type;
  final int version;
  final bool isActive;
  final double? price;
  final int? durationMin;
  final DateTime updatedAt;

  const DiagnosticTemplateSummary({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.version,
    required this.isActive,
    this.price,
    this.durationMin,
    required this.updatedAt,
  });

  String get durationDisplay {
    if (durationMin == null) return '';
    final h = durationMin! ~/ 60;
    final m = durationMin! % 60;
    if (h == 0) return '$mмин';
    if (m == 0) return '$hц';
    return '$hц $mмин';
  }

  factory DiagnosticTemplateSummary.fromJson(Map<String, dynamic> j) =>
      DiagnosticTemplateSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        type: DiagnosticType.fromString(j['type'] as String),
        version: j['version'] as int? ?? 1,
        isActive: j['isActive'] as bool? ?? true,
        price: j['price'] != null
            ? double.tryParse(j['price'].toString())
            : null,
        durationMin: j['durationMin'] as int?,
        updatedAt: j['updatedAt'] != null
            ? DateTime.parse(j['updatedAt'] as String)
            : DateTime(2000),
      );
}

class DiagnosticTemplateDetail extends DiagnosticTemplateSummary {
  final TemplateSchema schema;

  const DiagnosticTemplateDetail({
    required super.id,
    required super.name,
    super.description,
    required super.type,
    required super.version,
    required super.isActive,
    super.price,
    super.durationMin,
    required super.updatedAt,
    required this.schema,
  });

  factory DiagnosticTemplateDetail.fromJson(Map<String, dynamic> j) =>
      DiagnosticTemplateDetail(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        type: DiagnosticType.fromString(j['type'] as String),
        version: j['version'] as int? ?? 1,
        isActive: j['isActive'] as bool? ?? true,
        price: j['price'] != null
            ? double.tryParse(j['price'].toString())
            : null,
        durationMin: j['durationMin'] as int?,
        updatedAt: j['updatedAt'] != null
            ? DateTime.parse(j['updatedAt'] as String)
            : DateTime(2000),
        schema: TemplateSchema.fromJson(j['schema'] as Map<String, dynamic>),
      );
}

// ─── Customer / Vehicle / Branch / User summaries ────────────────────────────

class CustomerSummary {
  final String id;
  final String? fullName;
  final String phone;
  final String? email;

  /// Phase 4: байгууллага харилцагч — [fullName] нь холбогдох хүн.
  final bool isOrganization;
  final String? orgName;
  final String? orgRegnum;

  const CustomerSummary({
    required this.id,
    this.fullName,
    required this.phone,
    this.email,
    this.isOrganization = false,
    this.orgName,
    this.orgRegnum,
  });

  /// «РД 1234567» for organization customers with a registry number, else null.
  String? get orgRegnumLabel {
    final r = orgRegnum?.trim() ?? '';
    return isOrganization && r.isNotEmpty ? 'РД $r' : null;
  }

  /// Contact name if set, otherwise falls back to phone number.
  String get contactName {
    final n = fullName?.trim() ?? '';
    return n.isNotEmpty ? n : phone;
  }

  /// Organizations show [orgName] first; others the contact name.
  String get displayName {
    final o = orgName?.trim() ?? '';
    return isOrganization && o.isNotEmpty ? o : contactName;
  }

  factory CustomerSummary.fromJson(Map<String, dynamic> j) => CustomerSummary(
    id: j['id'] as String,
    fullName: j['fullName'] as String?,
    phone: j['phone'] as String,
    email: j['email'] as String?,
    isOrganization: j['isOrganization'] == true,
    orgName: j['orgName'] as String?,
    orgRegnum: j['orgRegnum'] as String?,
  );
}

class VehicleSummary {
  final String id;
  final String plate;
  final String? vin;
  final String make;
  final String model;
  final int? year;
  final int? mileage;
  final String? customerId;
  final CustomerSummary? customer;

  /// `TenantVehicle.isPostpaid` when the payload carries it; `false` when the
  /// endpoint omits it (the vehicles list does not select it today).
  final bool isPostpaid;

  /// Phase 4: server-derived (linked customer, else ХУР regnum).
  final bool ownerIsOrganization;

  const VehicleSummary({
    required this.id,
    required this.plate,
    this.vin,
    required this.make,
    required this.model,
    this.year,
    this.mileage,
    this.customerId,
    this.customer,
    this.isPostpaid = false,
    this.ownerIsOrganization = false,
  });

  String get displayName => '$make $model${year != null ? ' $year' : ''}';

  factory VehicleSummary.fromJson(Map<String, dynamic> j) => VehicleSummary(
    id: j['id'] as String,
    plate: j['plate'] as String,
    vin: j['vin'] as String?,
    make: j['make'] as String,
    model: j['model'] as String,
    year: j['year'] as int?,
    mileage: j['mileage'] as int?,
    customerId: j['customerId'] as String?,
    customer: j['customer'] != null
        ? CustomerSummary.fromJson(j['customer'] as Map<String, dynamic>)
        : null,
    isPostpaid: j['isPostpaid'] == true,
    ownerIsOrganization: j['ownerIsOrganization'] == true,
  );
}

class BranchSummary {
  final String id;
  final String name;
  final String? address;
  const BranchSummary({required this.id, required this.name, this.address});
  factory BranchSummary.fromJson(Map<String, dynamic> j) => BranchSummary(
    id: j['id'] as String,
    name: j['name'] as String,
    address: j['address'] as String?,
  );
}

class UserSummary {
  final String id;
  final String firstName;
  final String lastName;
  const UserSummary({
    required this.id,
    required this.firstName,
    required this.lastName,
  });
  String get fullName => '$firstName $lastName';
  factory UserSummary.fromJson(Map<String, dynamic> j) => UserSummary(
    id: j['id'] as String,
    firstName: j['firstName'] as String,
    lastName: j['lastName'] as String,
  );
}

// ─── Report models ────────────────────────────────────────────────────────────

class ReportTemplateSummary {
  final String id;
  final String name;
  final DiagnosticType type;
  const ReportTemplateSummary({
    required this.id,
    required this.name,
    required this.type,
  });
  factory ReportTemplateSummary.fromJson(Map<String, dynamic> j) =>
      ReportTemplateSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        type: DiagnosticType.fromString(j['type'] as String),
      );
}

class DiagnosticReportSummary {
  final String id;
  final DateTime createdAt;
  final int templateVersion;
  final int? mileageAtReport;
  final String? orderId;
  final ReportTemplateSummary template;
  final CustomerSummary customer;
  final VehicleSummary vehicle;
  final BranchSummary branch;
  final UserSummary? filledBy;

  const DiagnosticReportSummary({
    required this.id,
    required this.createdAt,
    required this.templateVersion,
    this.mileageAtReport,
    this.orderId,
    required this.template,
    required this.customer,
    required this.vehicle,
    required this.branch,
    this.filledBy,
  });

  factory DiagnosticReportSummary.fromJson(Map<String, dynamic> j) =>
      DiagnosticReportSummary(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        templateVersion: j['templateVersion'] as int? ?? 1,
        mileageAtReport: j['mileageAtReport'] as int?,
        orderId: j['orderId'] as String?,
        template: ReportTemplateSummary.fromJson(
          j['template'] as Map<String, dynamic>,
        ),
        customer: CustomerSummary.fromJson(
          j['customer'] as Map<String, dynamic>,
        ),
        vehicle: VehicleSummary.fromJson(j['vehicle'] as Map<String, dynamic>),
        branch: BranchSummary.fromJson(j['branch'] as Map<String, dynamic>),
        filledBy: j['filledBy'] != null
            ? UserSummary.fromJson(j['filledBy'] as Map<String, dynamic>)
            : null,
      );
}

// ─── Report entry & detail ────────────────────────────────────────────────────

class ReportEntry {
  final dynamic value; // String, num, or bool
  final List<String>? photos;
  final String? note;

  const ReportEntry({this.value, this.photos, this.note});

  factory ReportEntry.fromJson(Map<String, dynamic> j) => ReportEntry(
    value: j['value'],
    photos: j['photos'] != null ? List<String>.from(j['photos'] as List) : null,
    note: j['note'] as String?,
  );

  // check item утгыг CheckStatus болгон хөрвүүлнэ
  CheckStatus get checkStatus {
    final s = value?.toString() ?? '';
    if (s == 'Засах') return CheckStatus.danger;
    if (s == 'Анхаарах') return CheckStatus.warning;
    return CheckStatus.good;
  }
}

class DiagnosticReportDetail {
  final String id;
  final DateTime createdAt;
  final int templateVersion;
  final int? mileageAtReport;
  final String? notes;
  final String? signatureUrl;
  final String? orderId;
  final Map<String, ReportEntry> data;
  final DiagnosticTemplateDetail template;
  final CustomerSummary customer;
  final VehicleSummary vehicle;
  final BranchSummary branch;
  final UserSummary? filledBy;

  const DiagnosticReportDetail({
    required this.id,
    required this.createdAt,
    required this.templateVersion,
    this.mileageAtReport,
    this.notes,
    this.signatureUrl,
    this.orderId,
    required this.data,
    required this.template,
    required this.customer,
    required this.vehicle,
    required this.branch,
    this.filledBy,
  });

  // check item-уудаас нийт байдал тодорхойлно
  CheckStatus get overallStatus {
    bool hasWarning = false;
    for (final entry in data.values) {
      if (entry.value is String) {
        final cs = entry.checkStatus;
        if (cs == CheckStatus.danger) return CheckStatus.danger;
        if (cs == CheckStatus.warning) hasWarning = true;
      }
    }
    return hasWarning ? CheckStatus.warning : CheckStatus.good;
  }

  int get dangerCount =>
      data.values.where((e) => e.checkStatus == CheckStatus.danger).length;
  int get warningCount =>
      data.values.where((e) => e.checkStatus == CheckStatus.warning).length;
  int get goodCount => data.values
      .where((e) => e.value is String && e.checkStatus == CheckStatus.good)
      .length;

  factory DiagnosticReportDetail.fromJson(Map<String, dynamic> j) {
    final rawData = j['data'] as Map<String, dynamic>? ?? {};
    final data = rawData.map(
      (k, v) => MapEntry(
        k,
        v is Map<String, dynamic>
            ? ReportEntry.fromJson(v)
            : const ReportEntry(),
      ),
    );
    return DiagnosticReportDetail(
      id: j['id'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      templateVersion: j['templateVersion'] as int? ?? 1,
      mileageAtReport: j['mileageAtReport'] as int?,
      notes: j['notes'] as String?,
      signatureUrl: j['signatureUrl'] as String?,
      orderId: j['orderId'] as String?,
      data: data,
      template: DiagnosticTemplateDetail.fromJson(
        j['template'] as Map<String, dynamic>,
      ),
      customer: CustomerSummary.fromJson(j['customer'] as Map<String, dynamic>),
      vehicle: VehicleSummary.fromJson(j['vehicle'] as Map<String, dynamic>),
      branch: BranchSummary.fromJson(j['branch'] as Map<String, dynamic>),
      filledBy: j['filledBy'] != null
          ? UserSummary.fromJson(j['filledBy'] as Map<String, dynamic>)
          : null,
    );
  }
}
