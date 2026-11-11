import 'package:carservice_business/app/shell/shell_chrome.dart';
import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/core/widgets/adaptive/adaptive.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_screen.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:carservice_business/features/feedback/domain/feedback.dart';
import 'package:carservice_business/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:carservice_business/features/notifications/presentation/screens/notification_screen.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_list_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_list_screen.dart';
import 'package:carservice_business/features/overview/presentation/screens/home_screen.dart';
import 'package:carservice_business/features/profile/presentation/widgets/profile_identity_card.dart';
import 'package:carservice_business/features/shell/data/working_branch_repository.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';
import 'package:carservice_business/features/shell/presentation/screens/choose_branch_screen.dart';
import 'package:carservice_business/features/shell/presentation/widgets/working_branch_switcher.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

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
      icon: Icons.more_horiz_rounded,
      selectedIcon: Icons.more_horiz_rounded,
      label: 'Бусад',
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
            // Just the greeting; the branch switcher lives on Бусад.
            title: _ShellGreeting(user: user),
            // Pushed screens own a single app bar with the bell (D: shell
            // header only on top-level tabs; no branch switch mid-flow).
            showHeader: !ShellDepthTracker.instance.isSubPage(
              navigationShell.currentIndex,
            ),
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

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const groups = <_NavigationGroup>[
    _NavigationGroup('Үйлчлүүлэгчид', [
      _NavigationEntry(
        'Үйлчлүүлэгчид',
        Icons.people_outline,
        'customers',
        route: AppRoutes.customers,
      ),
      _NavigationEntry(
        'Машин',
        Icons.directions_car_outlined,
        'vehicles',
        route: AppRoutes.vehicles,
      ),
    ]),
    // D-164: Units ("Нэгж") and Categories ("Ангилал") management is
    // out of mobile scope — both stay owner-gated reference tables on the
    // web's Settings → System page. Their rows are removed here rather
    // than filled in; do not re-add them (see the Phase 4 entry state in
    // `TENANT_MOBILE_SLICES.md`). Хөдөлмөр/Бараа route into `/services`
    // with the corresponding kind preselected via the `type` query param
    // `_ServiceListRoute`/`ServiceListScreen.initialType` consume
    // (`lib/app/router.dart`, P4-F4).
    _NavigationGroup('Үйлчилгээ', [
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
      ),
    ]),
    // _NavigationGroup('Оношилгоо', [
    //   _NavigationEntry(
    //     'Түүх',
    //     Icons.assessment_outlined,
    //     'diagnostics',
    //     route: AppRoutes.diagnosticsReports,
    //   ),
    // ]),
    // P6-F5: the four rows below finally get real destinations. Gating
    // matches each screen's own in-screen gate exactly (D-163) — see each
    // route's registration in `lib/app/router.dart` and the screens'
    // "Not wired to a route" doc comments this slice resolves.
    _NavigationGroup('Ажилын хувиар', [
      _NavigationEntry(
        'Ажилтнууд',
        Icons.badge_outlined,
        'employees',
        route: AppRoutes.employees,
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
      ),
      _NavigationEntry(
        'Миний хуваарь',
        Icons.event_available_outlined,
        null,
        route: AppRoutes.mySchedule,
      ),
    ]),
    // Касс: register shifts and payment accounts — both `cash.manage`
    // (owner always), the permission every `/cash/sessions*` and
    // `/payment-accounts*` endpoint requires.
    _NavigationGroup('Касс', [
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
    ]),
    // P7-F4: the three rows below get real destinations. Тайлан and Санал
    // хүсэлт are visible to any authenticated user (D-174/D-176, matching
    // the web's `requireUser()`-only gate); Аудит stays gated on
    // `audit.view` via `canSeeView`'s existing 'audit' special-case.
    _NavigationGroup('Удирдлага', [
      _NavigationEntry(
        'Тайлан',
        Icons.bar_chart_outlined,
        null,
        route: AppRoutes.reports,
      ),
      _NavigationEntry(
        'Аудит',
        Icons.fact_check_outlined,
        'audit',
        route: AppRoutes.audit,
      ),
    ]),
    // Тохиргоо: the workshop's settings (owner only — the screen is
    // read-only for others, but the row stays owner-gated like the web's
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
  Widget build(BuildContext context) {
    final user = Authenticator.user;
    final unreadCount = context.watch<NotificationController>().unreadCount;

    // Full-screen, above the bottom navigation — like the group rows'
    // top-level routes.
    void open(String page) => AppNav.toNamed<void>(page);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Keep rows at a readable width on tablets instead of stretching
          // them across the whole content pane.
          final gutter = ((constraints.maxWidth - 640) / 2).clamp(
            20.0,
            double.infinity,
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
            children: [
              if (user != null)
                ProfileIdentityCard(
                  user: user,
                  onTap: () => open(AppPages.profile),
                  onEdit: () => AppNav.push<void>(AppRoutes.profileEdit),
                ),
              const _BranchRow(),
              for (final group in groups)
                _NavigationGroupView(group: group, user: user),
              _MoreSection(
                label: 'Апп',
                tiles: [
                  _MoreTile(
                    icon: Icons.notifications_none_rounded,
                    label: 'Мэдэгдэл',
                    trailing: unreadCount > 0
                        ? OpsPill(
                            unreadCount > 99 ? '99+' : '$unreadCount шинэ',
                            tone: OpsTone.accent,
                          )
                        : null,
                    // Back from the list, the count above shows what is left.
                    onTap: () =>
                        AppNav.toNamed<void>(AppPages.notifications).then((_) {
                          if (context.mounted) {
                            context.read<NotificationController>().load();
                          }
                        }),
                  ),
                  ?_AppearanceTile.maybe(context),
                ],
              ),
              _MoreSection(
                label: 'Тусламж',
                tiles: [
                  _MoreTile(
                    icon: Icons.menu_book_outlined,
                    label: 'Гарын авлага',
                    onTap: () => open(AppPages.help),
                  ),
                  _MoreTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Санал хүсэлт',
                    onTap: () => open(AppPages.feedback),
                  ),
                  _MoreTile(
                    icon: Icons.gavel_rounded,
                    label: 'Үйлчилгээний нөхцөл',
                    onTap: () => open(AppPages.terms),
                  ),
                  _MoreTile(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Нууцлалын бодлого',
                    onTap: () => open(AppPages.privacy),
                  ),
                  _MoreTile(
                    icon: Icons.info_outline_rounded,
                    label: 'Тухай',
                    onTap: () => open(AppPages.about),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _LogoutButton(onTap: () => _logout(context)),
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

class _NavigationGroupView extends StatelessWidget {
  const _NavigationGroupView({required this.group, required this.user});
  final _NavigationGroup group;
  final User? user;

  @override
  Widget build(BuildContext context) {
    final visible = group.entries
        .where((entry) => canSeeView(user, entry.permission))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return _MoreSection(
      label: group.label,
      tiles: [
        for (final entry in visible)
          _MoreTile(
            icon: entry.icon,
            label: entry.label,
            onTap: () {
              final route = entry.route;
              if (route != null) {
                AppNav.push(route);
              } else {
                _showUnavailable(context, entry);
              }
            },
          ),
      ],
    );
  }

  void _showUnavailable(BuildContext context, _NavigationEntry entry) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${entry.label}: удахгүй')));
  }
}

/// "Идэвхтэй салбар" card: the working scope and "Солих" (a sheet over the
/// same choices as the header switcher). Hidden outside the shell and when
/// there is nothing to switch — failed load or no branches; shows a spinner
/// while loading.
class _BranchRow extends StatelessWidget {
  const _BranchRow();

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
    final t = CarserviceTheme.of(context);
    final name = loading ? null : workingBranchLabel(branch);
    final canSwitch = !loading && !branch.isLocked;
    final controller = branch;
    return Padding(
      key: const ValueKey('more_branch_switcher'),
      padding: const EdgeInsets.only(top: 14),
      child: OpsCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: canSwitch
            ? () => showWorkingBranchSheet(context, controller)
            : null,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: OpsTone.accent.background(t),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.storefront_outlined,
                size: 18,
                color: OpsTone.accent.foreground(t),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Идэвхтэй салбар',
                    style: TextStyle(fontSize: 12, color: t.mutedText),
                  ),
                  const SizedBox(height: 2),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Text(
                      name ?? 'Сонгоогүй',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (canSwitch)
              Text(
                'Солих',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: t.accent,
                ),
              )
            else if (!loading)
              Tooltip(
                message: 'Өнөөдрийн хуваариар түгжигдсэн',
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: t.mutedText,
                ),
              ),
          ],
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

/// "Гарах" — a white card with the accent label, centred.
class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return OpsCard(
      key: const ValueKey('more_logout'),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Center(
          child: Text(
            'Гарах',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationGroup {
  const _NavigationGroup(this.label, this.entries);
  final String label;
  final List<_NavigationEntry> entries;
}

class _NavigationEntry {
  const _NavigationEntry(this.label, this.icon, this.permission, {this.route});
  final String label;
  final IconData icon;
  final String? permission;

  /// A `go_router` location to push instead of the "удахгүй" placeholder
  /// snackbar. `null` (the default, and every row outside Каталог today)
  /// keeps the pre-existing placeholder behaviour — added by `P4-F4`
  /// narrowly for the two rows it wires, not a blanket change to every
  /// `MoreScreen` entry.
  final String? route;
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
