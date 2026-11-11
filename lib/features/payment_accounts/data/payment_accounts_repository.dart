import 'package:dio/dio.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/payment_accounts/domain/payment_account.dart';

/// Thin transport seam over `/api/v1/payment-accounts*`.
abstract interface class PaymentAccountsDataSource {
  Future<Object?> list(Map<String, dynamic> query);
  Future<Object?> create(Map<String, dynamic> body);
  Future<Object?> update(String id, Map<String, dynamic> body);
  Future<Object?> delete(String id);
}

class RemotePaymentAccountsDataSource implements PaymentAccountsDataSource {
  RemotePaymentAccountsDataSource({Dio? dio})
    : _dio = dio ?? ApiService.instance.dio;

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
  Future<Object?> list(Map<String, dynamic> query) =>
      _send('payment-accounts', 'GET', query: query);

  @override
  Future<Object?> create(Map<String, dynamic> body) =>
      _send('payment-accounts', 'POST', body: body);

  @override
  Future<Object?> update(String id, Map<String, dynamic> body) =>
      _send('payment-accounts/${Uri.encodeComponent(id)}', 'PATCH', body: body);

  @override
  Future<Object?> delete(String id) =>
      _send('payment-accounts/${Uri.encodeComponent(id)}', 'DELETE');
}

class RemotePaymentAccountsRepository implements PaymentAccountsRepository {
  RemotePaymentAccountsRepository({PaymentAccountsDataSource? dataSource})
    : _dataSource = dataSource ?? RemotePaymentAccountsDataSource();

  final PaymentAccountsDataSource _dataSource;

  Future<Result<T>> _run<T>(Future<T> Function() body, String fallback) async {
    try {
      return Ok(await body());
    } catch (error) {
      return Err(switch (error) {
        AppError value => value,
        FormatException value => AppError(ErrorKind.unknown, value.message),
        _ => AppError(ErrorKind.unknown, fallback),
      });
    }
  }

  static PaymentAccount _account(Object? raw) {
    final account = raw is Map ? raw['account'] : null;
    if (account is! Map) {
      throw const FormatException('Төлбөрийн арга буруу байна.');
    }
    return PaymentAccount.fromJson(Map<String, dynamic>.from(account));
  }

  @override
  Future<Result<List<PaymentAccount>>> list({bool includeInactive = true}) =>
      _run(() async {
        final raw = await _dataSource.list({
          if (includeInactive) 'includeInactive': '1',
        });
        final list = raw is Map ? raw['accounts'] : null;
        if (list is! List) {
          throw const FormatException('accounts буруу байна.');
        }
        return list
            .whereType<Map>()
            .map((m) => PaymentAccount.fromJson(Map<String, dynamic>.from(m)))
            .toList(growable: false);
      }, 'Төлбөрийн данс ачаалж чадсангүй');

  @override
  Future<Result<PaymentAccount>> create(PaymentAccountDraft draft) => _run(
    () async => _account(await _dataSource.create(draft.toCreateJson())),
    'Төлбөрийн данс нэмж чадсангүй',
  );

  @override
  Future<Result<PaymentAccount>> update(String id, PaymentAccountDraft draft) =>
      _run(
        () async => _account(await _dataSource.update(id, draft.toUpdateJson())),
        'Төлбөрийн данс хадгалж чадсангүй',
      );

  @override
  Future<Result<PaymentAccount>> setActive(String id, bool isActive) => _run(
    () async => _account(await _dataSource.update(id, {'isActive': isActive})),
    'Төлөв өөрчилж чадсангүй',
  );

  @override
  Future<Result<void>> delete(String id) => _run(
    () => _dataSource.delete(id),
    'Төлбөрийн данс устгаж чадсангүй',
  );
}
