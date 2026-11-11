import 'package:carservice_business/features/diagnostics/domain/diagnostic.dart'
    as typed;
import 'package:carservice_business/features/diagnostics/domain/diagnostics_repository.dart';
import 'package:carservice_business/features/diagnostics/data/diagnostics_data_source.dart';
import 'package:carservice_business/features/diagnostics/data/diagnostics_repository.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class NewInspectionController extends ChangeNotifier {
  NewInspectionController({
    DiagnosticTemplateRepository? repo,
    DiagnosticReportRepository? reportRepo,
  }) : _repo = repo ?? DiagnosticsRepositoryImpl(RemoteDiagnosticsDataSource()),
       _reportRepo =
           reportRepo ??
           (repo is DiagnosticReportRepository
               ? repo as DiagnosticReportRepository
               : DiagnosticsRepositoryImpl(RemoteDiagnosticsDataSource()));

  final DiagnosticTemplateRepository _repo;
  final DiagnosticReportRepository _reportRepo;

  // Templates
  List<DiagnosticTemplateSummary> _templates = [];
  bool _loadingTemplates = false;

  // Selected template (with full schema)
  DiagnosticTemplateDetail? _template;
  bool _loadingTemplate = false;

  // Linked order (optional — set when creating inspection from order detail)
  String? _orderId;
  String? _itemId;

  // Vehicle & Customer
  VehicleSummary? _vehicle;
  CustomerSummary? _customer;

  // Checklist navigation
  int _currentSection = 0;

  // Form values
  int _mileage = 0;
  String _generalNote = '';

  // Answers: { itemId: value }
  final Map<String, String> _answers = {};
  // Notes per item: { itemId: note }
  final Map<String, String> _notes = {};
  // Photo file paths per item: { itemId: [path, ...] }
  final Map<String, List<String>> _photos = {};

  // Submission state
  bool _submitting = false;

  // ─── Getters ───────────────────────────────────────────────────────────────

  List<DiagnosticTemplateSummary> get templates => _templates;
  bool get loadingTemplates => _loadingTemplates;
  DiagnosticTemplateDetail? get template => _template;
  bool get loadingTemplate => _loadingTemplate;
  VehicleSummary? get vehicle => _vehicle;
  CustomerSummary? get customer => _customer;
  String? get itemId => _itemId;
  int get currentSection => _currentSection;
  int get mileage => _mileage;
  String get generalNote => _generalNote;
  bool get submitting => _submitting;

  List<TemplateSection> get sections => _template?.schema.sections ?? [];
  TemplateSection? get currentSectionData =>
      sections.isNotEmpty ? sections[_currentSection] : null;
  bool get canGoNext => _currentSection < sections.length - 1;
  bool get canGoPrev => _currentSection > 0;

  bool isItemVisible(TemplateItem item) {
    if (item.showWhen == null) return true;
    final dep = _answers[item.showWhen!.itemId];
    return item.showWhen!.values.contains(dep);
  }

  String? getAnswer(String itemId) => _answers[itemId];
  String? getNote(String itemId) => _notes[itemId];
  List<String> getPhotos(String itemId) => _photos[itemId] ?? [];

  int get totalCheckItems => sections.fold(
    0,
    (s, sec) =>
        s +
        sec.items
            .where((i) => i.type == ItemType.check)
            .fold<int>(
              0,
              (sum, i) => sum + (i.positionSet?.positions.length ?? 1),
            ),
  );
  int get answeredDanger => _answers.values.where((v) => v == 'Засах').length;
  int get answeredWarning =>
      _answers.values.where((v) => v == 'Анхаарах').length;
  int get answeredGood => _answers.values.where((v) => v == 'OK').length;

  // ─── Actions ───────────────────────────────────────────────────────────────

  Future<void> loadTemplates() async {
    if (_loadingTemplates || _templates.isNotEmpty) return;
    _loadingTemplates = true;
    notifyListeners();
    final result = await _repo.getTemplates();
    if (result case Ok(:final value)) {
      _templates = value.map(_legacyTemplateSummary).toList();
    }
    _loadingTemplates = false;
    notifyListeners();
  }

  Future<void> selectTemplate(String id) async {
    _loadingTemplate = true;
    _template = null;
    _currentSection = 0;
    _answers.clear();
    _notes.clear();
    notifyListeners();
    final result = await _repo.getTemplate(id);
    if (result case Ok(:final value)) _template = _legacyTemplate(value);
    _loadingTemplate = false;
    notifyListeners();
  }

  void setOrderId(String? id) => _orderId = id;
  bool get fromOrder => _orderId != null;

  /// Links a report to the diagnostic order item. The backend uses this
  /// identifier to enforce item-level completion and preserve the association.
  void setItemId(String? id) => _itemId = id;

  void setVehicle(VehicleSummary v, {CustomerSummary? customer}) {
    _vehicle = v;
    _customer = customer ?? v.customer;
    notifyListeners();
  }

  void setCustomer(CustomerSummary c) {
    _customer = c;
    notifyListeners();
  }

  void setMileage(int v) {
    _mileage = v;
    notifyListeners();
  }

  void setGeneralNote(String v) {
    _generalNote = v;
    notifyListeners();
  }

  void setAnswer(String itemId, String value) {
    _answers[itemId] = value;
    notifyListeners();
  }

  /// Options offered by the "Бүгдийг:" bulk buttons (web `BULK_OPTIONS`, plus
  /// the app's default 'OK' for templates without explicit options).
  static const bulkOptions = ['Хэвийн', 'OK', 'Анхаарах'];

  /// Bulk options actually used by the visible check items in [scope]
  /// (all sections when null), in [bulkOptions] order.
  List<String> bulkOptionsFor([List<TemplateSection>? scope]) {
    final used = <String>{};
    for (final s in scope ?? sections) {
      for (final item in s.items) {
        if (item.type == ItemType.check && isItemVisible(item)) {
          used.addAll(item.effectiveOptions);
        }
      }
    }
    return bulkOptions.where(used.contains).toList();
  }

  /// Sets every visible check item (each position too) in [scope] that
  /// offers [value] to it — overwriting earlier answers, like the web.
  void markAll(String value, [List<TemplateSection>? scope]) {
    for (final s in scope ?? sections) {
      for (final item in s.items) {
        if (item.type != ItemType.check || !isItemVisible(item)) continue;
        if (!item.effectiveOptions.contains(value)) continue;
        final positions = item.positionSet?.positions;
        if (positions == null) {
          _answers[item.id] = value;
        } else {
          for (final pos in positions) {
            _answers[positionedKey(item.id, pos.code)] = value;
          }
        }
      }
    }
    notifyListeners();
  }

  void setNote(String itemId, String note) {
    if (note.isEmpty) {
      _notes.remove(itemId);
    } else {
      _notes[itemId] = note;
    }
    notifyListeners();
  }

  void addPhoto(String itemId, String path) {
    _photos.putIfAbsent(itemId, () => []).add(path);
    notifyListeners();
  }

  void removePhoto(String itemId, int index) {
    _photos[itemId]?.removeAt(index);
    notifyListeners();
  }

  void nextSection() {
    if (canGoNext) {
      _currentSection++;
      notifyListeners();
    }
  }

  /// Jumps straight to section [index] (the checklist's section chips).
  void goToSection(int index) {
    if (index < 0 || index >= sections.length || index == _currentSection) {
      return;
    }
    _currentSection = index;
    notifyListeners();
  }

  void prevSection() {
    if (canGoPrev) {
      _currentSection--;
      notifyListeners();
    }
  }

  Future<FormData> _buildFormData(String branchId) async {
    final fields = <MapEntry<String, String>>[];
    final files = <MapEntry<String, MultipartFile>>[];

    fields.add(MapEntry('templateId', _template!.id));
    fields.add(MapEntry('branchId', branchId));
    if (_orderId != null) fields.add(MapEntry('orderId', _orderId!));
    if (_itemId != null) fields.add(MapEntry('itemId', _itemId!));
    if (_vehicle != null) fields.add(MapEntry('vehicleId', _vehicle!.id));
    if (_customer != null) fields.add(MapEntry('customerId', _customer!.id));
    if (_mileage > 0) {
      fields.add(MapEntry('mileageAtReport', _mileage.toString()));
    }
    if (_generalNote.isNotEmpty) fields.add(MapEntry('notes', _generalNote));

    for (final section in sections) {
      for (final item in section.items) {
        if (!isItemVisible(item)) continue;

        final positions = item.positionSet?.positions;
        if (positions != null) {
          for (final pos in positions) {
            final key = positionedKey(item.id, pos.code);
            final val = _answers[key];
            if (val != null && val.isNotEmpty) {
              fields.add(MapEntry('data[$key][value]', val));
            }
            final note = _notes[key];
            if (note != null && note.isNotEmpty) {
              fields.add(MapEntry('data[$key][note]', note));
            }
            final paths = _photos[key];
            if (paths != null) {
              for (final path in paths) {
                files.add(
                  MapEntry('photos[$key]', await MultipartFile.fromFile(path)),
                );
              }
            }
          }
        } else {
          final val = _answers[item.id];
          if (val != null && val.isNotEmpty) {
            fields.add(MapEntry('data[${item.id}][value]', val));
          }
          final note = _notes[item.id];
          if (note != null && note.isNotEmpty) {
            fields.add(MapEntry('data[${item.id}][note]', note));
          }
          final paths = _photos[item.id];
          if (paths != null) {
            for (final path in paths) {
              files.add(
                MapEntry(
                  'photos[${item.id}]',
                  await MultipartFile.fromFile(path),
                ),
              );
            }
          }
        }
      }
    }

    final formData = FormData()..fields.addAll(fields);
    formData.files.addAll(files);
    return formData;
  }

  /// Серверийн validateReportData-тай ижил дүрмээр эхний бөглөөгүй заавал
  /// талбарын нэрийг буцаана (далд item-ыг алгасна).
  String? firstMissingRequired() {
    bool filled(String key) =>
        (_answers[key]?.trim().isNotEmpty ?? false) ||
        (_photos[key]?.isNotEmpty ?? false);
    for (final section in sections) {
      for (final item in section.items) {
        if (!item.required || !isItemVisible(item)) continue;
        final positions = item.positionSet?.positions;
        if (positions != null) {
          for (final pos in positions) {
            if (!filled(positionedKey(item.id, pos.code))) {
              return '${item.label} — ${pos.label}';
            }
          }
        } else if (!filled(item.id)) {
          return item.label;
        }
      }
    }
    return null;
  }

  Future<String?> submit(String branchId) async {
    if (_template == null || _vehicle == null || _customer == null) {
      messageError('Загвар болон машины мэдээлэл шаардлагатай.');
      return null;
    }
    final missing = firstMissingRequired();
    if (missing != null) {
      messageError('"$missing" заавал бөглөх ёстой.');
      return null;
    }
    _submitting = true;
    notifyListeners();
    try {
      final formData = await _buildFormData(branchId);
      final result = await _reportRepo.createReport(formData);
      if (result case Ok(:final value)) {
        messageComplete('Тайлан амжилттай илгээгдлээ!');
        return value;
      }
      if (result case Err(:final error)) messageError(error.display);
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  void reset() {
    _template = null;
    _orderId = null;
    _itemId = null;
    _vehicle = null;
    _customer = null;
    _currentSection = 0;
    _mileage = 0;
    _generalNote = '';
    _answers.clear();
    _notes.clear();
    _photos.clear();
    _submitting = false;
    notifyListeners();
  }
}

// The form still consumes the app's shared legacy presentation models because
// vehicle/customer inline-create remains owned by DiagnosticService. All
// diagnostics API reads and writes above go through the frozen typed contract.
DiagnosticTemplateSummary _legacyTemplateSummary(
  typed.DiagnosticTemplateSummary t,
) => DiagnosticTemplateSummary(
  id: t.id,
  name: t.name,
  description: t.description,
  type: DiagnosticType.values.firstWhere(
    (e) => e.name == t.type.name,
    orElse: () => DiagnosticType.ROUTINE,
  ),
  version: t.version,
  isActive: t.isActive,
  price: t.price,
  durationMin: t.durationMin,
  updatedAt: t.updatedAt ?? DateTime(2000),
);

DiagnosticTemplateDetail _legacyTemplate(typed.DiagnosticTemplateDetail t) =>
    DiagnosticTemplateDetail(
      id: t.id,
      name: t.name,
      description: t.description,
      type: DiagnosticType.values.firstWhere(
        (e) => e.name == t.type.name,
        orElse: () => DiagnosticType.ROUTINE,
      ),
      version: t.version,
      isActive: t.isActive,
      price: t.price,
      durationMin: t.durationMin,
      updatedAt: t.updatedAt ?? DateTime(2000),
      schema: TemplateSchema(
        sections: t.schema.sections
            .map(
              (s) => TemplateSection(
                id: s.id,
                title: s.title,
                items: s.items
                    .map(
                      (i) => TemplateItem(
                        id: i.id,
                        label: i.label,
                        type: ItemType.values.firstWhere(
                          (e) => e.name == i.type.name,
                          orElse: () => ItemType.text,
                        ),
                        required: i.required,
                        options: i.options,
                        showWhen: i.showWhen == null
                            ? null
                            : ShowWhen(
                                itemId: i.showWhen!.itemId,
                                values: i.showWhen!.values,
                              ),
                        positionSet: i.positionSet == null
                            ? null
                            : PositionSetKey.values.firstWhere(
                                (e) => e.name == i.positionSet!.name,
                              ),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
