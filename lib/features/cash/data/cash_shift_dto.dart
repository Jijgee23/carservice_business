import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';

// Parsers for `/api/v1/cash/sessions*` payloads (`serializeCashSession`,
// `serializeCashEntry`, `getSessionDetail` in `lib/cash/*.ts`).

Map<String, dynamic> _map(Object? value, String what) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw CashParseException('$what буруу байна.');
}

String _str(Object? value, String what) {
  if (value is String && value.isNotEmpty) return value;
  throw CashParseException('$what буруу байна.');
}

String? _optStr(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

String? _optMoney(Object? value) {
  if (value is String && double.tryParse(value) != null) return value;
  if (value is num) return value.toString();
  return null;
}

String _money(Object? value, String what) =>
    _optMoney(value) ?? (throw CashParseException('$what буруу байна.'));

DateTime _date(Object? value, String what) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) throw CashParseException('$what буруу байна.');
  return parsed;
}

DateTime? _optDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

int? _optInt(Object? value) => value is num ? value.toInt() : null;

CashRef? _ref(Object? value) {
  if (value is! Map) return null;
  final id = _optStr(value['id']);
  if (id == null) return null;
  return CashRef(id, _optStr(value['name']) ?? id);
}

CashShiftMethodTotal _methodTotal(Object? raw) {
  final m = _map(raw, 'byMethod');
  return CashShiftMethodTotal(
    method: _str(m['method'], 'method'),
    bank: _optStr(m['bank']),
    bankLabel: _optStr(m['bankLabel']),
    income: _optMoney(m['income']) ?? '0',
    expense: _optMoney(m['expense']) ?? '0',
    net: _optMoney(m['net']) ?? '0',
    count: _optInt(m['count']) ?? 0,
    expected: _optMoney(m['expected']),
    counted: _optMoney(m['counted']),
    difference: _optMoney(m['difference']),
  );
}

CashShift parseCashShift(Object? raw) {
  final json = _map(raw, 'session');
  final branch = _ref(json['branch']);
  if (branch == null) throw const CashParseException('branch буруу байна.');
  final byMethod = json['byMethod'];
  return CashShift(
    id: _str(json['id'], 'id'),
    isOpen: json['status'] != 'CLOSED' && json['closedAt'] == null,
    branch: branch,
    openedAt: _date(json['openedAt'], 'openedAt'),
    openedBy: _ref(json['openedBy']),
    openingCash: _money(json['openingCash'], 'openingCash'),
    closedAt: _optDate(json['closedAt']),
    closedBy: _ref(json['closedBy']),
    countedCash: _optMoney(json['countedCash']),
    expectedCash: _optMoney(json['expectedCash']),
    difference: _optMoney(json['difference']),
    note: _optStr(json['note']),
    cashIn: _optMoney(json['cashIn']),
    cashOut: _optMoney(json['cashOut']),
    entryCount: _optInt(json['entryCount']),
    totalEntryCount: _optInt(json['totalEntryCount']),
    byMethod: byMethod is List
        ? byMethod.map(_methodTotal).toList(growable: false)
        : const [],
  );
}

CashShiftEntry parseCashShiftEntry(Object? raw) {
  final e = _map(raw, 'entry');
  final type = e['type'];
  final customer = e['customer'];
  final method = _optStr(e['method']) ?? 'CASH';
  return CashShiftEntry(
    id: _str(e['id'], 'entry.id'),
    direction: _optStr(e['direction']) ?? 'INCOME',
    typeName: type is Map ? (_optStr(type['name']) ?? '—') : '—',
    amount: _money(e['amount'], 'amount'),
    method: method,
    methodLabel: _optStr(e['methodLabel']) ?? cashMethodLabel(method),
    bankLabel: _optStr(e['bankLabel']),
    occurredAt: _date(e['occurredAt'], 'occurredAt'),
    note: _optStr(e['note']),
    orderNumber: _optStr(e['orderNumber']),
    customerName: customer is Map ? _optStr(customer['name']) : null,
    counterparty: _optStr(e['counterparty']),
    createdBy: _ref(e['createdBy']),
    voidedAt: _optDate(e['voidedAt']),
    voidReason: _optStr(e['voidReason']),
  );
}

List<CashShiftEntry> _entries(Object? raw) => raw is List
    ? raw.map(parseCashShiftEntry).toList(growable: false)
    : const [];

/// `{session: …}` envelope of open/close.
CashShift parseCashShiftEnvelope(Object? raw) =>
    parseCashShift(_map(raw, 'response')['session']);

/// `{sessions: […], pagination: {…}}`.
CashShiftPage parseCashShiftPage(Object? raw, {required int pageSize}) {
  final json = _map(raw, 'response');
  final list = json['sessions'];
  if (list is! List) throw const CashParseException('sessions буруу байна.');
  final items = list.map(parseCashShift).toList(growable: false);
  final meta = json['pagination'];
  return PagedResult(
    items: items,
    pagination: meta is Map
        ? PaginationMeta.fromJson(Map<String, dynamic>.from(meta))
        : PaginationMeta(
            page: 1,
            pageSize: pageSize,
            total: items.length,
            totalPages: 1,
            hasPrev: false,
            hasNext: false,
          ),
  );
}

/// `{branchId, session: CashSession | null}`.
CurrentCashShift parseCurrentCashShift(Object? raw) {
  final json = _map(raw, 'response');
  final session = json['session'];
  return CurrentCashShift(
    branchId: _optStr(json['branchId']) ?? '',
    shift: session == null ? null : parseCashShift(session),
  );
}

/// `{session, entries, voidedEntries, truncated, postCloseVoids}`.
CashShiftDetail parseCashShiftDetail(Object? raw) {
  final json = _map(raw, 'response');
  final voids = json['postCloseVoids'];
  final truncated = json['truncated'];
  return CashShiftDetail(
    shift: parseCashShift(json['session']),
    entries: _entries(json['entries']),
    voidedEntries: _entries(json['voidedEntries']),
    truncated: truncated is Map && truncated['entries'] == true,
    postCloseVoids: voids is Map
        ? CashShiftPostCloseVoids(
            count: _optInt(voids['count']) ?? 0,
            incomeAmount: _optMoney(voids['incomeAmount']) ?? '0',
            expenseAmount: _optMoney(voids['expenseAmount']) ?? '0',
            netAmount: _optMoney(voids['netAmount']) ?? '0',
          )
        : const CashShiftPostCloseVoids(),
  );
}
