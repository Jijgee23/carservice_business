import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/services/notification_router.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/adaptive/breakpoints.dart';
import 'package:carservice_business/core/widgets/mixin/pagination_mixin.dart';
import 'package:carservice_business/features/notifications/domain/notification_item.dart';
import 'package:carservice_business/features/notifications/domain/notifications_repository.dart';
import 'package:carservice_business/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key, this.repository});

  /// Tests and previews inject a fake. Production defaults to the remote
  /// adapter inside [NotificationController].
  final NotificationsRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NotificationController(repo: repository)..load(),
      child: const _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> with PaginationMixin {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initPagination(() => context.read<NotificationController>().loadMore());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationController>();
    final theme = Theme.of(context);
    final colors = _notificationColors(context);
    final hasUnread =
        (controller.listState.valueOrNull ?? const <NotificationItem>[]).any(
          (notification) => notification.isUnread,
        );

    return Scaffold(
      backgroundColor: colors.shellBackground,
      appBar: AppBar(
        title: const Text('Мэдэгдэл'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: controller.markAllRead,
              child: Text(
                'Бүгдийг уншсан',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = AdaptiveBreakpoints.ofWidth(constraints.maxWidth);
          return AsyncStateView<List<NotificationItem>>(
            state: controller.listState,
            isEmpty: (items) => items.isEmpty,
            empty: const _EmptyView(),
            error: (context, error) =>
                _ErrorView(message: error.display, onRetry: controller.load),
            builder: (context, items) => _NotificationList(
              items: items,
              controller: controller,
              scrollController: scrollController,
              size: size,
            ),
          );
        },
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.items,
    required this.controller,
    required this.scrollController,
    required this.size,
  });

  final List<NotificationItem> items;
  final NotificationController controller;
  final ScrollController scrollController;
  final AdaptiveSize size;

  @override
  Widget build(BuildContext context) {
    final colors = _notificationColors(context);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: RefreshIndicator(
        onRefresh: controller.load,
        child: size == AdaptiveSize.tablet
            ? GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 480,
                  mainAxisExtent: 116,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: items.length + (controller.loadingMore ? 1 : 0),
                itemBuilder: (context, index) => _item(context, index),
              )
            : ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length + (controller.loadingMore ? 1 : 0),
                separatorBuilder: (_, _) =>
                    Divider(color: colors.borderSubtle, height: 1),
                itemBuilder: (context, index) => _item(context, index),
              ),
      ),
    );
    return Align(alignment: Alignment.topCenter, child: content);
  }

  Widget _item(BuildContext context, int index) {
    if (index == items.length) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final item = items[index];
    return _NotificationTile(
      item: item,
      onTap: () {
        if (item.isUnread) controller.markRead(item.id);
        if (NotificationRouter.hasTarget(item.data)) {
          NotificationRouter.route(item.data);
        } else {
          // Announcements have nowhere to go; routing would just push another
          // inbox. Show the full (untruncated) text here instead.
          _showFullText(context, item);
        }
      },
    );
  }
}

void _showFullText(BuildContext context, NotificationItem item) {
  AppNav.sheet<void>(
    Builder(
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const ValueKey('notification_full_text'),
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingXL,
            0,
            AppDimens.paddingXL,
            AppDimens.paddingXL,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppDimens.paddingXS),
              Text(
                _formatRelative(item.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppDimens.paddingMD),
              SelectableText(
                item.body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    ),
    showDragHandle: true,
  );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final NotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _notificationColors(context);
    return Material(
      color: item.isUnread ? colors.panel2 : colors.panel,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TypeIcon(type: item.type, isUnread: item.isUnread),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.ink,
                              fontWeight: item.isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (item.isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6, top: 4),
                            decoration: BoxDecoration(
                              color: colors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatRelative(item.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.mutedText2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type, required this.isUnread});

  final String type;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    final colors = _notificationColors(context);
    final (icon, color) = switch (type) {
      'appointment_confirmed' => (
        Icons.check_circle_outline_rounded,
        colors.ok,
      ),
      'appointment_rejected' ||
      'appointment_cancelled' => (Icons.cancel_outlined, colors.danger),
      'appointment_reminder' => (Icons.alarm_rounded, colors.warn),
      'appointment_created' => (Icons.calendar_today_rounded, colors.accent),
      // A repair order was assigned to me (mechanic) — opens its detail.
      'order_assigned' => (Icons.assignment_ind_outlined, colors.accent),
      _ => (Icons.notifications_none_rounded, colors.mutedText2),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Icon(
        icon,
        size: 20,
        color: isUnread ? colors.accent : colors.mutedText,
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _notificationColors(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 56,
            color: colors.mutedText2,
          ),
          const SizedBox(height: 12),
          Text(
            'Мэдэгдэл байхгүй',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _notificationColors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Дахин оролдох'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRelative(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'Дөнгөж сая';
  if (diff.inHours < 1) return '${diff.inMinutes}м өмнө';
  if (diff.inHours < 24) return '${diff.inHours}ц өмнө';
  if (diff.inDays < 7) return '${diff.inDays}х өмнө';
  return '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
}

/// The app theme supplies [CarserviceTheme], while a plain MaterialApp remains a
/// useful lightweight harness for widget tests and previews.
class _NotificationColors {
  const _NotificationColors({
    required this.shellBackground,
    required this.panel,
    required this.panel2,
    required this.borderSubtle,
    required this.ink,
    required this.mutedText,
    required this.mutedText2,
    required this.accent,
    required this.ok,
    required this.warn,
    required this.danger,
  });

  final Color shellBackground;
  final Color panel;
  final Color panel2;
  final Color borderSubtle;
  final Color ink;
  final Color mutedText;
  final Color mutedText2;
  final Color accent;
  final Color ok;
  final Color warn;
  final Color danger;
}

_NotificationColors _notificationColors(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final colors = theme.extension<CarserviceTheme>();
  return _NotificationColors(
    shellBackground: colors?.shellBackground ?? theme.scaffoldBackgroundColor,
    panel: colors?.panel ?? scheme.surface,
    panel2: colors?.panel2 ?? scheme.surfaceContainerHighest,
    borderSubtle: colors?.borderSubtle ?? scheme.outlineVariant,
    ink: colors?.ink ?? scheme.onSurface,
    mutedText: colors?.mutedText ?? scheme.onSurfaceVariant,
    mutedText2: colors?.mutedText2 ?? scheme.onSurfaceVariant,
    accent: colors?.accent ?? scheme.primary,
    ok: colors?.ok ?? scheme.primary,
    warn: colors?.warn ?? scheme.secondary,
    danger: colors?.danger ?? scheme.error,
  );
}
