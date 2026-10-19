import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/network_status.dart';
import 'package:carservice_business/core/services/pending_logout_store.dart';
import 'package:carservice_business/core/services/saved_login_store.dart';
import 'package:carservice_business/features/auth/presentation/controllers/auth_controller.dart';

import '../../support/hive_test_setup.dart';

class _Network implements NetworkStatus {
  bool online = true;
  final _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get changes => _changes.stream;

  void comeBack() {
    online = true;
    _changes.add(true);
  }
}

/// Scripted `auth/logout`: answers [status], or fails like a dead network.
class _Server {
  final calls = <Map<String, dynamic>>[];
  int status = 200;
  bool unreachable = false;

  Future<AuthResponse> call(String path, Map<String, dynamic> body) async {
    expect(path, 'auth/logout');
    calls.add(body);
    if (unreachable) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    return AuthResponse(status, const {'ok': true});
  }
}

User _session(String refreshToken) => User(
  accessToken: 'access',
  refreshToken: refreshToken,
  id: 'user-1',
  email: 'bat@example.mn',
  firstName: 'Бат',
  lastName: 'Болд',
  phone: '99112233',
  isOwner: true,
  tenant: UserTenant('t-1', 'Инфосистемс'),
);

void main() {
  setUpAll(openTestHiveBoxes);

  late _Network network;
  late _Server server;
  late MemoryPendingLogoutStore store;
  late AuthController auth;

  setUp(() {
    network = _Network();
    server = _Server();
    store = MemoryPendingLogoutStore();
    auth = AuthController(
      transport: server.call,
      savedLogins: MemorySavedLoginStore(),
      pendingLogouts: store,
      network: network,
    );
  });

  tearDown(() async {
    auth.dispose();
    await Authenticator.clear();
  });

  test('online: the sign-out is sent at once, nothing is queued', () async {
    Authenticator.user = _session('r1');
    await auth.logout();

    expect(server.calls, hasLength(1));
    expect(server.calls.single['refreshToken'], 'r1');
    expect(
      DateTime.parse(server.calls.single['loggedOutAt'] as String).isUtc,
      isTrue,
    );
    expect(await store.read(), isEmpty);
    expect(Authenticator.user, isNull);
    expect(auth.authState, AuthState.noLogged);
  });

  test('offline: no call; the sign-out and its time are queued', () async {
    network.online = false;
    Authenticator.user = _session('r1');
    final before = DateTime.now();

    await auth.logout();

    expect(server.calls, isEmpty);
    final queued = await store.read();
    expect(queued.single.refreshToken, 'r1');
    expect(queued.single.loggedOutAt.isBefore(before), isFalse);
    // Signing out locally never waits on the network.
    expect(Authenticator.user, isNull);
    expect(auth.authState, AuthState.noLogged);
  });

  test('back online: the queued sign-out goes out with its own time', () async {
    network.online = false;
    Authenticator.user = _session('r1');
    await auth.logout();
    final signedOutAt = (await store.read()).single.loggedOutAt;

    network.comeBack();
    await pumpEventQueue();

    expect(server.calls, hasLength(1));
    expect(server.calls.single['refreshToken'], 'r1');
    expect(
      DateTime.parse(server.calls.single['loggedOutAt'] as String),
      signedOutAt.toUtc(),
    );
    expect(await store.read(), isEmpty);
  });

  test('online but unreachable: queued, then sent on the next sync', () async {
    server.unreachable = true;
    Authenticator.user = _session('r1');
    await auth.logout();
    expect(server.calls, hasLength(1));
    expect(await store.read(), hasLength(1));

    server.unreachable = false;
    await auth.syncPendingLogouts();
    expect(server.calls, hasLength(2));
    expect(await store.read(), isEmpty);
  });

  test('a server error keeps it for later; a rejection drops it', () async {
    store = MemoryPendingLogoutStore([
      PendingLogout(refreshToken: 'r1', loggedOutAt: DateTime.now()),
    ]);
    auth.dispose();
    auth = AuthController(
      transport: server.call,
      savedLogins: MemorySavedLoginStore(),
      pendingLogouts: store,
      network: network,
    );

    server.status = 502;
    await auth.syncPendingLogouts();
    expect(await store.read(), hasLength(1));

    // 400: nothing the server can do with it — retrying won't help.
    server.status = 400;
    await auth.syncPendingLogouts();
    expect(await store.read(), isEmpty);
  });

  test(
    'app start sends what the last session left; stale ones are dropped',
    () async {
      store = MemoryPendingLogoutStore([
        PendingLogout(
          refreshToken: 'old',
          loggedOutAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
        PendingLogout(refreshToken: 'r1', loggedOutAt: DateTime.now()),
      ]);
      auth.dispose();
      auth = AuthController(
        transport: server.call,
        savedLogins: MemorySavedLoginStore(),
        pendingLogouts: store,
        network: network,
      );

      await auth.loadUser();
      await pumpEventQueue();

      expect(server.calls.map((c) => c['refreshToken']), ['r1']);
      expect(await store.read(), isEmpty);
    },
  );

  test('still offline at app start: waits for the network', () async {
    network.online = false;
    store = MemoryPendingLogoutStore([
      PendingLogout(refreshToken: 'r1', loggedOutAt: DateTime.now()),
    ]);
    auth.dispose();
    auth = AuthController(
      transport: server.call,
      savedLogins: MemorySavedLoginStore(),
      pendingLogouts: store,
      network: network,
    );

    await auth.loadUser();
    await pumpEventQueue();
    expect(server.calls, isEmpty);
    expect(await store.read(), hasLength(1));

    network.comeBack();
    await pumpEventQueue();
    expect(server.calls, hasLength(1));
    expect(await store.read(), isEmpty);
  });

  test('stored sign-outs survive a bad entry', () {
    expect(PendingLogout.fromMap('junk'), isNull);
    expect(PendingLogout.fromMap({'refreshToken': 'r1'}), isNull);
    final p = PendingLogout(
      refreshToken: 'r1',
      loggedOutAt: DateTime.utc(2026, 10, 1, 8),
    );
    final back = PendingLogout.fromMap(p.toMap())!;
    expect(back.refreshToken, 'r1');
    expect(back.loggedOutAt, DateTime.utc(2026, 10, 1, 8));
  });
}
