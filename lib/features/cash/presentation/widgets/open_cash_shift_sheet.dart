import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/price_input.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/features/cash/data/cash_shift_repository.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';
import 'package:carservice_business/features/cash/domain/cash_shift_repository.dart';
import 'package:carservice_business/features/cash/presentation/widgets/cash_shift_widgets.dart';
import 'package:carservice_business/features/shell/domain/working_branch.dart';

/// «Ээлж нээх» — `POST /cash/sessions {branchId, openingCash, note?}`.
///
/// [branchId] fixes the branch (an order's branch, a pinned working branch);
/// without it the user picks one of [branches]. Resolves to the opened shift,
/// or null when dismissed.
class OpenCashShiftSheet extends StatefulWidget {
  const OpenCashShiftSheet({
    super.key,
    this.branchId,
    this.branchName,
    this.branches = const [],
    this.repo,
  });

  final String? branchId;
  final String? branchName;
  final List<SwitchableBranch> branches;
  final CashShiftRepository? repo;

  static Future<CashShift?> show(
    BuildContext context, {
    String? branchId,
    String? branchName,
    List<SwitchableBranch> branches = const [],
    CashShiftRepository? repo,
  }) => showModalBottomSheet<CashShift>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppDimens.radiusXL),
      ),
    ),
    builder: (_) => OpenCashShiftSheet(
      branchId: branchId,
      branchName: branchName,
      branches: branches,
      repo: repo,
    ),
  );

  @override
  State<OpenCashShiftSheet> createState() => _OpenCashShiftSheetState();
}

class _OpenCashShiftSheetState extends State<OpenCashShiftSheet> {
  late final CashShiftRepository _repo =
      widget.repo ?? RemoteCashShiftRepository();
  final _amount = TextEditingController(text: '0');
  final _note = TextEditingController();
  String? _branchId;
  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    _branchId =
        widget.branchId ??
        (widget.branches.length == 1 ? widget.branches.first.id : null);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final branch = _branchId;
    final amount = parsePriceInput(_amount.text);
    final local = <String, String>{
      if (branch == null) 'branchId': 'Салбар сонгоно уу.',
      if (amount == null || amount < 0) 'openingCash': 'Дүнг зөв оруулна уу.',
    };
    if (local.isNotEmpty) {
      setState(() {
        _fieldErrors = local;
        _error = null;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _fieldErrors = const {};
    });
    final result = await _repo.openShift(
      branchId: branch!,
      openingCash: _amount.text.replaceAll(',', '').trim(),
      note: _note.text,
    );
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final error):
        setState(() {
          _submitting = false;
          _fieldErrors = error.fieldErrors ?? const {};
          _error = error.display;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixedName =
        widget.branchName ??
        (widget.branchId == null
            ? null
            : widget.branches
                  .where((b) => b.id == widget.branchId)
                  .map((b) => b.name)
                  .firstOrNull);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: const ValueKey('open_cash_shift_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShiftSheetHeader(
              title: 'Ээлж нээх',
              subtitle: widget.branchId != null
                  ? (fixedName ?? 'Энэ салбарын касс')
                  : 'Кассанд байгаа бэлэн мөнгийг оруулна уу',
            ),
            if (widget.branchId == null) ...[
              DropdownButtonFormField<String>(
                key: const ValueKey('open_shift_branch'),
                initialValue: _branchId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Салбар',
                  errorText: _fieldErrors['branchId'],
                ),
                items: [
                  for (final b in widget.branches)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _branchId = v),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('open_shift_amount'),
              controller: _amount,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [PriceInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Эхний үлдэгдэл (₮)',
                helperText: 'Кассанд байгаа бэлэн мөнгө',
                errorText: _fieldErrors['openingCash'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('open_shift_note'),
              controller: _note,
              enabled: !_submitting,
              maxLines: 2,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'Тэмдэглэл (заавал биш)',
                errorText: _fieldErrors['note'],
              ),
            ),
            if (_error != null &&
                !_fieldErrors.keys.any(
                  (k) =>
                      k == 'openingCash' ||
                      k == 'note' ||
                      (k == 'branchId' && widget.branchId == null),
                ))
              ShiftErrorText(_error!),
            const SizedBox(height: 16),
            OpsPrimaryButton(
              key: const ValueKey('open_shift_submit'),
              label: 'Ээлж нээх',
              icon: Icons.lock_open_rounded,
              loading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
