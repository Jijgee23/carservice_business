import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';

/// Maps [AppointmentStatus] to a themed colour — presentation only. The
/// *meaning* of each status (which statuses are terminal, which
/// transitions are valid) stays entirely in [AppointmentStatus] itself;
/// this file only decides which token to paint it with.
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
    AppointmentStatus.CONFIRMED => theme.ok,
    AppointmentStatus.REJECTED => theme.danger,
    AppointmentStatus.CANCELLED => theme.mutedText3,
    AppointmentStatus.NO_SHOW => theme.danger,
    AppointmentStatus.unknown => theme.mutedText2,
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
