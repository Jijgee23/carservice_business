import 'package:carservice_business/core/errors/app_error.dart';
import 'package:dio/dio.dart';

/// Single shared `DioException` → [AppError] mapper.
///
/// Consolidates three previously-duplicated mappers (`api_client.dart`'s
/// `apiOrThrow`, `RemoteAppointmentsDataSource._toAppError`,
/// `RemoteOrdersDataSource._toAppError`) that had drifted: the generic
/// client's mapper used to collapse every non-401/403/404/500 status —
/// including 409 conflicts and 422 validation failures — into an
/// indistinguishable `ErrorKind.unknown` with no metadata, while the
/// Appointments and Orders data sources each carried their own copy that kept
/// `statusCode`, the server's `code`, and `fieldErrors` for exactly that
/// case. This mapper always preserves the richer behavior: 409 and 422 stay
/// `ErrorKind.unknown` but carry `statusCode`/`code`/`fieldErrors`, so a
/// caller can still tell them apart and bind field errors.
///
/// HTTP status is authoritative whenever present. Dio normally reports a
/// response as `DioExceptionType.badResponse`, but custom adapters and
/// interceptor-rejected responses can retain `DioExceptionType.unknown`
/// while still carrying a valid HTTP response, so status is checked before
/// falling back to `error.type`.
AppError mapDioException(DioException error) {
  final data = error.response?.data;
  final message = data is Map && data['error'] is String
      ? data['error'] as String
      : null;
  final metadata = _errorMetadata(data);
  final status = error.response?.statusCode;
  if (status != null) {
    return switch (status) {
      401 => AppError(
        ErrorKind.unauthorized,
        'Нэвтрэх шаардлагатай',
        statusCode: status,
        code: metadata.code,
        fieldErrors: metadata.fieldErrors,
      ),
      // Keep a caller-supplied message intact — e.g. the working-branch
      // interceptor's stale-branch 403, which the UI needs verbatim rather
      // than a generic authorization failure.
      403 => AppError(
        ErrorKind.forbidden,
        message ?? 'Хандах эрх байхгүй',
        statusCode: status,
        code: metadata.code,
        fieldErrors: metadata.fieldErrors,
      ),
      404 => AppError(
        ErrorKind.notFound,
        'Олдсонгүй',
        statusCode: status,
        code: metadata.code,
        fieldErrors: metadata.fieldErrors,
      ),
      500 => AppError(
        ErrorKind.server,
        'Серверийн алдаа',
        statusCode: status,
        code: metadata.code,
        fieldErrors: metadata.fieldErrors,
      ),
      // 409 (transition/reservation conflict) and 422 (field errors) are
      // deliberately NOT collapsed into a shared kind — callers distinguish
      // them via `statusCode`, e.g. a 409 triggers a slot re-fetch while a
      // 422 binds field errors, never a blind retry.
      _ => AppError(
        ErrorKind.unknown,
        // CASH_SESSION_CLOSED always reads the same, whatever the server text.
        metadata.code == CashSessionClosedError.code
            ? CashSessionClosedError.message
            : metadata.code == CashSessionEntryLockedError.code
            ? CashSessionEntryLockedError.message
            : message ?? 'Алдаа гарлаа',
        statusCode: status,
        code: metadata.code,
        fieldErrors: metadata.fieldErrors,
      ),
    };
  }
  return switch (error.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const AppError(
      ErrorKind.network,
      'Холболт байхгүй',
    ),
    _ => AppError(ErrorKind.unknown, error.message ?? 'Алдаа гарлаа'),
  };
}

/// Pulls the server's machine-readable `code` and `fieldErrors` off an error
/// body. `jsonError` in the web app emits `{error, ...extra}`, so both are
/// optional and either may be absent or malformed.
({String? code, Map<String, String>? fieldErrors}) _errorMetadata(
  Object? data,
) {
  if (data is! Map) return (code: null, fieldErrors: null);
  final rawCode = data['code'];
  final code = rawCode is String && rawCode.trim().isNotEmpty
      ? rawCode.trim()
      : null;
  final rawFieldErrors = data['fieldErrors'];
  Map<String, String>? fieldErrors;
  if (rawFieldErrors is Map) {
    final parsed = <String, String>{};
    var malformed = false;
    for (final entry in rawFieldErrors.entries) {
      if (entry.key is! String || entry.value is! String) {
        malformed = true;
        break;
      }
      parsed[entry.key as String] = entry.value as String;
    }
    // A partially-parsed map is worse than none: it would bind some fields and
    // silently drop others, so the caller shows an incomplete form error.
    fieldErrors = malformed ? null : parsed;
  }
  return (code: code, fieldErrors: fieldErrors);
}
