// ignore_for_file: constant_identifier_names

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/branch.dart';
import 'package:carservice_business/core/services/branch_service.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:flutter/material.dart';

import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/core/widgets/plate/plate_field.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/widgets/assignee_avatar.dart';
import 'package:intl/intl.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/core/widgets/app_dropdown.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

// ─── Filter model ─────────────────────────────────────────────────────────────

enum DatePreset {
  all,
  today,
  week,
  month;

  String get label {
    switch (this) {
      case all:
        return 'Бүгд';
      case today:
        return 'Өнөөдөр';
      case week:
        return '7 хоног';
      case month:
        return 'Энэ сар';
    }
  }

  DateTime? get cutoff => cutoffAt(DateTime.now());

  DateTime? cutoffAt(DateTime now) {
    final todayDate = DateTime(now.year, now.month, now.day);
    switch (this) {
      case all:
        return null;
      case today:
        return todayDate;
      case week:
        return todayDate.subtract(const Duration(days: 6));
      case month:
        return DateTime(todayDate.year, todayDate.month, 1);
    }
  }
}

enum OrderSortBy {
  createdAt,
  scheduledAt,
  totalAmount;

  String get label {
    switch (this) {
      case createdAt:
        return 'Үүсгэсэн огноо';
      case scheduledAt:
        return 'Товлосон огноо';
      case totalAmount:
        return 'Дүн';
    }
  }
}

class OrderFilter {
  final Set<OrderStatus> statuses;
  final Set<PaymentStatus> paymentStatuses;
  final DatePreset datePreset;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? branchId;
  final String? assignedToId;
  final String? plate;
  final bool? postpaid;

  /// Internal repair filter: true -> `internal=yes`, false -> `internal=no`.
  final bool? internal;

  /// Retained for source compatibility with the pre-F1 screen. The server's
  /// list contract has no ordering parameter, so this is never applied
  /// locally or counted as an active filter.
  final OrderSortBy sortBy;
  final bool sortAsc;

  const OrderFilter({
    this.statuses = const {},
    this.paymentStatuses = const {},
    this.datePreset = DatePreset.all,
    this.dateFrom,
    this.dateTo,
    this.branchId,
    this.assignedToId,
    this.plate,
    this.postpaid,
    this.internal,
    this.sortBy = OrderSortBy.createdAt,
    this.sortAsc = false,
  });

  static const empty = OrderFilter();

  int get activeCount {
    int n = 0;
    if (statuses.isNotEmpty) n++;
    if (paymentStatuses.isNotEmpty) n++;
    if (datePreset != DatePreset.all) n++;
    if (dateFrom != null || dateTo != null) n++;
    if (assignedToId != null) n++;
    if (plate != null) n++;
    if (postpaid != null || internal != null) n++;
    return n;
  }

  static const _serverStatuses = <OrderStatus>{
    OrderStatus.SCHEDULED,
    OrderStatus.IN_PROGRESS,
    OrderStatus.COMPLETED,
    OrderStatus.CANCELLED,
  };

  OrderStatus? get serverStatus =>
      statuses.length == 1 && _serverStatuses.contains(statuses.first)
      ? statuses.first
      : null;

  PaymentStatus? get serverPaymentStatus =>
      paymentStatuses.length == 1 ? paymentStatuses.first : null;

  bool get hasCustomRange => dateFrom != null || dateTo != null;

  /// "2026.09.01 – 2026.09.30" (or a single day) for chips and the filter bar.
  String get customRangeLabel {
    final fmt = DateFormat('yyyy.MM.dd');
    final a = fmt.format(dateFrom ?? dateTo!);
    final b = fmt.format(dateTo ?? dateFrom!);
    return a == b ? a : '$a – $b';
  }

  DateTime? get effectiveDateFrom => dateFrom ?? datePreset.cutoff;

