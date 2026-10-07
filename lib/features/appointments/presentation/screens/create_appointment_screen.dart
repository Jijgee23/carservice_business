import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';
import 'package:carservice_business/app/shell/shell_chrome.dart';
import 'package:flutter/material.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/service_catalog.dart';
import 'package:carservice_business/features/appointments/presentation/controllers/create_appointment_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/new_customer_sheet.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/features/appointments/presentation/widgets/assignee_picker_field.dart';

class CreateAppointmentScreen extends StatelessWidget {
  const CreateAppointmentScreen({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CreateAppointmentController(
        initialDate: initialDate,
        workingBranchId: workingBranchIdOf(context),
      )..init(),
      child: const _Body(),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreateAppointmentController>();

    return Scaffold(
      backgroundColor: context.opsBackground,
      appBar: AppBar(
        title: Text('Цаг захиалга үүсгэх'),
        actions: const [ShellNotificationBell()],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Салбар ──────────────────────────────────────────
                  _SectionLabel(
                    number: '1',
                    title: 'Салбар',
                    done: ctrl.selectedBranch != null,
                  ),
                  const SizedBox(height: 10),
                  _BranchSection(ctrl: ctrl),
                  if (ctrl.fieldError('branchId') != null) ...[
                    const SizedBox(height: 6),
                    _FieldErrorText(ctrl.fieldError('branchId')!),
                  ],
                  const SizedBox(height: 24),

                  // ── 2. Ажлын төрөл ───────────────────────────────────────
                  _SectionLabel(
                    number: '2',
                    title: 'Ажлын төрөл',
                    optional: true,
                    done: ctrl.selectedCategoryIds.isNotEmpty,
                  ),
                  const SizedBox(height: 10),
                  _CategorySection(ctrl: ctrl),
                  if (ctrl.fieldError('categoryIds') != null) ...[
                    const SizedBox(height: 6),
                    _FieldErrorText(ctrl.fieldError('categoryIds')!),
                  ],
                  const SizedBox(height: 24),

                  // ── 3. Огноо, цаг ─────────────────────────────────────
                  _SectionLabel(
                    number: '3',
                    title: 'Огноо, цаг',
                    done: ctrl.selectedSlot != null,
                  ),
                  const SizedBox(height: 10),
                  _DateTimeSection(ctrl: ctrl),
                  const SizedBox(height: 24),

                  // ── 4. Хэрэглэгч ──────────────────────────────────────
                  _SectionLabel(
                    number: '4',
                    title: 'Хэрэглэгч',
                    done: ctrl.selectedCustomer != null,
                  ),
                  const SizedBox(height: 10),
                  _CustomerSection(ctrl: ctrl),
                  if (ctrl.fieldError('customerId') != null) ...[
                    const SizedBox(height: 6),
                    _FieldErrorText(ctrl.fieldError('customerId')!),
                  ],
                  const SizedBox(height: 24),

                  // ── 5. Машин ───────────────────────────────────────────
                  _SectionLabel(
                    number: '5',
                    title: 'Машин',
                    done: ctrl.selectedVehicle != null,
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  _VehicleSection(ctrl: ctrl),
                  const SizedBox(height: 24),

                  // ── 6. Хариуцах мастер (orders.assign эрхтэй хэрэглэгчид) ──
                  if (ctrl.canAssign) ...[
                    _SectionLabel(
                      number: '6',
                      title: 'Хариуцах мастер',
                      done: ctrl.assignee != null,
                    ),
                    const SizedBox(height: 10),
                    AssigneePickerField(
                      users: ctrl.assignees,
                      selected: ctrl.assignee,
                      loading: ctrl.loadingAssignees,
                      error: ctrl.assigneesError,
                      fieldError: ctrl.fieldError('assignedToId'),
                      onChanged: ctrl.selectAssignee,
                      onRetry: ctrl.loadAssignees,
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (ctrl.assigneeBlockedReason != null) ...[
                    _FieldErrorText(ctrl.assigneeBlockedReason!),
                    const SizedBox(height: 24),
                  ],

                  // ── Тэмдэглэл ──────────────────────────────────────────
                  _SectionLabel(
                    number: ctrl.canAssign ? '7' : '6',
                    title: 'Тэмдэглэл',
                    optional: true,
                    done: false,
                  ),
                  const SizedBox(height: 10),
                  _NoteSection(ctrl: ctrl),
                  if (ctrl.fieldError('note') != null) ...[
                    const SizedBox(height: 6),
                    _FieldErrorText(ctrl.fieldError('note')!),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          _BottomBar(ctrl: ctrl),
        ],
      ),
    );
  }
}

// ─── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String number;
  final String title;
  final bool done;
  final bool optional;

  const _SectionLabel({
    required this.number,
    required this.title,
    this.done = false,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: done ? context.opsGood : context.opsPrimary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: done
                ? Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: context.opsTextOnDark,
                  )
                : Text(
                    number,
                    style: context.textStyles.label.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.opsTextOnDark,
                    ),
                  ),
          ),
        ),
        SizedBox(width: 8),
        Text(
          title,
          style: context.textStyles.h3.copyWith(
            color: done ? context.opsGood : context.opsTextPrimary,
          ),
        ),
        if (optional) ...[
          SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: context.opsBackground,
              borderRadius: BorderRadius.circular(AppDimens.radiusXS),
            ),
            child: Text(
              'заавал биш',
              style: context.textStyles.label.copyWith(
                color: context.opsTextHint,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Category section ───────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _CategorySection({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    if (ctrl.loadingCategories) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.opsDivider),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Ажлын төрлүүдийг ачааллаж байна...',
              style: context.textStyles.caption,
            ),
          ],
        ),
      );
    }

    if (ctrl.categories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ctrl.categories.map((LaborCategory c) {
        final selected = ctrl.selectedCategoryIds.contains(c.id);
        return GestureDetector(
          onTap: () => ctrl.toggleCategory(c.id),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? context.opsAccent.withOpacity(0.1)
                  : context.opsSurface,
              borderRadius: BorderRadius.circular(AppDimens.radiusFull),
              border: Border.all(
                color: selected ? context.opsAccent : context.opsDivider,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(
              c.name,
              style: context.textStyles.body.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? context.opsAccent : context.opsTextPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Date/time (slot) section ───────────────────────────────────────────────────

class _DateTimeSection extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _DateTimeSection({required this.ctrl});

  static final _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _pickDate(context),
          child: Container(
            decoration: BoxDecoration(
              color: context.opsSurface,
              borderRadius: BorderRadius.circular(AppDimens.radiusMD),
              border: Border.all(
                color: context.opsAccent.withOpacity(0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: context.opsAccent.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: context.opsAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppDimens.radiusSM),
                  ),
                  child: Icon(
                    Icons.event_rounded,
                    color: context.opsAccent,
                    size: 22,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Огноо',
                        style: context.textStyles.label.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.opsAccent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dateFmt.format(ctrl.selectedDate),
                        style: context.textStyles.h3,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_calendar_rounded,
                  size: 18,
                  color: context.opsAccent,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SlotPicker(ctrl: ctrl),
        if (ctrl.fieldError('requestedAt') != null) ...[
          const SizedBox(height: 6),
          _FieldErrorText(ctrl.fieldError('requestedAt')!),
        ],
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = await AppDatePicker.single(
      context,
      initial: ctrl.selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (result != null) ctrl.setDate(result);
  }
}

/// Real slot picking against `GET /appointments/slots`. A slot is offered as
/// tappable only when [CreateAppointmentController.isSlotBookable] says so —
/// past time never offers a booking affordance, and empty future capacity
/// (`available == false`) is shown but inert, mirroring the calendar's
/// `isFuture && withinCapacity` rule rather than a second one invented here.
class _SlotPicker extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _SlotPicker({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    if (ctrl.loadingSlots) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.opsDivider),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Сул цагийг ачааллаж байна...',
              style: context.textStyles.caption,
            ),
          ],
        ),
      );
    }

    if (ctrl.slotsError != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.opsWarning.withOpacity(0.4)),
        ),
        child: Text(
          ctrl.slotsError!.display,
          style: context.textStyles.caption.copyWith(color: context.opsWarning),
        ),
      );
    }

    final availability = ctrl.availability;
    if (availability == null) {
      return Text(
        'Эхлээд салбар сонгоно уу',
        style: context.textStyles.caption,
      );
    }

    if (!availability.open) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.opsDivider),
        ),
        child: Text(
          availability.reason ?? 'Энэ өдөр ажиллахгүй',
          style: context.textStyles.caption,
        ),
      );
    }

    if (availability.slots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.opsDivider),
        ),
        child: Text('Энэ өдөр сул цаг алга', style: context.textStyles.caption),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: availability.slots.map((slot) {
        final bookable = ctrl.isSlotBookable(slot);
        final selected = ctrl.selectedSlot?.iso == slot.iso;
        return GestureDetector(
          onTap: bookable ? () => ctrl.selectSlot(slot) : null,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: !bookable
                  ? context.opsBackground
                  : selected
                  ? context.opsAccent
                  : context.opsSurface,
              borderRadius: BorderRadius.circular(AppDimens.radiusFull),
              border: Border.all(
                color: !bookable
                    ? context.opsDivider
                    : selected
                    ? context.opsAccent
                    : context.opsDivider,
              ),
            ),
            child: Text(
              slot.time,
              style: context.textStyles.body.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: !bookable
                    ? context.opsTextHint
                    : selected
                    ? context.opsTextOnDark
                    : context.opsTextPrimary,
                decoration: !bookable ? TextDecoration.lineThrough : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FieldErrorText extends StatelessWidget {
  final String message;
  const _FieldErrorText(this.message);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 13, color: context.opsWarning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: context.textStyles.caption.copyWith(
              color: context.opsWarning,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Customer section ──────────────────────────────────────────────────────────

class _CustomerSection extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _CustomerSection({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    // Selected customer card
    if (ctrl.selectedCustomer != null) {
      return _SelectedCustomerCard(ctrl: ctrl);
    }

    // Search mode
    return Column(
      children: [
        // Search field
        _SearchField(
          controller: ctrl.customerSearchCtrl,
          hint: 'Нэр эсвэл утасны дугаараар хайх...',
          icon: Icons.person_search_rounded,
          loading: ctrl.searchingCustomer,
          onChanged: ctrl.searchCustomer,
          onClear: () {
            ctrl.customerSearchCtrl.clear();
            ctrl.searchCustomer('');
          },
        ),

        // Results
        if (ctrl.customerResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          _CustomerResults(ctrl: ctrl),
        ],

        const SizedBox(height: 10),

        // Create a new customer — matches the web dashboard's "Шинэ
        // үйлчлүүлэгч нэмэх" affordance; reuses the shared new-customer
        // sheet from the Orders feature (`showNewCustomerSheet`) rather than
        // a second creation path.
        GestureDetector(
          onTap: () => _openAddCustomer(context, ctrl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: context.opsSurface,
              borderRadius: BorderRadius.circular(AppDimens.radiusMD),
              border: Border.all(color: context.opsAccent.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.person_add_rounded,
                  size: 18,
                  color: context.opsAccent,
                ),
                SizedBox(width: 10),
                Text(
                  'Шинэ үйлчлүүлэгч нэмэх',
                  style: context.textStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.opsAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openAddCustomer(
    BuildContext context,
    CreateAppointmentController ctrl,
  ) async {
    final result = await showNewCustomerSheet(context);
    if (result != null && context.mounted) ctrl.selectCustomer(result);
  }
}

class _SelectedCustomerCard extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _SelectedCustomerCard({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final c = ctrl.selectedCustomer!;
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(
          color: context.opsAccent.withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: context.opsAccent.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.opsAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (c.displayName.isNotEmpty ? c.displayName[0] : '?')
                    .toUpperCase(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.opsAccent,
                ),
              ),
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.displayName, style: context.textStyles.bodyMedium),
                SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      size: 12,
                      color: context.opsTextHint,
                    ),
                    const SizedBox(width: 4),
                    Text(c.phone, style: context.textStyles.caption),
                    if (c.email != null) ...[
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.email!,
                          style: context.textStyles.caption.copyWith(
                            color: context.opsTextHint,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Хэрэглэгчийг арилгах',
            child: GestureDetector(
              onTap: ctrl.clearCustomer,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.opsBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: context.opsTextSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerResults extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _CustomerResults({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final results = ctrl.customerResults;
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsDivider),
        boxShadow: [
          BoxShadow(
            color: context.opsTextPrimary.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: results.take(5).toList().asMap().entries.map((e) {
          final i = e.key;
          final c = e.value;
          final isLast = i == results.length - 1 || i == 4;
          return InkWell(
            onTap: () => ctrl.selectCustomer(c),
            borderRadius: BorderRadius.vertical(
              top: i == 0
                  ? const Radius.circular(AppDimens.radiusMD)
                  : Radius.zero,
              bottom: isLast
                  ? const Radius.circular(AppDimens.radiusMD)
                  : Radius.zero,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                border: !isLast
                    ? Border(bottom: BorderSide(color: context.opsDivider))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.opsAccent.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (c.displayName.isNotEmpty ? c.displayName[0] : '?')
                            .toUpperCase(),
                        style: context.textStyles.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.opsAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.displayName,
                          style: context.textStyles.bodyMedium,
                        ),
                        Text(c.phone, style: context.textStyles.caption),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: context.opsTextHint,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Vehicle section ───────────────────────────────────────────────────────────

class _VehicleSection extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _VehicleSection({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    // Selected vehicle
    if (ctrl.selectedVehicle != null) {
      return _SelectedVehicleCard(ctrl: ctrl);
    }

    return Column(
      children: [
        _SearchField(
          controller: ctrl.vehicleSearchCtrl,
          hint: 'Улсын дугаараар хайх...',
          icon: Icons.directions_car_rounded,
          loading: ctrl.searchingVehicle || ctrl.loadingCustomerVehicles,
          onChanged: ctrl.searchVehicle,
          onClear: () {
            ctrl.vehicleSearchCtrl.clear();
            ctrl.searchVehicle('');
          },
          capitalize: true,
        ),
        if (ctrl.vehicleResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          _VehicleResults(ctrl: ctrl),
        ],
      ],
    );
  }
}

class _SelectedVehicleCard extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _SelectedVehicleCard({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final v = ctrl.selectedVehicle!;
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsGood.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.opsGood.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.opsGood.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDimens.radiusSM),
            ),
            child: Icon(
              Icons.directions_car_rounded,
              color: context.opsGood,
              size: 22,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plateLabel(v.plate, v.vin),
                  style: context.textStyles.h3.copyWith(color: context.opsGood),
                ),
                const SizedBox(height: 2),
                Text(v.displayName, style: context.textStyles.caption),
                if (v.customer != null) ...[
                  SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 12,
                        color: context.opsTextHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        v.customer!.displayName,
                        style: context.textStyles.caption,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Tooltip(
            message: 'Машиныг арилгах',
            child: GestureDetector(
              onTap: ctrl.clearVehicle,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.opsBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: context.opsTextSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleResults extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _VehicleResults({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final results = ctrl.vehicleResults;
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsDivider),
        boxShadow: [
          BoxShadow(
            color: context.opsTextPrimary.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: results.take(5).toList().asMap().entries.map((e) {
          final i = e.key;
          final v = e.value;
          final isLast = i == results.length - 1 || i == 4;
          return InkWell(
            onTap: () => ctrl.selectVehicle(v),
            borderRadius: BorderRadius.vertical(
              top: i == 0
                  ? const Radius.circular(AppDimens.radiusMD)
                  : Radius.zero,
              bottom: isLast
                  ? const Radius.circular(AppDimens.radiusMD)
                  : Radius.zero,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                border: !isLast
                    ? Border(bottom: BorderSide(color: context.opsDivider))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.opsAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(AppDimens.radiusSM),
                    ),
                    child: Icon(
                      Icons.directions_car_outlined,
                      color: context.opsAccent,
                      size: 18,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plateLabel(v.plate, v.vin),
                          style: context.textStyles.bodyMedium,
                        ),
                        Text(v.displayName, style: context.textStyles.caption),
                        if (v.customer != null)
                          Text(
                            v.customer!.displayName,
                            style: context.textStyles.caption.copyWith(
                              color: context.opsTextHint,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: context.opsTextHint,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Branch section ─────────────────────────────────────────────────────────────

class _BranchSection extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _BranchSection({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    if (ctrl.loadingBranches) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.opsDivider),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Салбаруудыг ачааллаж байна...',
              style: context.textStyles.caption,
            ),
          ],
        ),
      );
    }

    if (ctrl.branches.length == 1) {
      final b = ctrl.branches.first;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.opsGood.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
              color: context.opsGood.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.opsGood.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppDimens.radiusSM),
              ),
              child: Icon(
                Icons.storefront_rounded,
                color: context.opsGood,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name, style: context.textStyles.bodyMedium),
                  if (b.address != null)
                    Text(b.address!, style: context.textStyles.caption),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.opsGood.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppDimens.radiusFull),
              ),
              child: Text(
                'Автомат',
                style: context.textStyles.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.opsGood,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsDivider),
        boxShadow: [
          BoxShadow(
            color: context.opsTextPrimary.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: ctrl.branches.asMap().entries.map((e) {
          final i = e.key;
          final b = e.value;
          final isSelected = b.id == ctrl.selectedBranch?.id;
          final isLast = i == ctrl.branches.length - 1;
          return InkWell(
            onTap: () => ctrl.selectBranch(b),
            borderRadius: BorderRadius.vertical(
              top: i == 0
                  ? const Radius.circular(AppDimens.radiusMD)
                  : Radius.zero,
              bottom: isLast
                  ? const Radius.circular(AppDimens.radiusMD)
                  : Radius.zero,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? context.opsAccent.withOpacity(0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.vertical(
                  top: i == 0
                      ? const Radius.circular(AppDimens.radiusMD)
                      : Radius.zero,
                  bottom: isLast
                      ? const Radius.circular(AppDimens.radiusMD)
                      : Radius.zero,
                ),
                border: !isLast
                    ? Border(bottom: BorderSide(color: context.opsDivider))
                    : null,
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? context.opsAccent
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? context.opsAccent
                            : context.opsDivider,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 12,
                            color: context.opsTextOnDark,
                          )
                        : null,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.name,
                          style: context.textStyles.bodyMedium.copyWith(
                            color: isSelected
                                ? context.opsAccent
                                : context.opsTextPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (b.address != null)
                          Text(b.address!, style: context.textStyles.caption),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: context.opsAccent,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Note section ──────────────────────────────────────────────────────────────

class _NoteSection extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _NoteSection({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsDivider),
        boxShadow: [
          BoxShadow(
            color: context.opsTextPrimary.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.opsBackground,
                borderRadius: BorderRadius.circular(AppDimens.radiusSM),
              ),
              child: Icon(
                Icons.notes_rounded,
                size: 18,
                color: context.opsTextHint,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: ctrl.noteCtrl,
              maxLines: 3,
              style: context.textStyles.body,
              decoration: const InputDecoration(
                hintText: 'Тэмдэглэл... (заавал биш)',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared search field ───────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool loading;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool capitalize;

  const _SearchField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.loading,
    required this.onChanged,
    required this.onClear,
    this.capitalize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsDivider),
        boxShadow: [
          BoxShadow(
            color: context.opsTextPrimary.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        textCapitalization: capitalize
            ? TextCapitalization.characters
            : TextCapitalization.none,
        onChanged: onChanged,
        style: context.textStyles.body,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: context.opsTextHint, size: 20),
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, size: 18, color: context.opsTextHint),
                  tooltip: 'Цэвэрлэх',
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: context.opsSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            borderSide: BorderSide(color: context.opsAccent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─── Bottom bar ─────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final CreateAppointmentController ctrl;
  const _BottomBar({required this.ctrl});

  static final _fmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final can = ctrl.canSubmit;

    String? hint;
    if (ctrl.selectedBranch == null) {
      hint = 'Салбар сонгоогүй байна';
    } else if (ctrl.selectedSlot == null) {
      hint = 'Цаг сонгоогүй байна';
    } else if (ctrl.selectedCustomer == null) {
      hint = 'Хэрэглэгч сонгоогүй байна';
    } else if (ctrl.canAssign && ctrl.assignee == null) {
      hint = 'Мастер сонгоогүй байна';
    }

    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        border: Border(top: BorderSide(color: context.opsDivider)),
        boxShadow: [
          BoxShadow(
            color: context.opsTextPrimary.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Summary row
          if (can) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.opsBackground,
                borderRadius: BorderRadius.circular(AppDimens.radiusSM),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_rounded,
                    size: 13,
                    color: context.opsTextSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _fmt.format(ctrl.requestedAt!),
                    style: context.textStyles.captionMedium,
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.person_outline,
                    size: 13,
                    color: context.opsTextSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      ctrl.selectedCustomer!.displayName,
                      style: context.textStyles.captionMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Missing hint
          if (hint != null) ...[
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: context.opsWarning,
                ),
                SizedBox(width: 6),
                Text(
                  hint,
                  style: context.textStyles.caption.copyWith(
                    color: context.opsWarning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: can
                ? Material(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: ctrl.submitting
                            ? null
                            : LinearGradient(
                                colors: [
                                  context.opsAccent,
                                  context.opsAccent.withBlue(220),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                        color: ctrl.submitting
                            ? context.opsAccent.withOpacity(0.6)
                            : null,
                        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                        boxShadow: ctrl.submitting
                            ? null
                            : [
                                BoxShadow(
                                  color: context.opsAccent.withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: InkWell(
                        onTap: ctrl.submitting ? null : () => _submit(context),
                        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                        child: Center(
                          child: ctrl.submitting
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.opsTextOnDark,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 18,
                                      color: context.opsTextOnDark,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Цаг захиалга үүсгэх',
                                      style: context.textStyles.buttonText
                                          .copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: context.opsTextOnDark,
                                            letterSpacing: 0.3,
                                          ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: context.opsDivider,
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    ),
                    child: Center(
                      child: Text(
                        'Цаг захиалга үүсгэх',
                        style: context.textStyles.buttonText.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.opsTextHint,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final ctrl = context.read<CreateAppointmentController>();
    final result = await ctrl.submit();
    if (result != null && context.mounted) {
      messageComplete('Цаг захиалга амжилттай үүслээ');
      AppNav.back(result);
    }
  }
}
