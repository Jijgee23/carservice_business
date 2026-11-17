import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/roles/data/permission_catalog_data_source.dart';
import 'package:carservice_business/features/roles/data/permission_catalog_repository.dart';
import 'package:carservice_business/features/roles/data/role_repository.dart';
import 'package:carservice_business/features/roles/data/roles_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteRolesRepository', () {
    test('a 403 from getRoles passes through verbatim', () async {
      const mapped = AppError(
        ErrorKind.forbidden,
        'Танд энэ үйлдэл хийх эрх байхгүй.',
        statusCode: 403,
      );
      final result = await RemoteRolesRepository(
        dataSource: _ThrowingRolesDataSource(mapped),
      ).getRoles();
      expect((result as Err).error.statusCode, 403);
    });

    test('getRoles unwraps items and pagination', () async {
      final result = await RemoteRolesRepository(
        dataSource: _RecordingRolesDataSource({
          'roles': [
            {'id': 'role-1', 'key': 'MECHANIC'},
          ],
          'pagination': _pagination,
        }),
      ).getRoles();
      expect((result as Ok).value.items.single.id, 'role-1');
      expect((result as Ok).value.items.single.key, 'MECHANIC');
    });
  });

  group('RemotePermissionCatalogRepository', () {
    test('getPermissions unwraps the catalogue', () async {
      final result = await RemotePermissionCatalogRepository(
        dataSource: _RecordingPermissionsDataSource({
          'groups': const [],
          'standalone': [
            {'code': 'employees.schedule'},
          ],
        }),
      ).getPermissions();
      expect((result as Ok).value.standalone.single.code, 'employees.schedule');
    });

    test('an AppError from mapDioException passes through', () async {
      const mapped = AppError(
        ErrorKind.forbidden,
        'Хандах эрх байхгүй',
        statusCode: 403,
      );
      final result = await RemotePermissionCatalogRepository(
        dataSource: _ThrowingPermissionsDataSource(mapped),
      ).getPermissions();
      expect((result as Err).error.statusCode, 403);
    });
  });
}

const _pagination = {
  'page': 1,
  'pageSize': 50,
  'total': 1,
  'totalPages': 1,
  'hasPrev': false,
  'hasNext': false,
};

class _RecordingRolesDataSource implements RolesDataSource {
  _RecordingRolesDataSource(this.payload);
  final Object? payload;

  @override
  Future<Object?> list(Map<String, dynamic> query) async => payload;
  @override
  Future<Object?> detail(String id) async => payload;
}

class _ThrowingRolesDataSource implements RolesDataSource {
  _ThrowingRolesDataSource(this.error);
  final AppError error;

  @override
  Future<Object?> list(Map<String, dynamic> query) async => throw error;
  @override
  Future<Object?> detail(String id) async => throw error;
}

class _RecordingPermissionsDataSource implements PermissionCatalogDataSource {
  _RecordingPermissionsDataSource(this.payload);
  final Object? payload;
  @override
  Future<Object?> get() async => payload;
}

class _ThrowingPermissionsDataSource implements PermissionCatalogDataSource {
  _ThrowingPermissionsDataSource(this.error);
  final AppError error;
  @override
  Future<Object?> get() async => throw error;
}
