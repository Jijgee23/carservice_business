import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:dio/dio.dart' as dio show Response;
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/cash/data/cash_session_dto.dart';
import 'package:carservice_business/features/cash/domain/cash_session.dart';
import 'package:carservice_business/features/cash/presentation/controllers/settlement_flow_controller.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_payment_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_payment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../fakes/fake_order_repository.dart';
import 'fake_cash_repository.dart';

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

final _warning = find.byKey(const ValueKey('no_cash_session_warning'));

void main() {
  group('difference math', () {
    test('blocks every method only for a known-closed branch', () {
      expect(cashSessionBlocked(false), isTrue);
      expect(cashSessionBlocked(true), isFalse);
      expect(cashSessionBlocked(null), isFalse);
    });

    test('server CASH_SESSION_CLOSED 409 maps to the Mongolian message', () {
      final error = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: dio.Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 409,
            data: {'error': 'other text', 'code': 'CASH_SESSION_CLOSED'},
          ),
        ),
      );
      expect(error.code, CashSessionClosedError.code);
      expect(error.isCashSessionClosed, isTrue);
      expect(error.display, 'Касс нээгээгүй байна. Эхлээд кассаа нээнэ үү.');
    });

    test('server CASH_SESSION_ENTRY_LOCKED 409 maps to the locked message', () {
      final error = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: dio.Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 409,
            data: {'error': 'other', 'code': 'CASH_SESSION_ENTRY_LOCKED'},
          ),
        ),
      );
      expect(error.code, CashSessionEntryLockedError.code);
      expect(error.statusCode, 409);
      expect(error.display, 'Хаагдсан ээлжийн гүйлгээг буцаах боломжгүй.');
    });
  });

  test('PAID_PAYMENT_LOCKED 422 keeps the server message and code', () {
    final error = mapDioException(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: dio.Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
          data: {
            'error': 'Төлбөр нь хаагдсан ээлжид бүртгэгдсэн тул захиалгыг цуцлах боломжгүй.',
            'code': 'PAID_PAYMENT_LOCKED',
          },
        ),
      ),
    );
    expect(error.code, 'PAID_PAYMENT_LOCKED');
    expect(error.statusCode, 422);
    expect(error.message, contains('хаагдсан ээлжид'));
  });

  group('dto', () {
    test('open flag parses', () {
      expect(parseSessionOpenFlag({'branchId': 'b', 'open': true}), isTrue);
      expect(parseSessionOpenFlag({'branchId': 'b', 'open': false}), isFalse);
    });
  });

  group('warning on forms', () {
    test('a failed flag read never warns', () async {
      final repo = FakeCashRepository()..openFlagFails = true;
      final c = SettlementFlowController(
        repo: repo,
        accounts: const [],
        branchId: 'b-1',
      );
      await c.loadSessionFlag();
      expect(c.sessionOpen, isNull);
      expect(c.showNoSessionWarning, isFalse);
    });

    test('settlement flow: blocks any method while no open session', () async {
      final repo = FakeCashRepository()..openFlag = false;
      final c = SettlementFlowController(
        repo: repo,
        accounts: const [],
        branchId: 'b-1',
      );
      await c.loadSessionFlag();
      expect(c.showNoSessionWarning, isTrue);
      c.setMethod(OrderPaymentMethod.OTHER);
      expect(c.showNoSessionWarning, isTrue);
      expect(c.canSubmit, isFalse);
    });

    test('order payment: lookup used with payments.create alone', () async {
      final calls = <String>[];
      OrderPaymentController make(User u, bool open) => OrderPaymentController(
        repo: FakeOrderRepository(),
        orderId: 'order-1',
        user: u,
        sessionOpenLookup: (b) async {
          calls.add(b);
          return Ok(open);
        },
      );
      final c = make(user(const ['payments.view', 'payments.create']), false);
      await c.load();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['branch-1']);
      expect(c.showNoSessionWarning(OrderPaymentMethod.CASH), isTrue);
      expect(c.showNoSessionWarning(OrderPaymentMethod.CARD), isTrue);
      expect(c.cashSessionClosed, isTrue);
      expect(
        await c.createManual(amount: '1000', method: OrderPaymentMethod.CASH),
        isFalse,
      );
      expect(c.lastError?.code, CashSessionClosedError.code);

      final open = make(user(const ['payments.view', 'payments.create']), true);
      await open.load();
      await Future<void>.delayed(Duration.zero);
      expect(open.showNoSessionWarning(OrderPaymentMethod.CASH), isFalse);

      calls.clear();
      final viewOnly = make(user(const ['payments.view']), false);
      await viewOnly.load();
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty, reason: 'endpoint needs create or cash.manage');
      expect(viewOnly.sessionOpen, isNull);
    });
  });

  group('screens', () {
    testWidgets('order payment form blocks CASH and OTHER alike', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ChangeNotifierProvider(
            create: (_) => OrderPaymentController(
              repo: FakeOrderRepository(),
              orderId: 'order-1',
              user: user(const ['payments.view', 'payments.create']),
              sessionOpenLookup: (_) async => const Ok(false),
            ),
            child: const OrderPaymentScreen(orderId: 'order-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_warning, findsNothing);
      await tester.tap(find.byKey(const ValueKey('open_payment_sheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pay_opt_CASH')));
      await tester.pumpAndSettle();
      expect(_warning, findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('create_manual_payment')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('pay_sheet_back')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pay_opt_OTHER')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pay_opt_OTHER')));
      await tester.pumpAndSettle();
      expect(_warning, findsOneWidget);
    });
  });
}
