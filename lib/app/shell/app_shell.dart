import 'dart:math' as math;

import 'package:carservice_business/app/shell/shell_chrome.dart';
import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/domain/subscription.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/core/widgets/adaptive/adaptive.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_screen.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:carservice_business/features/customers/data/customer_repository.dart'
    show RemoteCustomersRepository;
import 'package:carservice_business/features/customers/domain/customers_repository.dart'
    show CustomerListQuery;
import 'package:carservice_business/features/employees/data/employee_repository.dart'
    show RemoteEmployeesRepository;
import 'package:carservice_business/features/employees/domain/employees_repository.dart'
    show EmployeeListQuery;
import 'package:carservice_business/features/vehicles/data/vehicle_repository.dart'
    show RemoteVehiclesRepository;
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart'
    show VehicleListQuery;
import 'package:carservice_business/features/feedback/domain/feedback.dart';
import 'package:carservice_business/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:carservice_business/features/notifications/presentation/screens/notification_screen.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_list_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_list_screen.dart';
import 'package:carservice_business/features/overview/presentation/screens/home_screen.dart';
import 'package:carservice_business/features/shell/data/working_branch_repository.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';
import 'package:carservice_business/features/shell/presentation/screens/choose_branch_screen.dart';
import 'package:carservice_business/features/shell/presentation/widgets/working_branch_switcher.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:provider/provider.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  /// The only tab under the shell header (greeting, search, bell); the
  /// others open on their own page title, as on the design canvas.
  static const _todayIndex = 0;

  static const _destinations = [
    AdaptiveNavigationDestination(
      icon: Icons.today_outlined,
      selectedIcon: Icons.today_rounded,
      label: 'Өнөөдөр',
    ),
    AdaptiveNavigationDestination(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Захиалга',
    ),
    AdaptiveNavigationDestination(
      icon: Icons.event_outlined,
      selectedIcon: Icons.event_rounded,
      label: 'Цаг',
    ),
    AdaptiveNavigationDestination(
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      label: 'Меню',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<OrderController>(
          create: (context) =>
              OrderController(repo: context.read<OrdersRepository>()),
        ),
        // Detail routes receive the same list instance so successful detail
        // mutations can reload the active server query instead of creating a
        // second list with different filters or pagination.
        Provider<OrderListController>(
          create: (context) => context.read<OrderController>(),
        ),
        ChangeNotifierProvider(create: (_) => AppointmentController()),
        ChangeNotifierProvider(
          create: (context) {
            final orders = context.read<OrderController>();
            final appointments = context.read<AppointmentController>();

            Future<void> clearLegacyBranchFilters() async {
              // These controllers' setBranch methods reload immediately. Once
              // the validated X-Working-Branch header is active, retaining a
              // stale ?branchId= would make the API reject the request (422).
              await Future.wait([
                orders.setBranch(null),
                appointments.setBranch(null),
              ]);
            }

            return WorkingBranchController(
              repository: RemoteWorkingBranchRepository(),
              onSelectionChanged: clearLegacyBranchFilters,
              onInvalidation: clearLegacyBranchFilters,
            )..load();
          },
        ),
        ChangeNotifierProvider(create: (_) => NotificationController()..load()),
        ChangeNotifierProvider<ShellDepthTracker>.value(
          value: ShellDepthTracker.instance,
        ),
      ],
      child: Builder(
        builder: (shellContext) {
          final branch = shellContext.watch<WorkingBranchController>();
          if (branch.needsChoice) {
            AppNav.currentTab = null;
            return ChooseBranchScreen(
              controller: branch,
              user: Authenticator.user,
            );
          }
          // `AppNav.to` opens pages inside the tab on screen.
          AppNav.currentTab = navigationShell.currentIndex;
          final bottomNav = shellContext.watch<BottomNavController>();
          shellContext.watch<ShellDepthTracker>();
          final user = Authenticator.user;
          final destinations = [
            _destinations[0],
            _destinations[1].copyWith(enabled: canSeeView(user, 'orders')),
            // Always tappable: without the permission the tab explains
            // itself (AppointmentScreen's no-permission view).
            _destinations[2],
            _destinations[3],
          ];
          final onToday = navigationShell.currentIndex == _todayIndex;
          final subPage = ShellDepthTracker.instance.isSubPage(
            navigationShell.currentIndex,
          );
          final canSearch =
              canSeeView(user, 'customers') || canSeeView(user, 'vehicles');
          return AdaptiveScaffold(
            scaffoldKey: bottomNav.scaffoldKey,
            body: navigationShell,
            destinations: destinations,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) {
              bottomNav.setIndex(index);
              navigationShell.goBranch(index);
            },
            searchAction: canSearch
                ? OpsCircleButton(
                    icon: Icons.search_rounded,
                    tooltip: 'Хайлт',
                    onPressed: () => shellContext.push(AppRoutes.search),
                  )
                : null,
            // Just the greeting; the branch switcher lives on Меню.
            title: _ShellGreeting(user: user),
            // Pushed screens own a single app bar with the bell (D: shell
            // header only on top-level tabs; no branch switch mid-flow).
            showHeader: !subPage,
            // Tab roots scroll under the floating nav; pushed pages keep
            // their bottom bars above it.
            floatNavOverContent: !subPage,
            // Other tabs carry their own page title: an empty header drops
            // the greeting bar but, unlike `showHeader: false`, keeps the
            // content below the status bar.
            header: onToday ? null : const SizedBox.shrink(),
            notificationAction: _NotificationAction(
              unreadCount: shellContext
                  .watch<NotificationController>()
                  .unreadCount,
              onPressed: () => _openNotifications(shellContext),
            ),
          );
        },
      ),
    );
  }

  void _openNotifications(BuildContext context) {
    AppNav.to(const NotificationScreen()).then((_) {
      if (context.mounted) context.read<NotificationController>().load();
    });
  }
}

