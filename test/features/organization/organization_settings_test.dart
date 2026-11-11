import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/organization/domain/organization.dart';
import 'package:carservice_business/features/organization/domain/organization_repository.dart';
import 'package:carservice_business/features/organization/presentation/controllers/organization_settings_controller.dart';
import 'package:carservice_business/features/organization/presentation/screens/organization_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

Map<String, dynamic> tenantJson({
  bool canEdit = true,
  bool onlineBookingInPlan = true,
  int? lead = 1440,
}) => {
  'tenant': {
    'id': 't1',
    'name': 'Авто Засвар',
    'registerNumber': '1234567',
    'email': null,
    'phone1': '99112233',
    'phone2': null,
    'logoUrl': null,
    'acceptsOnlineBooking': false,
    'requireCashSession': true,
    'appointmentReminderLeadMinutes': lead,
    'slug': 'avto-zasvar',
    'plan': 'BUSINESS',
    'createdAt': '2026-01-15T03:00:00.000Z',
  },
  'modules': {'onlineBooking': onlineBookingInPlan, 'appointments': true},
  'canEdit': canEdit,
};

class FakeOrganizationRepository implements OrganizationRepository {
  FakeOrganizationRepository(this.settings);

  OrganizationSettings settings;
  final patches = <Map<String, Object?>>[];
  AppError? updateError;
  String? uploadedPath;

  @override
  Future<Result<OrganizationSettings>> load() async => Ok(settings);

  @override
  Future<Result<OrganizationSettings>> update(Map<String, Object?> patch) async {
    patches.add(patch);
    final error = updateError;
    if (error != null) return Err(error);
    final json = tenantJson(canEdit: settings.canEdit);
    (json['tenant'] as Map).addAll(patch);
    settings = OrganizationSettings.fromJson(json);
    return Ok(settings);
  }

  @override
  Future<Result<String>> uploadLogo(String path) async {
    uploadedPath = path;
    return const Ok('/uploads/logo.png');
  }

  @override
  Future<Result<bool>> removeLogo() async => const Ok(true);
}

