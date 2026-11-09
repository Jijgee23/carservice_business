/// Displayed amounts in tugrik: thousands grouped, a zero fraction dropped,
/// any other fraction kept exactly as given — "25000.00" → "25,000₮",
/// "100.50" → "100.50₮", null/empty → "—".
///
/// Works on the decimal text rather than a double, so API amounts (`Money`,
/// see `orders/domain/order.dart`) are shown exactly, however large. Text
/// that is not a plain decimal is shown as-is with the sign appended.
String formatMoney(String? decimal) {
  final text = decimal?.trim() ?? '';
  if (text.isEmpty) return '—';
  final match = _decimal.firstMatch(text);
  if (match == null) return '$text₮';
  final integer = match[2]!.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  final fraction = match[3] ?? '';
  final shownFraction = RegExp(r'^0*$').hasMatch(fraction) ? '' : '.$fraction';
  final isZero = shownFraction.isEmpty && RegExp(r'^0+$').hasMatch(match[2]!);
  final sign = isZero ? '' : match[1]!;
  return '$sign$integer$shownFraction₮';
}

/// [formatMoney] for an already parsed number (legacy `double` fields,
/// report totals), rounded to two decimals.
String formatMoneyNum(num? value) {
  if (value == null || !value.isFinite) return '—';
  return formatMoney(value is int ? '$value' : value.toStringAsFixed(2));
}

final _decimal = RegExp(r'^(-?)(\d+)(?:\.(\d*))?$');
