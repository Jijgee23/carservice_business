import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:dio/dio.dart';

/// Thin transport seam — JSON and Dio stay below the repository contract,
/// exactly like `OrdersDataSource`. Endpoints mirror
/// `app/api/v1/appointments/` (P2-B2–P2-B6).
abstract interface class AppointmentsDataSource {
  Future<Object?> list(Map<String, dynamic> query);
  Future<Object?> detail(String id);
  Future<Object?> slots(Map<String, dynamic> query);
  Future<Object?> calendar(Map<String, dynamic> query);
  Future<Object?> create(Map<String, dynamic> body);
  Future<Object?> confirm(String id, {Map<String, dynamic>? body});
  Future<Object?> update(String id, Map<String, dynamic> body);
  Future<Object?> reject(String id);
  Future<Object?> noShow(String id);
  Future<Object?> arrived(String id);
  Future<Object?> cancel(String id);
  Future<Object?> reschedule(String id, Map<String, dynamic> body);
  Future<Object?> bulkCategory(Map<String, dynamic> body);
  Future<Object?> checkPayment(String id);
  Future<Object?> retryPayment(String id);
  Future<Object?> refundPayment(String id, Map<String, dynamic> body);
}

class RemoteAppointmentsDataSource implements AppointmentsDataSource {
  RemoteAppointmentsDataSource({Dio? dio})
    : _dio = dio ?? ApiService.instance.dio;

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
        options: Options(method: method),
      );
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  @override
  Future<Object?> list(Map<String, dynamic> query) async =>
      (await _request('appointments', 'GET', query: query)).data;

  @override
  Future<Object?> slots(Map<String, dynamic> query) async =>
      (await _request('appointments/slots', 'GET', query: query)).data;

  @override
  Future<Object?> calendar(Map<String, dynamic> query) async =>
      (await _request('appointments/calendar', 'GET', query: query)).data;

  @override
  Future<Object?> create(Map<String, dynamic> body) async =>
      (await _request('appointments', 'POST', body: body)).data;

  @override
  Future<Object?> confirm(String id, {Map<String, dynamic>? body}) async =>
      (await _request(
        'appointments/${Uri.encodeComponent(id)}/confirm',
        'POST',
        body: body,
      )).data;

  @override
  Future<Object?> update(String id, Map<String, dynamic> body) async =>
      (await _request(
        'appointments/${Uri.encodeComponent(id)}',
        'PATCH',
        body: body,
      )).data;

  @override
  Future<Object?> reject(String id) async => (await _request(
    'appointments/${Uri.encodeComponent(id)}/reject',
    'POST',
  )).data;

  @override
  Future<Object?> noShow(String id) async => (await _request(
    'appointments/${Uri.encodeComponent(id)}/no-show',
    'POST',
  )).data;

  @override
  Future<Object?> arrived(String id) async => (await _request(
    'appointments/${Uri.encodeComponent(id)}/arrived',
    'POST',
  )).data;

  @override
  Future<Object?> detail(String id) async =>
      (await _request('appointments/${Uri.encodeComponent(id)}', 'GET')).data;

  @override
  Future<Object?> cancel(String id) async => (await _request(
    'appointments/${Uri.encodeComponent(id)}',
    'PATCH',
    body: {'status': 'CANCELLED'},
  )).data;

  @override
  Future<Object?> reschedule(String id, Map<String, dynamic> body) async =>
      (await _request(
        'appointments/${Uri.encodeComponent(id)}/reschedule',
        'POST',
        body: body,
      )).data;

  @override
  Future<Object?> bulkCategory(Map<String, dynamic> body) async =>
      (await _request('appointments/bulk/category', 'POST', body: body)).data;

  @override
  Future<Object?> checkPayment(String id) async => (await _request(
    'appointments/${Uri.encodeComponent(id)}/payment',
    'POST',
  )).data;

  @override
  Future<Object?> retryPayment(String id) async => (await _request(
    'appointments/${Uri.encodeComponent(id)}/payment/retry',
    'POST',
  )).data;

  @override
  Future<Object?> refundPayment(String id, Map<String, dynamic> body) async =>
      (await _request(
        'appointments/${Uri.encodeComponent(id)}/payment/refund',
        'POST',
        body: body,
      )).data;
}

// Error mapping now lives in `mapDioException`
// (lib/core/network/dio_error_mapper.dart), shared with
// `RemoteOrdersDataSource` and the generic client's `apiOrThrow`. 409
// (transition/reservation conflict) and 422 (field errors) are deliberately
// NOT collapsed into a shared kind there — callers distinguish them via
// `statusCode`, matching the invariant that P2-F4 binds field errors while a
// 409 triggers a slot re-fetch, never a blind retry.
