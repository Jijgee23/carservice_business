import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/roles/domain/permission.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_permission_catalog_repository.dart';
import 'fake_role_repository.dart';

void main() {
  group('FakeRoleRepository', () {
    test('getRole answers the seeded system role', () async {
      final repo = FakeRoleRepository();
      expect((await repo.getRole('role-1') as Ok).value.id, 'role-1');
      expect((await repo.getRole('nope') as Err).error.code, 'NOT_FOUND');
    });
  });

  group('FakePermissionCatalogRepository', () {
    test(
      'getPermissions returns a deterministic catalogue with no gaps',
      () async {
        final repo = FakePermissionCatalogRepository();
        final catalog = (await repo.getPermissions() as Ok).value;
        expect(catalog.all, isNotEmpty);
        final allCodesNonEmpty = catalog.all.every(
          (PermissionItem p) => p.code.isNotEmpty,
        );
        expect(allCodesNonEmpty, isTrue);
      },
    );
  });
}
