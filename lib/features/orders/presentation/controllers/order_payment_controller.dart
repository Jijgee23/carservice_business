import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/domain/cash_session.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_error_codes.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/domain/payment_bank.dart';
import 'package:carservice_business/features/orders/domain/postpaid_settlement.dart';

/// Owns the payment screen's complete server-authoritative state.
///
/// The controller intentionally does not mutate a [ServiceOrderDetail] after a
/// write. Every successful mutation is followed by a fresh detail, ledger and
/// QPay read, which keeps the payment status and remaining amount owned by the
/// API rather than by a stale widget calculation.
class OrderPaymentController extends ChangeNotifier {
  OrderPaymentController({
    required this.repo,
    required this.orderId,
    this._user,
    this.sessionOpenLookup,
  });

  final OrdersRepository repo;
  final String orderId;
  final User? _user;

  /// Reads the branch's "cash session open" flag (GET /cash/sessions/open-flag).
  /// Null disables the warning; a failed read leaves the flag unknown.
  final Future<Result<bool>> Function(String branchId)? sessionOpenLookup;

  /// Whether the order's branch has an open drawer session; null = unknown.
  bool? sessionOpen;

  AsyncValue<ServiceOrderDetail> detailState = const AsyncLoading();
  AsyncValue<List<OrderPaymentRecord>> paymentsState = const AsyncLoading();
  AsyncValue<QPayState> qpayState = const AsyncLoading();
  AsyncValue<BankSettings> banksState = const AsyncLoading();
  AppError? lastError;
  QPayCheckResult? qpayCheckResult;
  AppError? qpayCheckError;

  bool _disposed = false;
  bool _operationActive = false;
  int _generation = 0;
  bool _loaded = false;

  ServiceOrderDetail? get order => detailState.valueOrNull;
  List<OrderPaymentRecord> get payments =>
      paymentsState.valueOrNull ?? const <OrderPaymentRecord>[];
  QPayState? get qpay => qpayState.valueOrNull;

  /// Payment accounts offered by the picker; empty until GET /banks resolves.
  List<PaymentBank> get accounts =>
      banksState.valueOrNull?.accounts ?? const <PaymentBank>[];
  bool get isLoading =>
      detailState is AsyncLoading ||
      paymentsState is AsyncLoading ||
      qpayState is AsyncLoading;
  bool get isBusy => _operationActive;

  User? get _currentUser {
    if (_user != null) return _user;
    try {
      return Authenticator.user;
    } catch (_) {
      // Unit tests and pre-auth routes may not have opened Hive yet.
      return null;
    }
  }

  bool can(String permission) {
    final user = _currentUser;
    return user?.isOwner == true ||
        (user?.role?.permissions.contains(permission) ?? false);
  }

  /// Owner or `orders.closeUnpaidPostpaid`.
  bool get canSettlePostpaid => userCanSettlePostpaid(_currentUser);

  /// A COMPLETED postpaid order only accepts payment writes from settlers.
  /// Unknown order state is not blocked here; the server stays authoritative.
  bool get settlementLocked {
    final value = order;
    return value != null &&
        value.isPostpaid &&
        value.status == OrderStatus.COMPLETED &&
        !canSettlePostpaid;
  }

  /// Internal repairs take no payment at all (server: ORDER_INTERNAL_NO_PAYMENT).
  bool get internalLocked => order?.isInternal == true;

  bool get canView => can('payments.view');

  /// True while the order's branch is known to have no open drawer session:
  /// record / QPay-start / reverse are disabled (any payment method).
  bool get cashSessionClosed => cashSessionBlocked(sessionOpen);

  /// Per-method hook of the payment sheet; every method is blocked alike.
  bool showNoSessionWarning(OrderPaymentMethod method) => cashSessionClosed;

  /// The flag endpoint needs `payments.create` or `cash.manage`.
  Future<void> _loadSessionFlag() async {
    final lookup = sessionOpenLookup;
    final branchId = order?.branch.id;
    if (lookup == null || branchId == null) return;
    if (!can('payments.create') && !can('cash.manage')) return;
    final result = await lookup(branchId);
    if (_disposed) return;
    sessionOpen = switch (result) {
      Ok(:final value) => value,
      Err() => null,
    };
    notifyListeners();
  }

  bool get canCreate =>
      can('payments.create') && !settlementLocked && !internalLocked;
  bool get canEdit =>
      can('payments.edit') && !settlementLocked && !internalLocked;
  bool get canDelete =>
      can('payments.delete') && !settlementLocked && !internalLocked;

