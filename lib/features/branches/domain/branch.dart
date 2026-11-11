import 'package:carservice_business/core/errors/app_error.dart';

/// Weekdays in the server's order (`lib/branches.ts` `WEEK_DAYS`).
enum BranchWeekday {
  mon('MON', 'Даваа', 'Дав'),
  tue('TUE', 'Мягмар', 'Мяг'),
  wed('WED', 'Лхагва', 'Лха'),
  thu('THU', 'Пүрэв', 'Пүр'),
  fri('FRI', 'Баасан', 'Баа'),
  sat('SAT', 'Бямба', 'Бям'),
  sun('SUN', 'Ням', 'Ням');

  const BranchWeekday(this.code, this.label, this.short);

  final String code;
  final String label;
  final String short;

  static BranchWeekday? fromCode(Object? code) {
    for (final d in values) {
      if (d.code == code) return d;
    }
    return null;
  }

  /// New branches open Monday–Friday (`DEFAULT_OPEN_DAYS`).
  bool get openByDefault => index < 5;
}

/// One row of `GET /api/v1/branches`.
class BranchSummary {
  const BranchSummary({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.isPrimary = false,
    this.isActive = true,
  });

  factory BranchSummary.fromJson(Map<dynamic, dynamic> j) => BranchSummary(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    address: _str(j['address']),
    phone: _str(j['phone']),
    isPrimary: j['isPrimary'] == true,
    // The list returns active branches only and may omit the flag.
    isActive: j['isActive'] != false,
  );

  final String id;
  final String name;
  final String? address;
  final String? phone;
  final bool isPrimary;
  final bool isActive;

  BranchSummary copyWith({bool? isPrimary, bool? isActive}) => BranchSummary(
    id: id,
    name: name,
    address: address,
    phone: phone,
    isPrimary: isPrimary ?? this.isPrimary,
    isActive: isActive ?? this.isActive,
  );
}

class BranchTag {
  const BranchTag({required this.id, required this.name});

  factory BranchTag.fromJson(Map<dynamic, dynamic> j) =>
      BranchTag(id: j['id']?.toString() ?? '', name: j['name']?.toString() ?? '');

  final String id;
  final String name;
}

class BranchDaySchedule {
  const BranchDaySchedule({
    required this.weekday,
    required this.isOpen,
    this.openTime,
    this.closeTime,
  });

  final BranchWeekday weekday;
  final bool isOpen;
  final String? openTime;
  final String? closeTime;

  BranchDaySchedule copyWith({bool? isOpen, String? openTime, String? closeTime}) =>
      BranchDaySchedule(
        weekday: weekday,
        isOpen: isOpen ?? this.isOpen,
        openTime: openTime ?? this.openTime,
        closeTime: closeTime ?? this.closeTime,
      );

  Map<String, Object?> toJson() => {
    'weekday': weekday.code,
    'isOpen': isOpen,
    'openTime': openTime,
    'closeTime': closeTime,
  };
}

/// `GET /api/v1/branches/[id]` — the edit form's fields.
class BranchDetail {
  const BranchDetail({
    required this.id,
    required this.name,
    this.phone,
    this.city,
    this.district,
    this.khoroo,
    this.address,
    this.latitude,
    this.longitude,
    this.openTime,
    this.closeTime,
    this.slotMinutes,
    this.slotCapacity,
    this.isPrimary = false,
    this.isActive = true,
    this.tags = const [],
    this.employeeCount = 0,
    this.schedules = const [],
  });

  factory BranchDetail.fromJson(Object? json) {
    final root = json is Map && json['branch'] is Map ? json['branch'] as Map : json;
    if (root is! Map) throw const FormatException('Салбарын хариу буруу байна');
    final byDay = <BranchWeekday, BranchDaySchedule>{};
    final rawSchedules = root['schedules'];
    if (rawSchedules is List) {
      for (final raw in rawSchedules) {
        if (raw is! Map) continue;
        final day = BranchWeekday.fromCode(raw['weekday']);
        if (day == null) continue;
        byDay[day] = BranchDaySchedule(
          weekday: day,
          isOpen: raw['isOpen'] == true,
          openTime: _str(raw['openTime']),
          closeTime: _str(raw['closeTime']),
        );
      }
    }
    final rawTags = root['tags'];
    return BranchDetail(
      id: root['id']?.toString() ?? '',
      name: root['name']?.toString() ?? '',
      phone: _str(root['phone']),
      city: _str(root['city']),
      district: _str(root['district']),
      khoroo: _str(root['khoroo']),
      address: _str(root['address']),
      latitude: _num(root['latitude']),
      longitude: _num(root['longitude']),
      openTime: _str(root['openTime']),
      closeTime: _str(root['closeTime']),
      slotMinutes: _num(root['slotMinutes'])?.toInt(),
      slotCapacity: _num(root['slotCapacity'])?.toInt(),
      isPrimary: root['isPrimary'] == true,
      isActive: root['isActive'] != false,
      tags: rawTags is List
          ? [for (final t in rawTags) if (t is Map) BranchTag.fromJson(t)]
          : const [],
      employeeCount: _num(root['employeeCount'])?.toInt() ?? 0,
      schedules: [
        for (final d in BranchWeekday.values)
          byDay[d] ?? BranchDaySchedule(weekday: d, isOpen: false),
      ],
    );
  }

