import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/appointments/data/appointment_repository.dart';
import 'package:carservice_business/features/appointments/data/appointments_data_source.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/create_appointment_controller.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_detail_screen.dart';
import 'package:carservice_business/features/appointments/domain/assignee_access.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/assignee_picker_field.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_appointment_repository.dart';
import '../../fakes/fake_order_repository.dart';

// ─── helpers ────────────────────────────────────────────────────────────────

class _Source implements AppointmentsDataSource {
  String? lastCall;
  Map<String, dynamic>? lastBody;
  Object? response;

  Future<Object?> _rec(String name, [Map<String, dynamic>? body]) async {
    lastCall = name;
    lastBody = body;
    return response;
  }

  @override
  Future<Object?> create(Map<String, dynamic> body) => _rec('create', body);
  @override
  Future<Object?> confirm(String id, {Map<String, dynamic>? body}) =>
      _rec('confirm', body);
  @override
  Future<Object?> update(String id, Map<String, dynamic> body) =>
      _rec('update', body);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _backend422 = {
  'error': 'Хариуцах мастер сонгоно уу.',
  'code': 'ASSIGNEE_REQUIRED',
  'fieldErrors': {'assignedToId': 'Хариуцах мастер сонгоно уу.'},
};

/// Real transport seam: a Dio that answers every request with the backend's
/// 422 JSON, mapped by `mapDioException` inside the data source.
RemoteAppointmentsRepository _http422Repo() {
  final dio = Dio(BaseOptions(baseUrl: 'http://x/'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) => h.reject(
        DioException.badResponse(
          statusCode: 422,
          requestOptions: o,
          response: Response(
            requestOptions: o,
            statusCode: 422,
            data: _backend422,
          ),
        ),
      ),
    ),
  );
  return RemoteAppointmentsRepository(
    dataSource: RemoteAppointmentsDataSource(dio: dio),
  );
}

/// Fake whose create/confirm go through the 422 HTTP stub.
class _Http422Repo extends _RecordingRepo {
  final _remote = _http422Repo();
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
  }) => _remote.createAppointment(
    branchId: branchId,
    customerId: customerId,
    requestedAt: requestedAt,
  );

  @override
  Future<Result<AppointmentLifecycleResult>> confirm(
    String appointmentId, {
    String? assignedToId,
  }) {
    confirmCalls++;
    return _remote.confirm(appointmentId, assignedToId: assignedToId);
  }
}

class _BranchUsersRepo extends FakeOrderRepository {
  @override
  Future<Result<List<AssignableUser>>> getAssignableUsers({
    String? branchId,
  }) async => Ok(
    branchId == 'branch-1'
        ? const [AssignableUser(id: 'u-a', firstName: 'A', lastName: 'A')]
        : const [AssignableUser(id: 'u-b', firstName: 'B', lastName: 'B')],
  );
}

class _RecordingRepo extends FakeAppointmentRepository {
  _RecordingRepo({super.seed});
  String? createdAssignee;
  bool createCalled = false;
  String? confirmedAssignee;
  int confirmCalls = 0;
  String? patchedAssignee;
  Result<AppointmentSummary>? createResult;
  int failConfirmWithAssigneeRequired = 0;

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
  }) {
    createCalled = true;
    createdAssignee = assignedToId;
    final forced = createResult;
    if (forced != null) return Future.value(forced);
    return super.createAppointment(
      branchId: branchId,
      customerId: customerId,
      vehicleId: vehicleId,
      requestedAt: requestedAt,
      note: note,
      categoryIds: categoryIds,
      confirmed: confirmed,
      assignedToId: assignedToId,
    );
  }

  @override
  Future<Result<AppointmentLifecycleResult>> confirm(
    String appointmentId, {
    String? assignedToId,
  }) {
    confirmCalls++;
    if (failConfirmWithAssigneeRequired > 0) {
      failConfirmWithAssigneeRequired--;
      return Future.value(
        const Err(
          AppError(
            ErrorKind.unknown,
            'x',
            statusCode: 422,
            code: 'ASSIGNEE_REQUIRED',
            fieldErrors: {
              'assignedToId': 'Цаг захиалгын мастер идэвхгүй болсон тул өөр мастер сонгоно уу.',
            },
          ),
        ),
      );
    }
    confirmedAssignee = assignedToId;
    return super.confirm(appointmentId, assignedToId: assignedToId);
  }

  @override
  Future<Result<AppointmentSummary>> updateAssignee(
    String appointmentId,
    String assignedToId,
  ) {
    patchedAssignee = assignedToId;
    return super.updateAssignee(appointmentId, assignedToId);
  }
}

