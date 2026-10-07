import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/cash/domain/cash_repository.dart';
import 'package:carservice_business/features/cash/domain/settlement.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';

class FakeCashRepository implements CashRepository {
  bool openFlag = false;
  bool openFlagFails = false;
  final flagBranches = <String>[];

  // Settlement fakes.
  List<EligibleOrder> eligible = const [];
  final settlementDrafts = <SettlementDraft>[];
  final settlements = <Settlement>[];

  /// Errors returned (in order) by createSettlement before it succeeds.
  final createSettlementErrors = <AppError>[];

  @override
  Future<Result<BankSettings>> getBanks() async =>
      const Ok(BankSettings(['KHAN', 'GOLOMT']));

  @override
  Future<Result<bool>> isSessionOpen(String branchId) async {
    flagBranches.add(branchId);
    if (openFlagFails) {
      return const Err(AppError(ErrorKind.unknown, 'алдаа'));
    }
    return Ok(openFlag);
  }

  @override
  Future<Result<EligibleOrders>> getEligibleOrders({
    required String customerId,
    required String branchId,
  }) async {
    var cents = 0;
    for (final o in eligible) {
      cents += moneyToCents(o.outstanding);
    }
    return Ok(EligibleOrders(orders: eligible, total: centsToMoney(cents)));
  }

  @override
  Future<Result<Settlement>> createSettlement(SettlementDraft draft) async {
    settlementDrafts.add(draft);
    if (createSettlementErrors.isNotEmpty) {
      return Err(createSettlementErrors.removeAt(0));
    }
    final s = settlement(id: 's-${settlementDrafts.length}');
    settlements.insert(0, s);
    return Ok(s);
  }
}

EligibleOrder eligibleOrder(String id, String outstanding) => EligibleOrder(
  id: id,
  number: '#$id',
  totalAmount: outstanding,
  paidAmount: '0',
  outstanding: outstanding,
);

Settlement settlement({
  String id = 's-1',
  bool voided = false,
  OrderPaymentMethod method = OrderPaymentMethod.BANK_TRANSFER,
}) => Settlement(
  id: id,
  branch: const CashRef('b-1', 'Төв салбар'),
  customer: const CashRef('c-1', 'Тест ХК'),
  amount: '300000',
  method: method,
  bank: 'KHAN',
  occurredAt: DateTime(2026, 10, 3, 12),
  orderCount: 2,
  entryId: 'e-9',
  createdAt: DateTime(2026, 10, 3, 12),
  voidedAt: voided ? DateTime(2026, 10, 4) : null,
);
