import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/create_appointment_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_appointment_repository.dart';

/// P2-F4 — staff appointment registration: slot picking, category
/// selection, 409 conflict handling and 422 field-error binding.
///
/// P2-F4a's regression is still pinned here: `canSubmit` must never enable
/// while `submit()` would still fail server-side. It now also folds in the
/// selected slot, since booking without a real slot from
/// `GET /appointments/slots` is exactly the same defect class.
void main() {
  const branch = BranchSummary(id: 'branch-1', name: 'Branch');
  const customer = CustomerSummary(
    id: 'cust-1',
    fullName: 'Бат Дорж',
    phone: '99112233',
  );

  /// [FakeAppointmentRepository.getSlots] always returns a single bookable
  /// slot regardless of branch/date/category — selecting it is the
  /// controller's real slot-picking path exercised end to end.
  Future<void> selectFirstSlot(CreateAppointmentController ctrl) async {
    final slot = ctrl.availability!.slots.first;
    ctrl.selectSlot(slot);
  }

  test('canSubmit is false with no branch and no customer', () async {
    final ctrl = CreateAppointmentController(repo: FakeAppointmentRepository());

    expect(ctrl.canSubmit, isFalse);
    ctrl.dispose();
  });

  test('canSubmit is false with a branch but no customer selected', () async {
    final ctrl = CreateAppointmentController(repo: FakeAppointmentRepository());
    await ctrl.selectBranch(branch);

    expect(ctrl.canSubmit, isFalse);
    ctrl.dispose();
  });

  test(
    'canSubmit is false with a branch and customer but no slot selected',
    () async {
      final ctrl = CreateAppointmentController(
        repo: FakeAppointmentRepository(),
      );
      await ctrl.selectBranch(branch);
      ctrl.selectCustomer(customer);

      expect(ctrl.canSubmit, isFalse);
      ctrl.dispose();
    },
  );

  test('canSubmit becomes true only once branch, customer and a bookable slot '
      'are all set — and submit() actually succeeds at that point (no '
      'enabled-then-fails dead end)', () async {
    final ctrl = CreateAppointmentController(repo: FakeAppointmentRepository());
    await ctrl.selectBranch(branch);
    expect(ctrl.canSubmit, isFalse);

    ctrl.selectCustomer(customer);
    expect(ctrl.canSubmit, isFalse);

    await selectFirstSlot(ctrl);
    expect(ctrl.canSubmit, isTrue);

    final result = await ctrl.submit();

    expect(result, isNotNull);
    ctrl.dispose();
  });

  test('create-customer-then-book: selecting a freshly created customer (as '
      'returned by the shared new-customer sheet) makes the controller '
      'submittable and books against that customer id', () async {
    final repo = FakeAppointmentRepository();
    final ctrl = CreateAppointmentController(repo: repo);
    await ctrl.selectBranch(branch);

    // Simulates the screen's `_openAddCustomer` flow: the sheet returns a
    // newly created CustomerSummary, which becomes `selectedCustomer` via
    // the same `selectCustomer` setter used by the search-result path —
    // one booking path, no separate walk-in creation call.
    const createdCustomer = CustomerSummary(
      id: 'cust-new',
      fullName: 'Шинэ Үйлчлүүлэгч',
      phone: '88112233',
    );
    ctrl.selectCustomer(createdCustomer);
    await selectFirstSlot(ctrl);

    expect(ctrl.canSubmit, isTrue);

    final result = await ctrl.submit();

    expect(result, isNotNull);
    expect(result!.customer?.id, 'cust-new');
    // And the repository actually recorded a booking against that id.
    final list = await repo.getAppointments();
    expect(
      (list as Ok).value.items.any((a) => a.customer?.id == 'cust-new'),
      isTrue,
    );
    ctrl.dispose();
  });

  test('submit() is a no-op when canSubmit is false (defensive guard, not the '
      'primary precondition surface)', () async {
    final ctrl = CreateAppointmentController(repo: FakeAppointmentRepository());

    final result = await ctrl.submit();

    expect(result, isNull);
    ctrl.dispose();
  });

  test(
    'a server-side createAppointment failure surfaces without crashing',
    () async {
      final repo = _FailingAppointmentsRepository();
      final ctrl = CreateAppointmentController(repo: repo);
      await ctrl.selectBranch(branch);
      ctrl.selectCustomer(customer);
      await selectFirstSlot(ctrl);

      final result = await ctrl.submit();

      expect(result, isNull);
      expect(ctrl.submitting, isFalse);
      ctrl.dispose();
    },
  );

  test('a 409 slot conflict clears the selected slot, re-fetches slots and '
      'never retries the submit automatically', () async {
    final repo = _ConflictThenOkRepository();
    final ctrl = CreateAppointmentController(repo: repo);
    await ctrl.selectBranch(branch);
    ctrl.selectCustomer(customer);
    await selectFirstSlot(ctrl);
    expect(ctrl.canSubmit, isTrue);

    final result = await ctrl.submit();

    // The conflict is surfaced, not silently retried: submit() returns
    // null exactly once and does not itself attempt a second create call.
    expect(result, isNull);
    expect(repo.createCallCount, 1);
    // Slots were re-fetched from the server (never invented locally) and
    // the stale selection was dropped, so a stale button state cannot
    // resubmit the same conflicting slot.
    expect(repo.getSlotsCallCount, 2);
    expect(ctrl.selectedSlot, isNull);
    expect(ctrl.canSubmit, isFalse);
    ctrl.dispose();
  });

  test('422 field errors bind to their specific fields rather than a generic '
      'message', () async {
    final repo = _FieldErrorRepository();
    final ctrl = CreateAppointmentController(repo: repo);
    await ctrl.selectBranch(branch);
    ctrl.selectCustomer(customer);
    await selectFirstSlot(ctrl);

    final result = await ctrl.submit();

    expect(result, isNull);
    expect(ctrl.fieldError('note'), 'Тэмдэглэл хэт урт байна.');
    expect(ctrl.fieldErrors, isNotNull);
    ctrl.dispose();
  });

  test(
    'isSlotBookable rejects a past slot even when the server marks it '
    'available, and rejects a future slot the server marks unavailable',
    () async {
      final ctrl = CreateAppointmentController(
        repo: FakeAppointmentRepository(),
      );
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final future = DateTime.now().add(const Duration(hours: 1));

      final pastSlot = AppointmentSlot(
        time: '00:00',
        iso: past.toIso8601String(),
        available: true,
        remaining: 5,
      );
      final fullSlot = AppointmentSlot(
        time: '00:00',
        iso: future.toIso8601String(),
        available: false,
        remaining: 0,
      );
      final bookableSlot = AppointmentSlot(
        time: '00:00',
        iso: future.toIso8601String(),
        available: true,
        remaining: 1,
      );

      expect(ctrl.isSlotBookable(pastSlot), isFalse);
      expect(ctrl.isSlotBookable(fullSlot), isFalse);
      expect(ctrl.isSlotBookable(bookableSlot), isTrue);

      // A tap on a non-bookable slot must not select it.
      ctrl.selectSlot(pastSlot);
      expect(ctrl.selectedSlot, isNull);
      ctrl.selectSlot(fullSlot);
      expect(ctrl.selectedSlot, isNull);
      ctrl.selectSlot(bookableSlot);
      expect(ctrl.selectedSlot, bookableSlot);

      ctrl.dispose();
    },
  );
}

