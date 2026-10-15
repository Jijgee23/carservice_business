import 'package:flutter/material.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/screens/create_order_screen.dart';
import 'package:carservice_business/features/today/presentation/controllers/today_appointments_controller.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Today board appointments timeline — Phase 4 (component part) of
/// `TENANT_UI_UX_PLAN.md`.
///
/// Self-contained: it listens to [controller] itself (like `TodayOrderCard`'s
/// callers, but driving its own `ListenableBuilder` rather than requiring
/// the parent screen to), and it is deliberately layout-agnostic — the
/// caller decides whether to place it in a tablet side column or as a full
/// phone tab body; this widget only renders a vertical, scrollable list.
///
/// Actions are gated by [canEditAppointments] (`appointments.edit`, for the
/// "Ирсэн" arrival button) and [canCreateOrders] (`orders.create`, for the
/// "Засварын хуудас үүсгэх" button shown once an appointment has been marked
/// arrived). Both default to `false` — the caller must pass its own
/// permission check, matching `TodayScreen`'s `_has(...)` pattern for the
/// order lanes.
class TodayAppointmentsTimeline extends StatelessWidget {
  const TodayAppointmentsTimeline({
    super.key,
    required this.controller,
    this.canEditAppointments = false,
    this.canCreateOrders = false,
    this.ordersRepository,
    this.onOrderCreated,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 12),
  });

  final TodayAppointmentsController controller;
  final bool canEditAppointments;
  final bool canCreateOrders;

  /// Test seam / explicit override for the repository `CreateOrderScreen`
  /// is pushed with. Defaults to `context.read<OrdersRepository>()` — the
  /// same app-wide provider `TodayScreen._create` already reads from.
  final OrdersRepository? ordersRepository;

  /// Called after a new order is created from an appointment row, so the
  /// caller can refresh whatever order surface it also shows (mirrors
  /// `TodayScreen._create` reloading `TodayOrdersController` afterwards).
  final ValueChanged<ServiceOrderSummary>? onOrderCreated;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TimelineHeader(controller: controller),
            Expanded(child: _body(context)),
          ],
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    return switch (controller.state) {
      AsyncLoading() => const _LoadingSkeleton(),
      AsyncError(:final error) => _ErrorView(
        message: error.display,
        onRetry: controller.load,
      ),
      AsyncData(:final value) =>
        value.isEmpty
            ? const _EmptyView()
            : _TimelineList(
                appointments: value,
                controller: controller,
                canEditAppointments: canEditAppointments,
                canCreateOrders: canCreateOrders,
                ordersRepository: ordersRepository,
                onOrderCreated: onOrderCreated,
                padding: padding,
              ),
    };
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({required this.controller});
  final TodayAppointmentsController controller;

  @override
  Widget build(BuildContext context) {
    final updated = controller.lastUpdated;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Өнөөдрийн цаг захиалга',
              style: context.textStyles.bodyMedium,
            ),
          ),
          if (updated != null)
            Text(
              controller.refreshError != null
                  ? 'Шинэчилж чадсангүй'
                  : 'Шинэчлэгдсэн ${DateFormat('HH:mm').format(updated)}',
              style: TextStyle(
                fontSize: 11,
                color: controller.refreshError != null
                    ? context.opsDanger
                    : context.opsTextHint,
              ),
            ),
          IconButton(
            key: const ValueKey('today_appointments_refresh'),
            tooltip: 'Шинэчлэх',
            onPressed: controller.refreshing ? null : controller.load,
            icon: controller.refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
    );
  }
}

// ─── States ─────────────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const ValueKey('today_appointments_skeleton'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        height: 84,
        decoration: BoxDecoration(
          color: context.opsCardBg,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 32,
              color: context.opsTextHint,
            ),
            const SizedBox(height: 8),
            Text(
              'Өнөөдөр цаг захиалга алга',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.opsTextHint),
            ),
          ],
        ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('today_appointments_retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Дахин оролдох'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── List ───────────────────────────────────────────────────────────────────

class _TimelineList extends StatelessWidget {
  const _TimelineList({
    required this.appointments,
    required this.controller,
    required this.canEditAppointments,
    required this.canCreateOrders,
    required this.ordersRepository,
    required this.onOrderCreated,
    required this.padding,
  });

  final List<AppointmentSummary> appointments;
  final TodayAppointmentsController controller;
  final bool canEditAppointments;
  final bool canCreateOrders;
  final OrdersRepository? ordersRepository;
  final ValueChanged<ServiceOrderSummary>? onOrderCreated;
  final EdgeInsetsGeometry padding;

  /// Id of the first appointment that is still ahead of us in time and not
  /// in a terminal/arrived state — the one row that gets the "next up"
  /// highlight. `appointments` is already sorted ascending by `requestedAt`
  /// (see `TodayAppointmentsController._sorted`), so the first match wins.
  String? _nextUpcomingId() {
    final now = controller.now();
    for (final a in appointments) {
      if (_isPastOrDone(a, now)) continue;
      return a.id;
    }
    return null;
  }

  bool _isPastOrDone(AppointmentSummary a, DateTime now) {
    if (a.status.isTerminal) return true;
    final at = a.requestedAt;
    if (at == null) return false;
    return at.isBefore(now);
  }

  @override
  Widget build(BuildContext context) {
    final nextId = _nextUpcomingId();
    return ListView.separated(
      key: const ValueKey('today_appointments_list'),
      padding: padding,
      itemCount: appointments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final a = appointments[i];
        final now = controller.now();
        return _TimelineRow(
          appointment: a,
          now: now,
          isNext: a.id == nextId,
          isDimmed: _isPastOrDone(a, now) && a.id != nextId,
          arrived: controller.isArrived(a.id),
          busy: controller.isBusy(a.id),
          canEditAppointments: canEditAppointments,
          canCreateOrders: canCreateOrders,
          onArrive: () => controller.markArrived(a.id),
          onCreateOrder: () => _createOrder(context, a),
        );
      },
    );
  }

  Future<void> _createOrder(BuildContext context, AppointmentSummary a) async {
    final repo = ordersRepository ?? context.read<OrdersRepository>();
    final vehicleRef = a.displayVehicle;
    final initialVehicle = vehicleRef?.id == null
        ? null
        : VehicleSummary(
            id: vehicleRef!.id!,
            plate: vehicleRef.plate ?? '',
            make: vehicleRef.make ?? '',
            model: vehicleRef.model ?? '',
            customerId: a.customer?.id,
          );
    final initialCustomer = a.customer?.id == null
        ? null
        : CustomerSummary(
            id: a.customer!.id!,
            fullName: a.customer?.fullName,
            phone: a.customer?.phone ?? a.account?.phone ?? '',
          );
    final created = await AppNav.to<ServiceOrderSummary>(
      CreateOrderScreen(
        repository: repo,
        appointmentId: a.id,
        initialVehicle: initialVehicle,
        initialCustomer: initialCustomer,
      ),
    );
    if (created != null) {
      onOrderCreated?.call(created);
      await controller.load();
    }
  }
}

