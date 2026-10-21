import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_detail_controller.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_list_controller.dart';

class ItemMoneyValidation {
  const ItemMoneyValidation._(this.value, this.error);

  final Money? value;
  final String? error;

  bool get isValid => value != null;

  static ItemMoneyValidation quantity(String input) => _parse(
    input,
    maxScale: 3,
    maximum: BigInt.from(1000000),
    minimumExclusive: true,
    label: 'Тоо',
  );

  static ItemMoneyValidation price(String input) => _parse(
    input,
    maxScale: 2,
    maximum: BigInt.from(1000000000),
    minimumExclusive: false,
    label: 'Нэгж үнэ',
  );

  static ItemMoneyValidation _parse(
    String input, {
    required int maxScale,
    required BigInt maximum,
    required bool minimumExclusive,
    required String label,
  }) {
    final raw = input.trim().replaceAll(',', '');
    if (!RegExp(r'^(?:0|[1-9]\d*)(?:\.\d+)?$').hasMatch(raw)) {
      return ItemMoneyValidation._(
        null,
        '$label нь зөв аравтын тоо байх ёстой.',
      );
    }
    final parts = raw.split('.');
    final fraction = parts.length == 1 ? '' : parts[1];
    if (fraction.length > maxScale) {
      return ItemMoneyValidation._(
        null,
        '$label нь таслалаас хойш $maxScale оронтой байна.',
      );
    }
    final scale = fraction.length;
    final multiplier = BigInt.from(10).pow(scale);
    final integer =
        BigInt.parse(parts[0]) * multiplier +
        BigInt.parse(fraction.isEmpty ? '0' : fraction);
    final max = maximum * multiplier;
    if (integer > max || (minimumExclusive && integer == BigInt.zero)) {
      return ItemMoneyValidation._(
        null,
        minimumExclusive
            ? '$label нь 0-ээс их, 1,000,000-аас ихгүй байна.'
            : '$label нь 0-ээс багагүй, 1,000,000,000-аас ихгүй байна.',
      );
    }
    return ItemMoneyValidation._(Money(raw), null);
  }
}

/// Outcome of [OrderItemController.completeAll]: how many lines the server
/// completed, how many it refused, and the first refusal to show.
typedef BulkStatusResult = ({int done, int failed, AppError? firstError});

const _alreadyRunning = AppError(
  ErrorKind.unknown,
  'Энэ үйлдэл аль хэдийн хийгдэж байна.',
);

/// Marks [itemIds] COMPLETED one request at a time (each is its own order
/// transaction on the server). A line the server refuses does not stop the
/// rest; [stop] ends the run early, e.g. once the screen is gone.
Future<BulkStatusResult> completeItems(
  OrdersRepository repo,
  String orderId,
  List<String> itemIds, {
  bool Function()? stop,
}) async {
  var done = 0;
  var failed = 0;
  AppError? firstError;
  for (final id in itemIds) {
    if (stop?.call() ?? false) break;
    final result = await _attempt(
      () => repo.changeItemStatus(orderId, id, ServiceItemStatus.COMPLETED),
    );
    if (result case Err(:final error)) {
      failed++;
      firstError ??= error;
    } else {
      done++;
    }
  }
  return (done: done, failed: failed, firstError: firstError);
}

/// Runs [action], turning a thrown error into an [Err].
Future<Result<T>> _attempt<T>(Future<Result<T>> Function() action) async {
  try {
    return await action();
  } catch (error) {
    return Err(
      error is AppError
          ? error
          : const AppError(ErrorKind.unknown, 'Мөрийн үйлдэл амжилтгүй.'),
    );
  }
}

/// Owns item mutations for one order. The server remains the only source of
/// truth: this controller never patches an item into a local detail snapshot.
/// Every completed request, including a failed request, is followed by a
/// detail/list reload so concurrent web changes and validation failures cannot
/// leave stale item state on screen.
class OrderItemController extends ChangeNotifier {
  OrderItemController({
    required this.repo,
    required this.orderId,
    required this.detailController,
    this.listController,
  });

