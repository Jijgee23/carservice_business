import 'package:carservice_business/core/utils/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatMoney groups thousands and drops a zero fraction', () {
    expect(formatMoney('25000.00'), '25,000₮');
    expect(formatMoney('1500000'), '1,500,000₮');
    expect(formatMoney('999'), '999₮');
    expect(formatMoney('0.00'), '0₮');
    expect(formatMoney('-0.00'), '0₮');
    expect(formatMoney('-12500.00'), '-12,500₮');
  });

  test('formatMoney keeps a non-zero fraction exactly', () {
    expect(formatMoney('100.50'), '100.50₮');
    expect(formatMoney('1234567890.1200300'), '1,234,567,890.1200300₮');
    expect(formatMoney('9007199254740993'), '9,007,199,254,740,993₮');
  });

  test('formatMoney shows a dash for a missing amount', () {
    expect(formatMoney(null), '—');
    expect(formatMoney(''), '—');
    expect(formatMoney('  '), '—');
  });

  test('formatMoneyNum rounds to cents', () {
    expect(formatMoneyNum(25000), '25,000₮');
    expect(formatMoneyNum(25000.0), '25,000₮');
    expect(formatMoneyNum(100.5), '100.50₮');
    expect(formatMoneyNum(0.1 + 0.2), '0.30₮');
    expect(formatMoneyNum(null), '—');
    expect(formatMoneyNum(double.nan), '—');
  });
}
