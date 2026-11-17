import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/roles/domain/role.dart';

/// `GET /api/v1/roles` supports only standard pagination (`page`,
/// `pageSize`/`limit`) — no `q`/filter params exist on this route.
class RoleListQuery {
  final int page;
  final int pageSize;
  const RoleListQuery({this.page = 1, this.pageSize = 50});
}

/// Read-only roles contract. Roles are **global system roles** managed by
/// the platform's super admin (MECHANIC, ENGINEER, ACCOUNTANT, CASHIER,
/// MANAGER + optional extras); a workshop can no longer create, edit or
/// delete them — `POST /roles`, `PATCH/DELETE /roles/[id]` answer
/// `403 SYSTEM_MANAGED`. The employee form only picks from active roles.
///
/// Readable by any of `employees.view`/`.create`/`.edit`.
abstract interface class RolesRepository {
  /// `GET /api/v1/roles` — active first, then `sortOrder`/name.
  Future<Result<PagedResult<Role>>> getRoles({RoleListQuery? query});

  /// `GET /api/v1/roles/[id]`.
  Future<Result<Role>> getRole(String roleId);
}