User _user({required bool assign}) => User(
  accessToken: 't',
  refreshToken: 'r',
  id: 'user-1',
  email: 'u@example.com',
  firstName: 'U',
  lastName: 'U',
  phone: '',
  isOwner: false,
  role: UserRole('r1', 'Staff', [
    'appointments.edit',
    if (assign) 'orders.assign',
  ]),
  tenant: UserTenant('t1', 'Tenant'),
);

AppointmentSummary _appt({
  AppointmentStatus status = AppointmentStatus.PENDING,
  String? assignedToId,
  AppointmentAssigneeRef? assignedTo,
}) => AppointmentSummary(
  id: 'a1',
  status: status,
  requestedAt: DateTime.now().add(const Duration(days: 1)),
  branch: const AppointmentBranchRef(id: 'b1', name: 'Салбар'),
  customer: const AppointmentCustomerRef(
    id: 'c1',
    fullName: 'Бат',
    phone: '99112233',
  ),
  assignedToId: assignedToId,
  assignedTo: assignedTo,
);

Future<void> _pumpDetail(
  WidgetTester tester,
  AppointmentSummary appt,
  _RecordingRepo repo, {
  required bool assign,
}) async {
  await tester.binding.setSurfaceSize(const Size(1024, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: AppointmentDetailScreen(
        initial: appt,
        repo: repo,
        ordersRepository: FakeOrderRepository(),
        user: _user(assign: assign),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  const branch = BranchSummary(id: 'branch-1', name: 'Branch');
  const customer = CustomerSummary(
    id: 'cust-1',
    fullName: 'Бат Дорж',
    phone: '99112233',
  );

  group('DTO parsing', () {
    test('parses assignedToId and assignedTo {id, name}', () {
      final a = AppointmentSummary.fromJson({
        'id': 'a1',
        'status': 'PENDING',
        'assignedToId': 'u9',
        'assignedTo': {'id': 'u9', 'name': 'Дорж Бат'},
      });
      expect(a.assignedToId, 'u9');
      expect(a.assignedTo?.id, 'u9');
      expect(a.assignedTo?.name, 'Дорж Бат');
      expect(a.assigneeName, 'Дорж Бат');
    });

    test('defaults to null when the fields are absent or null', () {
      final absent = AppointmentSummary.fromJson({
        'id': 'a1',
        'status': 'PENDING',
      });
      expect(absent.assignedToId, isNull);
      expect(absent.assignedTo, isNull);
      expect(absent.assigneeName, isNull);

      final nulls = AppointmentSummary.fromJson({
        'id': 'a1',
        'status': 'PENDING',
        'assignedToId': null,
        'assignedTo': null,
      });
      expect(nulls.assignedToId, isNull);
      expect(nulls.assignedTo, isNull);
    });
  });

  group('repository wire format', () {
    test('create sends assignedToId only when given', () async {
      final source = _Source()
        ..response = {
          'appointment': {'id': 'a1', 'status': 'CONFIRMED'},
        };
      final repo = RemoteAppointmentsRepository(dataSource: source);
      final at = DateTime.now().add(const Duration(days: 1));
      await repo.createAppointment(
        branchId: 'b',
        customerId: 'c',
        requestedAt: at,
        assignedToId: 'u1',
      );
      expect(source.lastBody?['assignedToId'], 'u1');
      await repo.createAppointment(
        branchId: 'b',
        customerId: 'c',
        requestedAt: at,
      );
      expect(source.lastBody?.containsKey('assignedToId'), isFalse);
    });

    test('confirm sends {assignedToId} body only when given', () async {
      final source = _Source()..response = {'ok': true, 'appointmentId': 'a1'};
      final repo = RemoteAppointmentsRepository(dataSource: source);
      await repo.confirm('a1', assignedToId: 'u1');
      expect(source.lastBody, {'assignedToId': 'u1'});
      await repo.confirm('a1');
      expect(source.lastBody, isNull);
    });

    test('updateAssignee PATCHes {assignedToId} and parses the row', () async {
      final source = _Source()
        ..response = {
          'appointment': {
            'id': 'a1',
            'status': 'CONFIRMED',
            'assignedToId': 'u2',
            'assignedTo': {'id': 'u2', 'name': 'Х'},
          },
        };
      final repo = RemoteAppointmentsRepository(dataSource: source);
      final result = await repo.updateAssignee('a1', 'u2');
      expect(source.lastCall, 'update');
      expect(source.lastBody, {'assignedToId': 'u2'});
      expect((result as Ok<AppointmentSummary>).value.assignedToId, 'u2');
    });
  });

  group('create form (controller)', () {
    test('assigners must pick a master; the current user is preselected '
        'and sent on POST', () async {
      final repo = _RecordingRepo();
      final ctrl = CreateAppointmentController(
        repo: repo,
        ordersRepo: FakeOrderRepository(),
        canAssign: true,
        currentUserId: 'user-1',
      );
      addTearDown(ctrl.dispose);
      await ctrl.selectBranch(branch);
      await Future<void>.delayed(Duration.zero);
      ctrl.selectCustomer(customer);
      ctrl.selectSlot(ctrl.availability!.slots.first);

      expect(ctrl.assignee?.id, 'user-1');
      expect(ctrl.canSubmit, isTrue);
      expect(await ctrl.submit(), isNotNull);
      expect(repo.createdAssignee, 'user-1');
    });

    test('canSubmit stays false until a master is chosen', () async {
      final repo = _RecordingRepo();
      final ctrl = CreateAppointmentController(
        repo: repo,
        ordersRepo: FakeOrderRepository(),
        canAssign: true,
        currentUserId: 'someone-not-listed',
      );
      addTearDown(ctrl.dispose);
      await ctrl.selectBranch(branch);
      await Future<void>.delayed(Duration.zero);
      ctrl.selectCustomer(customer);
      ctrl.selectSlot(ctrl.availability!.slots.first);

      expect(ctrl.assignee, isNull);
      expect(ctrl.canSubmit, isFalse);
      expect(await ctrl.submit(), isNull);
      expect(repo.createCalled, isFalse);

      ctrl.selectAssignee(ctrl.assignees.first);
      expect(ctrl.canSubmit, isTrue);
    });

    test('users without orders.assign: no picker state, no id sent', () async {
      final repo = _RecordingRepo();
      final ctrl = CreateAppointmentController(
        repo: repo,
        ordersRepo: FakeOrderRepository(),
        canAssign: false,
      );
      addTearDown(ctrl.dispose);
      await ctrl.selectBranch(branch);
      await Future<void>.delayed(Duration.zero);
      ctrl.selectCustomer(customer);
      ctrl.selectSlot(ctrl.availability!.slots.first);

      expect(ctrl.assignees, isEmpty);
      expect(ctrl.canSubmit, isTrue);
      await ctrl.submit();
      expect(repo.createdAssignee, isNull);
    });

    test('422 ASSIGNEE_REQUIRED binds fieldErrors.assignedToId inline and '
        'selecting a master clears it', () async {
      final repo = _RecordingRepo()
        ..createResult = const Err(
          AppError(
            ErrorKind.unknown,
            'Хариуцах мастер сонгоно уу.',
            statusCode: 422,
            code: 'ASSIGNEE_REQUIRED',
            fieldErrors: {'assignedToId': 'Хариуцах мастер сонгоно уу.'},
          ),
        );
      final ctrl = CreateAppointmentController(
        repo: repo,
        ordersRepo: FakeOrderRepository(),
        canAssign: true,
        currentUserId: 'user-1',
      );
      addTearDown(ctrl.dispose);
      await ctrl.selectBranch(branch);
      await Future<void>.delayed(Duration.zero);
      ctrl.selectCustomer(customer);
      ctrl.selectSlot(ctrl.availability!.slots.first);

      expect(await ctrl.submit(), isNull);
      expect(ctrl.fieldError('assignedToId'), 'Хариуцах мастер сонгоно уу.');
      ctrl.selectAssignee(ctrl.assignees.first);
      expect(ctrl.fieldError('assignedToId'), isNull);
    });
  });

  group('ineligible / empty cases', () {
    test('non-assigner refused with ASSIGNEE_REQUIRED sees the inline '
        'reason', () async {
      final repo = _RecordingRepo()
        ..createResult = const Err(
          AppError(
            ErrorKind.unknown,
            'x',
            statusCode: 422,
            code: 'ASSIGNEE_REQUIRED',
            fieldErrors: {'assignedToId': 'Хариуцах мастер сонгоно уу.'},
          ),
        );
      final ctrl = CreateAppointmentController(
        repo: repo,
        ordersRepo: FakeOrderRepository(),
        canAssign: false,
      );
      addTearDown(ctrl.dispose);
      await ctrl.selectBranch(branch);
      ctrl.selectCustomer(customer);
      ctrl.selectSlot(ctrl.availability!.slots.first);
      await ctrl.submit();
      expect(ctrl.assigneeBlockedReason, kAssigneeNoPermissionReason);
    });

    testWidgets('branch with no eligible master shows the reason', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: AssigneePickerField(
              users: const [],
              selected: null,
              loading: false,
              error: null,
              onChanged: (_) {},
              onRetry: () {},
            ),
          ),
        ),
      );
      expect(find.text(kNoEligibleAssigneeReason), findsOneWidget);
    });

    testWidgets('confirm refused for an inactive stored master re-prompts '
        'the picker and retries', (tester) async {
      final appt = _appt(
        assignedToId: 'gone',
        assignedTo: const AppointmentAssigneeRef(id: 'gone', name: 'Хуучин'),
      );
      final repo = _RecordingRepo(seed: [appt])
        ..failConfirmWithAssigneeRequired = 1;
      await _pumpDetail(tester, appt, repo, assign: true);

      await tester.tap(
        find.byKey(const ValueKey('appointment_confirm_button')),
      );
      await tester.pumpAndSettle();
      expect(repo.confirmCalls, 1);
      expect(
        find.text(
          'Цаг захиалгын мастер идэвхгүй болсон тул өөр мастер сонгоно уу.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('appointment_assignee_sheet_picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fake User').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('appointment_assignee_sheet_confirm')),
      );
      await tester.pumpAndSettle();
      expect(repo.confirmCalls, 2);
      expect(repo.confirmedAssignee, 'user-1');
    });
  });

  group('real HTTP 422 through mapDioException', () {
    test('create: code + fieldErrors reach the controller', () async {
      final ctrl = CreateAppointmentController(
        repo: _Http422Repo(),
        ordersRepo: FakeOrderRepository(),
        canAssign: true,
        currentUserId: 'user-1',
      );
      addTearDown(ctrl.dispose);
      await ctrl.selectBranch(branch);
      await Future<void>.delayed(Duration.zero);
      ctrl.selectCustomer(customer);
      ctrl.selectSlot(ctrl.availability!.slots.first);
      expect(await ctrl.submit(), isNull);
      expect(ctrl.fieldError('assignedToId'), 'Хариуцах мастер сонгоно уу.');
    });

    test('confirm: AppError carries the code and fieldErrors', () async {
      final r = await _http422Repo().confirm('a1');
      final err = (r as Err<AppointmentLifecycleResult>).error;
      expect(err.statusCode, 422);
      expect(err.code, 'ASSIGNEE_REQUIRED');
      expect(err.fieldErrors?['assignedToId'], 'Хариуцах мастер сонгоно уу.');
    });

    testWidgets('detail: assigner is re-prompted; non-assigner sees the '
        'reason inline', (tester) async {
      final appt = _appt();
      final repo = _Http422Repo();
      await _pumpDetail(tester, appt, repo, assign: false);
      await tester.tap(
        find.byKey(const ValueKey('appointment_confirm_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('appointment_confirm_blocked_reason')),
        findsOneWidget,
      );
      expect(find.text(kAssigneeNoPermissionReason), findsOneWidget);
    });
  });

  test(
    'switching branch reloads the list and drops an ineligible master',
    () async {
      final ctrl = CreateAppointmentController(
        repo: _RecordingRepo(),
        ordersRepo: _BranchUsersRepo(),
        canAssign: true,
        currentUserId: 'u-a',
      );
      addTearDown(ctrl.dispose);
      await ctrl.selectBranch(branch);
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.assignee?.id, 'u-a');

      await ctrl.selectBranch(const BranchSummary(id: 'branch-2', name: 'B2'));
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.assignees.map((u) => u.id), ['u-b']);
      expect(ctrl.assignee, isNull);
      expect(ctrl.canSubmit, isFalse);
    },
  );

  group('detail screen', () {
    testWidgets('no master + orders.assign: confirm asks for the master first '
        'and sends it in the confirm body', (tester) async {
      final appt = _appt();
      final repo = _RecordingRepo(seed: [appt]);
      await _pumpDetail(tester, appt, repo, assign: true);

      await tester.tap(
        find.byKey(const ValueKey('appointment_confirm_button')),
      );
      await tester.pumpAndSettle();

      // Prompt is shown, nothing was sent yet.
      expect(find.text('Хариуцах мастер сонгох'), findsOneWidget);
      expect(repo.confirmCalls, 0);
      // No clear / "none" affordance anywhere in the sheet.
      expect(find.text('Арилгах'), findsNothing);
      expect(find.text('Оноохгүй'), findsNothing);
      // Confirm stays disabled until a master is picked.
      final confirmBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('appointment_assignee_sheet_confirm')),
      );
      expect(confirmBtn.onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('appointment_assignee_sheet_picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fake User').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('appointment_assignee_sheet_confirm')),
      );
      await tester.pumpAndSettle();

      expect(repo.confirmCalls, 1);
      expect(repo.confirmedAssignee, 'user-1');
      expect(
        find.byKey(const ValueKey('appointment_assignee_value')),
        findsOneWidget,
      );
      // The fake echoes only the id (no name), so the row shows the
      // generic assigned label rather than "none".
      expect(find.text('Оноогдсон'), findsOneWidget);
      expect(find.text('Оноогоогүй'), findsNothing);
    });

    testWidgets('master already set: confirm goes straight through', (
      tester,
    ) async {
      final appt = _appt(
        assignedToId: 'user-1',
        assignedTo: const AppointmentAssigneeRef(id: 'user-1', name: 'Мастер'),
      );
      final repo = _RecordingRepo(seed: [appt]);
      await _pumpDetail(tester, appt, repo, assign: true);

      expect(find.text('Мастер'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('appointment_confirm_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Хариуцах мастер сонгох'), findsNothing);
      expect(repo.confirmCalls, 1);
      expect(repo.confirmedAssignee, isNull);
    });

    testWidgets('without orders.assign: no prompt, no change button', (
      tester,
    ) async {
      final appt = _appt();
      final repo = _RecordingRepo(seed: [appt]);
      await _pumpDetail(tester, appt, repo, assign: false);

      expect(
        find.byKey(const ValueKey('appointment_change_assignee_button')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('appointment_confirm_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Хариуцах мастер сонгох'), findsNothing);
      expect(repo.confirmCalls, 1);
      expect(repo.confirmedAssignee, isNull);
    });

    testWidgets('assigners can change the master via PATCH; the sheet has no '
        'clear option', (tester) async {
      final appt = _appt(
        status: AppointmentStatus.CONFIRMED,
        assignedToId: 'old',
        assignedTo: const AppointmentAssigneeRef(id: 'old', name: 'Хуучин'),
      );
      final repo = _RecordingRepo(seed: [appt]);
      await _pumpDetail(tester, appt, repo, assign: true);

      await tester.tap(
        find.byKey(const ValueKey('appointment_change_assignee_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Мастер солих'), findsOneWidget);
      expect(find.text('Арилгах'), findsNothing);
      expect(find.text('Оноохгүй'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('appointment_assignee_sheet_picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fake User').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('appointment_assignee_sheet_confirm')),
      );
      await tester.pumpAndSettle();

      expect(repo.patchedAssignee, 'user-1');
      // The fake echoes only the id (no name), so the row shows the
      // generic assigned label rather than "none".
      expect(find.text('Оноогдсон'), findsOneWidget);
      expect(find.text('Оноогоогүй'), findsNothing);
    });
  });
}
