import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/org_badge.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';
import 'package:carservice_business/features/vehicles/presentation/controllers/vehicle_detail_controller.dart';
import 'package:carservice_business/features/diagnostics/presentation/controllers/new_inspection_controller.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/new_inspection_screen.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Vehicle detail, delete and HUR-refresh screen — `P3-F5`.
///
/// Constructed with a [vehicleId] only, never a preloaded summary — the deep
/// link and every list/search row alike land here and fetch from
/// `GET /vehicles/[id]`, the only route that carries the extended attribute
/// block and the nested owner. See
/// `vehicle_detail_controller.dart` for the fetch/edit/delete/HUR lifecycle,
/// the `PATCH` owner-block divergence, and why a HUR refresh can never
/// discard a field this screen did not ask it to touch.
///
/// Every delete affordance is a client-side UX hint only
/// (`PermissionGate`, mirroring `AppointmentDetailScreen`): the server
/// remains authoritative, and a rejection this screen thought was legal is
/// always shown via `error.display` verbatim, never replaced with
/// client-authored copy.
class VehicleDetailScreen extends StatefulWidget {
  const VehicleDetailScreen({
    super.key,
    required this.vehicleId,
    this.repository,
    this.user,
  });

  final String vehicleId;
  final VehiclesRepository? repository;
  final User? user;

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  late final VehicleDetailController _controller;

  User? get _user => widget.user ?? Authenticator.user;

