import 'package:carservice_business/core/utils/business_time.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/domain/pagination.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/data/appointment_dto.dart';
import 'package:carservice_business/features/appointments/data/appointments_data_source.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';

/// Remote adapter for [AppointmentsRepository]. JSON and Dio stay below the
/// repository contract; controllers depend on [AppointmentsRepository] or
/// the fake, matching `RemoteOrdersRepository`.
class RemoteAppointmentsRepository implements AppointmentsRepository {
  RemoteAppointmentsRepository({AppointmentsDataSource? dataSource})
    : _dataSource = dataSource ?? RemoteAppointmentsDataSource();

  final AppointmentsDataSource _dataSource;

  @override
  Future<Result<PagedResult<AppointmentSummary>>> getAppointments({
    AppointmentListQuery? query,
  }) async {
    final effective = query ?? const AppointmentListQuery();
    try {
      final parsed = AppointmentPageDto.fromJson(
        await _dataSource.list(_listQuery(effective)),
      );
      return Ok(
        PagedResult(items: parsed.items, pagination: parsed.pagination),
      );
    } catch (error) {
      return Err(_error(error, 'Цаг захиалгын жагсаалт ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentDayAvailability>> getSlots({
    String? branchId,
    required DateTime date,
    List<String> categoryIds = const [],
  }) async {
    try {
      final json = await _dataSource.slots({
        if (branchId != null) 'branchId': branchId,
        'date': _dateOnly(date),
        if (categoryIds.isNotEmpty) 'categoryIds': categoryIds.join(','),
      });
      if (json is! Map) {
        throw const AppointmentParseException('Сул цагийн хариу буруу байна.');
      }
      return Ok(
        AppointmentDayAvailability.fromJson(Map<String, dynamic>.from(json)),
      );
    } catch (error) {
      return Err(_error(error, 'Сул цаг ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<CalendarDayModel>> getCalendarDay({
    String? branchId,
    required DateTime date,
  }) async {
    try {
      final json = await _dataSource.calendar({
        if (branchId != null) 'branchId': branchId,
        'date': _dateOnly(date),
      });
      if (json is! Map) {
        throw const AppointmentParseException('Хуанлийн хариу буруу байна.');
      }
      return Ok(CalendarDayModel.fromJson(Map<String, dynamic>.from(json)));
    } catch (error) {
      return Err(_error(error, 'Хуанли ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<Map<DateTime, int>>> getMonthCounts({
    String? branchId,
    required DateTime month,
  }) async {
    try {
      // Same `GET /appointments` endpoint as `getAppointments` — the `month`
      // query param switches the route into its month-counts mode
      // server-side, so this reuses `_dataSource.list` rather than adding a
      // parallel transport method for what is, on the wire, the same call.
      final parsed = AppointmentMonthCountsDto.fromJson(
        await _dataSource.list({
          'month': _monthOnly(month),
          if (branchId != null) 'branchId': branchId,
        }),
      );
      return Ok(parsed.counts);
    } catch (error) {
      return Err(_error(error, 'Сарын тоо ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentSummary>> getAppointment(
    String appointmentId,
  ) async {
    try {
      return Ok(
        AppointmentSummaryDto.fromJson(
          _envelope(await _dataSource.detail(appointmentId)),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Цаг захиалга ачаалж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentSummary>> createAppointment({
    required String branchId,
    required String customerId,
    String? vehicleId,
    required DateTime requestedAt,
    String? note,
    List<String> categoryIds = const [],
    bool confirmed = false,
    String? assignedToId,
  }) async {
    try {
      final body = <String, dynamic>{
        'branchId': branchId,
        'customerId': customerId,
        if (vehicleId != null) 'vehicleId': vehicleId,
        'requestedAt': _businessLocalDateTime(requestedAt),
        if (note != null && note.isNotEmpty) 'note': note,
        if (categoryIds.isNotEmpty) 'categoryIds': categoryIds,
        if (confirmed) 'confirmed': confirmed,
        if (assignedToId != null) 'assignedToId': assignedToId,
      };
      return Ok(
        AppointmentSummaryDto.fromJson(
          _envelope(await _dataSource.create(body)),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Цаг захиалга үүсгэж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentLifecycleResult>> confirm(
    String appointmentId, {
    String? assignedToId,
  }) async {
    try {
      return Ok(
        AppointmentLifecycleResultDto.fromJson(
          await _dataSource.confirm(
            appointmentId,
            body: assignedToId == null ? null : {'assignedToId': assignedToId},
          ),
          fallbackStatus: AppointmentStatus.CONFIRMED,
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Цаг баталгаажуулж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentSummary>> updateAssignee(
    String appointmentId,
    String assignedToId,
  ) async {
    try {
      return Ok(
        AppointmentSummaryDto.fromJson(
          _envelope(
            await _dataSource.update(appointmentId, {
              'assignedToId': assignedToId,
            }),
          ),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Мастер солиж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentLifecycleResult>> reject(
    String appointmentId,
  ) async {
    try {
      return Ok(
        AppointmentLifecycleResultDto.fromJson(
          await _dataSource.reject(appointmentId),
          fallbackStatus: AppointmentStatus.REJECTED,
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Цаг татгалзаж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentLifecycleResult>> markNoShow(
    String appointmentId,
  ) async {
    try {
      return Ok(
        AppointmentLifecycleResultDto.fromJson(
          await _dataSource.noShow(appointmentId),
          fallbackStatus: AppointmentStatus.NO_SHOW,
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Ирээгүй гэж тэмдэглэж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentLifecycleResult>> markArrived(
    String appointmentId,
  ) async {
    try {
      return Ok(
        AppointmentLifecycleResultDto.fromJson(
          await _dataSource.arrived(appointmentId),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Ирснийг тэмдэглэж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentLifecycleResult>> cancel(
    String appointmentId,
  ) async {
    try {
      final json = _envelope(await _dataSource.cancel(appointmentId));
      final appointment = json['appointment'];
      final status = appointment is Map && appointment['status'] is String
          ? AppointmentStatus.fromJson(appointment['status'])
          : AppointmentStatus.CANCELLED;
      return Ok(
        AppointmentLifecycleResult(
          appointmentId: appointmentId,
          status: status,
        ),
      );
    } catch (error) {
      return Err(_error(error, 'Цаг цуцалж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentRescheduleResult>> reschedule(
    String appointmentId,
    DateTime requestedAt, {
    bool confirmed = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'requestedAt': _businessLocalDateTime(requestedAt),
        if (confirmed) 'confirmed': confirmed,
      };
      return Ok(
        AppointmentRescheduleResultDto.fromJson(
          await _dataSource.reschedule(appointmentId, body),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Цаг шилжүүлж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentBulkResult>> bulkChangeCategory(
    List<String> appointmentIds,
    String categoryId,
  ) async {
    try {
      return Ok(
        AppointmentBulkResultDto.fromJson(
          await _dataSource.bulkCategory({
            'appointmentIds': appointmentIds,
            'categoryId': categoryId,
          }),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Бөөн ажлын төрөл өөрчлөх амжилтгүй'));
    }
  }

  @override
  Future<Result<AppointmentPaymentCheckResult>> checkPayment(
    String appointmentId,
  ) async {
    try {
      return Ok(
        AppointmentPaymentCheckResultDto.fromJson(
          await _dataSource.checkPayment(appointmentId),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Төлбөр шалгаж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentPaymentRetryResult>> retryPayment(
    String appointmentId,
  ) async {
    try {
      return Ok(
        AppointmentPaymentRetryResultDto.fromJson(
          await _dataSource.retryPayment(appointmentId),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Төлбөр дахин үүсгэж чадсангүй'));
    }
  }

  @override
  Future<Result<AppointmentRefundResult>> refundPayment(
    String appointmentId, {
    required String note,
  }) async {
    try {
      return Ok(
        AppointmentRefundResultDto.fromJson(
          await _dataSource.refundPayment(appointmentId, {'note': note}),
        ).value,
      );
    } catch (error) {
      return Err(_error(error, 'Төлбөр буцааж чадсангүй'));
    }
  }
}

Map<String, dynamic> _listQuery(AppointmentListQuery query) => {
  'page': query.page,
  'pageSize': query.pageSize,
  if (query.status != null) 'status': query.status!.name,
  if (query.branchId != null) 'branchId': query.branchId,
  if (query.date != null) 'date': _dateOnly(query.date!),
  // Trimmed, and omitted entirely when empty/whitespace-only — the server
  // treats a missing `q` and an empty `q` the same, but sending an empty
  // string would still be a vacuous parameter on the wire.
  if (query.q != null && query.q!.trim().isNotEmpty) 'q': query.q!.trim(),
};

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _monthOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

String _businessLocalDateTime(DateTime input) {
  // Slot `iso` values arrive as UTC (`…Z`); sending their UTC fields as
  // wall time shifted bookings 8h early (12:30 → 04:30, rejected PAST_TIME).
  // A UTC instant becomes Ulaanbaatar wall time (the zone the server reads
  // this zone-less string in); naive values are already business time.
  final value = input.isUtc ? toBusinessTime(input) : input;
  String two(int item) => item.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}T${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

Map<String, dynamic> _envelope(Object? raw) {
  if (raw is! Map) throw const AppointmentParseException('Хариу буруу байна.');
  return Map<String, dynamic>.from(raw);
}

AppError _error(Object error, String fallback) => switch (error) {
  AppError value => value,
  AppointmentParseException value => AppError(ErrorKind.unknown, value.message),
  _ => AppError(ErrorKind.unknown, fallback),
};
