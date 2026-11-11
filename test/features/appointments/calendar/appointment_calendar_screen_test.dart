import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/calendar_controller.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_calendar_screen.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/calendar/calendar_agenda_list.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/calendar/calendar_day_grid.dart';

import '../../../fakes/fake_appointment_repository.dart';
import 'calendar_test_fixtures.dart';

Future<void> _pumpScreen(
  WidgetTester tester,
  CalendarController controller, {
  ThemeData? theme,
  Size size = const Size(375, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: AppointmentCalendarScreen(controller: controller),
    ),
  );
  // Bounded pumps rather than `pumpAndSettle`: the loading state briefly
  // shows an indeterminate `CircularProgressIndicator`, whose animation
  // controller `pumpAndSettle` can race with the fake repository's
  // microtask resolution and, across many loop iterations in the same
  // test, occasionally still be mid-frame when settle gives up.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('AppointmentCalendarScreen', () {
    testWidgets('phone width (375dp) renders the day grid', (tester) async {
      final repo = FakeAppointmentRepository();
      final controller = CalendarController(
        repo: repo,
        branchId: 'branch-1',
        date: day(9),
      );
      await _pumpScreen(tester, controller, size: const Size(375, 800));
      expect(find.byType(CalendarDayGrid), findsOneWidget);
      expect(find.byType(CalendarAgendaList), findsNothing);
    });

    testWidgets('compact tablet width (700dp) renders the day grid', (
      tester,
    ) async {
      final repo = FakeAppointmentRepository();
      final controller = CalendarController(
        repo: repo,
        branchId: 'branch-1',
        date: day(9),
      );
      await _pumpScreen(tester, controller, size: const Size(700, 900));
      expect(find.byType(CalendarDayGrid), findsOneWidget);
      expect(find.byType(CalendarAgendaList), findsNothing);
    });

    testWidgets('tablet width (1024dp) renders the day grid', (tester) async {
      final repo = FakeAppointmentRepository();
      final controller = CalendarController(
        repo: repo,
        branchId: 'branch-1',
        date: day(9),
      );
      await _pumpScreen(tester, controller, size: const Size(1024, 900));
      expect(find.byType(CalendarDayGrid), findsOneWidget);
    });

    testWidgets(
      'no-branch-selected renders a prompt, not an error/retry view',
      (tester) async {
        final repo = FakeAppointmentRepository();
        final controller = CalendarController(
          repo: repo,
          branchId: null,
          date: day(9),
        );
        await _pumpScreen(tester, controller);
        expect(find.textContaining('салбар сонго'), findsOneWidget);
        expect(find.text('Дахин оролдох'), findsNothing);
      },
    );

    testWidgets('a server failure renders an error view with retry', (
      tester,
    ) async {
      final repo = _FailingRepository();
      final controller = CalendarController(
        repo: repo,
        branchId: 'branch-1',
        date: day(9),
      );
      await _pumpScreen(tester, controller);
      expect(find.text('Дахин оролдох'), findsOneWidget);
    });

    testWidgets('an empty day still renders (empty-day note), not an error', (
      tester,
    ) async {
      final repo = _EmptyDayRepository();
      final controller = CalendarController(
        repo: repo,
        branchId: 'branch-1',
        date: day(9),
      );
      await _pumpScreen(tester, controller, size: const Size(375, 800));
      expect(find.textContaining('цаг захиалга алга'), findsOneWidget);
    });

    testWidgets('switching the day triggers a reload', (tester) async {
      final repo = FakeAppointmentRepository();
      final controller = CalendarController(
        repo: repo,
        branchId: 'branch-1',
        date: day(9),
      );
      await _pumpScreen(tester, controller, size: const Size(700, 900));
      final before = controller.date;
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(controller.date.isAfter(before), isTrue);
    });

    testWidgets('renders without exception in both themes, at 375/700/1024dp', (
      tester,
    ) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final width in [375.0, 700.0, 1024.0]) {
          final repo = FakeAppointmentRepository();
          final controller = CalendarController(
            repo: repo,
            branchId: 'branch-1',
            date: day(9),
          );
          await _pumpScreen(
            tester,
            controller,
            theme: theme,
            size: Size(width, 900),
          );
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}

class _FailingRepository extends FakeAppointmentRepository {
  @override
  Future<Result<CalendarDayModel>> getCalendarDay({
    String? branchId,
    required DateTime date,
  }) async => const Err(
    AppError(ErrorKind.server, 'Сервер алдаа гарлаа', statusCode: 500),
  );
}

class _EmptyDayRepository extends FakeAppointmentRepository {}
