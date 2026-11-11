import 'package:carservice_business/core/services/app_version.dart';
import 'package:carservice_business/core/services/branch_service.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/subscription.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carservice_business/features/profile/data/me_repository.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/features/profile/presentation/widgets/profile_identity_card.dart';
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
        title: const Text('Профайл'),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // A readable width on tablets.
                  final gutter = ((constraints.maxWidth - 640) / 2).clamp(
                    20.0,
                    double.infinity,
                  );
                  return ListView(
                    padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
                    children: [
                      ProfileIdentityCard(
                        user: user,
                        onEdit: () => _openEntry(AppRoutes.profileEdit),
                      ),
                      _Section(
                        label: 'Мэдээлэл',
                        child: OpsGroup(
                          children: [
                            _InfoRow(
                              icon: Icons.phone_outlined,
                              title: 'Утас',
                              value: user.phone.isNotEmpty ? user.phone : '—',
                            ),
                            _InfoRow(
                              icon: Icons.mail_outline_rounded,
                              title: 'Имэйл',
                              value: user.email.isNotEmpty ? user.email : '—',
                            ),
                            _InfoRow(
                              icon: Icons.apartment_rounded,
                              title: 'Байгууллага',
                              value: user.tenant.name,
                            ),
                            _InfoRow(
                              icon: Icons.storefront_outlined,
                              title: 'Салбар',
                              value:
                                  _branchName ??
                                  (user.branchId == null ? 'Бүх салбар' : '—'),
                            ),
                            _InfoRow(
                              icon: Icons.badge_outlined,
                              title: 'Эрх',
                              value:
                                  user.role?.name ??
                                  (user.isOwner ? 'Эзэмшигч' : 'Ажилтан'),
                            ),
                          ],
                        ),
                      ),
                      _Section(
                        label: 'Бүртгэл',
                        child: OpsGroup(
                          children: [
                            OpsGroupRow(
                              icon: Icons.person_outline_rounded,
                              title: 'Профайл засах',
                              onTap: () => _openEntry(AppRoutes.profileEdit),
                            ),
                            OpsGroupRow(
                              icon: Icons.lock_outline_rounded,
                              title: 'Нууц үг солих',
                              onTap: () =>
                                  _openEntry(AppRoutes.profilePassword),
                            ),
                            OpsGroupRow(
                              icon: Icons.devices_other_rounded,
                              title: 'Нэвтэрсэн төхөөрөмжүүд',
                              onTap: () =>
                                  _openEntry(AppRoutes.profileSessions),
                            ),
                            OpsGroupRow(
                              icon: Icons.person_off_outlined,
                              title: 'Бүртгэл хаах',
                              tone: OpsTone.accent,
                              onTap: () => _openEntry(AppRoutes.profileClosure),
                            ),
                          ],
                        ),
                      ),
                      _Section(
                        label: 'Захиалгын багц',
                        child: _SubscriptionGroup(loading: _loading, sub: _sub),
                      ),
                      _Section(
                        label: 'Апп',
                        child: OpsGroup(
                          children: [
                            const _AppearanceRow(),
                            _InfoRow(
                              icon: Icons.info_outline_rounded,
                              title: 'Хувилбар',
                              value: _version ?? '—',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _LogoutButton(onTap: _logout),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

/// Mono section label over its group.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: OpsSectionLabel(label),
      ),
      child,
    ],
  );
}

/// A read-only row: icon tile, label, value right-aligned (ellipsized).
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: t.shellBackground,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: t.ink),
            ),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(fontSize: 15, color: t.ink)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 14, color: t.mutedText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Харагдах байдал": system / light / dark.
class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow();

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final theme = context.watch<ThemeProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: t.shellBackground,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.dark_mode_outlined, size: 16, color: t.ink),
              ),
              const SizedBox(width: 12),
              Text(
                'Харагдах байдал',
                style: TextStyle(fontSize: 15, color: t.ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              key: const ValueKey('profile_theme_mode'),
              showSelectedIcon: false,
              // Labels only: with icons "Системийн" wraps on a phone.
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Системийн'),
                ),
                ButtonSegment(value: ThemeMode.light, label: Text('Цайвар')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Бараан')),
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

class _SubscriptionGroup extends StatelessWidget {
  final bool loading;
  final SubscriptionStatus? sub;
  const _SubscriptionGroup({required this.loading, required this.sub});

  @override
  Widget build(BuildContext context) {
    final s = sub;
    if (loading && s == null) {
      return const OpsGroup(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      );
    }
    if (s == null) {
      return const OpsGroup(
        children: [
          _InfoRow(
            icon: Icons.workspace_premium_outlined,
            title: 'Багц',
            value: 'Мэдээлэл авах боломжгүй',
          ),
        ],
      );
    }
    final (label, tone) = s.locked
        ? ('Хаагдсан', OpsTone.accent)
        : s.expiringSoon
        ? ('Удахгүй дуусна', OpsTone.warn)
        : s.isTrial
        ? ('Туршилт', OpsTone.info)
        : ('Идэвхтэй', OpsTone.ok);
    return OpsGroup(
      children: [
        _InfoRow(
          icon: Icons.workspace_premium_outlined,
          title: 'Багц',
          value: s.plan ?? '—',
        ),
        OpsGroupRow(
          icon: Icons.verified_outlined,
          title: 'Төлөв',
          trailing: OpsPill(label, tone: tone),
        ),
        if (s.expiresAt != null)
          _InfoRow(
            icon: Icons.event_outlined,
            title: 'Дуусах',
            value:
                DateFormat('yyyy-MM-dd').format(s.expiresAt!) +
                (s.daysLeft != null ? ' • ${s.daysLeft} хоног' : ''),
          ),
      ],
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
      key: const ValueKey('profile_logout'),
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
