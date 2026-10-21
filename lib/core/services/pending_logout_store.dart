import 'package:hive_flutter/hive_flutter.dart';

/// A sign-out the server has not heard about yet (the device was offline):
/// the session's refresh token to revoke, and when the user signed out.
class PendingLogout {
  const PendingLogout({required this.refreshToken, required this.loggedOutAt});

  final String refreshToken;
  final DateTime loggedOutAt;

  /// Past this the refresh token has long expired on the server
  /// (`REFRESH_TOKEN_MAX_AGE_SECONDS`, 7 days): nothing is left to revoke.
  static const maxAge = Duration(days: 30);

  bool isStale(DateTime now) => now.difference(loggedOutAt) > maxAge;

  Map<String, dynamic> toMap() => {
    'refreshToken': refreshToken,
    'loggedOutAt': loggedOutAt.toUtc().toIso8601String(),
  };

  /// Null for anything unreadable: a corrupt entry is just dropped.
  static PendingLogout? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final token = raw['refreshToken'];
    final at = DateTime.tryParse(raw['loggedOutAt'] as String? ?? '');
    if (token is! String || token.isEmpty || at == null) return null;
    return PendingLogout(refreshToken: token, loggedOutAt: at);
  }
}

/// Queue of [PendingLogout]s, oldest first.
abstract class PendingLogoutStore {
  Future<List<PendingLogout>> read();
  Future<void> write(List<PendingLogout> pending);
}

/// Hive-backed [PendingLogoutStore] in its own `pending_logout` box, kept
/// apart from the session box that logout wipes. Best-effort: a storage
/// failure never blocks signing out, it only loses the later server sync.
class HivePendingLogoutStore implements PendingLogoutStore {
  HivePendingLogoutStore._();
  static final instance = HivePendingLogoutStore._();

  static const boxName = 'pending_logout';
  static const _key = 'queue';

  /// At most this many queued sign-outs are kept (the newest).
  static const maxEntries = 20;

  static Future<void> init() async {
    try {
      await Hive.openBox<dynamic>(boxName);
    } catch (_) {
      await Hive.deleteBoxFromDisk(boxName);
      await Hive.openBox<dynamic>(boxName);
    }
  }

  @override
  Future<List<PendingLogout>> read() async {
    try {
      final raw = Hive.box<dynamic>(boxName).get(_key);
      if (raw is! List) return [];
      return [for (final e in raw) ?PendingLogout.fromMap(e)];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> write(List<PendingLogout> pending) async {
    try {
      final box = Hive.box<dynamic>(boxName);
      if (pending.isEmpty) {
        await box.delete(_key);
        return;
      }
      final kept = pending.length > maxEntries
          ? pending.sublist(pending.length - maxEntries)
          : pending;
      await box.put(_key, [for (final p in kept) p.toMap()]);
    } catch (_) {}
  }
}

/// In-memory store for tests and previews.
class MemoryPendingLogoutStore implements PendingLogoutStore {
  MemoryPendingLogoutStore([List<PendingLogout>? initial])
    : _pending = [...?initial];
  List<PendingLogout> _pending;

  @override
  Future<List<PendingLogout>> read() async => [..._pending];

  @override
  Future<void> write(List<PendingLogout> pending) async =>
      _pending = [...pending];
}
