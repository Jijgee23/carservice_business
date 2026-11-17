/// Envelope parsing for Roles — P6-F1. See `employee_dto.dart` for the
/// shared idiom this mirrors.
library;

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/features/roles/domain/role.dart';

typedef JsonMap = Map<String, dynamic>;

JsonMap _map(Object? value, String label) {
  if (value is! Map) throw RoleParseException('$label буруу байна.');
  return Map<String, dynamic>.from(value);
}

int _requiredInt(JsonMap json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw RoleParseException('$key буруу байна.');
}

bool _requiredBool(JsonMap json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw RoleParseException('$key буруу байна.');
}

PaginationMeta _pagination(Object? raw) {
  final json = _map(raw, 'pagination');
  final page = _requiredInt(json, 'page');
  final pageSize = _requiredInt(json, 'pageSize');
  final total = _requiredInt(json, 'total');
  final totalPages = _requiredInt(json, 'totalPages');
  if (page < 1 || pageSize < 1 || total < 0 || totalPages < 0) {
    throw const RoleParseException('Хуудаслалтын мэдээлэл буруу байна.');
  }
  return PaginationMeta(
    page: page,
    pageSize: pageSize,
    total: total,
    totalPages: totalPages,
    hasPrev: _requiredBool(json, 'hasPrev'),
    hasNext: _requiredBool(json, 'hasNext'),
  );
}

/// `GET /api/v1/roles` — `{roles:[...], pagination}`.
class RolePageDto {
  const RolePageDto(this.items, this.pagination);
  final List<Role> items;
  final PaginationMeta pagination;

  factory RolePageDto.fromJson(Object? raw) {
    final json = _map(raw, 'roles response');
    final list = json['roles'];
    if (list is! List) {
      throw const RoleParseException('Үүргийн жагсаалт буруу байна.');
    }
    return RolePageDto(
      list
          .whereType<Map>()
          .map((item) => Role.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      _pagination(json['pagination']),
    );
  }
}

/// `GET /roles/[id]` role detail — `{role:{...}}`.
class RoleDto {
  const RoleDto(this.value);
  final Role value;

  factory RoleDto.fromJson(Object? raw) {
    final json = _map(raw, 'role response');
    return RoleDto(Role.fromJson(_map(json['role'], 'role')));
  }
}
