import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/money_format.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/mixin/pagination_mixin.dart';
import 'package:carservice_business/features/services/domain/service.dart';
import 'package:carservice_business/features/services/domain/services_repository.dart';
import 'package:carservice_business/features/services/presentation/controllers/service_list_controller.dart';

/// Server-paginated Services list — P4-F2 rebuild.
///
/// Replaces the legacy screen's three independently client-cached
/// `TabBarView` tabs (`AutomaticKeepAliveClientMixin` + a direct
/// `ServiceCatalogService.getServices` call per tab) with one
/// [ServiceListController] — server-side pagination, kind filter and search,
/// copying `VehicleListController`'s generation-guard + debounce pattern
/// exactly (`P3-F3`). The kind-filter tabs (Ажил / Сэлбэг-Бараа / Оношилгоо)
/// now drive [ServiceListQuery.type] server-side; switching tabs is a fresh
/// authoritative reload, not a swap between three cached lists.
///
/// **Affordance audit against the pre-rebuild on-disk file** (that file was
/// never committed, so there is no `git show HEAD:` baseline — read directly
/// per this slice's dispatch note):
///
/// | Legacy affordance | This rebuild |
/// |---|---|
/// | Search box, 350ms debounce | Kept — now the controller's own debounce |
/// | 3 kind tabs (Ажил/Бараа/Оношилгоо) | Kept — now drive the server `type` filter |
/// | Popup menu → labor-category / unit screens | **Removed** — `P4-F4` deleted both dead screens per D-164 and this menu was their only entry point |
/// | Refresh button | Kept |
/// | Pull-to-refresh | Kept |
/// | Per-tab loading spinner | Kept (via `AsyncStateView`'s `AsyncLoading`) |
/// | Per-tab empty state, icon by kind, message varies with query | Kept |
/// | **Silent empty list on any fetch failure** (`ServiceCatalogService.getServices` returned `[]` on network/permission failure — no error UI existed) | **Changed, deliberately**: a real error state with retry now shows, matching every sibling list. The legacy behavior was not a feature; it hid a 403/network failure as "no services", the exact truthfulness problem D-163 names for a missing gate. |
/// | Service card: icon by kind, inactive badge, category, code, GOODS stock badge, non-GOODS duration, price + unit, chevron | Kept, ported to the new [Service] domain model |
/// | FAB → create screen prefilled with the active tab's kind | Kept as a **hook** ([onCreateService]), not a hard-coded push into `CreateServiceScreen` — that screen is owned by the concurrent `P4-F3` worker and takes the legacy `CatalogService` model, not this slice's [Service]. Mirrors `VehicleListScreen`'s identical `onSelectVehicle` hook for the same reason (incompatible model owned by a screen this slice must not touch). The FAB does not render at all when [onCreateService] is null, rather than rendering permanently disabled. |
/// | Row tap → `ServiceDetailScreen` | Kept as a hook ([onSelectService]), same reasoning as the FAB — `service_detail_screen.dart` is also owned by `P4-F3` |
/// | No permission gating anywhere | **Changed**: the whole surface is gated on `services.view` (D-163 — gate the surface, not only its actions), and the create FAB is separately gated on `services.create` |
///
/// Neither hook is wired by this slice — `P4-F4` owns route wiring, matching
/// `VehicleListScreen`'s `P3-F3`→router hand-off precedent
/// (`lib/app/router.dart`'s `_VehicleListRoute`). The existing
/// `home_screen.dart` call site (`const ServiceListScreen()`, no hooks) keeps
/// compiling unchanged; its FAB simply does not render and its rows are
/// inert until a later slice supplies the hooks, exactly "same as today".
class ServiceListScreen extends StatelessWidget {
  const ServiceListScreen({
    super.key,
    this.repository,
    this.user,
    this.onSelectService,
    this.onCreateService,
    this.initialType,
  });

  /// Tests and previews inject a fake. Production defaults to the remote
  /// adapter inside [ServiceListController].
  final ServicesRepository? repository;

  /// Injectable for tests, matching `CustomerDetailScreen`/`VehicleSearchTab`
  /// — the injected-`user` pattern D-160 restored after `Authenticator.user`
  /// (a Hive box no widget test opens) broke a gate under test. Null in
  /// production, where the gate reads `Authenticator.user`.
  final User? user;

  final ValueChanged<Service>? onSelectService;

  /// Called with the currently-selected kind tab when the create FAB is
  /// tapped. See the class doc comment for why this is a hook rather than a
  /// direct push into the concurrently-owned `CreateServiceScreen`.
  final ValueChanged<ServiceKind>? onCreateService;

  /// Which kind tab opens selected. `null` preserves the pre-existing
  /// default (the labor tab, index 0) — added by `P4-F4` so a route/caller
  /// that already knows which kind the user wants (the "Каталог" drawer's
  /// Хөдөлмөр/Бараа entries) can seed it instead of the list always opening
  /// on labor regardless of entry point.
  final ServiceKind? initialType;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) =>
        ServiceListController(repo: repository, initialType: initialType),
    child: _Body(
      user: user,
      onSelectService: onSelectService,
      onCreateService: onCreateService,
      initialType: initialType,
    ),
  );
}

