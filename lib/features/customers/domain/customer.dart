/// Customers domain model — P3-F1.
///
/// Mirrors the `carservice.mn` backend contract measured field-by-field from
/// the routes under `app/api/v1/customers/` and the shared modules they
/// delegate to:
///
/// * `lib/customers/customer-commands.ts` (`CustomerRecord`,
///   `NormalizedCustomerData`, `CustomerCommandError`),
/// * `lib/customers/customer-list-query.ts` (the allow-listed query params),
/// * `lib/customers/customer-history.ts` (`CustomerHistoryOrder`),
/// * `lib/customers/customer-broadcast.ts` (recipient count / notified count),
/// * `lib/pagination.ts` (`buildMeta`).
///
/// Follows the Appointments idiom (`features/appointments/domain/
/// appointment.dart`) exactly: per-field tolerance everywhere, and
/// [CustomerParseException] thrown ONLY for a structurally missing `id`.
/// A null `email`, an absent `createdAt` (the PATCH route genuinely omits
/// it — see [Customer]), a malformed nested vehicle or an unparseable date
/// degrades to `null` rather than crashing a list.
library;

/// Typed failure for a structurally malformed Customers payload — thrown
/// only when a field the contract calls unconditionally required (an `id`)
/// is missing or the wrong type. Everything else degrades; see the module
/// doc comment. Mirrors `AppointmentParseException` / `OrderParseException`.
class CustomerParseException implements Exception {
  const CustomerParseException(this.message);

  final String message;

  @override
  String toString() => 'CustomerParseException: $message';
}

/// Machine-readable `code` values the customer routes emit.
///
/// MEASURED DIVERGENCE — read before keying UI off these. `jsonError`
/// spreads only the `extra` object it is given, and the customer routes are
/// not consistent about passing `code`:
///
/// | Route | fieldErrors branch | code branch |
/// |---|---|---|
/// | `POST /customers` | `{fieldErrors}` — **no `code`** | `jsonError(status, message)` — **no `code` at all** |
/// | `PATCH /customers/[id]` | `{fieldErrors}` — no `code` | `{code}` |
/// | `DELETE /customers/[id]` | — | `{code}` |
/// | `POST /customers/notify` | `{fieldErrors}` — no `code` | `{code}` |
///
/// So on **create** neither [planLimitReached] nor [phoneConflict] ever
/// reaches the client as a `code`; only the HTTP status and (for the
/// conflict/validation cases) `fieldErrors` do. [CustomerFailure] below
/// encodes exactly that, and nothing more.
abstract final class CustomerErrorCode {
  /// 422 — `validateCustomerInput` rejected phone/email. Carries
  /// `fieldErrors`. Not surfaced as a `code` by `POST /customers`.
  static const validationFailed = 'VALIDATION_FAILED';

  /// 422 — `MAX_CUSTOMERS` plan quota reached (`enforceCountLimit`).
  /// **Never surfaced as a `code`** — `POST /customers` is the only route
  /// that raises it and it drops the code. See [CustomerFailure.planLimit].
  static const planLimitReached = 'PLAN_LIMIT_REACHED';

  /// 409 — Prisma `P2002` on the partial `tenant+phone` unique index.
  /// Carries `fieldErrors: {phone: …}`. Not surfaced as a `code`.
  static const phoneConflict = 'PHONE_CONFLICT';

  /// 404 — tenant-scoped lookup miss. A cross-tenant id is deliberately
  /// indistinguishable from a nonexistent one.
  static const customerNotFound = 'CUSTOMER_NOT_FOUND';

  /// 409 — Prisma `P2003`: the customer still has service orders.
  static const customerInUse = 'CUSTOMER_IN_USE';

  /// 422 — `DAILY_CUSTOMER_NOTIFICATIONS` plan quota, from
  /// `POST /customers/notify`.
  static const dailyLimitReached = 'DAILY_LIMIT_REACHED';
}

