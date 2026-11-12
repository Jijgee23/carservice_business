import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/domain/service_catalog.dart';

class ServiceCatalogService {
  static Future<List<CatalogService>> getServices({String? type, String? q}) async {
    final params = <String, String>{};
    if (type != null) params['type'] = type;
    if (q != null && q.isNotEmpty) params['q'] = q;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final path = query.isEmpty ? 'services' : 'services?$query';

    final res = await api(Api.get, path);
    if (res == null) return [];
    final list = res.data['services'] as List<dynamic>? ?? [];
    return list.map((e) => CatalogService.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Нэгдсэн сангийн ажил/сэлбэг the tenant hasn't linked yet
  /// (`GET orders/catalog-items`), for the order line picker. An item's [id]
  /// is the shared `catalogItemId`, not a tenant service id. Errors throw
  /// silently ([apiOrThrow]): the list is extra, not worth a snackbar.
  static Future<List<CatalogService>> getCatalogItems({String? q}) async {
    final query = q == null || q.isEmpty
        ? ''
        : '&q=${Uri.encodeQueryComponent(q)}';
    final res = await apiOrThrow(
      Api.get,
      'orders/catalog-items?pageSize=100$query',
    );
    final list = res.data['items'] as List<dynamic>? ?? [];
    return list.map((e) {
      final j = e as Map<String, dynamic>;
      final category = j['category'] as Map<String, dynamic>?;
      return CatalogService(
        id: j['id'] as String,
        type: j['type'] == 'GOODS' ? ServiceKind.GOODS : ServiceKind.LABOR,
        name: j['name'] as String,
        code: j['code'] as String?,
        price: double.tryParse('${j['price']}') ?? 0,
        description: j['description'] as String?,
        isActive: true,
        laborCategory: category == null
            ? null
            : LaborCategory(
                id: category['id'] as String,
                name: category['name'] as String,
              ),
      );
    }).toList();
  }

  static Future<List<DiagnosticTemplateSummary>> getTemplates({String? q}) async {
    final path = (q != null && q.isNotEmpty)
        ? 'diagnostics/templates?q=${Uri.encodeQueryComponent(q)}'
        : 'diagnostics/templates';
    final res = await api(Api.get, path);
    if (res == null) return [];
    final list = res.data['templates'] as List<dynamic>? ?? [];
    return list.map((e) => DiagnosticTemplateSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ─── Units ──────────────────────────────────────────────────────────────────

  static Future<Result<List<ServiceUnit>>> getUnits({bool all = false}) async {
    try {
      final res = await apiOrThrow(Api.get, all ? 'units?all=true' : 'units');
      final list = res.data['units'] as List;
      return Ok(list.map((e) => ServiceUnit.fromJson(e as Map<String, dynamic>)).toList());
    } on AppError catch (e) {
      return Err(e);
    }
  }

  static Future<Result<ServiceUnit>> createUnit({
    required String name,
    String? code,
    bool isActive = true,
  }) async {
    try {
      final res = await apiOrThrow(
        Api.post,
        'units',
        body: {
          'name': name,
          if (code != null && code.isNotEmpty) 'code': code,
          'isActive': isActive,
        },
      );
      return Ok(ServiceUnit.fromJson(res.data['unit'] as Map<String, dynamic>));
    } on AppError catch (e) {
      return Err(e);
    }
  }

  static Future<Result<ServiceUnit>> updateUnit(
    String id, {
    String? name,
    String? code,
    bool? isActive,
  }) async {
    try {
      final res = await apiOrThrow(
        Api.patch,
        'units/$id',
        body: {'name': ?name, 'code': ?code, 'isActive': ?isActive},
      );
      return Ok(ServiceUnit.fromJson(res.data['unit'] as Map<String, dynamic>));
    } on AppError catch (e) {
      return Err(e);
    }
  }

  static Future<Result<void>> deleteUnit(String id) async {
    try {
      await apiOrThrow(Api.delete, 'units/$id');
      return const Ok(null);
    } on AppError catch (e) {
      return Err(e);
    }
  }

  // ─── Labor categories ────────────────────────────────────────────────────────

  static Future<Result<List<LaborCategory>>> getLaborCategories({bool all = false}) async {
    try {
      final res = await apiOrThrow(Api.get, all ? 'labor-categories?all=true' : 'labor-categories');
      final list = res.data['categories'] as List;
      return Ok(list.map((e) => LaborCategory.fromJson(e as Map<String, dynamic>)).toList());
    } on AppError catch (e) {
      return Err(e);
    }
  }

  static Future<Result<LaborCategory>> createLaborCategory({
    required String name,
    String? description,
    bool isActive = true,
  }) async {
    try {
      final res = await apiOrThrow(
        Api.post,
        'labor-categories',
        body: {
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
          'isActive': isActive,
        },
      );
      return Ok(LaborCategory.fromJson(res.data['category'] as Map<String, dynamic>));
    } on AppError catch (e) {
      return Err(e);
    }
  }

  static Future<Result<LaborCategory>> updateLaborCategory(
    String id, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    try {
      final res = await apiOrThrow(
        Api.patch,
        'labor-categories/$id',
        body: {'name': ?name, 'description': ?description, 'isActive': ?isActive},
      );
      return Ok(LaborCategory.fromJson(res.data['category'] as Map<String, dynamic>));
    } on AppError catch (e) {
      return Err(e);
    }
  }

  static Future<Result<void>> deleteLaborCategory(String id) async {
    try {
      await apiOrThrow(Api.delete, 'labor-categories/$id');
      return const Ok(null);
    } on AppError catch (e) {
      return Err(e);
    }
  }

  static Future<Result<CatalogService>> createService({
    required ServiceKind type,
    required String name,
    String? code,
    required double price,
    double? costPrice,
    double? stock,
    String? description,
    bool isActive = true,
    String? unitId,
    String? laborCategoryId,
    double? durationValue,
    String? durationUnitId,
  }) async {
    try {
      final res = await apiOrThrow(
        Api.post,
        'services',
        body: {
          'type': type.name,
          'name': name,
          if (code != null && code.isNotEmpty) 'code': code,
          'price': price,
          'costPrice': ?costPrice,
          'stock': ?stock,
          if (description != null && description.isNotEmpty) 'description': description,
          'isActive': isActive,
          'unitId': ?unitId,
          // The API field is `categoryId`; `laborCategoryId` was silently ignored,
          // so every service created on mobile ended up uncategorised.
          'categoryId': ?laborCategoryId,
          'durationValue': ?durationValue,
          'durationUnitId': ?durationUnitId,
        },
      );
      final s = res.data['service'] as Map<String, dynamic>;
      return Ok(CatalogService.fromJson(s));
    } on AppError catch (e) {
      return Err(e);
    }
  }

  static Future<CatalogService?> getService(String id) async {
    final res = await api(Api.get, 'services/$id');
    if (res == null) return null;
    final s = res.data['service'] as Map<String, dynamic>?;
    return s != null ? CatalogService.fromJson(s) : null;
  }
}
