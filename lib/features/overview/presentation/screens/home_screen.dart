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
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/features/today/presentation/widgets/today_home_widgets.dart';
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

  void _pushNewInspection() {
    AppNav.to(
      ChangeNotifierProvider(
        create: (_) => NewInspectionController(),
        child: const NewInspectionScreen(),
      ),
    );
  }

  void _openOrders() {
    final ctrl = context.read<OrderController>();
    AppNav.to(ChangeNotifierProvider.value(value: ctrl, child: const OrderListScreen()));
  }

  Future<void> _refresh() =>
      Future.wait([context.read<InspectionController>().loadReports(), _loadOverview()]);

  @override
  Widget build(BuildContext context) {
    final insProv = context.watch<InspectionController>();
    final counts = _overview?.counts;
    // Null while loading or after a failed fetch: the card shows "—".
    final shown = _overviewLoading ? null : counts;

    return Scaffold(
      backgroundColor: CarserviceTheme.of(context).shellBackground,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          // The shell header owns the greeting, search and notifications;
          // the page starts with the day card (tenant-app design "Нүүр").
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // ─── Subscription warning ────────────────────────────────────
            if (_sub != null && _sub!.needsAttention) ...[
              SubscriptionBanner(sub: _sub!, onTap: () => AppNav.to(const ProfileScreen())),
              const SizedBox(height: 12),
            ],

            // ─── Day card — GET /overview (D-177) ──────────────────────
            // A failed fetch shows "—"; nothing else on the page waits on it.
            TodayHeroCard(
              label: 'Өнөөдөр · ${homeDateLabel(DateTime.now())}',
              stats: [
                TodayHeroStat(label: 'Өнөөдрийн', value: shown?.todayOrders),
                TodayHeroStat(label: 'Нээлттэй', value: shown?.openOrders, highlight: true),
                TodayHeroStat(label: 'Энэ сард дууссан', value: shown?.completedThisMonth),
              ],
            ),
            const SizedBox(height: 16),

            // ─── Quick actions ──────────────────────────────────────────
            HomeQuickActions(
              actions: [
                HomeQuickAction(
                  key: const ValueKey('home_new_inspection'),
                  icon: Icons.fact_check_outlined,
                  label: 'Оношилгоо',
                  onTap: _pushNewInspection,
                ),
                HomeQuickAction(
                  key: const ValueKey('home_search'),
                  icon: Icons.manage_search_rounded,
                  label: 'Хайх',
                  onTap: () => AppNav.to(const SearchScreen()),
                ),
                HomeQuickAction(
                  key: const ValueKey('home_appointments'),
                  icon: Icons.event_outlined,
                  label: 'Цаг захиалга',
                  // Its own tab: the screen is a tab root with no app bar,
                  // so it is switched to, not pushed.
                  onTap: () => AppNav.go(AppRoutes.appointments),
                ),
                HomeQuickAction(
                  key: const ValueKey('home_services'),
                  icon: Icons.build_outlined,
                  label: 'Үйлчилгээ',
                  onTap: () => AppNav.push(AppRoutes.services),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ─── Menu ───────────────────────────────────────────────────
            const HomeSectionHeader(title: 'Цэс'),
            const SizedBox(height: 10),
            OpsGroup(
              children: [
                OpsGroupRow(
                  icon: Icons.receipt_long_outlined,
                  title: 'Засварын хуудсууд',
                  onTap: _openOrders,
                ),
                OpsGroupRow(
                  icon: Icons.insights_rounded,
                  title: 'Тайлан',
                  onTap: () => AppNav.push(AppRoutes.reports),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ─── Recent inspections ─────────────────────────────────────
            HomeSectionHeader(
              title: 'Сүүлийн бүртгэлүүд',
              trailing: [HomeSeeAllButton(onPressed: () => AppNav.to(const HistoryScreen()))],
            ),
            const SizedBox(height: 8),
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
                        onTap: () => AppNav.to(ReportDetailScreen(reportId: r.id)),
                      ),
                    ),
                  ),
          ],
        ),
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
    final title = locked ? 'Захиалгын багц хаагдсан' : 'Захиалгын багц удахгүй дуусна';
    final subtitle = locked
        ? 'Зарим үйлдэл хийх боломжгүй. Багцаа сунгана уу.'
        : (sub.daysLeft != null
              ? '${sub.daysLeft} хоногийн дараа дуусна. Багцаа сунгана уу.'
              : 'Багцаа сунгана уу.');

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(locked ? Icons.lock_outline_rounded : Icons.warning_amber_rounded, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
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
