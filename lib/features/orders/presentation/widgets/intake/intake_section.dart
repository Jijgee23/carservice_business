import 'dart:typed_data';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/price_input.dart';
import 'package:carservice_business/core/utils/upload_image.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/orders/domain/order_settings.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_intake_controller.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/intake/signature_pad.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// «Хүлээн авах» — захиалга үүсгэхэд л харагдах нээгддэг хэсэг: гүйлт,
/// шалгах жагсаалт, тэмдэглэл, зураг (дээд тал нь 20), гарын үсэг. Захиалга
/// үүссэний дараа засагдахгүй. Tenant-ийн тохиргоогоор заавал бөглөх зүйл
/// байвал анхнаасаа нээлттэй, тэдгээр нь «*»-тэй.
class IntakeSection extends StatefulWidget {
  const IntakeSection({super.key, required this.controller, this.picker});

  final OrderIntakeController controller;
  final ImagePicker? picker;

  @override
  State<IntakeSection> createState() => _IntakeSectionState();
}

class _IntakeSectionState extends State<IntakeSection> {
  /// Хэрэглэгч өөрөө нээж/хаасан эсэх; хэзээ ч дараагүй бол заавал бөглөх
  /// зүйл байгаа эсэхээр нээгдэнэ.
  bool? _userExpanded;
  bool get _expanded => _userExpanded ?? _c.settings.hasIntakeRequirements;
  bool _signing = false;
  final List<List<Offset>> _strokes = [];
  final _padKey = GlobalKey<SignaturePadState>();

  OrderIntakeController get _c => widget.controller;
  ImagePicker get _picker => widget.picker ?? ImagePicker();

  Future<void> _addFromGallery() async {
    final left = _c.remainingPhotoSlots;
    if (left <= 0) return;
    final picked = await _picker.pickMultiImage(
      imageQuality: uploadImageQuality,
      maxWidth: uploadIntakeMaxDimension,
      maxHeight: uploadIntakeMaxDimension,
      limit: left < 2 ? null : left,
    );
    await _handle(picked);
  }

