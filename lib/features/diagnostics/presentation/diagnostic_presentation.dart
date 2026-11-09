import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:flutter/material.dart';

/// Presentation-only colors for diagnostic template categories.
///
/// These are derived from the active theme so tinted chips remain legible in
/// both brightnesses while preserving the category/status distinctions from
/// the original UI.
extension DiagnosticTypePresentation on DiagnosticType {
  Color colorFor(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    return switch (this) {
      DiagnosticType.INTAKE => theme.info,
      DiagnosticType.POST_SERVICE => theme.ok,
      DiagnosticType.ROUTINE => theme.mutedText,
      DiagnosticType.DAMAGE_REPORT => theme.warn,
    };
  }

  Color backgroundFor(BuildContext context) =>
      colorFor(context).withValues(alpha: 0.12);
}
