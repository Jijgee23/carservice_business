import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/services/domain/service.dart';
import 'package:carservice_business/features/services/domain/services_repository.dart';
import 'package:carservice_business/features/services/presentation/controllers/service_detail_controller.dart';
import 'package:carservice_business/features/services/presentation/screens/bulk_category_screen.dart';
import 'package:carservice_business/features/services/presentation/screens/create_service_screen.dart';
import 'package:carservice_business/features/services/presentation/screens/stock_adjust_sheet.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Service detail rebuild — P4-F3.
///
/// Fetches by id ([ServiceDetailController], no preloaded-summary
/// constructor) — the `P3-F4`/`P3-F5` convention. Permission-gates the
/// **surface itself** on `services.view` (D-163: "gate the screen, not only
/// its buttons" — the legacy screen this replaces had no gating at all), and
/// gates edit/delete/stock/bulk-category actions individually on
/// `services.edit`/`services.delete` through the same injected-[User]
/// pattern `CustomerDetailScreen` uses (D-160: a bare `Authenticator.user`
/// fallback reads a Hive box no widget test opens).
///
/// **Never renders a `PATCH` echo.** Editing pushes [CreateServiceScreen] in
/// edit mode and only acts on its `true`/`false` result — [_edit] always
/// calls [ServiceDetailController.refresh] (a fresh `getService`) afterward
/// rather than trust anything the edit screen's own repository call
/// returned, per `service.dart`'s module doc comment on the measured
/// `PATCH`-vs-`GET` shape divergence.
class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({
    super.key,
    required this.serviceId,
    this.repo,
    this.user,
  });

  final String serviceId;
  final ServicesRepository? repo;
  final User? user;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  late final ServiceDetailController _controller;

  User? get _user => widget.user ?? Authenticator.user;

  @override
  void initState() {
    super.initState();
    _controller = ServiceDetailController(
      serviceId: widget.serviceId,
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
    // D-163 — gate the surface itself, not only its actions. A staff member
    // without `services.view` never even issues the fetch.
    if (!canSeeView(_user, 'services.view')) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          message: 'Энэ мэдээллийг үзэх эрх байхгүй байна',
          icon: Icons.lock_outline,
        ),
      );
    }
    return ChangeNotifierProvider<ServiceDetailController>.value(
      value: _controller,
      child: _ServiceDetailBody(user: _user),
    );
  }
}

class _ServiceDetailBody extends StatelessWidget {
  const _ServiceDetailBody({required this.user});

  final User? user;

  Future<void> _edit(BuildContext context, ServiceDetailController ctrl) async {
    final service = ctrl.service;
    if (service == null) return;
    final saved = await AppNav.to<bool>(CreateServiceScreen(existing: service));
    if (saved == true) {
      // Re-fetch rather than trust the edit screen's own PATCH response —
      // see the class doc comment.
      await ctrl.refresh();
      if (context.mounted) messageComplete('Үйлчилгээ шинэчлэгдлээ');
    }
  }

  Future<void> _adjustStock(
    BuildContext context,
    ServiceDetailController ctrl,
  ) async {
    final service = ctrl.service;
    if (service == null || !service.isStockAdjustable) return;
    await StockAdjustSheet.show(context, service: service, controller: ctrl);
  }

  void _bulkCategory(BuildContext context) {
    AppNav.to(BulkCategoryScreen(user: user));
  }

