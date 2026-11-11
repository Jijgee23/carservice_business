import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/branches/domain/branch.dart';
import 'package:carservice_business/features/branches/domain/branches_repository.dart';
import 'package:carservice_business/features/branches/presentation/controllers/branch_form_controller.dart';
import 'package:carservice_business/features/branches/presentation/screens/branch_form_screen.dart';
import 'package:carservice_business/features/branches/presentation/screens/branch_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

User user({bool isOwner = false, List<String> permissions = const []}) => User(
  accessToken: 'a',
  refreshToken: 'r',
  id: 'u1',
  email: 'u@x.mn',
  firstName: 'Бат',
  lastName: 'Болд',
  phone: '99112233',
  isOwner: isOwner,
  role: UserRole('r1', 'Менежер', permissions),
  tenant: UserTenant('t1', 'Авто'),
);

Map<String, dynamic> detailJson({bool isPrimary = false, bool isActive = true}) => {
  'branch': {
    'id': 'b2',
    'name': 'Зайсан',
    'phone': '99001122',
    'city': 'Улаанбаатар',
    'district': 'Хан-Уул',
    'khoroo': null,
    'address': 'Зайсан гудамж',
    'latitude': 47.88,
    'longitude': 106.91,
    'openTime': '09:00',
    'closeTime': '18:00',
    'slotMinutes': 30,
    'slotCapacity': null,
    'isPrimary': isPrimary,
    'isActive': isActive,
    'tags': [
      {'id': 'tag-private', 'name': 'Хувийн шошго'},
    ],
    'tagIds': ['tag-private'],
    'employeeCount': 3,
    'schedules': [
      {'weekday': 'MON', 'isOpen': true, 'openTime': '09:00', 'closeTime': '18:00'},
      {'weekday': 'SAT', 'isOpen': true, 'openTime': '10:00', 'closeTime': '14:00'},
    ],
  },
};

class FakeBranchesRepository implements BranchesRepository {
  FakeBranchesRepository({
    this.branches = const [],
    BranchDetail? detail,
    this.tags = const [BranchTag(id: 'tag-1', name: 'Авто засвар')],
  }) : detail = detail ?? BranchDetail.fromJson(detailJson());

  List<BranchSummary> branches;
  BranchDetail detail;
  List<BranchTag> tags;

  final createdDrafts = <BranchDraft>[];
  final updates = <({BranchDraft draft, bool confirm})>[];
  AppError? createError;
  AppError? deleteError;

  /// Answered once to the first non-confirmed update.
  BranchScheduleImpactError? impactOnce;
  int deletes = 0;

  @override
  Future<Result<List<BranchSummary>>> listBranches() async => Ok(branches);

  @override
  Future<Result<BranchDetail>> getBranch(String id) async => Ok(detail);

  @override
  Future<Result<BranchDetail>> createBranch(BranchDraft draft) async {
    createdDrafts.add(draft);
    final error = createError;
    if (error != null) return Err(error);
    return Ok(detail);
  }

  @override
  Future<Result<BranchDetail>> updateBranch(String id, BranchDraft draft, {bool confirm = false}) async {
    updates.add((draft: draft, confirm: confirm));
    final impact = impactOnce;
    if (impact != null && !confirm) return Err(impact);
    return Ok(detail);
  }

  @override
  Future<Result<bool>> toggleActive(String id) async => const Ok(false);

  @override
  Future<Result<bool>> deleteBranch(String id) async {
    deletes++;
    final error = deleteError;
    return error == null ? const Ok(true) : Err(error);
  }

  @override
  Future<Result<List<BranchTag>>> listTags() async => Ok(tags);

  @override
  Future<Result<BranchPinAddress>> addressAt(double lat, double lng) async =>
      const Ok(BranchPinAddress(city: 'Улаанбаатар', district: 'Сүхбаатар', address: 'Төв талбай'));
}

