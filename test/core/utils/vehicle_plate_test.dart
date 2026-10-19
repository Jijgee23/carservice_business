import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isNoPlate matches the sentinel case-insensitively', () {
    expect(isNoPlate('ДУГААРГҮЙ'), isTrue);
    expect(isNoPlate(' дугааргүй '), isTrue);
    expect(isNoPlate('1234ҮНА'), isFalse);
    expect(isNoPlate(null), isFalse);
  });

  test('plateLabel mirrors backend label logic', () {
    expect(plateLabel('1234ҮНА', 'X'), '1234ҮНА');
    expect(
      plateLabel(kNoPlate, 'JT123456789012345'),
      'Дугааргүй · JT123456789012345',
    );
    expect(plateLabel(kNoPlate), 'Дугааргүй');
  });

  test('isValidVin matches backend rules', () {
    expect(isValidVin('JTDKN3DU0A0123456'), isTrue);
    expect(isValidVin('JTDKN3DU0A012345I'), isFalse); // I not allowed in 17
    expect(isValidVin('ZVW30-1234567'), isTrue);
    expect(isValidVin('ZVW30-12-34'), isFalse);
    expect(isValidVin('ABC12'), isFalse);
  });

  test(
    'plate validator accepts the sentinel; vin validator honours required',
    () {
      expect(AppValidators.plate(kNoPlate), isNull);
      expect(AppValidators.vin(required: true)(''), isNotNull);
      expect(AppValidators.vin()(''), isNull);
    },
  );

  test('normalizePlate matches the server: upper, no gaps, Latin lookalikes', () {
    expect(normalizePlate(' 1234 уба '), '1234УБА');
    expect(normalizePlate('1234-ҮНА'), '1234ҮНА');
    expect(normalizePlate('1234өү'), '1234ӨҮ');
    // Latin letters shaped like Cyrillic become Cyrillic...
    expect(normalizePlate('1234ABC'), '1234АВС');
    expect(normalizePlate('1234abc'), '1234АВС');
    // ...others stay (shape, not sound: as on the server).
    expect(normalizePlate('1234UBA'), '1234UВА');
    expect(normalizePlate(kNoPlate), kNoPlate);
    expect(normalizePlate('дугааргүй'), kNoPlate);
  });

  test('a Latin and a Cyrillic spelling compare as one plate', () {
    expect(comparablePlate('1234ABC'), comparablePlate('1234 АВС'));
    expect(formerPlate('1234ABC', '1234АВС'), isNull);
    expect(formerPlate('1234УБА', '5678УБА'), '1234УБА');
  });

  test('plateSearchQuery normalizes only plate-shaped searches', () {
    expect(plateSearchQuery('1234 уба'), '1234УБА');
    expect(plateSearchQuery(' 1234-ABC '), '1234АВС');
    expect(plateSearchQuery('1234у'), '1234У');
    // Names, VINs and free text are left alone (trimmed).
    expect(plateSearchQuery(' Бат '), 'Бат');
    expect(plateSearchQuery('JTDKN3DU0A0123456'), 'JTDKN3DU0A0123456');
    expect(plateSearchQuery('Prius'), 'Prius');
    expect(plateSearchQuery('1234'), '1234');
  });

  test('the plate validator accepts Latin lookalikes once normalized', () {
    expect(AppValidators.isValidPlate('1234 уба'), isTrue);
    expect(AppValidators.isValidPlate('1234ABC'), isTrue);
    expect(AppValidators.isValidPlate('123УБА'), isFalse);
  });
}
