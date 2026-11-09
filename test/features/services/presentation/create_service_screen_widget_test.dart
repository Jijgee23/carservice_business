import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/services/domain/service.dart';
import 'package:carservice_business/features/services/domain/services_repository.dart';
import 'package:carservice_business/features/services/presentation/screens/create_service_screen.dart';

import '../../../fakes/fake_api_backend.dart';
import '../data/fake_service_repository.dart';

/// Widget coverage for the rebuilt `CreateServiceScreen` — P4-F3.
///
/// Covers: the surface-level permission gate for both modes, the kind
/// selector becoming a read-only chip once editing (`type` is immutable —
/// see `CreateServiceController`'s doc comment), the `GOODS` edit-mode
/// locked-stock notice, and 422 field-error binding.
User _user(List<String> permissions) => User(
  accessToken: 'token',
  refreshToken: 'refresh',
  id: 'user',
  email: 'user@example.test',
  firstName: 'Test',
  lastName: 'User',
  phone: '99001122',
  isOwner: false,
  role: UserRole('role', 'Role', permissions),
  tenant: UserTenant('tenant', 'Tenant'),
);

void main() {
  setUp(() => FakeApiBackend.instance.reset());

  testWidgets('create mode is denied without services.create', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CreateServiceScreen(
          repo: FakeServiceRepository(),
          user: _user(const []),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Энэ үйлдэлд эрх байхгүй байна'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('edit mode is denied without services.edit', (tester) async {
    final existing = FakeServiceRepository.seedService(id: 'svc-1');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CreateServiceScreen(
          existing: existing,
          repo: FakeServiceRepository(seed: [existing]),
          user: _user(const ['services.view']),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Энэ үйлдэлд эрх байхгүй байна'), findsOneWidget);
  });

  testWidgets('edit mode prefills fields and locks the kind + stock', (
    tester,
  ) async {
    final existing = FakeServiceRepository.seedService(
      id: 'svc-1',
      type: ServiceKind.goods,
      name: 'Тормозны наклад',
      code: 'BRK-001',
      price: '45000.00',
      stock: '12.5',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CreateServiceScreen(
          existing: existing,
          repo: FakeServiceRepository(seed: [existing]),
          user: _user(const ['services.edit']),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Тормозны наклад'), findsOneWidget);
    expect(find.text('BRK-001'), findsOneWidget);
    expect(find.text('45,000'), findsOneWidget);
    // Stock is never an editable field in edit mode — see
    // `CreateServiceController.lockedStock`'s doc comment.
    expect(find.textContaining('Одоогийн үлдэгдэл: 12.5'), findsOneWidget);
    expect(find.text('Үүсгэсний дараа өөрчлөгдөхгүй'), findsOneWidget);
    // The submit button must read "Хадгалах" (save), not "Бүртгэх" (create).
    expect(find.text('Хадгалах'), findsOneWidget);
  });

  testWidgets('create mode renders the kind selector and an empty form', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CreateServiceScreen(
          repo: FakeServiceRepository(),
          user: _user(const ['services.create']),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Үйлчилгээ бүртгэх'), findsOneWidget);
    expect(find.text('Бүртгэх'), findsOneWidget);
    for (final kind in [
      ServiceKind.labor,
      ServiceKind.goods,
      ServiceKind.diagnostic,
    ]) {
      expect(find.text(kind.label), findsOneWidget);
    }
  });

  testWidgets('a 422 from updateService binds inline, not a toast', (
    tester,
  ) async {
    final existing = FakeServiceRepository.seedService(id: 'svc-1');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CreateServiceScreen(
          existing: existing,
          repo: _RejectingRepository(existing),
          user: _user(const ['services.edit']),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.ensureVisible(
      find.byKey(const ValueKey('service_form_submit')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('service_form_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Нэр оруулна уу.'), findsOneWidget);
  });

  testWidgets('price fields group thousands but submit plain numbers', (
    tester,
  ) async {
    final existing = FakeServiceRepository.seedService(id: 'svc-1');
    final repo = _RejectingRepository(existing);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CreateServiceScreen(
          existing: existing,
          repo: repo,
          user: _user(const ['services.edit']),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Prefilled from '30000.00'.
    expect(find.text('30,000'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Зарах үнэ ₮'),
      '1250000.5',
    );
    await tester.pump();
    expect(find.text('1,250,000.5'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('service_form_submit')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('service_form_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repo.sentPrice, '1250000.5');
    expect(repo.sentCostPrice, '30000');
  });
}

/// Always rejects `updateService` with a 422 on `name`, so the screen's
/// field-error binding can be exercised without depending on the real
/// validation rules in `FakeServiceRepository`.
class _RejectingRepository implements ServicesRepository {
  _RejectingRepository(this._existing);
  final Service _existing;

  /// What the last `updateService` call was given.
  String? sentPrice, sentCostPrice;

  @override
  Future<Result<Service>> updateService(
    String serviceId, {
    required ServiceKind type,
    required String name,
    String? code,
    String? unitId,
    required String price,
    String? costPrice,
    String? stock,
    String? durationValue,
    String? durationUnitId,
    int? reminderIntervalMonths,
    String? description,
    bool isActive = true,
    required String categoryId,
  }) async {
    sentPrice = price;
    sentCostPrice = costPrice;
    return const Err(
      AppError(
        ErrorKind.unknown,
        'Хүсэлт буруу.',
        statusCode: 422,
        code: 'VALIDATION_FAILED',
        fieldErrors: {'name': 'Нэр оруулна уу.'},
      ),
    );
  }

  @override
  Future<Result<List<Unit>>> getUnits() async =>
      Ok([FakeServiceRepository.seedUnit()]);

  @override
  Future<Result<List<Category>>> getCategories() async =>
      Ok([FakeServiceRepository.seedCategory()]);

  @override
  Future<Result<Service>> getService(String serviceId) async => Ok(_existing);

  @override
  Future<Result<PagedResult<Service>>> getServices({ServiceListQuery? query}) =>
      throw UnimplementedError();

  @override
  Future<Result<ServiceDeleteResult>> deleteService(String serviceId) =>
      throw UnimplementedError();

  @override
  Future<Result<ServiceStockResult>> adjustStock(
    String serviceId, {
    required StockDirection direction,
    required String amount,
  }) => throw UnimplementedError();

  @override
  Future<Result<BulkCategoryResult>> bulkChangeCategory({
    required List<String> serviceIds,
    required String categoryId,
  }) => throw UnimplementedError();
}
