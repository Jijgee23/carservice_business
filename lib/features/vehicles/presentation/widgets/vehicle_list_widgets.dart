import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/adaptive/adaptive.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/list_search_bar.dart';
import 'package:carservice_business/core/widgets/org_badge.dart';
import 'package:carservice_business/core/widgets/mixin/pagination_mixin.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/presentation/controllers/vehicle_list_controller.dart';

/// Server-authoritative Vehicles list body — P3-F3.
///
/// Deliberately a standalone widget rather than baked into a screen: the
/// vehicle tab of `search_screen.dart` (owned by the concurrent `P3-F2`
/// worker) is meant to embed exactly this widget once that migration lands,
/// the same way `VehicleListScreen` in this slice does. See that screen's
/// doc comment for what the migration needs to do.
///
/// Layout follows `NotificationScreen`'s precedent
/// (`features/notifications/presentation/screens/notification_screen.dart`):
/// [AsyncStateView] for load/empty/error, [PaginationMixin] for the
/// scroll-triggered `loadMore`, and [AdaptiveBreakpoints] to switch between a
/// phone card list and a tablet table — not [DataTableView], because that
/// primitive owns its internal `ListView` outright and has no seam for an
/// append-only load-more footer; this widget needs both in one scroll view.
class VehicleListView extends StatefulWidget {
  const VehicleListView({super.key, required this.controller, this.onTap});

  final VehicleListController controller;
  final ValueChanged<Vehicle>? onTap;

  @override
  State<VehicleListView> createState() => _VehicleListViewState();
}

class _VehicleListViewState extends State<VehicleListView>
    with PaginationMixin {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.controller.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initPagination(() {
        if (mounted) widget.controller.loadMore();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        children: [
          ListSearchBar(
            controller: _searchController,
            hintText: 'Дугаар, марк, VIN, эзэмшигч',
            onChanged: controller.setQuery,
            onClear: () {
              _searchController.clear();
              controller.setQuery('');
            },
            loading: controller.listState is AsyncLoading,
            padding: const EdgeInsets.fromLTRB(
              AppDimens.paddingMD,
              AppDimens.paddingMD,
              AppDimens.paddingMD,
              AppDimens.paddingSM,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = AdaptiveBreakpoints.ofWidth(constraints.maxWidth);
                return AsyncStateView<List<Vehicle>>(
                  state: controller.listState,
                  isEmpty: (items) => items.isEmpty,
                  empty: _EmptyView(
                    hasQuery:
                        controller.query.isNotEmpty ||
                        controller.hasActiveFilters,
                  ),
                  error: (context, error) => _ErrorView(
                    message: error.display,
                    onRetry: controller.refresh,
                  ),
                  builder: (context, items) => RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: size == AdaptiveSize.phone
                        ? _PhoneList(
                            vehicles: items,
                            controller: controller,
                            scrollController: scrollController,
                            onTap: widget.onTap,
                          )
                        : _TabletTable(
                            vehicles: items,
                            controller: controller,
                            scrollController: scrollController,
                            onTap: widget.onTap,
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.hasQuery});
  final bool hasQuery;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      hasQuery ? 'Шүүлтэд тохирох машин байхгүй' : 'Машин бүртгэгдээгүй байна',
      style: context.textStyles.body,
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Дахин оролдох'),
        ),
      ],
    ),
  );
}

class _PhoneList extends StatelessWidget {
  const _PhoneList({
    required this.vehicles,
    required this.controller,
    required this.scrollController,
    required this.onTap,
  });
  final List<Vehicle> vehicles;
  final VehicleListController controller;
  final ScrollController scrollController;
  final ValueChanged<Vehicle>? onTap;

  @override
  Widget build(BuildContext context) => ListView.separated(
    controller: scrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(
      AppDimens.paddingMD,
      AppDimens.paddingXS,
      AppDimens.paddingMD,
      AppDimens.paddingMD,
    ),
    itemCount: vehicles.length + 1,
    separatorBuilder: (_, index) => SizedBox(
      height: index == vehicles.length - 1 ? 4 : AppDimens.paddingSM,
    ),
    itemBuilder: (_, index) {
      if (index == vehicles.length) {
        return VehicleListFooter(controller: controller);
      }
      final vehicle = vehicles[index];
      return VehiclePhoneCard(
        vehicle: vehicle,
        onTap: onTap == null ? null : () => onTap!(vehicle),
      );
    },
  );
}

class _TabletTable extends StatelessWidget {
  const _TabletTable({
    required this.vehicles,
    required this.controller,
    required this.scrollController,
    required this.onTap,
  });
  final List<Vehicle> vehicles;
  final VehicleListController controller;
  final ScrollController scrollController;
  final ValueChanged<Vehicle>? onTap;

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: scrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(
      AppDimens.paddingMD,
      AppDimens.paddingXS,
      AppDimens.paddingMD,
      AppDimens.paddingMD,
    ),
    itemCount: vehicles.length + 2,
    itemBuilder: (context, index) {
      if (index == 0) return const _TableHeader();
      if (index == vehicles.length + 1) {
        return VehicleListFooter(controller: controller);
      }
      final vehicle = vehicles[index - 1];
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: context.colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            side: BorderSide(color: context.colors.divider),
          ),
          child: VehicleTableRow(
            vehicle: vehicle,
            onTap: onTap == null ? null : () => onTap!(vehicle),
          ),
        ),
      );
    },
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = context.textStyles.captionMedium.copyWith(
      color: context.colors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingMD,
        AppDimens.paddingSM,
        AppDimens.paddingMD,
        AppDimens.paddingSM,
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Улсын дугаар', style: style)),
          Expanded(flex: 3, child: Text('Марк / модел', style: style)),
          Expanded(flex: 3, child: Text('Эзэмшигч', style: style)),
          Expanded(flex: 2, child: Text('Дараа төлбөр', style: style)),
        ],
      ),
    );
  }
}

