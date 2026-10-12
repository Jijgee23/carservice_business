import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/domain/cash_entry.dart';
import 'package:carservice_business/features/cash/domain/cash_repository.dart';
import 'package:carservice_business/features/cash/domain/cash_session.dart';
import 'package:carservice_business/features/cash/domain/settlement.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';

const settlementAmountChangedNotice =
    'Захиалгын үлдэгдэл өөрчлөгдсөн тул жагсаалтыг шинэчиллээ. Дүнг шалгаад дахин баталгаажуулна уу.';

/// Form state of «Тооцоо нийлэх»: customer + branch -> eligible orders (all
/// ticked, total = sum of ticked outstandings) -> method/bank/date/note.
/// The server stays authoritative; a stale view comes back as
/// SETTLEMENT_AMOUNT_CHANGED and the list is reloaded.
class SettlementFlowController extends ChangeNotifier {
  SettlementFlowController({
    required this.repo,
    required this.accounts,
    this.branchId,
    DateTime? now,
  }) : _now = now ?? DateTime.now(),
       date = _dateOnly(now ?? DateTime.now());

  final CashRepository repo;
  final List<PaymentBank> accounts;
  String? branchId;
  final DateTime _now;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  CashRef? customer;
  List<EligibleOrder> orders = const [];
  final Set<String> selected = {};
  bool loading = false;
  AppError? loadError;

  OrderPaymentMethod method = OrderPaymentMethod.CASH;
  String? bankId;
  DateTime date;
  String note = '';

  /// Whether the branch has an open drawer session; null until known.
  bool? sessionOpen;
  int _flagGeneration = 0;

  bool submitting = false;
  AppError? submitError;

  /// Set after a stale-amount rejection; cleared on the next edit/submit.
  String? notice;

  bool _disposed = false;
  int _generation = 0;

  bool get needsBank => paymentMethodNeedsBank(method);

  /// Any method: settling is blocked while the branch has no open session.
  bool get showNoSessionWarning => cashSessionBlocked(sessionOpen);

  Future<void> loadSessionFlag() async {
    final branch = branchId;
    final generation = ++_flagGeneration;
    if (branch == null) {
      sessionOpen = null;
      _notify();
      return;
    }
    final result = await repo.isSessionOpen(branch);
    if (_disposed || generation != _flagGeneration) return;
    sessionOpen = switch (result) {
      Ok(:final value) => value,
      Err() => null,
    };
    _notify();
  }

  int get totalCents => orders
      .where((o) => selected.contains(o.id))
      .fold(0, (sum, o) => sum + moneyToCents(o.outstanding));

  String get total => centsToMoney(totalCents);
  bool get allSelected => orders.isNotEmpty && selected.length == orders.length;

  bool get canSubmit =>
      !submitting &&
      !showNoSessionWarning &&
      !loading &&
      branchId != null &&
      customer != null &&
      selected.isNotEmpty &&
      totalCents > 0 &&
      (!needsBank || bankId != null);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setCustomer(CashRef value) {
    customer = value;
    orders = const [];
    selected.clear();
    notice = null;
    submitError = null;
    return loadEligible(selectAll: true);
  }

  Future<void> setBranch(String value) {
    if (value == branchId) return Future.value();
    branchId = value;
    orders = const [];
    selected.clear();
    sessionOpen = null;
    loadSessionFlag();
    return loadEligible(selectAll: true);
  }

  /// Loads the customer's settleable orders. With [selectAll] every row is
  /// ticked; otherwise the previous ticks are kept for rows that still exist.
  Future<void> loadEligible({bool selectAll = false}) async {
    final c = customer;
    final b = branchId;
    if (c == null || b == null) {
      _notify();
      return;
    }
    final generation = ++_generation;
    loading = true;
    loadError = null;
    _notify();
    final result = await repo.getEligibleOrders(customerId: c.id, branchId: b);
    if (_disposed || generation != _generation) return;
    loading = false;
    switch (result) {
      case Ok(:final value):
        orders = value.orders;
        final ids = orders.map((o) => o.id).toSet();
        if (selectAll) {
          selected
            ..clear()
            ..addAll(ids);
        } else {
          selected.removeWhere((id) => !ids.contains(id));
        }
      case Err(:final error):
        orders = const [];
        selected.clear();
        loadError = error;
    }
    _notify();
  }

  void toggle(String orderId, bool value) {
    if (value) {
      selected.add(orderId);
    } else {
      selected.remove(orderId);
    }
    notice = null;
    _notify();
  }

  void toggleAll(bool value) {
    selected.clear();
    if (value) selected.addAll(orders.map((o) => o.id));
    notice = null;
    _notify();
  }

  void setMethod(OrderPaymentMethod value) {
    method = value;
    if (!paymentMethodNeedsBank(value)) bankId = null;
    _notify();
  }

  void setBank(String? value) {
    bankId = value;
    _notify();
  }

  void setDate(DateTime value) {
    // Never later than today.
    final picked = _dateOnly(value);
    final today = _dateOnly(_now);
    date = picked.isAfter(today) ? today : picked;
    _notify();
  }

  SettlementDraft? buildDraft() {
    if (!canSubmit) return null;
    final trimmed = note.trim();
    final today = _dateOnly(_now);
    return SettlementDraft(
      branchId: branchId!,
      customerId: customer!.id,
      // Keep server (completedAt) order, not tick order.
      orderIds: [
        for (final o in orders)
          if (selected.contains(o.id)) o.id,
      ],
      method: method,
      bankId: needsBank ? bankId : null,
      // Today means "now": a date-only value could predate an order that
      // completed earlier today (server: CASH_DATE_INVALID).
      occurredAt: date == today ? null : cashDateParam(date),
      note: trimmed.isEmpty ? null : trimmed,
      expectedAmount: total,
    );
  }

  /// Sends the settlement. Returns it on success; null when rejected (see
  /// [submitError] / [notice]).
  Future<Settlement?> submit() async {
    final draft = buildDraft();
    if (draft == null) return null;
    submitting = true;
    submitError = null;
    notice = null;
    _notify();
    final result = await repo.createSettlement(draft);
    if (_disposed) return null;
    submitting = false;
    switch (result) {
      case Ok(:final value):
        _notify();
        return value;
      case Err(:final error):
        if (error.isCashSessionClosed) sessionOpen = false;
        final stale =
            error.code == SettlementErrorCodes.amountChanged ||
            error.code == SettlementErrorCodes.orderInvalid;
        if (stale) {
          notice = error.code == SettlementErrorCodes.amountChanged
              ? settlementAmountChangedNotice
              : error.display;
          _notify();
          await loadEligible();
        } else {
          submitError = error;
          _notify();
        }
        return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
