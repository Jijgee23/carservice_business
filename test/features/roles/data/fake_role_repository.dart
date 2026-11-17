import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/roles/domain/role.dart';
import 'package:carservice_business/features/roles/domain/roles_repository.dart';

/// Hand-written fake for the read-only [RolesRepository] (system roles).
class FakeRoleRepository implements RolesRepository {
  FakeRoleRepository({List<Role>? seed})
    : _roles = [
        ...(seed ?? [seedRole()]),
      ];

  final List<Role> _roles;

  static Role seedRole({
    String id = 'role-1',
    String name = 'Механик',
    List<String> permissions = const ['orders.view', 'orders.edit'],
    bool isActive = true,
  }) => Role(id: id, name: name, permissions: permissions, isActive: isActive);

  int _indexOf(String id) => _roles.indexWhere((r) => r.id == id);

  AppError _notFound() => const AppError(
    ErrorKind.notFound,
    'Үүрэг олдсонгүй.',
    statusCode: 404,
    code: 'NOT_FOUND',
  );

  @override
  Future<Result<PagedResult<Role>>> getRoles({RoleListQuery? query}) async {
    final q = query ?? const RoleListQuery();
    final total = _roles.length;
    final totalPages = (total / q.pageSize).ceil().clamp(1, 1 << 30);
    final page = q.page.clamp(1, totalPages);
    final skip = (page - 1) * q.pageSize;
    final items = _roles.skip(skip).take(q.pageSize).toList(growable: false);
    return Ok(
      PagedResult(
        items: items,
        pagination: PaginationMeta(
          page: page,
          pageSize: q.pageSize,
          total: total,
          totalPages: totalPages,
          hasPrev: page > 1,
          hasNext: page < totalPages,
        ),
      ),
    );
  }

  @override
  Future<Result<Role>> getRole(String roleId) async {
    final index = _indexOf(roleId);
    if (index < 0) return Err(_notFound());
    return Ok(_roles[index]);
  }
}