// ─── Row ────────────────────────────────────────────────────────────────────

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.appointment,
    required this.now,
    required this.isNext,
    required this.isDimmed,
    required this.arrived,
    required this.busy,
    required this.canEditAppointments,
    required this.canCreateOrders,
    required this.onArrive,
    required this.onCreateOrder,
  });

  final AppointmentSummary appointment;
  final DateTime now;
  final bool isNext;
  final bool isDimmed;
  final bool arrived;
  final bool busy;
  final bool canEditAppointments;
  final bool canCreateOrders;
  final VoidCallback onArrive;
  final VoidCallback onCreateOrder;

  bool get _canMarkArrived =>
      canEditAppointments &&
      arrived != true &&
      appointment.status == AppointmentStatus.CONFIRMED;

  bool get _canCreateOrderNow =>
      canCreateOrders && arrived && appointment.serviceOrder == null;

  bool get _isPendingArrival =>
      canEditAppointments &&
      arrived != true &&
      appointment.status == AppointmentStatus.PENDING;

  @override
  Widget build(BuildContext context) {
    final vehicle = appointment.displayVehicle;
    final plate = (vehicle?.plate ?? '').isEmpty
        ? '—'
        : plateLabel(vehicle!.plate);
    final serviceName = appointment.category?.name ?? 'Ерөнхий үйлчилгээ';
    final time = appointment.requestedAt;
    final opacity = isDimmed ? 0.55 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Container(
        key: ValueKey('today_appt_${appointment.id}'),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isNext ? context.opsAccent : context.opsDivider,
            width: isNext ? 1.5 : 1,
          ),
          boxShadow: isNext
              ? [
                  BoxShadow(
                    color: context.opsAccent.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TimeColumn(time: time, isNext: isNext),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plate,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _StatusChip(status: appointment.status, arrived: arrived),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    appointment.displayName,
                    style: context.textStyles.captionMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    serviceName,
                    style: TextStyle(fontSize: 12, color: context.opsTextHint),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_canMarkArrived ||
                      _isPendingArrival ||
                      _canCreateOrderNow) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: _canCreateOrderNow
                          ? FilledButton.icon(
                              key: ValueKey(
                                'today_appt_create_order_${appointment.id}',
                              ),
                              onPressed: onCreateOrder,
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Засварын хуудас үүсгэх'),
                            )
                          : FilledButton.icon(
                              key: ValueKey(
                                'today_appt_arrived_${appointment.id}',
                              ),
                              onPressed: (_canMarkArrived && !busy)
                                  ? onArrive
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: context.opsGood,
                              ),
                              icon: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                              label: const Text('Ирсэн'),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.time, required this.isNext});
  final DateTime? time;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final label = time == null ? '--:--' : DateFormat('HH:mm').format(time!);
    return SizedBox(
      width: 52,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: isNext ? context.opsAccent : context.opsTextPrimary,
            ),
          ),
          if (isNext)
            Text(
              'дараагийн',
              style: TextStyle(fontSize: 10, color: context.opsAccent),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.arrived});
  final AppointmentStatus status;
  final bool arrived;

  @override
  Widget build(BuildContext context) {
    final (label, color) = arrived
        ? ('Ирсэн', context.opsGood)
        : switch (status) {
            AppointmentStatus.PENDING => ('Хүлээгдэж буй', context.opsWarning),
            AppointmentStatus.CONFIRMED => ('Баталгаажсан', context.opsAccent),
            AppointmentStatus.NO_SHOW => ('Ирээгүй', context.opsDanger),
            AppointmentStatus.CANCELLED => ('Цуцлагдсан', context.opsTextHint),
            AppointmentStatus.REJECTED => ('Татгалзсан', context.opsTextHint),
            AppointmentStatus.unknown => ('Тодорхойгүй', context.opsTextHint),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
