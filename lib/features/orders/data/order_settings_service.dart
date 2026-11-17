import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/features/orders/domain/order_settings.dart';

/// `GET /api/v1/tenant/order-settings` — нэвтэрсэн бүх ажилтан уншина.
///
/// Best-effort, [SubscriptionService]-тэй ижил: алдаа (сүлжээ, хуучин сервер
/// дээр 404) гарвал toast харуулахгүйгээр `null` буцааж, дуудагч
/// [OrderSettings.defaults]-аар ажиллана. Сессийн туршид cache-лэгдэнэ;
/// гарах үед [invalidate].
class OrderSettingsService {
  OrderSettingsService._();
  static final OrderSettingsService instance = OrderSettingsService._();

  OrderSettings? _cache;
  Future<OrderSettings?>? _inFlight;

  /// Test seam — production reads the API.
  Future<Object?> Function()? loaderOverride;

  OrderSettings? get cached => _cache;

  /// [cached], эсвэл анхдагч дүрэм.
  OrderSettings get current => _cache ?? OrderSettings.defaults;

  Future<OrderSettings?> get({bool force = false}) {
    if (_cache != null && !force) return Future.value(_cache);
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<OrderSettings?> _load() async {
    final loader = loaderOverride;
    try {
      // Signed out (or no session store, e.g. in widget tests): nothing to ask.
      if (loader == null && Authenticator.user == null) return null;
      final data = loader != null
          ? await loader()
          : (await apiOrThrow(Api.get, 'tenant/order-settings')).data;
      if (data is! Map) return null;
      return _cache = OrderSettings.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  void invalidate() {
    _cache = null;
    _inFlight = null;
  }
}