class _Body extends StatefulWidget {
  const _Body({
    this.user,
    this.onSelectService,
    this.onCreateService,
    this.initialType,
  });

  final User? user;
  final ValueChanged<Service>? onSelectService;
  final ValueChanged<ServiceKind>? onCreateService;
  final ServiceKind? initialType;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body>
    with SingleTickerProviderStateMixin, PaginationMixin {
  static const _kinds = <ServiceKind>[
    ServiceKind.labor,
    ServiceKind.goods,
    ServiceKind.diagnostic,
  ];

  late final TabController _tabController;
  final _searchController = TextEditingController();
  bool _didLoad = false;

  User? get _user => widget.user ?? Authenticator.user;

  @override
  void initState() {
    super.initState();
    final seededIndex = widget.initialType == null
        ? 0
        : _kinds.indexOf(widget.initialType!);
    _tabController = TabController(
      length: _kinds.length,
      vsync: this,
      initialIndex: seededIndex < 0 ? 0 : seededIndex,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoad) {
      _didLoad = true;
      final controller = context.read<ServiceListController>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        initPagination(() {
          if (mounted) controller.loadMore();
        });
        controller.loadServices();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (!canSeeView(user, 'services.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Үйлчилгээний каталог')),
        body: const EmptyState(
          message: 'Танд үйлчилгээний каталог харах эрх байхгүй байна.',
          icon: Icons.lock_outline,
        ),
      );
    }

    final controller = context.watch<ServiceListController>();
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Үйлчилгээний каталог'),
        actions: [
          IconButton(
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _SearchField(
                  controller: _searchController,
                  onChanged: controller.setQuery,
                  onClear: () {
                    _searchController.clear();
                    controller.setQuery('');
                  },
                ),
              ),
              TabBar(
                controller: _tabController,
                onTap: (index) => controller.setType(_kinds[index]),
                tabs: _kinds.map((k) => Tab(text: k.label)).toList(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.onCreateService == null
          ? null
          : PermissionGate(
              permission: 'services.create',
              user: user,
              child: FloatingActionButton(
                heroTag: 'service_create_fab',
                onPressed: () =>
                    widget.onCreateService!(_kinds[_tabController.index]),
                backgroundColor: context.colors.accent,
                child: Icon(
                  Icons.add,
                  color: CarserviceTheme.of(context).onAccent,
                ),
              ),
            ),
      body: AsyncStateView<List<Service>>(
        state: controller.listState,
        isEmpty: (items) => items.isEmpty,
        empty: _EmptyView(query: controller.query, kind: controller.type),
        onRetry: controller.refresh,
        builder: (context, items) => RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.all(AppDimens.paddingMD),
            itemCount: items.length + 1,
            separatorBuilder: (_, index) =>
                SizedBox(height: index == items.length - 1 ? 4 : 8),
            itemBuilder: (_, index) {
              if (index == items.length) {
                return _ServiceListFooter(controller: controller);
              }
              final service = items[index];
              return _ServiceCard(
                service: service,
                onTap: widget.onSelectService == null
                    ? null
                    : () => widget.onSelectService!(service),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Search field ───────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14, color: context.colors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Нэр, код, тайлбар хайх...',
        hintStyle: TextStyle(color: context.colors.textHint, fontSize: 14),
        prefixIcon: Icon(
          Icons.search,
          color: context.colors.textHint,
          size: 18,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  color: context.colors.textHint,
                  size: 18,
                ),
              ),
        filled: true,
        fillColor: context.colors.background,
        contentPadding: EdgeInsets.zero,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          borderSide: BorderSide(color: CarserviceTheme.of(context).accentHi),
        ),
      ),
    ),
  );
}

// ─── Empty / footer ──────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.query, required this.kind});

  final String query;
  final ServiceKind kind;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_kindIcon(kind), size: 56, color: context.colors.textHint),
        const SizedBox(height: 12),
        Text(
          query.isNotEmpty
              ? '"$query" — үр дүн олдсонгүй'
              : 'Үйлчилгээ байхгүй байна',
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

/// Load-more footer — same loading/error-preserving-data/exhausted states as
/// `VehicleListFooter` / `AppointmentListController`'s equivalents.
class _ServiceListFooter extends StatelessWidget {
  const _ServiceListFooter({required this.controller});
  final ServiceListController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final loadMoreError = controller.loadMoreError;
    if (loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: TextButton.icon(
          onPressed: controller.loadMore,
          icon: const Icon(Icons.refresh),
          label: Text('Дахин оролдох: ${loadMoreError.display}'),
        ),
      );
    }
    if (controller.hasNext) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: TextButton.icon(
          onPressed: controller.loadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('Дараагийн хуудас'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          'Нийт ${controller.total} үйлчилгээ',
          style: context.textStyles.caption,
        ),
      ),
    );
  }
}

