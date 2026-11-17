/// Tenant subscription / plan status — `GET /api/v1/subscription`.
///
/// Read-only snapshot used to warn staff before access is lost. The staff guard
/// returns 403 `SUBSCRIPTION_EXPIRED` for mutations once locked; this model lets
/// the UI surface that state proactively rather than only on a failed action.
class SubscriptionStatus {
  final String? plan;
  final String status;
  final bool locked;
  final bool isTrial;
  final int? daysLeft;
  final DateTime? expiresAt;
  final bool expiringSoon;
  final int? warnDays;
  final bool hasPendingPayment;

  /// Plan modules the tenant has (`enable_diagnostics`, `enable_reports` …);
  /// the server answers 403 `MODULE_DISABLED` on the others' endpoints.
  /// Null from a server that doesn't send them: treat everything as open.
  final Set<String>? modules;

  const SubscriptionStatus({
    required this.plan,
    required this.status,
    required this.locked,
    required this.isTrial,
    required this.daysLeft,
    required this.expiresAt,
    required this.expiringSoon,
    required this.warnDays,
    required this.hasPendingPayment,
    this.modules,
  });

  /// Whether a screen behind [module] (null = core, always open) is in the
  /// plan. Unknown modules allow it — the server stays the gate.
  bool allowsModule(String? module) =>
      module == null || modules == null || modules!.contains(module);

  /// True when the banner should be shown (locked, or nearing expiry).
  bool get needsAttention => locked || expiringSoon;

  factory SubscriptionStatus.fromJson(Map<String, dynamic> j) =>
      SubscriptionStatus(
        plan: j['plan'] as String?,
        status: j['status'] as String? ?? 'unknown',
        locked: j['locked'] as bool? ?? false,
        isTrial: j['isTrial'] as bool? ?? false,
        daysLeft: (j['daysLeft'] as num?)?.toInt(),
        expiresAt: j['expiresAt'] != null
            ? DateTime.tryParse(j['expiresAt'] as String)
            : null,
        expiringSoon: j['expiringSoon'] as bool? ?? false,
        warnDays: (j['warnDays'] as num?)?.toInt(),
        hasPendingPayment: j['hasPendingPayment'] as bool? ?? false,
        modules: j['modules'] is List
            ? {
                for (final m in j['modules'] as List)
                  if (m is String) m,
              }
            : null,
      );
}
