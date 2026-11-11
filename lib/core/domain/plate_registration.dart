import 'package:carservice_business/core/domain/diagnostic.dart';

/// Reply of `POST /api/v1/vehicles/from-plate` — the order form's
/// «+ 1234УБА — машин бүртгэх» (web `registerVehicleFromPlateAction`).
sealed class PlateRegistration {
  const PlateRegistration();
}

/// Registered (or the tenant's existing ownerless row for that plate). No
/// customer given → `customerId` is null; the order create links it.
final class PlateRegistered extends PlateRegistration {
  const PlateRegistered(this.vehicle);

  final VehicleSummary vehicle;
}

/// Nothing found by plate (or the lookup was throttled): send again with the
/// make and model typed in.
final class PlateNeedsDetails extends PlateRegistration {
  const PlateNeedsDetails(this.reason);

  final String reason;
}
