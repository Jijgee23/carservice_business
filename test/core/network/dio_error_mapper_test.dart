import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

RequestOptions _req() => RequestOptions(path: '/x');

DioException _badResponse(int statusCode, {Object? data}) => DioException(
  requestOptions: _req(),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: _req(),
    statusCode: statusCode,
    data: data,
  ),
);

void main() {
  group('mapDioException — status-code mapping', () {
    test('401 maps to unauthorized with a fixed message', () {
      final error = mapDioException(
        _badResponse(401, data: {'error': 'ignored'}),
      );
      expect(error.kind, ErrorKind.unauthorized);
      expect(error.message, 'Нэвтрэх шаардлагатай');
      expect(error.statusCode, 401);
    });

    test('403 uses the server message when present, else a fallback', () {
      final withMessage = mapDioException(
        _badResponse(403, data: {'error': 'working branch is stale'}),
      );
      expect(withMessage.kind, ErrorKind.forbidden);
      expect(withMessage.message, 'working branch is stale');

      final withoutMessage = mapDioException(_badResponse(403, data: {}));
      expect(withoutMessage.message, 'Хандах эрх байхгүй');
    });

    test('404 maps to notFound with a fallback message when none is sent', () {
      final error = mapDioException(_badResponse(404));
      expect(error.kind, ErrorKind.notFound);
      expect(error.message, 'Олдсонгүй');
      expect(error.statusCode, 404);
    });

    test('404 surfaces the server message and code when present', () {
      final error = mapDioException(
        _badResponse(
          404,
          data: {
            'error': 'Төлбөр аль хэдийн цуцлагдсан.',
            'code': 'PAYMENT_NOT_FOUND',
          },
        ),
      );
      expect(error.kind, ErrorKind.notFound);
      expect(error.message, 'Төлбөр аль хэдийн цуцлагдсан.');
      expect(error.code, 'PAYMENT_NOT_FOUND');
    });

    test('500 maps to server with a fallback message when none is sent', () {
      final error = mapDioException(_badResponse(500));
      expect(error.kind, ErrorKind.server);
      expect(error.message, 'Серверийн алдаа');
      expect(error.statusCode, 500);
    });

    test('500 surfaces the server message when present', () {
      final error = mapDioException(
        _badResponse(
          500,
          data: {'error': 'Серверийн алдаа гарлаа. Дахин оролдоно уу.'},
        ),
      );
      expect(error.kind, ErrorKind.server);
      expect(error.message, 'Серверийн алдаа гарлаа. Дахин оролдоно уу.');
    });

    test(
      '409 stays ErrorKind.unknown but carries statusCode/code/fieldErrors',
      () {
        final error = mapDioException(
          _badResponse(
            409,
            data: {
              'error': 'Энэ цаг аль хэдийн захиалагдсан байна.',
              'code': 'RESERVATION_CONFLICT',
              'fieldErrors': {'confirmNeeded': 'true'},
            },
          ),
        );
        expect(error.kind, ErrorKind.unknown);
        expect(error.statusCode, 409);
        expect(error.code, 'RESERVATION_CONFLICT');
        expect(error.fieldErrors, {'confirmNeeded': 'true'});
        expect(error.message, 'Энэ цаг аль хэдийн захиалагдсан байна.');
      },
    );

    test(
      '422 stays ErrorKind.unknown but carries statusCode and fieldErrors',
      () {
        final error = mapDioException(
          _badResponse(
            422,
            data: {
              'error': 'Хүсэлт буруу.',
              'fieldErrors': {'requestedAt': 'Огноо буруу.'},
            },
          ),
        );
        expect(error.kind, ErrorKind.unknown);
        expect(error.statusCode, 422);
        expect(error.fieldErrors, {'requestedAt': 'Огноо буруу.'});
      },
    );

    test('409 APPOINTMENT_NOT_PAYABLE keeps the server message and code', () {
      final error = mapDioException(
        _badResponse(
          409,
          data: {
            'error': 'Энэ цаг цуцлагдсан тул хураамж төлөх боломжгүй.',
            'code': 'APPOINTMENT_NOT_PAYABLE',
          },
        ),
      );
      expect(error.statusCode, 409);
      expect(error.code, 'APPOINTMENT_NOT_PAYABLE');
      expect(error.message, 'Энэ цаг цуцлагдсан тул хураамж төлөх боломжгүй.');
    });

    test('409 and 422 never collapse into the same statusCode', () {
      final conflict = mapDioException(_badResponse(409, data: {}));
      final validation = mapDioException(_badResponse(422, data: {}));
      expect(conflict.statusCode, isNot(validation.statusCode));
    });

    test('other/unmapped status falls back to ErrorKind.unknown', () {
      final error = mapDioException(_badResponse(418, data: {}));
      expect(error.kind, ErrorKind.unknown);
      expect(error.statusCode, 418);
      expect(error.message, 'Алдаа гарлаа');
    });
  });

  group('mapDioException — transport-level DioExceptionTypes', () {
    test('connectionTimeout maps to network with no response', () {
      final error = mapDioException(
        DioException(
          requestOptions: _req(),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      expect(error.kind, ErrorKind.network);
      expect(error.message, 'Холболт байхгүй');
      expect(error.statusCode, isNull);
    });

    test('sendTimeout, receiveTimeout, connectionError all map to network', () {
      for (final type in [
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        final error = mapDioException(
          DioException(requestOptions: _req(), type: type),
        );
        expect(error.kind, ErrorKind.network, reason: type.toString());
      }
    });

    test('cancel and other unmapped types fall back to unknown', () {
      final error = mapDioException(
        DioException(
          requestOptions: _req(),
          type: DioExceptionType.cancel,
          message: 'cancelled',
        ),
      );
      expect(error.kind, ErrorKind.unknown);
      expect(error.message, 'cancelled');
    });

    test('status is authoritative even when type is not badResponse', () {
      // Interceptor-rejected responses can retain `unknown` while still
      // carrying a valid HTTP response.
      final error = mapDioException(
        DioException(
          requestOptions: _req(),
          type: DioExceptionType.unknown,
          response: Response<dynamic>(
            requestOptions: _req(),
            statusCode: 404,
            data: {},
          ),
        ),
      );
      expect(error.kind, ErrorKind.notFound);
      expect(error.statusCode, 404);
    });
  });

  group('mapDioException — fieldErrors/code metadata extraction', () {
    test('extracts code and fieldErrors together', () {
      final error = mapDioException(
        _badResponse(
          422,
          data: {
            'error': 'bad',
            'code': 'CODE',
            'fieldErrors': {'a': 'b', 'c': 'd'},
          },
        ),
      );
      expect(error.code, 'CODE');
      expect(error.fieldErrors, {'a': 'b', 'c': 'd'});
    });

    test('non-map body yields no metadata', () {
      final error = mapDioException(_badResponse(422, data: 'plain string'));
      expect(error.code, isNull);
      expect(error.fieldErrors, isNull);
      expect(error.message, 'Алдаа гарлаа');
    });

    test('non-string code is dropped', () {
      final error = mapDioException(
        _badResponse(422, data: {'error': 'x', 'code': 409}),
      );
      expect(error.code, isNull);
    });

    test('blank code trims to null', () {
      final error = mapDioException(
        _badResponse(422, data: {'error': 'x', 'code': '   '}),
      );
      expect(error.code, isNull);
    });

    test('code is trimmed', () {
      final error = mapDioException(
        _badResponse(422, data: {'error': 'x', 'code': '  CODE  '}),
      );
      expect(error.code, 'CODE');
    });

    test('fieldErrors that is not a map is dropped', () {
      final error = mapDioException(
        _badResponse(422, data: {'error': 'x', 'fieldErrors': 'not-a-map'}),
      );
      expect(error.fieldErrors, isNull);
    });

    test('a partially-malformed fieldErrors map is dropped entirely, not partially bound', () {
      final error = mapDioException(
        _badResponse(
          422,
          data: {
            'error': 'x',
            'fieldErrors': {'a': 'ok', 'b': 42},
          },
        ),
      );
      expect(error.fieldErrors, isNull);
    });

    test('a non-string fieldErrors key drops the whole map', () {
      final error = mapDioException(
        _badResponse(
          422,
          data: {
            'error': 'x',
            'fieldErrors': {1: 'value'},
          },
        ),
      );
      expect(error.fieldErrors, isNull);
    });

    test('an empty but well-formed fieldErrors map is preserved as empty', () {
      final error = mapDioException(
        _badResponse(
          422,
          data: {'error': 'x', 'fieldErrors': <String, String>{}},
        ),
      );
      expect(error.fieldErrors, isNotNull);
      expect(error.fieldErrors, isEmpty);
    });
  });
}
