import 'package:carservice_business/app/shell/shell_chrome.dart';
import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/core/widgets/adaptive/adaptive.dart';
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
            return ChooseBranchScreen(controller: branch);
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
                ? IconButton(
                    tooltip: 'Хайлт',
                    onPressed: () => shellContext.push(AppRoutes.search),
                    icon: const Icon(Icons.search_rounded),
                  )
                : null,
            // Just the greeting; the branch switcher lives on Бусад.
            title: _ShellGreeting(name: user?.firstName),
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

class _ShellGreeting extends StatelessWidget {
  const _ShellGreeting({required this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final who = name?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        who == null || who.isEmpty ? 'Сайн байна уу' : 'Сайн байна уу, $who',
        key: const ValueKey('shell_greeting'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textStyles.h3,
      ),
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
    return Badge(
      isLabelVisible: unreadCount > 0,
      label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
      child: IconButton(
        tooltip: 'Мэдэгдэл',
        onPressed: onPressed,
        icon: const Icon(Icons.notifications_none_rounded),
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
    // Салбарууд / Тохиргоо had no mobile screen (placeholder snackbar only)
    // and were removed with the duplicate Каталог → Оношилгоо row, which
    // pointed at the same route as Оношилгоо → Загвар.
  ];

  @override
  Widget build(BuildContext context) {
    final user = Authenticator.user;
    final unreadCount = context.watch<NotificationController>().unreadCount;
    // Work groups cycle through the theme's accent tones; the general app
    // rows stay neutral so the two kinds read apart at a glance.
    final tones = [
      context.colors.accent,
      context.colors.good,
      context.colors.warning,
    ];
    final neutral = context.colors.textSecondary;

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
            16.0,
            double.infinity,
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
            children: [
              if (user != null)
                _ProfileCard(user: user, onTap: () => open(AppPages.profile)),
              for (final (i, group) in groups.indexed)
                _NavigationGroupView(
                  group: group,
                  user: user,
                  tone: tones[i % tones.length],
                ),
              _MoreSection(
                label: 'Ерөнхий',
                tiles: [
                  _MoreTile(
                    icon: Icons.notifications_none_rounded,
                    label: 'Мэдэгдэл',
                    tone: neutral,
                    trailing: unreadCount > 0
                        ? Badge(
                            label: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                            ),
                          )
                        : null,
                    // Back from the list, the badge above shows what is left.
                    onTap: () =>
                        AppNav.toNamed<void>(AppPages.notifications).then((_) {
                          if (context.mounted)
                            context.read<NotificationController>().load();
                        }),
                  ),
                  _MoreTile(
                    icon: Icons.feedback_outlined,
                    label: 'Санал хүсэлт',
                    tone: neutral,
                    onTap: () => open(AppPages.feedback),
                  ),
                  _MoreTile(
                    icon: Icons.menu_book_outlined,
                    label: 'Гарын авлага',
                    tone: neutral,
                    onTap: () => open(AppPages.help),
                  ),
                  _MoreTile(
                    icon: Icons.gavel_rounded,
                    label: 'Үйлчилгээний нөхцөл',
                    tone: neutral,
                    onTap: () => open(AppPages.terms),
                  ),
                  _MoreTile(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Нууцлалын бодлого',
                    tone: neutral,
                    onTap: () => open(AppPages.privacy),
                  ),
                  _MoreTile(
                    icon: Icons.info_outline_rounded,
                    label: 'Тухай',
                    tone: neutral,
                    onTap: () => open(AppPages.about),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Panel(
                child: _MoreTile(
                  icon: Icons.logout_rounded,
                  label: 'Гарах',
                  tone: context.colors.danger,
                  destructive: true,
                  onTap: () => _logout(context),
                ),
              ),
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
  const _NavigationGroupView({
    required this.group,
    required this.user,
    required this.tone,
  });
  final _NavigationGroup group;
  final User? user;
  final Color tone;

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
            tone: tone,
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

/// The flat bordered surface every MoreScreen block sits on — same panel
/// treatment as the Today board (1px border, no shadow).
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.cardBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        side: BorderSide(color: context.colors.divider),
      ),
      child: child,
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.onTap});
  final User user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final role = user.role?.name ?? (user.isOwner ? 'Эзэмшигч' : 'Ажилтан');
    WorkingBranchController? branch;
    try {
      branch = context.watch<WorkingBranchController>();
    } on ProviderNotFoundException {
      // Outside the shell (isolated tests): no branch row.
    }
    // Hidden when there is nothing to switch — failed load or no branches;
    // shown (with its spinner) while loading.
    final showBranch =
        branch != null &&
        (branch.state == WorkingBranchLoadState.initial ||
            branch.isLoading ||
            (!branch.hasError && branch.options.branches.isNotEmpty));
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.paddingMD),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: context.colors.accent,
                    child: Text(
                      user.firstName.isNotEmpty ? user.firstName[0] : '?',
                      style: TextStyle(
                        fontSize: 20,
                        color: CarserviceTheme.of(context).onAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          style: context.textStyles.h3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            role,
                            user.tenant.name,
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: context.textStyles.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.textHint,
                  ),
                ],
              ),
            ),
          ),
          if (showBranch) ...[
            Divider(height: 1, color: context.colors.divider),
            Padding(
              key: const ValueKey('more_branch_switcher'),
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 20,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text('Салбар', style: context.textStyles.bodyMedium),
                  const SizedBox(width: 12),
                  // Right-aligned; long branch names ellipsize inside.
                  Expanded(
                    child: WorkingBranchSwitcher(
                      controller: branch,
                      expanded: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labelled group of [_MoreTile]s in one panel, separated by hairlines
/// that start under the label text rather than the icon.
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
          child: Text(label.toUpperCase(), style: context.textStyles.label),
        ),
        _Panel(
          child: Column(
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0)
                  Divider(height: 1, indent: 66, color: context.colors.divider),
                tile,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onTap;
  final Widget? trailing;

  /// Colours the label with [tone] and drops the chevron — an action, not
  /// a destination.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      minVerticalPadding: 10,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        ),
        child: Icon(icon, size: AppDimens.iconMD, color: tone),
      ),
      title: Text(
        label,
        style: context.textStyles.bodyMedium.copyWith(
          color: destructive ? tone : null,
          fontWeight: destructive ? FontWeight.w600 : null,
        ),
      ),
      trailing: destructive
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.colors.textHint,
                ),
              ],
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
