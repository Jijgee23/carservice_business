import 'package:carservice_business/core/network/token_interceptor.dart';
import 'package:carservice_business/core/network/working_branch_interceptor.dart';
import 'package:carservice_business/core/network/dio_error_mapper.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  static final ApiService instance = ApiService._internal();
  factory ApiService() => instance;

  late final Dio _dio;

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        responseType: ResponseType.json,
        baseUrl: dotenv.env['BASE_URL']!,
        // Mobile networks: 5s dropped ordinary calls on a weak 4G signal.
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
      ),
    );

    _dio.interceptors.add(const TransferTimeoutInterceptor());
    _dio.interceptors.add(TokenInterceptor(dio));
    _dio.interceptors.add(WorkingBranchInterceptor());
    if (kDebugMode) _dio.interceptors.add(_DebugLogInterceptor());
  }
  Dio get dio => _dio;
}

/// Gives uploads and file downloads room to finish. Multipart bodies
/// (diagnostic photos, feedback screenshots) and byte responses (server-
/// rendered PDFs, Excel exports) routinely take longer than an ordinary
/// JSON call; applied centrally so no caller can forget it.
class TransferTimeoutInterceptor extends Interceptor {
  const TransferTimeoutInterceptor();

  static const transferTimeout = Duration(seconds: 120);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.data is FormData) {
      options.sendTimeout = transferTimeout;
      options.receiveTimeout = transferTimeout;
    }
    if (options.responseType == ResponseType.bytes ||
        options.responseType == ResponseType.stream) {
      options.receiveTimeout = transferTimeout;
    }
    handler.next(options);
  }
}

/// The server's `{ error }` message, or null for a non-JSON body (an HTML
/// 502 page from a proxy must not crash error handling).
String? _serverError(Response<dynamic>? response) {
  final data = response?.data;
  if (data is Map && data['error'] != null) return data['error'].toString();
  return null;
}

void _debugLog(Object? value) {
  if (kDebugMode) debugPrint('$value');
}

Future<Response?> api(
  Api method,
  String endpoint, {
  Map<String, dynamic>? body,
  Map<String, String>? headers,
  bool skipAuthenticaor = true,
}) async {
  try {
    final apiService = ApiService.instance;
    return await apiService.dio.request(
      endpoint,
      data: body,
      options: Options(
        // validateStatus: (status) {
        //   if (status != null && status < 500) {
        //     return false;
        //   }
        //   return true;
        // },
        method: method.name.toUpperCase(),
      ),
    );
  } on DioException catch (e) {
    _handleDioError(e);
    return null;
  }
}

void _handleDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      _debugLog('Түр хүлээнэ үү!');
      break;

    case DioExceptionType.connectionError:
      _debugLog(
        'Серверт холбогдож чадсангүй, Инфосистемс ХХК-д холбогдоно уу!',
      );
      break;

    case DioExceptionType.badResponse:
      final statusCode = e.response?.statusCode;
      _debugLog(e.response?.data);
      if (statusCode == 500) {
        messageError('Серверийн алдаа гарлаа!');
      } else if (statusCode == 400) {
        messageError(_serverError(e.response) ?? 'Амжилтгүй');
      } else if (statusCode == 404) {
        messageError('Мэдээлэл олдсонгүй!');
      } else if (statusCode == 405) {
        messageError('Мэдээлэл олдсонгүй!');
      } else {
        if (e.requestOptions.uri.path.contains('logout')) {
          break;
        }
        messageWarning(_serverError(e.response) ?? 'Алдаа гарлаа');
      }
      break;

    case DioExceptionType.cancel:
      // debugPrint('Request cancelled');
      break;

    default:
      // The raw Dio text is for developers; staff get a plain message.
      _debugLog(e.message);
      messageError('Алдаа гарлаа. Дахин оролдоно уу.');
  }
}

enum Api { get, post, patch, delete, put }

// Error-г AppError болгон шидэнэ — repository-д ашиглана.
// api() дуудлагаас ялгаатай нь toast харуулахгүй.
Future<Response> apiOrThrow(Api method, String endpoint, {dynamic body}) async {
  try {
    return await ApiService.instance.dio.request(
      endpoint,
      data: body,
      options: Options(method: method.name.toUpperCase()),
    );
  } on DioException catch (e) {
    throw mapDioException(e);
  }
}

class _DebugLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('→ ${options.method} ${options.uri}');
    if (options.data != null) debugPrint('  body: ${options.data}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('← ${response.statusCode} ${response.requestOptions.uri}');
    debugPrint('  body: ${response.data}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('✗ ${err.response?.statusCode} ${err.requestOptions.uri}');
    if (err.response?.data != null) debugPrint('  body: ${err.response?.data}');
    handler.next(err);
  }
}

// Future<void> toUrl(String url) async {
//   try {
//     await launchUrl(Uri.parse(url));
//   } catch (e) {
//     // final canLaunch = await canLaunchUrl(Uri.parse(url));
//     // if (!canLaunch) {

//     //   throw Exception('Could not launch $url');
//     // }
//     messageError('Холбоос олдсонгүй');
//   }
// }
