import 'package:carservice_business/core/domain/working_branch_scope.dart';
import 'package:carservice_business/core/network/working_branch_interceptor.dart';
import 'package:carservice_business/features/shell/domain/working_branch.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';
import 'package:carservice_business/features/shell/presentation/screens/choose_branch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements WorkingBranchSelectionStore {
  String? value;
  _MemoryStore([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? selection) async => value = selection;
  @override
  Future<void> clear() => write(null);
}

class _Repo implements WorkingBranchRepository {
  final WorkingBranchOptions options;
  _Repo(this.options);
  @override
  Future<WorkingBranchOptions> fetchOptions() async => options;
}

const _a = SwitchableBranch(
  id: 'a',
  name: 'Салбар A',
  isPrimary: true,
  district: 'СБД',
  address: '1-р хороо',
  openTime: '09:00',
  closeTime: '18:00',
);
const _b = SwitchableBranch(id: 'b', name: 'Салбар B');

Future<WorkingBranchController> _loaded(
  WorkingBranchOptions options, [
  String? persisted,
]) async {
  final c = WorkingBranchController(
    repository: _Repo(options),
    store: _MemoryStore(persisted),
    invalidationBus: WorkingBranchInvalidationBus(),
  );
  await c.load();
  return c;
}

void main() {
  test('parses optional location and hours', () {
    final b = SwitchableBranch.fromJson({
      'id': 'x',
      'name': 'X',
      'address': ' Addr ',
      'openTime': '10:00',
      'closeTime': null,
    });
    expect(b.location, 'Addr');
    expect(b.hours, isNull);
    expect(SwitchableBranch.fromJson({'id': 'y'}).location, isNull);
  });

  group('needsChoice', () {
    test('true for 2+ branches with no saved choice', () async {
      final c = await _loaded(
        const WorkingBranchOptions(
          branches: [_a, _b],
          allowAll: false,
          lockedBranchId: null,
        ),
      );
      expect(c.needsChoice, isTrue);
    });

    test('true for an owner (allowAll) even with one branch', () async {
      final c = await _loaded(
        const WorkingBranchOptions(
          branches: [_a],
          allowAll: true,
          lockedBranchId: null,
        ),
      );
      expect(c.needsChoice, isTrue);
    });

    test('false for a single-branch staff member', () async {
      final c = await _loaded(
        const WorkingBranchOptions(
          branches: [_a],
          allowAll: false,
          lockedBranchId: null,
        ),
      );
      expect(c.needsChoice, isFalse);
    });

    test('false when the roster locks today', () async {
      final c = await _loaded(
        const WorkingBranchOptions(
          branches: [_a, _b],
          allowAll: true,
          lockedBranchId: 'b',
        ),
      );
      expect(c.needsChoice, isFalse);
    });

    test('false when a valid choice is persisted', () async {
      final c = await _loaded(
        const WorkingBranchOptions(
          branches: [_a, _b],
          allowAll: false,
          lockedBranchId: null,
        ),
        'b',
      );
      expect(c.needsChoice, isFalse);
    });

    test('true again when the persisted branch is no longer valid', () async {
      final c = await _loaded(
        const WorkingBranchOptions(
          branches: [_a, _b],
          allowAll: false,
          lockedBranchId: null,
        ),
        'gone',
      );
      expect(c.needsChoice, isTrue);
    });
  });

  testWidgets('lists branches + Бүх салбар and persists the pick', (
    tester,
  ) async {
    final store = _MemoryStore();
    final c = WorkingBranchController(
      repository: _Repo(
        const WorkingBranchOptions(
          branches: [_a, _b],
          allowAll: true,
          lockedBranchId: null,
        ),
      ),
      store: store,
      invalidationBus: WorkingBranchInvalidationBus(),
    );
    await c.load();
    await tester.pumpWidget(
      MaterialApp(home: ChooseBranchScreen(controller: c)),
    );

    expect(find.text('Салбар A'), findsOneWidget);
    expect(find.text('Салбар B'), findsOneWidget);
    expect(find.text('Бүх салбар'), findsOneWidget);
    expect(
      find.text('Үндсэн салбар\nСБД · 1-р хороо\n09:00–18:00'),
      findsOneWidget,
    );

    // Marking a card persists nothing until "Үргэлжлүүлэх".
    await tester.tap(find.byKey(const ValueKey('choose_branch_b')));
    await tester.pump();
    expect(store.value, isNull);
    await tester.tap(find.byKey(const ValueKey('choose_branch_continue')));
    await tester.pump();
    expect(store.value, 'b');
    expect(c.needsChoice, isFalse);

    // All-branches option persists the wire sentinel.
    await c.handleInvalidBranch();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('choose_branch_all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('choose_branch_continue')));
    await tester.pump();
    expect(store.value, allWorkingBranches);
  });
}
