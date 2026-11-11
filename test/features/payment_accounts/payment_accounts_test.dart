import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/payment_accounts/domain/payment_account.dart';
import 'package:carservice_business/features/payment_accounts/presentation/controllers/payment_account_list_controller.dart';
import 'package:carservice_business/features/payment_accounts/presentation/screens/payment_account_form_screen.dart';
import 'package:carservice_business/features/payment_accounts/presentation/screens/payment_account_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

User user(List<String> permissions, {bool isOwner = false}) => User(
  accessToken: 't',
  refreshToken: 'r',
  id: 'u',
  email: 'u@example.test',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: isOwner,
  branchId: 'b-1',
  role: UserRole('role', 'Role', permissions),
  tenant: UserTenant('tenant', 'Tenant'),
);

final manager = user(const ['cash.manage']);

const cash = PaymentAccount(
  id: 'acc-cash',
  type: PaymentAccountType.cash,
  name: 'Бэлэн',
);
const khan = PaymentAccount(
  id: 'acc-khan',
  type: PaymentAccountType.bankAccount,
  name: 'Хаан банк',
  accountNumber: '5012345678',
);
const pos = PaymentAccount(
  id: 'acc-pos',
  type: PaymentAccountType.pos,
  name: 'Голомт POS',
  accountNumber: '1100223344',
  terminalId: 'T001',
  isTest: true,
  isActive: false,
);

class FakePaymentAccountsRepository implements PaymentAccountsRepository {
  FakePaymentAccountsRepository([List<PaymentAccount>? seed])
    : accounts = [...seed ?? const [cash, khan, pos]];

  List<PaymentAccount> accounts;
  final created = <PaymentAccountDraft>[];
  final updated = <(String, PaymentAccountDraft)>[];
  final activeCalls = <(String, bool)>[];
  final deleted = <String>[];
  AppError? createError;
  AppError? deleteError;

  @override
  Future<Result<List<PaymentAccount>>> list({
    bool includeInactive = true,
  }) async => Ok(List.of(accounts));

  @override
  Future<Result<PaymentAccount>> create(PaymentAccountDraft draft) async {
    created.add(draft);
    if (createError != null) return Err(createError!);
    final a = PaymentAccount(
      id: 'acc-${accounts.length + 1}',
      type: draft.type,
      name: draft.name.trim(),
      accountNumber: draft.accountNumber,
    );
    accounts.add(a);
    return Ok(a);
  }

  @override
  Future<Result<PaymentAccount>> update(
    String id,
    PaymentAccountDraft draft,
  ) async {
    updated.add((id, draft));
    final old = accounts.firstWhere((a) => a.id == id);
    final a = PaymentAccount(
      id: id,
      type: old.type,
      name: draft.name.trim(),
      accountNumber: draft.accountNumber,
      isActive: old.isActive,
    );
    return Ok(a);
  }

  @override
  Future<Result<PaymentAccount>> setActive(String id, bool isActive) async {
    activeCalls.add((id, isActive));
    final old = accounts.firstWhere((a) => a.id == id);
    return Ok(
      PaymentAccount(
        id: id,
        type: old.type,
        name: old.name,
        accountNumber: old.accountNumber,
        terminalId: old.terminalId,
        isTest: old.isTest,
        isActive: isActive,
      ),
    );
  }

  @override
  Future<Result<void>> delete(String id) async {
    deleted.add(id);
    if (deleteError != null) return Err(deleteError!);
    accounts.removeWhere((a) => a.id == id);
    return const Ok(null);
  }
}