// ─── Service card ────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, this.onTap});

  final Service service;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final categoryName = s.category?.name;

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusLG),
      elevation: AppDimens.cardElevation,
      shadowColor: context.colors.textPrimary.withOpacity(0.12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kindColor(context, s.type).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                ),
                child: Icon(
                  _kindIcon(s.type),
                  size: 22,
                  color: _kindColor(context, s.type),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.displayName,
                            style: context.textStyles.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!s.isActive)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.textHint.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(
                                AppDimens.radiusFull,
                              ),
                            ),
                            child: Text(
                              'Идэвхгүй',
                              style: TextStyle(
                                fontSize: 10,
                                color: context.colors.textHint,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // `Wrap`, not `Row`: category name + code + stock badge
                    // can exceed a phone-width card together (a long
                    // category name in particular), and this metadata line
                    // is allowed to take a second line rather than overflow
                    // or truncate silently.
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (categoryName != null && categoryName.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 12,
                                  color: context.colors.textHint,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    categoryName,
                                    style: context.textStyles.caption,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (s.code != null)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 90),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tag,
                                  size: 12,
                                  color: context.colors.textHint,
                                ),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    s.code!,
                                    style: context.textStyles.caption,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (s.type == ServiceKind.goods)
                          _StockBadge(service: s),
                      ],
                    ),
                    if (s.type != ServiceKind.goods &&
                        s.durationValue != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            size: 12,
                            color: context.colors.textHint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _durationDisplay(s),
                            style: context.textStyles.caption,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(s.price),
                    style: context.textStyles.bodyMedium.copyWith(
                      color: context.colors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (s.unit != null)
                    Text(
                      '/ ${s.unit!.display}',
                      style: context.textStyles.caption,
                    ),
                ],
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.colors.textHint,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.service});
  final Service service;

  @override
  Widget build(BuildContext context) {
    final level = _stockLevelOf(service);
    final color = _stockColor(context, level);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 110),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _stockDisplay(service),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Kind / stock presentation helpers ──────────────────────────────────────
//
// `service_catalog_presentation.dart`'s `ServiceKindPresentation` extension
// is keyed on the legacy uppercase `ServiceKind` (`core/domain/
// service_catalog.dart`), not the `P4-F1` domain model's lowercase one this
// screen renders — that file is out of this slice's scope (not among its
// owned paths) and could not be reused even read-only without an extension
// clash. These are file-private equivalents for the new enum only.

IconData _kindIcon(ServiceKind kind) => switch (kind) {
  ServiceKind.labor => Icons.build_outlined,
  ServiceKind.goods => Icons.inventory_2_outlined,
  ServiceKind.diagnostic => Icons.troubleshoot_outlined,
  ServiceKind.unknown => Icons.help_outline,
};

Color _kindColor(BuildContext context, ServiceKind kind) => switch (kind) {
  ServiceKind.labor => context.colors.accent,
  ServiceKind.goods => context.colors.good,
  ServiceKind.diagnostic => context.colors.accentLight,
  ServiceKind.unknown => context.colors.textHint,
};

enum _StockLevel { out, low, ok }

/// Same thresholds as the legacy `CatalogService.stockLevel` (`out` at `<=0`,
/// `low` under `5`, `ok` otherwise) — parity, not a new policy.
_StockLevel _stockLevelOf(Service service) {
  if (service.type != ServiceKind.goods) return _StockLevel.ok;
  final value = double.tryParse(service.stock ?? '') ?? 0;
  if (value <= 0) return _StockLevel.out;
  if (value < 5) return _StockLevel.low;
  return _StockLevel.ok;
}

Color _stockColor(BuildContext context, _StockLevel level) => switch (level) {
  _StockLevel.out => context.colors.danger,
  _StockLevel.low => context.colors.warning,
  _StockLevel.ok => context.colors.good,
};

String _stockDisplay(Service service) {
  final raw = double.tryParse(service.stock ?? '');
  final unit = service.unit?.display;
  if (raw == null) {
    final fallback = service.stock ?? '0';
    return unit != null && unit.isNotEmpty ? '$fallback $unit' : fallback;
  }
  final n = raw == raw.truncateToDouble()
      ? raw.toInt().toString()
      : raw.toStringAsFixed(3);
  return unit != null && unit.isNotEmpty ? '$n $unit' : n;
}

String _durationDisplay(Service service) {
  final raw = double.tryParse(service.durationValue ?? '');
  if (raw == null) return '—';
  final n = raw == raw.truncateToDouble()
      ? raw.toInt().toString()
      : raw.toStringAsFixed(1);
  final unit = service.durationUnit?.display;
  return unit != null && unit.isNotEmpty ? '$n $unit' : n;
}
