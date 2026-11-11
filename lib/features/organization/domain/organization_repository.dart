import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/organization/domain/organization.dart';

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
}
