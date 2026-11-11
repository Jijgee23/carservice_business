import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/network/working_branch_interceptor.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';
import 'package:carservice_business/features/cash/domain/cash_shift_repository.dart';
import 'package:carservice_business/features/shell/domain/working_branch.dart';

CashShift shift({
  String id = 'sh-1',
  bool open = true,
  String branchId = 'b-1',
  String branchName = 'Төв салбар',
  String openingCash = '50000',
  String? expectedCash = '120000',
  String? countedCash,
  String? difference,
}) => CashShift(
  id: id,
  isOpen: open,
  branch: CashRef(branchId, branchName),
  openedAt: DateTime.utc(2026, 11, 11, 1, 30),
  openedBy: const CashRef('u-1', 'Бат Дорж'),
  openingCash: openingCash,
  closedAt: open ? null : DateTime.utc(2026, 11, 11, 10),
  countedCash: countedCash,
  expectedCash: expectedCash,
  difference: difference,
  cashIn: '80000',
  cashOut: '10000',
  byMethod: const [
    CashShiftMethodTotal(
      method: 'CASH',
      income: '80000',
      expense: '10000',
      net: '70000',
      count: 3,
    ),
    CashShiftMethodTotal(
      method: 'CARD',
      bank: 'acc-pos',
      bankLabel: 'Хаан POS',
      income: '40000',
      expense: '0',
      net: '40000',
      count: 1,
    ),
  ],
);

class FakeCashShiftRepository implements CashShiftRepository {
  FakeCashShiftRepository({List<CashShift>? shifts, this.current})
    : shifts = shifts ?? [];

  List<CashShift> shifts;
  CashShift? current;

  final listQueries = <CashShiftQuery>[];
  final currentBranches = <String?>[];
  final opened = <(String, String, String?)>[];
  final closed = <(String, String, String?)>[];

  AppError? listError;
  AppError? openError;
  AppError? closeError;

  @override
  Future<Result<CashShiftPage>> listShifts(CashShiftQuery query) async {
    listQueries.add(query);
    if (listError != null) return Err(listError!);
    final items = shifts
        .where(
          (s) =>
              query.status == null ||
              (query.status == 'OPEN') == s.isOpen,
        )
        .where((s) => query.branchId == null || s.branch.id == query.branchId)
        .toList();
    return Ok(
      PagedResult(
        items: items,
        pagination: PaginationMeta(
          page: 1,
          pageSize: query.pageSize,
          total: items.length,
          totalPages: 1,
          hasPrev: false,
          hasNext: false,
        ),
      ),
    );
  }

  @override
  Future<Result<CurrentCashShift>> currentShift(String? branchId) async {
    currentBranches.add(branchId);
    return Ok(CurrentCashShift(branchId: branchId ?? '', shift: current));
  }

  @override
  Future<Result<CashShiftDetail>> shiftDetail(String id) async {
    final s = [...shifts, ?current].firstWhere((x) => x.id == id);
    return Ok(
      CashShiftDetail(
        shift: s,
        entries: [
          CashShiftEntry(
            id: 'e-1',
            direction: 'INCOME',
            typeName: 'Засварын төлбөр',
            amount: '80000',
            method: 'CASH',
            methodLabel: 'Бэлэн',
            occurredAt: DateTime.utc(2026, 11, 11, 2),
            orderNumber: 'ЗХ-0012',
          ),
        ],
      ),
    );
  }

  @override
  Future<Result<CashShift>> openShift({
    required String branchId,
    required String openingCash,
    String? note,
  }) async {
    opened.add((branchId, openingCash, note));
    if (openError != null) return Err(openError!);
    final s = shift(
      id: 'sh-new',
      branchId: branchId,
      openingCash: openingCash,
      expectedCash: openingCash,
    );
    current = s;
    shifts = [s, ...shifts];
    return Ok(s);
  }

  @override
  Future<Result<CashShift>> closeShift(
    String id, {
    required String countedCash,
    String? note,
  }) async {
    closed.add((id, countedCash, note));
    if (closeError != null) return Err(closeError!);
    final s = shift(
      id: id,
      open: false,
      countedCash: countedCash,
      difference: '-5000',
    );
    current = null;
    shifts = [for (final x in shifts) x.id == id ? s : x];
    return Ok(s);
  }
}

class FakeWorkingBranchRepository implements WorkingBranchRepository {
  FakeWorkingBranchRepository({
    this.branches = const [
      SwitchableBranch(id: 'b-1', name: 'Төв салбар'),
      SwitchableBranch(id: 'b-2', name: 'Зүүн салбар'),
    ],
    this.lockedBranchId,
  });

  final List<SwitchableBranch> branches;
  final String? lockedBranchId;

  @override
  Future<WorkingBranchOptions> fetchOptions() async => WorkingBranchOptions(
    branches: branches,
    allowAll: true,
    lockedBranchId: lockedBranchId,
  );
}

class MemoryBranchStore implements WorkingBranchSelectionStore {
  MemoryBranchStore([this.value]);
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? selection) async => value = selection;

  @override
  Future<void> clear() async => value = null;
}
