import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';

/// Hand-written fake for [CustomersRepository] — P3-F1.
///
/// Deterministic in-memory seed data; no network. Mirrors the server-side
/// rules this repository binds to so a payload the real API would reject
/// (an unknown list param, a `pageSize` over `MAX_PAGE_SIZE`, an invalid
/// phone, a duplicate walk-in phone, deleting a customer that has orders,
/// exceeding `MAX_CUSTOMERS`, an empty broadcast title) cannot pass in a
/// test that only exercises this fake.
class FakeCustomerRepository implements CustomersRepository {
  FakeCustomerRepository({
    List<Customer>? seed,
    Map<String, List<CustomerHistoryOrder>>? history,
    Set<String>? accountLinkedPhones,
    Set<String>? customersWithOrders,
    Map<String, OrgLookupResult>? orgDirectory,
    this.maxCustomers = 100,
    this.dailyBroadcastLimit = 5,
  }) : _customers = [
         ...(seed ?? [_seedCustomer()]),
       ],
       _history = {...?history},
       _accountLinkedPhones = {...?accountLinkedPhones},
       _customersWithOrders = {...?customersWithOrders},
       _orgDirectory = {...?orgDirectory};

  final List<Customer> _customers;
  final Map<String, List<CustomerHistoryOrder>> _history;

  /// regno -> org the `GET /ebarimt/org` lookup would find.
  final Map<String, OrgLookupResult> _orgDirectory;

  /// Every regno [lookupOrg] was asked for, in order.
  final List<String> lookupCalls = [];

  /// When set, [lookupOrg] fails with this error instead of consulting the
  /// directory.
  AppError? lookupFailure;

  /// Phones that have a global `Account`. `createCustomer` with one of these
  /// exercises the claim/existing path — the 200 outcome — rather than the
  /// 201 create path, mirroring `createCustomerCommand`.
  final Set<String> _accountLinkedPhones;

  /// Customer ids the server would refuse to delete with 409
  /// `CUSTOMER_IN_USE` (Prisma `P2003`).
  final Set<String> _customersWithOrders;

  /// Mirrors `PLAN_LIMIT_CODES.MAX_CUSTOMERS`, enforced on **every** create
  /// entry point since D-154.
  final int maxCustomers;

  /// Mirrors `PLAN_LIMIT_CODES.DAILY_CUSTOMER_NOTIFICATIONS`. Counted per
  /// send attempt that reached `broadcastTenantPromo`, including
  /// zero-recipient sends — the documented wart in
  /// `lib/customers/customer-broadcast.ts`.
  final int dailyBroadcastLimit;

  /// Set of customer ids whose `accountId` is non-null — the only broadcast
  /// recipients. Keyed off [_accountLinkedPhones], never off "all customers".
  Set<String> get _accountLinkedCustomerIds => _customers
      .where((c) => c.phone != null && _accountLinkedPhones.contains(c.phone))
      .map((c) => c.id)
      .toSet();

  int _broadcastsToday = 0;
  int _idSequence = 0;

  /// Snapshot of the current rows, for assertions.
  List<Customer> get customers => List.unmodifiable(_customers);

  int get broadcastsToday => _broadcastsToday;

  static Customer _seedCustomer({
    String id = 'cust-1',
    String fullName = 'Бат',
    String phone = '99001122',
  }) => Customer(
    id: id,
    fullName: fullName,
    phone: phone,
    email: 'bat@example.mn',
    createdAt: DateTime(2026, 9, 1, 8),
  );

  int _indexOf(String id) => _customers.indexWhere((c) => c.id == id);

  static Err<T> _notFound<T>() => const Err(
    AppError(
      ErrorKind.notFound,
      'Үйлчлүүлэгч олдсонгүй.',
      statusCode: 404,
      code: CustomerErrorCode.customerNotFound,
    ),
  );

  /// Mirrors `buildCustomerListWhere`'s `OR` exactly — three clauses:
  /// `fullName` case-insensitive, `phone` **case-sensitive**, `email`
  /// case-insensitive. Not the note, not the customer's vehicles. Widening
  /// this means the fake is lying about the server.
  bool _matchesSearch(Customer c, String q) {
    final lower = q.toLowerCase();
    final name = c.fullName;
    if (name != null && name.toLowerCase().contains(lower)) return true;
    final phone = c.phone;
    if (phone != null && phone.contains(q)) return true;
    final email = c.email;
    if (email != null && email.toLowerCase().contains(lower)) return true;
    return false;
  }

