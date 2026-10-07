import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';

import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';
import 'package:carservice_business/features/vehicles/presentation/controllers/vehicle_list_controller.dart';
import 'package:carservice_business/features/vehicles/presentation/widgets/vehicle_filter_sheet.dart';
import 'package:carservice_business/features/vehicles/presentation/widgets/vehicle_list_widgets.dart';

/// Standalone first-class Vehicles list screen — P3-F3.
///
/// **Scope note for the follow-up migration:** this slice does not touch
/// `lib/features/shell/presentation/screens/search_screen.dart` — that file
/// is exclusively owned by the concurrent `P3-F2` (customer list) worker to
/// avoid a collision, and the slice text's "vehicle tab of `search_screen`"
/// line is deliberately not implemented here. The follow-up task that
/// migrates that tab should:
///
/// 1. Construct a [VehicleListController] (optionally sharing one
///    `VehiclesRepository` instance with anything else on that screen) and
///    provide it with `ChangeNotifierProvider`, exactly as this screen does.
/// 2. Embed [VehicleListView] as the tab's body instead of rebuilding list
///    UI — it already owns the search field, pagination, and the
///    empty/error/race-safe states this slice's tests cover. The
///    `assigned`/`postpaid` filters are this screen's app-bar sheet, not
///    part of the view.
/// 3. Call `controller.loadVehicles()` once, on first build (see
///    `_VehicleListScreenState.didChangeDependencies` below) — not in
///    `initState`, so it does not fire before the widget tree can show a
///    loading state.
/// 4. Replace the legacy tab's hand-rolled debounce and any direct
///    `DiagnosticService` call, matching what `P3-F2` does for the customer
///    tab — this slice's controller already owns the only debounce needed.
/// 5. Wire [onTap] to the vehicle detail route once it exists
///    (`P3-F5`/`P3-F6`); until then this screen's own [onTap] is a no-op,
///    deliberately, rather than reaching into the legacy
///    `VehicleDetailScreen` which takes the incompatible legacy
///    `VehicleSummary` model, not this slice's `Vehicle` domain model.
class VehicleListScreen extends StatelessWidget {
  const VehicleListScreen({
    super.key,
    this.repository,
    this.onSelectVehicle,
    this.onCreateVehicle,
    this.user,
  });

  /// Opens the vehicle-create flow and resolves to `true` when a vehicle was
  /// created (the list then reloads). The "+" button is shown only when this
  /// is set AND the user holds `vehicles.create`.
  final Future<bool> Function()? onCreateVehicle;

  /// Injected by tests; production falls back to the signed-in user.
  final User? user;

  /// Tests and previews inject a fake. Production defaults to the remote
  /// adapter inside [VehicleListController].
  final VehiclesRepository? repository;

  /// Left as an explicit hook rather than a hard-coded route push, since no
  /// route for the new vehicle detail screen exists yet (see the class doc).
  final ValueChanged<Vehicle>? onSelectVehicle;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => VehicleListController(repo: repository),
    child: _Body(
      onSelectVehicle: onSelectVehicle,
      onCreateVehicle: onCreateVehicle,
      user: user,
    ),
  );
}

class _Body extends StatefulWidget {
  const _Body({this.onSelectVehicle, this.onCreateVehicle, this.user});
  final ValueChanged<Vehicle>? onSelectVehicle;
  final Future<bool> Function()? onCreateVehicle;
  final User? user;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoad) {
      _didLoad = true;
      final controller = context.read<VehicleListController>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.loadVehicles();
      });
    }
  }

  Future<void> _openFilters(VehicleListController controller) async {
    final result = await VehicleFilterSheet.show(
      context,
      assigned: controller.assigned,
      postpaid: controller.postpaid,
      ownerKind: controller.ownerKind,
    );
    if (result == null || !mounted) return;
    await controller.setFilters(
      assigned: result.assigned,
      postpaid: result.postpaid,
      ownerKind: result.ownerKind,
    );
  }

  Future<void> _create(VehicleListController controller) async {
    final created = await widget.onCreateVehicle!();
    if (created && mounted) await controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VehicleListController>();
    return Scaffold(
      floatingActionButton: widget.onCreateVehicle == null
          ? null
          : PermissionGate(
              permission: 'vehicles.create',
              user: widget.user,
              child: FloatingActionButton(
                heroTag: 'vehicle_create_fab',
                tooltip: 'Машин бүртгэх',
                onPressed: () => _create(controller),
                backgroundColor: context.colors.accent,
                child: Icon(
                  Icons.add,
                  color: CarserviceTheme.of(context).onAccent,
                ),
              ),
            ),
      appBar: AppBar(
        title: const Text('Машинууд'),
        actions: [
          // Selected (filled icon) while any filter is active; tapping always
          // opens the sheet, where filters are changed or cleared.
          IconButton(
            tooltip: 'Шүүлтүүр',
            isSelected: controller.hasActiveFilters,
            icon: const Icon(Icons.filter_alt_outlined),
            selectedIcon: const Icon(Icons.filter_alt),
            onPressed: () => _openFilters(controller),
          ),
        ],
      ),
      body: VehicleListView(
        controller: controller,
        onTap: widget.onSelectVehicle,
      ),
    );
  }
}