  Future<void> _delete(
    BuildContext context,
    ServiceDetailController ctrl,
  ) async {
    final service = ctrl.service;
    if (service == null) return;
    // The server alone decides archive-vs-hard-delete (order-item history),
    // but `orderItemCount` from this same detail fetch predicts it well
    // enough to warn honestly before the user confirms — see the class doc
    // comment.
    final willArchive = (service.orderItemCount ?? 0) > 0;
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Үйлчилгээ устгах уу?',
      message: willArchive
          ? '${service.displayName}-г засварын хуудсанд ашигласан тул бүрмөсөн '
                'устгахгүй, харин архивлана. Каталогт "Идэвхгүй" гэж харагдана.'
          : '${service.displayName}-г бүрмөсөн устгахдаа итгэлтэй байна уу?',
      confirmLabel: 'Устгах',
      icon: Icons.delete_forever_rounded,
      isDangerous: true,
    );
    if (!confirmed) return;
    final result = await ctrl.delete();
    if (!context.mounted) return;
    switch (result) {
      case Ok(:final value):
        messageComplete(
          value.outcome == ServiceDeleteOutcome.archived
              ? 'Үйлчилгээ архивлагдлаа'
              : 'Үйлчилгээ устгагдлаа',
        );
        AppNav.back();
      case Err(:final error):
        messageError(error.display);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ServiceDetailController>();
    final service = ctrl.service;
    final canEdit = canSeeView(user, 'services.edit');
    final canDelete = canSeeView(user, 'services.delete');

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(service?.displayName ?? 'Үйлчилгээ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Дахин ачаалах',
            onPressed: ctrl.refresh,
          ),
          PermissionGate(
            permission: 'services.edit',
            user: user,
            child: IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Засах',
              onPressed: canEdit && service != null
                  ? () => _edit(context, ctrl)
                  : null,
            ),
          ),
          PermissionGate(
            permission: 'services.delete',
            user: user,
            child: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Устгах',
              onPressed: canDelete && service != null && !ctrl.mutating
                  ? () => _delete(context, ctrl)
                  : null,
            ),
          ),
          if (canEdit)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'bulk_category') _bulkCategory(context);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'bulk_category',
                  child: Text('Ангилал бөөнөөр солих'),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton:
          service != null && service.isStockAdjustable && canEdit
          ? FloatingActionButton.extended(
              key: const ValueKey('service_stock_fab'),
              heroTag: 'service_stock_fab',
              onPressed: () => _adjustStock(context, ctrl),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Үлдэгдэл'),
            )
          : null,
      body: AsyncStateView<Service>(
        state: ctrl.state,
        onRetry: ctrl.refresh,
        builder: (context, s) => RefreshIndicator(
          onRefresh: ctrl.refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppDimens.paddingMD),
            children: [
              _HeaderCard(service: s),
              const SizedBox(height: 14),
              _PricingCard(service: s),
              if (s.type == ServiceKind.goods) ...[
                const SizedBox(height: 14),
                _StockCard(service: s),
              ],
              const SizedBox(height: 14),
              _DetailsCard(service: s),
              if (s.code != null) ...[
                const SizedBox(height: 14),
                AppCard(
                  child: _DetailRow(
                    icon: Icons.tag,
                    label: 'Код (SKU)',
                    value: s.code!,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              AppCard(
                child: _DetailRow(
                  icon: Icons.receipt_long_outlined,
                  label: 'Засварын хуудсанд ашигласан',
                  value: '${s.orderItemCount ?? 0} удаа',
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Cards ──────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.service});
  final Service service;

  @override
  Widget build(BuildContext context) {
    final color = _kindColor(context, service.type);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                ),
                child: Icon(_kindIcon(service.type), size: 28, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.displayName, style: context.textStyles.h3),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _Chip(label: service.type.label, color: color),
                        if (!service.isActive) ...[
                          const SizedBox(width: 8),
                          _Chip(
                            label: 'Идэвхгүй / Архивласан',
                            color: context.colors.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (service.description != null &&
              service.description!.isNotEmpty) ...[
            const Divider(height: 20),
            Text(service.description!, style: context.textStyles.body),
          ],
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({required this.service});
  final Service service;

  @override
  Widget build(BuildContext context) {
    final costPrice = service.costPrice;
    final price = double.tryParse(service.price ?? '');
    final cost = double.tryParse(costPrice ?? '');
    final profit = (price != null && cost != null) ? price - cost : null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Үнэ мэдээлэл', style: context.textStyles.h3),
          const Divider(height: 20),
          _DetailRow(
            icon: Icons.sell_outlined,
            label: 'Зарах үнэ',
            value:
                '${service.price ?? '—'}₮'
                '${service.unit != null ? ' / ${service.unit!.display}' : ''}',
            valueStyle: context.textStyles.bodyMedium.copyWith(
              color: context.colors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (costPrice != null) ...[
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.receipt_outlined,
              label: 'Өртөг',
              value: '$costPrice₮',
            ),
          ],
          if (profit != null) ...[
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.trending_up_outlined,
              label: 'Ашиг',
              value: '${profit.toStringAsFixed(2)}₮',
              valueStyle: TextStyle(color: context.colors.good),
            ),
          ],
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.service});
  final Service service;

  @override
  Widget build(BuildContext context) {
    final stock = double.tryParse(service.stock ?? '');
    final level = stock == null
        ? null
        : stock <= 0
        ? _StockLevel.out
        : stock < 5
        ? _StockLevel.low
        : _StockLevel.ok;
    final color = switch (level) {
      _StockLevel.out => context.colors.danger,
      _StockLevel.low => context.colors.warning,
      _StockLevel.ok || null => context.colors.good,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Нөөц', style: context.textStyles.h3),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: _StockBox(
                  label: 'Үлдэгдэл',
                  value: service.stock ?? '—',
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StockBox(
                  label: 'Төлөв',
                  value: switch (level) {
                    _StockLevel.out => 'Дууссан',
                    _StockLevel.low => 'Бага үлдэгдэл',
                    _StockLevel.ok || null => 'Хүрэлцээтэй',
                  },
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _StockLevel { out, low, ok }

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.service});
  final Service service;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (service.category?.name != null) {
      rows.add(
        _DetailRow(
          icon: Icons.folder_outlined,
          label: 'Ангилал',
          value: service.category!.name!,
        ),
      );
    }
    if (service.durationValue != null) {
      final unitLabel = service.durationUnit?.display;
      rows.add(
        _DetailRow(
          icon: Icons.schedule_outlined,
          label: 'Зарцуулах хугацаа',
          value: unitLabel != null
              ? '${service.durationValue} $unitLabel'
              : service.durationValue!,
        ),
      );
    }
    if (service.unit?.name != null) {
      rows.add(
        _DetailRow(
          icon: Icons.straighten_outlined,
          label: 'Хэмжих нэгж',
          value: service.unit!.name!,
        ),
      );
    }
    if (service.updatedAt != null) {
      rows.add(
        _DetailRow(
          icon: Icons.history_rounded,
          label: 'Сүүлд шинэчилсэн',
          value: DateFormat('yyyy-MM-dd HH:mm').format(service.updatedAt!),
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Дэлгэрэнгүй', style: context.textStyles.h3),
          const Divider(height: 20),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            rows[i],
          ],
        ],
      ),
    );
  }
}

// ─── Small shared widgets ───────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final IconData icon;
  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.colors.textSecondary),
        const SizedBox(width: 8),
        Text(label, style: context.textStyles.caption),
        const Spacer(),
        Text(value, style: valueStyle ?? context.textStyles.bodyMedium),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StockBox extends StatelessWidget {
  const _StockBox({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.textStyles.caption),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Kind presentation (new `ServiceKind`; the legacy presentation extension
// in `service_catalog_presentation.dart` is for the old enum and is left
// untouched — still used by `service_list_screen.dart`, owned by `P4-F2`) ──

Color _kindColor(BuildContext context, ServiceKind kind) {
  final theme = CarserviceTheme.of(context);
  return switch (kind) {
    ServiceKind.labor => theme.accent,
    ServiceKind.goods => theme.ok,
    ServiceKind.diagnostic => theme.accentHi,
    ServiceKind.unknown => theme.mutedText,
  };
}

IconData _kindIcon(ServiceKind kind) => switch (kind) {
  ServiceKind.labor => Icons.build_outlined,
  ServiceKind.goods => Icons.inventory_2_outlined,
  ServiceKind.diagnostic => Icons.troubleshoot_outlined,
  ServiceKind.unknown => Icons.help_outline,
};
