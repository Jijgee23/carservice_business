import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/adaptive/adaptive.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
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
          _SearchField(
            controller: _searchController,
            onChanged: controller.setQuery,
            onClear: () {
              _searchController.clear();
              controller.setQuery('');
            },
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppDimens.paddingMD,
      AppDimens.paddingMD,
      AppDimens.paddingMD,
      AppDimens.paddingSM,
    ),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Улсын дугаар, марк, модел, VIN, эзэмшигч...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(onPressed: onClear, icon: const Icon(Icons.close)),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
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
    padding: const EdgeInsets.all(AppDimens.paddingMD),
    itemCount: vehicles.length + 1,
    separatorBuilder: (_, index) =>
        SizedBox(height: index == vehicles.length - 1 ? 4 : 10),
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
    padding: const EdgeInsets.symmetric(vertical: 8),
    itemCount: vehicles.length + 2,
    itemBuilder: (context, index) {
      if (index == 0) return const _TableHeader();
      if (index == vehicles.length + 1) {
        return VehicleListFooter(controller: controller);
      }
      final vehicle = vehicles[index - 1];
      return VehicleTableRow(
        vehicle: vehicle,
        onTap: onTap == null ? null : () => onTap!(vehicle),
      );
    },
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppDimens.paddingMD,
      vertical: AppDimens.paddingSM,
    ),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text('Улсын дугаар', style: context.textStyles.captionMedium),
        ),
        Expanded(
          flex: 3,
          child: Text('Марк / модел', style: context.textStyles.captionMedium),
        ),
        Expanded(
          flex: 3,
          child: Text('Эзэмшигч', style: context.textStyles.captionMedium),
        ),
        Expanded(
          flex: 2,
          child: Text('Дараа төлбөр', style: context.textStyles.captionMedium),
        ),
      ],
    ),
  );
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
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    vehicle.plate == null
                        ? '—'
                        : plateLabel(vehicle.plate, vehicle.vin),
                    style: context.textStyles.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  vehicle.hasOwner ? Icons.person : Icons.person_off_outlined,
                  size: 16,
                  color: context.textStyles.caption.color,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              vehicle.displayName.isEmpty ? '—' : vehicle.displayName,
              style: context.textStyles.captionMedium,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(
                  child: Text(
                    vehicle.customer?.displayName ?? 'Эзэнгүй',
                    style: context.textStyles.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (vehicle.ownerIsOrganization) ...[
                  const SizedBox(width: 6),
                  const OrgBadge(),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// One vehicle, tablet width. Same list-route field restriction as
/// [VehiclePhoneCard] applies.
class VehicleTableRow extends StatelessWidget {
  const VehicleTableRow({super.key, required this.vehicle, this.onTap});
  final Vehicle vehicle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
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
              child: Text(
                vehicle.plate == null
                    ? '—'
                    : plateLabel(vehicle.plate, vehicle.vin),
                style: context.textStyles.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                vehicle.displayName.isEmpty ? '—' : vehicle.displayName,
                style: context.textStyles.captionMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      vehicle.customer?.displayName ?? 'Эзэнгүй',
                      style: context.textStyles.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (vehicle.ownerIsOrganization) ...[
                    const SizedBox(width: 6),
                    const OrgBadge(),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: vehicle.isPostpaid
                  ? const _PostpaidChip()
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    ),
  );
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
