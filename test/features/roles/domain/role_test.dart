import 'package:carservice_business/features/roles/domain/permission.dart';
import 'package:carservice_business/features/roles/domain/role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Role', () {
    test('parses the measured full row', () {
      final r = Role.fromJson({
        'id': 'role-1',
        'key': 'MECHANIC',
        'name': 'Механик',
        'description': 'Засварчин',
        'permissions': ['orders.view', 'orders.edit'],
        'isActive': true,
        'userCount': 3,
      });
      expect(r.id, 'role-1');
      expect(r.key, 'MECHANIC');
      expect(r.permissions, ['orders.view', 'orders.edit']);
      expect(r.userCount, 3);
    });

    test('a missing id throws', () {
      expect(
        () => Role.fromJson({'name': 'Механик'}),
        throwsA(isA<RoleParseException>()),
      );
    });

    test('everything but id degrades tolerantly', () {
      final r = Role.fromJson({'id': 'role-1'});
      expect(r.name, isNull);
      expect(r.permissions, isEmpty);
      expect(r.isActive, isTrue);
      expect(r.userCount, isNull);
    });
  });

  group('PermissionCatalog', () {
    test('all() flattens groups and standalone', () {
      const catalog = PermissionCatalog(
        groups: [
          PermissionGroup(
            group: 'orders',
            items: [PermissionItem(code: 'orders.view')],
          ),
        ],
        standalone: [PermissionItem(code: 'employees.schedule')],
      );
      expect(catalog.all.map((p) => p.code), [
        'orders.view',
        'employees.schedule',
      ]);
    });

    test('PermissionItem requires code', () {
      expect(
        () => PermissionItem.fromJson({'label': 'x'}),
        throwsA(isA<PermissionParseException>()),
      );
    });
  });
}