/// Minimal repository that always fails createAppointment, to confirm the
/// controller's error path leaves `submitting` reset and returns null
/// without throwing.
class _FailingAppointmentsRepository extends FakeAppointmentRepository {
  @override
  Future<Result<AppointmentSummary>> createAppointment({
    required String branchId,
    required String customerId,
    String? vehicleId,
    required DateTime requestedAt,
    String? note,
    List<String> categoryIds = const [],
    bool confirmed = false,
    String? assignedToId,
  }) async => const Err(AppError(ErrorKind.unknown, 'boom'));
}

/// Fails the first create with a 409 (mirrors a reservation conflict) and
/// counts calls to both `createAppointment` and `getSlots`, so the test can
/// assert the controller re-fetches slots exactly once per conflict and
/// never retries the create call by itself.
class _ConflictThenOkRepository extends FakeAppointmentRepository {
  int createCallCount = 0;
  int getSlotsCallCount = 0;

  @override
  Future<Result<AppointmentDayAvailability>> getSlots({
    String? branchId,
    required DateTime date,
    List<String> categoryIds = const [],
  }) async {
    getSlotsCallCount++;
    return super.getSlots(
      branchId: branchId,
      date: date,
      categoryIds: categoryIds,
    );
  }

  @override
  Future<Result<AppointmentSummary>> createAppointment({
    required String branchId,
    required String customerId,
    String? vehicleId,
    required DateTime requestedAt,
    String? note,
    List<String> categoryIds = const [],
    bool confirmed = false,
    String? assignedToId,
  }) async {
    createCallCount++;
    return const Err(
      AppError(
        ErrorKind.unknown,
        'Энэ цаг аль хэдийн авагдсан байна.',
        statusCode: 409,
        code: 'RESERVATION_CONFLICT',
      ),
    );
  }
}

/// Fails createAppointment with a 422 carrying a field-specific error, the
/// same shape the real API returns for validation failures.
class _FieldErrorRepository extends FakeAppointmentRepository {
  @override
  Future<Result<AppointmentSummary>> createAppointment({
    required String branchId,
    required String customerId,
    String? vehicleId,
    required DateTime requestedAt,
    String? note,
    List<String> categoryIds = const [],
    bool confirmed = false,
    String? assignedToId,
  }) async => const Err(
    AppError(
      ErrorKind.unknown,
      'Тэмдэглэл хэт урт байна.',
      statusCode: 422,
      code: 'VALIDATION_ERROR',
      fieldErrors: {'note': 'Тэмдэглэл хэт урт байна.'},
    ),
  );
}
