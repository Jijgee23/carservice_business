import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/assignee_picker_field.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';

/// Bottom sheet that asks for a master and returns the choice (or `null` when
/// dismissed). Used before confirming a master-less appointment and for
/// changing the master. There is deliberately no "clear" action: the server
/// refuses clearing (422 `ASSIGNEE_REQUIRED`).
abstract final class AssigneeSheet {
  static Future<AssignableUser?> show(
    BuildContext context, {
    required Future<Result<List<AssignableUser>>> Function() loadUsers,
    required String title,
    required String confirmLabel,
    String? message,
    String? preselectId,
  }) {
    return showModalBottomSheet<AssignableUser>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.opsCardBg,
      builder: (_) => _AssigneeSheetBody(
        loadUsers: loadUsers,
        title: title,
        confirmLabel: confirmLabel,
        message: message,
        preselectId: preselectId,
      ),
    );
  }
}

class _AssigneeSheetBody extends StatefulWidget {
  const _AssigneeSheetBody({
    required this.loadUsers,
    required this.title,
    required this.confirmLabel,
    this.message,
    this.preselectId,
  });

  final Future<Result<List<AssignableUser>>> Function() loadUsers;
  final String title;
  final String confirmLabel;
  final String? message;
  final String? preselectId;

  @override
  State<_AssigneeSheetBody> createState() => _AssigneeSheetBodyState();
}

class _AssigneeSheetBodyState extends State<_AssigneeSheetBody> {
  List<AssignableUser> _users = [];
  bool _loading = true;
  String? _error;
  AssignableUser? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.loadUsers();
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _users = value;
          for (final u in value) {
            if (u.id == widget.preselectId) _selected = u;
          }
        case Err(:final error):
          _users = [];
          _error = error.display;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimens.paddingMD,
        0,
        AppDimens.paddingMD,
        AppDimens.paddingMD + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: context.textStyles.h3),
          if (widget.message != null) ...[
            const SizedBox(height: AppDimens.paddingXS),
            Text(widget.message!, style: context.textStyles.caption),
          ],
          const SizedBox(height: AppDimens.paddingMD),
          AssigneePickerField(
            pickerKey: const ValueKey('appointment_assignee_sheet_picker'),
            users: _users,
            selected: _selected,
            loading: _loading,
            error: _error,
            onChanged: (u) => setState(() => _selected = u),
            onRetry: _load,
          ),
          const SizedBox(height: AppDimens.paddingMD),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Болих'),
                ),
              ),
              const SizedBox(width: AppDimens.paddingSM),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('appointment_assignee_sheet_confirm'),
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                  child: Text(widget.confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