/// The distinct, typed failure shapes the customer routes can produce,
/// classified from what is ACTUALLY on the wire (status + `code` +
/// `fieldErrors`) rather than from what the server-side error class was
/// named. This is the Appointments convention — `AppError.statusCode` /
/// `code` / `fieldErrors` stay authoritative and callers switch on them —
/// expressed once here so every call site classifies identically.
enum CustomerFailure {
  /// 403 — `customers.view` / `.create` / `.edit` / `.delete` / `.notify`
  /// missing, or the subscription gate. `GET /customers` newly returns this
  /// (P3-B0) where it previously did not.
  forbidden,

  /// 400 — `rejectUnknownParams` or a malformed `page`/`pageSize`/`limit`.
  /// A client that only ever sends the allow-listed params
  /// (`q`, `page`, `pageSize`, `limit`) cannot trigger the unknown-param
  /// half of this; see [CustomerListQuery].
  badRequest,

  /// 404 — customer not found, or belongs to another tenant.
  notFound,

  /// 422 with `fieldErrors` — bind them to the form.
  validation,

  /// 409 — duplicate phone among the tenant's unclaimed (walk-in)
  /// customers. Carries `fieldErrors: {phone: …}`, so it is distinguished
  /// from [validation] by status, not by field presence.
  phoneConflict,

  /// 409 `CUSTOMER_IN_USE` — cannot delete a customer that has orders.
  inUse,

  /// 422 without `fieldErrors` — a plan quota (`MAX_CUSTOMERS` on create,
  /// `DAILY_CUSTOMER_NOTIFICATIONS` on broadcast).
  ///
  /// Classified by **absence of `fieldErrors`**, not by `code`, because
  /// `POST /customers` drops the code (see [CustomerErrorCode]). The
  /// server-supplied message is the only human-readable detail available,
  /// so callers must show it verbatim rather than substituting their own.
  planLimit,

  /// Anything else — network, 401, 500, an unrecognised status.
  other;

  /// Classifies an `AppError`-shaped failure. Kept as a pure function of
  /// (status, code, fieldErrors) so it can be unit-tested without Dio.
  static CustomerFailure classify({
    int? statusCode,
    String? code,
    Map<String, String>? fieldErrors,
  }) {
    if (code == CustomerErrorCode.customerInUse) return inUse;
    return switch (statusCode) {
      403 => forbidden,
      400 => badRequest,
      404 => notFound,
      409 => phoneConflict,
      422 =>
        (fieldErrors != null && fieldErrors.isNotEmpty)
            ? validation
            : planLimit,
      _ => other,
    };
  }
}

/// A tenant customer row.
///
/// `GET /customers` (list), `GET /customers/[id]` and `POST /customers` all
/// return the full `CUSTOMER_SELECT` shape
/// (`{id, fullName, phone, email, note, createdAt}`).
///
/// **`PATCH /customers/[id]` does not.** It returns
/// `updateCustomerCommand`'s `NormalizedCustomerData & {id}` —
/// `{id, fullName, phone, email, note}` with **no `createdAt`**. That is why
/// [createdAt] is nullable here rather than required: a required field would
/// make every successful edit throw.
///
/// `fullName` is a non-nullable `String` in Prisma but
/// `validateCustomerInput` accepts an empty one (only `phone` is mandatory),
/// and `deleteCustomerCommand` types it `string | null`. It is therefore
/// modelled as nullable with empty-string normalised to `null`.
class Customer {
  final String id;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? note;

  /// Phase 4: organization customer. `fullName`/`phone`/`email` remain the
  /// contact person; the org fields are null when [isOrganization] is false.
  final bool isOrganization;
  final String? orgRegnum;
  final String? orgName;
  final String? orgEmail;

  /// Absent on the PATCH response — see the class doc.
  final DateTime? createdAt;

  const Customer({
    required this.id,
    this.fullName,
    this.phone,
    this.email,
    this.note,
    this.isOrganization = false,
    this.orgRegnum,
    this.orgName,
    this.orgEmail,
    this.createdAt,
  });

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
    id: _reqString(j, 'id'),
    fullName: _optString(j['fullName']),
    phone: _optString(j['phone']),
    email: _optString(j['email']),
    note: _optString(j['note']),
    isOrganization: j['isOrganization'] == true,
    orgRegnum: _optString(j['orgRegnum']),
    orgName: _optString(j['orgName']),
    orgEmail: _optString(j['orgEmail']),
    createdAt: _optDate(j['createdAt']),
  );

  /// The contact person (or phone) label, ignoring the organization.
  String get contactName => fullName ?? phone ?? 'Нэргүй';

  /// «РД 1234567» for organization customers with a registry number, else null.
  String? get orgRegnumLabel {
    final r = orgRegnum?.trim() ?? '';
    return isOrganization && r.isNotEmpty ? 'РД $r' : null;
  }

  /// Never empty. Organizations show [orgName] as the primary label; others
  /// fall back to the name, then the phone, then a placeholder, so a
  /// phone-only walk-in customer still renders a label.
  String get displayName =>
      (isOrganization && orgName != null) ? orgName! : contactName;
}