  /// Mirrors `validateCustomerInput` + `normalizePhone`: only the phone is
  /// mandatory, it must normalise to 8 digits starting 5–9, and the email is
  /// optional but format-checked when present.
  static String? _normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'\D+'), '');
    if (digits.length == 11 && digits.startsWith('976')) {
      digits = digits.substring(3);
    }
    if (digits.length == 9 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length != 8) return null;
    if (!RegExp(r'^[5-9]').hasMatch(digits)) return null;
    return digits;
  }

  static final _emailFormat = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  ({
    Map<String, String> fieldErrors,
    String phone,
    String? email,
    String? note,
    String fullName,
  })
  _validate({
    String? fullName,
    required String phone,
    String? email,
    String? note,
  }) {
    final trimmedName = (fullName ?? '').trim();
    final trimmedPhone = phone.trim();
    final trimmedEmail = (email ?? '').trim();
    final trimmedNote = (note ?? '').trim();
    final fieldErrors = <String, String>{};
    final normalized = _normalizePhone(trimmedPhone);
    if (trimmedPhone.isEmpty) {
      fieldErrors['phone'] = 'Утасны дугаар оруулна уу.';
    } else if (normalized == null) {
      fieldErrors['phone'] = 'Утасны дугаар 8 оронтой тоо байх ёстой.';
    }
    if (trimmedEmail.isNotEmpty && !_emailFormat.hasMatch(trimmedEmail)) {
      fieldErrors['email'] = 'Имэйл хаяг буруу.';
    }
    return (
      fieldErrors: fieldErrors,
      phone: normalized ?? trimmedPhone,
      email: trimmedEmail.isEmpty ? null : trimmedEmail,
      note: trimmedNote.isEmpty ? null : trimmedNote,
      fullName: trimmedName,
    );
  }

  /// Mirrors the Phase 4 org rules of `validateCustomerInput`.
  static Map<String, String> _orgErrors(
    bool isOrganization,
    String? orgRegnum,
    String? orgName,
    String? orgEmail,
  ) {
    if (!isOrganization) return const {};
    final errors = <String, String>{};
    if (!RegExp(r'^\d{7}$').hasMatch((orgRegnum ?? '').trim())) {
      errors['orgRegnum'] = 'Байгууллагын регистр 7 оронтой тоо байна.';
    }
    if ((orgName ?? '').trim().isEmpty) {
      errors['orgName'] = 'Байгууллагын нэр оруулна уу.';
    }
    final email = (orgEmail ?? '').trim();
    if (email.isNotEmpty && !_emailFormat.hasMatch(email)) {
      errors['orgEmail'] = 'Имэйл хаяг буруу.';
    }
    return errors;
  }

  static Err<T> _validationError<T>(Map<String, String> fieldErrors) => Err(
    AppError(
      ErrorKind.unknown,
      'Хүсэлт буруу.',
      statusCode: 422,
      // `POST /customers` and `PATCH /customers/[id]` both take the
      // `fieldErrors` branch of `jsonError`, which does NOT pass `code`.
      // The fake omits it for the same reason — a test must not come to
      // depend on a code the wire never carries.
      fieldErrors: fieldErrors,
    ),
  );

  static const _phoneConflictMessage =
      'Энэ утасны дугаартай үйлчлүүлэгч аль хэдийн бүртгэлтэй байна.';

  @override
  Future<Result<PagedResult<Customer>>> getCustomers({
    CustomerListQuery? query,
  }) async {
    final effective = query ?? const CustomerListQuery();
    // Mirrors `parsePositiveInteger`/`parsePagination`: a bad page or an
    // over-cap pageSize is a 400, never a silent clamp.
    if (effective.page < 1) {
      return const Err(
        AppError(ErrorKind.unknown, 'page утга буруу байна.', statusCode: 400),
      );
    }
    if (effective.pageSize < 1 ||
        effective.pageSize > CustomerListQuery.maxPageSize) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'pageSize утга буруу байна.',
          statusCode: 400,
        ),
      );
    }
    final q = effective.q?.trim();
    final filtered = _customers
        .where((c) => q == null || q.isEmpty || _matchesSearch(c, q))
        .where(
          (c) => switch (effective.kind) {
            null => true,
            CustomerKindFilter.org => c.isOrganization,
            CustomerKindFilter.person => !c.isOrganization,
          },
        )
        .toList(growable: false);
    // `orderBy: { fullName: "asc" }` — fixed server-side on this route.
    final sorted = [...filtered]
      ..sort((a, b) => (a.fullName ?? '').compareTo(b.fullName ?? ''));
    final start = (effective.page - 1) * effective.pageSize;
    final page = start >= sorted.length
        ? const <Customer>[]
        : sorted.skip(start).take(effective.pageSize).toList(growable: false);
    return Ok(
      PagedResult(
        items: page,
        pagination: _meta(sorted.length, effective.page, effective.pageSize),
      ),
    );
  }

  @override
  Future<Result<CustomerDetail>> getCustomer(String customerId) async {
    final index = _indexOf(customerId);
    if (index < 0) return _notFound();
    return Ok(CustomerDetail(customer: _customers[index]));
  }

  @override
  Future<Result<CustomerCreateResult>> createCustomer({
    String? fullName,
    required String phone,
    String? email,
    String? note,
    bool isOrganization = false,
    String? orgRegnum,
    String? orgName,
    String? orgEmail,
  }) async {
    final input = _validate(
      fullName: fullName,
      phone: phone,
      email: email,
      note: note,
    );
    final orgErrors = _orgErrors(isOrganization, orgRegnum, orgName, orgEmail);
    if (input.fieldErrors.isNotEmpty || orgErrors.isNotEmpty) {
      return _validationError({...input.fieldErrors, ...orgErrors});
    }
    // MAX_CUSTOMERS is checked on every entry point (D-154), before the
    // account lookup — matching the command's ordering.
    if (_customers.length >= maxCustomers) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Үйлчлүүлэгчийн хязгаарт хүрсэн байна.',
          statusCode: 422,
          // No `code`: `POST /customers` routes a code-less
          // `CustomerCommandError` through `jsonError(status, message)`.
          // Callers classify this as `CustomerFailure.planLimit` by the
          // absence of `fieldErrors`, and the fake must not hand them a
          // discriminator the server does not send.
        ),
      );
    }
    final accountLinked = _accountLinkedPhones.contains(input.phone);
    if (accountLinked) {
      final existing = _customers
          .where((c) => c.phone == input.phone)
          .cast<Customer?>()
          .firstWhere((c) => true, orElse: () => null);
      if (existing != null) {
        // "existing" or "claimed" — both are HTTP 200, and the two are
        // indistinguishable to a client. See `CustomerCreateResult.created`.
        return Ok(CustomerCreateResult(customer: existing, created: false));
      }
    } else if (_customers.any((c) => c.phone == input.phone)) {
      // Partial unique index on `(tenantId, phone) WHERE accountId IS NULL`
      // → Prisma P2002 → 409 PHONE_CONFLICT with fieldErrors, no `code`.
      return const Err(
        AppError(
          ErrorKind.unknown,
          _phoneConflictMessage,
          statusCode: 409,
          fieldErrors: {'phone': _phoneConflictMessage},
        ),
      );
    }
    final created = Customer(
      id: 'cust-${++_idSequence}-new',
      fullName: input.fullName.isEmpty ? null : input.fullName,
      phone: input.phone,
      email: input.email,
      note: input.note,
      isOrganization: isOrganization,
      orgRegnum: isOrganization ? orgRegnum!.trim() : null,
      orgName: isOrganization ? orgName!.trim() : null,
      orgEmail: isOrganization && (orgEmail ?? '').trim().isNotEmpty
          ? orgEmail!.trim()
          : null,
      createdAt: DateTime(2026, 9, 22, 12),
    );
    _customers.add(created);
    return Ok(CustomerCreateResult(customer: created, created: true));
  }

  @override
  Future<Result<Customer>> updateCustomer(
    String customerId, {
    required String? fullName,
    required String phone,
    required String? email,
    required String? note,
    bool isOrganization = false,
    String? orgRegnum,
    String? orgName,
    String? orgEmail,
  }) async {
    final input = _validate(
      fullName: fullName,
      phone: phone,
      email: email,
      note: note,
    );
    final orgErrors = _orgErrors(isOrganization, orgRegnum, orgName, orgEmail);
    if (input.fieldErrors.isNotEmpty || orgErrors.isNotEmpty) {
      return _validationError({...input.fieldErrors, ...orgErrors});
    }
    final index = _indexOf(customerId);
    if (index < 0) return _notFound();
    if (_customers.any((c) => c.id != customerId && c.phone == input.phone)) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          _phoneConflictMessage,
          statusCode: 409,
          fieldErrors: {'phone': _phoneConflictMessage},
        ),
      );
    }
    // The route echoes `NormalizedCustomerData & {id}` — deliberately WITHOUT
    // `createdAt`, so the fake drops it too. A test that relies on a
    // `createdAt` surviving an edit is relying on something the server does
    // not send.
    final updated = Customer(
      id: customerId,
      fullName: input.fullName.isEmpty ? null : input.fullName,
      phone: input.phone,
      email: input.email,
      note: input.note,
      isOrganization: isOrganization,
      orgRegnum: isOrganization ? orgRegnum!.trim() : null,
      orgName: isOrganization ? orgName!.trim() : null,
      orgEmail: isOrganization && (orgEmail ?? '').trim().isNotEmpty
          ? orgEmail!.trim()
          : null,
    );
    _customers[index] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<CustomerDeleteResult>> deleteCustomer(String customerId) async {
    final index = _indexOf(customerId);
    if (index < 0) return _notFound();
    if (_customersWithOrders.contains(customerId)) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Энэ үйлчлүүлэгчтэй холбоотой засварын хуудас байгаа тул устгах боломжгүй.',
          statusCode: 409,
          code: CustomerErrorCode.customerInUse,
        ),
      );
    }
    final removed = _customers.removeAt(index);
    _history.remove(customerId);
    return Ok(CustomerDeleteResult(id: removed.id, fullName: removed.fullName));
  }

  @override
  Future<Result<PagedResult<CustomerHistoryOrder>>> getCustomerHistory(
    String customerId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (_indexOf(customerId) < 0) return _notFound();
    // `getApiPageInfo` clamps rather than rejecting — pageSize into
    // [1, 200], page to at least 1. Mirrored exactly, because a caller that
    // sends 0 gets a page here, not an error.
    final effectivePage = page < 1 ? 1 : page;
    final effectiveSize = pageSize < 1 ? 50 : (pageSize > 200 ? 200 : pageSize);
    final rows = _history[customerId] ?? const <CustomerHistoryOrder>[];
    final start = (effectivePage - 1) * effectiveSize;
    final slice = start >= rows.length
        ? const <CustomerHistoryOrder>[]
        : rows.skip(start).take(effectiveSize).toList(growable: false);
    return Ok(
      PagedResult(
        items: slice,
        pagination: _meta(rows.length, effectivePage, effectiveSize),
      ),
    );
  }

  @override
  Future<Result<OrgLookupResult>> lookupOrg(String regno) async {
    lookupCalls.add(regno);
    if (lookupFailure != null) return Err(lookupFailure!);
    if (!RegExp(r'^\d{7}$').hasMatch(regno)) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Регистр буруу.',
          statusCode: 422,
          code: OrgLookupErrorCode.regnoInvalid,
        ),
      );
    }
    final found = _orgDirectory[regno];
    if (found == null) {
      return const Err(
        AppError(
          ErrorKind.notFound,
          'Байгууллага олдсонгүй.',
          statusCode: 404,
          code: OrgLookupErrorCode.notFound,
        ),
      );
    }
    return Ok(found);
  }

  @override
  Future<Result<int>> getBroadcastRecipientCount() async =>
      Ok(_accountLinkedCustomerIds.length);

  @override
  Future<Result<CustomerBroadcastResult>> sendBroadcast({
    required String title,
    required String body,
  }) async {
    final fieldErrors = <String, String>{};
    if (title.trim().isEmpty) fieldErrors['title'] = 'Гарчиг оруулна уу.';
    if (body.trim().isEmpty) fieldErrors['body'] = 'Агуулга оруулна уу.';
    if (fieldErrors.isNotEmpty) return _validationError(fieldErrors);
    if (_broadcastsToday >= dailyBroadcastLimit) {
      return const Err(
        AppError(
          ErrorKind.unknown,
          'Өдрийн зар илгээх хязгаарт хүрсэн байна.',
          statusCode: 422,
          // This route DOES pass `code` for the limit case — unlike
          // `POST /customers`. Kept faithful to that asymmetry.
          code: CustomerErrorCode.dailyLimitReached,
        ),
      );
    }
    // A zero-recipient send still consumes one of the day's sends.
    _broadcastsToday++;
    return Ok(
      CustomerBroadcastResult(notified: _accountLinkedCustomerIds.length),
    );
  }
}

/// Mirrors `buildMeta` in `carservice.mn/lib/pagination.ts`, including its
/// `totalPages >= 1` clamp and its page clamping.
PaginationMeta _meta(int total, int page, int pageSize) {
  final totalPages = total <= 0 ? 1 : (total / pageSize).ceil();
  final clamped = page < 1 ? 1 : (page > totalPages ? totalPages : page);
  return PaginationMeta(
    page: clamped,
    pageSize: pageSize,
    total: total,
    totalPages: totalPages,
    hasPrev: clamped > 1,
    hasNext: clamped < totalPages,
  );
}
