import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_item_controller.dart';

/// The three lanes of the Today board.
enum TodayLane {
  waiting('Хүлээгдэж буй'),
  inProgress('Хийгдэж буй'),
  completed('Өнөөдөр дууссан');

  const TodayLane(this.label);
  final String label;
}

/// A snapshot of the work queue for one local day.
///
/// Built from status queries rather than the list endpoint's `dateFrom` /
/// `dateTo`, because that filter applies to `scheduledAt` and walk-in orders
/// have none — a date-filtered query would silently hide them.
/// - [waiting]: every SCHEDULED order due today or earlier, plus walk-ins.
/// - [inProgress]: every IN_PROGRESS order, regardless of start day.
/// - [completed]: COMPLETED orders whose `completedAt` is today, taken from
///   the newest-created page; see [completedMayBeIncomplete].
class TodayBoard {
  const TodayBoard({
    required this.waiting,
    required this.inProgress,
    required this.completed,
    this.laterCount = 0,
    this.truncated = false,
    this.completedMayBeIncomplete = false,
  });

  final List<ServiceOrderSummary> waiting;
  final List<ServiceOrderSummary> inProgress;
  final List<ServiceOrderSummary> completed;

  /// SCHEDULED orders booked for a later day (not shown on the board).
  final int laterCount;

  /// True when a waiting/in-progress query had more rows than one page.
  final bool truncated;

  /// The list endpoint orders by `createdAt`, so an order created long ago
  /// and completed today can fall outside the fetched page.
  final bool completedMayBeIncomplete;

  List<ServiceOrderSummary> lane(TodayLane lane) => switch (lane) {
    TodayLane.waiting => waiting,
    TodayLane.inProgress => inProgress,
    TodayLane.completed => completed,
  };
}

class TodayOrdersController extends ChangeNotifier {
  TodayOrdersController({
    required OrdersRepository repository,
    DateTime Function()? clock,
    this._autoRefresh = const Duration(minutes: 1),
  }) : _repo = repository,
       _clock = clock ?? DateTime.now;

  /// Fetch every open-order page so the board's working lanes are complete.
  /// Completed orders retain a one-page preview because the API sorts by
  /// creation time, not completion time; the UI warns when that preview may
  /// be incomplete.
  static const int pageSize = 100;

  final OrdersRepository _repo;
  final DateTime Function() _clock;
  final Duration? _autoRefresh;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  AsyncValue<TodayBoard> state = const AsyncLoading();

  /// Set when a background refresh fails while older data is still shown.
  AppError? refreshError;
  DateTime? lastUpdated;
  bool refreshing = false;
  final Set<String> _busy = <String>{};

  DateTime now() => _clock();
  bool isBusy(String orderId) => _busy.contains(orderId);

  /// The board's repository, for screens opened from a card.
  OrdersRepository get repository => _repo;

