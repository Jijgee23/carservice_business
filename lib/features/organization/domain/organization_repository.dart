import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/organization/domain/organization.dart';
import 'package:carservice_business/features/organization/domain/service_keys.dart';

/// Workshop settings — `GET/PATCH /api/v1/tenant`,
/// `POST/DELETE /api/v1/tenant/logo`. Writes are owner-only server-side.
abstract interface class OrganizationRepository {
  Future<Result<OrganizationSettings>> load();

  /// Partial update; answers the refreshed settings. Validation failures
  /// come back as an [AppError] with `fieldErrors`.
  Future<Result<OrganizationSettings>> update(Map<String, Object?> patch);

  /// Multipart upload of the image at [path]; answers the new logo URL.
  Future<Result<String>> uploadLogo(String path);

  Future<Result<bool>> removeLogo();

  /// `GET /api/v1/tenant/service-keys` — the workshop's offered services
  /// (every signed-in employee may read; `canEdit` = owner).
  Future<Result<TenantServiceKeys>> loadServiceKeys();

  /// `PUT /api/v1/tenant/service-keys` — owner only; replaces the whole
  /// selection (at least one id) and marks it confirmed.
  Future<Result<TenantServiceKeys>> saveServiceKeys(List<String> ids);
}
