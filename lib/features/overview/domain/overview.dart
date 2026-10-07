/// Overview domain model — P7-F1.
///
/// Measured against `carservice.mn` after `P7-B1`:
/// * `app/api/v1/overview/route.ts` (`GET /api/v1/overview`),
/// * `lib/overview.ts` (`loadOverviewData`), `app/dashboard/trend.ts`
///   (`dailyTrend`/`Trend`), `app/dashboard/income-range.ts`.
///
/// D-177: home stats come from this endpoint; the retired
/// `AnalyticsScreen`'s client-side inspection counts are not modeled here.
library;

class OverviewParseException implements Exception {
  const OverviewParseException(this.message);
  final String message;

  @override
  String toString() => 'OverviewParseException: $message';
}

/// `overview.incomeRange` — dates are ISO strings on the wire.
class OverviewIncomeRange {
  final String? key;
  final DateTime? from;
  final DateTime? to;
  final String? label;

  const OverviewIncomeRange({this.key, this.from, this.to, this.label});

  factory OverviewIncomeRange.fromJson(Map<String, dynamic> j) =>
      OverviewIncomeRange(
        key: _optString(j['key']),
        from: _optDate(j['from']),
        to: _optDate(j['to']),
        label: _optString(j['label']),
      );
}

/// `overview.counts`.
class OverviewCounts {
  final int branches;
  final int employees;
  final int customers;
  final int vehicles;
  final int openOrders;
  final int completedThisMonth;
  final int todayOrders;

  const OverviewCounts({
    this.branches = 0,
    this.employees = 0,
    this.customers = 0,
    this.vehicles = 0,
    this.openOrders = 0,
    this.completedThisMonth = 0,
    this.todayOrders = 0,
  });

  factory OverviewCounts.fromJson(Map<String, dynamic> j) => OverviewCounts(
    branches: _optInt(j['branches']) ?? 0,
    employees: _optInt(j['employees']) ?? 0,
    customers: _optInt(j['customers']) ?? 0,
    vehicles: _optInt(j['vehicles']) ?? 0,
    openOrders: _optInt(j['openOrders']) ?? 0,
    completedThisMonth: _optInt(j['completedThisMonth']) ?? 0,
    todayOrders: _optInt(j['todayOrders']) ?? 0,
  );
}

/// One `Trend` entry — `app/dashboard/trend.ts`'s `dailyTrend` output:
/// per-day counts over the window plus the recent-vs-previous-half %.
class OverviewTrend {
  final List<int> spark;
  final double? changePct;

  const OverviewTrend({this.spark = const [], this.changePct});

  factory OverviewTrend.fromJson(Object? raw) {
    if (raw is! Map) return const OverviewTrend();
    final j = Map<String, dynamic>.from(raw);
    final rawSpark = j['spark'];
    return OverviewTrend(
      spark: rawSpark is List
          ? rawSpark.map((v) => _optInt(v) ?? 0).toList(growable: false)
          : const [],
      changePct: _optDouble(j['changePct']),
    );
  }
}

/// `overview.trends` — one [OverviewTrend] per stat card.
class OverviewTrends {
  final OverviewTrend orders;
  final OverviewTrend completed;
  final OverviewTrend customers;
  final OverviewTrend vehicles;
  final OverviewTrend branches;
  final OverviewTrend employees;

  const OverviewTrends({
    this.orders = const OverviewTrend(),
    this.completed = const OverviewTrend(),
    this.customers = const OverviewTrend(),
    this.vehicles = const OverviewTrend(),
    this.branches = const OverviewTrend(),
    this.employees = const OverviewTrend(),
  });

  factory OverviewTrends.fromJson(Object? raw) {
    if (raw is! Map) return const OverviewTrends();
    final j = Map<String, dynamic>.from(raw);
    return OverviewTrends(
      orders: OverviewTrend.fromJson(j['orders']),
      completed: OverviewTrend.fromJson(j['completed']),
      customers: OverviewTrend.fromJson(j['customers']),
      vehicles: OverviewTrend.fromJson(j['vehicles']),
      branches: OverviewTrend.fromJson(j['branches']),
      employees: OverviewTrend.fromJson(j['employees']),
    );
  }
}

class OverviewIncomePoint {
  final String? label;
  final double value;

  const OverviewIncomePoint({this.label, this.value = 0});

  factory OverviewIncomePoint.fromJson(Map<String, dynamic> j) =>
      OverviewIncomePoint(
        label: _optString(j['label']),
        value: _optDouble(j['value']) ?? 0,
      );
}

/// `overview.income`.
class OverviewIncome {
  final double total;
  final double? changePct;
  final List<OverviewIncomePoint> points;

  const OverviewIncome({this.total = 0, this.changePct, this.points = const []});

  factory OverviewIncome.fromJson(Object? raw) {
    if (raw is! Map) return const OverviewIncome();
    final j = Map<String, dynamic>.from(raw);
    final rawPoints = j['points'];
    return OverviewIncome(
      total: _optDouble(j['total']) ?? 0,
      changePct: _optDouble(j['changePct']),
      points: rawPoints is List
          ? rawPoints
              .whereType<Map>()
              .map(
                (p) =>
                    OverviewIncomePoint.fromJson(Map<String, dynamic>.from(p)),
              )
              .toList(growable: false)
          : const [],
    );
  }
}

