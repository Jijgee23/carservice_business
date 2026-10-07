// Улсын дугааргүй машин — backend `lib/vehicle-plate.ts` / `lib/vehicles.ts`-тэй
// яг ижил дүрэм. `Vehicle.plate` заавал талбар тул тусгай тэмдэг илгээнэ;
// ийм машиныг VIN-ээр ялгана (VIN заавал).

const String kNoPlate = 'ДУГААРГҮЙ';

/// `ДУГААРГҮЙ` тэмдэгт мөн эсэх (том/жижиг үсэг, зай үл хамаарна).
bool isNoPlate(String? plate) => (plate ?? '').trim().toUpperCase() == kNoPlate;

/// Харуулах дугаар: дугааргүй бол "Дугааргүй · VIN", бусад үед дугаар хэвээр.
String plateLabel(String? plate, [String? vin]) {
  final p = (plate ?? '').trim();
  if (!isNoPlate(p)) return p;
  final v = (vin ?? '').trim();
  return v.isEmpty ? 'Дугааргүй' : 'Дугааргүй · $v';
}

final _vinIsoRx = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');
final _vinLooseRx = RegExp(r'^[A-Z0-9]+(-[A-Z0-9]+)?$');

/// 17 тэмдэгт ISO VIN (I/O/Q-гүй) эсвэл Япон рамын дугаар (нэг зураастай,
/// зураасгүй 9–14 тэмдэгт). `isValidVin` (carcare.mn lib/vehicles.ts)-тэй ижил.
bool isValidVin(String v) {
  final t = v.trim().toUpperCase();
  if (_vinIsoRx.hasMatch(t)) return true;
  if (!_vinLooseRx.hasMatch(t)) return false;
  final len = t.replaceAll('-', '').length;
  return len >= 9 && len <= 14;
}

/// Харьцуулахад зориулсан дугаар: зай/зураас хасч, том үсэг болгоно.
String comparablePlate(String? plate) =>
    (plate ?? '').toUpperCase().replaceAll(RegExp(r'[\s\-]+'), '');

/// Захиалгын дугаарын snapshot одоогийн машины дугаараас ялгаатай бол хуучин
/// дугаарыг (trim хийсэн) буцаана; бусад үед `null`.
String? formerPlate(String? plateSnapshot, String? currentPlate) {
  final snap = (plateSnapshot ?? '').trim();
  if (snap.isEmpty) return null;
  if (comparablePlate(snap) == comparablePlate(currentPlate)) return null;
  return snap;
}