  Future<void> _addFromCamera() async {
    if (_c.remainingPhotoSlots <= 0) return;
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: uploadImageQuality,
      maxWidth: uploadIntakeMaxDimension,
      maxHeight: uploadIntakeMaxDimension,
    );
    await _handle(shot == null ? const [] : [shot]);
  }

  Future<void> _handle(List<XFile> picked) async {
    if (picked.isEmpty) return;
    final List<({String filename, Uint8List bytes})> files;
    try {
      final filtered = await filterUploadable(picked);
      if (filtered.rejected > 0) messageError(uploadTooLargeMessage);
      files = [
        for (final x in filtered.accepted)
          (filename: x.name, bytes: await x.readAsBytes()),
      ];
    } catch (_) {
      messageError('Зураг уншиж чадсангүй');
      return;
    }
    if (files.isEmpty) return;
    final dropped = await _c.addPhotos(files);
    if (dropped > 0) {
      messageError('Дээд тал нь ${OrderIntakeController.maxPhotos} зураг.');
    }
  }

  Future<void> _saveSignature() async {
    final size = _padKey.currentState?.size ?? Size.zero;
    if (size.isEmpty) return;
    final png = await exportSignaturePng(_strokes, size);
    if (png == null) return;
    final ok = await _c.saveSignature(png);
    if (ok && mounted) {
      setState(() {
        _signing = false;
        _strokes.clear();
      });
    } else if (_c.signatureError != null) {
      messageError(_c.signatureError!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final settings = _c.settings;
        final filled = !_c.isEmpty && _c.missingRequirement == null;
        final reason = _c.blockReason;
        final missing = reason == null ? _c.missingRequirement : null;
        final box = Container(
          decoration: BoxDecoration(
            color: context.opsSurface,
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            border: Border.all(color: context.opsDivider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: const ValueKey('intake_toggle'),
                borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                onTap: () => setState(() => _userExpanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 20,
                        color: context.opsTextSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          settings.hasIntakeRequirements
                              ? 'Хүлээн авах *'
                              : 'Хүлээн авах',
                          style: context.textStyles.body.copyWith(
                            color: context.opsTextPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (filled)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.check_circle,
                            size: 18,
                            color: context.opsGood,
                          ),
                        ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: context.opsTextHint,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 180,
                        child: TextField(
                          key: const ValueKey('intake_mileage'),
                          controller: _c.mileageCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [IntegerInputFormatter()],
                          decoration: InputDecoration(
                            labelText: settings.requireMileage
                                ? 'Гүйлт (км) *'
                                : 'Гүйлт (км)',
                            errorText: _c.mileageErrorText,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (settings.intakeChecklist.isNotEmpty) ...[
                        _checklist(context, settings),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        key: const ValueKey('intake_notes'),
                        controller: _c.notesCtrl,
                        minLines: 3,
                        maxLines: 8,
                        maxLength: OrderIntakeController.maxNotes,
                        decoration: const InputDecoration(
                          labelText: 'Хүлээн авалтын тэмдэглэл',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _photos(context),
                      const SizedBox(height: 16),
                      _signature(context),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            box,
            if (reason != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  reason,
                  key: const ValueKey('intake_block_reason'),
                  style: context.textStyles.caption.copyWith(
                    color: context.opsDanger,
                  ),
                ),
              )
            else if (missing != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  missing,
                  key: const ValueKey('intake_missing_requirement'),
                  style: context.textStyles.caption.copyWith(
                    color: context.opsWarning,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _checklist(BuildContext context, OrderSettings settings) {
    final items = settings.intakeChecklist;
    return Column(
      key: const ValueKey('intake_checklist'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Шалгах жагсаалт${settings.checklistRequired ? ' *' : ''}'
          '  ${_c.checklistAnswered}/${items.length}',
          style: context.textStyles.caption,
        ),
        const SizedBox(height: 6),
        for (final item in items) _checklistRow(context, item),
      ],
    );
  }

  Widget _checklistRow(BuildContext context, ChecklistItemDef item) {
    final current = _c.checklistStatus[item.id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label, style: context.textStyles.body),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final status in ChecklistStatus.values)
                ChoiceChip(
                  key: ValueKey('intake_check_${item.id}_${status.name}'),
                  label: Text(status.label),
                  selected: current == status,
                  selectedColor: switch (status) {
                    ChecklistStatus.OK => context.opsGood,
                    ChecklistStatus.ISSUE => context.opsDanger,
                    ChecklistStatus.NA => context.opsTextHint,
                  }.withValues(alpha: 0.18),
                  onSelected: (_) => _c.setChecklistStatus(item.id, status),
                ),
            ],
          ),
          if (current == ChecklistStatus.ISSUE) ...[
            const SizedBox(height: 6),
            TextField(
              key: ValueKey('intake_check_note_${item.id}'),
              controller: _c.checklistNoteCtrl(item.id),
              maxLength: checklistNoteMax,
              decoration: const InputDecoration(
                hintText: 'Тэмдэглэл',
                isDense: true,
                counterText: '',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _photos(BuildContext context) {
    final full = _c.remainingPhotoSlots <= 0;
    final min = _c.settings.minIntakePhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Зураг (${_c.photos.length}/${OrderIntakeController.maxPhotos})'
          '${min > 0 ? ' * — хамгийн багадаа $min' : ''}',
          style: context.textStyles.caption,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _c.photos) _PhotoTile(item: p, controller: _c),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              key: const ValueKey('intake_add_camera'),
              onPressed: full ? null : _addFromCamera,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Камер'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const ValueKey('intake_add_gallery'),
              onPressed: full ? null : _addFromGallery,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Галерей'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _signature(BuildContext context) {
    final bytes = _c.signatureBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _c.settings.requireSignature
              ? 'Хэрэглэгчийн гарын үсэг *'
              : 'Хэрэглэгчийн гарын үсэг',
          style: context.textStyles.caption,
        ),
        const SizedBox(height: 8),
        if (bytes != null)
          Stack(
            children: [
              Container(
                key: const ValueKey('intake_signature_preview'),
                height: 120,
                width: double.infinity,
                color: Colors.white,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: _RemoveButton(onTap: _c.clearSignature),
              ),
            ],
          )
        else if (_signing) ...[
          SignaturePad(
            key: _padKey,
            strokes: _strokes,
            onChanged: () => _c.setSignatureDirty(_strokes.isNotEmpty),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                key: const ValueKey('intake_signature_clear'),
                onPressed: () {
                  setState(_strokes.clear);
                  _c.setSignatureDirty(false);
                },
                child: const Text('Арилгах'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('intake_signature_save'),
                onPressed: _c.signatureUploading ? null : _saveSignature,
                child: _c.signatureUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Хадгалах'),
              ),
            ],
          ),
        ] else
          OutlinedButton.icon(
            key: const ValueKey('intake_signature_start'),
            onPressed: () => setState(() => _signing = true),
            icon: const Icon(Icons.draw_outlined, size: 18),
            label: const Text('Гарын үсэг зурах'),
          ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.item, required this.controller});

  final IntakePhotoItem item;
  final OrderIntakeController controller;

  @override
  Widget build(BuildContext context) {
    final failed = item.status == IntakeUploadStatus.failed;
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusSM),
            child: Image.memory(
              item.bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.grey),
            ),
          ),
          if (item.status == IntakeUploadStatus.uploading)
            const ColoredBox(
              color: Colors.black38,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (failed)
            InkWell(
              onTap: () => controller.retryPhoto(item),
              child: ColoredBox(
                color: Colors.black54,
                child: Column(
                  key: const ValueKey('intake_photo_failed'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.refresh, color: Colors.white),
                    const SizedBox(height: 2),
                    Text(
                      'Алдаа',
                      style: TextStyle(
                        color: context.opsDanger,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: _RemoveButton(onTap: () => controller.removePhoto(item)),
          ),
        ],
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: const CircleAvatar(
        radius: 11,
        backgroundColor: Colors.black54,
        child: Icon(Icons.close, size: 14, color: Colors.white),
      ),
    );
  }
}
