import 'package:carservice_business/features/roles/data/permission_dto.dart';
import 'package:carservice_business/features/roles/data/role_dto.dart';
import 'package:carservice_business/features/roles/domain/permission.dart';
import 'package:carservice_business/features/roles/domain/role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RolePageDto', () {
    test('parses the measured list envelope', () {
      final dto = RolePageDto.fromJson({
        'roles': [
          {'id': 'role-1', 'name': 'Механик'},
        ],
        'pagination': _pagination,
      });
      expect(dto.items.single.id, 'role-1');
    });

    test('a missing or non-list roles key throws', () {
      expect(
        () => RolePageDto.fromJson({'pagination': _pagination}),
        throwsA(isA<RoleParseException>()),
      );
    });
  });

  group('RoleDto', () {
    test('parses {role:{...}}', () {
      final r = RoleDto.fromJson({
        'role': {'id': 'role-1', 'permissions': const []},
      }).value;
      expect(r.id, 'role-1');
    });

    test('a missing role key throws', () {
      expect(
        () => RoleDto.fromJson(<String, dynamic>{}),
        throwsA(isA<RoleParseException>()),
      );
    });
  });

  group('PermissionCatalogDto', () {
    test('parses the measured groups/standalone envelope', () {
      final catalog = PermissionCatalogDto.fromJson({
        'groups': [
          {
            'group': 'orders',
            'items': [
              {'code': 'orders.view', 'label': 'Захиалга харах'},
            ],
          },
        ],
        'standalone': [
          {
            'code': 'employees.schedule',
            'label': 'Хувиар удирдах',
            'group': 'employees',
          },
        ],
      }).value;
      expect(catalog.groups.single.items.single.code, 'orders.view');
      expect(catalog.standalone.single.code, 'employees.schedule');
    });

    test('missing groups/standalone degrade to empty lists', () {
      final catalog = PermissionCatalogDto.fromJson(<String, dynamic>{}).value;
      expect(catalog.groups, isEmpty);
      expect(catalog.standalone, isEmpty);
    });

    test('a non-map envelope throws', () {
      expect(
        () => PermissionCatalogDto.fromJson('nope'),
        throwsA(isA<PermissionParseException>()),
      );
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
