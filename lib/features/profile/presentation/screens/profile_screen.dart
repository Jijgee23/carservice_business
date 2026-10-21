import 'package:carservice_business/core/services/app_version.dart';
import 'package:carservice_business/core/services/branch_service.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/subscription.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carservice_business/features/profile/data/me_repository.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Staff profile & account screen.
///
/// Refreshes the authoritative profile from `GET /api/v1/me`, resolves the
/// assigned branch name, and surfaces subscription status from
/// `GET /api/v1/subscription`. All network work is best-effort; the screen
/// renders from stored state if any call fails.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _meRepo = MeRepository();
  bool _loading = true;
  String? _branchName;
  SubscriptionStatus? _sub;
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
    appVersionLabel().then((v) {
      if (mounted && v != null) setState(() => _version = v);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Refresh profile (updates Hive-stored user), subscription and branch name.
    await _meRepo.refresh();
    _sub = await SubscriptionService.instance.getStatus();
    final branchId = Authenticator.user?.branchId;
    if (branchId != null) {
      final branches = await BranchService.instance.getBranches();
      _branchName = branches
          .where((b) => b.id == branchId)
          .map((b) => b.name)
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);
    } else {
      _branchName = null;
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Pushes an account-management route (edit / password / sessions) and
  /// refreshes the displayed profile on return — `updateProfile` and
  /// `changePassword` already update `Authenticator.user`/Hive themselves
  /// (matching `MeRepository.refresh()`'s merge), so this only needs to
  /// re-read that stored state, not re-fetch `/me`.
  Future<void> _openEntry(String route) async {
    await AppNav.push(route);
    if (mounted) _load();
  }

  Future<void> _logout() async {
    final ok = await ConfirmSheet.show(
      context,
      title: 'Гарах уу?',
      message: 'Та системээс гарахдаа итгэлтэй байна уу?',
      confirmLabel: 'Гарах',
      icon: Icons.logout_rounded,
      isDangerous: true,
    );
    if (ok && mounted) context.read<AuthController>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = Authenticator.user;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text('Профайл'),
        actions: [
          IconButton(
            tooltip: 'Шинэчлэх',
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Хэрэглэгчийн мэдээлэл байхгүй'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(AppDimens.paddingMD),
                children: [
                  _Header(user: user),
                  const SizedBox(height: 16),
                  _InfoCard(
                    title: 'Хувийн мэдээлэл',
                    rows: [
                      ('Утас', user.phone.isNotEmpty ? user.phone : '—'),
                      ('Байгууллага', user.tenant.name),
                      (
                        'Салбар',
                        _branchName ??
                            (user.branchId == null ? 'Бүх салбар' : '—'),
                      ),
                      (
                        'Эрх',
                        user.role?.name ??
                            (user.isOwner ? 'Эзэмшигч' : 'Ажилтан'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SubscriptionCard(loading: _loading, sub: _sub),
                  const SizedBox(height: 14),
                  const _AppearanceCard(),
                  const SizedBox(height: 14),
                  _InfoCard(
                    title: 'Аппликейшн',
                    rows: [('Хувилбар', _version ?? '—')],
                  ),
                  const SizedBox(height: 14),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _EntryRow(
                          icon: Icons.edit_rounded,
                          label: 'Профайл засах',
                          onTap: () => _openEntry(AppRoutes.profileEdit),
                        ),
                        Divider(height: 1, color: context.colors.divider),
                        _EntryRow(
                          icon: Icons.lock_outline_rounded,
                          label: 'Нууц үг солих',
                          onTap: () => _openEntry(AppRoutes.profilePassword),
                        ),
                        Divider(height: 1, color: context.colors.divider),
                        _EntryRow(
                          icon: Icons.devices_other_rounded,
                          label: 'Нэвтэрсэн төхөөрөмжүүд',
                          onTap: () => _openEntry(AppRoutes.profileSessions),
                        ),
                        Divider(height: 1, color: context.colors.divider),
                        _EntryRow(
                          icon: Icons.person_off_outlined,
                          label: 'Бүртгэл хаах',
                          onTap: () => _openEntry(AppRoutes.profileClosure),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.danger,
                        side: BorderSide(color: context.colors.danger),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusMD,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: Text(
                        'Гарах',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Харагдах байдал', style: context.textStyles.h3),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              key: const ValueKey('profile_theme_mode'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('Системийн'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Цайвар'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Бараан'),
                ),
              ],
              selected: {theme.mode},
              onSelectionChanged: (s) => theme.setMode(s.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final User user;
  const _Header({required this.user});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: context.colors.accent,
            child: Text(
              user.firstName.isNotEmpty ? user.firstName[0] : '?',
              style: TextStyle(
                fontSize: 24,
                color: CarserviceTheme.of(context).onAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName, style: context.textStyles.h2),
                const SizedBox(height: 4),
                Text(user.email, style: context.textStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textStyles.h3),
          const SizedBox(height: 12),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(r.$1, style: context.textStyles.caption),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: context.textStyles.bodyMedium,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final bool loading;
  final SubscriptionStatus? sub;
  const _SubscriptionCard({required this.loading, required this.sub});

  @override
  Widget build(BuildContext context) {
    final s = sub;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Захиалгын багц', style: context.textStyles.h3),
          const SizedBox(height: 12),
          if (loading && s == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (s == null)
            Text('Мэдээлэл авах боломжгүй', style: context.textStyles.caption)
          else ...[
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text('Багц', style: context.textStyles.caption),
                ),
                Expanded(
                  child: Text(
                    s.plan ?? '—',
                    style: context.textStyles.bodyMedium,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text('Төлөв', style: context.textStyles.caption),
                ),
                const Spacer(),
                _StatusPill(sub: s),
              ],
            ),
            if (s.expiresAt != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text('Дуусах', style: context.textStyles.caption),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('yyyy-MM-dd').format(s.expiresAt!) +
                          (s.daysLeft != null ? ' • ${s.daysLeft} хоног' : ''),
                      style: context.textStyles.bodyMedium,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final SubscriptionStatus sub;
  const _StatusPill({required this.sub});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = sub.locked
        ? ('Хаагдсан', context.colors.danger, context.colors.dangerBg)
        : sub.expiringSoon
        ? ('Удахгүй дуусна', context.colors.warning, context.colors.warningBg)
        : sub.isTrial
        ? (
            'Туршилт',
            context.colors.accent,
            context.colors.accent.withValues(alpha: 0.12),
          )
        : ('Идэвхтэй', context.colors.good, context.colors.goodBg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// One tappable account-management entry — P8-F3. `Профайл засах`, `Нууц үг
/// солих`, `Нэвтэрсэн төхөөрөмжүүд` above the logout button all use this.
class _EntryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _EntryRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.colors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: context.textStyles.bodyMedium),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.colors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}
