import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/roles/data/role_dto.dart';
import 'package:carservice_business/features/roles/data/roles_data_source.dart';
import 'package:carservice_business/features/roles/domain/role.dart';
import 'package:carservice_business/features/roles/domain/roles_repository.dart';

/// Remote adapter for [RolesRepository] — P6-F1.
class RemoteRolesRepository implements RolesRepository {
  RemoteRolesRepository({RolesDataSource? dataSource})
    : _dataSource = dataSource ?? RemoteRolesDataSource();

  final RolesDataSource _dataSource;

  @override
  Future<Result<PagedResult<Role>>> getRoles({RoleListQuery? query}) async {
    final effective = query ?? const RoleListQuery();
    try {
      final parsed = RolePageDto.fromJson(
        await _dataSource.list({
          'page': effective.page,
          'pageSize': effective.pageSize,
        }),
      );
      return Ok(
        PagedResult(items: parsed.items, pagination: parsed.pagination),
      );
    } catch (error) {
      return Err(_error(error, 'Үүргийн жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<Role>> getRole(String roleId) async {
    try {
      return Ok(RoleDto.fromJson(await _dataSource.detail(roleId)).value);
    } catch (error) {
      return Err(_error(error, 'Үүргийн мэдээлэл ачаалж чадсангүй'));
    }
  }
}

AppError _error(Object error, String fallback) => switch (error) {
  AppError value => value,
  RoleParseException value => AppError(ErrorKind.unknown, value.message),
  _ => AppError(ErrorKind.unknown, fallback),
};
