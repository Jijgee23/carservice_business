import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/data/appointment_repository.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';

/// Controller for the Today board's appointments timeline (Phase 4,
/// component part of `TENANT_UI_UX_PLAN.md`).
///
/// Mirrors `TodayOrdersController`'s shape exactly (periodic auto-refresh,
/// `lastUpdated`, a `refreshError` that keeps stale data on screen rather
/// than replacing it with an error view, and a per-row busy set) but is
/// otherwise self-contained: it owns its own `AppointmentsRepository`
/// instance rather than sharing the Orders tab's, the same reasoning
/// `TodayOrdersController`'s doc comment gives for not reusing the Orders
/// tab's shared list controller.
///
/// `arrived` is not part of the server-shaped `AppointmentSummary` (see
/// `appointment.dart`'s doc comment on `AppointmentLifecycleResult` — the
/// arrived route only echoes its own result, never read back from the day
/// list). This controller therefore tracks "arrived today" locally in
/// [_arrivedIds], exactly like `AppointmentDetailController.arrived` does
/// for a single appointment, and clears the set on every reload so a stale
/// local flag can never survive past the appointment's actual server state.
class TodayAppointmentsController extends ChangeNotifier {
  TodayAppointmentsController({
    AppointmentsRepository? repository,
    DateTime Function()? clock,
    this._autoRefresh = const Duration(minutes: 1),
  }) : _repo = repository ?? RemoteAppointmentsRepository(),
       _clock = clock ?? DateTime.now;

  /// The list endpoint's page cap; a single branch rarely has more
  /// appointments than this in one day.
  static const int pageSize = 200;

  final AppointmentsRepository _repo;
  final DateTime Function() _clock;
  final Duration? _autoRefresh;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  AsyncValue<List<AppointmentSummary>> state = const AsyncLoading();

  /// Set when a background refresh fails while older data is still shown.
  AppError? refreshError;
  DateTime? lastUpdated;
  bool refreshing = false;
  bool truncated = false;

  final Set<String> _busy = <String>{};
  final Set<String> _arrivedIds = <String>{};

  /// Exposed for tests / callers that need the same repository instance
  /// (e.g. to build a `CreateOrderScreen` off the same auth/session).
  AppointmentsRepository get repository => _repo;

  DateTime now() => _clock();
  bool isBusy(String appointmentId) => _busy.contains(appointmentId);

  /// Whether [appointmentId] has been marked arrived locally since the last
  /// reload. Never a substitute for server truth — see the class doc.
  bool isArrived(String appointmentId) => _arrivedIds.contains(appointmentId);

  /// First load; also starts the periodic refresh that keeps a shared
  /// front-desk tablet from going stale, matching `TodayOrdersController`.
  Future<void> start() async {
    await load();
    final every = _autoRefresh;
    if (every != null && !_disposed) {
      _timer ??= Timer.periodic(every, (_) => load());
    }
  }

  Future<void> load() async {
    final generation = ++_generation;
    refreshing = true;
    _notify();
    final today = _dateOnly(_clock());
    final result = await _repo.getAppointments(
      query: AppointmentListQuery(date: today, pageSize: pageSize),
    );
    if (_disposed || generation != _generation) return;
    refreshing = false;
    switch (result) {
      case Ok(:final value):
        state = AsyncData(_sorted(value.items));
        truncated = value.pagination.total > value.items.length;
        refreshError = null;
        lastUpdated = _clock();
        // A fresh page reflects the server's current arrived state (none of
        // it, since the field isn't served) — clearing here means a local
        // "arrived" flag never outlives the load that should have superseded
        // it.
        _arrivedIds.clear();
      case Err(:final error):
        if (state is AsyncData<List<AppointmentSummary>>) {
          refreshError = error;
        } else {
          state = AsyncError(error);
        }
    }
    _notify();
  }

  Future<void> refresh() => load();

  /// `POST /appointments/[id]/arrived`. On success the appointment is
  /// marked arrived locally (see class doc) so the timeline can offer
  /// "Засварын хуудас үүсгэх" immediately, without waiting for the next poll.
  Future<AppError?> markArrived(String appointmentId) async {
    if (_busy.contains(appointmentId)) return null;
    _busy.add(appointmentId);
    _notify();
    final result = await _repo.markArrived(appointmentId);
    if (_disposed) return null;
    _busy.remove(appointmentId);
    switch (result) {
      case Ok(:final value):
        _arrivedIds.add(appointmentId);
        if (value.arrived == false) _arrivedIds.remove(appointmentId);
        _notify();
        return null;
      case Err(:final error):
        _notify();
        return error;
    }
  }

  /// Booked time (earliest first); appointments with no `requestedAt` sort
  /// last, matching `TodayOrdersController._waitingKey`'s "unknown time
  /// last" convention.
  List<AppointmentSummary> _sorted(List<AppointmentSummary> items) {
    final sorted = [...items]..sort((a, b) => _key(a).compareTo(_key(b)));
    return sorted;
  }

  static DateTime _key(AppointmentSummary a) =>
      a.requestedAt ?? DateTime(9999);

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