  DateTime? get effectiveDateTo {
    if (dateTo != null) return dateTo;
    if (datePreset == DatePreset.all) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  OrderFilter copyWith({
    Set<OrderStatus>? statuses,
    Set<PaymentStatus>? paymentStatuses,
    DatePreset? datePreset,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? branchId,
    String? assignedToId,
    String? plate,
    bool? postpaid,
    bool? internal,
    OrderSortBy? sortBy,
    bool? sortAsc,
  }) => OrderFilter(
    statuses: statuses ?? this.statuses,
    paymentStatuses: paymentStatuses ?? this.paymentStatuses,
    datePreset: datePreset ?? this.datePreset,
    dateFrom: dateFrom ?? this.dateFrom,
    dateTo: dateTo ?? this.dateTo,
    branchId: branchId ?? this.branchId,
    assignedToId: assignedToId ?? this.assignedToId,
    plate: plate ?? this.plate,
    postpaid: postpaid ?? this.postpaid,
    internal: internal ?? this.internal,
    sortBy: sortBy ?? this.sortBy,
    sortAsc: sortAsc ?? this.sortAsc,
  );

  /// Compatibility shim. Filtering and ordering pages on the client is
  /// incorrect; callers must use [OrderListController]'s server query.
  List<ServiceOrderSummary> apply(List<ServiceOrderSummary> list) => list;
}

// ─── Reusable form body ─────────────────────────────────────────────────────
//
// Extracted for `TENANT_UI_UX_PLAN.md` Phase 5 so the same filter controls
// back both the phone bottom sheet (buffered, applied on a button tap) and
// the ≥1200dp persistent tablet panel (applied immediately, no buffering).
// Every edit is expressed as a brand-new [OrderFilter] built from [filter]
// rather than `OrderFilter.copyWith`, because `copyWith`'s `x ?? this.x`
// pattern can never clear a nullable field back to null.

const Object _unset = Object();

OrderFilter _withFilter(
  OrderFilter f, {
  Object? statuses = _unset,
  Object? paymentStatuses = _unset,
  Object? datePreset = _unset,
  Object? assignedToId = _unset,
  Object? plate = _unset,
  Object? dateFrom = _unset,
  Object? dateTo = _unset,
  Object? postpaid = _unset,
  Object? internal = _unset,
  Object? sortBy = _unset,
  Object? sortAsc = _unset,
}) => OrderFilter(
  statuses: identical(statuses, _unset)
      ? f.statuses
      : statuses as Set<OrderStatus>,
  paymentStatuses: identical(paymentStatuses, _unset)
      ? f.paymentStatuses
      : paymentStatuses as Set<PaymentStatus>,
  datePreset: identical(datePreset, _unset)
      ? f.datePreset
      : datePreset as DatePreset,
  dateFrom: identical(dateFrom, _unset) ? f.dateFrom : dateFrom as DateTime?,
  dateTo: identical(dateTo, _unset) ? f.dateTo : dateTo as DateTime?,
  branchId: f.branchId,
  assignedToId: identical(assignedToId, _unset)
      ? f.assignedToId
      : assignedToId as String?,
  plate: identical(plate, _unset) ? f.plate : plate as String?,
  postpaid: identical(postpaid, _unset) ? f.postpaid : postpaid as bool?,
  internal: identical(internal, _unset) ? f.internal : internal as bool?,
  sortBy: identical(sortBy, _unset) ? f.sortBy : sortBy as OrderSortBy,
  sortAsc: identical(sortAsc, _unset) ? f.sortAsc : sortAsc as bool,
);

/// The filter form's field set, with no sheet/panel chrome of its own.
///
/// [onChanged] fires with a complete, ready-to-apply [OrderFilter] on every
/// edit. The phone sheet buffers those into local state and only calls the
/// controller on "Хэрэглэх"; the tablet panel passes the controller's
/// `setFilter` straight through so a chip tap applies immediately.
class OrderFilterFormBody extends StatelessWidget {
  const OrderFilterFormBody({
    super.key,
    required this.filter,
    required this.onChanged,
    this.assignableUsers = const [],
    this.currentUserId,
    this.showSort = true,
    this.branchId,
    this.onBranchChanged,
  });

  final OrderFilter filter;
  final ValueChanged<OrderFilter> onChanged;
  final List<AssignableUser> assignableUsers;

  /// Adds a "Би" chip to the "Хариуцагч" section, so staff without
  /// `orders.assign` (whose roster request is denied) can still narrow the
  /// list to their own orders.
  final String? currentUserId;

  /// The phone sheet still offers a client sort order (kept for source
  /// compatibility; the server has no ordering parameter — see
  /// [OrderFilter.sortBy]). The tablet table sorts via its own column
  /// headers instead, so the persistent panel hides this section.
  final bool showSort;

  /// The list's branch, kept outside [filter] (see
  /// `OrderListController.applyFilters`). The "Салбар" section shows only
  /// when [onBranchChanged] is set — the caller decides who may widen the
  /// scope (owner, header working branch on "all").
  final String? branchId;
  final ValueChanged<String?>? onBranchChanged;

