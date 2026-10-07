import 'package:flutter/material.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/org_badge.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_detail_controller.dart';
import 'package:carservice_business/features/customers/presentation/widgets/customer_edit_sheet.dart';
import 'package:carservice_business/features/customers/presentation/widgets/customer_list_widgets.dart';
import 'package:carservice_business/features/vehicles/presentation/screens/vehicle_detail_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/controllers/new_inspection_controller.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/new_inspection_screen.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Customer detail rebuild — P3-F4.
///
/// Fetches by id (constructed with only [customerId], never a pre-loaded
/// summary) so a cold deep-link start — the screen given nothing but an id —
/// works exactly like any other navigation into it. Shows the server's own
/// `vehicles[]` from `GET /customers/[id]` and the customer's paginated
/// order history from `GET /customers/[id]/history`, replacing the legacy
/// screen's client-side de-duplication of diagnostic reports into a fake
/// vehicle list.
///
/// Edit and delete are gated on `customers.edit` / `customers.delete`
/// through the shared [PermissionGate] / [User] model — no second
/// permission mechanism. A hidden/disabled action is a UX hint only; the
/// server remains authoritative and a rejection is always shown verbatim.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    this.repo,
    this.user,
  });

  final String customerId;
  final CustomersRepository? repo;
  final User? user;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late final CustomerDetailController _controller;

  User? get _user => widget.user ?? Authenticator.user;

  @override
  void initState() {
    super.initState();
    _controller = CustomerDetailController(
      customerId: widget.customerId,
      repo: widget.repo,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CustomerDetailController>.value(
      value: _controller,
      child: _CustomerDetailBody(user: _user),
    );
  }
}

class _CustomerDetailBody extends StatelessWidget {
  const _CustomerDetailBody({required this.user});

  final User? user;

