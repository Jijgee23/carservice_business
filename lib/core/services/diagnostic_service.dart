import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/plate_registration.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/result.dart';

// Олон feature-д хуваалцдаг lookup operations.
// Diagnostic-specific (templates, reports) → DiagnosticRepository
class DiagnosticService {
  // ─── Vehicles ──────────────────────────────────────────────────────────────

  static Future<List<VehicleSummary>> searchVehicles(String q) async {
    // A plate-shaped search is sent canonical, as plates are stored.
    final encoded = Uri.encodeQueryComponent(plateSearchQuery(q));
    final res = await api(Api.get, 'vehicles?q=$encoded&limit=20');
    if (res == null) return [];
    final list = res.data['vehicles'] as List;
    return list
        .map((e) => VehicleSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Тухайн харилцагчийн машинууд — вэбийн "харилцагч → машин" урсгалтай ижил.
  static Future<List<VehicleSummary>> vehiclesForCustomer(
    String customerId,
  ) async {
    final encoded = Uri.encodeQueryComponent(customerId);
    final res = await api(Api.get, 'vehicles?customerId=$encoded&limit=100');
    if (res == null) return [];
    final list = res.data['vehicles'] as List? ?? const [];
    return list
        .map((e) => VehicleSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// «+ 1234УБА — машин бүртгэх»: the server fetches the vehicle by plate
  /// (or takes [make]/[model]) and registers it — for [customerId], else
  /// ownerless (the order create links it). No toast: the picker shows the
  /// error under its field, like the web form.
  static Future<Result<PlateRegistration>> registerVehicleFromPlate({
    required String plate,
    String? customerId,
    String? make,
    String? model,
  }) async {
    try {
      final res = await apiOrThrow(
        Api.post,
        'vehicles/from-plate',
        body: {
          'plate': plate,
          'customerId': ?customerId,
          'make': ?make,
          'model': ?model,
        },
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['needsDetails'] == true) {
        return Ok(
          PlateNeedsDetails(
            data['reason'] as String? ??
                'Машины мэдээлэл олдсонгүй — марк, загвараа оруулна уу.',
          ),
        );
      }
      return Ok(
        PlateRegistered(
          VehicleSummary.fromJson(
            Map<String, dynamic>.from(data['vehicle'] as Map),
          ),
        ),
      );
    } on AppError catch (e) {
      return Err(e);
    } catch (_) {
      return const Err(
        AppError(ErrorKind.unknown, 'Машин бүртгэхэд алдаа гарлаа.'),
      );
    }
  }

  static Future<VehicleSummary?> createVehicle({
    required String plate,
    required String make,
    required String model,
    String? vin,
    int? year,
    int? mileage,
    String? customerId,
  }) async {
    final res = await api(
      Api.post,
      'vehicles',
      body: {
        'plate': plate,
        'make': make,
        'model': model,
        if (vin != null && vin.isNotEmpty) 'vin': vin,
        'year': ?year,
        'mileage': ?mileage,
        if (customerId != null && customerId.isNotEmpty)
          'customerId': customerId,
      },
    );
    if (res == null) return null;
    return VehicleSummary.fromJson(res.data['vehicle'] as Map<String, dynamic>);
  }

  // ─── Customers ─────────────────────────────────────────────────────────────

  static Future<List<CustomerSummary>> searchCustomers(String q) async {
    final encoded = Uri.encodeQueryComponent(q);
    final res = await api(Api.get, 'customers?q=$encoded&limit=20');
    if (res == null) return [];
    final list = res.data['customers'] as List;
    return list
        .map((e) => CustomerSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<CustomerSummary?> createCustomer({
    required String fullName,
    required String phone,
    String? email,
  }) async {
    final res = await api(
      Api.post,
      'customers',
      body: {
        'fullName': fullName,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
    if (res == null) return null;
    return CustomerSummary.fromJson(
      res.data['customer'] as Map<String, dynamic>,
    );
  }

  // ─── HUR ───────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> lookupHurVehicle(String plate) async {
    return (await lookupHurWithMatch(plate))?.vehicle;
  }

  /// HUR хайлт + тухайн tenant-ийн таарсан үйлчлүүлэгчийн id. Эзний утас
  /// маскалсан тул (`owner.phone`) түүгээр үйлчлүүлэгч тааруулахгүй —
  /// зөвхөн `matchedCustomerId`-г ашиглана.
  static Future<({Map<String, dynamic>? vehicle, String? matchedCustomerId})?>
  lookupHurWithMatch(String plate) async {
    final encoded = Uri.encodeQueryComponent(plate);
    final res = await api(Api.get, 'hur/vehicle?plate=$encoded');
    if (res == null) return null;
    final data = res.data;
    if (data is! Map) return null;
    final m = data['matchedCustomerId'];
    return (
      vehicle: data['vehicle'] as Map<String, dynamic>?,
      matchedCustomerId: m is String && m.isNotEmpty ? m : null,
    );
  }

  // ─── Branches ──────────────────────────────────────────────────────────────

  static Future<List<BranchSummary>> getBranches() async {
    final res = await api(Api.get, 'branches');
    if (res == null) return [];
    final list = res.data['branches'] as List;
    return list
        .map((e) => BranchSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
