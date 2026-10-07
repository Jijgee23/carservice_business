// ─── AppValidators ────────────────────────────────────────────────────────────
//
// Web-тэй яг нийцэх дүрмүүд (carservice.mn):
//   email    → /^[^\s@]+@[^\s@]+\.[^\s@]+$/
//   phone    → 8 оронтой MN (5-9 эхэлсэн), 976/+976/0-prefix арилгана
//   password → min 8 тэмдэгт
//   plate    → /^\d{4}[А-ЯЁӨҮA-Z]{3}$/  (жш: 1234ҮНА)
//   otp      → яг 6 оронтой тоо
//
// Хэрэглэх (static):
//   TextFormField(validator: AppValidators.email)
//   TextFormField(validator: AppValidators.phone)
//   TextFormField(validator: AppValidators.plate)
//   TextFormField(validator: (v) => AppValidators.required(v, 'Нэр'))
//
// Хэрэглэх (mixin):
//   class _State extends State<W> with ValidatorMixin {
//     TextFormField(validator: emailValidator)
//     TextFormField(validator: requiredField('Нэр'))
//     TextFormField(validator: confirmPassword(passwordCtrl.text))
//   }

import 'package:carservice_business/core/utils/vehicle_plate.dart';

// ─── Regexes (web-тэй дахин нягтлах) ─────────────────────────────────────────

final _emailRx = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

// 4 тоо + 3 Кирилл/Латин том үсэг  (жш: 1234ҮНА, 9876ABC)
final _plateRx = RegExp(r'^\d{4}[А-ЯЁӨҮA-Z]{3}$');

final _otpRx = RegExp(r'^\d{6}$');

// Байгууллагын регистр: яг 7 оронтой тоо (хувь хүний 2 үсэг + 8 тоо биш).
final _orgRegnumRx = RegExp(r'^\d{7}$');

// ─── Pure helpers ─────────────────────────────────────────────────────────────

