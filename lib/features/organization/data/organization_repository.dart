import 'package:dio/dio.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/organization/domain/organization.dart';
import 'package:carservice_business/features/organization/domain/organization_repository.dart';

/// Remote [OrganizationRepository] over the shared Dio client.
class RemoteOrganizationRepository implements OrganizationRepository {
  RemoteOrganizationRepository({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  Future<Result<T>> _guard<T>(Future<T> Function() run, String fallback) async {
    try {
      return Ok(await run());
    } on DioException catch (e) {
      return Err(mapDioException(e));
    } on AppError catch (e) {
      return Err(e);
    } on FormatException catch (e) {
      return Err(AppError(ErrorKind.unknown, e.message));
    } catch (_) {
      return Err(AppError(ErrorKind.unknown, fallback));
    }
  }

  @override
  Future<Result<OrganizationSettings>> load() => _guard(
    () async => OrganizationSettings.fromJson((await _dio.get<dynamic>('tenant')).data),
    'Байгууллагын мэдээлэл ачаалж чадсангүй',
  );

  @override
  Future<Result<OrganizationSettings>> update(Map<String, Object?> patch) => _guard(
    () async =>
        OrganizationSettings.fromJson((await _dio.patch<dynamic>('tenant', data: patch)).data),
    'Хадгалж чадсангүй',
  );

  @override
  Future<Result<String>> uploadLogo(String path) => _guard(() async {
    final res = await _dio.post<dynamic>(
      'tenant/logo',
      data: FormData.fromMap({'file': await MultipartFile.fromFile(path)}),
    );
    final data = res.data;
    final url = data is Map ? data['logoUrl'] : null;
    if (url is! String || url.isEmpty) throw const FormatException('Лого хадгалагдсангүй');
    return url;
  }, 'Лого байршуулж чадсангүй');

  @override
  Future<Result<bool>> removeLogo() => _guard(() async {
    await _dio.delete<dynamic>('tenant/logo');
    return true;
  }, 'Лого устгаж чадсангүй');
}
