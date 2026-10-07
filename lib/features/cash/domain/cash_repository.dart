import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/domain/settlement.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';

/// Contract over the `/api/v1/cash/*` endpoints the app still uses: the
/// register open flag (order payments) and the postpaid settlement flow.
abstract interface class CashRepository {
  /// Enabled receiving banks (same endpoint as the order payment screen).
  Future<Result<BankSettings>> getBanks();

  /// Light "is a session open" flag (payments.create or cash.manage).
  Future<Result<bool>> isSessionOpen(String branchId);

  // Postpaid settlement («Тооцоо нийлэх»).
  Future<Result<EligibleOrders>> getEligibleOrders({
    required String customerId,
    required String branchId,
  });
  Future<Result<Settlement>> createSettlement(SettlementDraft draft);
}
