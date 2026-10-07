/// Reports domain model — P7-F1.
///
/// Measured against `carservice.mn` after `P7-B0`:
/// * `app/api/v1/reports/route.ts` (`GET /api/v1/reports`),
/// * `app/api/v1/reports/export/route.ts` (`GET /api/v1/reports/export`),
/// * `lib/reports.ts` (`ReportData`, `Range`, `parseRange`).
///
/// D-174/D-175: any authenticated staff member (no `reports.*` permission
/// exists), and export reuses the web's `.xlsx` workbook byte-for-byte — no
/// CSV, no client-side re-derivation of the sheet content.
library;

class ReportParseException implements Exception {
  const ReportParseException(this.message);
  final String message;

  @override
  String toString() => 'ReportParseException: $message';
}

/// `range` on `GET /api/v1/reports` — `lib/reports.ts`'s `Range`, serialized.
class ReportRange {
  final DateTime? from;
  final DateTime? to;
  final String? label;
  final String? key;

  const ReportRange({this.from, this.to, this.label, this.key});

  factory ReportRange.fromJson(Map<String, dynamic> j) => ReportRange(
    from: _optDate(j['from']),
    to: _optDate(j['to']),
    label: _optString(j['label']),
    key: _optString(j['key']),
  );
}

class ReportStatusRow {
  final String? status;
  final String? label;
  final int count;
  final int pct;

  const ReportStatusRow({
    this.status,
    this.label,
    this.count = 0,
    this.pct = 0,
  });

  factory ReportStatusRow.fromJson(Map<String, dynamic> j) => ReportStatusRow(
    status: _optString(j['status']),
    label: _optString(j['label']),
    count: _optInt(j['count']) ?? 0,
    pct: _optInt(j['pct']) ?? 0,
  );
}

class ReportKindRow {
  final String? kind;
  final String? label;
  final double total;
  final int pct;

  const ReportKindRow({this.kind, this.label, this.total = 0, this.pct = 0});

  factory ReportKindRow.fromJson(Map<String, dynamic> j) => ReportKindRow(
    kind: _optString(j['kind']),
    label: _optString(j['label']),
    total: _optDouble(j['total']) ?? 0,
    pct: _optInt(j['pct']) ?? 0,
  );
}

class ReportBranchRow {
  final String id;
  final String? name;
  final double revenue;
  final int count;

  const ReportBranchRow({
    required this.id,
    this.name,
    this.revenue = 0,
    this.count = 0,
  });

  factory ReportBranchRow.fromJson(Map<String, dynamic> j) => ReportBranchRow(
    id: _optString(j['id']) ?? '',
    name: _optString(j['name']),
    revenue: _optDouble(j['revenue']) ?? 0,
    count: _optInt(j['count']) ?? 0,
  );
}

class ReportTechRow {
  final String id;
  final String? name;
  final double revenue;
  final int count;

  const ReportTechRow({
    required this.id,
    this.name,
    this.revenue = 0,
    this.count = 0,
  });

  factory ReportTechRow.fromJson(Map<String, dynamic> j) => ReportTechRow(
    id: _optString(j['id']) ?? '',
    name: _optString(j['name']),
    revenue: _optDouble(j['revenue']) ?? 0,
    count: _optInt(j['count']) ?? 0,
  );
}

class ReportJobDurationRow {
  final String id;
  final String? name;
  final int count;
  final int avgMinutes;

  const ReportJobDurationRow({
    required this.id,
    this.name,
    this.count = 0,
    this.avgMinutes = 0,
  });

  factory ReportJobDurationRow.fromJson(Map<String, dynamic> j) =>
      ReportJobDurationRow(
        id: _optString(j['id']) ?? '',
        name: _optString(j['name']),
        count: _optInt(j['count']) ?? 0,
        avgMinutes: _optInt(j['avgMinutes']) ?? 0,
      );
}

class ReportCustomerRow {
  final String id;
  final String? name;
  final String? phone;
  final double revenue;
  final int count;

  const ReportCustomerRow({
    required this.id,
    this.name,
    this.phone,
    this.revenue = 0,
    this.count = 0,
  });

  factory ReportCustomerRow.fromJson(Map<String, dynamic> j) =>
      ReportCustomerRow(
        id: _optString(j['id']) ?? '',
        name: _optString(j['name']),
        phone: _optString(j['phone']),
        revenue: _optDouble(j['revenue']) ?? 0,
        count: _optInt(j['count']) ?? 0,
      );
}

class ReportPartRow {
  final String id;
  final String? name;
  final String? sku;
  final String? unit;
  final double qty;
  final double revenue;

  const ReportPartRow({
    required this.id,
    this.name,
    this.sku,
    this.unit,
    this.qty = 0,
    this.revenue = 0,
  });

