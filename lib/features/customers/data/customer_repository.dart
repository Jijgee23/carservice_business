import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/data/customer_dto.dart';
import 'package:carservice_business/features/customers/data/customers_data_source.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';

/// Remote adapter for [CustomersRepository] — P3-F1. JSON and Dio stay below
/// the repository contract; controllers depend on [CustomersRepository] or
/// the fake, matching `RemoteAppointmentsRepository`.
class RemoteCustomersRepository implements CustomersRepository {
  RemoteCustomersRepository({CustomersDataSource? dataSource})
    : _dataSource = dataSource ?? RemoteCustomersDataSource();

  final CustomersDataSource _dataSource;

  @override
  Future<Result<PagedResult<Customer>>> getCustomers({
    CustomerListQuery? query,
  }) async {
    final effective = query ?? const CustomerListQuery();
    try {
      final parsed = CustomerPageDto.fromJson(
        await _dataSource.list(_listQuery(effective)),
      );
      return Ok(
        PagedResult(items: parsed.items, pagination: parsed.pagination),
      );
    } catch (error) {
      return Err(_error(error, 'Үйлчлүүлэгчийн жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<CustomerDetail>> getCustomer(String customerId) async {
    try {
      return Ok(
        CustomerDetailDto.fromJson(await _dataSource.detail(customerId)).value,
      );
    } catch (error) {
      return Err(_error(error, 'Үйлчлүүлэгчийн мэдээлэл ачаалж чадсангүй'));
    }
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
    try {
      final envelope = await _dataSource.create({
        'fullName': fullName ?? '',
        'phone': phone,
        'email': email,
        'note': note,
        ...orgBody(isOrganization, orgRegnum, orgName, orgEmail),
      });
      // 201 = genuine create, 200 = account-claim or reuse. Both success.
      return Ok(
        CustomerCreateResult(
          customer: CustomerEnvelopeDto.fromJson(envelope.data).value,
          created: envelope.statusCode == 201,
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Үйлчлүүлэгч бүртгэж чадсангүй'));
    }
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
    try {
      // Full-state PATCH: the route coerces every absent field, so all four
      // are always sent. See `CustomersRepository.updateCustomer`.
      return Ok(
        CustomerEnvelopeDto.fromJson(
          await _dataSource.update(customerId, {
            'fullName': fullName ?? '',
            'phone': phone,
            'email': email,
            'note': note,
            ...orgBody(isOrganization, orgRegnum, orgName, orgEmail),
          }),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Үйлчлүүлэгч засварлаж чадсангүй'));
    }
  }

  @override
  Future<Result<CustomerDeleteResult>> deleteCustomer(String customerId) async {
    try {
      return Ok(
        CustomerDeleteResultDto.fromJson(
          await _dataSource.delete(customerId),
          requestedId: customerId,
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Үйлчлүүлэгч устгаж чадсангүй'));
    }
  }

  @override
  Future<Result<PagedResult<CustomerHistoryOrder>>> getCustomerHistory(
    String customerId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final parsed = CustomerHistoryPageDto.fromJson(
        await _dataSource.history(customerId, {
          'page': page,
          'pageSize': pageSize,
        }),
      );
      return Ok(
        PagedResult(items: parsed.items, pagination: parsed.pagination),
      );
    } catch (error) {
      return Err(_error(error, 'Үйлчилгээний түүх ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<int>> getBroadcastRecipientCount() async {
    try {
      return Ok(
        BroadcastRecipientCountDto.fromJson(await _dataSource.notifyCount())
            .value,
      );
    } catch (error) {
      return Err(_error(error, 'Хүлээн авагчийн тоо ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<OrgLookupResult>> lookupOrg(String regno) async {
    try {
      final parsed = OrgLookupResult.tryParse(
        await _dataSource.orgLookup(regno),
      );
      if (parsed == null) {
        return const Err(
          AppError(
            ErrorKind.unknown,
            'Байгууллагын мэдээлэл олдсонгүй.',
            code: OrgLookupErrorCode.notFound,
          ),
        );
      }
      return Ok(parsed);
    } catch (error) {
      return Err(_error(error, 'Байгууллагын мэдээлэл татаж чадсангүй'));
    }
  }

  @override
  Future<Result<CustomerBroadcastResult>> sendBroadcast({
    required String title,
    required String body,
  }) async {
    try {
      return Ok(
        CustomerBroadcastResultDto.fromJson(
          await _dataSource.notify({'title': title, 'body': body}),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Зар илгээж чадсангүй'));
    }
  }
}

/// Only the allow-listed params ever go on the wire — anything else is
/// a 400 from `rejectUnknownParams`. `limit` is the accepted alias of
/// `pageSize` and is never sent alongside it.
/// Org fields are always sent explicitly; when off they are null so the
/// server clears them (contract: "when off: org fields saved as null").
Map<String, dynamic> orgBody(
  bool isOrganization,
  String? orgRegnum,
  String? orgName,
  String? orgEmail,
) => {
  'isOrganization': isOrganization,
  'orgRegnum': isOrganization ? orgRegnum : null,
  'orgName': isOrganization ? orgName : null,
  'orgEmail': isOrganization ? orgEmail : null,
};

Map<String, dynamic> _listQuery(CustomerListQuery query) => {
  'page': query.page,
  'pageSize': query.pageSize,
  if (query.kind != null) 'kind': query.kind!.wire,
  if (query.q != null && query.q!.trim().isNotEmpty) 'q': query.q!.trim(),
};

AppError _error(Object error, String fallback) => switch (error) {
  AppError value => value,
  CustomerParseException value => AppError(ErrorKind.unknown, value.message),
  _ => AppError(ErrorKind.unknown, fallback),
};