  @override
  void initState() {
    super.initState();
    _controller = VehicleDetailController(
      vehicleId: widget.vehicleId,
      repo: widget.repository,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<VehicleDetailController>.value(
      value: _controller,
      child: Consumer<VehicleDetailController>(
        builder: (context, controller, _) =>
            _Scaffold(controller: controller, user: _user),
      ),
    );
  }
}

class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.controller, required this.user});

  final VehicleDetailController controller;
  final User? user;

  /// Restored for DM-01 parity. Pushes a bare `NewInspectionController`,
  /// exactly as the legacy screen's FAB did.
  void _startInspection(BuildContext context) {
    AppNav.to(
      ChangeNotifierProvider(
        create: (_) => NewInspectionController(),
        child: const NewInspectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.detailState;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.valueOrNull == null
              ? 'Машин'
              : plateLabel(state.valueOrNull!.plate, state.valueOrNull!.vin),
        ),
        actions: [
          if (state.valueOrNull != null) ...[
            // IconButton(
            //   tooltip: 'ХУР-аас шинэчлэх',
            //   onPressed: controller.refreshingHur ? null : () => _refreshHur(context, controller),
            //   icon: controller.refreshingHur
            //       ? const SizedBox(
            //           width: 18,
            //           height: 18,
            //           child: CircularProgressIndicator(strokeWidth: 2),
            //         )
            //       : const Icon(Icons.sync_rounded),
            // ),
            // Shown but disabled without `vehicles.delete`.
            PermissionGate(
              permission: 'vehicles.delete',
              user: user,
              disable: true,
              child: IconButton(
                tooltip: 'Устгах',
                onPressed: () => _confirmDelete(context, controller),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ),
          ],
        ],
      ),
      // Parity with the legacy screen (DM-01): staff had an "Оношилгоо"
      // FAB here and the rebuild dropped it. Same class of regression as the
      // customer detail screen's, found by the P3-X1 audit. Like that one it
      // carries no vehicle context — the legacy action also pushed a bare
      // `NewInspectionController` — so it is restored as-is, not improved.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'vehicle_detail_fab',
        onPressed: () => _startInspection(context),
        icon: const Icon(Icons.add),
        label: const Text('Оношилгоо'),
      ),
      body: switch (state) {
        AsyncLoading() => const AppLoading(),
        AsyncError(:final error) => _ErrorBody(
          error: error,
          onRetry: controller.refresh,
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: controller.refresh,
          child: _DetailBody(vehicle: value, controller: controller),
        ),
      },
    );
  }

  // Future<void> _refreshHur(BuildContext context, VehicleDetailController controller) async {
  //   final result = await controller.refreshFromHur();
  //   if (!context.mounted) return;
  //   switch (result) {
  //     case Ok():
  //       messageComplete('ХУР-аас мэдээлэл шинэчлэгдлээ');
  //     case Err(:final error):
  //       // A 502 upstream failure is expected, not a crash — shown as a
  //       // normal error toast, never a dialog implying something broke.
  //       messageError(error.display);
  //   }
  // }

  Future<void> _confirmDelete(
    BuildContext context,
    VehicleDetailController controller,
  ) async {
    final ok = await ConfirmSheet.show(
      context,
      title: 'Машин устгах уу?',
      message: 'Энэ үйлдлийг буцаах боломжгүй.',
      confirmLabel: 'Устгах',
      icon: Icons.delete_forever_rounded,
      isDangerous: true,
    );
    if (!ok) return;
    final result = await controller.delete();
    if (!context.mounted) return;
    switch (result) {
      case Ok():
        messageComplete('Машин устгагдлаа');
        AppNav.back();
      case Err(:final error):
        // `VEHICLE_IN_USE` (409) carries the server's own explanation in
        // `error.message`; `error.display` renders it verbatim rather than a
        // generic "action failed" string.
        await AppNav.dialog<void>(
          AlertDialog(
            title: const Text('Устгах боломжгүй'),
            content: Text(error.display),
            actions: [
              TextButton(
                onPressed: () => AppNav.back(),
                child: const Text('Ойлголоо'),
              ),
            ],
          ),
        );
    }
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});
  final AppError error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.paddingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: context.colors.danger),
            const SizedBox(height: 12),
            Text(error.display, textAlign: TextAlign.center),
            const SizedBox(height: AppDimens.paddingMD),
            OutlinedButton(
              onPressed: () => onRetry(),
              child: const Text('Дахин оролдох'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.vehicle, required this.controller});
  final Vehicle vehicle;
  final VehicleDetailController controller;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingMD,
        AppDimens.paddingMD,
        AppDimens.paddingMD,
        32,
      ),
      children: [
        if (controller.hurError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Banner(
              color: context.colors.warning,
              icon: Icons.cloud_off_rounded,
              text: controller.hurError!.display,
            ),
          ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: context.colors.textPrimary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    ),
                    child: Icon(
                      Icons.directions_car,
                      color: context.colors.textPrimary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNoPlate(v.plate) ? 'Дугааргүй' : (v.plate ?? '—'),
                          style: context.textStyles.h2.copyWith(
                            fontWeight: FontWeight.w800,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          v.displayName.isEmpty ? '—' : v.displayName,
                          style: context.textStyles.body,
                        ),
                      ],
                    ),
                  ),
                  if (v.isPostpaid)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusFull,
                        ),
                      ),
                      child: Text(
                        'Зээлээр',
                        style: context.textStyles.caption.copyWith(
                          color: context.colors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const Divider(height: 20),
              if (v.year != null) _InfoRow(label: 'Он', value: '${v.year}'),
              if (v.vin != null && v.vin!.isNotEmpty)
                _InfoRow(label: 'VIN', value: v.vin!),
              if (v.mileage != null)
                _InfoRow(label: 'Явсан км', value: '${v.mileage} км'),
              if (v.fuelType != null)
                _InfoRow(label: 'Түлш', value: v.fuelType!),
              if (v.wheelPosition != null)
                _InfoRow(label: 'Хүрд', value: v.wheelPosition!),
              if (v.colorName != null)
                _InfoRow(label: 'Өнгө', value: v.colorName!),
              if (v.capacity != null)
                _InfoRow(label: 'Багтаамж', value: '${v.capacity} см³'),
              if (v.purpose != null)
                _InfoRow(label: 'Ангилал', value: v.purpose!),
              if (v.ownerRegnum != null)
                _InfoRow(label: 'Эзний РД', value: v.ownerRegnum!),
              const Divider(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      v.customer?.displayName ?? 'Эзэнгүй',
                      style: context.textStyles.captionMedium,
                    ),
                  ),
                  if (v.ownerIsOrganization) ...[
                    const OrgBadge(),
                    const SizedBox(width: 8),
                  ],
                  if (v.customer?.phone != null)
                    Text(v.customer!.phone!, style: context.textStyles.caption),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _HistorySection(controller: controller, fmt: fmt),
        if (controller.vinHistory != null)
          _VinHistorySection(history: controller.vinHistory!, fmt: fmt),
      ],
    );
  }
}

