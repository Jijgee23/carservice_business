import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/features/cash/domain/cash_entry.dart';

/// «Кассын ээлж» — one register session of a branch, mirroring
/// `serializeCashSession` (`lib/cash/session.ts`). Amounts stay Decimal
/// strings, as everywhere in the cash feature.
class CashShift {
  final String id;
  final bool isOpen;
  final CashRef branch;
  final DateTime openedAt;
  final CashRef? openedBy;
  final String openingCash;
  final DateTime? closedAt;
  final CashRef? closedBy;

  /// Closed: what the cashier counted. Open: null.
  final String? countedCash;

  /// Open: live (opening + cash in − cash out). Closed: frozen at close.
  final String? expectedCash;

  /// counted − expected, closed sessions only.
  final String? difference;
  final String? note;

  /// Live non-voided CASH totals (null when the server sent none).
  final String? cashIn;
  final String? cashOut;
  final int? entryCount;
  final int? totalEntryCount;
  final List<CashShiftMethodTotal> byMethod;

  const CashShift({
    required this.id,
    required this.isOpen,
    required this.branch,
    required this.openedAt,
    required this.openingCash,
    this.openedBy,
    this.closedAt,
    this.closedBy,
    this.countedCash,
    this.expectedCash,
    this.difference,
    this.note,
    this.cashIn,
    this.cashOut,
    this.entryCount,
    this.totalEntryCount,
    this.byMethod = const [],
  });
}

/// One per-(method, bank) row of a session's breakdown.
class CashShiftMethodTotal {
  final String method;
  final String? bank;
  final String? bankLabel;
  final String income;
  final String expense;
  final String net;
  final int count;
  final String? expected;
  final String? counted;
  final String? difference;

  const CashShiftMethodTotal({
    required this.method,
    required this.income,
    required this.expense,
    required this.net,
    required this.count,
    this.bank,
    this.bankLabel,
    this.expected,
    this.counted,
    this.difference,
  });
}

/// One ledger row inside a session (`serializeCashEntry`).
class CashShiftEntry {
  final String id;

  /// `INCOME` | `EXPENSE`.
  final String direction;
  final String typeName;
  final String amount;
  final String method;
  final String methodLabel;
  final String? bankLabel;
  final DateTime occurredAt;
  final String? note;
  final String? orderNumber;
  final String? customerName;
  final String? counterparty;
  final CashRef? createdBy;
  final DateTime? voidedAt;
  final String? voidReason;

  const CashShiftEntry({
    required this.id,
    required this.direction,
    required this.typeName,
    required this.amount,
    required this.method,
    required this.methodLabel,
    required this.occurredAt,
    this.bankLabel,
    this.note,
    this.orderNumber,
    this.customerName,
    this.counterparty,
    this.createdBy,
    this.voidedAt,
    this.voidReason,
  });

  bool get isIncome => direction == 'INCOME';
}

/// Voids that happened after the session closed — reported apart, they never
/// change the frozen close figures.
class CashShiftPostCloseVoids {
  final int count;
  final String incomeAmount;
  final String expenseAmount;
  final String netAmount;

  const CashShiftPostCloseVoids({
    this.count = 0,
    this.incomeAmount = '0',
    this.expenseAmount = '0',
    this.netAmount = '0',
  });
}

/// `GET /cash/sessions/[id]`.
class CashShiftDetail {
  final CashShift shift;
  final List<CashShiftEntry> entries;
  final List<CashShiftEntry> voidedEntries;
  final CashShiftPostCloseVoids postCloseVoids;

  /// The entry lists are capped server-side (totals stay exact).
  final bool truncated;

  const CashShiftDetail({
    required this.shift,
    this.entries = const [],
    this.voidedEntries = const [],
    this.postCloseVoids = const CashShiftPostCloseVoids(),
    this.truncated = false,
  });
}

/// `GET /cash/sessions/current` — the branch's open session, or none.
class CurrentCashShift {
  final String branchId;
  final CashShift? shift;
  const CurrentCashShift({required this.branchId, this.shift});
}

/// Filters of `GET /cash/sessions` (`status` = OPEN | CLOSED).
class CashShiftQuery {
  final String? branchId;
  final String? status;
  final int page;
  final int pageSize;

  const CashShiftQuery({
    this.branchId,
    this.status,
    this.page = 1,
    this.pageSize = 30,
  });

  Map<String, dynamic> toQuery() => {
    'branchId': ?branchId,
    'status': ?status,
    'page': page,
    'pageSize': pageSize,
  };
}

typedef CashShiftPage = PagedResult<CashShift>;

/// Labels for session payment methods (`SESSION_METHOD_ORDER`).
String cashMethodLabel(String method) => switch (method) {
  'CASH' => 'Бэлэн',
  'CARD' => 'Карт',
  'BANK_TRANSFER' => 'Дансаар',
  'QPAY' => 'QPay',
  'OTHER' => 'Бусад',
  _ => method,
};

/// The sum shown while closing: counted − expected, both Decimal strings,
/// computed on integer cents. Null while either side is unusable.
String? cashDifference(String? counted, String? expected) {
  final c = num.tryParse(counted?.replaceAll(',', '').trim() ?? '');
  final e = num.tryParse(expected ?? '');
  if (c == null || e == null) return null;
  final cents = (c * 100).round() - (e * 100).round();
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;
  if (frac == 0) return '$sign$whole';
  return '$sign$whole.${frac.toString().padLeft(2, '0')}';
}
