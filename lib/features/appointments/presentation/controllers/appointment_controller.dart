import 'dart:async';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/appointment_list_controller.dart';

/// Shared Appointments notifier — P2-F2.
///
/// List/filter/selection/pagination state lives in
/// [AppointmentListController]; this subclass adds the single-appointment
/// lifecycle mutations the detail sheet drives, matching how `OrderController
/// extends OrderListController` keeps detail actions alongside list state
/// (`lib/features/orders/presentation/controllers/order_controller.dart`).
///
/// Existing call sites construct this with no arguments
/// (`lib/app/shell/app_shell.dart`, `lib/core/services/notification_router.dart`,
/// `lib/features/shell/presentation/screens/index.dart`) — none of those
/// files are owned by this slice, so the zero-arg constructor is preserved.
class AppointmentController extends AppointmentListController {
  AppointmentController({super.repo, super.searchDebounce});

  /// Applies a named lifecycle transition for [id]. The named routes are the
  /// only mutation surface the frozen contract exposes for
  /// PENDING→CONFIRMED/REJECTED and CONFIRMED→NO_SHOW; CANCELLED goes through
  /// the `PATCH .../cancel` adapter. Known-trap #2: the successful result is
  /// applied to local list state first, and only then is an authoritative
  /// reload attempted — a reload failure never overwrites the just-committed
  /// success with an error page, it is surfaced as a transient message
  /// instead.
  Future<bool> transition(String id, AppointmentStatus target) async {
    final Future<Result<AppointmentLifecycleResult>> call = switch (target) {
      AppointmentStatus.CONFIRMED => repository.confirm(id),
      AppointmentStatus.REJECTED => repository.reject(id),
      AppointmentStatus.NO_SHOW => repository.markNoShow(id),
      AppointmentStatus.CANCELLED => repository.cancel(id),
      _ => Future.value(
        const Err(AppError(ErrorKind.unknown, 'Энэ төлөвт шилжих боломжгүй.')),
      ),
    };
    final result = await call;
    switch (result) {
      case Ok(:final value):
        _patchLocalStatus(id, value.status ?? target);
        unawaited(refresh());
        return true;
      case Err(:final error):
        messageError(error.display);
        return false;
    }
  }

  Future<bool> markArrived(String id) async {
    final result = await repository.markArrived(id);
    switch (result) {
      case Ok():
        unawaited(refresh());
        return true;
      case Err(:final error):
        messageError(error.display);
        return false;
    }
  }

  void _patchLocalStatus(String id, AppointmentStatus status) {
    final current = listState.valueOrNull;
    if (current == null) return;
    final updated = [
      for (final appt in current)
        if (appt.id == id) _withStatus(appt, status) else appt,
    ];
    listState = AsyncData(updated);
    notifyListeners();
  }
}

/// Local rebuild helper — [AppointmentSummary] has no `copyWith`; the domain
/// contract is frozen (P2-F1-owned) so one is not added here.
AppointmentSummary _withStatus(
  AppointmentSummary appt,
  AppointmentStatus status,
) => AppointmentSummary(
  id: appt.id,
  status: status,
  requestedAt: appt.requestedAt,
  note: appt.note,
  createdAt: appt.createdAt,
  branch: appt.branch,
  category: appt.category,
  account: appt.account,
  customer: appt.customer,
  accountVehicle: appt.accountVehicle,
  vehicle: appt.vehicle,
  serviceOrder: appt.serviceOrder,
  paymentStatus: appt.paymentStatus,
  arrivedAt: appt.arrivedAt,
  assignedToId: appt.assignedToId,
  assignedTo: appt.assignedTo,
);
