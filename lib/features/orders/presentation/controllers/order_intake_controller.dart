import 'dart:typed_data';

import 'package:carservice_business/core/utils/price_input.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/orders/domain/order_intake.dart';
import 'package:carservice_business/features/orders/domain/order_settings.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:flutter/widgets.dart';

enum IntakeUploadStatus { uploading, done, failed }

class IntakePhotoItem {
  IntakePhotoItem({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;
  IntakeUploadStatus status = IntakeUploadStatus.uploading;

  /// Сервер дээрх түр зам (upload амжилттай болсны дараа).
  String? url;
}

/// Захиалга үүсгэх дэлгэцийн «Хүлээн авах» хэсгийн төлөв.
/// Зураг бүр сонгогдмогц шууд upload хийгдэнэ; submit нь [uploading] үед
/// хаалттай.
class OrderIntakeController extends ChangeNotifier {
  OrderIntakeController(this._repository) {
    mileageCtrl.addListener(_notify);
  }

  static const maxMileageKm = 2000000;
  static const mileageError = 'Гүйлт 0–2,000,000 км байх ёстой.';
  static const maxPhotos = 20;
  static const maxNotes = 5000;

  final OrdersRepository _repository;
  final notesCtrl = TextEditingController();
  final mileageCtrl = TextEditingController();
  final List<IntakePhotoItem> photos = [];

  /// Tenant-ийн «нээх үеийн шаардлага» + шалгах жагсаалт.
  OrderSettings settings = OrderSettings.defaults;

  /// Шалгах жагсаалтын сонгосон төлөв (мөрийн id → төлөв).
  final Map<String, ChecklistStatus> checklistStatus = {};

  /// «Асуудалтай» мөрийн тэмдэглэл (мөрийн id → controller).
  final Map<String, TextEditingController> checklistNotes = {};

  Uint8List? signatureBytes;
  String? signatureUrl;
  bool signatureUploading = false;
  String? signatureError;
  bool _disposed = false;

  /// Гарын үсгийн талбарт хадгалаагүй зураас байгаа эсэх.
  bool signatureDirty = false;

  void setSignatureDirty(bool value) {
    if (signatureDirty == value) return;
    signatureDirty = value;
    _notify();
  }

  /// Оруулсан гүйлт (км); хоосон эсвэл хүрээнээс гарсан бол `null`.
  int? get mileageKm {
    final km = parseIntegerInput(mileageCtrl.text);
    return km != null && km >= 0 && km <= maxMileageKm ? km : null;
  }

  /// Гүйлт оруулсан боловч буруу (хүрээнээс гарсан) үед алдааны текст.
  String? get mileageErrorText {
    if (mileageCtrl.text.trim().isEmpty) return null;
    return mileageKm == null ? mileageError : null;
  }

  /// Submit-ийг хаах шалтгаан (байхгүй бол `null`). Upload дуусаагүй,
  /// амжилтгүй зураг, хадгалаагүй гарын үсэг гурвыг ялгана.
  String? get blockReason {
    if (mileageErrorText != null) return mileageErrorText;
    if (uploading) return 'Файл хуулж байна...';
    if (hasFailedPhoto) {
      return 'Зураг upload амжилтгүй — дахин оролдох эсвэл устгана уу';
    }
    if (signatureDirty) return 'Гарын үсгээ хадгална уу эсвэл арилгана уу';
    return null;
  }

  /// Серверээс ирсэн тохиргоог хэрэглэнэ; жагсаалтаас хасагдсан мөрийн
  /// хариултыг цэвэрлэнэ.
  void applySettings(OrderSettings value) {
    settings = value;
    final ids = {for (final c in value.intakeChecklist) c.id};
    checklistStatus.removeWhere((id, _) => !ids.contains(id));
    for (final id in checklistNotes.keys.toList()) {
      if (!ids.contains(id)) checklistNotes.remove(id)?.dispose();
    }
    _notify();
  }

  /// Шалгах жагсаалтын мөрийн төлөвийг сонгоно; ижлийг дахин дарвал арилна.
  void setChecklistStatus(String id, ChecklistStatus status) {
    if (checklistStatus[id] == status) {
      checklistStatus.remove(id);
    } else {
      checklistStatus[id] = status;
    }
    _notify();
  }

  TextEditingController checklistNoteCtrl(String id) =>
      checklistNotes.putIfAbsent(id, TextEditingController.new);

  int get checklistAnswered => settings.intakeChecklist
      .where((c) => checklistStatus.containsKey(c.id))
      .length;

  int get donePhotoCount =>
      photos.where((p) => p.status == IntakeUploadStatus.done).length;

  /// Tenant-ийн тохиргоогоор дутуу байгаа зүйл (байхгүй бол `null`) — сервер
  /// мөн адил шалгадаг (MILEAGE_REQUIRED, SIGNATURE_REQUIRED,
  /// INTAKE_PHOTOS_REQUIRED, CHECKLIST_REQUIRED).
  String? get missingRequirement {
    final s = settings;
    if (s.requireMileage && mileageKm == null) {
      return 'Хүлээн авах үеийн гүйлтийг (км) оруулна уу.';
    }
    if (s.minIntakePhotos > 0 && donePhotoCount < s.minIntakePhotos) {
      return 'Хүлээн авалтын зураг хамгийн багадаа ${s.minIntakePhotos} '
          'байна (одоо $donePhotoCount).';
    }
    if (s.requireSignature && signatureUrl == null) {
      return 'Үйлчлүүлэгчийн гарын үсгийг авна уу.';
    }
    if (s.checklistRequired) {
      final left = s.intakeChecklist.length - checklistAnswered;
      if (left > 0) return 'Шалгах жагсаалтын $left мөр бөглөгдөөгүй байна.';
    }
    return null;
  }

  int get remainingPhotoSlots => maxPhotos - photos.length;

  bool get uploading =>
      signatureUploading ||
      photos.any((p) => p.status == IntakeUploadStatus.uploading);

  bool get hasFailedPhoto =>
      photos.any((p) => p.status == IntakeUploadStatus.failed);

  bool get isEmpty => draft == null;

  /// Серверт илгээх ноорог; хоосон бол `null`.
  OrderIntakeDraft? get draft {
    final value = OrderIntakeDraft(
      notes: notesCtrl.text,
      photoPaths: [
        for (final p in photos)
          if (p.status == IntakeUploadStatus.done && p.url != null) p.url!,
      ],
      signaturePath: signatureUrl,
      mileageKm: mileageKm,
      checklist: [
        for (final c in settings.intakeChecklist)
          if (checklistStatus[c.id] case final status?)
            IntakeChecklistAnswer(
              id: c.id,
              status: status,
              // Тэмдэглэл зөвхөн «Асуудалтай» мөрөнд (вэбтэй адил).
              note: status == ChecklistStatus.ISSUE
                  ? checklistNotes[c.id]?.text
                  : null,
            ),
      ],
    );
    return value.isEmpty ? null : value;
  }

  /// Сонгосон зургуудыг (cap 20 хүртэл) нэмж, тус бүрийг upload хийнэ.
  /// Cap-аас хэтэрсэн тоог буцаана.
  Future<int> addPhotos(
    List<({String filename, Uint8List bytes})> files,
  ) async {
    final accepted = files.take(remainingPhotoSlots).toList();
    final dropped = files.length - accepted.length;
    final items = [
      for (final f in accepted)
        IntakePhotoItem(filename: f.filename, bytes: f.bytes),
    ];
    photos.addAll(items);
    _notify();
    await Future.wait(items.map(_upload));
    return dropped;
  }

  Future<void> retryPhoto(IntakePhotoItem item) async {
    item.status = IntakeUploadStatus.uploading;
    _notify();
    await _upload(item);
  }

  Future<void> _upload(IntakePhotoItem item) async {
    final result = await _repository.uploadIntakeFile(
      item.bytes,
      item.filename,
      signature: false,
    );
    if (!photos.contains(item)) return; // upload дундуур устгагдсан
    switch (result) {
      case Ok(:final value):
        item.url = value;
        item.status = IntakeUploadStatus.done;
      case Err():
        item.status = IntakeUploadStatus.failed;
    }
    _notify();
  }

  void removePhoto(IntakePhotoItem item) {
    photos.remove(item);
    _notify();
  }

  /// Гарын үсгийн PNG-г upload хийж хадгална.
  Future<bool> saveSignature(Uint8List png) async {
    signatureUploading = true;
    signatureError = null;
    _notify();
    final result = await _repository.uploadIntakeFile(
      png,
      'signature.png',
      signature: true,
    );
    signatureUploading = false;
    switch (result) {
      case Ok(:final value):
        signatureBytes = png;
        signatureUrl = value;
        signatureDirty = false;
        _notify();
        return true;
      case Err(:final error):
        signatureError = error.display;
        _notify();
        return false;
    }
  }

  void clearSignature() {
    signatureBytes = null;
    signatureUrl = null;
    signatureError = null;
    signatureDirty = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    notesCtrl.dispose();
    mileageCtrl.dispose();
    for (final c in checklistNotes.values) {
      c.dispose();
    }
    super.dispose();
  }
}