  factory ReportPartRow.fromJson(Map<String, dynamic> j) => ReportPartRow(
    id: _optString(j['id']) ?? '',
    name: _optString(j['name']),
    sku: _optString(j['sku']),
    unit: _optString(j['unit']),
    qty: _optDouble(j['qty']) ?? 0,
    revenue: _optDouble(j['revenue']) ?? 0,
  );
}

class ReportIncomePoint {
  final String? label;
  final double value;

  const ReportIncomePoint({this.label, this.value = 0});

  factory ReportIncomePoint.fromJson(Map<String, dynamic> j) =>
      ReportIncomePoint(
        label: _optString(j['label']),
        value: _optDouble(j['value']) ?? 0,
      );
}

class ReportIncome {
  final List<ReportIncomePoint> points;
  final double? changePct;

  const ReportIncome({this.points = const [], this.changePct});

  factory ReportIncome.fromJson(Map<String, dynamic> j) {
    final rawPoints = j['points'];
    return ReportIncome(
      points: rawPoints is List
          ? rawPoints
                .whereType<Map>()
                .map(
                  (p) =>
                      ReportIncomePoint.fromJson(Map<String, dynamic>.from(p)),
                )
                .toList(growable: false)
          : const [],
      changePct: _optDouble(j['changePct']),
    );
  }
}

/// `data` on `GET /api/v1/reports` — `lib/reports.ts`'s `ReportData`.
///
/// Every list defaults to empty and every scalar defaults to 0/false rather
/// than throwing — a malformed row degrades to nothing rendered, not a
/// broken screen. Only the top-level envelope is structurally required (see
/// `report_dto.dart`).
class ReportData {
  final double totalRevenue;
  final int completedCount;
  final double avgTicket;
  final int activeCount;
  final List<ReportStatusRow> statusRows;
  final List<ReportKindRow> kindRows;
  final List<ReportBranchRow> branchRows;
  final List<ReportTechRow> techRows;
  final int avgJobDurationMinutes;
  final List<ReportJobDurationRow> jobDurationRows;
  final List<ReportCustomerRow> customerRows;
  final List<ReportPartRow> partRows;
  final ReportIncome income;

  /// Total of COMPLETED internal repairs ("Дотоод зардал"); `null` when the
  /// server omits it - the screen then hides the figure.
  final double? internalCost;

  const ReportData({
    this.totalRevenue = 0,
    this.completedCount = 0,
    this.avgTicket = 0,
    this.activeCount = 0,
    this.statusRows = const [],
    this.kindRows = const [],
    this.branchRows = const [],
    this.techRows = const [],
    this.avgJobDurationMinutes = 0,
    this.jobDurationRows = const [],
    this.customerRows = const [],
    this.partRows = const [],
    this.income = const ReportIncome(),
    this.internalCost,
  });

  factory ReportData.fromJson(Map<String, dynamic> j) => ReportData(
    totalRevenue: _optDouble(j['totalRevenue']) ?? 0,
    completedCount: _optInt(j['completedCount']) ?? 0,
    avgTicket: _optDouble(j['avgTicket']) ?? 0,
    activeCount: _optInt(j['activeCount']) ?? 0,
    statusRows: _list(j['statusRows'], ReportStatusRow.fromJson),
    kindRows: _list(j['kindRows'], ReportKindRow.fromJson),
    branchRows: _list(j['branchRows'], ReportBranchRow.fromJson),
    techRows: _list(j['techRows'], ReportTechRow.fromJson),
    avgJobDurationMinutes: _optInt(j['avgJobDurationMinutes']) ?? 0,
    jobDurationRows: _list(j['jobDurationRows'], ReportJobDurationRow.fromJson),
    customerRows: _list(j['customerRows'], ReportCustomerRow.fromJson),
    partRows: _list(j['partRows'], ReportPartRow.fromJson),
    income: j['income'] is Map
        ? ReportIncome.fromJson(Map<String, dynamic>.from(j['income'] as Map))
        : const ReportIncome(),
    internalCost: _optDouble(j['internalCost']),
  );
}

/// The full `GET /api/v1/reports` response.
class ReportResult {
  final ReportRange range;
  final ReportData data;

  const ReportResult({required this.range, required this.data});
}

/// `GET /api/v1/reports/export` — the xlsx bytes plus the filename resolved
/// from `Content-Disposition`, falling back to `tailan_<from>_<to>.xlsx`
/// (matching `lib/reports-export.ts`'s `reportExportFilename`) when the
/// header is missing or unparsable.
class ReportExportFile {
  final List<int> bytes;
  final String filename;

  const ReportExportFile({required this.bytes, required this.filename});
}

// ─── Parse helpers ─────────────────────────────────────────────────────────

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) fromJson) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}

String? _optString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _optInt(Object? value) {
  if (value is int) return value;
  if (value is double) {
    return value == value.roundToDouble() ? value.toInt() : value.round();
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _optDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

DateTime? _optDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toLocal();
}
