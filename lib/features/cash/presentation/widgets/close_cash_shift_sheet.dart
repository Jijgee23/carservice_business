import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/money_format.dart';
import 'package:carservice_business/core/utils/price_input.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/features/cash/data/cash_shift_repository.dart';
import 'package:carservice_business/features/cash/domain/cash_shift.dart';
import 'package:carservice_business/features/cash/domain/cash_shift_repository.dart';
import 'package:carservice_business/features/cash/presentation/widgets/cash_shift_widgets.dart';

/// «Ээлж хаах» — `POST /cash/sessions/[id]/close {countedCash, note?}`.
///
/// Shows the expected drawer cash (live, from the shift it was opened
/// with), the counted amount and the difference as it is typed. The server
/// recomputes expected cash under its lock, so the stored difference is the
/// authoritative one — the returned closed shift carries it. Non-cash
/// method rows are shown for reference; their per-method counts are left
/// to the web (optional on the API).
class CloseCashShiftSheet extends StatefulWidget {
  const CloseCashShiftSheet({super.key, required this.shift, this.repo});

  final CashShift shift;
  final CashShiftRepository? repo;

  static Future<CashShift?> show(
    BuildContext context, {
    required CashShift shift,
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
    builder: (_) => CloseCashShiftSheet(shift: shift, repo: repo),
  );

  @override
  State<CloseCashShiftSheet> createState() => _CloseCashShiftSheetState();
}

class _CloseCashShiftSheetState extends State<CloseCashShiftSheet> {
  late final CashShiftRepository _repo =
      widget.repo ?? RemoteCashShiftRepository();
  final _counted = TextEditingController();
  final _note = TextEditingController();
  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  String? get _expected => widget.shift.expectedCash ?? widget.shift.openingCash;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final counted = parsePriceInput(_counted.text);
    if (counted == null || counted < 0) {
      setState(() {
        _fieldErrors = const {'countedCash': 'Тоолсон дүнг оруулна уу.'};
        _error = null;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _fieldErrors = const {};
    });
    final result = await _repo.closeShift(
      widget.shift.id,
      countedCash: _counted.text.replaceAll(',', '').trim(),
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
    final s = widget.shift;
    final diff = cashDifference(_counted.text, _expected);
    final others = s.byMethod.where((m) => m.method != 'CASH').toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: const ValueKey('close_cash_shift_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShiftSheetHeader(
              title: 'Ээлж хаах',
              subtitle:
                  '${s.branch.name} · ${formatShiftDateTime(s.openedAt)}-с',
            ),
            ShiftFigure(
              label: 'Эхний үлдэгдэл',
              value: formatMoney(s.openingCash),
            ),
            if (s.cashIn != null)
              ShiftFigure(label: 'Бэлэн орлого', value: formatMoney(s.cashIn)),
            if (s.cashOut != null)
              ShiftFigure(
                label: 'Бэлэн зарлага',
                value: formatMoney(s.cashOut),
              ),
            ShiftFigure(
              key: const ValueKey('close_shift_expected'),
              label: 'Кассанд байх ёстой',
              value: formatMoney(_expected),
              bold: true,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('close_shift_counted'),
              controller: _counted,
              enabled: !_submitting,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [PriceInputFormatter()],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Тоолсон бэлэн мөнгө (₮)',
                errorText: _fieldErrors['countedCash'],
              ),
            ),
            const SizedBox(height: 8),
            ShiftFigure(
              key: const ValueKey('close_shift_difference'),
              label: 'Зөрүү',
              value: diff == null ? '—' : formatSignedMoney(diff),
              valueColor: diff == null
                  ? null
                  : differenceColor(context, diff),
              bold: true,
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 12),
              const OpsSectionLabel('Бусад төлбөр (лавлах)'),
              const SizedBox(height: 4),
              for (final m in others)
                ShiftFigure(
                  label: [
                    cashMethodLabel(m.method),
                    ?m.bankLabel,
                  ].join(' · '),
                  value: formatMoney(m.net),
                ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('close_shift_note'),
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
                !_fieldErrors.containsKey('countedCash') &&
                !_fieldErrors.containsKey('note'))
              ShiftErrorText(_error!),
            const SizedBox(height: 16),
            OpsPrimaryButton(
              key: const ValueKey('close_shift_submit'),
              label: 'Ээлж хаах',
              icon: Icons.lock_outline_rounded,
              dark: true,
              loading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
