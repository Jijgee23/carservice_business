abstract final class AppointmentErrorCodes {
  static const overdue = 'APPOINTMENT_OVERDUE';

  /// 422 — the appointment has no master and none was supplied (create /
  /// confirm), or an attempt to clear the master (PATCH `assignedToId: null`).
  /// `fieldErrors.assignedToId` carries the user-facing message.
  static const assigneeRequired = 'ASSIGNEE_REQUIRED';
}
