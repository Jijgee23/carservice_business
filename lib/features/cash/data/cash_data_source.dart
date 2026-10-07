import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:dio/dio.dart';

/// Thin transport seam over `/api/v1/cash/*` and `/banks`.
abstract interface class CashDataSource {
  Future<Object?> banks();
  Future<Object?> sessionOpenFlag(String branchId);
  Future<Object?> eligibleOrders(String customerId, String branchId);
  Future<Object?> createSettlement(Map<String, Object?> body);
}

class RemoteCashDataSource implements CashDataSource {
  RemoteCashDataSource({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  Future<Object?> _send(
    String path,
    String method, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    try {
      return (await _dio.request(
        path,
        queryParameters: query,
        data: body,
        options: Options(method: method),
      )).data;
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  @override
  Future<Object?> banks() => _send('banks', 'GET');

  @override
  Future<Object?> sessionOpenFlag(String branchId) =>
      _send('cash/sessions/open-flag', 'GET', query: {'branchId': branchId});

  @override
  Future<Object?> eligibleOrders(String customerId, String branchId) => _send(
    'cash/settlements/eligible',
    'GET',
    query: {'customerId': customerId, 'branchId': branchId},
  );

  @override
  Future<Object?> createSettlement(Map<String, Object?> body) =>
      _send('cash/settlements', 'POST', body: body);
}
