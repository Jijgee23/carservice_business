import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/branch.dart';
import 'package:carservice_business/core/services/branch_service.dart';
import 'package:carservice_business/core/widgets/filter_pill.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Open/closed split of [AppointmentStatus] for the filter sheet. Closed is
/// exactly [AppointmentStatus.isTerminal]; open is what can still move.
enum AppointmentStatusGroup {
  open('Нээлттэй', {AppointmentStatus.PENDING, AppointmentStatus.CONFIRMED}),
  closed('Хаагдсан', {
    AppointmentStatus.REJECTED,
    AppointmentStatus.NO_SHOW,
    AppointmentStatus.CANCELLED,
  });

  const AppointmentStatusGroup(this.label, this.statuses);
  final String label;
  final Set<AppointmentStatus> statuses;

  /// The group whose statuses are exactly [statuses], if any.
  static AppointmentStatusGroup? of(Set<AppointmentStatus>? statuses) {
    if (statuses == null) return null;
    for (final group in values) {
      if (group.statuses.length == statuses.length &&
          group.statuses.containsAll(statuses)) {
        return group;
      }
    }
    return null;
  }
}

/// What the appointments filter sheet edits. [status] narrows [group]: the
/// sheet only offers statuses that belong to the chosen group.
@immutable
class AppointmentFilter {
  const AppointmentFilter({this.branchId, this.group, this.status});

  final String? branchId;
  final AppointmentStatusGroup? group;
  final AppointmentStatus? status;

  int get activeCount =>
      [branchId, group, status].where((value) => value != null).length;
}

/// Branch/open-closed/status filter sheet for the appointments list.
/// [showBranches] is the caller's call (owner, working branch set to "all");
/// even then the branch section only appears once 2+ branches have loaded.
Future<AppointmentFilter?> showAppointmentFilterSheet(
  BuildContext context,
  AppointmentFilter current, {
  bool showBranches = false,
}) {
  return AppNav.sheet<AppointmentFilter>(
    _AppointmentFilterSheet(current: current, showBranches: showBranches),
    backgroundColor: Colors.transparent,
  );
}

class _AppointmentFilterSheet extends StatefulWidget {
  const _AppointmentFilterSheet({
    required this.current,
    required this.showBranches,
  });

  final AppointmentFilter current;
  final bool showBranches;

  @override
  State<_AppointmentFilterSheet> createState() =>
      _AppointmentFilterSheetState();
}

class _AppointmentFilterSheetState extends State<_AppointmentFilterSheet> {
  // Same order the old inline status row used.
  static const _statusOrder = [
    AppointmentStatus.PENDING,
    AppointmentStatus.CONFIRMED,
    AppointmentStatus.REJECTED,
    AppointmentStatus.NO_SHOW,
    AppointmentStatus.CANCELLED,
  ];

  late String? _branchId = widget.current.branchId;
  late AppointmentStatusGroup? _group = widget.current.group;
  late AppointmentStatus? _status = widget.current.status;
  List<Branch> _branches = const [];

  @override
  void initState() {
    super.initState();
    if (widget.showBranches) _loadBranches();
  }

  Future<void> _loadBranches() async {
    final branches = await BranchService.instance.getBranches();
    if (mounted) setState(() => _branches = branches);
  }

  AppointmentFilter get _built =>
      AppointmentFilter(branchId: _branchId, group: _group, status: _status);

  void _setGroup(AppointmentStatusGroup? group) => setState(() {
    _group = group;
    // Keep the status only while it still belongs to the chosen group.
    if (group != null && !group.statuses.contains(_status)) _status = null;
  });

  void _reset() => setState(() {
    _branchId = null;
    _group = null;
    _status = null;
  });

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final statuses = [
      for (final status in _statusOrder)
        if (group == null || group.statuses.contains(status)) status,
    ];
    final activeCount = _built.activeCount;

    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXL)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.opsDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Text('Шүүлтүүр', style: context.textStyles.h3),
                  const Spacer(),
                  TextButton(
                    onPressed: activeCount > 0 ? _reset : null,
                    style: TextButton.styleFrom(
                      foregroundColor: context.opsDanger,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text(
                      'Бүгдийг арилгах',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                // Full width, so the sections stay left-aligned however
                // narrow their chips are.
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.showBranches && _branches.length >= 2) ...[
                        _Section(
                          title: 'Салбар',
                          children: [
                            FilterPill(
                              label: 'Бүгд',
                              selected: _branchId == null,
                              onTap: () => setState(() => _branchId = null),
                            ),
                            for (final branch in _branches)
                              FilterPill(
                                label: branch.name,
                                selected: _branchId == branch.id,
                                onTap: () =>
                                    setState(() => _branchId = branch.id),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                      _Section(
                        title: 'Нээлттэй / Хаагдсан',
                        children: [
                          FilterPill(
                            label: 'Бүгд',
                            selected: group == null,
                            onTap: () => _setGroup(null),
                          ),
                          for (final option in AppointmentStatusGroup.values)
                            FilterPill(
                              label: option.label,
                              selected: group == option,
                              onTap: () => _setGroup(option),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        title: 'Төлөв',
                        children: [
                          FilterPill(
                            label: 'Бүгд',
                            selected: _status == null,
                            onTap: () => setState(() => _status = null),
                          ),
                          for (final status in statuses)
                            FilterPill(
                              label: status.label,
                              selected: _status == status,
                              color: context.appointmentStatusColor(status),
                              onTap: () => setState(() => _status = status),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.opsDivider)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  key: const ValueKey('appointment_filter_apply'),
                  onPressed: () => AppNav.back(_built),
                  child: Text(
                    activeCount > 0
                        ? 'Хэрэглэх  ·  $activeCount шүүлт'
                        : 'Хэрэглэх',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.opsTextOnDark,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.opsTextSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }
}