  @override
  Widget build(BuildContext context) {
    final onBranch = onBranchChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBranch != null)
          _BranchSection(selectedId: branchId, onChanged: onBranch),
        _PlateFilterField(
          value: filter.plate,
          onChanged: (plate) => onChanged(_withFilter(filter, plate: plate)),
        ),
        const SizedBox(height: 20),
        // Нэгдсэн төлбөрийн нөхцөл: Энгийн = дараа тооцоо ч биш, дотоод ч биш.
        _Section(
          title: 'Төлбөрийн нөхцөл',
          child: Wrap(
            spacing: 8,
            children: [
              _FilterChip(
                label: 'Бүгд',
                active: filter.postpaid == null && filter.internal == null,
                activeColor: context.opsAccent,
                onTap: () => onChanged(
                  _withFilter(filter, postpaid: null, internal: null),
                ),
              ),
              _FilterChip(
                label: 'Энгийн',
                active: filter.postpaid == false && filter.internal == false,
                activeColor: context.opsAccent,
                onTap: () => onChanged(
                  _withFilter(filter, postpaid: false, internal: false),
                ),
              ),
              _FilterChip(
                label: 'Дараа тооцоо',
                active: filter.postpaid == true,
                activeColor: context.opsAccent,
                onTap: () => onChanged(
                  _withFilter(filter, postpaid: true, internal: null),
                ),
              ),
              _FilterChip(
                label: 'Дотоод засвар',
                active: filter.internal == true,
                activeColor: context.opsAccent,
                onTap: () => onChanged(
                  _withFilter(filter, postpaid: null, internal: true),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (assignableUsers.isNotEmpty || currentUserId != null) ...[
          _AssigneeSection(
            selectedId: filter.assignedToId,
            users: assignableUsers,
            currentUserId: currentUserId,
            onChanged: (id) => onChanged(_withFilter(filter, assignedToId: id)),
          ),
          const SizedBox(height: 20),
        ],
        _Section(
          title: 'Статус',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                const [
                  OrderStatus.SCHEDULED,
                  OrderStatus.IN_PROGRESS,
                  OrderStatus.COMPLETED,
                  OrderStatus.CANCELLED,
                ].map((s) {
                  final active = filter.statuses.contains(s);
                  return _FilterChip(
                    label: s.label,
                    active: active,
                    activeColor: context.orderStatusColor(s),
                    onTap: () => onChanged(
                      _withFilter(
                        filter,
                        statuses: active ? const <OrderStatus>{} : {s},
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Төлбөрийн байдал',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PaymentStatus.values.map((s) {
              final active = filter.paymentStatuses.contains(s);
              return _FilterChip(
                label: s.label,
                active: active,
                activeColor: context.paymentStatusColor(s),
                onTap: () => onChanged(
                  _withFilter(
                    filter,
                    paymentStatuses: active ? const <PaymentStatus>{} : {s},
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Огноо',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...DatePreset.values.map((p) {
                final active = !filter.hasCustomRange && p == filter.datePreset;
                return _FilterChip(
                  label: p.label,
                  active: active,
                  activeColor: context.opsAccent,
                  onTap: () => onChanged(
                    _withFilter(
                      filter,
                      datePreset: p,
                      dateFrom: null,
                      dateTo: null,
                    ),
                  ),
                );
              }),
              _FilterChip(
                label: filter.hasCustomRange
                    ? filter.customRangeLabel
                    : 'Хугацаа сонгох',
                active: filter.hasCustomRange,
                activeColor: context.opsAccent,
                onTap: () async {
                  final now = DateTime.now();
                  final range = await AppDatePicker.range(
                    context,
                    initial: filter.hasCustomRange
                        ? DateTimeRange(
                            start: filter.dateFrom ?? filter.dateTo!,
                            end: filter.dateTo ?? filter.dateFrom!,
                          )
                        : null,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 1, 12, 31),
                  );
                  if (range == null) return;
                  onChanged(
                    _withFilter(
                      filter,
                      datePreset: DatePreset.all,
                      dateFrom: range.start,
                      dateTo: range.end,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        if (showSort) ...[
          const SizedBox(height: 20),
          _Section(
            title: 'Дараалал',
            child: Column(
              children: OrderSortBy.values.map((s) {
                final active = s == filter.sortBy;
                return InkWell(
                  onTap: () => onChanged(
                    _withFilter(
                      filter,
                      sortBy: s,
                      sortAsc: filter.sortBy == s ? !filter.sortAsc : false,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                  child: AnimatedContainer(
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? context.opsAccent.withOpacity(0.08)
                          : context.opsBackground,
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                      border: Border.all(
                        color: active
                            ? context.opsAccent.withOpacity(0.4)
                            : context.opsDivider,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          s == OrderSortBy.totalAmount
                              ? Icons.monetization_on_outlined
                              : s == OrderSortBy.scheduledAt
                              ? Icons.event_outlined
                              : Icons.access_time_outlined,
                          size: 16,
                          color: active
                              ? context.opsAccent
                              : context.opsTextSecondary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: active
                                ? context.opsAccent
                                : context.opsTextPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (active)
                          Icon(
                            filter.sortAsc
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 16,
                            color: context.opsAccent,
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

/// The persistent filter panel shown beside the tablet table at ≥1200dp
/// (`TENANT_UI_UX_PLAN.md` Phase 5). Reuses [OrderFilterFormBody] and applies
/// every edit immediately — there is no separate "apply" step because the
/// panel is always visible, unlike the phone sheet it shares its fields with.
class OrderFilterPanel extends StatelessWidget {
  const OrderFilterPanel({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.onClear,
    this.assignableUsers = const [],
    this.currentUserId,
    this.branchId,
    this.onBranchChanged,
  });

  final OrderFilter filter;
  final ValueChanged<OrderFilter> onChanged;
  final VoidCallback onClear;
  final List<AssignableUser> assignableUsers;
  final String? currentUserId;
  final String? branchId;
  final ValueChanged<String?>? onBranchChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('order_filter_panel'),
      width: 300,
      decoration: BoxDecoration(
        color: context.opsSurface,
        border: Border(right: BorderSide(color: context.opsDivider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('Шүүлтүүр', style: context.textStyles.h3),
                const Spacer(),
                if (filter.activeCount > 0 || branchId != null)
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      foregroundColor: context.opsDanger,
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text(
                      'Арилгах',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: OrderFilterFormBody(
                filter: filter,
                assignableUsers: assignableUsers,
                currentUserId: currentUserId,
                onChanged: onChanged,
                showSort: false,
                branchId: branchId,
                onBranchChanged: onBranchChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sheet ────────────────────────────────────────────────────────────────────

/// What the filter sheet returns: its [OrderFilter] plus the branch choice,
/// which the list keeps separately (see `OrderListController.applyFilters`).
typedef OrderFilterSelection = ({OrderFilter filter, String? branchId});

/// [showBranches] adds the "Салбар" section; the caller decides who may
/// widen the scope (owner, header working branch on "all").
Future<OrderFilterSelection?> showOrderFilterSheet(
  BuildContext context,
  OrderFilter current, {
  List<AssignableUser> assignableUsers = const [],
  String? currentUserId,
  String? branchId,
  bool showBranches = false,
}) {
  return AppNav.sheet<OrderFilterSelection>(
    _OrderFilterSheet(
      current: current,
      assignableUsers: assignableUsers,
      currentUserId: currentUserId,
      branchId: branchId,
      showBranches: showBranches,
    ),
    backgroundColor: Colors.transparent,
  );
}

class _OrderFilterSheet extends StatefulWidget {
  final OrderFilter current;
  final List<AssignableUser> assignableUsers;
  final String? currentUserId;
  final String? branchId;
  final bool showBranches;
  const _OrderFilterSheet({
    required this.current,
    this.assignableUsers = const [],
    this.currentUserId,
    this.branchId,
    this.showBranches = false,
  });

  @override
  State<_OrderFilterSheet> createState() => _OrderFilterSheetState();
}

class _OrderFilterSheetState extends State<_OrderFilterSheet> {
  late Set<OrderStatus> _statuses;
  late Set<PaymentStatus> _paymentStatuses;
  late DatePreset _datePreset;
  late OrderSortBy _sortBy;
  late bool _sortAsc;
  late String? _assignedToId;
  late bool? _postpaid;
  late bool? _internal;
  late String? _plate;
  late DateTime? _dateFrom;
  late DateTime? _dateTo;
  late String? _branchId = widget.current.branchId ?? widget.branchId;

  int get _activeCount => _built.activeCount + (_branchId != null ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _statuses = Set.from(widget.current.statuses);
    _paymentStatuses = Set.from(widget.current.paymentStatuses);
    _datePreset = widget.current.datePreset;
    _sortBy = widget.current.sortBy;
    _sortAsc = widget.current.sortAsc;
    _assignedToId = widget.current.assignedToId;
    _postpaid = widget.current.postpaid;
    _internal = widget.current.internal;
    _plate = widget.current.plate;
    _dateFrom = widget.current.dateFrom;
    _dateTo = widget.current.dateTo;
  }

  OrderFilter get _built => OrderFilter(
    statuses: _statuses,
    paymentStatuses: _paymentStatuses,
    datePreset: _datePreset,
    dateFrom: _dateFrom,
    dateTo: _dateTo,
    assignedToId: _assignedToId,
    plate: _plate,
    postpaid: _postpaid,
    internal: _internal,
    sortBy: _sortBy,
    sortAsc: _sortAsc,
  );

  void _reset() => setState(() {
    _statuses = {};
    _paymentStatuses = {};
    _datePreset = DatePreset.all;
    _sortBy = OrderSortBy.createdAt;
    _sortAsc = false;
    _assignedToId = null;
    _postpaid = null;
    _internal = null;
    _plate = null;
    _dateFrom = null;
    _dateTo = null;
    _branchId = null;
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.opsDivider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text('Шүүлтүүр', style: context.textStyles.h3),
                Spacer(),
                TextButton(
                  onPressed: _reset,
                  style: TextButton.styleFrom(
                    foregroundColor: context.opsDanger,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(
                    'Бүгдийг арилгах',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
              children: [
                OrderFilterFormBody(
                  filter: _built,
                  assignableUsers: widget.assignableUsers,
                  currentUserId: widget.currentUserId,
                  branchId: _branchId,
                  onBranchChanged: widget.showBranches
                      ? (id) => setState(() => _branchId = id)
                      : null,
                  onChanged: (next) => setState(() {
                    _statuses = next.statuses;
                    _paymentStatuses = next.paymentStatuses;
                    _datePreset = next.datePreset;
                    _assignedToId = next.assignedToId;
                    _postpaid = next.postpaid;
                    _internal = next.internal;
                    _plate = next.plate;
                    _dateFrom = next.dateFrom;
                    _dateTo = next.dateTo;
                    _sortBy = next.sortBy;
                    _sortAsc = next.sortAsc;
                  }),
                ),
              ],
            ),
          ),

          // Apply button
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: context.opsSurface,
              border: Border(top: BorderSide(color: context.opsDivider)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => AppNav.back<OrderFilterSelection>((
                  filter: _built,
                  branchId: _branchId,
                )),
                child: Text(
                  _activeCount > 0
                      ? 'Хэрэглэх  ·  $_activeCount шүүлт'
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
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// "Салбар" chips, formerly the list's inline `BranchFilterBar`. Loads the
/// tenant's branches itself ([BranchService] caches them) and renders
/// nothing — no gap either — until there are at least two to choose from.
/// The plate filter with the plate keypad; its value is canonical
/// ([normalizePlate]) so it matches the stored plates.
class _PlateFilterField extends StatefulWidget {
  const _PlateFilterField({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<_PlateFilterField> createState() => _PlateFilterFieldState();
}

class _PlateFilterFieldState extends State<_PlateFilterField> {
  late final _ctrl = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(_PlateFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow a reset from outside, not the field's own edits.
    final value = widget.value ?? '';
    if (normalizePlate(_ctrl.text) != value) _ctrl.text = value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlateField(
    fieldKey: const ValueKey('order_filter_plate'),
    controller: _ctrl,
    decoration: const InputDecoration(
      labelText: 'Улсын дугаар',
      hintText: 'Жишээ: 1234УБА',
      prefixIcon: Icon(Icons.directions_car_outlined),
      border: OutlineInputBorder(),
    ),
    onChanged: (value) {
      final plate = normalizePlate(value);
      widget.onChanged(plate.isEmpty ? null : plate);
    },
  );
}

class _BranchSection extends StatefulWidget {
  const _BranchSection({required this.selectedId, required this.onChanged});

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  State<_BranchSection> createState() => _BranchSectionState();
}

class _BranchSectionState extends State<_BranchSection> {
  List<Branch> _branches = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final branches = await BranchService.instance.getBranches();
    if (mounted) setState(() => _branches = branches);
  }

  @override
  Widget build(BuildContext context) {
    if (_branches.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: _Section(
        title: 'Салбар',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: 'Бүгд',
              active: widget.selectedId == null,
              activeColor: context.opsAccent,
              onTap: () => widget.onChanged(null),
            ),
            for (final branch in _branches)
              _FilterChip(
                label: branch.name,
                active: widget.selectedId == branch.id,
                activeColor: context.opsAccent,
                onTap: () => widget.onChanged(branch.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Хариуцагч" dropdown: all, the current user, then the branch roster.
/// The server filters by exact `assignedToId` only, so there is no
/// "unassigned" option.
class _AssigneeSection extends StatelessWidget {
  const _AssigneeSection({
    required this.selectedId,
    required this.users,
    required this.currentUserId,
    required this.onChanged,
  });

  final String? selectedId;
  final List<AssignableUser> users;
  final String? currentUserId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final me = currentUserId;
    // A filter from elsewhere (another branch's roster) still gets an
    // option, so it stays visible and can be changed here.
    final unknown =
        selectedId != null &&
        selectedId != me &&
        !users.any((user) => user.id == selectedId);
    return _Section(
      title: 'Хариуцагч',
      child: AppDropdown<String?>(
        key: const ValueKey('order_filter_assignee'),
        value: selectedId,
        items: [
          const AppDropdownItem<String?>(
            key: ValueKey('order_filter_assignee_all'),
            value: null,
            label: 'Бүгд',
            leading: _AssigneeIcon(icon: Icons.groups_outlined),
          ),
          if (me != null)
            AppDropdownItem<String?>(
              key: const ValueKey('order_filter_assignee_me'),
              value: me,
              label: 'Би',
              leading: const _AssigneeIcon(icon: Icons.person_rounded),
            ),
          for (final user in users)
            if (user.id != me)
              AppDropdownItem<String?>(
                key: ValueKey('order_filter_assignee_${user.id}'),
                value: user.id,
                label: user.fullName,
                leading: AssigneeAvatar(name: user.fullName, size: 28),
              ),
          if (unknown)
            AppDropdownItem<String?>(
              value: selectedId,
              label: 'Сонгосон ажилтан',
              leading: const AssigneeAvatar(name: null, size: 28),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Icon in an avatar-sized circle, for the non-person "Бүгд"/"Би" rows.
class _AssigneeIcon extends StatelessWidget {
  const _AssigneeIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: context.opsAccent.withOpacity(.14),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 16, color: context.opsAccent),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

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
        child,
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: AnimatedContainer(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? activeColor.withOpacity(0.12)
                    : context.opsBackground,
                borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                border: Border.all(
                  color: active
                      ? activeColor.withOpacity(0.5)
                      : context.opsDivider,
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? activeColor : context.opsTextSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Active filter summary widget (used in list screen) ───────────────────────

class ActiveFilterBar extends StatelessWidget {
  final OrderFilter filter;
  final VoidCallback onClear;

  /// Resolve [OrderFilter.assignedToId] to a name for its chip.
  final List<AssignableUser> assignableUsers;
  final String? currentUserId;
  final NumberFormat numFmt = NumberFormat('#,###');

  ActiveFilterBar({
    super.key,
    required this.filter,
    required this.onClear,
    this.assignableUsers = const [],
    this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <String>[];

    for (final s in filter.statuses) {
      chips.add(s.label);
    }
    for (final p in filter.paymentStatuses) {
      chips.add(p.label);
    }
    if (filter.datePreset != DatePreset.all) chips.add(filter.datePreset.label);
    if (filter.hasCustomRange) chips.add(filter.customRangeLabel);
    if (filter.plate != null) chips.add(filter.plate!);
    if (filter.assignedToId case final id?) {
      final name = id == currentUserId
          ? 'Би'
          : assignableUsers
                .where((user) => user.id == id)
                .firstOrNull
                ?.fullName;
      chips.add(name == null ? 'Хариуцагч' : 'Хариуцагч: $name');
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      color: context.opsAccent.withOpacity(0.06),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 14, color: context.opsAccent),
          SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: chips
                    .map(
                      (c) => Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: context.opsAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusFull,
                          ),
                        ),
                        child: Text(
                          c,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.opsAccent,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close, size: 16, color: context.opsAccent),
            ),
          ),
        ],
      ),
    );
  }
}
