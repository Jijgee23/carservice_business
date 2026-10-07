import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/appointment_detail_controller.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_detail_screen.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';

import '../../fakes/fake_order_repository.dart';

class _RecordingOrdersRepository extends FakeOrderRepository {
  _RecordingOrdersRepository({this.failure});

  final AppError? failure;
  int createCalls = 0;
  String? branchId;
  String? customerId;
  String? vehicleId;
  String? appointmentId;
  int? estimatedDurationMinutes;

  @override
  Future<Result<ServiceOrderSummary>> createOrder({
    required String branchId,
    required String customerId,
    required String vehicleId,
    String? assignedToId,
    DateTime? scheduledAt,
    String? notes,
    String? appointmentId,
    int? estimatedDurationMinutes,
    OrderIntakeDraft? intake,
    bool? isPostpaid,
    bool? isInternal,
  }) async {
    createCalls++;
    this.branchId = branchId;
    this.customerId = customerId;
    this.vehicleId = vehicleId;
    this.appointmentId = appointmentId;
    this.estimatedDurationMinutes = estimatedDurationMinutes;
    if (failure != null) return Err(failure!);
    return super.createOrder(
      branchId: branchId,
      customerId: customerId,
      vehicleId: vehicleId,
      assignedToId: assignedToId,
      scheduledAt: scheduledAt,
      notes: notes,
      appointmentId: appointmentId,
      estimatedDurationMinutes: estimatedDurationMinutes,
      intake: intake,
    );
  }
}

AppointmentSummary _appointment({AppointmentOrderRef? serviceOrder}) =>
    AppointmentSummary(
      id: 'appointment-1',
      status: AppointmentStatus.CONFIRMED,
      requestedAt: DateTime(2026, 9, 22, 10),
      note: 'Тоормос шалгах',
      branch: const AppointmentBranchRef(id: 'branch-1', name: 'Төв'),
      customer: const AppointmentCustomerRef(
        id: 'customer-1',
        fullName: 'Бат',
      ),
      vehicle: const AppointmentVehicleRef(
        id: 'vehicle-1',
        plate: '1234ABC',
      ),
      serviceOrder: serviceOrder,
    );

void main() {
  group('AppointmentDetailController.convertToOrder', () {
    test(
      'delegates appointment-origin creation with no duration override',
      () async {
        final appointment = _appointment();
        final orders = _RecordingOrdersRepository();
        final controller = AppointmentDetailController(
          initial: appointment,
          ordersRepository: orders,
        );
        addTearDown(controller.dispose);

        final result = await controller.convertToOrder();

        expect(result, isA<Ok<ServiceOrderSummary>>());
        expect(orders.createCalls, 1);
        expect(orders.branchId, 'branch-1');
        expect(orders.customerId, 'customer-1');
        expect(orders.vehicleId, 'vehicle-1');
        expect(orders.appointmentId, 'appointment-1');
        expect(orders.estimatedDurationMinutes, isNull);
        expect(controller.appointment?.serviceOrder?.id, isNotNull);
        expect(controller.mutating, isFalse);
      },
    );

    test(
      'failed conversion leaves the appointment link and state untouched',
      () async {
        final appointment = _appointment();
        final orders = _RecordingOrdersRepository(
          failure: const AppError(ErrorKind.network, 'offline'),
        );
        final controller = AppointmentDetailController(
          initial: appointment,
          ordersRepository: orders,
        );
        addTearDown(controller.dispose);

        final result = await controller.convertToOrder();

        expect(result, isA<Err<ServiceOrderSummary>>());
        expect(controller.appointment, same(appointment));
        expect(controller.appointment?.serviceOrder, isNull);
        expect(controller.mutating, isFalse);
      },
    );

    test(
      'does not create a second order when appointment is already linked',
      () async {
        final orders = _RecordingOrdersRepository();
        final controller = AppointmentDetailController(
          initial: _appointment(
            serviceOrder: const AppointmentOrderRef(id: 'order-existing'),
          ),
          ordersRepository: orders,
        );
        addTearDown(controller.dispose);

        final result = await controller.convertToOrder();

        expect(result, isA<Err<ServiceOrderSummary>>());
        expect(orders.createCalls, 0);
      },
    );

    test(
      'account-origin appointment without customer/vehicle ids is not convertible',
      () async {
        final orders = _RecordingOrdersRepository();
        final controller = AppointmentDetailController(
          initial: AppointmentSummary(
            id: 'account-appointment-1',
            status: AppointmentStatus.CONFIRMED,
            branch: const AppointmentBranchRef(id: 'branch-1'),
            account: const AppointmentAccountRef(name: 'Бат'),
            accountVehicle: const AppointmentVehicleRef(plate: '1234ABC'),
          ),
          ordersRepository: orders,
        );
        addTearDown(controller.dispose);

        final result = await controller.convertToOrder();

        expect(result, isA<Err<ServiceOrderSummary>>());
        expect(orders.createCalls, 0);
        expect(controller.appointment?.serviceOrder, isNull);
      },
    );
  });

  test('appointment order route encodes the server order id', () {
    expect(
      appointmentOrderRoute('order/with space'),
      '/orders/order%2Fwith%20space',
    );
  });
}