/// "Ижил арлын дугаартай бүртгэл" — hidden by the controller when the VIN is
/// absent, there is nothing to show, or the load failed.
class _VinHistorySection extends StatelessWidget {
  const _VinHistorySection({required this.history, required this.fmt});
  final VinHistory history;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ижил арлын дугаартай бүртгэл', style: context.textStyles.h3),
          const SizedBox(height: 8),
          for (final r in history.records)
            ListTile(
              key: ValueKey('vin-record-${r.vehicleId}'),
              contentPadding: EdgeInsets.zero,
              title: Text(plateLabel(r.plate)),
              subtitle: Text(
                [
                  [
                    r.make,
                    r.model,
                    if (r.year != null) '${r.year}',
                  ].whereType<String>().join(' '),
                  if (r.ownerName != null) r.ownerName!,
                  '${r.orderCount} захиалга',
                  if (r.lastOrderAt != null)
                    'сүүлд ${fmt.format(r.lastOrderAt!.toLocal())}',
                ].where((e) => e.isNotEmpty).join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => AppNav.push('/vehicles/${r.vehicleId}'),
            ),
          if (history.otherTenantRecords > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Бусад байгууллагад ${history.otherTenantRecords} бүртгэл байна.',
                key: const ValueKey('vin-other-tenants'),
                style: context.textStyles.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.controller, required this.fmt});
  final VehicleDetailController controller;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    final state = controller.historyState;
    return switch (state) {
      AsyncLoading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppDimens.paddingLG),
        child: AppLoading(),
      ),
      AsyncError(:final error) => _Banner(
        color: context.colors.danger,
        icon: Icons.error_outline,
        text: error.display,
      ),
      AsyncData(:final value) => _HistoryList(history: value, fmt: fmt),
    };
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.history, required this.fmt});
  final VehicleHistory history;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    final entries =
        <_HistoryEntry>[
          ...history.orders.map(
            (o) => _HistoryEntry(
              title: o.number != null ? 'Захиалга №${o.number}' : 'Захиалга',
              subtitle: [
                if (o.status != null) o.status!,
                if (o.paymentStatus != null) o.paymentStatus!,
              ].join(' · '),
              at: o.scheduledAt ?? o.createdAt,
              icon: Icons.receipt_long_outlined,
            ),
          ),
          ...history.appointments.map(
            (a) => _HistoryEntry(
              title: a.categoryName ?? 'Цаг захиалга',
              subtitle: a.status ?? '',
              at: a.requestedAt,
              icon: Icons.event_outlined,
            ),
          ),
        ]..sort((a, b) {
          final at = a.at;
          final bt = b.at;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Засварын түүх', style: context.textStyles.h3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.colors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppDimens.radiusFull),
              ),
              child: Text(
                '${entries.length} удаа',
                style: context.textStyles.caption.copyWith(
                  color: context.colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (history.diagnosticReportCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Оношилгоо: ${history.diagnosticReportCount}',
            style: context.textStyles.caption,
          ),
        ],
        const SizedBox(height: 10),
        if (entries.isEmpty)
          const EmptyState(
            message: 'Түүх байхгүй байна',
            icon: Icons.inbox_outlined,
          )
        else
          ...entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: AppDimens.paddingSM),
              child: AppCard(
                padding: const EdgeInsets.all(AppDimens.paddingMD),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: context.colors.accent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                      ),
                      child: Icon(
                        e.icon,
                        color: context.colors.accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title, style: context.textStyles.bodyMedium),
                          if (e.subtitle.isNotEmpty)
                            Text(
                              e.subtitle,
                              style: context.textStyles.caption.copyWith(
                                color: context.colors.accent,
                              ),
                            ),
                          if (e.at != null)
                            Text(
                              fmt.format(e.at!),
                              style: context.textStyles.caption,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryEntry {
  const _HistoryEntry({
    required this.title,
    required this.subtitle,
    required this.at,
    required this.icon,
  });
  final String title;
  final String subtitle;
  final DateTime? at;
  final IconData icon;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: context.textStyles.caption),
          ),
          Expanded(child: Text(value, style: context.textStyles.captionMedium)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimens.paddingSM),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppDimens.paddingSM),
          Expanded(
            child: Text(
              text,
              style: context.textStyles.body.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
