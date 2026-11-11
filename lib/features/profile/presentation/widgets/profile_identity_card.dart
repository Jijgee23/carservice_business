import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';

/// The navy identity card at the top of Бусад and Профайл (tenant-app
/// design): initials, full name, masked phone, role and workshop pills,
/// and an edit button.
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.user,
    this.onTap,
    this.onEdit,
  });

  final User user;

  /// Opens the profile (Бусад); null on the profile screen itself.
  final VoidCallback? onTap;

  /// Shows the edit button when set.
  final VoidCallback? onEdit;

  /// "99112233" → "+976 ••••2233". Shorter numbers come back unchanged.
  static String maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return phone.trim();
    final local = digits.length > 8 && digits.startsWith('976')
        ? digits.substring(3)
        : digits;
    return '+976 ••••${local.substring(local.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final role = user.role?.name ?? (user.isOwner ? 'Эзэмшигч' : 'Ажилтан');
    final contact = user.phone.trim().isNotEmpty
        ? maskPhone(user.phone)
        : user.email.trim();
    final tenant = user.tenant.name.trim();
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    return Material(
      color: OpsDark.bg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              OpsAvatar(
                initials: opsInitials(user.firstName, user.lastName),
                size: 60,
                onDark: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: OpsDark.ink,
                      ),
                    ),
                    if (contact.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        contact,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: opsMono(context, color: OpsDark.muted),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        // The deep accent: white 11px text needs its contrast.
                        _HeroPill(
                          role,
                          background: OpsColors.lightAccent,
                          bold: true,
                        ),
                        if (tenant.isNotEmpty)
                          _HeroPill(tenant, background: OpsDark.line),
                      ],
                    ),
                  ],
                ),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('profile_identity_edit'),
                  tooltip: 'Профайл засах',
                  onPressed: onEdit,
                  style: IconButton.styleFrom(
                    backgroundColor: OpsDark.line,
                    foregroundColor: OpsDark.ink,
                    fixedSize: const Size.square(40),
                    minimumSize: const Size.square(40),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill(this.label, {required this.background, this.bold = false});

  final String label;
  final Color background;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: bold ? FontWeight.w500 : FontWeight.w400,
        color: bold ? Colors.white : OpsDark.ink,
      ),
    ),
  );
}
