import 'package:flutter/material.dart';

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
                    // A 1px top line, like the app bar's bottom one: the bar
                    // is a panel, flat against the page.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                      child: NavigationBar(
                        selectedIndex: _safeIndex,
                        onDestinationSelected: (index) {
                          if (destinations[index].enabled) {
                            onDestinationSelected(index);
                          }
                        },
                        destinations: _bottomDestinations,
                      ),
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
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (leadingAction != null) leadingAction!,
            if (title != null) Expanded(child: title!) else const Spacer(),
            if (searchAction != null) searchAction!,
            if (notificationAction != null) notificationAction!,
          ],
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
