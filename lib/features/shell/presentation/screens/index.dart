import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:carservice_business/features/notifications/presentation/screens/notification_screen.dart';
import 'package:carservice_business/features/settings/presentation/screens/about_screen.dart';
import 'package:carservice_business/features/settings/presentation/screens/help_screen.dart';
import 'package:carservice_business/features/profile/presentation/screens/profile_screen.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_screen.dart';
import 'package:carservice_business/features/history/presentation/screens/history_screen.dart';
import 'package:carservice_business/features/overview/presentation/screens/home_screen.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_list_screen.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class IndexScreen extends StatelessWidget {
  const IndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) =>
              OrderController(repo: context.read<OrdersRepository>()),
        ),
        ChangeNotifierProvider(create: (_) => AppointmentController()),
        ChangeNotifierProvider(create: (_) => NotificationController()..load()),
      ],
      child: const _MainShell(),
    );
  }
}

class _MainShell extends StatelessWidget {
  const _MainShell();

  @override
  Widget build(BuildContext context) {
    final navProv = context.watch<BottomNavController>();

    return Scaffold(
      key: navProv.scaffoldKey,
      // index: 0=Нүүр 1=Захиалга 2=Цаг 3=Жагсаалт
      body: IndexedStack(
        index: navProv.index,
        children: const [
          HomeScreen(),
          OrderListScreen(),
          AppointmentScreen(),
          HistoryScreen(),
        ],
      ),
      drawer: _AppDrawer(
        currentIndex: navProv.index,
        onTap: navProv.setIndex,
        unreadCount: context.watch<NotificationController>().unreadCount,
      ),
    );
  }
}

// ─── App Drawer ───────────────────────────────────────────────────────────────

class _AppDrawer extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;
  final int unreadCount;
  const _AppDrawer({
    required this.currentIndex,
    required this.onTap,
    required this.unreadCount,
  });

  // static const _navItems = [
  //   (icon: Icons.home_rounded, label: 'Нүүр', index: 0),
  //   (icon: Icons.receipt_long_rounded, label: 'Захиалга', index: 1),
  //   (icon: Icons.event_rounded, label: 'Цаг захиалга', index: 2),
  //   (icon: Icons.list_alt_rounded, label: 'Жагсаалт', index: 3),
  // ];

  static const _settingsItems = [
    (icon: Icons.notifications_none_rounded, label: 'Мэдэгдэл'),
    (icon: Icons.language_rounded, label: 'Хэл'),
    (icon: Icons.help_outline_rounded, label: 'Тусламж'),
    (icon: Icons.info_outline_rounded, label: 'Тухай'),
  ];

  void _onSettingsTap(BuildContext context, String label) {
    AppNav.back(); // close drawer
    switch (label) {
      case 'Мэдэгдэл':
        AppNav.to(const NotificationScreen()).then((_) {
          if (context.mounted) context.read<NotificationController>().load();
        });
      case 'Тусламж':
        AppNav.to(const HelpScreen());
      case 'Тухай':
        AppNav.to(const AboutScreen());
      case 'Хэл':
        messageWarning('Одоогоор зөвхөн монгол хэл дэмжигдэнэ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Authenticator.user;

    return Drawer(
      backgroundColor: context.colors.surface,
      child: Column(
        children: [
          if (user != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AppNav.back();
                AppNav.to(const ProfileScreen());
              },
              child: _UserHeader(user: user),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                // ── Navigation ──────────────────────────────────────────
                // _DrawerSectionLabel('Үндсэн цэс'),
                // ..._navItems.map((item) {
                //   final isActive = item.index == currentIndex;
                //   return Padding(
                //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                //     child: ListTile(
                //       leading: Icon(
                //         item.icon,
                //         color: isActive ? context.colors.accent : context.colors.textSecondary,
                //         size: 22,
                //       ),
                //       title: Text(
                //         item.label,
                //         style: TextStyle(
                //           color: isActive ? context.colors.accent : context.colors.textPrimary,
                //           fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                //           fontSize: 15,
                //         ),
                //       ),
                //       selected: isActive,
                //       selectedTileColor: context.colors.accent.withOpacity(0.08),
                //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusMD)),
                //       onTap: () => onTap(item.index),
                //     ),
                //   );
                // }),
                const SizedBox(height: 8),
                const Divider(height: 1, indent: 16, endIndent: 16),
                const SizedBox(height: 8),

                // ── Settings ─────────────────────────────────────────────
                _DrawerSectionLabel('Тохиргоо'),
                ..._settingsItems.map((item) {
                  final isNotif = item.label == 'Мэдэгдэл';
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: ListTile(
                      leading: Icon(
                        item.icon,
                        color: context.colors.textSecondary,
                        size: 22,
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      trailing: isNotif && unreadCount > 0
                          ? _Badge(count: unreadCount)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                      ),
                      onTap: () => _onSettingsTap(context, item.label),
                    ),
                  );
                }),
              ],
            ),
          ),

          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: Icon(Icons.logout, color: context.colors.danger),
              title: Text(
                'Гарах',
                style: TextStyle(color: context.colors.danger),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusMD),
              ),
              onTap: () async {
                final ok = await ConfirmSheet.show(
                  context,
                  title: 'Гарах уу?',
                  message: 'Та системээс гарахдаа итгэлтэй байна уу?',
                  confirmLabel: 'Гарах',
                  icon: Icons.logout_rounded,
                  isDangerous: true,
                );
                if (ok && context.mounted) {
                  context.read<AuthController>().logout();
                }
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  final String label;
  const _DrawerSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.colors.textHint,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Badge ────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.danger,
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: CarserviceTheme.of(context).onAccent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─── User header ──────────────────────────────────────────────────────────────

class _UserHeader extends StatelessWidget {
  final User user;
  const _UserHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: context.colors.brandSurface,
      padding: EdgeInsets.fromLTRB(20, top + 24, 20, 24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: context.colors.accent,
            child: Text(
              user.firstName[0],
              style: TextStyle(
                fontSize: 22,
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
                  style: TextStyle(
                    color: CarserviceTheme.of(context).onAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: TextStyle(
                    color: CarserviceTheme.of(context).onAccent
                        .withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: CarserviceTheme.of(context).onAccent
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                  ),
                  child: Text(
                    user.role?.name ??
                        (user.isOwner ? 'Эзэмшигч' : 'Хэрэглэгч'),
                    style: TextStyle(
                      color: CarserviceTheme.of(context).onAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
