import 'package:carservice_business/features/cash/domain/cash_entry.dart';

/// GET /sessions/open-flag -> `{branchId, open}`.
bool parseSessionOpenFlag(Object? raw) {
  final open = raw is Map ? raw['open'] : null;
  if (open is! bool) throw const CashParseException('open буруу байна.');
  return open;
}
