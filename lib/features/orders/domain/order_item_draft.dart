import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';

/// A line staged while the order is being created: picked from the catalog
/// ([serviceId] / [diagnosticTemplateId] / shared [catalogItemId]) or entered
/// by hand. The server's create request takes no lines, so they go in through
/// `POST /orders/{id}/items` once the order exists ([addOrderItemDrafts]).
class OrderItemDraft {
  const OrderItemDraft({
    required this.kind,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.serviceId,
    this.diagnosticTemplateId,
    this.catalogItemId,
  });

  final ItemKind kind;
  final String description;
  final Money quantity;
  final Money unitPrice;
  final String? serviceId;
  final String? diagnosticTemplateId;

  /// Нэгдсэн сангийн мөр — the server links it as the tenant's service.
  final String? catalogItemId;

  bool get fromCatalog =>
      serviceId != null ||
      diagnosticTemplateId != null ||
      catalogItemId != null;

  /// Preview only: the server computes and rounds the real line total.
  double get total => quantity.asDouble * unitPrice.asDouble;
}

/// Outcome of [addOrderItemDrafts]: how many lines the server refused and the
/// first refusal to show.
typedef DraftItemsResult = ({int failed, AppError? firstError});

/// Adds [drafts] to the just-created order one request at a time, in the
/// order they were staged. A refused line doesn't stop the rest.
Future<DraftItemsResult> addOrderItemDrafts(
  OrdersRepository repo,
  String orderId,
  List<OrderItemDraft> drafts,
) async {
  var failed = 0;
  AppError? firstError;
  for (final d in drafts) {
    final result = await repo.addItemMoney(
      orderId,
      kind: d.kind,
      description: d.description,
      quantity: d.quantity,
      unitPrice: d.unitPrice,
      serviceId: d.serviceId,
      diagnosticTemplateId: d.diagnosticTemplateId,
      catalogItemId: d.catalogItemId,
    );
    if (result case Err(:final error)) {
      failed++;
      firstError ??= error;
    }
  }
  return (failed: failed, firstError: firstError);
}
