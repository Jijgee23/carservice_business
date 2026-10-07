import 'dart:typed_data';

import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:dio/dio.dart';

abstract interface class OrdersDataSource {
  Future<Object?> list(Map<String, dynamic> query);
  Future<Object?> detail(String id);
  Future<Object?> create(Map<String, dynamic> body);
  Future<Object?> uploadIntake(Uint8List bytes, String filename, String mime);
  Future<Object?> patch(String id, Map<String, dynamic> body);
  Future<void> delete(String id);
  Future<Object?> expectedFinish(String id, Map<String, dynamic> body);
  Future<Object?> schedule(String id, Map<String, dynamic> body);
  Future<Object?> addItem(String id, Map<String, dynamic> body);
  Future<Object?> patchItem(
    String id,
    String itemId,
    Map<String, dynamic> body,
  );
  Future<void> deleteItem(String id, String itemId);
  Future<Object?> cancelItem(String id, String itemId);
  Future<Object?> itemStatus(
    String id,
    String itemId,
    Map<String, dynamic> body,
  );
  Future<Object?> itemPrice(
    String id,
    String itemId,
    Map<String, dynamic> body,
  );
  Future<Object?> itemHistory(String id, Map<String, dynamic> query);
  Future<Object?> payments(String id);
  Future<Object?> createPayment(String id, Map<String, dynamic> body);
  Future<Object?> reversePayment(String id, String paymentId);
  Future<Object?> banks();
  Future<Object?> qpay(String id);
  Future<Object?> createQPay(String id, {String? amount});
  Future<Object?> checkQPay(String id, Map<String, dynamic> body);
  Future<void> cancelQPay(String id, Map<String, dynamic> body);
  Future<Object?> postpaid(Map<String, dynamic> query);
  Future<Object?> assignableUsers(Map<String, dynamic> query);
  Future<Object?> bulkStatus(Map<String, dynamic> body);
  Future<Object?> bulkAssign(Map<String, dynamic> body);
}

class RemoteOrdersDataSource implements OrdersDataSource {
  RemoteOrdersDataSource({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

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
      (await _request('orders', 'GET', query: query)).data;

  @override
  Future<Object?> detail(String id) async =>
      (await _request('orders/${Uri.encodeComponent(id)}', 'GET')).data;

  @override
  Future<Object?> create(Map<String, dynamic> body) async =>
      (await _request('orders', 'POST', body: body)).data;

  @override
  Future<Object?> uploadIntake(
    Uint8List bytes,
    String filename,
    String mime,
  ) async {
    final form = FormData.fromMap({
      'kind': 'intake',
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mime),
      ),
    });
    return (await _request('uploads', 'POST', body: form)).data;
  }

  @override
  Future<Object?> patch(String id, Map<String, dynamic> body) async =>
      (await _request(
        'orders/${Uri.encodeComponent(id)}',
        'PATCH',
        body: body,
      )).data;

  @override
  Future<void> delete(String id) async {
    await _request('orders/${Uri.encodeComponent(id)}', 'DELETE');
  }

  @override
  Future<Object?> expectedFinish(String id, Map<String, dynamic> body) async =>
      (await _request(
        'orders/${Uri.encodeComponent(id)}/expected-finish',
        'PATCH',
        body: body,
      )).data;

  @override
  Future<Object?> schedule(String id, Map<String, dynamic> body) async =>
      (await _request(
        'orders/${Uri.encodeComponent(id)}/schedule',
        'PATCH',
        body: body,
      )).data;

  @override
  Future<Object?> addItem(String id, Map<String, dynamic> body) async =>
      (await _request(
        'orders/${Uri.encodeComponent(id)}/items',
        'POST',
        body: body,
      )).data;

  @override
  Future<Object?> patchItem(
    String id,
    String itemId,
    Map<String, dynamic> body,
  ) async => (await _request(
    'orders/${Uri.encodeComponent(id)}/items/${Uri.encodeComponent(itemId)}',
    'PATCH',
    body: body,
  )).data;