/// `GET /api/v1/ebarimt/org?regno=` — flat `{regno, name}`.
class OrgLookupResult {
  const OrgLookupResult({required this.regno, required this.name});
  final String regno;
  final String name;

  /// Null when `name` is missing/blank (unusable result).
  static OrgLookupResult? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = _optString(raw['name']);
    if (name == null) return null;
    return OrgLookupResult(regno: _optString(raw['regno']) ?? '', name: name);
  }
}

/// Machine codes of `GET /ebarimt/org`.
abstract final class OrgLookupErrorCode {
  static const notFound = 'ORG_NOT_FOUND';
  static const regnoInvalid = 'ORG_REGNO_INVALID';
  static const lookupFailed = 'ORG_LOOKUP_FAILED';
}

/// The `vehicle` sub-object of `GET /customers/[id]`'s `vehicles[]`.
/// Selected fields: `{id, plate, vin, make, model, year, mileage}`.
class CustomerVehicleRef {
  final String id;
  final String? plate;
  final String? vin;
  final String? make;
  final String? model;
  final int? year;
  final int? mileage;

  const CustomerVehicleRef({
    required this.id,
    this.plate,
    this.vin,
    this.make,
    this.model,
    this.year,
    this.mileage,
  });

  factory CustomerVehicleRef.fromJson(Map<String, dynamic> j) =>
      CustomerVehicleRef(
        id: _reqString(j, 'id'),
        plate: _optString(j['plate']),
        vin: _optString(j['vin']),
        make: _optString(j['make']),
        model: _optString(j['model']),
        year: _optInt(j['year']),
        mileage: _optInt(j['mileage']),
      );

  String get displayName {
    final parts = [make, model].whereType<String>().toList(growable: false);
    if (parts.isEmpty) return plate ?? 'Тодорхойгүй';
    return parts.join(' ');
  }
}

/// One row of `GET /customers/[id]`'s `vehicles[]`:
/// `{id, isPostpaid, vehicle, orderCount}`.
///
/// [id] is the **TenantVehicle** link id, not the vehicle's own id — the
/// route maps `tv.id`. The vehicle's id lives on [vehicle]. Conflating the
/// two would address the wrong row on any later mutation, so they are kept
/// separate deliberately.
class CustomerVehicleLink {
  final String id;
  final bool isPostpaid;
  final CustomerVehicleRef? vehicle;

  /// Tenant-scoped `ServiceOrder` count for this vehicle. The route always
  /// emits it (`?? 0`), so an absent/invalid value degrades to `0`.
  final int orderCount;

  const CustomerVehicleLink({
    required this.id,
    this.isPostpaid = false,
    this.vehicle,
    this.orderCount = 0,
  });

  factory CustomerVehicleLink.fromJson(Map<String, dynamic> j) {
    final vehicle = _optMap(j['vehicle']);
    return CustomerVehicleLink(
      id: _reqString(j, 'id'),
      isPostpaid: j['isPostpaid'] == true,
      // A malformed nested vehicle degrades to null rather than discarding
      // the whole link — the link id and postpaid flag are still usable.
      vehicle: vehicle == null ? null : _tryVehicle(vehicle),
      orderCount: _optInt(j['orderCount']) ?? 0,
    );
  }

  static CustomerVehicleRef? _tryVehicle(Map<String, dynamic> json) {
    try {
      return CustomerVehicleRef.fromJson(json);
    } on CustomerParseException {
      return null;
    }
  }
}

/// `GET /customers/[id]` — `{customer, vehicles}`.
class CustomerDetail {
  final Customer customer;
  final List<CustomerVehicleLink> vehicles;

