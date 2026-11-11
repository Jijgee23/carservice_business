import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';

import 'breakpoints.dart';

/// A shell scaffold that switches navigation chrome at the programme's three
/// width tiers. The body is intentionally supplied by the caller: feature
/// screens keep ownership of their app bars and scrolling state.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.scaffoldKey,
    this.drawer,
    this.header,
    this.title,
    this.notificationAction,
    this.leadingAction,
    this.searchAction,
    this.floatingActionButton,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.showHeader = true,
  });

  final Widget body;
  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final Widget? drawer;
  final Widget? header;

  /// Fills the default header between [leadingAction] and the trailing
  /// actions — the shell's greeting.
  final Widget? title;
  final Widget? notificationAction;

  /// Shown at the start of the default header (e.g. the drawer menu button).
  final Widget? leadingAction;

  /// Global search entry, placed before [notificationAction]. Search is a
  /// utility reachable from every tab, not a navigation destination.
  final Widget? searchAction;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;

  /// False on pushed screens: they carry their own app bar (← + title +
  /// bell), so the persistent header would only stack a second bar.
  final bool showHeader;

  int get _safeIndex =>
      destinations.isEmpty ? 0 : selectedIndex.clamp(0, destinations.length - 1).toInt();

  List<NavigationDestination> get _bottomDestinations => [
    for (final destination in destinations)
      NavigationDestination(
        icon: Icon(destination.icon),
        selectedIcon: Icon(destination.selectedIcon ?? destination.icon),
        label: destination.label,
        enabled: destination.enabled,
      ),
  ];

  List<NavigationRailDestination> get _railDestinations => [
    for (final destination in destinations)
      NavigationRailDestination(
        icon: Icon(destination.icon),
        selectedIcon: Icon(destination.selectedIcon ?? destination.icon),
        label: Text(destination.label),
        disabled: !destination.enabled,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = AdaptiveBreakpoints.ofWidth(constraints.maxWidth);
        final rail = size != AdaptiveSize.phone;
        // Labels beside rail icons cost ~180dp; only spend it on large screens
        // so tablet landscape keeps room for the orders + appointments panes.
        final extended = constraints.maxWidth >= AdaptiveBreakpoints.extendedRail;
        // The header lives in the content column at every width, never in
        // the compact rail.
        final persistentHeader = showHeader ? header ?? _defaultHeader() : null;
        final content = persistentHeader == null
            ? body
            : Column(
                children: [
                  persistentHeader,
                  Expanded(child: body),
                ],
              );

        return Scaffold(
          key: scaffoldKey,
          drawer: drawer,
          backgroundColor: backgroundColor,
          floatingActionButton: floatingActionButton,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rail)
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(
                    right: false,
                    child: NavigationRail(
                      selectedIndex: _safeIndex,
                      onDestinationSelected: (index) {
                        if (destinations[index].enabled) {
                          onDestinationSelected(index);
                        }
                      },
                      extended: extended,
                      // Compact tablets use the collapsed icon-only rail;
                      // extended tablets show labels beside the icons.
                      labelType: NavigationRailLabelType.none,
                      destinations: _railDestinations,
                    ),
                  ),
                ),
              // A pushed screen's own app bar pads itself under the status
              // bar; insetting it here too left a background strip above it.
              Expanded(
                child: SafeArea(left: false, top: showHeader, child: content),
              ),
            ],
          ),
          bottomNavigationBar: rail
              ? null
              : (bottomNavigationBar ??
                    _FloatingNavBar(
                      selectedIndex: _safeIndex,
                      onDestinationSelected: (index) {
                        if (destinations[index].enabled) {
                          onDestinationSelected(index);
                        }
                      },
                      destinations: _bottomDestinations,
                    )),
        );
      },
    );
  }

  Widget? _defaultHeader() {
    if (title == null &&
        notificationAction == null &&
        leadingAction == null &&
        searchAction == null) {
      return null;
    }
    // Design header: avatar + greeting on the left, round actions right.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
        child: Row(
          children: [
            if (leadingAction != null) ...[leadingAction!, const SizedBox(width: 8)],
            if (title != null) Expanded(child: title!) else const Spacer(),
            if (searchAction != null) ...[const SizedBox(width: 8), searchAction!],
            if (notificationAction != null) ...[const SizedBox(width: 8), notificationAction!],
          ],
        ),
      ),
    );
  }
}

/// Phone navigation: a floating pill over the page — translucent panel,
/// blur, 1px line, soft shadow; the selected tab in ink, the rest muted, no
/// indicator blob. Still a [NavigationBar] inside, for its semantics.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  static const _height = 68.0;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final shape = BorderRadius.circular(AppDimens.radiusFull);
    return Padding(
      // ~24 above the bottom edge on a home-indicator phone, never flush.
      padding: EdgeInsets.fromLTRB(16, 8, 16, math.max(16, bottomInset - 10)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: [
            BoxShadow(
              color: t.ink.withValues(alpha: 0.16),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.panel.withValues(alpha: 0.78),
                borderRadius: shape,
                border: Border.all(color: t.border.withValues(alpha: 0.9)),
              ),
              // The pill already sits above the safe area.
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: NavigationBarTheme(
                  data: NavigationBarThemeData(
                    height: _height,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    indicatorColor: Colors.transparent,
                    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    iconTheme: WidgetStateProperty.resolveWith(
                      (states) => IconThemeData(
                        size: 22,
                        color: states.contains(WidgetState.disabled)
                            ? t.mutedText3.withValues(alpha: 0.5)
                            : states.contains(WidgetState.selected)
                            ? t.ink
                            : t.mutedText,
                      ),
                    ),
                    labelTextStyle: WidgetStateProperty.resolveWith(
                      (states) => TextStyle(
                        fontFamily: AppFonts.sans,
                        fontSize: 10,
                        fontWeight: states.contains(WidgetState.selected)
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: states.contains(WidgetState.disabled)
                            ? t.mutedText3.withValues(alpha: 0.5)
                            : states.contains(WidgetState.selected)
                            ? t.ink
                            : t.mutedText,
                      ),
                    ),
                  ),
                  child: NavigationBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    destinations: destinations,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdaptiveNavigationDestination {
  const AdaptiveNavigationDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.enabled = true,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final bool enabled;
  final String? tooltip;
}
