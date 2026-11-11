import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/payment_accounts/data/payment_accounts_repository.dart';
import 'package:carservice_business/features/payment_accounts/domain/payment_account.dart';

/// «Төлбөрийн данс» list (active and inactive) plus the row actions:
/// activate / deactivate and delete. Each action returns the server error so
/// the screen can show its message (e.g. `PAYMENT_ACCOUNT_IN_USE`).
class PaymentAccountListController extends ChangeNotifier {
  PaymentAccountListController({PaymentAccountsRepository? repo})
    : repo = repo ?? RemotePaymentAccountsRepository();

  final PaymentAccountsRepository repo;

  AsyncValue<List<PaymentAccount>> state = const AsyncLoading();

  /// Ids with an action in flight.
  final busy = <String>{};

  bool _disposed = false;
  int _generation = 0;

  List<PaymentAccount> get accounts =>
      state.valueOrNull ?? const <PaymentAccount>[];

  Future<void> load() async {
    final generation = ++_generation;
    if (state is! AsyncData) {
      state = const AsyncLoading();
      _notify();
    }
    final result = await repo.list(includeInactive: true);
    if (_disposed || generation != _generation) return;
    state = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => AsyncError(error),
    };
    _notify();
  }

  /// Puts a saved account into the list (create or edit).
  void upsert(PaymentAccount account) {
    final list = [...accounts];
    final index = list.indexWhere((a) => a.id == account.id);
    if (index == -1) {
      list.add(account);
    } else {
      list[index] = account;
    }
    state = AsyncData(list);
    _notify();
  }

  Future<AppError?> setActive(PaymentAccount account, bool isActive) async {
    if (!busy.add(account.id)) return null;
    _notify();
    final result = await repo.setActive(account.id, isActive);
    busy.remove(account.id);
    if (_disposed) return null;
    switch (result) {
      case Ok(:final value):
        upsert(value);
        return null;
      case Err(:final error):
        _notify();
        return error;
    }
  }

  Future<AppError?> delete(PaymentAccount account) async {
    if (!busy.add(account.id)) return null;
    _notify();
    final result = await repo.delete(account.id);
    busy.remove(account.id);
    if (_disposed) return null;
    switch (result) {
      case Ok():
        state = AsyncData(
          accounts.where((a) => a.id != account.id).toList(growable: false),
        );
        _notify();
        return null;
      case Err(:final error):
        _notify();
        return error;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
