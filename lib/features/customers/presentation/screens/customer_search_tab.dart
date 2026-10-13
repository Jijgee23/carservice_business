import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/widgets/adaptive/adaptive.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/filter_pill.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_list_controller.dart';
import 'package:carservice_business/features/customers/presentation/screens/customer_broadcast_screen.dart';
import 'package:carservice_business/features/customers/presentation/screens/customer_detail_screen.dart';
import 'package:carservice_business/features/customers/presentation/widgets/customer_list_widgets.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// The customer tab of `search_screen.dart`'s `SearchScreen`, split into its
/// own file — P3-F2 — so it can take an injectable [controller] for tests.
/// Its sibling `VehicleSearchTab` was migrated the same way in the `P3-F3`
/// follow-up, leaving `search_screen.dart` as just a tab bar.
///
/// Migrated onto [CustomerListController]: server-side pagination and `q`
/// filter, the shared `AsyncStateView` for loading/empty/error states, and
/// the controller's own debounce — replacing the hand-rolled `Timer` and the
/// direct `DiagnosticService.searchCustomers` call the legacy tab used. The
/// tab now shows the full, paginated customer list by default (a
/// first-class list, not just a search box) and narrows it via `q` as the
/// user types, composing with — rather than replacing — the previous
/// "type to search" affordance.
///
/// Navigation opens the rebuilt `CustomerDetailScreen` (P3-F4) by id. The
/// legacy adapter method that used to convert [Customer] into the old
/// `CustomerSummary` shape for that screen has been removed; the screen now
/// fetches its own data by id.
class CustomerSearchTab extends StatefulWidget {
  const CustomerSearchTab({super.key, this.controller, this.user});

  /// Injectable for tests; defaults to a fresh
  /// `CustomerListController()` (real repository) in production, matching
  /// how the other list screens are constructed at their call sites.
  final CustomerListController? controller;

  /// Injectable for tests, matching `CustomerDetailScreen`. In production it
  /// is null and the gate reads `Authenticator.user`.
  final User? user;

  @override
  State<CustomerSearchTab> createState() => _CustomerSearchTabState();
}

class _CustomerSearchTabState extends State<CustomerSearchTab> {
  final _ctrl = TextEditingController();
  late final CustomerListController _controller;
  late final bool _ownsController;

  User? get _user => widget.user ?? Authenticator.user;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? CustomerListController();
    _ownsController = widget.controller == null;
    unawaited(_controller.loadCustomers());
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // P3-X1: the surface itself is gated, not just its actions. The server
    // is authoritative (`customers.view` → 403), but a staff member without
    // the permission should meet an explanation, not an empty list that
    // looks like missing data.
    if (!canSeeView(_user, 'customers.view')) {
      return const EmptyState(
        message: 'Танд үйлчлүүлэгчийн жагсаалт харах эрх байхгүй байна.',
        icon: Icons.lock_outline,
      );
    }
    return ChangeNotifierProvider<CustomerListController>.value(
      value: _controller,
      child: Consumer<CustomerListController>(
        builder: (context, ctrl, _) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.paddingMD,
                  AppDimens.paddingMD,
                  AppDimens.paddingMD,
                  AppDimens.paddingXS,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        onChanged: ctrl.setQuery,
                        decoration: InputDecoration(
                          hintText: 'Нэр, утас эсвэл регистрээр хайх...',
                          prefixIcon: Icon(
                            Icons.search,
                            color: context.colors.textHint,
                          ),
                          suffixIcon: ctrl.listState is AsyncLoading
                              // Fixed box: AppLoading's Center would
                              // otherwise expand across the whole field and
                              // squeeze the typed text out of view.
                              ? const SizedBox.square(
                                  dimension: 48,
                                  child: AppLoading(size: 16),
                                )
                              : _ctrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _ctrl.clear();
                                    ctrl.setQuery('');
                                  },
                                )
                              : null,
                        ),
                        style: context.textStyles.body,
                      ),
                    ),
                    // Entry point for the P3-F7 broadcast surface — an
                    // imperative push (not a route: `lib/app/router.dart` is
                    // owned by the concurrent P3-F6 worker this cycle).
                    // Gated on the same permission the screen itself
                    // re-checks. The screen's own check is authoritative and
                    // the server is authoritative over both — this only stops
                    // staff without `customers.notify` being shown a control
                    // that leads to a refusal. Uses the `user ?? Authenticator`
                    // pattern the detail screens use, so tests inject a user
                    // rather than needing a live Hive box.
                    PermissionGate(
                      permission: 'customers.notify',
                      user: _user,
                      child: IconButton(
                        icon: const Icon(Icons.campaign_outlined),
                        tooltip: 'Зар мэдээ илгээх',
                        onPressed: () =>
                            AppNav.to(const CustomerBroadcastScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.paddingMD,
                ),
                child: Wrap(
                  spacing: 8,
                  children: [
                    FilterPill(
                      label: 'Бүгд',
                      selected: ctrl.kind == null,
                      onTap: () => ctrl.setKind(null),
                    ),
                    FilterPill(
                      label: 'Байгууллага',
                      selected: ctrl.kind == CustomerKindFilter.org,
                      onTap: () => ctrl.setKind(CustomerKindFilter.org),
                    ),
                    FilterPill(
                      label: 'Хувь хүн',
                      selected: ctrl.kind == CustomerKindFilter.person,
                      onTap: () => ctrl.setKind(CustomerKindFilter.person),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AsyncStateView<List<Customer>>(
                  state: ctrl.listState,
                  isEmpty: (value) => value.isEmpty,
                  empty: EmptyState(
                    message: ctrl.query.isEmpty
                        ? 'Үйлчлүүлэгч алга'
                        : 'Үйлчлүүлэгч олдсонгүй',
                    icon: Icons.person_search_outlined,
                  ),
                  onRetry: ctrl.refresh,
                  builder: (context, customers) => ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.paddingMD,
                      vertical: AppDimens.paddingXS,
                    ),
                    itemCount: customers.length + 1,
                    separatorBuilder: (context, i) =>
                        const SizedBox(height: AppDimens.paddingSM),
                    itemBuilder: (_, i) {
                      if (i == customers.length) {
                        return CustomerListFooter(
                          loadingMore: ctrl.loadingMore,
                          loadMoreError: ctrl.loadMoreError?.display,
                          hasNext: ctrl.hasNext,
                          total: ctrl.total,
                          onLoadMore: () => unawaited(ctrl.loadMore()),
                        );
                      }
                      final c = customers[i];
                      return CustomerCard(
                        customer: c,
                        onTap: () =>
                            AppNav.to(CustomerDetailScreen(customerId: c.id)),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
