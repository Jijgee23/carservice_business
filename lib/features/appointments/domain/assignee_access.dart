import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/features/appointments/domain/appointment_error_codes.dart';

/// Whether the signed-in user may choose an appointment/order master
/// (`orders.assign`, or the owner). Mirrors `create_order_screen.dart`.
///
/// Reads [Authenticator.user], which needs the Hive box; before it is opened
/// (unit tests, very early startup) this answers `false` rather than throwing.
bool currentUserCanAssign() {
  try {
    final user = Authenticator.user;
    return user?.isOwner == true ||
        user?.role?.permissions.contains('orders.assign') == true;
  } catch (_) {
    return false;
  }
}

String? currentUserIdOrNull() {
  try {
    return Authenticator.user?.id;
  } catch (_) {
    return null;
  }
}

extension AppointmentAssigneeError on AppError {
  /// `ASSIGNEE_REQUIRED` carries the user-facing text in
  /// `fieldErrors.assignedToId`; show that, otherwise the usual message.
  String get assigneeAwareMessage {
    if (code == AppointmentErrorCodes.assigneeRequired) {
      return fieldErrors?['assignedToId'] ?? display;
    }
    return display;
  }
}

/// Shown inline when a user without `orders.assign` who is not an eligible
/// master tries to create / confirm an appointment (server 422
/// `ASSIGNEE_REQUIRED`).
const kAssigneeNoPermissionReason =
    'Цаг бүртгэхэд хариуцах мастер шаардлагатай. Танд мастер оноох эрх '
    '(orders.assign) байхгүй тул менежерт хандана уу.';

/// Shown in place of the picker when the branch has no eligible master.
const kNoEligibleAssigneeReason = 'Энэ салбарт сонгох боломжтой мастер алга.';