  /// First load; also starts the periodic refresh that keeps a shared
  /// front-desk tablet from going stale.
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
    final results = await Future.wait([
      _fetch(OrderStatus.SCHEDULED),
      _fetch(OrderStatus.IN_PROGRESS),
      _fetch(OrderStatus.COMPLETED),
    ]);
    if (_disposed || generation != _generation) return;
    refreshing = false;
    final error = results
        .whereType<Err<PagedResult<ServiceOrderSummary>>>()
        .map((e) => e.error)
        .firstOrNull;
    if (error != null) {
      if (state is AsyncData<TodayBoard>) {
        refreshError = error;
      } else {
        state = AsyncError(error);
      }
      _notify();
      return;
    }
    final pages = [
      for (final r in results)
        (r as Ok<PagedResult<ServiceOrderSummary>>).value,
    ];
    state = AsyncData(_build(pages[0], pages[1], pages[2]));
    refreshError = null;
    lastUpdated = _clock();
    _notify();
  }

  /// Sends a status transition and reloads the board. Returns the error to
  /// show, or `null` on success.
  Future<AppError?> changeStatus(
    ServiceOrderSummary order,
    OrderStatus status, {
    int? durationMinutes,
  }) async {
    if (_busy.contains(order.id)) return null;
    _busy.add(order.id);
    _notify();
    final result = await _repo.updateStatus(
      order.id,
      status,
      durationMinutes: durationMinutes,
    );
    if (_disposed) return null;
    _busy.remove(order.id);
    switch (result) {
      case Ok():
        await load();
        return null;
      case Err(:final error):
        _notify();
        return error;
    }
  }

  /// The order's full detail (its work lines), for a card action. The card
  /// shows busy while it loads.
  Future<Result<ServiceOrderDetail>> detail(String orderId) async {
    _busy.add(orderId);
    _notify();
    final result = await _repo.getOrderDetail(orderId);
    if (_disposed) return result;
    _busy.remove(orderId);
    _notify();
    return result;
  }

  /// Marks the order's [itemIds] COMPLETED, one request at a time. Once any
  /// line moved the board reloads, so its progress is the server's.
  Future<BulkStatusResult> completeLines(
    ServiceOrderSummary order,
    List<String> itemIds,
  ) async {
    if (_busy.contains(order.id)) {
      return (done: 0, failed: 0, firstError: null);
    }
    _busy.add(order.id);
    _notify();
    final result = await completeItems(
      _repo,
      order.id,
      itemIds,
      stop: () => _disposed,
    );
    if (_disposed) return result;
    _busy.remove(order.id);
    if (result.done > 0) {
      await load();
    } else {
      _notify();
    }
    return result;
  }

  Future<Result<PagedResult<ServiceOrderSummary>>> _fetch(
    OrderStatus status,
  ) async {
    final items = <ServiceOrderSummary>[];
    var page = 1;
    while (true) {
      final query = OrderListQuery(
        status: status,
        page: page,
        pageSize: pageSize,
      );
      final result = await _repo.getOrders(
        query: query,
        status: status,
        page: page,
        pageSize: pageSize,
      );
      switch (result) {
        case Err():
          return result;
        case Ok(:final value):
          items.addAll(value.items);
          if (status == OrderStatus.COMPLETED) return result;
          if (!value.pagination.hasNext ||
              value.items.isEmpty ||
              page >= value.pagination.totalPages) {
            return Ok(
              PagedResult(
                items: items,
                pagination: PaginationMeta(
                  page: page,
                  pageSize: pageSize,
                  total: value.pagination.total,
                  totalPages: page,
                  hasPrev: page > 1,
                  hasNext: false,
                ),
              ),
            );
          }
      }
      page++;
    }
  }

  TodayBoard _build(
    PagedResult<ServiceOrderSummary> scheduled,
    PagedResult<ServiceOrderSummary> active,
    PagedResult<ServiceOrderSummary> done,
  ) {
    final now = _clock();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final waiting = <ServiceOrderSummary>[];
    var later = 0;
    for (final order in scheduled.items) {
      final at = order.scheduledAt?.toLocal();
      if (at != null && !at.isBefore(dayEnd)) {
        later++;
      } else {
        waiting.add(order);
      }
    }
    // Booked orders by time (overdue first); walk-ins by arrival.
    waiting.sort((a, b) => _waitingKey(a).compareTo(_waitingKey(b)));

    final inProgress = [...active.items]
      ..sort((a, b) {
        final ae = a.expectedFinishAt, be = b.expectedFinishAt;
        if (ae == null && be == null) return a.createdAt.compareTo(b.createdAt);
        if (ae == null) return 1;
        if (be == null) return -1;
        return ae.compareTo(be);
      });

    final completed = done.items.where((o) {
      final at = o.completedAt?.toLocal();
      return at != null && !at.isBefore(dayStart) && at.isBefore(dayEnd);
    }).toList()..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));

    return TodayBoard(
      waiting: waiting,
      inProgress: inProgress,
      completed: completed,
      laterCount: later,
      truncated:
          scheduled.pagination.total > scheduled.items.length ||
          active.pagination.total > active.items.length,
      completedMayBeIncomplete: done.pagination.total > done.items.length,
    );
  }

  static DateTime _waitingKey(ServiceOrderSummary o) =>
      o.scheduledAt ?? o.createdAt;

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