  Future<void> _edit(
    BuildContext context,
    CustomerDetailController ctrl,
  ) async {
    final customer = ctrl.customer;
    if (customer == null) return;
    final saved = await CustomerEditSheet.show(
      context,
      customer: customer,
      controller: ctrl,
    );
    if (saved && context.mounted) {
      messageComplete('Мэдээлэл шинэчлэгдлээ');
    } else if (context.mounted && ctrl.lastError != null) {
      final failure = CustomerFailure.classify(
        statusCode: ctrl.lastError!.statusCode,
        code: ctrl.lastError!.code,
        fieldErrors: ctrl.lastError!.fieldErrors,
      );
      if (failure != CustomerFailure.validation &&
          failure != CustomerFailure.phoneConflict) {
        messageError(ctrl.lastError!.display);
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    CustomerDetailController ctrl,
  ) async {
    final customer = ctrl.customer;
    if (customer == null) return;
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Үйлчлүүлэгч устгах уу?',
      message: '${customer.displayName}-г устгахдаа итгэлтэй байна уу?',
      confirmLabel: 'Устгах',
      icon: Icons.delete_forever_rounded,
      isDangerous: true,
    );
    if (!confirmed) return;
    final result = await ctrl.delete();
    if (!context.mounted) return;
    switch (result) {
      case Ok():
        messageComplete('Үйлчлүүлэгч устгагдлаа');
        AppNav.back();
      case Err(:final error):
        final failure = CustomerFailure.classify(
          statusCode: error.statusCode,
          code: error.code,
          fieldErrors: error.fieldErrors,
        );
        if (failure == CustomerFailure.inUse) {
          // Real explanation, not a generic failure — this customer has
          // service orders and the server refuses the delete for exactly
          // that reason.
          await _showInUseExplanation(context);
        } else {
          messageError(error.display);
        }
    }
  }

  Future<void> _showInUseExplanation(BuildContext context) {
    return AppNav.dialog<void>(
      AlertDialog(
        icon: const Icon(Icons.info_outline_rounded),
        title: const Text('Устгах боломжгүй'),
        content: const Text(
          'Энэ үйлчлүүлэгчтэй холбоотой засварын хуудас байгаа тул устгах '
          'боломжгүй. Эхлээд холбогдох захиалгуудыг цуцлах эсвэл өөр '
          'үйлчлүүлэгч рүү шилжүүлнэ үү.',
        ),
        actions: [
          TextButton(
            onPressed: () => AppNav.back(),
            child: const Text('Ойлголоо'),
          ),
        ],
      ),
    );
  }

  /// Restored for DM-01 parity with the legacy screen. Pushes a bare
  /// `NewInspectionController`, exactly as the legacy action did.
  void _startInspection(BuildContext context) {
    AppNav.to(
      ChangeNotifierProvider(
        create: (_) => NewInspectionController(),
        child: const NewInspectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerDetailController>();
    final canEdit = canSeeView(user, 'customers.edit');
    final canDelete = canSeeView(user, 'customers.delete');
    return Scaffold(
      appBar: AppBar(
        title: Text(ctrl.customer?.displayName ?? 'Үйлчлүүлэгч'),
        actions: [
          // Parity with the legacy screen (DM-01): staff had a "new
          // inspection" shortcut here and the rebuild must not silently drop
          // it. Note it carries no customer context — the legacy action also
          // pushed a bare `NewInspectionController`, so the customer whose
          // page this is was never prefilled. Preserved as-is rather than
          // improved; prefilling is a separate change with its own decision.
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Шинэ оношилгоо',
            onPressed: () => _startInspection(context),
          ),
          PermissionGate(
            permission: 'customers.edit',
            user: user,
            child: IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Засах',
              onPressed: canEdit && ctrl.customer != null
                  ? () => _edit(context, ctrl)
                  : null,
            ),
          ),
          PermissionGate(
            permission: 'customers.delete',
            user: user,
            child: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Устгах',
              onPressed: canDelete && ctrl.customer != null && !ctrl.mutating
                  ? () => _delete(context, ctrl)
                  : null,
            ),
          ),
        ],
      ),
      body: AsyncStateView<CustomerDetail>(
        state: ctrl.detailState,
        onRetry: ctrl.refresh,
        builder: (context, detail) => RefreshIndicator(
          onRefresh: ctrl.refresh,
          child: ListView(
            padding: EdgeInsets.all(AppDimens.paddingMD),
            children: [
              _CustomerHeaderCard(customer: detail.customer),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Машин',
                      count: ctrl.vehicles.length,
                      icon: Icons.directions_car_outlined,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Захиалга',
                      count: ctrl.historyTotal,
                      icon: Icons.receipt_long_outlined,
                      color: context.colors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Машинууд', style: context.textStyles.h3),
              const SizedBox(height: 10),
              if (ctrl.vehicles.isEmpty)
                const EmptyState(
                  message: 'Машин бүртгэгдээгүй',
                  icon: Icons.directions_car_outlined,
                )
              else
                ...ctrl.vehicles.map(
                  (link) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _VehicleRow(link: link),
                  ),
                ),
              const SizedBox(height: 20),
              Text('Захиалгын түүх', style: context.textStyles.h3),
              const SizedBox(height: 10),
              _HistorySection(controller: ctrl),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerHeaderCard extends StatelessWidget {
  const _CustomerHeaderCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final name = customer.displayName;
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: context.colors.accent.withOpacity(0.12),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: context.textStyles.h2.copyWith(
                fontWeight: FontWeight.w800,
                color: context.colors.accent,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: context.textStyles.h3),
                if (customer.isOrganization) ...[
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: OrgBadge(),
                  ),
                  if (customer.orgRegnum != null)
                    _InfoRow(
                      icon: Icons.badge_outlined,
                      text: 'Регистр: ${customer.orgRegnum!}',
                    ),
                  if (customer.orgEmail != null)
                    _InfoRow(
                      icon: Icons.alternate_email,
                      text: customer.orgEmail!,
                    ),
                  if (customer.fullName != null)
                    _InfoRow(
                      icon: Icons.person_outline,
                      text: 'Холбогдох: ${customer.fullName!}',
                    ),
                ],
                const SizedBox(height: 4),
                if (customer.phone != null)
                  _InfoRow(icon: Icons.phone_outlined, text: customer.phone!),
                if (customer.email != null)
                  _InfoRow(icon: Icons.email_outlined, text: customer.email!),
                if (customer.note != null)
                  _InfoRow(icon: Icons.notes_outlined, text: customer.note!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: context.colors.textSecondary),
          const SizedBox(width: 5),
          Expanded(child: Text(text, style: context.textStyles.caption)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: context.textStyles.h2.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: context.textStyles.caption),
        ],
      ),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({required this.link});

  final CustomerVehicleLink link;

  @override
  Widget build(BuildContext context) {
    final vehicle = link.vehicle;
    return AppCard(
      onTap: vehicle == null
          ? null
          : () => _openVehicle(context, vehicle, link),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            ),
            child: Icon(
              Icons.directions_car_outlined,
              color: context.colors.textPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle?.plate == null
                      ? 'Дугаар байхгүй'
                      : plateLabel(vehicle?.plate, vehicle?.vin),
                  style: context.textStyles.bodyMedium,
                ),
                Text(
                  vehicle?.displayName ?? 'Тодорхойгүй',
                  style: context.textStyles.caption,
                ),
              ],
            ),
          ),
          Text('${link.orderCount}', style: context.textStyles.caption),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, color: context.colors.textHint),
        ],
      ),
    );
  }

  // `VehicleDetailScreen` (P3-F5, concurrent slice) fetches by vehicle id —
  // `vehicle.id` here is the vehicle's own id (see [CustomerVehicleRef]),
  // not the `TenantVehicle` link id carried on [CustomerVehicleLink.id].
  void _openVehicle(
    BuildContext context,
    CustomerVehicleRef vehicle,
    CustomerVehicleLink link,
  ) {
    AppNav.to(VehicleDetailScreen(vehicleId: vehicle.id));
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.controller});

  final CustomerDetailController controller;

  @override
  Widget build(BuildContext context) {
    return AsyncStateView<List<CustomerHistoryOrder>>(
      state: controller.historyState,
      isEmpty: (value) => value.isEmpty,
      empty: const EmptyState(
        message: 'Захиалгын түүх алга',
        icon: Icons.receipt_long_outlined,
      ),
      onRetry: controller.loadHistory,
      builder: (context, orders) => Column(
        children: [
          ...orders.map(
            (order) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _HistoryOrderRow(order: order),
            ),
          ),
          CustomerListFooter(
            loadingMore: controller.historyLoadingMore,
            loadMoreError: controller.historyLoadMoreError?.display,
            hasNext: controller.hasHistoryNext,
            total: controller.historyTotal,
            onLoadMore: controller.loadMoreHistory,
          ),
        ],
      ),
    );
  }
}

class _HistoryOrderRow extends StatelessWidget {
  const _HistoryOrderRow({required this.order});

  final CustomerHistoryOrder order;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final date = order.completedAt ?? order.scheduledAt ?? order.createdAt;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.colors.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              color: context.colors.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.number ??
                      (order.vehicle?.plate == null
                          ? null
                          : plateLabel(
                              order.vehicle!.plate,
                              order.vehicle!.vin,
                            )) ??
                      order.id,
                  style: context.textStyles.bodyMedium,
                ),
                if (order.status != null)
                  Text(
                    order.status!,
                    style: context.textStyles.caption.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                if (date != null)
                  Text(fmt.format(date), style: context.textStyles.caption),
              ],
            ),
          ),
          if (order.totalAmount != null)
            Text(order.totalAmount!, style: context.textStyles.bodyMedium),
        ],
      ),
    );
  }
}
