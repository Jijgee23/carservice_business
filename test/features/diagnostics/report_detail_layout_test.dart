import 'dart:async';

import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/diagnostics/domain/diagnostic.dart';
import 'package:carservice_business/features/diagnostics/domain/diagnostics_repository.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/report_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/hive_test_setup.dart';

/// Real-world worst case: long template/branch names, a long free-text
/// answer, long positioned answers and notes — the content that overflowed.
DiagnosticReportDetail _report() => DiagnosticReportDetail(
  id: 'r1',
  createdAt: DateTime(2026, 9, 28, 10, 30),
  templateVersion: 1,
  mileageAtReport: 184500,
  notes: 'Урд тэнхлэгийн холхивч чимээ гаргаж байна. Дараагийн үзлэгээр дахин шалгах.',
  data: {
    'text-1': const ReportEntry(
      value: 'Хөдөлгүүрийн тосны түвшин доод хэмжээнээс бага, солих хугацаа хэтэрсэн байна',
    ),
    'check-1': const ReportEntry(value: 'Засах', note: 'Наалт сэтэрсэн'),
    'pos-1:L': const ReportEntry(value: 'Хээ 2мм-ээс бага, солих шаардлагатай'),
    'pos-1:R': const ReportEntry(value: 'OK'),
  },
  template: const DiagnosticTemplateDetail(
    id: 't1',
    name: 'Бүрэн техникийн үзлэг — суудлын автомашин (өргөтгөсөн)',
    type: DiagnosticType.ROUTINE,
    version: 1,
    isActive: true,
    isSystemDefault: false,
    schema: TemplateSchema(
      sections: [
        TemplateSection(
          id: 's1',
          title: 'Хөдөлгүүр болон тосолгооны систем',
          items: [
            TemplateItem(
              id: 'text-1',
              label: 'Тосны байдал',
              type: ItemType.text,
              required: false,
            ),
            TemplateItem(
              id: 'check-1',
              label: 'Хөргөлтийн шингэний хоолойн бүрэн бүтэн байдал',
              type: ItemType.check,
              required: false,
            ),
            TemplateItem(
              id: 'pos-1',
              label: 'Дугуйн хээ',
              type: ItemType.text,
              required: false,
              positionSet: PositionSetKey.LR,
            ),
          ],
        ),
      ],
    ),
  ),
  customer: const CustomerSummary(
    id: 'c1',
    fullName: 'Батбаяр Болдбаатарын Энхтүвшин',
    phone: '99112233',
  ),
  vehicle: const VehicleSummary(
    id: 'v1',
    plate: '1234 УБА',
    make: 'Toyota',
    model: 'Land Cruiser Prado 150',
  ),
  branch: const BranchSummary(
    id: 'b1',
    name: 'Хан-Уул дүүргийн 15-р хорооны салбар',
  ),
  filledBy: const UserSummary(
    id: 'u1',
    firstName: 'Энхбаяр',
    lastName: 'Ганбаатар',
  ),
);

class _Repo implements DiagnosticReportRepository {
  /// When set, getPdfBytes waits on it — lets a test observe the loading state.
  Completer<Result<List<int>>>? pdf;

  @override
  Future<Result<DiagnosticReportDetail>> getReport(String id) async =>
      Ok(_report());

  @override
  Future<Result<List<int>>> getPdfBytes(String id) =>
      pdf?.future ??
      Future.value(const Err(AppError(ErrorKind.server, 'fail')));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(openTestHiveBoxes);
  setUp(() {
    Authenticator.user = User(
      accessToken: 'a',
      refreshToken: 'r',
      id: 'u1',
      email: 'a@b.mn',
      firstName: 'A',
      lastName: 'B',
      phone: '99000000',
      isOwner: true,
      tenant: UserTenant('t1', 'T'),
    );
  });
  tearDown(Authenticator.clear);

  for (final size in const [Size(320, 640), Size(390, 844), Size(1024, 768)]) {
    testWidgets('no overflow at ${size.width.toInt()}dp with long content', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ReportDetailScreen(reportId: 'r1', repository: _Repo()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1234 УБА'), findsOneWidget);
      // Scroll through the whole report so every card is laid out.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no overflow at 390dp with 1.3x accessibility text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: ReportDetailScreen(reportId: 'r1', repository: _Repo()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('PDF export loading', () {
    final pdfButton = find.byKey(const ValueKey('report_pdf_button'));
    final overlay = find.byKey(const ValueKey('report_pdf_overlay'));

    Future<void> pump(WidgetTester tester, Widget screen) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();
    }

    testWidgets('blocks the whole screen until the export finishes', (
      tester,
    ) async {
      final done = Completer<void>();
      var calls = 0;
      await pump(
        tester,
        ReportDetailScreen(
          reportId: 'r1',
          repository: _Repo(),
          onPdfExport: (_) {
            calls++;
            return done.future;
          },
        ),
      );

      await tester.tap(pdfButton);
      await tester.pump();
      expect(overlay, findsOneWidget);
      expect(find.text('PDF бэлдэж байна…'), findsOneWidget);
      // Button disabled while exporting.
      expect(tester.widget<IconButton>(pdfButton).onPressed, isNull);

      // Taps underneath are swallowed: the tone filter doesn't change, and a
      // second tap on the button starts no second export.
      final goodChip = find.widgetWithText(FilterChip, 'Хэвийн (1)');
      await tester.tap(goodChip, warnIfMissed: false);
      await tester.tap(pdfButton, warnIfMissed: false);
      await tester.pump();
      expect(tester.widget<FilterChip>(goodChip).selected, isFalse);
      expect(calls, 1);

      done.complete();
      await tester.pumpAndSettle();
      expect(overlay, findsNothing);
      expect(tester.widget<IconButton>(pdfButton).onPressed, isNotNull);
    });

    testWidgets('a failed download releases the screen', (tester) async {
      final repo = _Repo()..pdf = Completer();
      await pump(tester, ReportDetailScreen(reportId: 'r1', repository: repo));

      await tester.tap(pdfButton);
      await tester.pump();
      expect(overlay, findsOneWidget);

      repo.pdf!.complete(const Err(AppError(ErrorKind.server, 'fail')));
      await tester.pumpAndSettle();
      expect(overlay, findsNothing);
      // Let the error toast's de-duplication timer run out.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  for (final locked in [true, false]) {
    testWidgets('delete button is ${locked ? 'disabled' : 'enabled'} '
        'when deleteLocked=$locked', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReportDetailScreen(
            reportId: 'r1',
            repository: _Repo(),
            deleteLocked: locked,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('report_delete_button')),
      );
      expect(button.onPressed == null, locked);
    });
  }
}