/// `overview.subscription` — `null` when the tenant has no active
/// subscription row.
class OverviewSubscription {
  final String? plan;
  final String? status;
  final DateTime? expiresAt;
  final int? daysLeft;

  const OverviewSubscription({this.plan, this.status, this.expiresAt, this.daysLeft});

  factory OverviewSubscription.fromJson(Map<String, dynamic> j) =>
      OverviewSubscription(
        plan: _optString(j['plan']),
        status: _optString(j['status']),
        expiresAt: _optDate(j['expiresAt']),
        daysLeft: _optInt(j['daysLeft']),
      );
}

/// `overview.postpaid` — `receivable` is a decimal string on the wire
/// (`Prisma.Decimal.toString()`), parsed to `double` here; a mobile screen
/// only ever displays it, never re-derives it arithmetically against other
/// server-computed decimals.
class OverviewPostpaid {
  final int vehicleCount;
  final double receivable;

  const OverviewPostpaid({this.vehicleCount = 0, this.receivable = 0});

  factory OverviewPostpaid.fromJson(Object? raw) {
    if (raw is! Map) return const OverviewPostpaid();
    final j = Map<String, dynamic>.from(raw);
    return OverviewPostpaid(
      vehicleCount: _optInt(j['vehicleCount']) ?? 0,
      receivable: _optDouble(j['receivable']) ?? 0,
    );
  }
}

class RecentOrderItem {
  final String? status;
  final String? kind;

  const RecentOrderItem({this.status, this.kind});

  factory RecentOrderItem.fromJson(Map<String, dynamic> j) => RecentOrderItem(
    status: _optString(j['status']),
    kind: _optString(j['kind']),
  );
}

/// `overview.recentlyUpdatedOrders[]`.
class RecentOrder {
  final String id;
  final String? number;
  final String? status;
  final DateTime? updatedAt;
  final String? customerName;
  final String? vehiclePlate;
  final List<RecentOrderItem> items;

  const RecentOrder({
    required this.id,
    this.number,
    this.status,
    this.updatedAt,
    this.customerName,
    this.vehiclePlate,
    this.items = const [],
  });

  factory RecentOrder.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    return RecentOrder(
      id: _optString(j['id']) ?? '',
      number: _optString(j['number']),
      status: _optString(j['status']),
      updatedAt: _optDate(j['updatedAt']),
      customerName: _optString(j['customerName']),
      vehiclePlate: _optString(j['vehiclePlate']),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((i) => RecentOrderItem.fromJson(Map<String, dynamic>.from(i)))
              .toList(growable: false)
          : const [],
    );
  }
}

/// `overview.planLimits` — `PLAN_LIMIT_CODES` keys (`daily_orders`,
/// `max_vehicles`, `max_users`, `max_branches`) → the effective int limit,
/// or `null` when the plan has no cap for that code
/// (`getLimitsMap`/`DEFAULT_PLAN_LIMITS`).
typedef OverviewPlanLimits = Map<String, int?>;

OverviewPlanLimits _planLimits(Object? raw) {
  if (raw is! Map) return const {};
  final result = <String, int?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) continue;
    result[entry.key as String] = _optInt(entry.value);
  }
  return result;
}

/// The full `overview` object on `GET /api/v1/overview`.
class Overview {
  final OverviewIncomeRange incomeRange;
  final OverviewCounts counts;
  final OverviewTrends trends;
  final OverviewIncome income;
  final OverviewSubscription? subscription;
  final OverviewPlanLimits planLimits;
  final OverviewPostpaid postpaid;

  /// Period total of COMPLETED internal repairs ("Дотоод зардал"). `null`
  /// when the server omits it - callers hide the figure.
  final double? internalCost;
  final List<RecentOrder> recentlyUpdatedOrders;

  const Overview({
    this.incomeRange = const OverviewIncomeRange(),
    this.counts = const OverviewCounts(),
    this.trends = const OverviewTrends(),
    this.income = const OverviewIncome(),
    this.subscription,
    this.planLimits = const {},
    this.postpaid = const OverviewPostpaid(),
    this.internalCost,
    this.recentlyUpdatedOrders = const [],
  });

  factory Overview.fromJson(Map<String, dynamic> j) {
    final rawOrders = j['recentlyUpdatedOrders'];
    return Overview(
      incomeRange: j['incomeRange'] is Map
          ? OverviewIncomeRange.fromJson(
              Map<String, dynamic>.from(j['incomeRange'] as Map),
            )
          : const OverviewIncomeRange(),
      counts: j['counts'] is Map
          ? OverviewCounts.fromJson(Map<String, dynamic>.from(j['counts'] as Map))
          : const OverviewCounts(),
      trends: OverviewTrends.fromJson(j['trends']),
      income: OverviewIncome.fromJson(j['income']),
      subscription: j['subscription'] is Map
          ? OverviewSubscription.fromJson(
              Map<String, dynamic>.from(j['subscription'] as Map),
            )
          : null,
      planLimits: _planLimits(j['planLimits']),
      postpaid: OverviewPostpaid.fromJson(j['postpaid']),
      internalCost: _optDouble(j['internalCost']),
      recentlyUpdatedOrders: rawOrders is List
          ? rawOrders
              .whereType<Map>()
              .map((o) => RecentOrder.fromJson(Map<String, dynamic>.from(o)))
              .toList(growable: false)
          : const [],
    );
  }
}

// ─── Parse helpers ─────────────────────────────────────────────────────────

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