/// One vehicle, phone width. List rows carry only `customer:{id,fullName,
/// phone}|null` — no extended attribute block and no `isPostpaid` from the
/// list route per the frozen contract, so nothing here may render those; the
/// `isPostpaid` field on [Vehicle] defaults to `false` for a list row and
/// must not be trusted as "confirmed not postpaid" — hence no postpaid
/// badge on this card. It is shown only on the tablet table below as an
/// explicit "list default" chip, worded to avoid implying certainty.
class VehiclePhoneCard extends StatelessWidget {
  const VehiclePhoneCard({super.key, required this.vehicle, this.onTap});
  final Vehicle vehicle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mileage = vehicle.mileage;
    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        side: BorderSide(color: context.colors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PlateLine(vehicle: vehicle),
                    const SizedBox(height: 8),
                    _ModelLine(vehicle: vehicle),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _OwnerMeta(vehicle: vehicle),
                        if (vehicle.customer?.fullName != null &&
                            vehicle.customer?.phone != null)
                          _Meta(
                            icon: Icons.call_outlined,
                            text: vehicle.customer!.phone!,
                          ),
                        if (mileage != null)
                          _Meta(
                            icon: Icons.speed_outlined,
                            text: '${_km.format(mileage)} км',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.colors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One vehicle, tablet width. Same list-route field restriction as
/// [VehiclePhoneCard] applies.
class VehicleTableRow extends StatelessWidget {
  const VehicleTableRow({super.key, required this.vehicle, this.onTap});
  final Vehicle vehicle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.paddingMD,
        vertical: 12,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _PlateLine(vehicle: vehicle),
            ),
          ),
          Expanded(flex: 3, child: _ModelLine(vehicle: vehicle)),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _OwnerMeta(vehicle: vehicle),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: vehicle.isPostpaid
                  ? const _PostpaidChip()
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    ),
  );
}

final _km = NumberFormat('#,##0', 'en_US');

