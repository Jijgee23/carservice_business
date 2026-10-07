import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';

/// The applied `assigned`/`postpaid` pair — `null` means that filter is off.
class VehicleFilterResult {
  const VehicleFilterResult({this.assigned, this.postpaid, this.ownerKind});

  final bool? assigned;
  final bool? postpaid;
  final VehicleOwnerKind? ownerKind;
}

/// Filter sheet for the Vehicles list — the two boolean server filters the
/// frozen list contract exposes beyond `q`/`customerId`. `customerId` is not
/// offered: it is set programmatically, never typed by a user. Layout
/// follows `AuditFilterSheet`: edits stay local until "Хэрэглэх", and
/// dismissing the sheet leaves the list's filters untouched.
class VehicleFilterSheet extends StatefulWidget {
  const VehicleFilterSheet({
    super.key,
    this.assigned,
    this.postpaid,
    this.ownerKind,
  });

  final bool? assigned;
  final bool? postpaid;
  final VehicleOwnerKind? ownerKind;

  static Future<VehicleFilterResult?> show(
    BuildContext context, {
    bool? assigned,
    bool? postpaid,
    VehicleOwnerKind? ownerKind,
  }) {
    return AppNav.sheet<VehicleFilterResult>(
      VehicleFilterSheet(
        assigned: assigned,
        postpaid: postpaid,
        ownerKind: ownerKind,
      ),
      backgroundColor: Colors.transparent,
    );
  }

  @override
  State<VehicleFilterSheet> createState() => _VehicleFilterSheetState();
}

class _VehicleFilterSheetState extends State<VehicleFilterSheet> {
  bool? _assigned;
  bool? _postpaid;
  VehicleOwnerKind? _ownerKind;

  @override
  void initState() {
    super.initState();
    _assigned = widget.assigned;
    _postpaid = widget.postpaid;
    _ownerKind = widget.ownerKind;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Шүүлтүүр', style: context.textStyles.bodyMedium),
                  TextButton(
                    onPressed: () => setState(() {
                      _assigned = null;
                      _postpaid = null;
                      _ownerKind = null;
                    }),
                    child: const Text('Цэвэрлэх'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Эзэмшигч', style: context.textStyles.captionMedium),
                      const SizedBox(height: 8),
                      _TriChoice(
                        value: _assigned,
                        trueLabel: 'Эзэнтэй',
                        falseLabel: 'Эзэнгүй',
                        onChanged: (v) => setState(() => _assigned = v),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Эзэмшигчийн төрөл',
                        style: context.textStyles.captionMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, option) in [
                            ('Бүгд', null),
                            ('Байгууллага', VehicleOwnerKind.org),
                            ('Хувь хүн', VehicleOwnerKind.person),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _ownerKind == option,
                              onSelected: (_) =>
                                  setState(() => _ownerKind = option),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Төлбөр', style: context.textStyles.captionMedium),
                      const SizedBox(height: 8),
                      _TriChoice(
                        value: _postpaid,
                        trueLabel: 'Дараа төлбөрт',
                        falseLabel: 'Дараа төлбөрт биш',
                        onChanged: (v) => setState(() => _postpaid = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => AppNav.back(
                    VehicleFilterResult(
                      assigned: _assigned,
                      postpaid: _postpaid,
                      ownerKind: _ownerKind,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: CarserviceTheme.of(context).onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    ),
                  ),
                  child: const Text('Хэрэглэх'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// All / true / false for one boolean server filter.
class _TriChoice extends StatelessWidget {
  const _TriChoice({
    required this.value,
    required this.trueLabel,
    required this.falseLabel,
    required this.onChanged,
  });

  final bool? value;
  final String trueLabel;
  final String falseLabel;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (label, option) in [
        ('Бүгд', null),
        (trueLabel, true),
        (falseLabel, false),
      ])
        ChoiceChip(
          label: Text(label),
          selected: value == option,
          onSelected: (_) => onChanged(option),
        ),
    ],
  );
}