extension on AdaptiveNavigationDestination {
  AdaptiveNavigationDestination copyWith({bool? enabled}) =>
      AdaptiveNavigationDestination(
        label: label,
        icon: icon,
        selectedIcon: selectedIcon,
        enabled: enabled ?? this.enabled,
        tooltip: tooltip,
      );
}

/// Shell header text: today's date and a time-of-day greeting, after the
/// user's initials ("Даваа, 11-р сарын 9" / "Өглөөний мэнд, Бат").
class _ShellGreeting extends StatelessWidget {
  const _ShellGreeting({required this.user});
  final User? user;

  static const _weekdays = [
    'Даваа',
    'Мягмар',
    'Лхагва',
    'Пүрэв',
    'Баасан',
    'Бямба',
    'Ням',
  ];

  static String _greeting(int hour) {
    if (hour >= 5 && hour < 12) return 'Өглөөний мэнд';
    if (hour >= 12 && hour < 18) return 'Өдрийн мэнд';
    if (hour >= 18 && hour < 23) return 'Оройн мэнд';
    return 'Сайн байна уу';
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final now = DateTime.now();
    final user = this.user;
    final who = user?.firstName.trim() ?? '';
    final greeting = _greeting(now.hour);
    return Row(
      children: [
        if (user != null) ...[
          OpsAvatar(initials: opsInitials(user.firstName, user.lastName)),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_weekdays[now.weekday - 1]}, ${now.month}-р сарын ${now.day}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: t.mutedText),
              ),
              const SizedBox(height: 2),
              Text(
                who.isEmpty ? greeting : '$greeting, $who',
                key: const ValueKey('shell_greeting'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// «Меню», the large page title atop [MoreScreen] (the canvas board's).
class _MenuTitle extends StatelessWidget {
  const _MenuTitle();

  @override
  Widget build(BuildContext context) => Text(
    'Меню',
    key: const ValueKey('menu_title'),
    maxLines: 1,
    style: TextStyle(
      fontSize: 28,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: CarserviceTheme.of(context).ink,
    ),
  );
}

class _NotificationAction extends StatelessWidget {
  const _NotificationAction({
    required this.unreadCount,
    required this.onPressed,
  });
  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Badge(
      isLabelVisible: unreadCount > 0,
      label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
      backgroundColor: t.accentHi,
      textColor: Colors.white,
      offset: const Offset(-2, 2),
      child: OpsCircleButton(
        icon: Icons.notifications_none_rounded,
        tooltip: 'Мэдэгдэл',
        onPressed: onPressed,
      ),
    );
  }
}

/// The «Меню» tab (canvas board «Tenant app — Бусад (шинэчилсэн)»): its own
/// title with the bell and «Гарах» beside it, a navy identity card with the
/// working branch, a menu search, then each group as a grid of tinted tiles —
/// the customer pair as wide cards with their counts — and the app/help lists
/// below.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  static const groups = <_NavigationGroup>[
    _NavigationGroup('Үйлчлүүлэгч', wide: true, [
      _NavigationEntry(
        'Үйлчлүүлэгчид',
        Icons.people_outline,
        'customers',
        route: AppRoutes.customers,
        count: _MenuCount.customers,
      ),
      _NavigationEntry(
        'Машин',
        Icons.directions_car_outlined,
        'vehicles',
        route: AppRoutes.vehicles,
        count: _MenuCount.vehicles,
      ),
    ]),
    // D-164: Units ("Нэгж") and Categories ("Ангилал") stay on the web's
    // Settings → System page; do not re-add them. Ажил/Сэлбэг open
    // `/services` with the kind preselected via `type` (P4-F4).
    _NavigationGroup('Үйлчилгээ', tone: _MenuTone.accent, [
      _NavigationEntry(
        'Ажил/Үйлчилгээ',
        Icons.build_outlined,
        'services',
        route: '${AppRoutes.services}?type=labor',
      ),
      _NavigationEntry(
        'Сэлбэг/Бараа',
        Icons.inventory_2_outlined,
        'services',
        route: '${AppRoutes.services}?type=goods',
      ),
      _NavigationEntry(
        'Оношилгоо',
        Icons.description_outlined,
        'diagnostics',
        route: AppRoutes.diagnosticsTemplates,
        module: 'enable_diagnostics',
      ),
    ]),
    // Gating matches each screen's own in-screen gate (D-163).
    _NavigationGroup('Ажилтан', tone: _MenuTone.ok, [
      _NavigationEntry(
        'Ажилтнууд',
        Icons.badge_outlined,
        'employees',
        route: AppRoutes.employees,
        count: _MenuCount.employees,
      ),
      _NavigationEntry(
        'Эрхүүд',
        Icons.admin_panel_settings_outlined,
        'owner',
        route: AppRoutes.roles,
      ),
      _NavigationEntry(
        'Ажлын хуваарь',
        Icons.calendar_view_week_outlined,
        'employees',
        route: AppRoutes.schedules,
        module: 'enable_staff_schedule',
      ),
      _NavigationEntry(
        'Миний хуваарь',
        Icons.event_available_outlined,
        null,
        route: AppRoutes.mySchedule,
        module: 'enable_staff_schedule',
      ),
    ]),
    // Тайлан: any signed-in user (D-174); Касс rows: `cash.manage`, which
    // every `/cash/sessions*` and `/payment-accounts*` endpoint requires;
    // Аудит: `audit.view` via `canSeeView`'s 'audit' case.
    _NavigationGroup('Санхүү, тайлан', [
      _NavigationEntry(
        'Тайлан',
        Icons.bar_chart_outlined,
        null,
        route: AppRoutes.reports,
        module: 'enable_reports',
      ),
      _NavigationEntry(
        'Кассын ээлж',
        Icons.point_of_sale_outlined,
        'cash.manage',
        route: AppRoutes.cashShifts,
      ),
      _NavigationEntry(
        'Төлбөрийн данс',
        Icons.account_balance_outlined,
        'cash.manage',
        route: AppRoutes.paymentAccounts,
      ),
      _NavigationEntry(
        'Аудит',
        Icons.fact_check_outlined,
        'audit',
        route: AppRoutes.audit,
        module: 'enable_audit',
      ),
    ]),
    // The workshop's settings (owner only, like the web's
    // /dashboard/settings) and branch management (`branches.view`).
    _NavigationGroup('Тохиргоо', [
      _NavigationEntry(
        'Байгууллага',
        Icons.storefront_outlined,
        'owner',
        route: AppRoutes.organizationSettings,
      ),
      _NavigationEntry(
        'Салбарууд',
        Icons.store_mall_directory_outlined,
        'branches',
        route: AppRoutes.branches,
      ),
    ]),
  ];

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Map<_MenuCount, int> _counts = {};

  /// The plan's modules: entries outside it are hidden (their endpoints
  /// answer 403 `MODULE_DISABLED`). Until it loads, everything shows.
  SubscriptionStatus? _subscription = SubscriptionService.instance.cached;

  @override
  void initState() {
    super.initState();
    SubscriptionService.instance.getStatus().then((status) {
      if (status != null && mounted) setState(() => _subscription = status);
    });
    _searchCtrl.addListener(() {
      final query = _searchCtrl.text.trim();
      if (query != _query) setState(() => _query = query);
    });
    _loadCounts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Totals for the count badges: one `pageSize=1` list request each, only
  /// for entries the user can open. A failure just leaves the number off.
  Future<void> _loadCounts() async {
    final user = Authenticator.user;
    final wanted = {
      for (final group in MoreScreen.groups)
        for (final entry in group.entries)
          if (entry.count != null && canSeeView(user, entry.permission))
            entry.count!,
    };
    await Future.wait([
      for (final key in wanted)
        _fetchCount(key).then((total) {
          if (total != null && mounted) setState(() => _counts[key] = total);
        }),
    ]);
  }

  Future<int?> _fetchCount(_MenuCount key) async {
    try {
      switch (key) {
        case _MenuCount.customers:
          final result = await RemoteCustomersRepository().getCustomers(
            query: const CustomerListQuery(pageSize: 1),
          );
          if (result case Ok(:final value)) return value.pagination.total;
        case _MenuCount.vehicles:
          final result = await RemoteVehiclesRepository().getVehicles(
            query: const VehicleListQuery(pageSize: 1),
          );
          if (result case Ok(:final value)) return value.pagination.total;
        case _MenuCount.employees:
          final result = await RemoteEmployeesRepository().getEmployees(
            query: const EmployeeListQuery(pageSize: 1),
          );
          if (result case Ok(:final value)) return value.page.pagination.total;
      }
    } catch (_) {
      // A count is extra: no number rather than an error.
    }
    return null;
  }

  void _openEntry(_NavigationEntry entry) {
    final route = entry.route;
    if (route != null) {
      AppNav.push(route);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${entry.label}: удахгүй')));
    }
  }

  List<_MenuAction> _groupActions(_NavigationGroup group, User? user) => [
    for (final entry in group.entries)
      if (canSeeView(user, entry.permission) &&
          (_subscription?.allowsModule(entry.module) ?? true))
        _MenuAction(
          entry.label,
          entry.icon,
          () => _openEntry(entry),
          tone: group.tone,
          count: entry.count == null ? null : _counts[entry.count],
        ),
  ];

  void _openNotifications() {
    AppNav.to(const NotificationScreen()).then((_) {
      if (mounted) context.read<NotificationController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Authenticator.user;
    final unreadCount = context.watch<NotificationController>().unreadCount;

    // Full-screen, above the bottom navigation — like the group rows'
    // top-level routes.
    void open(String page) => AppNav.toNamed<void>(page);

    final help = [
      _MenuAction(
        'Гарын авлага',
        Icons.menu_book_outlined,
        () => open(AppPages.help),
      ),
      _MenuAction(
        'Санал хүсэлт',
        Icons.chat_bubble_outline_rounded,
        () => open(AppPages.feedback),
      ),
      _MenuAction(
        'Үйлчилгээний нөхцөл',
        Icons.gavel_rounded,
        () => open(AppPages.terms),
      ),
      _MenuAction(
        'Нууцлалын бодлого',
        Icons.privacy_tip_outlined,
        () => open(AppPages.privacy),
      ),
      _MenuAction(
        'Тухай',
        Icons.info_outline_rounded,
        () => open(AppPages.about),
      ),
    ];
    final notifications = _MenuAction(
      'Мэдэгдэл',
      Icons.notifications_none_rounded,
      _openNotifications,
    );

    final query = _query.toLowerCase();
    final results = query.isEmpty
        ? const <_MenuAction>[]
        : [
            for (final group in MoreScreen.groups)
              ..._groupActions(group, user),
            notifications,
            ...help,
          ].where((a) => a.label.toLowerCase().contains(query)).toList();

    return Scaffold(
      backgroundColor: context.colors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Keep content at a readable width on tablets instead of
          // stretching it across the whole content pane.
          final gutter = ((constraints.maxWidth - 640) / 2).clamp(
            20.0,
            double.infinity,
          );
          return ListView(
            // Bottom: room for the floating nav the page runs under.
            padding: EdgeInsets.fromLTRB(
              gutter,
              12,
              gutter,
              32 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Row(
                children: [
                  const Expanded(child: _MenuTitle()),
                  _NotificationAction(
                    unreadCount: unreadCount,
                    onPressed: _openNotifications,
                  ),
                  const SizedBox(width: 8),
                  OpsCircleButton(
                    key: const ValueKey('more_logout'),
                    icon: Icons.logout_rounded,
                    tooltip: 'Гарах',
                    onPressed: () => _logout(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (user != null) ...[
                _MenuIdentityCard(
                  user: user,
                  onOpenProfile: () => open(AppPages.profile),
                ),
                const SizedBox(height: 12),
              ],
              _MenuSearchField(controller: _searchCtrl),
              if (query.isNotEmpty && results.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Олдсонгүй',
                    key: const ValueKey('menu_search_empty'),
                    textAlign: TextAlign.center,
                    style: context.textStyles.caption,
                  ),
                )
              else if (query.isNotEmpty)
                _MenuGroupView(label: 'Илэрц', actions: results)
              else ...[
                for (final group in MoreScreen.groups)
                  if (_groupActions(group, user) case final actions
                      when actions.isNotEmpty)
                    _MenuGroupView(
                      label: group.label,
                      actions: actions,
                      wide: group.wide,
                    ),
                _MoreSection(
                  label: 'Апп',
                  tiles: [
                    _MoreTile(
                      icon: notifications.icon,
                      label: notifications.label,
                      trailing: unreadCount > 0
                          ? OpsPill(
                              unreadCount > 99 ? '99+' : '$unreadCount шинэ',
                              tone: OpsTone.accent,
                            )
                          : null,
                      // Back from the list, the count above shows what is left.
                      onTap: notifications.onTap,
                    ),
                    ?_AppearanceTile.maybe(context),
                  ],
                ),
                _MoreSection(
                  label: 'Тусламж',
                  tiles: [
                    for (final action in help)
                      _MoreTile(
                        icon: action.icon,
                        label: action.label,
                        onTap: action.onTap,
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await ConfirmSheet.show(
      context,
      title: 'Гарах уу?',
      message: 'Та системээс гарахдаа итгэлтэй байна уу?',
      confirmLabel: 'Гарах',
      icon: Icons.logout_rounded,
      isDangerous: true,
    );
    if (ok && context.mounted) context.read<AuthController>().logout();
  }
}

/// One tappable menu item, from a group entry or an app/help row; the
/// search lists them all in one grid.
class _MenuAction {
  const _MenuAction(
    this.label,
    this.icon,
    this.onTap, {
    this.tone = _MenuTone.navy,
    this.count,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final _MenuTone tone;
  final int? count;
}

/// Icon tint of a menu group, from the canvas: navy (customers, finance,
/// settings), accent (services), green (staff).
enum _MenuTone { navy, accent, ok }

extension on _MenuTone {
  Color background(CarserviceTheme t) => switch (this) {
    _MenuTone.navy => Color.alphaBlend(t.ink.withValues(alpha: 0.1), t.panel),
    _MenuTone.accent => OpsTone.accent.background(t),
    _MenuTone.ok => OpsTone.ok.background(t),
  };

  Color foreground(CarserviceTheme t) => switch (this) {
    _MenuTone.navy => t.ink,
    _MenuTone.accent => t.accent,
    _MenuTone.ok => t.ok,
  };
}

/// Which total a menu entry shows.
enum _MenuCount { customers, vehicles, employees }

/// A mono section label over its actions: wide two-column cards for the
/// customer pair, a grid of tiles otherwise.
class _MenuGroupView extends StatelessWidget {
  const _MenuGroupView({
    required this.label,
    required this.actions,
    this.wide = false,
  });
  final String label;
  final List<_MenuAction> actions;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: OpsSectionLabel(label),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // Height follows the text scale so large text doesn't overflow
            // (+4 slack for line-height rounding). Tile columns keep a tile
            // ~100 logical px wide per text scale, so a word like
            // «Байгууллага» isn't split mid-word: 3 on a phone, 2 on a
            // narrow one or with large text, up to 4 on a tablet.
            final text = MediaQuery.textScalerOf(context).scale(13);
            final columns = wide
                ? 2
                : ((constraints.maxWidth + 10) / (100 * text / 13 + 10))
                      .floor()
                      .clamp(2, 4);
            final extent = wide
                ? math.max(104.0, 14 + 42 + 8 + text / 13 * 14 * 1.3 + 14 + 4)
                : math.max(104.0, 12 + 42 + 8 + text * 1.3 * 2 + 12 + 4);
            return GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: extent,
              ),
              children: [
                for (final action in actions)
                  wide
                      ? _MenuWideCard(action: action)
                      : _MenuTile(action: action),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The group-tinted rounded icon square of a menu item.
class _MenuIcon extends StatelessWidget {
  const _MenuIcon({required this.icon, required this.tone});
  final IconData icon;
  final _MenuTone tone;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: tone.background(t),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, size: 21, color: tone.foreground(t)),
    );
  }
}

final _countFormat = NumberFormat('#,##0', 'en_US');

/// One menu item in a grid: tinted icon over a centred label of up to two
/// lines, an optional count badge in the corner.
class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.action});
  final _MenuAction action;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final count = action.count;
    return Semantics(
      button: true,
      child: OpsCard(
        radius: 18,
        padding: EdgeInsets.zero,
        onTap: action.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MenuIcon(icon: action.icon, tone: action.tone),
                  const SizedBox(height: 8),
                  Flexible(
                    child: Text(
                      action.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: t.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (count != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: t.shellBackground,
                    borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                  ),
                  child: Text(
                    _countFormat.format(count),
                    style: opsMono(
                      context,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: t.mutedText,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A customer-group card: tinted icon and big mono total on top, the label
/// at the bottom. The total is left off until it loads (or if it fails).
class _MenuWideCard extends StatelessWidget {
  const _MenuWideCard({required this.action});
  final _MenuAction action;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final count = action.count;
    return Semantics(
      button: true,
      child: OpsCard(
        radius: 18,
        padding: const EdgeInsets.all(14),
        onTap: action.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MenuIcon(icon: action.icon, tone: action.tone),
                const SizedBox(width: 8),
                // Kept within the icon's height: with large text the total
                // shrinks instead of pushing the label out of the card.
                if (count != null)
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topRight,
                        child: Text(
                          _countFormat.format(count),
                          maxLines: 1,
                          style: opsMono(
                            context,
                            fontSize: 26,
                            fontWeight: FontWeight.w500,
                            color: t.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: t.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The navy card at the top of Меню: who is signed in (opens the profile)
/// and, in a darker strip below, the working branch with «Солих».
class _MenuIdentityCard extends StatelessWidget {
  const _MenuIdentityCard({required this.user, required this.onOpenProfile});
  final User user;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final role = user.role?.name ?? (user.isOwner ? 'Эзэмшигч' : 'Ажилтан');
    final tenant = user.tenant.name.trim();
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    return Material(
      color: OpsDark.bg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('menu_profile'),
            onTap: onOpenProfile,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  OpsAvatar(
                    initials: opsInitials(user.firstName, user.lastName),
                    size: 46,
                    onDark: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: OpsDark.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [role, if (tenant.isNotEmpty) tenant].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: OpsDark.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: OpsDark.muted2,
                  ),
                ],
              ),
            ),
          ),
          const _MenuBranchStrip(),
        ],
      ),
    );
  }
}

/// The working branch and «Солих» (a sheet over the same choices as the
/// header switcher). Hidden outside the shell and when there is nothing to
/// switch — failed load or no branches; a spinner while loading; a lock
/// while today's schedule pins the branch.
class _MenuBranchStrip extends StatelessWidget {
  const _MenuBranchStrip();

  @override
  Widget build(BuildContext context) {
    WorkingBranchController? branch;
    try {
      branch = context.watch<WorkingBranchController>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final loading =
        branch.state == WorkingBranchLoadState.initial || branch.isLoading;
    if (!loading && (branch.hasError || branch.options.branches.isEmpty)) {
      return const SizedBox.shrink();
    }
    final name = loading ? null : workingBranchLabel(branch);
    final canSwitch = !loading && !branch.isLocked;
    final controller = branch;
    return Material(
      color: OpsColors.lightInk2,
      child: InkWell(
        key: const ValueKey('more_branch_switcher'),
        onTap: canSwitch
            ? () => showWorkingBranchSheet(context, controller)
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  size: 17,
                  color: OpsDark.muted2,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: loading
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: OpsDark.ink,
                            ),
                          ),
                        )
                      : Text(
                          name ?? 'Салбар сонгоогүй',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: OpsDark.ink,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                if (canSwitch)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: OpsDark.accent,
                      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                    ),
                    child: const Text(
                      'Солих',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  )
                else if (!loading)
                  const Tooltip(
                    message: 'Өнөөдрийн хуваариар түгжигдсэн',
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: OpsDark.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Цэснээс хайх»: filters every menu item by its label.
class _MenuSearchField extends StatelessWidget {
  const _MenuSearchField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return TextField(
      key: const ValueKey('menu_search'),
      controller: controller,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 15, color: t.ink),
      decoration: InputDecoration(
        hintText: 'Цэснээс хайх',
        hintStyle: TextStyle(fontSize: 15, color: t.mutedText),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: t.mutedText),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Арилгах',
                icon: Icon(Icons.close_rounded, size: 18, color: t.mutedText),
                onPressed: controller.clear,
              ),
        filled: true,
        fillColor: t.borderSubtle,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: t.ink, width: 1.2),
        ),
      ),
    );
  }
}

/// "Харагдах байдал" with the current mode; a sheet picks another. Null
/// when no [ThemeProvider] is in scope (isolated tests).
class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile();

  static Widget? maybe(BuildContext context) {
    try {
      context.watch<ThemeProvider>();
    } on ProviderNotFoundException {
      return null;
    }
    return const _AppearanceTile();
  }

  static const _labels = {
    ThemeMode.system: 'Системийн',
    ThemeMode.light: 'Цайвар',
    ThemeMode.dark: 'Бараан',
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return _MoreTile(
      icon: Icons.dark_mode_outlined,
      label: 'Харагдах байдал',
      value: _labels[theme.mode],
      onTap: () => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final MapEntry(key: mode, value: label) in _labels.entries)
                ListTile(
                  title: Text(label),
                  trailing: mode == theme.mode
                      ? Icon(
                          Icons.check_rounded,
                          color: CarserviceTheme.of(sheetContext).accent,
                        )
                      : null,
                  onTap: () {
                    theme.setMode(mode);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A mono section label over one white group of [_MoreTile]s with
/// hairlines between them (the design's settings groups).
class _MoreSection extends StatelessWidget {
  const _MoreSection({required this.label, required this.tiles});
  final String label;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: OpsSectionLabel(label),
        ),
        OpsGroup(children: tiles),
      ],
    );
  }
}

/// One settings row: neutral icon tile, title, optional value / trailing,
/// chevron. A [ListTile] underneath, for semantics and the router tests.
class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return ListTile(
      onTap: onTap,
      minTileHeight: 50,
      contentPadding: const EdgeInsets.only(left: 14, right: 10),
      horizontalTitleGap: 12,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: t.shellBackground,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: t.ink),
      ),
      title: Text(label, style: TextStyle(fontSize: 15, color: t.ink)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value!, style: TextStyle(fontSize: 13, color: t.mutedText)),
          ?trailing,
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: t.mutedText3),
        ],
      ),
    );
  }
}

class _NavigationGroup {
  const _NavigationGroup(
    this.label,
    this.entries, {
    this.tone = _MenuTone.navy,
    this.wide = false,
  });
  final String label;
  final List<_NavigationEntry> entries;

  /// Icon tint of the group's tiles.
  final _MenuTone tone;

  /// Two wide cards with totals (the customer pair) instead of tiles.
  final bool wide;
}

class _NavigationEntry {
  const _NavigationEntry(
    this.label,
    this.icon,
    this.permission, {
    this.route,
    this.count,
    this.module,
  });
  final String label;
  final IconData icon;
  final String? permission;

  /// Plan module the screen needs (`enable_reports` …); null = core.
  final String? module;

  /// A `go_router` location to push; `null` shows the "удахгүй" snackbar.
  final String? route;

  /// The total shown on the item, when it has one.
  final _MenuCount? count;
}

class SubscriptionLockedScreen extends StatelessWidget {
  const SubscriptionLockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 56,
                  color: context.colors.danger,
                ),
                const SizedBox(height: 16),
                Text(
                  'Захиалга идэвхгүй байна',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Байгууллагын захиалга дуусгавар болсон тул үргэлжлүүлэхийн тулд админтайгаа холбогдоно уу.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => context.read<AuthController>().logout(),
                  child: const Text('Гарах'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
