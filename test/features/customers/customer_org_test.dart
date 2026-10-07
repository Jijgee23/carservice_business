import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/features/customers/data/customer_dto.dart';
import 'package:carservice_business/features/customers/data/customer_repository.dart';
import 'package:carservice_business/features/customers/data/customers_data_source.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_list_controller.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_org_form_controller.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_dto.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_repository.dart';
import 'package:carservice_business/features/vehicles/data/vehicles_data_source.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_customer_repository.dart';

class _CaptureCustomersSource implements CustomersDataSource {
  Map<String, dynamic>? query;
  Map<String, dynamic>? body;
  String? regno;
  Object? response;

  @override
  Future<Object?> list(Map<String, dynamic> q) async {
    query = q;
    return response;
  }

  @override
  Future<ApiEnvelope> create(Map<String, dynamic> b) async {
    body = b;
    return (statusCode: 201, data: response);
  }

  @override
  Future<Object?> update(String id, Map<String, dynamic> b) async {
    body = b;
    return response;
  }

  @override
  Future<Object?> orgLookup(String r) async {
    regno = r;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _CaptureVehiclesSource implements VehiclesDataSource {
  Map<String, dynamic>? query;

  @override
  Future<Object?> list(Map<String, dynamic> q) async {
    query = q;
    return {
      'vehicles': const [],
      'pagination': {
        'page': 1,
        'pageSize': 50,
        'total': 0,
        'totalPages': 1,
        'hasPrev': false,
        'hasNext': false,
      },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('AppValidators.orgRegnum', () {
    test('accepts exactly 7 digits', () {
      expect(AppValidators.orgRegnum('1234567'), isNull);
      expect(AppValidators.orgRegnum(' 1234567 '), isNull);
    });

    test('rejects everything else with the contract message', () {
      const msg = 'Байгууллагын регистр 7 оронтой тоо байна.';
      for (final bad in [
        null,
        '',
        '123456',
        '12345678',
        'АБ12345678', // personal regnum format
        '12345ab',
      ]) {
        expect(AppValidators.orgRegnum(bad), msg, reason: '$bad');
      }
    });

    test('optionalEmail allows blank, validates otherwise', () {
      expect(AppValidators.optionalEmail(''), isNull);
      expect(AppValidators.optionalEmail('a@b.mn'), isNull);
      expect(AppValidators.optionalEmail('nope'), isNotNull);
    });
  });

  group('Customer org parsing', () {
    test('parses org fields and shows orgName as primary', () {
      final c = Customer.fromJson({
        'id': 'c1',
        'fullName': 'Бат',
        'phone': '99001122',
        'isOrganization': true,
        'orgRegnum': '1234567',
        'orgName': 'Монгол ХХК',
        'orgEmail': 'info@mn.mn',
      });
      expect(c.isOrganization, isTrue);
      expect(c.orgRegnum, '1234567');
      expect(c.displayName, 'Монгол ХХК');
      expect(c.contactName, 'Бат');
      expect(c.orgEmail, 'info@mn.mn');
      expect(c.orgRegnumLabel, 'РД 1234567');
    });

    test('absent org fields degrade to a person', () {
      final c = Customer.fromJson({'id': 'c2', 'fullName': 'Дорж'});
      expect(c.isOrganization, isFalse);
      expect(c.orgName, isNull);
      expect(c.displayName, 'Дорж');
      expect(c.orgRegnumLabel, isNull);
    });

    test('the page DTO carries org fields', () {
      final dto = CustomerPageDto.fromJson({
        'customers': [
          {'id': 'c1', 'isOrganization': true, 'orgName': 'X ХХК'},
        ],
        'pagination': {
          'page': 1,
          'pageSize': 50,
          'total': 1,
          'totalPages': 1,
          'hasPrev': false,
          'hasNext': false,
        },
      });
      expect(dto.items.single.isOrganization, isTrue);
    });

    test('OrgLookupResult needs a name', () {
      expect(OrgLookupResult.tryParse({'regno': '1234567'}), isNull);
      expect(
        OrgLookupResult.tryParse({'regno': '1234567', 'name': 'A ХХК'})!.name,
        'A ХХК',
      );
    });
  });

  group('wire shaping', () {
    test('create/update send org fields; off nulls them', () async {
      final source = _CaptureCustomersSource()
        ..response = {
          'customer': {'id': 'c1'},
        };
      final repo = RemoteCustomersRepository(dataSource: source);

      await repo.createCustomer(
        phone: '99001122',
        isOrganization: true,
        orgRegnum: '1234567',
        orgName: 'X ХХК',
        orgEmail: null,
      );
      expect(source.body!['isOrganization'], isTrue);
      expect(source.body!['orgRegnum'], '1234567');
      expect(source.body!['orgName'], 'X ХХК');
      expect(source.body!['orgEmail'], isNull);

      await repo.updateCustomer(
        'c1',
        fullName: 'Бат',
        phone: '99001122',
        email: null,
        note: null,
        isOrganization: false,
        orgRegnum: 'stale',
        orgName: 'stale',
        orgEmail: 'stale@x.mn',
      );
      expect(source.body!['isOrganization'], isFalse);
      expect(source.body!['orgRegnum'], isNull);
      expect(source.body!['orgName'], isNull);
      expect(source.body!['orgEmail'], isNull);
    });

    test('customer list sends ?kind=', () async {
      final source = _CaptureCustomersSource()
        ..response = {
          'customers': const [],
          'pagination': {
            'page': 1,
            'pageSize': 50,
            'total': 0,
            'totalPages': 1,
            'hasPrev': false,
            'hasNext': false,
          },
        };
      final repo = RemoteCustomersRepository(dataSource: source);
      await repo.getCustomers(
        query: const CustomerListQuery(kind: CustomerKindFilter.org),
      );
      expect(source.query!['kind'], 'org');
      await repo.getCustomers(
        query: const CustomerListQuery(kind: CustomerKindFilter.person),
      );
      expect(source.query!['kind'], 'person');
      await repo.getCustomers();
      expect(source.query!.containsKey('kind'), isFalse);
    });

    test('lookupOrg hits the data source and parses {regno, name}', () async {
      final source = _CaptureCustomersSource()
        ..response = {'regno': '1234567', 'name': 'A ХХК'};
      final result = await RemoteCustomersRepository(dataSource: source)
          .lookupOrg('1234567');
      expect(source.regno, '1234567');
      expect((result as Ok<OrgLookupResult>).value.name, 'A ХХК');
    });

    test('customer list controller passes kind through', () async {
      final repo = FakeCustomerRepository(
        seed: [
          const Customer(id: 'p', fullName: 'Хүн', phone: '99001122'),
          const Customer(
            id: 'o',
            fullName: 'Холбоо',
            phone: '99001123',
            isOrganization: true,
            orgName: 'Z ХХК',
            orgRegnum: '1234567',
          ),
        ],
      );
      final ctrl = CustomerListController(repo: repo);
      addTearDown(ctrl.dispose);
      ctrl.setKind(CustomerKindFilter.org);
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.customers.map((c) => c.id), ['o']);
      ctrl.setKind(CustomerKindFilter.person);
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.customers.map((c) => c.id), ['p']);
      ctrl.setKind(null);
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.customers.length, 2);
    });
  });

  group('CustomerOrgFormController', () {
    late FakeCustomerRepository repo;
    late CustomerOrgFormController form;

    setUp(() {
      repo = FakeCustomerRepository(
        orgDirectory: {
          '1234567': const OrgLookupResult(regno: '1234567', name: 'А ХХК'),
          '7654321': const OrgLookupResult(regno: '7654321', name: 'Б ХХК'),
        },
      );
      form = CustomerOrgFormController(
        repository: repo,
        debounce: const Duration(milliseconds: 5),
      );
    });

    tearDown(() => form.dispose());

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 40));

    test('toggling off clears every org field and values go null', () {
      form.setOrganization(true);
      form.regnumCtrl.text = '12';
      form.nameCtrl.text = 'X';
      form.emailCtrl.text = 'a@b.mn';
      form.setOrganization(false);
      expect(form.regnumCtrl.text, isEmpty);
      expect(form.nameCtrl.text, isEmpty);
      expect(form.emailCtrl.text, isEmpty);
      expect(form.orgRegnum, isNull);
      expect(form.orgName, isNull);
      expect(form.orgEmail, isNull);
    });

    test('validators are inert when off, strict when on', () {
      expect(form.validateRegnum(''), isNull);
      expect(form.validateName(''), isNull);
      form.setOrganization(true);
      expect(form.validateRegnum('12'), isNotNull);
      expect(form.validateName(' '), isNotNull);
      expect(form.validateEmail(''), isNull);
      expect(form.validateEmail('bad'), isNotNull);
    });

    test('7 digits triggers a lookup and autofills an empty name', () async {
      form.setOrganization(true);
      form.regnumCtrl.text = '123456';
      await settle();
      expect(repo.lookupCalls, isEmpty);
      form.regnumCtrl.text = '1234567';
      await settle();
      expect(repo.lookupCalls, ['1234567']);
      expect(form.nameCtrl.text, 'А ХХК');
    });

    test(
      're-autofills while the name is still the previous autofill',
      () async {
        form.setOrganization(true);
        form.regnumCtrl.text = '1234567';
        await settle();
        form.regnumCtrl.text = '7654321';
        await settle();
        expect(form.nameCtrl.text, 'Б ХХК');
      },
    );

    test('never overwrites a name the user typed', () async {
      form.setOrganization(true);
      form.nameCtrl.text = 'Миний нэр';
      form.regnumCtrl.text = '1234567';
      await settle();
      expect(form.nameCtrl.text, 'Миний нэр');

      form.regnumCtrl.text = '1234567';
      form.regnumCtrl.text = '7654321';
      await settle();
      expect(form.nameCtrl.text, 'Миний нэр');
    });

    test('an edit of an autofilled name stops later autofill', () async {
      form.setOrganization(true);
      form.regnumCtrl.text = '1234567';
      await settle();
      form.nameCtrl.text = 'А ХХК (засав)';
      form.regnumCtrl.text = '7654321';
      await settle();
      expect(form.nameCtrl.text, 'А ХХК (засав)');
    });

    test('ORG_NOT_FOUND shows a quiet error and clears on change', () async {
      form.setOrganization(true);
      form.regnumCtrl.text = '9999999';
      await settle();
      expect(form.lookupError, isNotNull);
      expect(form.nameCtrl.text, isEmpty);
      form.regnumCtrl.text = '999';
      expect(form.lookupError, isNull);
    });

    test('ORG_LOOKUP_FAILED shows an error and does not block', () async {
      repo.lookupFailure = const AppError(
        ErrorKind.server,
        'x',
        statusCode: 502,
        code: OrgLookupErrorCode.lookupFailed,
      );
      form.setOrganization(true);
      form.regnumCtrl.text = '1234567';
      await settle();
      expect(form.lookupError, contains('Лавлагаа'));
      // Saving is independent of lookup: name typed by hand still works.
      form.nameCtrl.text = 'Гараар';
      expect(form.validateName(form.nameCtrl.text), isNull);
      expect(form.orgName, 'Гараар');
    });

    test('a stale lookup result is dropped after toggling off', () async {
      form.setOrganization(true);
      form.regnumCtrl.text = '1234567';
      await Future<void>.delayed(const Duration(milliseconds: 6));
      form.setOrganization(false);
      await settle();
      expect(form.nameCtrl.text, isEmpty);
    });
  });

  group('vehicles — owner kind', () {
    test('Vehicle.fromJson parses ownerIsOrganization', () {
      expect(
        Vehicle.fromJson({'id': 'v1', 'ownerIsOrganization': true})
            .ownerIsOrganization,
        isTrue,
      );
      expect(Vehicle.fromJson({'id': 'v1'}).ownerIsOrganization, isFalse);
    });

    test('page DTO carries it per row', () {
      final dto = VehiclePageDto.fromJson({
        'vehicles': [
          {'id': 'a', 'ownerIsOrganization': true},
          {'id': 'b', 'ownerIsOrganization': false},
        ],
        'pagination': {
          'page': 1,
          'pageSize': 50,
          'total': 2,
          'totalPages': 1,
          'hasPrev': false,
          'hasNext': false,
        },
      });
      expect(dto.items.map((v) => v.ownerIsOrganization), [true, false]);
    });

    test('list query sends ?ownerKind=', () async {
      final source = _CaptureVehiclesSource();
      final repo = RemoteVehiclesRepository(dataSource: source);
      await repo.getVehicles(
        query: const VehicleListQuery(ownerKind: VehicleOwnerKind.org),
      );
      expect(source.query!['ownerKind'], 'org');
      await repo.getVehicles(
        query: const VehicleListQuery(ownerKind: VehicleOwnerKind.person),
      );
      expect(source.query!['ownerKind'], 'person');
      await repo.getVehicles(query: const VehicleListQuery());
      expect(source.query!.containsKey('ownerKind'), isFalse);
    });
  });
}
