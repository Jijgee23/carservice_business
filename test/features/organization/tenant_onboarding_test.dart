import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/features/organization/domain/organization.dart';
import 'package:carservice_business/features/organization/domain/service_keys.dart';
import 'package:carservice_business/features/organization/presentation/controllers/service_keys_controller.dart';
import 'package:carservice_business/features/organization/presentation/controllers/tenant_onboarding_controller.dart';
import 'package:carservice_business/features/organization/presentation/screens/onboarding_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'organization_settings_test.dart' show FakeOrganizationRepository, tenantJson;

Map<String, dynamic> _withOnboarding({
  bool shopName = true,
  bool serviceKeys = true,
}) => {
  ...tenantJson(),
  'onboarding': {'needsShopName': shopName, 'needsServiceKeys': serviceKeys},
};

TenantOnboardingController _controller(
  FakeOrganizationRepository repo, {
  bool owner = true,
}) => TenantOnboardingController(
  repo: repo,
  isOwner: () => owner,
  refreshUser: () async {},
);

void main() {
  group('TenantOnboarding', () {
    test('parses flags; missing block means nothing to do', () {
      final s = OrganizationSettings.fromJson(_withOnboarding(shopName: false));
      expect(s.onboarding.needsShopName, isFalse);
      expect(s.onboarding.needsServiceKeys, isTrue);
      expect(
        OrganizationSettings.fromJson(tenantJson()).onboarding.isComplete,
        isTrue,
      );
    });

    test('shop name validation mirrors the server (2–100)', () {
      expect(ShopName.validate(' a '), isNotNull);
      expect(ShopName.validate('Бат  Авто'), isNull);
      expect(ShopName.normalize('  Бат   Авто '), 'Бат Авто');
      expect(ShopName.validate('x' * 101), isNotNull);
    });

    test('service keys payload', () {
      final k = TenantServiceKeys.fromJson({
        'keys': [
          {'id': 'k1', 'name': 'Тос солих', 'description': null},
          {'id': 3},
        ],
        'selectedIds': ['k1'],
        'confirmed': false,
        'canEdit': true,
      });
      expect(k.keys.single.name, 'Тос солих');
      expect(k.selectedIds, {'k1'});
      expect(k.confirmed, isFalse);
    });
  });

  group('TenantOnboardingController', () {
    test('non-owner never loads or gates', () async {
      final repo = FakeOrganizationRepository(
        OrganizationSettings.fromJson(_withOnboarding()),
      );
      final c = _controller(repo, owner: false);
      await c.load();
      expect(c.needsShopName, isFalse);
      expect(c.needsServiceKeys, isFalse);
    });

    test('shop name first, then services', () async {
      final repo = FakeOrganizationRepository(
        OrganizationSettings.fromJson(_withOnboarding()),
      );
      final c = _controller(repo);
      await c.load();
      expect(c.needsShopName, isTrue);
      expect(c.needsServiceKeys, isFalse);

      expect(await c.saveShopName(' Бат  Авто '), isNull);
      expect(repo.patches.single, {'name': 'Бат Авто'});
      expect(c.needsShopName, isFalse);
      expect(c.needsServiceKeys, isTrue);

      c.serviceKeysSaved();
      expect(c.needsServiceKeys, isFalse);
    });

    test('a taken name comes back as the field error', () async {
      final repo =
          FakeOrganizationRepository(
              OrganizationSettings.fromJson(_withOnboarding()),
            )
            ..updateError = const AppError(
              ErrorKind.unknown,
              'Давхцал',
              statusCode: 409,
              code: 'CONFLICT',
              fieldErrors: {'name': 'Энэ нэртэй байгууллага бүртгэлтэй байна.'},
            );
      final c = _controller(repo);
      await c.load();
      expect(
        await c.saveShopName('Бат Авто'),
        'Энэ нэртэй байгууллага бүртгэлтэй байна.',
      );
      expect(c.needsShopName, isTrue);
    });
  });

  group('ServiceKeysController', () {
    test('requires at least one and saves the selection', () async {
      final repo = FakeOrganizationRepository(
        OrganizationSettings.fromJson(tenantJson()),
      );
      final c = ServiceKeysController(repo: repo);
      await c.load();
      expect(await c.save(), isFalse);
      expect(c.error, isNotNull);
      c.toggle('k2');
      expect(await c.save(), isTrue);
      expect(repo.savedServiceKeys.single, ['k2']);
      expect(c.data!.confirmed, isTrue);
    });
  });

  testWidgets('services gate saves and releases the onboarding', (
    tester,
  ) async {
    final repo = FakeOrganizationRepository(
      OrganizationSettings.fromJson(_withOnboarding(shopName: false)),
    );
    final onboarding = _controller(repo);
    await onboarding.load();
    expect(onboarding.needsServiceKeys, isTrue);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light,
        home: ServiceKeysGateScreen(onboarding: onboarding, repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Танайх ямар үйлчилгээ үзүүлдэг вэ?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('service_key_k1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('service_keys_save')));
    await tester.pumpAndSettle();
    expect(repo.savedServiceKeys.single, ['k1']);
    expect(onboarding.needsServiceKeys, isFalse);
  });
}
