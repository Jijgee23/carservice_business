import 'dart:typed_data';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/orders/data/order_dto.dart';
import 'package:carservice_business/features/orders/data/order_repository.dart';
import 'package:carservice_business/features/orders/data/order_settings_service.dart';
import 'package:carservice_business/features/orders/data/orders_data_source.dart';
import 'package:carservice_business/features/orders/domain/order_settings.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_intake_controller.dart';
import 'package:carservice_business/features/orders/presentation/widgets/intake/intake_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../fakes/fake_order_repository.dart';

const _settingsJson = {
  'settings': {
    'requireAssignee': false,
    'requireMileage': true,
    'requireSignature': true,
    'minIntakePhotos': 2,
    'requireChecklist': true,
    'intakeChecklist': [
      {'id': 'c1', 'label': 'Тосны түвшин'},
      {'id': 'c2', 'label': ' Дугуй '},
      {'id': '', 'label': 'skip'},
    ],
    'requireDiagnosticsFilled': false,
    'requireItemsCompleted': false,
    'allowCloseUnpaid': true,
  },
  'canEdit': true,
};

void main() {
  group('OrderSettings', () {
    test('parses GET /tenant/order-settings', () {
      final s = OrderSettings.fromJson(_settingsJson);
      expect(s.requireAssignee, isFalse);
      expect(s.requireMileage, isTrue);
      expect(s.minIntakePhotos, 2);
      expect(s.intakeChecklist.map((c) => c.label), ['Тосны түвшин', 'Дугуй']);
      expect(s.checklistRequired, isTrue);
      expect(s.hasIntakeRequirements, isTrue);
      expect(s.requireItemsCompleted, isFalse);
      expect(s.allowCloseUnpaid, isTrue);
      expect(s.canEdit, isTrue);
    });

    test('junk falls back to the old strict defaults', () {
      final s = OrderSettings.fromJson({'settings': 'x'});
      expect(s.requireAssignee, isTrue);
      expect(s.requireItemsCompleted, isTrue);
      expect(s.allowCloseUnpaid, isFalse);
      expect(s.hasIntakeRequirements, isFalse);
    });

    test('service caches and swallows failures', () async {
      final service = OrderSettingsService.instance..invalidate();
      addTearDown(() {
        service
          ..loaderOverride = null
          ..invalidate();
      });
      service.loaderOverride = () async => throw StateError('404');
      expect(await service.get(), isNull);
      expect(service.current.requireAssignee, isTrue);
      service.loaderOverride = () async => _settingsJson;
      expect((await service.get())!.minIntakePhotos, 2);
      expect(service.cached, isNotNull);
    });
  });

  group('intake requirements', () {
    test('missingRequirement walks mileage → photos → signature → checklist', () async {
      final c = OrderIntakeController(FakeOrderRepository())
        ..applySettings(OrderSettings.fromJson(_settingsJson));
      addTearDown(c.dispose);
      expect(c.missingRequirement, contains('гүйлт'));
      c.mileageCtrl.text = '1000';
      expect(c.missingRequirement, contains('хамгийн багадаа 2'));
      await c.addPhotos([
        (filename: 'a.jpg', bytes: Uint8List(1)),
        (filename: 'b.jpg', bytes: Uint8List(1)),
      ]);
      expect(c.missingRequirement, contains('гарын үсг'));
      await c.saveSignature(Uint8List(2));
      expect(c.missingRequirement, contains('2 мөр'));
      c.setChecklistStatus('c1', ChecklistStatus.OK);
      c.setChecklistStatus('c2', ChecklistStatus.ISSUE);
      c.checklistNoteCtrl('c2').text = ' хагарсан ';
      expect(c.missingRequirement, isNull);
      final draft = c.draft!;
      expect(draft.checklistJson(), [
        {'id': 'c1', 'status': 'OK'},
        {'id': 'c2', 'status': 'ISSUE', 'note': 'хагарсан'},
      ]);
    });

    test('tapping the same status again clears it', () {
      final c = OrderIntakeController(FakeOrderRepository())
        ..applySettings(OrderSettings.fromJson(_settingsJson));
      addTearDown(c.dispose);
      c.setChecklistStatus('c1', ChecklistStatus.NA);
      expect(c.checklistAnswered, 1);
      c.setChecklistStatus('c1', ChecklistStatus.NA);
      expect(c.checklistAnswered, 0);
    });

    test('createOrder sends intakeChecklist next to intake', () async {
      final source = _Source();
      await RemoteOrdersRepository(dataSource: source).createOrder(
        branchId: 'b1',
        customerId: 'c1',
        vehicleId: 'v1',
        intake: const OrderIntakeDraft(
          checklist: [
            IntakeChecklistAnswer(id: 'c1', status: ChecklistStatus.NA),
          ],
        ),
      );
      expect(source.createBody!.containsKey('intake'), isFalse);
      expect(source.createBody!['intakeChecklist'], [
        {'id': 'c1', 'status': 'NA'},
      ]);
    });

    testWidgets('section opens by itself and shows the checklist', (
      tester,
    ) async {
      final c = OrderIntakeController(FakeOrderRepository())
        ..applySettings(OrderSettings.fromJson(_settingsJson));
      addTearDown(c.dispose);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: IntakeSection(controller: c)),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('intake_checklist')), findsOneWidget);
      expect(find.text('Хүлээн авах *'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('intake_check_c2_ISSUE')));
      await tester.pump();
      expect(find.byKey(const ValueKey('intake_check_note_c2')), findsOneWidget);
    });
  });

  group('close rules', () {
    ServiceOrderSummary order({
      bool postpaid = false,
      int total = 1000,
      int completed = 0,
    }) => OrderSummaryDto.fromJson({
      ..._orderJson,
      'totalAmount': '$total.00',
      'isPostpaid': postpaid,
      'progress': {'total': 2, 'completed': completed},
    }).value;

    test('defaults block unfinished work and a balance', () {
      final blocker = order().completionBlocker();
      expect(blocker, contains('ажил дуусаагүй'));
      expect(blocker, contains('төлөгдөөгүй'));
    });

    test('relaxed settings: no item rule, unpaid closable with permission', () {
      expect(
        order().completionBlocker(
          canCloseUnpaidPostpaid: true,
          requireItemsCompleted: false,
          allowCloseUnpaid: true,
        ),
        isNull,
      );
      expect(
        order().completionBlocker(
          requireItemsCompleted: false,
          allowCloseUnpaid: true,
        ),
        contains('эрхтэй хэрэглэгч'),
      );
    });
  });
}

class _Source extends Fake implements OrdersDataSource {
  Map<String, dynamic>? createBody;

  @override
  Future<Object?> create(Map<String, dynamic> body) async {
    createBody = body;
    return {'order': _orderJson};
  }
}

const _orderJson = <String, dynamic>{
  'id': 'o1',
  'number': 'D1-1',
  'status': 'IN_PROGRESS',
  'paymentStatus': 'UNPAID',
  'totalAmount': '1000.00',
  'paidAmount': '0.00',
  'createdAt': '2026-09-18T03:00:00.000Z',
  'customer': {'id': 'c1', 'fullName': 'Бат', 'phone': '99001122'},
  'vehicle': {'id': 'v1', 'plate': '1234ABC', 'make': 'T', 'model': 'P'},
  'branch': {'id': 'b1', 'name': 'Толгойт'},
};
