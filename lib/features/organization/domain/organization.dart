/// `GET /api/v1/tenant` — the workshop's settings ("Байгууллагын тохиргоо"),
/// the plan modules that gate parts of the form, and whether the caller may
/// edit (`canEdit` = owner; every signed-in employee may read).
class OrganizationSettings {
  const OrganizationSettings({
    required this.id,
    required this.name,
    required this.registerNumber,
    required this.phone1,
    this.email,
    this.phone2,
    this.logoUrl,
    this.acceptsOnlineBooking = false,
    this.requireCashSession = false,
    this.appointmentReminderLeadMinutes,
    this.slug = '',
    this.plan = '',
    this.createdAt,
    this.onlineBookingInPlan = false,
    this.appointmentsInPlan = false,
    this.canEdit = false,
  });

  factory OrganizationSettings.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Хариу буруу байна');
    final tenant = json['tenant'];
    if (tenant is! Map) throw const FormatException('Хариу буруу байна');
    final modules = json['modules'] is Map ? json['modules'] as Map : const {};
    String? str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    final lead = tenant['appointmentReminderLeadMinutes'];
    return OrganizationSettings(
      id: tenant['id']?.toString() ?? '',
      name: tenant['name']?.toString() ?? '',
      registerNumber: tenant['registerNumber']?.toString() ?? '',
      phone1: tenant['phone1']?.toString() ?? '',
      email: str(tenant['email']),
      phone2: str(tenant['phone2']),
      logoUrl: str(tenant['logoUrl']),
      acceptsOnlineBooking: tenant['acceptsOnlineBooking'] == true,
      requireCashSession: tenant['requireCashSession'] == true,
      appointmentReminderLeadMinutes: lead is num ? lead.toInt() : null,
      slug: tenant['slug']?.toString() ?? '',
      plan: tenant['plan']?.toString() ?? '',
      createdAt: DateTime.tryParse(tenant['createdAt']?.toString() ?? '')?.toLocal(),
      onlineBookingInPlan: modules['onlineBooking'] == true,
      appointmentsInPlan: modules['appointments'] == true,
      canEdit: json['canEdit'] == true,
    );
  }

  final String id;
  final String name;
  final String registerNumber;
  final String phone1;
  final String? email;
  final String? phone2;
  final String? logoUrl;
  final bool acceptsOnlineBooking;
  final bool requireCashSession;

  /// Minutes before a confirmed appointment that the customer is reminded
  /// (multiple of 60, 60…10080). Null when the server does not send it.
  final int? appointmentReminderLeadMinutes;
  final String slug;
  final String plan;
  final DateTime? createdAt;

  /// The plan has `online_booking` — only then may [acceptsOnlineBooking]
  /// be turned on (the server answers 403 MODULE_DISABLED otherwise).
  final bool onlineBookingInPlan;
  final bool appointmentsInPlan;
  final bool canEdit;

  OrganizationSettings copyWith({String? logoUrl, bool clearLogo = false}) => OrganizationSettings(
    id: id,
    name: name,
    registerNumber: registerNumber,
    phone1: phone1,
    email: email,
    phone2: phone2,
    logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
    acceptsOnlineBooking: acceptsOnlineBooking,
    requireCashSession: requireCashSession,
    appointmentReminderLeadMinutes: appointmentReminderLeadMinutes,
    slug: slug,
    plan: plan,
    createdAt: createdAt,
    onlineBookingInPlan: onlineBookingInPlan,
    appointmentsInPlan: appointmentsInPlan,
    canEdit: canEdit,
  );
}

/// The form's values; [OrganizationDraft.patchFrom] sends only what changed.
class OrganizationDraft {
  const OrganizationDraft({
    required this.name,
    required this.registerNumber,
    required this.email,
    required this.phone1,
    required this.phone2,
    required this.acceptsOnlineBooking,
    required this.requireCashSession,
    this.reminderLeadMinutes,
  });

  final String name;
  final String registerNumber;
  final String email;
  final String phone1;
  final String phone2;
  final bool acceptsOnlineBooking;
  final bool requireCashSession;
  final int? reminderLeadMinutes;

  /// `PATCH /tenant` body: only changed fields (the server merges the rest).
  /// Empty email/phone2 go as `null` (clears them). The online-booking flag
  /// is never sent when the plan lacks the module.
  Map<String, Object?> patchFrom(OrganizationSettings current) {
    final body = <String, Object?>{};
    final name = this.name.trim();
    final regno = registerNumber.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final email = this.email.trim();
    final phone1 = this.phone1.trim();
    final phone2 = this.phone2.trim();
    if (name != current.name) body['name'] = name;
    if (regno != current.registerNumber) body['registerNumber'] = regno;
    if (email != (current.email ?? '')) body['email'] = email.isEmpty ? null : email;
    if (phone1 != current.phone1) body['phone1'] = phone1;
    if (phone2 != (current.phone2 ?? '')) body['phone2'] = phone2.isEmpty ? null : phone2;
    if (current.onlineBookingInPlan && acceptsOnlineBooking != current.acceptsOnlineBooking) {
      body['acceptsOnlineBooking'] = acceptsOnlineBooking;
    }
    if (requireCashSession != current.requireCashSession) {
      body['requireCashSession'] = requireCashSession;
    }
    final lead = reminderLeadMinutes;
    if (lead != null && lead != current.appointmentReminderLeadMinutes) {
      body['appointmentReminderLeadMinutes'] = lead;
    }
    return body;
  }
}

/// Reminder lead bounds (`lib/tenant-settings.ts`): whole hours, 1 h…7 days.
abstract final class ReminderLead {
  static const minMinutes = 60;
  static const maxMinutes = 7 * 24 * 60;
  static const defaultMinutes = 24 * 60;

  static String label(int minutes) {
    final days = minutes ~/ 1440;
    final hours = (minutes % 1440) ~/ 60;
    final parts = [if (days > 0) '$days хоног', if (hours > 0) '$hours цаг'];
    return parts.isEmpty ? '0 цаг' : parts.join(' ');
  }
}

/// Mongolian label of the server's `Plan` enum.
String planLabel(String plan) => switch (plan) {
  'FREE' => 'Үнэгүй',
  'BUSINESS' => 'Бизнес',
  'ENTERPRISE' => 'Энтерпрайз',
  _ => plan,
};
