import 'package:carservice_business/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_screen.dart';
import 'package:carservice_business/features/notifications/presentation/screens/notification_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/subscription.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/overview/domain/overview.dart';
import 'package:carservice_business/features/overview/domain/overview_repository.dart';
import 'package:carservice_business/features/overview/data/overview_repository.dart';
import 'package:carservice_business/features/profile/presentation/screens/profile_screen.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:carservice_business/features/history/presentation/screens/history_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/new_inspection_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/report_detail_screen.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_list_screen.dart';
import 'package:carservice_business/features/shell/presentation/screens/search_screen.dart';
import 'package:carservice_business/core/widgets/cards/inspection_cards.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.overviewRepository});

  /// Test/DI seam for the `GET /overview` stats — D-177. Defaults to
  /// [RemoteOverviewRepository] when not injected, matching every other
  /// screen's `repository`-parameter precedent in this app.
  final OverviewRepository? overviewRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SubscriptionStatus? _sub;
  late final OverviewRepository _overviewRepository =
      widget.overviewRepository ?? RemoteOverviewRepository();
  Overview? _overview;
  bool _overviewLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InspectionController>().loadReports();
    });
    _loadSubscription();
    _loadOverview();
  }

  Future<void> _loadSubscription() async {
    final sub = await SubscriptionService.instance.getStatus();
    if (mounted) setState(() => _sub = sub);
  }

  /// D-177: home stats come from `GET /overview`, not from whatever the
  /// order/diagnostics controllers happen to have loaded locally. A failed
  /// or slow fetch must not block or crash the rest of the screen — the
  /// stat cards fall back to a dash and every other section renders exactly
  /// as it does today.
  Future<void> _loadOverview() async {
    final result = await _overviewRepository.getOverview();
    if (!mounted) return;
    setState(() {
      _overviewLoading = false;
      if (result is Ok<Overview>) _overview = result.value;
    });
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Өглөөний мэнд';
    if (h < 18) return 'Өдрийн мэнд';
    return 'Оройн мэнд';
  }

  String get _dateStr {
    const weekdays = [
      'Ням',
      'Даваа',
      'Мягмар',
      'Лхагва',
      'Пүрэв',
      'Баасан',
      'Бямба',
    ];
    const months = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      '11',
      '12',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday % 7]}, ${now.year} оны ${months[now.month - 1]}-р сарын ${now.day}';
  }

  void _pushNewInspection() {
    AppNav.to(
      ChangeNotifierProvider(
        create: (_) => NewInspectionController(),
        child: const NewInspectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insProv = context.watch<InspectionController>();
    final user = Authenticator.user;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Column(
        children: [
          // ─── Scrollable content ──────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: insProv.loadReports,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                children: [
                  // The shell header owns menu/search/notifications; this is
                  // only the day context, so there is a single header.
                  _Greeting(
                    greeting: _greeting,
                    name: user?.firstName ?? 'Хэрэглэгч',
                    dateStr: _dateStr,
                  ),
                  const SizedBox(height: 16),
                  // ─── Subscription warning ────────────────────────────────
                  if (_sub != null && _sub!.needsAttention) ...[
                    SubscriptionBanner(
                      sub: _sub!,
                      onTap: () => AppNav.to(const ProfileScreen()),
                    ),
                    SizedBox(height: 16),
                  ],

                  // ─── Stats row — GET /overview (D-177) ────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          count: _overview?.counts.todayOrders,
                          loading: _overviewLoading,
                          label: 'Өнөөдрийн\nзасварын хуудас',
                          icon: Icons.receipt_long_outlined,
                          color: context.colors.good,
                          bgColor: context.colors.goodBg,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          count: _overview?.counts.openOrders,
                          loading: _overviewLoading,
                          label: 'Нээлттэй\nзасварын хуудас',
                          icon: Icons.pending_actions_outlined,
                          color: context.colors.accent,
                          bgColor: context.colors.accent.withOpacity(0.12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ─── Menu ──────────────────────────────────────────────
                  Text('Цэс', style: context.textStyles.h3),
                  const SizedBox(height: 10),
                  _MenuSection(
                    items: [
                      _MenuEntry(
                        icon: Icons.add_circle_outline_rounded,
                        color: context.colors.accent,
                        label: 'Шинэ оношилгоо',
                        subtitle: 'Тээврийн хэрэгсэл бүртгэх',
                        onTap: _pushNewInspection,
                      ),
                      _MenuEntry(
                        icon: Icons.receipt_long_rounded,
                        color: context.colors.good,
                        label: 'Засварын хуудсууд',
                        subtitle: 'Үйлчилгээний засварын хуудас харах',
                        onTap: () {
                          final ctrl = context.read<OrderController>();
                          AppNav.to(
                            ChangeNotifierProvider.value(
                              value: ctrl,
                              child: const OrderListScreen(),
                            ),
                          );
                        },
                      ),
                      _MenuEntry(
                        icon: Icons.person_search_rounded,
                        color: context.colors.warning,
                        label: 'Үйлчлүүлэгч хайх',
                        subtitle: 'Нэр, утас, дугаараар хайх',
                        onTap: () => AppNav.to(const SearchScreen()),
                      ),
                      _MenuEntry(
                        icon: Icons.build_circle_rounded,
                        color: CarserviceTheme.of(context).accentHi,
                        label: 'Үйлчилгээ',
                        subtitle: 'Үнийн жагсаалт удирдах',
                        onTap: () => AppNav.push(AppRoutes.services),
                      ),
                      _MenuEntry(
                        icon: Icons.event_rounded,
                        color: context.colors.accent,
                        label: 'Цаг захиалга',
                        subtitle: 'Өнөөдрийн цаг захиалга харах',
                        // Its own tab: the screen is a tab root with no
                        // app bar, so it is switched to, not pushed.
                        onTap: () => AppNav.go(AppRoutes.appointments),
                      ),
                      _MenuEntry(
                        icon: Icons.insights_rounded,
                        color: context.colors.danger,
                        label: 'Тайлан',
                        subtitle: 'Орлого, засварын хуудасны тайлан харах',
                        onTap: () => AppNav.push(AppRoutes.reports),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ─── Recent inspections ────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Сүүлийн бүртгэлүүд', style: context.textStyles.h3),
                      TextButton(
                        onPressed: () => AppNav.to(const HistoryScreen()),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Бүгдийг харах',
                          style: context.textStyles.caption.copyWith(
                            color: context.colors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (insProv.loading)
                    const Center(child: CircularProgressIndicator())
                  else if (insProv.reports.isEmpty)
                    const EmptyState(
                      message: 'Оношилгооны бүртгэл байхгүй',
                      icon: Icons.inventory_2_outlined,
                    )
                  else
                    ...insProv.reports
                        .take(5)
                        .map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ReportListCard(
                              report: r,
                              onTap: () =>
                                  AppNav.to(ReportDetailScreen(reportId: r.id)),
                            ),
                          ),
                        ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Subscription banner ────────────────────────────────────────────────────────

class SubscriptionBanner extends StatelessWidget {
  final SubscriptionStatus sub;
  final VoidCallback onTap;
  const SubscriptionBanner({super.key, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final locked = sub.locked;
    final color = locked ? context.colors.danger : context.colors.warning;
    final bg = locked ? context.colors.dangerBg : context.colors.warningBg;
    final title = locked
        ? 'Захиалгын багц хаагдсан'
        : 'Захиалгын багц удахгүй дуусна';
    final subtitle = locked
        ? 'Зарим үйлдэл хийх боломжгүй. Багцаа сунгана уу.'
        : (sub.daysLeft != null
              ? '${sub.daysLeft} хоногийн дараа дуусна. Багцаа сунгана уу.'
              : 'Багцаа сунгана уу.');

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppDimens.radiusLG),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                locked
                    ? Icons.lock_outline_rounded
                    : Icons.warning_amber_rounded,
                color: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.greeting,
    required this.name,
    required this.dateStr,
  });
  final String greeting;
  final String name;
  final String dateStr;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$greeting, $name', style: context.textStyles.h3),
        const SizedBox(height: 4),
        Text(
          dateStr,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final int? count;
  final bool loading;
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _StatCard({
    required this.count,
    this.loading = false,
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.colors.textPrimary.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Text(
                        count == null ? '—' : '$count',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: color,
                          height: 1,
                        ),
                      ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.textSecondary,
                    height: 1.3,
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

// ─── Menu section ─────────────────────────────────────────────────────────────

class _MenuEntry {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuEntry({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
}

class _MenuSection extends StatelessWidget {
  final List<_MenuEntry> items;
  const _MenuSection({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.colors.textPrimary.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final isLast = i == items.length - 1;
          return Column(
            children: [
              InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(16) : Radius.zero,
                  bottom: isLast ? const Radius.circular(16) : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: item.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(item.icon, color: item.color, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: context.colors.textHint,
                      ),
                    ],
                  ),
                ),
              ),
              if (!isLast) const Divider(height: 1, indent: 70, endIndent: 0),
            ],
          );
        }),
      ),
    );
  }
}
