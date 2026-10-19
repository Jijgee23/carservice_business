import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart' as diagnostic;
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/orders/domain/order.dart';

/// Theme-aware presentation tokens shared by the order and appointment
/// screens. Domain objects deliberately expose state only; colour belongs to
/// the active presentation context.
extension FeatureTheme on BuildContext {
  CarserviceTheme get _ops => CarserviceTheme.of(this);

  Color get opsBackground => _ops.shellBackground;
  Color get opsSurface => _ops.panel;
  Color get opsCardBg => _ops.panel2;
  Color get opsDivider => _ops.border;
  Color get opsPrimary => _ops.accent;
  Color get opsAccent => _ops.accent;
  Color get opsAccentHi => _ops.accentHi;
  Color get opsGood => _ops.ok;
  Color get opsWarning => _ops.warn;
  Color get opsDanger => _ops.danger;
  Color get opsTextPrimary => _ops.ink;
  Color get opsTextSecondary => _ops.mutedText;
  Color get opsTextHint => _ops.mutedText3;
  Color get opsTextOnDark => _ops.onAccent;

  Color orderStatusColor(OrderStatus status) => switch (status) {
    OrderStatus.SCHEDULED => _ops.warn,
    OrderStatus.IN_PROGRESS => _ops.accentHi,
    OrderStatus.COMPLETED => _ops.ok,
    OrderStatus.CANCELLED => _ops.danger,
  };

  Color orderStatusBackground(OrderStatus status) =>
      orderStatusColor(status).withOpacity(0.12);

  Color paymentStatusColor(PaymentStatus status) => switch (status) {
    PaymentStatus.UNPAID => _ops.danger,
    PaymentStatus.PARTIAL => _ops.warn,
    PaymentStatus.PAID => _ops.ok,
  };

  Color paymentStatusBackground(PaymentStatus status) =>
      paymentStatusColor(status).withOpacity(0.12);

  Color itemKindColor(ItemKind kind) => switch (kind) {
    ItemKind.LABOR => _ops.accentHi,
    ItemKind.DIAGNOSTIC => _ops.accent,
    ItemKind.PART => _ops.warn,
    ItemKind.FEE => _ops.danger,
  };

  Color itemKindBackground(ItemKind kind) =>
      itemKindColor(kind).withOpacity(0.1);

  Color itemStatusColor(ServiceItemStatus status) => switch (status) {
    ServiceItemStatus.PENDING => _ops.mutedText,
    ServiceItemStatus.IN_PROGRESS => _ops.accent,
    ServiceItemStatus.COMPLETED => _ops.ok,
    ServiceItemStatus.CANCELLED => _ops.danger,
  };

  Color diagnosticTypeColor(diagnostic.DiagnosticType type) => switch (type) {
    diagnostic.DiagnosticType.INTAKE => _ops.accent,
    diagnostic.DiagnosticType.POST_SERVICE => _ops.ok,
    diagnostic.DiagnosticType.ROUTINE => _ops.accentHi,
    diagnostic.DiagnosticType.DAMAGE_REPORT => _ops.warn,
  };

  Color diagnosticTypeBackground(diagnostic.DiagnosticType type) =>
      diagnosticTypeColor(type).withOpacity(0.12);

  Color appointmentStatusColor(AppointmentStatus status) => switch (status) {
    AppointmentStatus.PENDING => _ops.warn,
    AppointmentStatus.CONFIRMED => _ops.ok,
    AppointmentStatus.REJECTED => _ops.danger,
    AppointmentStatus.CANCELLED => _ops.mutedText2,
    AppointmentStatus.NO_SHOW => _ops.accent,
    // P2-F1 added `unknown` so an unrecognised server status degrades instead
    // of crashing the parse. It must stay visually neutral — colouring it like
    // a real status would assert something the server never said.
    AppointmentStatus.unknown => _ops.mutedText2,
  };

  Color appointmentStatusBackground(AppointmentStatus status) =>
      appointmentStatusColor(status).withOpacity(0.12);
}
