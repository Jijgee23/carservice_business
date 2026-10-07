import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:dio/dio.dart';

/// Thin transport seam — JSON and Dio stay below the repository contract,
/// exactly like `AppointmentsDataSource` and `OrdersDataSource`. Endpoints
/// mirror `app/api/v1/vehicles/` (P3-B2, P3-B4, P3-B5, P3-B6).
abstract interface class VehiclesDataSource {
  Future<Object?> list(Map<String, dynamic> query);
  Future<Object?> detail(String id);
  Future<Object?> create(Map<String, dynamic> body);
  Future<Object?> update(String id, Map<String, dynamic> body);
  Future<Object?> delete(String id);
  Future<Object?> history(String id);
  Future<Object?> vinHistory(String id);
  Future<Object?> refreshHur(String id);
}

class RemoteVehiclesDataSource implements VehiclesDataSource {
  RemoteVehiclesDataSource({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  /// Error mapping uses the single consolidated `mapDioException`
  /// (`lib/core/network/dio_error_mapper.dart`, P3-D2). This slice adds no
  /// mapper of its own — a fourth copy is a slice failure. The consolidated
  /// mapper is what keeps `statusCode`, the server's `code` and `fieldErrors`
  /// intact, which the vehicles contract relies on to tell
  /// `PLAN_LIMIT_REACHED`, `VALIDATION_FAILED`, `VEHICLE_OWNER_CHANGE_BLOCKED`
  /// (all 422) and `VEHICLE_IN_USE` (409) apart.
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
      (await _request('vehicles', 'GET', query: query)).data;

  @override
  Future<Object?> detail(String id) async =>
      (await _request('vehicles/${Uri.encodeComponent(id)}', 'GET')).data;

  @override
  Future<Object?> create(Map<String, dynamic> body) async =>
      (await _request('vehicles', 'POST', body: body)).data;

  @override
  Future<Object?> update(String id, Map<String, dynamic> body) async =>
      (await _request(
        'vehicles/${Uri.encodeComponent(id)}',
        'PATCH',
        body: body,
      )).data;

  @override
  Future<Object?> delete(String id) async =>
      (await _request('vehicles/${Uri.encodeComponent(id)}', 'DELETE')).data;

  @override
  Future<Object?> history(String id) async => (await _request(
    'vehicles/${Uri.encodeComponent(id)}/history',
    'GET',
  )).data;

  @override
  Future<Object?> vinHistory(String id) async => (await _request(
    'vehicles/${Uri.encodeComponent(id)}/vin-history',
    'GET',
  )).data;

  @override
  Future<Object?> refreshHur(String id) async => (await _request(
    'vehicles/${Uri.encodeComponent(id)}/refresh-hur',
    'POST',
  )).data;
}
