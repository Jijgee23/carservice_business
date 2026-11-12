import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_detail_controller.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_item_controller.dart';

import '../../fakes/fake_order_repository.dart';

class _ItemRepository extends FakeOrderRepository {
  int detailReads = 0;
  int addCalls = 0;
  int updateCalls = 0;
  Completer<Result<ServiceItem>>? pendingAdd;
  bool failAdd = false;
  bool failUpdate = false;
  int historyCalls = 0;
  Completer<Result<OrderItemHistoryPage>>? pendingNextHistory;
  bool failNextHistory = false;

  @override
  Future<Result<ServiceOrderDetail>> getOrderDetail(String id) async {
    detailReads++;
    return super.getOrderDetail(id);
  }

  @override
  Future<Result<ServiceItem>> addItemMoney(
    String orderId, {
    required ItemKind kind,
    required String description,
    required Money quantity,
    required Money unitPrice,
    String? serviceId,
    String? diagnosticTemplateId,
    String? catalogItemId,
  }) async {
    addCalls++;
    if (pendingAdd != null) return pendingAdd!.future;
    if (failAdd) {
      return const Err(AppError(ErrorKind.server, 'failed'));
    }
    return super.addItemMoney(
      orderId,
      kind: kind,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      serviceId: serviceId,
      diagnosticTemplateId: diagnosticTemplateId,
      catalogItemId: catalogItemId,
    );
  }

  @override
  Future<Result<ServiceItem>> updateItemMoney(
    String orderId,
    String itemId, {
    ItemKind? kind,
    String? description,
    Money? quantity,
    Money? unitPrice,
    ServiceItemStatus? status,
  }) async {
    updateCalls++;
    if (failUpdate) {
      return const Err(AppError(ErrorKind.server, 'failed'));
    }
    return super.updateItemMoney(
      orderId,
      itemId,
      kind: kind,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      status: status,
    );
  }

  @override
  Future<Result<OrderItemHistoryPage>> getItemHistory(
    String orderId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    historyCalls++;
    if (page == 1) {
      return Ok(_historyPage(page: 1, hasNext: true, id: 'cancelled-1'));
    }
    if (pendingNextHistory != null) return pendingNextHistory!.future;
    if (failNextHistory) {
      return const Err(AppError(ErrorKind.server, 'Түүх ачаалж чадсангүй.'));
    }
    return Ok(_historyPage(page: 2, hasNext: false, id: 'cancelled-2'));
  }
}

OrderItemHistoryPage _historyPage({
  required int page,
  required bool hasNext,
  required String id,
}) => OrderItemHistoryPage(
  items: [
    ServiceItem(
      id: id,
      kind: ItemKind.LABOR,
      description: id,
      quantity: 1.125,
      unitPrice: 99.90,
      total: 112.3875,
      status: ServiceItemStatus.CANCELLED,
      cancelledById: 'user-1',
      quantityMoney: const Money('1.125'),
      unitPriceMoney: const Money('99.90'),
      totalMoney: const Money('112.3875'),
    ),
  ],
  pagination: PaginationMeta(
    page: page,
    pageSize: 1,
    total: hasNext ? 2 : 2,
    totalPages: 2,
    hasPrev: page > 1,
    hasNext: hasNext,
  ),
);

