import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/organization/data/organization_repository.dart';
import 'package:carservice_business/features/organization/domain/organization_repository.dart';
import 'package:carservice_business/features/organization/domain/service_keys.dart';

/// «Танайх ямар үйлчилгээ үзүүлдэг вэ?» сонгогчийн төлөв — onboarding-ийн
/// хааж болохгүй дэлгэц болон Тохиргоо → «Үзүүлдэг үйлчилгээ» хоёуланд
/// (вэбийн `service-keys-picker.tsx`).
class ServiceKeysController extends ChangeNotifier {
  ServiceKeysController({OrganizationRepository? repo})
    : _repo = repo ?? RemoteOrganizationRepository();

  final OrganizationRepository _repo;

  AsyncValue<TenantServiceKeys> state = const AsyncLoading();
  Set<String> selected = {};
  String query = '';
  bool saving = false;

  /// Сүүлийн хадгалалтын алдаа.
  String? error;
  bool _disposed = false;

  TenantServiceKeys? get data => state.valueOrNull;
  bool get canEdit => data?.canEdit == true;

  /// Хайлтаар шүүсэн төрлүүд (нуугдсан сонголт ч хадгалагдана).
  List<ServiceKeyChoice> get visible {
    final keys = data?.keys ?? const <ServiceKeyChoice>[];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return keys;
    return keys.where((k) => k.name.toLowerCase().contains(q)).toList();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    _notify();
    final result = await _repo.loadServiceKeys();
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
        selected = {...value.selectedIds};
      case Err(:final error):
        state = AsyncError(error);
    }
    _notify();
  }

  void setQuery(String value) {
    query = value;
    _notify();
  }

  void toggle(String id) {
    if (!selected.remove(id)) selected.add(id);
    error = null;
    _notify();
  }

  /// `true` on success (the selection is then confirmed server-side).
  Future<bool> save() async {
    if (saving) return false;
    if (selected.isEmpty) {
      error = 'Дор хаяж нэг үйлчилгээ сонгоно уу.';
      _notify();
      return false;
    }
    saving = true;
    error = null;
    _notify();
    final result = await _repo.saveServiceKeys(selected.toList());
    saving = false;
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
        selected = {...value.selectedIds};
        _notify();
        return true;
      case Err(:final error):
        this.error = error.fieldErrors?['serviceKeyIds'] ?? error.display;
        _notify();
        return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