/// The plate drawn like a number plate; a plate-less vehicle gets a muted
/// «Дугааргүй» plate with its VIN beside it.
class _PlateLine extends StatelessWidget {
  const _PlateLine({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final noPlate = vehicle.plate == null || isNoPlate(vehicle.plate);
    final vin = vehicle.vin?.trim() ?? '';
    final mono = CarserviceTheme.of(context).monoFontFamily;
    final ink = noPlate
        ? context.colors.textSecondary
        : context.colors.textPrimary;
    final plate = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(AppDimens.radiusXS + 2),
        border: Border.all(
          color: noPlate ? context.colors.divider : ink,
          width: 1.2,
        ),
      ),
      child: Text(
        noPlate ? plateLabel(kNoPlate) : vehicle.plate!,
        maxLines: 1,
        style: TextStyle(
          fontFamily: mono,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: ink,
        ),
      ),
    );
    if (!noPlate || vin.isEmpty) return plate;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        plate,
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            vin,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.caption.copyWith(fontFamily: mono),
          ),
        ),
      ],
    );
  }
}

/// «Toyota Prius 30 · 2012»; a muted placeholder when make and model are
/// both unknown.
class _ModelLine extends StatelessWidget {
  const _ModelLine({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final name = vehicle.displayName;
    if (name.isEmpty) {
      return Text(
        'Марк, загвар тодорхойгүй',
        style: context.textStyles.caption.copyWith(
          color: context.colors.textHint,
        ),
      );
    }
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.bodyMedium,
          ),
        ),
        if (vehicle.year != null)
          Text(' · ${vehicle.year}', style: context.textStyles.caption),
      ],
    );
  }
}

/// The owner (or «Эзэнгүй»), with the organization badge when it is one.
class _OwnerMeta extends StatelessWidget {
  const _OwnerMeta({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final owner = vehicle.customer;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _Meta(
            icon: owner == null
                ? Icons.person_off_outlined
                : vehicle.ownerIsOrganization
                ? Icons.apartment_rounded
                : Icons.person_outline,
            text: owner?.displayName ?? 'Эзэнгүй',
            muted: owner == null,
          ),
        ),
        if (vehicle.ownerIsOrganization) ...[
          const SizedBox(width: 6),
          const OrgBadge(),
        ],
      ],
    );
  }
}

/// One icon + text fact, as on the Orders and Customers list rows.
class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? context.colors.textHint
        : context.colors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.caption.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// `isPostpaid` on a list row is a genuine `false`/absent-degrades-to-`false`
/// per the domain model's contract doc, so a chip only ever appears for the
/// `true` case; there is deliberately no "not postpaid" chip that would
/// overclaim certainty for a field the list route may not have sent.
class _PostpaidChip extends StatelessWidget {
  const _PostpaidChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppDimens.paddingSM,
      vertical: 3,
    ),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
    ),
    child: Text(
      'Дараа төлбөр',
      style: context.textStyles.caption.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onTertiaryContainer,
      ),
    ),
  );
}

/// Load-more footer shared by phone and tablet layouts — same
/// loading/error-preserving-data/exhausted states as
/// `order_list_widgets.dart`'s `_ListFooter` /
/// `appointment_list_widgets.dart`'s equivalent.
class VehicleListFooter extends StatelessWidget {
  const VehicleListFooter({super.key, required this.controller});
  final VehicleListController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppDimens.paddingLG),
        child: AppLoading(size: 24),
      );
    }
    final loadMoreError = controller.loadMoreError;
    if (loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        child: TextButton.icon(
          onPressed: controller.loadMore,
          icon: const Icon(Icons.refresh),
          label: Text('Дахин оролдох: ${loadMoreError.display}'),
        ),
      );
    }
    if (controller.hasNext) {
      return Padding(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        child: TextButton.icon(
          onPressed: controller.loadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('Дараагийн хуудас'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppDimens.paddingLG),
      child: Center(
        child: Text(
          'Нийт ${controller.total} машин',
          style: context.textStyles.caption,
        ),
      ),
    );
  }
}