  final OrdersRepository repo;
  final String orderId;
  final OrderDetailController detailController;
  final OrderListController? listController;

  AsyncValue<OrderItemHistoryPage> historyState = const AsyncLoading();
  int historyPage = 0;
  bool historyHasNext = false;
  String? historyNextError;
  int _generation = 0;
  bool _disposed = false;
  final Set<String> _inFlight = <String>{};

  /// Status a line is being moved to while its request and the reload after
  /// it are in flight. The screen shows it in place of the server status so a
  /// tap answers at once. It is dropped after the authoritative reload, so a
  /// refused change falls back to whatever the server says.
  final Map<String, ServiceItemStatus> _pendingStatus = {};
  Future<Result<OrderItemHistoryPage>>? _nextHistoryRequest;

  bool get isLoadingHistory => historyState is AsyncLoading;
  bool get isLoadingNextHistory => _nextHistoryRequest != null;

  ServiceItemStatus? pendingStatusOf(String itemId) => _pendingStatus[itemId];

  bool isStatusBusy(String itemId) => _pendingStatus.containsKey(itemId);

  /// True when the last successful [add] returned a line that already existed
  /// on the order: the server merged the quantity into it instead of creating
  /// a new line.
  bool lastAddMerged = false;

  Future<Result<ServiceItem>> add({
    required ItemKind kind,
    required String description,
    required Money quantity,
    required Money unitPrice,
    String? serviceId,
    String? diagnosticTemplateId,
  }) {
    final existingIds = {
      for (final i in detailController.order?.items ?? const <ServiceItem>[])
        i.id,
    };
    lastAddMerged = false;
    return _runItem('add', () async {
      final result = await repo.addItemMoney(
        orderId,
        kind: kind,
        description: description,
        quantity: quantity,
        unitPrice: unitPrice,
        serviceId: serviceId,
        diagnosticTemplateId: diagnosticTemplateId,
      );
      if (result case Ok(:final value)) {
        lastAddMerged = existingIds.contains(value.id);
      }
      return result;
    });
  }

  Future<Result<ServiceItem>> edit({
    required String itemId,
    ItemKind? kind,
    String? description,
    Money? quantity,
    Money? unitPrice,
  }) => _runItem(
    'edit:$itemId',
    () => repo.updateItemMoney(
      orderId,
      itemId,
      kind: kind,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
    ),
  );

  Future<Result<ServiceItem>> changePrice(String itemId, Money unitPrice) =>
      _runItem(
        'price:$itemId',
        () => repo.changeItemPrice(orderId, itemId, unitPrice),
      );

  Future<Result<ServiceItem>> changeStatus(
    String itemId,
    ServiceItemStatus status,
  ) async {
    if (_disposed) return _disposedError<ServiceItem>();
    if (isStatusBusy(itemId)) return const Err(_alreadyRunning);
    _setPending([itemId], status);
    try {
      return await _runItem(
        'status:$itemId',
        () => repo.changeItemStatus(orderId, itemId, status),
      );
    } finally {
      _clearPending([itemId]);
    }
  }

  /// Marks every line in [itemIds] COMPLETED ([completeItems]), then reloads
  /// once. Lines already changing are left to their own request.
  Future<BulkStatusResult> completeAll(List<String> itemIds) async {
    if (_disposed) {
      return (done: 0, failed: 0, firstError: _disposedError<void>().error);
    }
    if (!_inFlight.add('status:bulk')) {
      return (done: 0, failed: 0, firstError: _alreadyRunning);
    }
    final ids = itemIds.where((id) => !isStatusBusy(id)).toList();
    final generation = _generation;
    _setPending(ids, ServiceItemStatus.COMPLETED);
    try {
      final result = await completeItems(
        repo,
        orderId,
        ids,
        stop: () => _disposed,
      );
      await _reloadAuthoritative(generation);
      return result;
    } finally {
      _inFlight.remove('status:bulk');
      _clearPending(ids);
    }
  }

