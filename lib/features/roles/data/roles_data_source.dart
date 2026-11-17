import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:dio/dio.dart';

/// Thin transport seam for `app/api/v1/roles*` — mirrors
/// `EmployeesDataSource`. Read-only: roles are global system roles managed
/// by the platform's super admin (POST/PATCH/DELETE answer 403
/// `SYSTEM_MANAGED`).
abstract interface class RolesDataSource {
  Future<Object?> list(Map<String, dynamic> query);
  Future<Object?> detail(String id);
}

class RemoteRolesDataSource implements RolesDataSource {
  RemoteRolesDataSource({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

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
      (await _request('roles', 'GET', query: query)).data;

  @override
  Future<Object?> detail(String id) async =>
      (await _request('roles/${Uri.encodeComponent(id)}', 'GET')).data;
}