  const CustomerDetail({required this.customer, this.vehicles = const []});
}

/// `POST /customers` outcome.
///
/// The route returns **201 for a genuine create and 200 for an
/// account-claim or a reuse of the tenant's existing account-linked
/// customer** (`createCustomerCommand`'s `"created"` / `"claimed"` /
/// `"existing"` outcomes). Both are success; the HTTP status is the only
/// signal on the wire, since the body is `{customer}` either way and the
/// `outcome` discriminant is not serialized.
///
/// [created] therefore means "201" and nothing finer — `claimed` and
/// `existing` are indistinguishable to a client and are both reported as
/// `created: false`. Do not synthesise a three-way outcome here; the server
/// does not send one.
class CustomerCreateResult {
  final Customer customer;
  final bool created;

  const CustomerCreateResult({required this.customer, required this.created});
}

/// `DELETE /customers/[id]` — `{ok, id, fullName}`.
class CustomerDeleteResult {
  final String id;
  final String? fullName;
  final bool ok;

  const CustomerDeleteResult({required this.id, this.fullName, this.ok = true});
}

/// One row of `GET /customers/[id]/history`'s `orders[]`, straight from
/// `CustomerHistoryOrder` in `lib/customers/customer-history.ts`.
///
/// [status] and [paymentStatus] are carried as **raw strings**, not as the
/// Orders feature's `OrderStatus`/`PaymentStatus` enums. The history module
/// types them `string` and this slice freezes the customers contract only;
/// mapping them onto the Orders enums would couple two features' contracts
/// together for a purely presentational gain and is left to the presentation
/// slice that needs it.
///
/// [totalAmount] is likewise the raw decimal string the server produces
/// (`Decimal.toString()`), never a parsed double — matching how the
/// Appointments refund payload carries its amount.
class CustomerHistoryOrder {
  final String id;
  final String? number;
  final String? status;
  final String? paymentStatus;
  final DateTime? scheduledAt;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final String? totalAmount;
  final String? branchName;
  final int itemCount;
  final CustomerVehicleRef? vehicle;

  const CustomerHistoryOrder({
    required this.id,
    this.number,
    this.status,
    this.paymentStatus,
    this.scheduledAt,
    this.completedAt,
    this.createdAt,
    this.totalAmount,
    this.branchName,
    this.itemCount = 0,
    this.vehicle,
  });

  factory CustomerHistoryOrder.fromJson(Map<String, dynamic> j) {
    final branch = _optMap(j['branch']);
    final vehicle = _optMap(j['vehicle']);
    return CustomerHistoryOrder(
      id: _reqString(j, 'id'),
      number: _optString(j['number']),
      status: _optString(j['status']),
      paymentStatus: _optString(j['paymentStatus']),
      scheduledAt: _optDate(j['scheduledAt']),
      completedAt: _optDate(j['completedAt']),
      createdAt: _optDate(j['createdAt']),
      totalAmount: _optString(j['totalAmount']),
      branchName: branch == null ? null : _optString(branch['name']),
      itemCount: _optInt(j['itemCount']) ?? 0,
      vehicle: vehicle == null
          ? null
          : CustomerVehicleLink._tryVehicle(vehicle),
    );
  }
}

/// `POST /customers/notify` — `{notified}`.
///
/// Recorded behaviour from `sendCustomerBroadcast`'s own doc comment, so no
/// caller re-derives it: a zero-recipient send still consumes one of the
/// day's sends, because the audit row doubles as the rate-limit counter.
/// [notified] counts recipients reached, never "sends remaining".
class CustomerBroadcastResult {
  final int notified;

  const CustomerBroadcastResult({required this.notified});
}

// ─── Helpers ────────────────────────────────────────────────────────────────

String _reqString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw CustomerParseException('$key талбар буруу байна.');
  }
  return value.trim();
}

String? _optString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _optDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toLocal();
}

/// Tolerates the JSON-number ambiguity: `year`/`mileage`/`orderCount` are
/// integers server-side, but a double that happens to be whole (`2019.0`)
/// must not degrade to null.
int? _optInt(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble() && value.isFinite) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

Map<String, dynamic>? _optMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}
