import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';

/// Maps [AppointmentStatus] to a themed colour — presentation only. The
/// *meaning* of each status (which statuses are terminal, which
/// transitions are valid) stays entirely in [AppointmentStatus] itself;
/// this file only decides which token to paint it with.
///
/// Tenant-app design: a confirmed booking is the navy "scheduled" block,
/// a pending one the amber tint, a rejected/no-show one the red tint.
///
/// [AppointmentStatus.unknown] (the P2-F1 defensive sentinel for a value
/// this build does not recognise yet) is deliberately mapped to the same
/// neutral muted tone as "no status" — it must never look actionable or be
/// mistaken for a real status.
Color calendarStatusColor(BuildContext context, AppointmentStatus? status) {
  final theme = CarserviceTheme.of(context);
  return switch (status) {
    null => theme.mutedText2,
    AppointmentStatus.PENDING => theme.warn,
    AppointmentStatus.CONFIRMED => theme.ink,
    AppointmentStatus.REJECTED => theme.danger,
    AppointmentStatus.CANCELLED => theme.mutedText3,
    AppointmentStatus.NO_SHOW => theme.danger,
    AppointmentStatus.unknown => theme.mutedText2,
  };
}

/// Fill / text colours of one appointment block or status pill.
class CalendarStatusStyle {
  const CalendarStatusStyle({
    required this.background,
    required this.foreground,
    required this.secondary,
    this.border,
  });

  final Color background;

  /// Title and status text.
  final Color foreground;

  /// Times and other secondary text.
  final Color secondary;

  /// Only the neutral (cancelled / unknown) style draws an outline.
  final Color? border;
}

/// The design's block colours: solid navy for a confirmed booking, pale
/// tints with a dark matching text for the others.
CalendarStatusStyle calendarStatusStyle(
  BuildContext context,
  AppointmentStatus? status,
) {
  final t = CarserviceTheme.of(context);
  CalendarStatusStyle tint(Color color) {
    return CalendarStatusStyle(
      background: Color.alphaBlend(color.withValues(alpha: 0.14), t.panel),
      foreground: color,
      secondary: color.withValues(alpha: 0.8),
    );
  }

  return switch (status) {
    AppointmentStatus.CONFIRMED => CalendarStatusStyle(
      background: t.ink,
      foreground: t.shellBackground,
      secondary: t.shellBackground.withValues(alpha: 0.75),
    ),
    AppointmentStatus.PENDING => tint(t.warn),
    AppointmentStatus.REJECTED || AppointmentStatus.NO_SHOW => tint(t.accent),
    AppointmentStatus.CANCELLED ||
    AppointmentStatus.unknown ||
    null => CalendarStatusStyle(
      background: t.panel,
      foreground: t.mutedText,
      secondary: t.mutedText,
      border: t.border,
    ),
  };
}

/// A small dot/icon marker for a legend or block chip. Kept separate from
/// [calendarStatusColor] so a future icon-per-status change does not ripple
/// through every call site that only wants the colour.
IconData calendarStatusIcon(AppointmentStatus? status) => switch (status) {
  null => Icons.help_outline_rounded,
  AppointmentStatus.PENDING => Icons.hourglass_top_rounded,
  AppointmentStatus.CONFIRMED => Icons.event_available_rounded,
  AppointmentStatus.REJECTED => Icons.event_busy_rounded,
  AppointmentStatus.CANCELLED => Icons.block_rounded,
  AppointmentStatus.NO_SHOW => Icons.person_off_rounded,
  AppointmentStatus.unknown => Icons.help_outline_rounded,
};
