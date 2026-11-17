import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/organization/data/organization_repository.dart';
import 'package:carservice_business/features/organization/domain/organization.dart';
import 'package:carservice_business/features/organization/domain/organization_repository.dart';
import 'package:carservice_business/features/profile/data/me_repository.dart';

/// Эзний заавал бөглөх алхмууд (`GET /api/v1/tenant` → `onboarding`):
/// эхлээд засварын нэр, дараа нь үзүүлдэг үйлчилгээ — вэбийн dashboard-ын
/// `shop-name-gate.tsx` / `service-keys-gate.tsx`-тэй адил дараалал.
///
/// Shell нь [needsShopName] / [needsServiceKeys] үнэн үед хааж болохгүй
/// дэлгэц харуулна. Эзэн биш, эсвэл ачаалж чадаагүй (хуучин сервер, сүлжээ)
/// үед юу ч хаахгүй — сервер өөрөө ямар нэг үйлдлийг хориглодоггүй.
class TenantOnboardingController extends ChangeNotifier {
  TenantOnboardingController({
    OrganizationRepository? repo,
    bool Function()? isOwner,
    Future<void> Function()? refreshUser,
  }) : _repo = repo ?? RemoteOrganizationRepository(),
       _isOwner = isOwner ?? (() => Authenticator.user?.isOwner == true),
       _refreshUser = refreshUser ?? _refreshCachedUser;

  final OrganizationRepository _repo;
  final bool Function() _isOwner;

  /// The cached user carries the tenant name (headers, greeting).
  final Future<void> Function() _refreshUser;

  static Future<void> _refreshCachedUser() async {
    await MeRepository().refresh();
  }

  TenantOnboarding onboarding = TenantOnboarding.none;

  /// Одоогийн нэр (хувь хүний бүртгэлд эзний овог нэр).
  String currentName = '';
  bool savingName = false;
  bool _disposed = false;

  bool get needsShopName => onboarding.needsShopName;

  /// Нэрийн алхмын дараа л.
  bool get needsServiceKeys =>
      !onboarding.needsShopName && onboarding.needsServiceKeys;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (!_isOwner()) return;
    final result = await _repo.load();
    if (result case Ok(:final value)) {
      onboarding = value.onboarding;
      currentName = value.name;
      _notify();
    }
  }

  /// `PATCH /tenant { name }` — баталгаажуулна. Алдааны мессеж буцаана
  /// (409 CONFLICT: нэр давхацсан), амжилттай бол `null`.
  Future<String?> saveShopName(String raw) async {
    final invalid = ShopName.validate(raw);
    if (invalid != null) return invalid;
    if (savingName) return null;
    savingName = true;
    _notify();
    final result = await _repo.update({'name': ShopName.normalize(raw)});
    savingName = false;
    switch (result) {
      case Ok(:final value):
        onboarding = TenantOnboarding(
          needsShopName: false,
          // Older payloads may omit `onboarding`; keep the known step then.
          needsServiceKeys:
              value.onboarding.needsServiceKeys || onboarding.needsServiceKeys,
        );
        currentName = value.name;
        _notify();
        unawaited(_refreshUser().catchError((_) {}));
        return null;
      case Err(:final error):
        _notify();
        return error.fieldErrors?['name'] ?? error.display;
    }
  }

  /// Үйлчилгээгээ хадгалсны дараа.
  void serviceKeysSaved() {
    onboarding = TenantOnboarding(needsShopName: onboarding.needsShopName);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