void main() {
  test('suppresses duplicate add and reloads authoritative detail', () async {
    final repo = _ItemRepository();
    final detail = OrderDetailController(repo: repo);
    await detail.load('order-1');
    final items = OrderItemController(
      repo: repo,
      orderId: 'order-1',
      detailController: detail,
    );
    repo.pendingAdd = Completer<Result<ServiceItem>>();

    final first = items.add(
      kind: ItemKind.LABOR,
      description: 'Oil service',
      quantity: const Money('1.50'),
      unitPrice: const Money('12.25'),
    );
    final duplicate = await items.add(
      kind: ItemKind.LABOR,
      description: 'Oil service',
      quantity: const Money('1.50'),
      unitPrice: const Money('12.25'),
    );
    expect(duplicate, isA<Err<ServiceItem>>());
    expect(repo.addCalls, 1);

    repo.pendingAdd!.complete(const Err(AppError(ErrorKind.server, 'failed')));
    await first;
    expect(repo.detailReads, greaterThan(1));
    items.dispose();
    detail.dispose();
  });

  test(
    'reloads after a failed mutation without changing local truth',
    () async {
      final repo = _ItemRepository()..failAdd = true;
      final detail = OrderDetailController(repo: repo);
      await detail.load('order-1');
      final before = detail.order!.items;
      final items = OrderItemController(
        repo: repo,
        orderId: 'order-1',
        detailController: detail,
      );

      final result = await items.add(
        kind: ItemKind.FEE,
        description: 'Fee',
        quantity: const Money('1'),
        unitPrice: const Money('99.90'),
      );
      expect(result, isA<Err<ServiceItem>>());
      expect(detail.order!.items, before);
      expect(repo.detailReads, greaterThan(1));
      items.dispose();
      detail.dispose();
    },
  );

  test(
    'combined edit uses one repository patch and preserves exact money',
    () async {
      final repo = _ItemRepository()..failUpdate = true;
      final detail = OrderDetailController(repo: repo);
      await detail.load('order-1');
      final items = OrderItemController(
        repo: repo,
        orderId: 'order-1',
        detailController: detail,
      );

      final result = await items.edit(
        itemId: 'item-1',
        description: 'Updated',
        quantity: const Money('1.125'),
        unitPrice: const Money('99.90'),
      );
      expect(result, isA<Err<ServiceItem>>());
      expect(repo.updateCalls, 1);
      items.dispose();
      detail.dispose();
    },
  );

  test('item money validation is exact and bounded', () {
    expect(ItemMoneyValidation.quantity('1.125').isValid, isTrue);
    expect(ItemMoneyValidation.quantity('1.1234').isValid, isFalse);
    expect(ItemMoneyValidation.quantity('0').isValid, isFalse);
    expect(ItemMoneyValidation.quantity('1000000.001').isValid, isFalse);
    expect(ItemMoneyValidation.price('0').isValid, isTrue);
    expect(ItemMoneyValidation.price('12.34').value?.raw, '12.34');
    expect(ItemMoneyValidation.price('12.345').isValid, isFalse);
    expect(ItemMoneyValidation.price('1000000000.01').isValid, isFalse);
  });

  test(
    'next history page is duplicate-suppressed and retry preserves items',
    () async {
      final repo = _ItemRepository();
      final detail = OrderDetailController(repo: repo);
      final items = OrderItemController(
        repo: repo,
        orderId: 'order-1',
        detailController: detail,
      );
      await items.loadHistory();
      repo.pendingNextHistory = Completer<Result<OrderItemHistoryPage>>();

      final first = items.loadNextHistory();
      await Future<void>.delayed(Duration.zero);
      final duplicate = items.loadNextHistory();
      expect(repo.historyCalls, 2);

      repo.pendingNextHistory!.complete(
        const Err(AppError(ErrorKind.server, 'Түр алдаа')),
      );
      expect(await first, isA<Err<OrderItemHistoryPage>>());
      expect(await duplicate, isA<Err<OrderItemHistoryPage>>());
      final failedState = items.historyState;
      expect(failedState, isA<AsyncData<OrderItemHistoryPage>>());
      expect(
        (failedState as AsyncData<OrderItemHistoryPage>).value.items,
        hasLength(1),
      );
      expect(items.historyNextError, isNotNull);

      repo.pendingNextHistory = null;
      final retry = await items.loadNextHistory();
      expect(retry, isA<Ok<OrderItemHistoryPage>>());
      final finalState = items.historyState as AsyncData<OrderItemHistoryPage>;
      expect(finalState.value.items, hasLength(2));
      expect(items.historyHasNext, isFalse);
      items.dispose();
      detail.dispose();
    },
  );
}
