import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';

/// `?kind=` values of `GET /api/v1/customers`.
enum CustomerKindFilter {
  org('org'),
  person('person');

  const CustomerKindFilter(this.wire);
  final String wire;
}

/// Server-side filters supported by `GET /api/v1/customers`.
///
/// The route parses through `parseCustomerListQuery`
/// (`lib/customers/customer-list-query.ts`), which calls
/// `rejectUnknownParams` with the allow-list
/// `["q", "page", "pageSize", "limit"]` and **returns 400 for any other
/// param**. This class exists so that allow-list is expressed exactly once
/// on the client: there is deliberately no free-form map of extra filters,
/// because sending one would be an automatic 400.
///
/// `pageSize` is validated by `parsePagination` against `MAX_PAGE_SIZE = 100`
/// — a larger value is a 400, not a silent clamp. [maxPageSize] mirrors it so
/// a caller can refuse before the round trip.
class CustomerListQuery {
  /// `?q=` — matched server-side by `buildCustomerListWhere` as an `OR` over
  /// exactly three fields: `fullName` (case-insensitive `contains`), `phone`
  /// (**case-sensitive** — phone numbers have no case) and `email`
  /// (case-insensitive). Not the note, and not the customer's vehicles.
  ///
  /// `optionalText` trims and maps an empty result to `undefined`, so an
  /// all-whitespace `q` is the same as none — callers still omit it rather
  /// than sending a vacuous parameter, matching `AppointmentListQuery`.
  final String? q;

  /// `?kind=org|person` (Phase 4). Null omits the param.
  final CustomerKindFilter? kind;
  final int page;
  final int pageSize;

  /// `MAX_PAGE_SIZE` in `lib/list-query-params.ts`.
  static const maxPageSize = 100;

  const CustomerListQuery({
    this.q,
    this.kind,
    this.page = 1,
    this.pageSize = 50,
  });
}

/// One frozen repository contract for the Customers feature — P3-F1.
///
/// One named method per backend route+verb under `app/api/v1/customers/`,
/// eight in total. No generic `request(path)` escape hatch: a route that is
/// not on this interface is a route this app does not call.
///
/// Results are `Result<T>`; a failure carries an `AppError` whose
/// `statusCode`/`code`/`fieldErrors` survive from the consolidated
/// `mapDioException` (P3-D2), and `CustomerFailure.classify` turns that
/// triple into the typed cases documented on [CustomerFailure].
abstract interface class CustomersRepository {
  /// `GET /api/v1/customers` — permission `customers.view`.
  ///
  /// P3-B0 added the permission gate, so this can now return a 403
  /// (`CustomerFailure.forbidden`) where earlier builds could not. Ordering
  /// is fixed server-side to `fullName asc` and is not part of the query
  /// contract.
  Future<Result<PagedResult<Customer>>> getCustomers({
    CustomerListQuery? query,
  });

  /// `GET /api/v1/customers/[id]` — permission `customers.view`.
  ///
  /// A cross-tenant id returns 404, never 403 — deliberately
  /// indistinguishable from a nonexistent one.
  Future<Result<CustomerDetail>> getCustomer(String customerId);

  /// `POST /api/v1/customers` — permission `customers.create` + an active
  /// subscription.
  ///
  /// Success is **201 OR 200**: 201 for a genuine create, 200 when
  /// `createCustomerCommand` claimed an unclaimed walk-in row or reused the
  /// tenant's existing account-linked customer. Both land in `Ok`; see
  /// [CustomerCreateResult.created].
  ///
  /// Only [phone] is mandatory server-side ([fullName] may be empty).
  Future<Result<CustomerCreateResult>> createCustomer({
    String? fullName,
    required String phone,
    String? email,
    String? note,
    bool isOrganization = false,
    String? orgRegnum,
    String? orgName,
    String? orgEmail,
  });

  /// `PATCH /api/v1/customers/[id]` — permission `customers.edit` + an
  /// active subscription.
  ///
  /// Not a partial update despite the verb: the route reads all four fields
  /// off the body and coerces a non-string to `""`/`null`, so an omitted
  /// `note` **clears** the note. Every field is therefore required-with-
  /// nullable here, forcing the caller to pass the full intended state
  /// rather than accidentally blanking a field it did not mean to touch.
  ///
  /// The response omits `createdAt` — see [Customer].
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
  });

  /// `DELETE /api/v1/customers/[id]` — permission `customers.delete` + an
  /// active subscription. A customer with service orders is a 409
  /// `CUSTOMER_IN_USE` (`CustomerFailure.inUse`), never a 500.
  Future<Result<CustomerDeleteResult>> deleteCustomer(String customerId);

  /// `GET /api/v1/customers/[id]/history` — permission `customers.view`.
  ///
  /// Paginated through `getApiPageInfo`, which is a **different** parser
  /// from the list route's: it silently clamps rather than rejecting, has no
  /// unknown-param rejection, defaults `pageSize` to 50 and caps it at 200.
  /// The envelope key is `meta`, not `pagination`.
  Future<Result<PagedResult<CustomerHistoryOrder>>> getCustomerHistory(
    String customerId, {
    int page,
    int pageSize,
  });

  /// `GET /api/v1/customers/notify` — permission `customers.notify` + an
  /// active subscription. Recipient preview only, no side effects.
  ///
  /// Counts account-linked customers only: `accountId: null` walk-ins are
  /// never recipients and are never counted.
  Future<Result<int>> getBroadcastRecipientCount();

  /// `POST /api/v1/customers/notify` — permission `customers.notify` + an
  /// active subscription.
  ///
  /// Both fields are trimmed and mandatory server-side; an empty one is a
  /// 422 with `fieldErrors` keyed `title` / `body`.
  Future<Result<CustomerBroadcastResult>> sendBroadcast({
    required String title,
    required String body,
  });

  /// `GET /api/v1/ebarimt/org?regno=` — staff-auth, rate-limited. Failures
  /// carry `code` [OrgLookupErrorCode] (404 not found, 422 bad regno, 502
  /// upstream). Callers must never block saving on a failure.
  Future<Result<OrgLookupResult>> lookupOrg(String regno);
}
