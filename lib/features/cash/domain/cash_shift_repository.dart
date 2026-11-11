import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';

/// Contract over `/api/v1/cash/sessions*` («Кассын ээлж»). Every call needs
/// `cash.manage` (owner always). The `X-Working-Branch` header is added by
/// the network layer: while the working branch is pinned the server scopes
/// every call to it and ignores a different `branchId` filter.
///
/// Errors surface as `Err(AppError)` keeping `statusCode`/`code`/
/// `fieldErrors`: `CASH_SESSION_ALREADY_OPEN` (409), `CASH_SESSION_NOT_OPEN`
/// (422), `CASH_AMOUNT_INVALID`/`CASH_BRANCH_INVALID`/`CASH_FIELD_INVALID`
/// (422 with field errors), `CASH_SESSION_NOT_FOUND` (404).
abstract interface class CashShiftRepository {
  /// `GET /cash/sessions` — newest first.
  Future<Result<CashShiftPage>> listShifts(CashShiftQuery query);

  /// `GET /cash/sessions/current?branchId=`.
  Future<Result<CurrentCashShift>> currentShift(String? branchId);

  /// `GET /cash/sessions/[id]`.
  Future<Result<CashShiftDetail>> shiftDetail(String id);

  /// `POST /cash/sessions` → the new OPEN session.
  Future<Result<CashShift>> openShift({
    required String branchId,
    required String openingCash,
    String? note,
  });

  /// `POST /cash/sessions/[id]/close` → the CLOSED session.
  Future<Result<CashShift>> closeShift(
    String id, {
    required String countedCash,
    String? note,
  });
}
