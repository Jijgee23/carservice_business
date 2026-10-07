import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:dio/dio.dart';

/// A response body plus the HTTP status that carried it.
///
/// Only `POST /api/v1/customers` needs the status: the route returns **201
/// for a genuine create and 200 for an account-claim or reuse**, with an
/// identical `{customer}` body in both cases, so the status is the only
/// discriminant on the wire. Every other method returns the bare body, as
/// `AppointmentsDataSource` does.
typedef ApiEnvelope = ({int? statusCode, Object? data});

/// Thin transport seam — JSON and Dio stay below the repository contract,
/// exactly like `AppointmentsDataSource`. One method per route+verb under
/// `app/api/v1/customers/` (P3-B0…P3-B7).
abstract interface class CustomersDataSource {
  Future<Object?> list(Map<String, dynamic> query);
  Future<Object?> detail(String id);
  Future<ApiEnvelope> create(Map<String, dynamic> body);
  Future<Object?> update(String id, Map<String, dynamic> body);
  Future<Object?> delete(String id);
  Future<Object?> history(String id, Map<String, dynamic> query);
  Future<Object?> notifyCount();
  Future<Object?> notify(Map<String, dynamic> body);
  Future<Object?> orgLookup(String regno);
}

class RemoteCustomersDataSource implements CustomersDataSource {
  RemoteCustomersDataSource({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  Future<Response<dynamic>> _request(
    String path,
    String method, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    try {
      return await _dio.request(
        path,
        queryParameters: query,
        data: body,
        options: Options(
          method: method,
          // `POST /customers` uses 200 and 201 interchangeably for success.
          // Dio's default validator already accepts both, but stating the
          // range here stops a future default change from turning a
          // legitimate 201 claim-vs-create distinction into a DioException.
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
    } on DioException catch (error) {
      // The consolidated P3-D2 mapper — 409 and 422 stay distinguishable and
      // keep `statusCode` / `code` / `fieldErrors`, which the customers
      // contract depends on (phone conflict, validation, plan limit).
      // Deliberately NOT a fourth local `_toAppError`.
      throw mapDioException(error);
    }
  }

  static String _path(String id, [String? suffix]) {
    final base = 'customers/${Uri.encodeComponent(id)}';
    return suffix == null ? base : '$base/$suffix';
  }

  @override
  Future<Object?> list(Map<String, dynamic> query) async =>
      (await _request('customers', 'GET', query: query)).data;

  @override
  Future<Object?> detail(String id) async =>
      (await _request(_path(id), 'GET')).data;

  @override
  Future<ApiEnvelope> create(Map<String, dynamic> body) async {
    final response = await _request('customers', 'POST', body: body);
    return (statusCode: response.statusCode, data: response.data);
  }

  @override
  Future<Object?> update(String id, Map<String, dynamic> body) async =>
      (await _request(_path(id), 'PATCH', body: body)).data;

  @override
  Future<Object?> delete(String id) async =>
      (await _request(_path(id), 'DELETE')).data;

  @override
  Future<Object?> history(String id, Map<String, dynamic> query) async =>
      (await _request(_path(id, 'history'), 'GET', query: query)).data;

  @override
  Future<Object?> notifyCount() async =>
      (await _request('customers/notify', 'GET')).data;

  @override
  Future<Object?> notify(Map<String, dynamic> body) async =>
      (await _request('customers/notify', 'POST', body: body)).data;

  @override
  Future<Object?> orgLookup(String regno) async =>
      (await _request('ebarimt/org', 'GET', query: {'regno': regno})).data;
}
