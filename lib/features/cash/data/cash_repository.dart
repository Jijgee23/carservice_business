import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/data/cash_data_source.dart';
import 'package:carservice_business/features/cash/data/cash_session_dto.dart';
import 'package:carservice_business/features/cash/data/settlement_dto.dart';
import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/cash/domain/cash_repository.dart';
import 'package:carservice_business/features/cash/domain/settlement.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';

class RemoteCashRepository implements CashRepository {
  RemoteCashRepository({CashDataSource? dataSource})
    : _dataSource = dataSource ?? RemoteCashDataSource();

  final CashDataSource _dataSource;

  @override
  Future<Result<BankSettings>> getBanks() async {
    try {
      final json = await _dataSource.banks();
      final raw = json is Map ? json['accounts'] : null;
      if (raw is! List) {
        throw const CashParseException('accounts буруу байна.');
      }
      return Ok(
        BankSettings(
          raw
              .whereType<Map<String, dynamic>>()
              .map(PaymentBank.fromJson)
              .toList(growable: false),
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Банкны жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<bool>> isSessionOpen(String branchId) async {
    try {
      return Ok(
        parseSessionOpenFlag(await _dataSource.sessionOpenFlag(branchId)),
      );
    } catch (error) {
      return Err(_error(error, 'Ээлжийн төлөв ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<EligibleOrders>> getEligibleOrders({
    required String customerId,
    required String branchId,
  }) async {
    try {
      return Ok(
        parseEligibleOrders(
          await _dataSource.eligibleOrders(customerId, branchId),
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Захиалгын жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<Settlement>> createSettlement(SettlementDraft draft) async {
    try {
      return Ok(
        parseSettlementEnvelope(
          await _dataSource.createSettlement(draft.toJson()),
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Тооцоо хадгалж чадсангүй'));
    }
  }
}

AppError _error(Object error, String fallback) => switch (error) {
  AppError value => value,
  CashParseException value => AppError(ErrorKind.unknown, value.message),
  _ => AppError(ErrorKind.unknown, fallback),
};