Future<void> pump(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(GetMaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

void main() {
  group('domain', () {
    test('parses the DTO and builds the hint like the web', () {
      final a = PaymentAccount.fromJson({
        'id': 'p1',
        'type': 'POS',
        'method': 'CARD',
        'name': 'Хаан POS',
        'accountNumber': '5012345678',
        'accountNumberMasked': '••••5678',
        'terminalId': 'TID9',
        'merchantId': null,
        'isTest': true,
        'isActive': true,
      });
      expect(a.isPos, isTrue);
      expect(a.hint, 'TID TID9');
      expect(khan.hint, '5012345678');
      expect(cash.hint, isNull);
    });

    test('draft JSON: POS-only fields only for POS, CASH name only', () {
      const bank = PaymentAccountDraft(
        type: PaymentAccountType.bankAccount,
        name: ' Хаан ',
        accountNumber: '5012345678',
        terminalId: 'x',
      );
      expect(bank.toCreateJson(), {
        'type': 'BANK_ACCOUNT',
        'name': 'Хаан',
        'accountNumber': '5012345678',
      });
      const posDraft = PaymentAccountDraft(
        type: PaymentAccountType.pos,
        name: 'POS',
        accountNumber: '123456',
        terminalId: ' ',
        isTest: true,
      );
      expect(posDraft.toUpdateJson(), {
        'name': 'POS',
        'accountNumber': '123456',
        'terminalId': null,
        'merchantId': null,
        'isTest': true,
      });
      const cashDraft = PaymentAccountDraft(
        type: PaymentAccountType.cash,
        name: 'Касс',
      );
      expect(cashDraft.toUpdateJson(), {'name': 'Касс'});
    });
  });

  group('PaymentAccountListController', () {
    test('toggle active replaces the row; delete error is returned', () async {
      final repo = FakePaymentAccountsRepository();
      final c = PaymentAccountListController(repo: repo);
      await c.load();
      expect(c.accounts, hasLength(3));

      expect(await c.setActive(pos, true), isNull);
      expect(c.accounts.firstWhere((a) => a.id == 'acc-pos').isActive, isTrue);

      repo.deleteError = const AppError(
        ErrorKind.unknown,
        '3 гүйлгээнд ашиглагдсан — идэвхгүй болгоно уу.',
        statusCode: 409,
        code: 'PAYMENT_ACCOUNT_IN_USE',
      );
      final error = await c.delete(khan);
      expect(error?.code, 'PAYMENT_ACCOUNT_IN_USE');
      expect(c.accounts, hasLength(3));

      repo.deleteError = null;
      expect(await c.delete(khan), isNull);
      expect(c.accounts.map((a) => a.id), isNot(contains('acc-khan')));
    });
  });

  group('PaymentAccountListScreen', () {
    testWidgets('without cash.manage shows the lock state', (tester) async {
      await pump(
        tester,
        PaymentAccountListScreen(
          repository: FakePaymentAccountsRepository(),
          user: user(const ['payments.create']),
        ),
      );
      expect(
        find.text('Танд кассыг удирдах эрх байхгүй байна.'),
        findsOneWidget,
      );
    });

    testWidgets('groups by type with badges; CASH has no delete', (
      tester,
    ) async {
      await pump(
        tester,
        PaymentAccountListScreen(
          repository: FakePaymentAccountsRepository(),
          user: manager,
        ),
      );
      expect(find.text('ДАНС'), findsOneWidget);
      expect(find.text('Хаан банк'), findsOneWidget);
      expect(find.text('5012345678'), findsOneWidget);
      expect(find.text('TID T001'), findsOneWidget);
      expect(find.text('Туршилт'), findsOneWidget);
      expect(find.text('Идэвхгүй'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('payment_account_menu_acc-cash')));
      await tester.pumpAndSettle();
      expect(find.text('Засах'), findsOneWidget);
      expect(find.text('Устгах'), findsNothing);
      expect(find.text('Идэвхгүй болгох'), findsNothing);
    });

    testWidgets('deactivate from the row menu', (tester) async {
      final repo = FakePaymentAccountsRepository();
      await pump(
        tester,
        PaymentAccountListScreen(repository: repo, user: manager),
      );
      await tester.tap(find.byKey(const ValueKey('payment_account_menu_acc-khan')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Идэвхгүй болгох'));
      await tester.pumpAndSettle();
      expect(repo.activeCalls.single, ('acc-khan', false));
      expect(find.text('Идэвхгүй'), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('delete asks for confirmation first', (tester) async {
      final repo = FakePaymentAccountsRepository();
      await pump(
        tester,
        PaymentAccountListScreen(repository: repo, user: manager),
      );
      await tester.tap(find.byKey(const ValueKey('payment_account_menu_acc-khan')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Устгах'));
      await tester.pumpAndSettle();
      expect(find.text('«Хаан банк»-г устгах уу?'), findsOneWidget);
      expect(repo.deleted, isEmpty);

      await tester.tap(find.text('Устгах').last);
      await tester.pumpAndSettle();
      expect(repo.deleted, ['acc-khan']);
      expect(find.text('Хаан банк'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('PaymentAccountFormScreen', () {
    testWidgets('validates locally, then creates a bank account', (
      tester,
    ) async {
      final repo = FakePaymentAccountsRepository();
      await pump(tester, PaymentAccountFormScreen(repository: repo));

      await tester.tap(find.byKey(const ValueKey('payment_account_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Нэр 2–80 тэмдэгт байна.'), findsOneWidget);
      expect(find.text('Дансны дугаар 6–20 орон байна.'), findsOneWidget);
      expect(repo.created, isEmpty);

      await tester.tap(find.text('Хаан банк'));
      await tester.enterText(
        find.byKey(const ValueKey('payment_account_number')),
        '5012345678',
      );
      await tester.tap(find.byKey(const ValueKey('payment_account_submit')));
      await tester.pumpAndSettle();
      expect(repo.created.single.type, PaymentAccountType.bankAccount);
      expect(repo.created.single.name, 'Хаан банк');
      expect(repo.created.single.accountNumber, '5012345678');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('POS shows terminal fields; server error is shown', (
      tester,
    ) async {
      final repo = FakePaymentAccountsRepository()
        ..createError = const AppError(
          ErrorKind.unknown,
          'Энэ дансны дугаар аль хэдийн бүртгэгдсэн байна.',
          statusCode: 409,
          code: 'PAYMENT_ACCOUNT_DUPLICATE',
          fieldErrors: {'accountNumber': 'Давхардсан дугаар.'},
        );
      await pump(tester, PaymentAccountFormScreen(repository: repo));
      expect(find.byKey(const ValueKey('payment_account_terminal')), findsNothing);
      await tester.tap(find.text('POS'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payment_account_terminal')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('payment_account_name')),
        'Хаан POS',
      );
      await tester.enterText(
        find.byKey(const ValueKey('payment_account_number')),
        '5012345678',
      );
      await tester.tap(find.byKey(const ValueKey('payment_account_submit')));
      await tester.pumpAndSettle();
      expect(repo.created.single.type, PaymentAccountType.pos);
      expect(find.text('Давхардсан дугаар.'), findsOneWidget);
    });

    testWidgets('editing CASH offers the name only', (tester) async {
      final repo = FakePaymentAccountsRepository();
      await pump(
        tester,
        PaymentAccountFormScreen(account: cash, repository: repo),
      );
      expect(find.byKey(const ValueKey('payment_account_type')), findsNothing);
      expect(find.byKey(const ValueKey('payment_account_number')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('payment_account_name')),
        'Касс',
      );
      await tester.tap(find.byKey(const ValueKey('payment_account_submit')));
      await tester.pumpAndSettle();
      expect(repo.updated.single.$1, 'acc-cash');
      expect(repo.updated.single.$2.toUpdateJson(), {'name': 'Касс'});
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