  @override
  Future<void> deleteItem(String id, String itemId) async {
    await _request(
      'orders/${Uri.encodeComponent(id)}/items/${Uri.encodeComponent(itemId)}',
      'DELETE',
    );
  }

  @override
  Future<Object?> cancelItem(String id, String itemId) async => (await _request(
    'orders/${Uri.encodeComponent(id)}/items/${Uri.encodeComponent(itemId)}/cancel',
    'POST',
  )).data;

  @override
  Future<Object?> itemStatus(
    String id,
    String itemId,
    Map<String, dynamic> body,
  ) async => (await _request(
    'orders/${Uri.encodeComponent(id)}/items/${Uri.encodeComponent(itemId)}/status',
    'POST',
    body: body,
  )).data;

  @override
  Future<Object?> itemPrice(
    String id,
    String itemId,
    Map<String, dynamic> body,
  ) async => (await _request(
    'orders/${Uri.encodeComponent(id)}/items/${Uri.encodeComponent(itemId)}/price',
    'PATCH',
    body: body,
  )).data;

  @override
  Future<Object?> itemHistory(String id, Map<String, dynamic> query) async =>
      (await _request(
        'orders/${Uri.encodeComponent(id)}/items/history',
        'GET',
        query: query,
      )).data;

  @override
  Future<Object?> payments(String id) async => (await _request(
    'orders/${Uri.encodeComponent(id)}/payments',
    'GET',
  )).data;

  @override
  Future<Object?> createPayment(String id, Map<String, dynamic> body) async =>
      (await _request(
        'orders/${Uri.encodeComponent(id)}/payments',
        'POST',
        body: body,
      )).data;

  @override
  Future<Object?> reversePayment(
    String id,
    String paymentId,
  ) async => (await _request(
    'orders/${Uri.encodeComponent(id)}/payments/${Uri.encodeComponent(paymentId)}/reverse',
    'POST',
  )).data;

  @override
  Future<Object?> banks() async => (await _request('banks', 'GET')).data;

  @override
  Future<Object?> qpay(String id) async =>
      (await _request('orders/${Uri.encodeComponent(id)}/qpay', 'GET')).data;

  @override
  Future<Object?> createQPay(String id, {String? amount}) async =>
      (await _request(
        'orders/${Uri.encodeComponent(id)}/qpay',
        'POST',
        body: amount == null ? null : {'amount': amount},
      )).data;

  @override
  Future<Object?> checkQPay(String id, Map<String, dynamic> body) async =>
      (await _request(
        'orders/${Uri.encodeComponent(id)}/qpay/check',
        'POST',
        body: body,
      )).data;

  @override
  Future<void> cancelQPay(String id, Map<String, dynamic> body) async {
    await _request(
      'orders/${Uri.encodeComponent(id)}/qpay',
      'DELETE',
      body: body,
    );
  }

  @override
  Future<Object?> postpaid(Map<String, dynamic> query) async =>
      (await _request('orders/postpaid', 'GET', query: query)).data;

  @override
  Future<Object?> assignableUsers(Map<String, dynamic> query) async =>
      (await _request('orders/assignable-users', 'GET', query: query)).data;

  @override
  Future<Object?> bulkStatus(Map<String, dynamic> body) async =>
      (await _request('orders/bulk/status', 'POST', body: body)).data;

  @override
  Future<Object?> bulkAssign(Map<String, dynamic> body) async =>
      (await _request('orders/bulk/assign', 'POST', body: body)).data;
}

// Error mapping now lives in `mapDioException`
// (lib/core/network/dio_error_mapper.dart), shared with
// `RemoteAppointmentsDataSource` and the generic client's `apiOrThrow`. HTTP
// status is authoritative whenever present there — Dio normally reports a
// response as `badResponse`, but custom adapters and interceptor-rejected
// responses can retain `unknown` while still carrying a valid HTTP response.
// The stale-working-branch 403 message is preserved by the shared mapper too
// (see its doc comment), so the UI still gets it verbatim.

typedef OrdersRemoteDataSource = RemoteOrdersDataSource;