void main() {
  group('OrganizationSettings / draft', () {
    test('parses the GET /tenant shape', () {
      final s = OrganizationSettings.fromJson(tenantJson());
      expect(s.name, 'Авто Засвар');
      expect(s.email, isNull);
      expect(s.requireCashSession, isTrue);
      expect(s.appointmentReminderLeadMinutes, 1440);
      expect(s.onlineBookingInPlan, isTrue);
      expect(s.canEdit, isTrue);
      expect(s.plan, 'BUSINESS');
      expect(s.createdAt, isNotNull);
    });

    test('patch carries only changed fields; empty optional → null', () {
      final s = OrganizationSettings.fromJson(
        tenantJson()..['tenant']['email'] = 'a@b.mn',
      );
      final patch = OrganizationDraft(
        name: ' Шинэ нэр ',
        registerNumber: '1234567',
        email: '',
        phone1: '99112233',
        phone2: '',
        acceptsOnlineBooking: true,
        requireCashSession: true,
        reminderLeadMinutes: 1440,
      ).patchFrom(s);
      expect(patch, {'name': 'Шинэ нэр', 'email': null, 'acceptsOnlineBooking': true});
    });

    test('online booking is never sent when the plan lacks it', () {
      final s = OrganizationSettings.fromJson(tenantJson(onlineBookingInPlan: false));
      final patch = OrganizationDraft(
        name: s.name,
        registerNumber: s.registerNumber,
        email: '',
        phone1: s.phone1,
        phone2: '',
        acceptsOnlineBooking: true,
        requireCashSession: false,
        reminderLeadMinutes: 90 * 60,
      ).patchFrom(s);
      expect(patch, {'requireCashSession': false, 'appointmentReminderLeadMinutes': 5400});
    });

    test('reminder lead label', () {
      expect(ReminderLead.label(60), '1 цаг');
      expect(ReminderLead.label(1500), '1 хоног 1 цаг');
      expect(ReminderLead.label(10080), '7 хоног');
    });
  });

  group('OrganizationSettingsController', () {
    test('binds server field errors inline, not as a form error', () async {
      final repo = FakeOrganizationRepository(OrganizationSettings.fromJson(tenantJson()))
        ..updateError = const AppError(
          ErrorKind.unknown,
          'Энэ нэртэй байгууллага бүртгэлтэй',
          statusCode: 409,
          fieldErrors: {'name': 'Энэ нэртэй байгууллага бүртгэлтэй'},
        );
      final c = OrganizationSettingsController(repo: repo, refreshUser: () async {});
      await c.load();
      final outcome = await c.save(
        const OrganizationDraft(
          name: 'Давхардсан',
          registerNumber: '1234567',
          email: '',
          phone1: '99112233',
          phone2: '',
          acceptsOnlineBooking: false,
          requireCashSession: true,
        ),
      );
      expect(outcome, OrganizationSaveOutcome.failed);
      expect(c.fieldErrors['name'], isNotNull);
      expect(c.formError, isNull);
    });

    test('a 403 without field errors becomes the form error', () async {
      final repo = FakeOrganizationRepository(OrganizationSettings.fromJson(tenantJson()))
        ..updateError = const AppError(ErrorKind.forbidden, 'Зөвхөн админ тохиргоог өөрчилнө.');
      final c = OrganizationSettingsController(repo: repo, refreshUser: () async {});
      await c.load();
      await c.save(
        const OrganizationDraft(
          name: 'X',
          registerNumber: '1234567',
          email: '',
          phone1: '99112233',
          phone2: '',
          acceptsOnlineBooking: false,
          requireCashSession: true,
        ),
      );
      expect(c.formError, 'Зөвхөн админ тохиргоог өөрчилнө.');
    });

    test('unchanged form makes no request; rename refreshes the cached user', () async {
      final repo = FakeOrganizationRepository(OrganizationSettings.fromJson(tenantJson()));
      var refreshed = 0;
      final c = OrganizationSettingsController(repo: repo, refreshUser: () async => refreshed++);
      await c.load();
      final s = c.settings!;
      final same = OrganizationDraft(
        name: s.name,
        registerNumber: s.registerNumber,
        email: '',
        phone1: s.phone1,
        phone2: '',
        acceptsOnlineBooking: s.acceptsOnlineBooking,
        requireCashSession: s.requireCashSession,
        reminderLeadMinutes: s.appointmentReminderLeadMinutes,
      );
      expect(await c.save(same), OrganizationSaveOutcome.unchanged);
      expect(repo.patches, isEmpty);

      final renamed = OrganizationDraft(
        name: 'Шинэ',
        registerNumber: s.registerNumber,
        email: '',
        phone1: s.phone1,
        phone2: '',
        acceptsOnlineBooking: s.acceptsOnlineBooking,
        requireCashSession: s.requireCashSession,
      );
      expect(await c.save(renamed), OrganizationSaveOutcome.saved);
      expect(repo.patches.single, {'name': 'Шинэ'});
      expect(c.settings!.name, 'Шинэ');
      expect(refreshed, 1);
    });

    test('logo upload swaps the logo url', () async {
      final repo = FakeOrganizationRepository(OrganizationSettings.fromJson(tenantJson()));
      final c = OrganizationSettingsController(repo: repo, refreshUser: () async {});
      await c.load();
      expect(await c.uploadLogo('/tmp/a.png'), isNull);
      expect(c.settings!.logoUrl, '/uploads/logo.png');
      expect(await c.removeLogo(), isNull);
      expect(c.settings!.logoUrl, isNull);
      expect(c.state, isA<AsyncData<OrganizationSettings>>());
    });
  });

  group('OrganizationSettingsScreen', () {
    Future<void> pump(WidgetTester tester, FakeOrganizationRepository repo) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        GetMaterialApp(
          home: OrganizationSettingsScreen(repository: repo, refreshUser: () async {}),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('owner edits the name and saves only that field', (tester) async {
      final repo = FakeOrganizationRepository(OrganizationSettings.fromJson(tenantJson()));
      await pump(tester, repo);

      expect(find.text('Онлайн цаг захиалга'), findsOneWidget);
      expect(find.text('Касс заавал нээх'), findsOneWidget);
      expect(find.text('avto-zasvar'), findsOneWidget);
      expect(find.text('Бизнес'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('org_name')), 'Шинэ нэр');
      await tester.tap(find.byKey(const ValueKey('org_save')));
      await tester.pumpAndSettle();

      expect(repo.patches.single, {'name': 'Шинэ нэр'});
      await tester.pump(const Duration(seconds: 4)); // toast dedupe timer
    });

    testWidgets('non-owner sees read-only fields and no save button', (tester) async {
      final repo = FakeOrganizationRepository(
        OrganizationSettings.fromJson(tenantJson(canEdit: false)),
      );
      await pump(tester, repo);

      expect(find.byKey(const ValueKey('org_save')), findsNothing);
      expect(find.byKey(const ValueKey('org_logo_pick')), findsNothing);
      expect(find.text('Тохиргоог зөвхөн байгууллагын эзэмшигч өөрчилнө.'), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const ValueKey('org_name')));
      expect(field.enabled, isFalse);
    });

    testWidgets('online booking toggle is hidden when the plan lacks it', (tester) async {
      final repo = FakeOrganizationRepository(
        OrganizationSettings.fromJson(tenantJson(onlineBookingInPlan: false)),
      );
      await pump(tester, repo);

      expect(find.byKey(const ValueKey('org_online_booking')), findsNothing);
      expect(find.text('Таны багц онлайн цаг захиалгыг дэмжихгүй байна.'), findsOneWidget);
    });

    testWidgets('server field error shows under the field', (tester) async {
      final repo = FakeOrganizationRepository(OrganizationSettings.fromJson(tenantJson()))
        ..updateError = const AppError(
          ErrorKind.unknown,
          'Утасны дугаар 8 оронтой тоо байх ёстой.',
          statusCode: 400,
          fieldErrors: {'phone1': 'Утасны дугаар 8 оронтой тоо байх ёстой.'},
        );
      await pump(tester, repo);

      await tester.enterText(find.byKey(const ValueKey('org_phone1')), '1234');
      await tester.tap(find.byKey(const ValueKey('org_save')));
      await tester.pumpAndSettle();

      expect(find.text('Утасны дугаар 8 оронтой тоо байх ёстой.'), findsOneWidget);
    });
  });
}