  Future<void> load() async {
    // Banks are static per session; fetch once, never blocks the ledger.
    if (banksState is! AsyncData) unawaited(_loadBanks());
    await refresh(initial: true);
  }

  bool get banksLoading => banksState is AsyncLoading;
  bool get banksFailed => banksState is AsyncError;

  /// Reloads only the QPay status (retry after a failed load).
  Future<void> retryQPay() async {
    if (_disposed) return;
    qpayState = const AsyncLoading();
    notifyListeners();
    final result = await repo.getQPay(orderId);
    if (_disposed) return;
    qpayState = switch (result) {
      Ok(:final value) => AsyncData(
        QPayState(qpayEnabled: value.qpayEnabled, pending: value.pending),
      ),
      Err(:final error) => AsyncError(error),
    };
    notifyListeners();
  }

  Future<void> retryBanks() async {
    banksState = const AsyncLoading();
    notifyListeners();
    await _loadBanks();
  }

  Future<void> _loadBanks() async {
    final result = await repo.getBanks();
    if (_disposed) return;
    banksState = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => AsyncError(error),
    };
    notifyListeners();
  }

  Future<void> refresh({bool initial = false}) async {
    if (_disposed || !canView) return;
    final generation = ++_generation;
    if (initial || !_loaded) {
      detailState = const AsyncLoading();
      paymentsState = const AsyncLoading();
      qpayState = const AsyncLoading();
      _loaded = true;
      _notifyIfCurrent(generation);
    }

    final results = await Future.wait<Object?>([
      repo.getOrderDetail(orderId),
      repo.getPayments(orderId),
      repo.getQPay(orderId),
    ]);
    if (!_isCurrent(generation)) return;

    final detail = results[0] as Result<ServiceOrderDetail>;
    final ledger = results[1] as Result<List<OrderPaymentRecord>>;
    final qpayResult =
        results[2] as Result<({bool qpayEnabled, OrderPayment? pending})>;
    detailState = switch (detail) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => AsyncError(error),
    };
    paymentsState = switch (ledger) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => AsyncError(error),
    };
    qpayState = switch (qpayResult) {
      Ok(:final value) => AsyncData(
        QPayState(qpayEnabled: value.qpayEnabled, pending: value.pending),
      ),
      Err(:final error) => AsyncError(error),
    };
    lastError = _firstError(detail, ledger, qpayResult);
    _notifyIfCurrent(generation);
    unawaited(_loadSessionFlag());
  }

  /// Creates a paid ledger row. The server remains authoritative for the
  /// final status and balance; this method only performs local shape checks.
  Future<bool> createManual({
    required String amount,
    required OrderPaymentMethod method,
    String? bankId,
  }) async {
    if (!canCreate || method == OrderPaymentMethod.QPAY) return false;
    if (cashSessionClosed) return _failed(_sessionClosedError);
    if (paymentMethodNeedsBank(method) && (bankId == null || bankId.isEmpty)) {
      _setError(
        const AppError(
          ErrorKind.unknown,
          OrdersErrorCodes.paymentBankRequiredMessage,
        ),
      );
      return false;
    }
    final normalized = _validateAmount(amount);
    if (normalized == null) {
      _setError(
        const AppError(
          ErrorKind.unknown,
          'Дүнг 0-ээс их, 2 орны бутархайтай оруулна уу.',
        ),
      );
      return false;
    }
    final remaining = _remainingMoney;
    if (remaining != null && _compareDecimal(normalized, remaining.raw) > 0) {
      _setError(
        const AppError(ErrorKind.unknown, 'Төлбөрийн дүн үлдэгдлээс их байна.'),
      );
      return false;
    }
    return _runMutation(() async {
      final result = await repo.createPayment(
        orderId,
        method: method,
        amount: Money(normalized),
        bankId: paymentMethodNeedsBank(method) ? bankId : null,
      );
      return switch (result) {
        Ok() => true,
        Err(:final error) => _failed(error),
      };
    });
  }

  /// Reason the reverse action is disabled for [payment], or null when allowed.
  String? reverseBlockedReason(OrderPaymentRecord payment) =>
      payment.isSettlement
      ? OrdersErrorCodes.settlementPaymentLockedMessage
      : payment.locked
      ? OrdersErrorCodes.cashSessionEntryLockedMessage
      : cashSessionClosed
      ? CashSessionClosedError.message
      : null;

  Future<bool> reverse(OrderPaymentRecord payment) async {
    if (!canDelete ||
        payment.status != OrderPaymentRecordStatus.PAID ||
        payment.locked ||
        payment.isSettlement) {
      return false;
    }
    if (cashSessionClosed) return _failed(_sessionClosedError);
    return _runMutation(() async {
      final result = await repo.reversePayment(orderId, payment.id);
      return switch (result) {
        Ok() => true,
        Err(:final error) => _failed(error),
      };
    });
  }

  Future<bool> createQPay({String? amount}) async {
    if (!canCreate || qpay?.qpayEnabled != true || qpay?.pending != null) {
      return false;
    }
    if (cashSessionClosed) return _failed(_sessionClosedError);
    _clearQPayFeedback();
    return _runMutation(() async {
      final result = await repo.createQPay(orderId, amount: amount);
      return switch (result) {
        Ok() => true,
        Err(:final error) => _failed(_withServerQPayMessage(error)),
      };
    });
  }

  Future<bool> checkQPay() async {
    final pending = qpay?.pending;
    if (!canEdit || pending == null) return false;
    _clearQPayFeedback();
    return _runMutation(() async {
      final result = await repo.checkQPay(orderId, pending.id);
      return switch (result) {
        Ok(:final value) => _recordQPayCheck(value),
        Err(:final error) => _failedQPay(error),
      };
    });
  }

  Future<bool> cancelQPay() async {
    final pending = qpay?.pending;
    if (!canDelete || pending == null) return false;
    _clearQPayFeedback();
    return _runMutation(() async {
      final result = await repo.cancelQPay(orderId, pending.id);
      return switch (result) {
        Ok() => true,
        Err(:final error) => _failed(_withServerQPayMessage(error)),
      };
    });
  }

  /// QPAY_PREVIOUS_PAID / QPAY_INVOICE_PAID: the old invoice was already paid
  /// and recorded server-side. The failed mutation still runs the full
  /// order/payments/QPay refresh in [_runMutation], and the payment sheet
  /// closes once the order reads PAID. QPAY_CANCEL_FAILED and
  /// QPAY_INVOICE_PARTIALLY_PAID change nothing, so the QR stays visible.
  /// All of them are shown with the server's own message; a 5xx kind would
  /// otherwise be replaced by the generic "server error" text.
  AppError _withServerQPayMessage(AppError error) {
    const codes = {
      'QPAY_PREVIOUS_PAID',
      'QPAY_INVOICE_PAID',
      'QPAY_CANCEL_FAILED',
      'QPAY_INVOICE_PARTIALLY_PAID',
      'QPAY_OVERPAYMENT',
      'QPAY_ORDER_CANCELLED',
      'QPAY_PAYMENT_NOT_PENDING',
    };
    if (!codes.contains(error.code) || error.kind == ErrorKind.unknown) {
      return error;
    }
    return AppError(
      ErrorKind.unknown,
      error.message,
      statusCode: error.statusCode,
      code: error.code,
      fieldErrors: error.fieldErrors,
    );
  }

  Money? get _remainingMoney {
    final value = order;
    if (value == null) return null;
    if (value.paymentTotals != null) {
      return value.paymentTotals!.remainingAmountMoney;
    }
    final total = value.totalAmountMoney;
    final paid = value.paidAmountMoney ?? _ledgerPaidMoney;
    if (total == null || paid == null) return null;
    return Money(_subtractDecimal(total.raw, paid.raw));
  }

  Money? get _ledgerPaidMoney {
    if (paymentsState is AsyncError) return null;
    final paid = payments
        .where((item) => item.status == OrderPaymentRecordStatus.PAID)
        .map((item) => item.amountMoney.raw)
        .toList(growable: false);
    if (paid.isEmpty) return const Money('0');
    var sum = paid.first;
    for (final value in paid.skip(1)) {
      sum = _addDecimal(sum, value);
    }
    return Money(sum);
  }

  static const _sessionClosedError = AppError(
    ErrorKind.unknown,
    CashSessionClosedError.message,
    statusCode: 409,
    code: CashSessionClosedError.code,
  );

  bool _failed(AppError error) {
    if (error.isCashSessionClosed) sessionOpen = false;
    _setError(error);
    return false;
  }

  bool _recordQPayCheck(({bool paid, String? message}) value) {
    qpayCheckError = null;
    qpayCheckResult = QPayCheckResult(
      paid: value.paid,
      message: value.message?.trim().isEmpty == true ? null : value.message,
    );
    notifyListeners();
    return value.paid;
  }

  bool _failedQPay(AppError error) {
    qpayCheckResult = null;
    qpayCheckError = error;
    return _failed(error);
  }

  void _clearQPayFeedback() {
    if (qpayCheckResult == null && qpayCheckError == null) return;
    qpayCheckResult = null;
    qpayCheckError = null;
    notifyListeners();
  }

  Future<bool> _runMutation(Future<bool> Function() operation) async {
    if (_disposed || _operationActive) return false;
    _operationActive = true;
    lastError = null;
    notifyListeners();
    var succeeded = false;
    try {
      succeeded = await operation();
      if (!_disposed) {
        // A rejected or racing server mutation still invalidates the three
        // snapshots on screen. Preserve its error after the authoritative
        // reload so the user sees the useful server response.
        final mutationError = lastError;
        await refresh();
        if (mutationError != null && !_disposed) {
          lastError = mutationError;
          notifyListeners();
        }
      }
      return succeeded;
    } finally {
      if (!_disposed) {
        _operationActive = false;
        notifyListeners();
      }
    }
  }

  void _setError(AppError error) {
    if (_disposed) return;
    lastError = error;
    notifyListeners();
  }

  AppError? _firstError(
    Result<ServiceOrderDetail> detail,
    Result<List<OrderPaymentRecord>> ledger,
    Result<({bool qpayEnabled, OrderPayment? pending})> qpayResult,
  ) {
    if (detail case Err(:final error)) return error;
    if (ledger case Err(:final error)) return error;
    if (qpayResult case Err(:final error)) return error;
    return null;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notifyIfCurrent(int generation) {
    if (_isCurrent(generation)) notifyListeners();
  }

  String? _validateAmount(String input) {
    final value = input.replaceAll(',', '').trim();
    if (!RegExp(r'^(?:0|[1-9]\d*)(?:\.\d{1,2})?$').hasMatch(value)) {
      return null;
    }
    if (_compareDecimal(value, '0') <= 0) return null;
    return value;
  }

  int _compareDecimal(String left, String right) {
    final a = _decimalParts(left);
    final b = _decimalParts(right);
    final scale = a.$2.length > b.$2.length ? a.$2.length : b.$2.length;
    final av =
        BigInt.parse(a.$1) * BigInt.from(10).pow(scale) +
        _fraction(a.$2, scale);
    final bv =
        BigInt.parse(b.$1) * BigInt.from(10).pow(scale) +
        _fraction(b.$2, scale);
    return av.compareTo(bv);
  }

  String _subtractDecimal(String left, String right) {
    final a = _decimalParts(left);
    final b = _decimalParts(right);
    final scale = a.$2.length > b.$2.length ? a.$2.length : b.$2.length;
    final av =
        BigInt.parse(a.$1) * BigInt.from(10).pow(scale) +
        _fraction(a.$2, scale);
    final bv =
        BigInt.parse(b.$1) * BigInt.from(10).pow(scale) +
        _fraction(b.$2, scale);
    final result = av - bv;
    if (result <= BigInt.zero) return '0';
    final raw = result.toString().padLeft(scale + 1, '0');
    if (scale == 0) return raw;
    final split = raw.length - scale;
    return '${raw.substring(0, split)}.${raw.substring(split)}'.replaceFirst(
      RegExp(r'\.0+$'),
      '',
    );
  }

  String _addDecimal(String left, String right) {
    final a = _decimalParts(left);
    final b = _decimalParts(right);
    final scale = a.$2.length > b.$2.length ? a.$2.length : b.$2.length;
    final av =
        BigInt.parse(a.$1) * BigInt.from(10).pow(scale) +
        _fraction(a.$2, scale);
    final bv =
        BigInt.parse(b.$1) * BigInt.from(10).pow(scale) +
        _fraction(b.$2, scale);
    final raw = (av + bv).toString().padLeft(scale + 1, '0');
    if (scale == 0) return raw;
    final split = raw.length - scale;
    return '${raw.substring(0, split)}.${raw.substring(split)}';
  }

  // scale == 0 үед бутархай хэсэг хоосон — BigInt.parse('') FormatException
  // шиддэг тул бүхэл дүн (жишээ нь "14000") бүртгэх товч чимээгүй унаж байсан.
  BigInt _fraction(String digits, int scale) {
    final padded = digits.padRight(scale, '0');
    return padded.isEmpty ? BigInt.zero : BigInt.parse(padded);
  }

  (String, String) _decimalParts(String value) {
    final pieces = value.split('.');
    return (pieces.first, pieces.length == 1 ? '' : pieces.last);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
