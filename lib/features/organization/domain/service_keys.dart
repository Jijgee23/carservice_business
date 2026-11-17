/// «Үзүүлдэг үйлчилгээ» — `GET/PUT /api/v1/tenant/service-keys`.
///
/// Системийн үйлчилгээний төрлүүдээс (Тос солих, Дугуй засвар, …) байгууллага
/// үзүүлдгээ сонгоно; жолооч нар /book болон газрын зураг дээр ажлаараа
/// хайхад эдгээрээр гарна. Эзэн баталгаажуулаагүй (`confirmed=false`) бол апп
/// сонголтыг заавал хийлгэнэ (вэбийн хааж болохгүй dialog-тэй адил).
library;

class ServiceKeyChoice {
  const ServiceKeyChoice({
    required this.id,
    required this.name,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
}

class TenantServiceKeys {
  const TenantServiceKeys({
    this.keys = const [],
    this.selectedIds = const {},
    this.confirmed = false,
    this.canEdit = false,
  });

  factory TenantServiceKeys.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Хариу буруу байна');
    final keys = <ServiceKeyChoice>[];
    final list = raw['keys'];
    if (list is List) {
      for (final it in list) {
        if (it is! Map) continue;
        final id = it['id'];
        final name = it['name'];
        if (id is! String || id.isEmpty || name is! String) continue;
        final description = it['description'];
        keys.add(
          ServiceKeyChoice(
            id: id,
            name: name,
            description: description is String && description.trim().isNotEmpty
                ? description.trim()
                : null,
          ),
        );
      }
    }
    final selected = raw['selectedIds'];
    return TenantServiceKeys(
      keys: List.unmodifiable(keys),
      selectedIds: {
        if (selected is List) ...selected.whereType<String>(),
      },
      confirmed: raw['confirmed'] == true,
      canEdit: raw['canEdit'] == true,
    );
  }

  /// Бүх идэвхтэй төрөл (нэрээр эрэмбэлэгдсэн).
  final List<ServiceKeyChoice> keys;
  final Set<String> selectedIds;
  final bool confirmed;

  /// Эзэн — сонголтыг өөрчилж болно.
  final bool canEdit;
}
