import 'package:carservice_business/core/utils/validators.dart';

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

/// Харьцуулахад зориулсан дугаар ([normalizePlate]): латин ба кирилл, зай,
/// зураасаас үл хамааран нэг машин нэг утгатай.
String comparablePlate(String? plate) => normalizePlate(plate ?? '');

final _plateQueryRx = RegExp(r'^\d{4}[\s\-]*[A-Za-zА-Яа-яЁёӨөҮү]{1,3}$');

/// Хайлтын текст: дугаар шиг (4 цифр + 1–3 үсэг) бол канон дугаар болгоно,
/// ингэснээр "1234 уба" нь "1234УБА"-г, латин "1234ABC" нь "1234АВС"-г олно.
/// Нэр, VIN зэрэг бусад текст хэвээр (trim).
String plateSearchQuery(String query) {
  final q = query.trim();
  return _plateQueryRx.hasMatch(q) ? normalizePlate(q) : q;
}

/// Захиалгын дугаарын snapshot одоогийн машины дугаараас ялгаатай бол хуучин
/// дугаарыг (trim хийсэн) буцаана; бусад үед `null`.
String? formerPlate(String? plateSnapshot, String? currentPlate) {
  final snap = (plateSnapshot ?? '').trim();
  if (snap.isEmpty) return null;
  if (comparablePlate(snap) == comparablePlate(currentPlate)) return null;
  return snap;
}