/// Утасны дугаарыг 8 оронтой канон форматад хувиргана.
/// `+976`, `976`, урд `0` — арилгана. Буруу бол null буцаана.
String? normalizePhone(String? input) {
  final digits = (input ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;

  var d = digits;
  if (d.length == 11 && d.startsWith('976')) d = d.substring(3);
  if (d.length == 9 && d.startsWith('0')) d = d.substring(1);
  if (d.length != 8) return null;
  if (!RegExp(r'^[5-9]').hasMatch(d)) return null;
  return d;
}

/// Улсын дугаарыг канон (том үсэг, зай хасагдсан) болгоно.
String normalizePlate(String input) => input.trim().toUpperCase();

// ─── AppValidators ────────────────────────────────────────────────────────────

class AppValidators {
  AppValidators._();

  // ── Required ───────────────────────────────────────────────────────────────

  /// Хоосон эсэхийг шалгана. [label] алдааны мэдэгдэлд ашиглана.
  static String? required(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label оруулна уу';
    return null;
  }

  // ── Email ──────────────────────────────────────────────────────────────────

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Имэйл хаяг оруулна уу';
    if (!_emailRx.hasMatch(v.trim())) return 'Зөв имэйл хаяг оруулна уу';
    return null;
  }

  static bool isValidEmail(String v) => _emailRx.hasMatch(v.trim());

  // ── Phone ──────────────────────────────────────────────────────────────────

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Утасны дугаар оруулна уу';
    if (normalizePhone(v) == null) {
      return '8 оронтой Монгол дугаар оруулна уу';
    }
    return null;
  }

  static bool isValidPhone(String? v) => normalizePhone(v) != null;

  // ── Organization (Phase 4) ─────────────────────────────────────────────────

  static const orgRegnumMessage = 'Байгууллагын регистр 7 оронтой тоо байна.';

  /// Байгууллагын регистр — яг 7 оронтой тоо; хоосон ч алдаа.
  static String? orgRegnum(String? v) =>
      isValidOrgRegnum(v) ? null : orgRegnumMessage;

  static bool isValidOrgRegnum(String? v) =>
      _orgRegnumRx.hasMatch((v ?? '').trim());

  /// Байгууллагын имэйл — заавал биш, бөглөсөн бол формат шалгана.
  static String? optionalEmail(String? v) =>
      (v == null || v.trim().isEmpty) ? null : email(v);

  // ── Password ───────────────────────────────────────────────────────────────

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Нууц үг оруулна уу';
    if (v.length < 8) return 'Нууц үг хамгийн багадаа 8 тэмдэгт байна';
    return null;
  }

  /// Давтсан нууц үг [original]-тай тохирч байгааг шалгана.
  static String? confirmPassword(String? v, String original) {
    if (v == null || v.isEmpty) return 'Нууц үгийг давтан оруулна уу';
    if (v != original) return 'Нууц үг таарахгүй байна';
    return null;
  }

  // ── Vehicle plate ──────────────────────────────────────────────────────────

  /// Монголын улсын дугаар: 4 тоо + 3 том үсэг  (жш: 1234ҮНА)
  static String? plate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Улсын дугаар оруулна уу';
    if (isNoPlate(v)) return null;
    if (!_plateRx.hasMatch(normalizePlate(v))) {
      return 'Формат буруу — жш: 1234ҮНА';
    }
    return null;
  }

  static bool isValidPlate(String v) =>
      isNoPlate(v) || _plateRx.hasMatch(normalizePlate(v));

  /// VIN: 17 ISO эсвэл 9–14 тэмдэгт (нэг зураастай). Хоосон бол [required]
  /// эсэхээс хамаарна.
  static String? Function(String?) vin({bool required = false}) => (v) {
    if (v == null || v.trim().isEmpty) {
      return required ? 'VIN оруулна уу' : null;
    }
    if (!isValidVin(v)) {
      return 'VIN буруу — 17 тэмдэгт эсвэл 9–14 тэмдэгт (нэг зураас зөвшөөрнө)';
    }
    return null;
  };

  // ── OTP ────────────────────────────────────────────────────────────────────

  static String? otp(String? v) {
    if (v == null || v.trim().isEmpty) return 'OTP код оруулна уу';
    if (!_otpRx.hasMatch(v.trim())) return '6 оронтой тоон код оруулна уу';
    return null;
  }

  // ── Min length ─────────────────────────────────────────────────────────────

  static String? Function(String?) minLength(int min, String label) {
    return (v) {
      if (v == null || v.trim().isEmpty) return '$label оруулна уу';
      if (v.trim().length < min)
        return '$label хамгийн багадаа $min тэмдэгт байна';
      return null;
    };
  }

  // ── Combine ────────────────────────────────────────────────────────────────

  /// Хэд хэдэн validator-ийг дараалан нэгтгэнэ. Эхний алдааг буцаана.
  ///
  /// ```dart
  /// validator: AppValidators.combine([
  ///   (v) => AppValidators.required(v, 'Нэр'),
  ///   AppValidators.minLength(2, 'Нэр'),
  /// ])
  /// ```
  static String? Function(String?) combine(
    List<String? Function(String?)> validators,
  ) {
    return (v) {
      for (final fn in validators) {
        final err = fn(v);
        if (err != null) return err;
      }
      return null;
    };
  }
}

// ─── ValidatorMixin ───────────────────────────────────────────────────────────
//
// State класст `with ValidatorMixin` нэмснээр validator функцуудыг
// шууд дуудаж болно — `AppValidators.email` гэхийн оронд `emailValidator`.
//
// ```dart
// class _MyState extends State<My> with ValidatorMixin {
//   final _passCtrl = TextEditingController();
//
//   // TextFormField дотор:
//   validator: emailValidator
//   validator: phoneValidator
//   validator: plateValidator
//   validator: passwordValidator
//   validator: otpValidator
//   validator: required('Нэр')
//   validator: confirmPassword(_passCtrl.text)
// }
// ```

mixin ValidatorMixin {
  String? Function(String?) get emailValidator => AppValidators.email;
  String? Function(String?) get phoneValidator => AppValidators.phone;
  String? Function(String?) get plateValidator => AppValidators.plate;
  String? Function(String?) get passwordValidator => AppValidators.password;
  String? Function(String?) get otpValidator => AppValidators.otp;

  /// Заавал оруулах талбар.  `validator: requiredField('Нэр')`
  String? Function(String?) requiredField(String label) =>
      (v) => AppValidators.required(v, label);

  /// Нууц үг давтах талбар.  `validator: confirmPassword(_passCtrl.text)`
  String? Function(String?) confirmPassword(String original) =>
      (v) => AppValidators.confirmPassword(v, original);

  /// Хамгийн богино урт.  `validator: minLength(2, 'Нэр')`
  String? Function(String?) minLength(int min, String label) =>
      AppValidators.minLength(min, label);

  /// Хэд хэдэн validator нэгтгэх.
  String? Function(String?) combine(
    List<String? Function(String?)> validators,
  ) => AppValidators.combine(validators);
}
