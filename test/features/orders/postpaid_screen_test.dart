import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/network/working_branch_interceptor.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/controllers/postpaid_controller.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/screens/postpaid_screen.dart';
import 'package:carservice_business/features/orders/presentation/widgets/postpaid/postpaid_widgets.dart';
import 'package:carservice_business/features/shell/domain/working_branch.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../fakes/fake_order_repository.dart';

class _MemoryBranchStore implements WorkingBranchSelectionStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? selection) async => value = selection;

  @override
  Future<void> clear() async => value = null;
}

class _BranchRepository implements WorkingBranchRepository {
  @override
  Future<WorkingBranchOptions> fetchOptions() async =>
      const WorkingBranchOptions(
        branches: [
          SwitchableBranch(id: 'branch-1', name: 'Нэгдүгээр салбар'),
          SwitchableBranch(id: 'branch-2', name: 'Хоёрдугаар салбар'),
        ],
        allowAll: false,
        lockedBranchId: null,
      );
}

class _RecordingPostpaidRepository extends FakeOrderRepository {
  _RecordingPostpaidRepository() : super(seedPostpaid: true);

  final queries = <PostpaidQuery>[];

  @override
  Future<Result<PostpaidPage>> getPostpaid({PostpaidQuery? query}) {
    queries.add(query ?? const PostpaidQuery());
    return super.getPostpaid(query: query);
  }
}

User _viewer() => User(
  accessToken: 'access',
  refreshToken: 'refresh',
  id: 'user',
  email: 'staff@example.test',
  firstName: 'Staff',
  lastName: 'User',
  phone: '99000000',
  isOwner: false,
  role: UserRole('role', 'Staff', const ['orders.viewOwn']),
  tenant: UserTenant('tenant', 'Tenant'),
);

Future<void> _pumpPostpaid(
  WidgetTester tester, {
  required ThemeData theme,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = PostpaidController(
    repo: FakeOrderRepository(seedPostpaid: true),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: PostpaidScreen(controller: controller, user: _viewer()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders server summary and postpaid history on a phone', (
    tester,
  ) async {
    await _pumpPostpaid(
      tester,
      theme: AppTheme.light,
      size: const Size(375, 800),
    );

    expect(find.text('Нийт үлдэгдэл'), findsOneWidget);
    expect(find.text('Тээврийн хэрэгслээр'), findsOneWidget);
    expect(find.text('Засварын хуудасны түүх'), findsOneWidget);
    expect(find.text('#A-0001'), findsOneWidget);
  });

  testWidgets('renders the same postpaid content in dark tablet theme', (
    tester,
  ) async {
    await _pumpPostpaid(
      tester,
      theme: AppTheme.dark,
      size: const Size(1024, 800),
    );

    expect(find.text('Серверийн нэгтгэсэн үлдэгдэл'), findsOneWidget);
    expect(
      find.text('Сонгосон төлбөр, огноо, тээврийн хэрэгслийн шүүлтүүр'),
      findsOneWidget,
    );
    expect(find.text('Дараагийн хуудас'), findsNothing);
  });

  testWidgets('reloads when the ambient working branch changes', (
    tester,
  ) async {
    final repository = _RecordingPostpaidRepository();
    final controller = PostpaidController(repo: repository);
    final branchController = WorkingBranchController(
      repository: _BranchRepository(),
      store: _MemoryBranchStore(),
      invalidationBus: WorkingBranchInvalidationBus(),
    );
    await branchController.load();
    await branchController.selectBranch('branch-1');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChangeNotifierProvider<WorkingBranchController>.value(
          value: branchController,
          child: PostpaidScreen(controller: controller, user: _viewer()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final initialRequestCount = repository.queries.length;

    await branchController.selectBranch('branch-2');
    await tester.pump();
    await tester.pump();

    expect(repository.queries.length, greaterThan(initialRequestCount));
    expect(controller.selectedBranchId, 'branch-2');
    controller.dispose();
    branchController.dispose();
  });

  test('formats postpaid money without floating-point rounding', () {
    expect(
      formatPostpaidMoney(Money('9007199254740993')),
      '9,007,199,254,740,993₮',
    );
    expect(
      formatPostpaidMoney(Money('1234567890.1200300')),
      '1,234,567,890.1200300₮',
    );
  });

  testWidgets('renders at compact-tablet width', (tester) async {
    await _pumpPostpaid(
      tester,
      theme: AppTheme.light,
      size: const Size(700, 800),
    );
    expect(find.text('Тээврийн хэрэгслээр'), findsOneWidget);
    expect(find.text('Засварын хуудасны түүх'), findsOneWidget);
  });
}
