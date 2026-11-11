import 'package:dio/dio.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/branches/domain/branch.dart';
import 'package:carservice_business/features/branches/domain/branches_repository.dart';

/// Remote [BranchesRepository] over the shared Dio client.
///
/// - `GET branches` (paged, active only, no primary flag) is joined with
///   `GET branches/switchable` (which carries `isPrimary`) for the badge;
/// - tags come from the public catalog `GET app/branch-tags`;
/// - the map pin's address reuses `GET auth/signup/address`.
class RemoteBranchesRepository implements BranchesRepository {
  RemoteBranchesRepository({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  static const _pageSize = 100;

  Future<Result<T>> _guard<T>(Future<T> Function() run, String fallback) async {
    try {
      return Ok(await run());
    } on DioException catch (e) {
      return Err(_map(e));
    } on AppError catch (e) {
      return Err(e);
    } on FormatException catch (e) {
      return Err(AppError(ErrorKind.unknown, e.message));
    } catch (_) {
      return Err(AppError(ErrorKind.unknown, fallback));
    }
  }

  static AppError _map(DioException e) {
    final data = e.response?.data;
    if (e.response?.statusCode == 409 &&
        data is Map &&
        data['code'] == BranchScheduleImpactError.errorCode) {
      final impact = data['impact'];
      int count(String key) => impact is Map && impact[key] is List ? (impact[key] as List).length : 0;
      return BranchScheduleImpactError(
        ErrorKind.unknown,
        data['error']?.toString() ?? 'Хуваарь өөрчлөхөд цаг захиалгууд нөлөөлөгдөнө.',
        needsConfirm: data['needsConfirm'] == true,
        clippedCount: count('clipped'),
        erasedCount: count('erased'),
        statusCode: 409,
        code: BranchScheduleImpactError.errorCode,
      );
    }
    return mapDioException(e);
  }

  String _path(String id) => 'branches/${Uri.encodeComponent(id)}';

  @override
  Future<Result<List<BranchSummary>>> listBranches() => _guard(() async {
    final rows = <BranchSummary>[];
    var page = 1;
    while (true) {
      final res = await _dio.get<dynamic>(
        'branches',
        queryParameters: {'page': page, 'pageSize': _pageSize},
      );
      final data = res.data;
      if (data is! Map || data['branches'] is! List) {
        throw const FormatException('Салбарын жагсаалт буруу байна');
      }
      for (final raw in data['branches'] as List) {
        if (raw is Map) rows.add(BranchSummary.fromJson(raw));
      }
      final meta = data['pagination'];
      if (meta is! Map || meta['hasNext'] != true || page >= 20) break;
      page++;
    }
    // The primary flag lives on the switcher endpoint; a failure there only
    // loses the badge.
    final primary = <String>{};
    try {
      final res = await _dio.get<dynamic>('branches/switchable');
      final list = res.data is Map ? (res.data as Map)['branches'] : null;
      if (list is List) {
        for (final b in list) {
          if (b is Map && b['isPrimary'] == true) primary.add(b['id'].toString());
        }
      }
    } on DioException {
      // ignore — badge only
    }
    final merged = [
      for (final b in rows) primary.contains(b.id) ? b.copyWith(isPrimary: true) : b,
    ];
    merged.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return merged;
  }, 'Салбаруудыг ачаалж чадсангүй');

  @override
  Future<Result<BranchDetail>> getBranch(String id) => _guard(
    () async => BranchDetail.fromJson((await _dio.get<dynamic>(_path(id))).data),
    'Салбарын мэдээлэл ачаалж чадсангүй',
  );

  @override
  Future<Result<BranchDetail>> createBranch(BranchDraft draft) => _guard(
    () async => BranchDetail.fromJson((await _dio.post<dynamic>('branches', data: draft.toJson())).data),
    'Салбар үүсгэж чадсангүй',
  );

  @override
  Future<Result<BranchDetail>> updateBranch(String id, BranchDraft draft, {bool confirm = false}) =>
      _guard(
        () async => BranchDetail.fromJson(
          (await _dio.patch<dynamic>(
            _path(id),
            data: {...draft.toJson(), if (confirm) 'confirm': true},
          )).data,
        ),
        'Салбарыг хадгалж чадсангүй',
      );

  @override
  Future<Result<bool>> toggleActive(String id) => _guard(() async {
    final data = (await _dio.post<dynamic>('${_path(id)}/toggle-active')).data;
    final branch = data is Map ? data['branch'] : null;
    if (branch is! Map || branch['isActive'] is! bool) {
      throw const FormatException('Төлөв солигдсонгүй');
    }
    return branch['isActive'] as bool;
  }, 'Төлөв сольж чадсангүй');

  @override
  Future<Result<bool>> deleteBranch(String id) => _guard(() async {
    await _dio.delete<dynamic>(_path(id));
    return true;
  }, 'Салбар устгаж чадсангүй');

  @override
  Future<Result<List<BranchTag>>> listTags() => _guard(() async {
    final data = (await _dio.get<dynamic>('app/branch-tags')).data;
    final list = data is Map ? data['tags'] : null;
    if (list is! List) return const <BranchTag>[];
    return [for (final t in list) if (t is Map) BranchTag.fromJson(t)];
  }, 'Шошго ачаалж чадсангүй');

  @override
  Future<Result<BranchPinAddress>> addressAt(double lat, double lng) => _guard(
    () async => BranchPinAddress.fromJson(
      (await _dio.get<dynamic>(
        'auth/signup/address',
        queryParameters: {'lat': '$lat', 'lng': '$lng'},
      )).data,
    ),
    'Хаяг тодорхойлж чадсангүй',
  );
}