Future<void> pump(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(GetMaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  group('Branch models', () {
    test('detail fills all seven weekdays in order, missing days closed', () {
      final d = BranchDetail.fromJson(detailJson());
      expect(d.schedules.map((s) => s.weekday), BranchWeekday.values);
      expect(d.schedules.first.isOpen, isTrue);
      expect(d.schedules[1].isOpen, isFalse);
      expect(d.schedules[5].openTime, '10:00');
      expect(d.latitude, 47.88);
      expect(d.slotCapacity, isNull);
      expect(d.employeeCount, 3);
    });

    test('draft JSON sends every field, empty → null', () {
      final json = BranchDraft(
        name: ' Шинэ ',
        phone: '',
        slotMinutes: '45',
        tagIds: const ['tag-1'],
        schedules: [
          for (final d in BranchWeekday.values)
            BranchDaySchedule(weekday: d, isOpen: d.openByDefault, openTime: '09:00', closeTime: '18:00'),
        ],
      ).toJson();
      expect(json['name'], 'Шинэ');
      expect(json['phone'], isNull);
      expect(json['latitude'], isNull);
      expect(json['slotMinutes'], '45');
      expect(json['slotCapacity'], isNull);
      expect(json['isPrimary'], isFalse);
      expect((json['schedules'] as List).length, 7);
      expect((json['schedules'] as List).last, containsPair('weekday', 'SUN'));
    });
  });

  group('BranchFormController', () {
    test('a shortening schedule asks to confirm, then resends confirm: true', () async {
      final repo = FakeBranchesRepository()
        ..impactOnce = const BranchScheduleImpactError(
          ErrorKind.unknown,
          'Хуваарь хадгалбал 2 захиалгын үргэлжлэх хугацаа богиносно.',
          needsConfirm: true,
          clippedCount: 2,
        );
      final c = BranchFormController(branchId: 'b2', repo: repo);
      await c.load();
      final draft = BranchDraft(name: 'Зайсан', schedules: c.branch!.schedules);

      final first = await c.submit(draft);
      expect(first, isA<BranchNeedsConfirm>());
      expect(repo.updates.single.confirm, isFalse);

      final second = await c.submit(draft, confirm: true);
      expect(second, isA<BranchSaved>());
      expect(repo.updates.last.confirm, isTrue);
    });

    test('an erasing schedule is a hard failure with the server message', () async {
      final repo = FakeBranchesRepository()
        ..impactOnce = const BranchScheduleImpactError(
          ErrorKind.unknown,
          'Хуваарь хадгалахад 1 захиалга бүрэн хүчингүй болно.',
          needsConfirm: false,
          erasedCount: 1,
        );
      final c = BranchFormController(branchId: 'b2', repo: repo);
      await c.load();
      final outcome = await c.submit(BranchDraft(name: 'Зайсан', schedules: c.branch!.schedules));
      expect(outcome, isA<BranchSaveFailed>());
      expect(c.formError, 'Хуваарь хадгалахад 1 захиалга бүрэн хүчингүй болно.');
    });

    test('the plan-limit error on create is the form error', () async {
      final repo = FakeBranchesRepository()
        ..createError = const AppError(
          ErrorKind.forbidden,
          '«Олон салбар» модуль таны багцад багтаагүй.',
          statusCode: 403,
          code: 'MODULE_DISABLED',
        );
      final c = BranchFormController(repo: repo);
      await c.load();
      final outcome = await c.submit(const BranchDraft(name: 'Хоёр', schedules: []));
      expect(outcome, isA<BranchSaveFailed>());
      expect(c.formError, '«Олон салбар» модуль таны багцад багтаагүй.');
    });

    test("the branch's own tags stay selectable", () async {
      final c = BranchFormController(branchId: 'b2', repo: FakeBranchesRepository());
      await c.load();
      expect(c.tagOptions.map((t) => t.id), containsAll(['tag-1', 'tag-private']));
    });
  });

  group('BranchListScreen', () {
    const rows = [
      BranchSummary(id: 'b1', name: 'Төв', address: 'Сүхбаатар', isPrimary: true),
      BranchSummary(id: 'b2', name: 'Зайсан', phone: '99001122'),
    ];

    testWidgets('shows the primary badge; create needs branches.create', (tester) async {
      await pump(
        tester,
        BranchListScreen(
          repository: FakeBranchesRepository(branches: rows),
          user: user(permissions: const ['branches.view']),
        ),
      );
      expect(find.text('Төв'), findsOneWidget);
      expect(find.text('Зайсан'), findsOneWidget);
      expect(find.text('Үндсэн'), findsOneWidget);
      expect(find.byKey(const ValueKey('branch_create')), findsNothing);
    });

    testWidgets('owner can create and open a branch', (tester) async {
      final opened = <String?>[];
      await pump(
        tester,
        BranchListScreen(
          repository: FakeBranchesRepository(branches: rows),
          user: user(isOwner: true),
          openForm: (_, id) async => opened.add(id),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('branch_create')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Зайсан'));
      await tester.pumpAndSettle();
      expect(opened, [null, 'b2']);
    });

    testWidgets('empty state', (tester) async {
      await pump(
        tester,
        BranchListScreen(repository: FakeBranchesRepository(), user: user(isOwner: true)),
      );
      expect(find.text('Салбар бүртгэгдээгүй байна'), findsOneWidget);
    });
  });

  group('BranchFormScreen', () {
    testWidgets('create: server field errors render inline', (tester) async {
      final repo = FakeBranchesRepository()
        ..createError = const AppError(
          ErrorKind.unknown,
          'Салбарын нэрээ оруулна уу.',
          statusCode: 400,
          code: 'VALIDATION',
          fieldErrors: {
            'name': 'Салбарын нэрээ оруулна уу.',
            'tagIds': 'Ядаж нэг шошго сонгоно уу.',
          },
        );
      await pump(tester, BranchFormScreen(repository: repo, user: user(isOwner: true)));

      expect(find.text('Шинэ салбар'), findsOneWidget);
      expect(find.byKey(const ValueKey('branch_toggle_active')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('branch_save')));
      await tester.pumpAndSettle();

      expect(find.text('Салбарын нэрээ оруулна уу.'), findsOneWidget);
      expect(find.text('Ядаж нэг шошго сонгоно уу.'), findsOneWidget);
      // New branch defaults: Mon–Fri open.
      expect(repo.createdDrafts.single.schedules.where((d) => d.isOpen).length, 5);
    });

    testWidgets('create sends tags, location and the edited fields', (tester) async {
      final repo = FakeBranchesRepository();
      await pump(
        tester,
        BranchFormScreen(
          repository: repo,
          user: user(permissions: const ['branches.create']),
          pickLocation: (_, _) async => const LatLng(47.9185, 106.9177),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('branch_name')), 'Шинэ салбар');
      await tester.tap(find.byKey(const ValueKey('branch_tag_tag-1')));
      await tester.tap(find.byKey(const ValueKey('branch_pick_location')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('branch_day_SAT')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('branch_save')));
      await tester.pumpAndSettle();

      final draft = repo.createdDrafts.single;
      expect(draft.name, 'Шинэ салбар');
      expect(draft.tagIds, ['tag-1']);
      expect(draft.latitude, 47.9185);
      expect(draft.district, 'Сүхбаатар');
      expect(draft.address, 'Төв талбай');
      expect(draft.schedules.firstWhere((d) => d.weekday == BranchWeekday.sat).isOpen, isTrue);
      await tester.pump(const Duration(seconds: 4)); // toast dedupe timer
    });

    testWidgets('edit: primary branch cannot be deleted or deactivated', (tester) async {
      await pump(
        tester,
        BranchFormScreen(
          branchId: 'b2',
          repository: FakeBranchesRepository(detail: BranchDetail.fromJson(detailJson(isPrimary: true))),
          user: user(isOwner: true),
        ),
      );
      expect(find.byKey(const ValueKey('branch_delete')), findsNothing);
      expect(find.byKey(const ValueKey('branch_toggle_active')), findsNothing);
      expect(find.text('3 ажилтан'), findsOneWidget);
    });

    testWidgets('edit: delete confirms and surfaces the in-use error', (tester) async {
      final repo = FakeBranchesRepository()
        ..deleteError = const AppError(
          ErrorKind.unknown,
          'Энэ салбарт 3 ажилтан бүртгэлтэй.',
          statusCode: 409,
          code: 'HAS_EMPLOYEES',
        );
      await pump(
        tester,
        BranchFormScreen(
          branchId: 'b2',
          repository: repo,
          user: user(permissions: const ['branches.edit', 'branches.delete']),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('branch_delete')));
      await tester.pumpAndSettle();
      // Confirm sheet.
      await tester.tap(find.text('Устгах').last);
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      // Stays on the form after the refusal.
      expect(find.byKey(const ValueKey('branch_save')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // toast dedupe timer
    });

    testWidgets('edit without branches.delete hides delete', (tester) async {
      await pump(
        tester,
        BranchFormScreen(
          branchId: 'b2',
          repository: FakeBranchesRepository(),
          user: user(permissions: const ['branches.edit']),
        ),
      );
      expect(find.byKey(const ValueKey('branch_delete')), findsNothing);
      expect(find.byKey(const ValueKey('branch_toggle_active')), findsOneWidget);
    });
  });
}