  Future<Result<void>> cancel(String itemId) =>
      _runVoid('cancel:$itemId', () => repo.cancelItem(orderId, itemId));

  Future<Result<OrderItemHistoryPage>> loadHistory({
    int page = 1,
    int pageSize = 20,
  }) async {
    if (_disposed) return _disposedError<OrderItemHistoryPage>();
    final generation = ++_generation;
    historyState = const AsyncLoading();
    historyNextError = null;
    notifyListeners();
    final result = await repo.getItemHistory(
      orderId,
      page: page,
      pageSize: pageSize,
    );
    if (_disposed || generation != _generation) return result;
    historyState = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => AsyncError(error),
    };
    if (result case Ok(:final value)) {
      historyPage = value.pagination.page;
      historyHasNext = value.pagination.hasNext;
    } else {
      historyPage = page;
      historyHasNext = false;
    }
    notifyListeners();
    return result;
  }

  Future<Result<OrderItemHistoryPage>> loadNextHistory() async {
    final pending = _nextHistoryRequest;
    if (pending != null) return pending;
    if (!historyHasNext || historyState is! AsyncData<OrderItemHistoryPage>) {
      return historyState is AsyncData<OrderItemHistoryPage>
          ? Ok((historyState as AsyncData<OrderItemHistoryPage>).value)
          : _disposedError<OrderItemHistoryPage>();
    }
    final request = _loadNextHistoryPage();
    _nextHistoryRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_nextHistoryRequest, request)) {
        _nextHistoryRequest = null;
      }
    }
  }

  Future<Result<OrderItemHistoryPage>> _loadNextHistoryPage() async {
    final generation = ++_generation;
    final current = (historyState as AsyncData<OrderItemHistoryPage>).value;
    final result = await repo.getItemHistory(
      orderId,
      page: historyPage + 1,
      pageSize: current.pagination.pageSize,
    );
    if (_disposed || generation != _generation) return result;
    switch (result) {
      case Ok(:final value):
        final combined = OrderItemHistoryPage(
          items: [...current.items, ...value.items],
          pagination: value.pagination,
        );
        historyState = AsyncData(combined);
        historyPage = value.pagination.page;
        historyHasNext = value.pagination.hasNext;
        historyNextError = null;
      case Err(:final error):
        // Keep the accumulated page visible. The sheet renders this message
        // beside a retry action instead of replacing it with AsyncError.
        historyNextError = error.display;
    }
    notifyListeners();
    return result;
  }

  Future<Result<T>> _runItem<T>(
    String key,
    Future<Result<T>> Function() action,
  ) async {
    if (_disposed) return _disposedError<T>();
    if (!_inFlight.add(key)) return const Err(_alreadyRunning);
    final generation = _generation;
    try {
      final result = await _attempt(action);
      await _reloadAuthoritative(generation);
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<Result<void>> _runVoid(
    String key,
    Future<Result<void>> Function() action,
  ) => _runItem<void>(key, action);

  void _setPending(Iterable<String> ids, ServiceItemStatus status) {
    for (final id in ids) {
      _pendingStatus[id] = status;
    }
    notifyListeners();
  }

  void _clearPending(Iterable<String> ids) {
    if (_disposed) return;
    for (final id in ids) {
      _pendingStatus.remove(id);
    }
    notifyListeners();
  }

  Future<void> _reloadAuthoritative(int generation) async {
    if (_disposed || generation != _generation) return;
    await detailController.refresh();
    if (_disposed || generation != _generation) return;
    await listController?.refresh();
  }

  Err<T> _disposedError<T>() =>
      const Err(AppError(ErrorKind.unknown, 'Энэ дэлгэц хаагдсан байна.'));

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _inFlight.clear();
    _pendingStatus.clear();
    super.dispose();
  }
}
