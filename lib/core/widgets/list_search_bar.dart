import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';

/// Search field for a list screen, with an optional filter button whose
/// badge counts the active filters. Flat panel styling, so it reads the same
/// on every tab root (Orders, Appointments).
///
/// Debounce and stale-response guards belong to the list controller; this
/// only forwards [onChanged].
class ListSearchBar extends StatelessWidget {
  const ListSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
    this.onFilter,
    this.activeFilters = 0,
    this.filterKey,
    this.loading = false,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Null hides the filter button.
  final VoidCallback? onFilter;
  final int activeFilters;
  final Key? filterKey;

  /// A small spinner in place of the clear button while the list reloads.
  final bool loading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      borderSide: BorderSide(color: color),
    );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                suffixIcon: loading
                    // Fixed box: AppLoading's Center would otherwise expand
                    // across the whole field and squeeze the typed text out.
                    ? const SizedBox.square(
                        dimension: 48,
                        child: AppLoading(size: 16),
                      )
                    : controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Цэвэрлэх',
                        onPressed: onClear,
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: colors.surface,
                enabledBorder: border(colors.divider),
                focusedBorder: border(colors.accent),
                border: border(colors.divider),
              ),
            ),
          ),
          if (onFilter != null) ...[
            const SizedBox(width: 8),
            IconButton.outlined(
              key: filterKey,
              tooltip: 'Шүүлтүүр',
              onPressed: onFilter,
              icon: Badge(
                isLabelVisible: activeFilters > 0,
                label: Text('$activeFilters'),
                child: const Icon(Icons.tune),
              ),
              color: colors.textPrimary,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                side: BorderSide(color: colors.divider),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