  final String id;
  final String name;
  final String? phone;
  final String? city;
  final String? district;
  final String? khoroo;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? openTime;
  final String? closeTime;
  final int? slotMinutes;
  final int? slotCapacity;
  final bool isPrimary;
  final bool isActive;
  final List<BranchTag> tags;
  final int employeeCount;
  final List<BranchDaySchedule> schedules;
}

/// The create/edit form's values — the `POST /branches` / `PATCH
/// /branches/[id]` body. Every field is sent (`null` clears it), so the
/// server's whole-record save matches the form exactly.
class BranchDraft {
  const BranchDraft({
    required this.name,
    this.phone = '',
    this.city = '',
    this.district = '',
    this.khoroo = '',
    this.address = '',
    this.latitude,
    this.longitude,
    this.openTime = '09:00',
    this.closeTime = '18:00',
    this.slotMinutes = '',
    this.slotCapacity = '',
    this.isPrimary = false,
    this.tagIds = const [],
    required this.schedules,
  });

  final String name;
  final String phone;
  final String city;
  final String district;
  final String khoroo;
  final String address;
  final double? latitude;
  final double? longitude;
  final String openTime;
  final String closeTime;

  /// Raw text; empty = server default (30 min / 1).
  final String slotMinutes;
  final String slotCapacity;
  final bool isPrimary;
  final List<String> tagIds;
  final List<BranchDaySchedule> schedules;

  static String? _orNull(String v) => v.trim().isEmpty ? null : v.trim();

  Map<String, Object?> toJson() => {
    'name': name.trim(),
    'phone': _orNull(phone),
    'city': _orNull(city),
    'district': _orNull(district),
    'khoroo': _orNull(khoroo),
    'address': _orNull(address),
    'latitude': latitude,
    'longitude': longitude,
    'openTime': _orNull(openTime),
    'closeTime': _orNull(closeTime),
    'slotMinutes': _orNull(slotMinutes),
    'slotCapacity': _orNull(slotCapacity),
    'isPrimary': isPrimary,
    'tagIds': tagIds,
    'schedules': [for (final s in schedules) s.toJson()],
  };
}

/// Pin address from `GET /api/v1/auth/signup/address` (reverse geocode).
class BranchPinAddress {
  const BranchPinAddress({this.city = '', this.district = '', this.khoroo = '', this.address = ''});

  factory BranchPinAddress.fromJson(Object? json) {
    final j = json is Map ? json : const {};
    return BranchPinAddress(
      city: j['city']?.toString() ?? '',
      district: j['district']?.toString() ?? '',
      khoroo: j['khoroo']?.toString() ?? '',
      address: j['address']?.toString() ?? '',
    );
  }

  final String city;
  final String district;
  final String khoroo;
  final String address;
}

/// `409 SCHEDULE_IMPACT` from `PATCH /branches/[id]`: the new hours affect
/// upcoming bookings. [needsConfirm] = only shortened (resend with
/// `confirm: true`); otherwise some bookings would be erased and the save is
/// refused until staff resolve them.
class BranchScheduleImpactError extends AppError {
  const BranchScheduleImpactError(
    super.kind,
    super.message, {
    required this.needsConfirm,
    this.clippedCount = 0,
    this.erasedCount = 0,
    super.statusCode,
    super.code,
  });

  static const errorCode = 'SCHEDULE_IMPACT';

  final bool needsConfirm;
  final int clippedCount;
  final int erasedCount;
}

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

double? _num(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s),
  _ => null,
};
