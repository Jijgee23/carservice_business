/// Roles domain model — P6-F1.
///
/// Measured against `app/api/v1/roles/route.ts` (GET/POST) and
/// `app/api/v1/roles/[id]/route.ts` (GET/PATCH/DELETE) after `P6-B0`/
/// `P6-B2`, and `lib/roles/dto.ts`'s `toRoleDto`.
///
/// Roles are **global system roles** (2026-11-13): the platform's super
/// admin manages them; POST/PATCH/DELETE answer `403 SYSTEM_MANAGED`.
/// `GET` is open to any of `employees.view`/`.create`/`.edit`, matching the
/// employee create/edit form's role picker. There are no `roles.*`
/// permission codes.
library;

class RoleParseException implements Exception {
  const RoleParseException(this.message);
  final String message;

  @override
  String toString() => 'RoleParseException: $message';
}

/// One system role row — `{id, key, name, description, permissions,
/// isActive}` (`key`: MECHANIC|ENGINEER|ACCOUNTANT|CASHIER|MANAGER for the
/// built-in roles, null for extras),
/// plus `userCount` from `_count.users` when the server includes it (not
/// selected by every route today; `null` when absent).
class Role {
  final String id;

  /// Built-in system role key (`MECHANIC`, `ENGINEER`, `ACCOUNTANT`,
  /// `CASHIER`, `MANAGER`); null for an extra role.
  final String? key;
  final String? name;
  final String? description;
  final List<String> permissions;
  final bool isActive;
  final int? userCount;

  const Role({
    required this.id,
    this.key,
    this.name,
    this.description,
    this.permissions = const [],
    this.isActive = true,
    this.userCount,
  });

  factory Role.fromJson(Map<String, dynamic> j) => Role(
    id: _reqString(j, 'id'),
    key: _optString(j['key']),
    name: _optString(j['name']),
    description: _optString(j['description']),
    permissions: _stringList(j['permissions']),
    isActive: _optBool(j['isActive']) ?? true,
    userCount: _optInt(j['userCount']),
  );
}

String _reqString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw RoleParseException('$key талбар буруу байна.');
  }
  return value.trim();
}

String? _optString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool? _optBool(Object? value) => value is bool ? value : null;

int? _optInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value.trim());
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}
