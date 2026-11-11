import 'package:dio/dio.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/data/cash_shift_dto.dart';
import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';
import 'package:carservice_business/features/cash/domain/cash_shift_repository.dart';

/// Thin transport seam over `/api/v1/cash/sessions*`. The shared Dio adds
/// the auth token and `X-Working-Branch`.
abstract interface class CashShiftDataSource {
  Future<Object?> list(Map<String, dynamic> query);
  Future<Object?> current(String? branchId);
  Future<Object?> detail(String id);
  Future<Object?> open(Map<String, dynamic> body);
  Future<Object?> close(String id, Map<String, dynamic> body);
}

class RemoteCashShiftDataSource implements CashShiftDataSource {
  RemoteCashShiftDataSource({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

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
      _send('cash/sessions', 'GET', query: query);

  @override
  Future<Object?> current(String? branchId) => _send(
    'cash/sessions/current',
    'GET',
    query: {'branchId': ?branchId},
  );

  @override
  Future<Object?> detail(String id) =>
      _send('cash/sessions/${Uri.encodeComponent(id)}', 'GET');

  @override
  Future<Object?> open(Map<String, dynamic> body) =>
      _send('cash/sessions', 'POST', body: body);

  @override
  Future<Object?> close(String id, Map<String, dynamic> body) => _send(
    'cash/sessions/${Uri.encodeComponent(id)}/close',
    'POST',
    body: body,
  );
}

class RemoteCashShiftRepository implements CashShiftRepository {
  RemoteCashShiftRepository({CashShiftDataSource? dataSource})
    : _dataSource = dataSource ?? RemoteCashShiftDataSource();

  final CashShiftDataSource _dataSource;

  Future<Result<T>> _run<T>(Future<T> Function() body, String fallback) async {
    try {
      return Ok(await body());
    } catch (error) {
      return Err(switch (error) {
        AppError value => value,
        CashParseException value => AppError(ErrorKind.unknown, value.message),
        _ => AppError(ErrorKind.unknown, fallback),
      });
    }
  }

  @override
  Future<Result<CashShiftPage>> listShifts(CashShiftQuery query) => _run(
    () async => parseCashShiftPage(
      await _dataSource.list(query.toQuery()),
      pageSize: query.pageSize,
    ),
    'Ээлжийн жагсаалт ачаалж чадсангүй',
  );

  @override
  Future<Result<CurrentCashShift>> currentShift(String? branchId) => _run(
    () async => parseCurrentCashShift(await _dataSource.current(branchId)),
    'Нээлттэй ээлж ачаалж чадсангүй',
  );

  @override
  Future<Result<CashShiftDetail>> shiftDetail(String id) => _run(
    () async => parseCashShiftDetail(await _dataSource.detail(id)),
    'Ээлжийн мэдээлэл ачаалж чадсангүй',
  );

  @override
  Future<Result<CashShift>> openShift({
    required String branchId,
    required String openingCash,
    String? note,
  }) => _run(
    () async => parseCashShiftEnvelope(
      await _dataSource.open({
        'branchId': branchId,
        'openingCash': openingCash,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }),
    ),
    'Ээлж нээж чадсангүй',
  );

  @override
  Future<Result<CashShift>> closeShift(
    String id, {
    required String countedCash,
    String? note,
  }) => _run(
    () async => parseCashShiftEnvelope(
      await _dataSource.close(id, {
        'countedCash': countedCash,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }),
    ),
    'Ээлж хааж чадсангүй',
  );
}
